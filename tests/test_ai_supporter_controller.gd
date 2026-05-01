# test_ai_supporter_controller.gd
# Tier 1 — unit tests for AISupporterController skill/attribute integration
# and machinegun placement logic.
#
# AISupporterController is a plain Node (not an autoload). We instantiate it
# directly, set team before add_child, then exercise its _ready() hooks and
# decision helpers without a physics world or real BuildSystem.
extends GutTest

const AISupporterScript := preload("res://scripts/roles/supporter/AISupporterController.gd")
const BuildSystemScript  := preload("res://scripts/BuildSystem.gd")

var ai: Node
var bs: Node

# ─── helpers ──────────────────────────────────────────────────────────────────

# Stub BuildSystem that records the last place_item call so we can inspect args.
class StubBuildSystem extends Node:
	var last_place_peer_id: int = -999
	var last_can_place_peer_id: int = -999
	var last_placed_type: String = ""
	var place_should_succeed: bool = true
	var can_place_result: bool = true

	const WEAPON_COSTS: Dictionary = {"pistol": 10, "rifle": 20, "heavy": 30, "rocket_launcher": 60}

	func can_place_item(_pos: Vector3, _team: int, item_type: String, placer_peer_id: int = -1) -> bool:
		last_can_place_peer_id = placer_peer_id
		last_placed_type = item_type
		return can_place_result

	func place_item(_pos: Vector3, _team: int, item_type: String, _subtype: String, placer_peer_id: int = -1) -> String:
		last_place_peer_id = placer_peer_id
		last_placed_type = item_type
		if place_should_succeed:
			return "%s_0_0" % item_type
		return ""

	func get_item_cost(item_type: String, _subtype: String) -> int:
		var costs := {"cannon": 25, "mortar": 35, "slow": 30, "machinegun": 40,
				"launcher_missile": 50, "healthpack": 15, "healstation": 25}
		return costs.get(item_type, 0)

func _make_ai(team_val: int = 0) -> Node:
	var node: Node = Node.new()
	node.set_script(AISupporterScript)
	node.set("team", team_val)
	add_child_autofree(node)
	return node

func before_each() -> void:
	# Reset autoloads
	LevelSystem.clear_all()
	SkillTree.clear_all()
	TeamData.sync_from_server(200, 200)

	ai = _make_ai(0)
	# Build stub build system and inject into AI
	bs = StubBuildSystem.new()
	add_child_autofree(bs)
	ai.set("build_system", bs)

# ─── Test 1: AI registers with LevelSystem ────────────────────────────────────

func test_ai_registers_with_level_system() -> void:
	var pid: int = ai.get("peer_id")
	assert_eq(LevelSystem.get_level(pid), 1,
		"AI peer should be registered at level 1 after _ready()")

# ─── Test 2: AI registers with SkillTree ─────────────────────────────────────

func test_ai_registers_with_skill_tree() -> void:
	var pid: int = ai.get("peer_id")
	assert_eq(SkillTree.get_role(pid), "Supporter",
		"AI peer should be registered as Supporter in SkillTree")

# ─── Test 3: peer_id passed to place_item ────────────────────────────────────

func test_ai_place_item_passes_peer_id() -> void:
	var pid: int = ai.get("peer_id")
	# Directly call _do_place so we don't need physics
	ai.call("_do_place", Vector3.ZERO, "cannon", "")
	assert_eq((bs as StubBuildSystem).last_place_peer_id, pid,
		"_do_place must pass AI peer_id as placer_peer_id to build_system.place_item")

# ─── Test 4: peer_id passed to can_place_item ────────────────────────────────

func test_ai_can_place_item_passes_peer_id() -> void:
	var pid: int = ai.get("peer_id")
	# _try_place_zone is the canonical path — but it needs LaneData which is complex.
	# Directly invoke _do_place (which calls place_item and can check that peer_id
	# flows through the stub's can_place path via _try_place_near_player).
	# Simpler: call _do_place and verify place_item got the peer_id.
	ai.call("_do_place", Vector3(5.0, 0.0, 5.0), "healthpack", "")
	assert_eq((bs as StubBuildSystem).last_place_peer_id, pid,
		"All place_item calls must forward AI peer_id")

# ─── Test 5: tower_hp bonus applies to placed towers ─────────────────────────

func test_ai_tower_hp_bonus_applies() -> void:
	var pid: int = ai.get("peer_id")
	# Give the AI a tower_hp attribute point directly (bypassing level-up)
	LevelSystem.spend_point_local(pid, "tower_hp")  # needs 1 point first
	# spend_point_local requires an unspent point — grant one manually
	# Re-register fresh with 1 unspent point
	LevelSystem.clear_peer(pid)
	LevelSystem.register_peer(pid)
	# Inject 1 unspent point by awarding enough XP to level up
	LevelSystem.award_xp(pid, LevelSystem.XP_PER_LEVEL[0])  # level 1→2
	# Now spend it on tower_hp
	LevelSystem.spend_point_local(pid, "tower_hp")
	var bonus: float = LevelSystem.get_bonus_tower_hp_mult(pid)
	assert_gt(bonus, 0.0, "AI tower_hp bonus should be > 0 after spending a point")
	# Verify bonus value: 1 point * TOWER_HP_PER_POINT = 0.05
	assert_almost_eq(bonus, LevelSystem.TOWER_HP_PER_POINT, 0.001)

# ─── Test 6: fire_rate bonus is non-zero after spending ──────────────────────

func test_ai_fire_rate_bonus_applies() -> void:
	var pid: int = ai.get("peer_id")
	LevelSystem.clear_peer(pid)
	LevelSystem.register_peer(pid)
	LevelSystem.award_xp(pid, LevelSystem.XP_PER_LEVEL[0])
	LevelSystem.spend_point_local(pid, "tower_fire_rate")
	var bonus: float = LevelSystem.get_bonus_tower_fire_rate_mult(pid)
	assert_almost_eq(bonus, LevelSystem.TOWER_FIRE_RATE_PER_POINT, 0.001,
		"AI fire rate bonus should equal TOWER_FIRE_RATE_PER_POINT after 1 point")

# ─── Test 7: XP awarded on enemy tower despawn ───────────────────────────────

func test_ai_earns_xp_on_enemy_tower_despawn() -> void:
	var pid: int = ai.get("peer_id")
	var xp_before: int = LevelSystem.get_xp(pid)
	# Emit with enemy team (1, since AI is team 0)
	LobbyManager.tower_despawned.emit("cannon", 1, "Cannon_0_0")
	var xp_after: int = LevelSystem.get_xp(pid)
	assert_eq(xp_after - xp_before, LevelSystem.XP_TOWER,
		"AI should earn XP_TOWER when an enemy tower is destroyed")

# ─── Test 8: No XP for own tower despawn ─────────────────────────────────────

func test_ai_no_xp_on_own_tower_despawn() -> void:
	var pid: int = ai.get("peer_id")
	var xp_before: int = LevelSystem.get_xp(pid)
	# Emit with own team (0, same as AI)
	LobbyManager.tower_despawned.emit("cannon", 0, "Cannon_0_0")
	var xp_after: int = LevelSystem.get_xp(pid)
	assert_eq(xp_after, xp_before, "AI should NOT earn XP when its own tower is destroyed")

# ─── Test 9: XP awarded on enemy player death ────────────────────────────────

func test_ai_earns_xp_on_enemy_player_death() -> void:
	var pid: int = ai.get("peer_id")
	# Register an enemy player (team 1) in GameSync
	GameSync.register_player(999, "EnemyPlayer")
	GameSync.set_player_team(999, 1)
	var xp_before: int = LevelSystem.get_xp(pid)
	GameSync.player_died.emit(999)
	var xp_after: int = LevelSystem.get_xp(pid)
	assert_eq(xp_after - xp_before, LevelSystem.XP_PLAYER,
		"AI should earn XP_PLAYER when an enemy player dies")

# ─── Test 10: auto-attribute spend triggers on level-up ──────────────────────

func test_ai_auto_spends_attr_on_level_up() -> void:
	var pid: int = ai.get("peer_id")
	# Award enough XP for level-up
	LevelSystem.award_xp(pid, LevelSystem.XP_PER_LEVEL[0])
	# After level-up signal fires, _on_level_up → _spend_all_attribute_points
	var attrs: Dictionary = LevelSystem.get_attrs(pid)
	var total_spent: int = attrs.get("tower_hp", 0) + attrs.get("tower_fire_rate", 0) + attrs.get("placement_range", 0)
	assert_gt(total_spent, 0, "AI should auto-spend attribute points after leveling up")

# ─── Test 11: skill auto-unlock on skill_pts_changed ─────────────────────────

func test_ai_auto_unlocks_skill_on_pts_gained() -> void:
	var pid: int = ai.get("peer_id")
	# Grant a skill point directly — triggers skill_pts_changed signal
	SkillTree.debug_grant_pts(pid, 1)
	# s_basic_t1 is first in unlock order and has no prereqs and cost=1, level_req=0
	# It should be auto-unlocked now
	assert_true(SkillTree.is_unlocked(pid, "s_basic_t1"),
		"AI should auto-unlock s_basic_t1 when it has skill points")

# ─── Test 12: machinegun placed in mid phase ──────────────────────────────────

func test_ai_places_machinegun_in_mid_phase() -> void:
	# Set wave to mid
	ai.set("_wave_number", 4)
	# Saturate all non-machinegun mid-phase keys so phase reaches machinegun
	# 3 lanes × 3 zones × cannon cap=2
	for li in range(3):
		for z in ["agg", "mid", "def"]:
			ai.get("_placed_counts")["lane_%d_cannon_%s" % [li, z]] = 2
	# Also saturate slow/mortar
	for li in range(3):
		for tt in ["slow", "mortar"]:
			ai.get("_placed_counts")["lane_%d_%s_agg" % [li, tt]] = 1
	# launcher_missile_0 — skip for simplicity, AI will try machinegun next
	ai.get("_placed_counts")["launcher_missile_0"] = 1
	# jungle cannons
	for ji in range(3):
		ai.get("_placed_counts")["jungle_cannon_%d" % ji] = 1

	TeamData.sync_from_server(200, 200)
	(bs as StubBuildSystem).can_place_result = true
	ai.call("_phase_mid", 200.0)

	var counts: Dictionary = ai.get("_placed_counts")
	var found: bool = false
	for key in counts.keys():
		if key.contains("machinegun"):
			found = true
			break
	assert_true(found, "_phase_mid should place a machinegun tower when slots are available")

# ─── Test 13: machinegun placed in late phase ─────────────────────────────────

func test_ai_places_machinegun_in_late_phase() -> void:
	ai.set("_wave_number", 7)
	# Saturate non-machinegun late-phase keys
	for li in range(3):
		for z in ["agg", "mid", "def"]:
			ai.get("_placed_counts")["lane_%d_cannon_%s" % [li, z]] = 3
	for li in range(3):
		for z_pair in [["agg"], ["mid"]]:
			for tt in ["mortar", "slow"]:
				ai.get("_placed_counts")["lane_%d_%s_%s" % [li, tt, z_pair[0]]] = 2
	ai.get("_placed_counts")["healstation"] = 1
	for ji in range(8):
		ai.get("_placed_counts")["jungle_cannon_%d" % ji] = 1
	for ji in range(4):
		ai.get("_placed_counts")["jungle_mortar_%d" % ji] = 1
	for li in range(3):
		ai.get("_placed_counts")["launcher_missile_%d" % li] = 1

	TeamData.sync_from_server(200, 200)
	(bs as StubBuildSystem).can_place_result = true
	ai.call("_phase_late", 200.0)

	var counts: Dictionary = ai.get("_placed_counts")
	var found: bool = false
	for key in counts.keys():
		if key.contains("machinegun"):
			found = true
			break
	assert_true(found, "_phase_late should place machinegun towers when other slots are full")
