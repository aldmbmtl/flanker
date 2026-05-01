# test_build_system.gd
# Tier 1/2 — unit tests for BuildSystem placement validation and cost logic.
# We test the pure-logic helpers (get_item_cost, can_place_item team-half check,
# spacing computation) without needing a full physics world.
#
# NOTE: BuildSystem is NOT an autoload — it lives as a child of Main.tscn.
# We instantiate it directly here using its script path.
extends GutTest

const BuildSystemScript := preload("res://scripts/BuildSystem.gd")

var bs: Node  # local BuildSystem instance

# ─── helpers ──────────────────────────────────────────────────────────────────

# Place a fake tower node in the "towers" group at the given position so the
# spacing check in can_place_item() has something to collide against.
class FakeTower extends Node3D:
	var tower_type: String = "cannon"

func _add_fake_tower(pos: Vector3, tower_type: String = "cannon") -> Node3D:
	var n := FakeTower.new()
	n.tower_type = tower_type
	add_child_autofree(n)
	n.global_position = pos  # set AFTER add_child so the node is in the tree
	n.add_to_group("towers")
	return n

func _add_fake_drop(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child_autofree(n)
	n.global_position = pos  # set AFTER add_child
	n.add_to_group("supporter_drops")
	return n

func before_each() -> void:
	bs = Node.new()
	bs.set_script(BuildSystemScript)
	add_child_autofree(bs)
	# _ready() runs automatically; spacing is computed there.
	TeamData.sync_from_server(200, 200)

# ── get_item_cost ─────────────────────────────────────────────────────────────

func test_cost_cannon() -> void:
	assert_eq(bs.get_item_cost("cannon", ""), 25)

func test_cost_mortar() -> void:
	assert_eq(bs.get_item_cost("mortar", ""), 35)

func test_cost_machinegun() -> void:
	assert_eq(bs.get_item_cost("machinegun", ""), 40)

func test_cost_launcher_missile() -> void:
	assert_eq(bs.get_item_cost("launcher_missile", ""), 50)

func test_cost_healthpack() -> void:
	assert_eq(bs.get_item_cost("healthpack", ""), 15)

func test_cost_healstation() -> void:
	assert_eq(bs.get_item_cost("healstation", ""), 25)

func test_cost_weapon_pistol() -> void:
	assert_eq(bs.get_item_cost("weapon", "pistol"), 10)

func test_cost_weapon_rifle() -> void:
	assert_eq(bs.get_item_cost("weapon", "rifle"), 20)

func test_cost_weapon_heavy() -> void:
	assert_eq(bs.get_item_cost("weapon", "heavy"), 30)

func test_cost_weapon_rocket_launcher() -> void:
	assert_eq(bs.get_item_cost("weapon", "rocket_launcher"), 60)

func test_cost_unknown_type_returns_zero() -> void:
	assert_eq(bs.get_item_cost("does_not_exist", ""), 0)

func test_cost_unknown_weapon_subtype_returns_zero() -> void:
	assert_eq(bs.get_item_cost("weapon", "flamethrower"), 0)

# ── get_tower_cost (legacy shim) ──────────────────────────────────────────────

func test_get_tower_cost_equals_cannon_cost() -> void:
	assert_eq(bs.get_tower_cost(), bs.get_item_cost("cannon", ""))

# ── spacing computation (_ready populates this) ───────────────────────────────

func test_spacing_computed_for_cannon() -> void:
	var def: Dictionary = bs.PLACEABLE_DEFS["cannon"]
	assert_true(def.has("spacing"), "cannon def should have 'spacing' key after _ready()")
	# cannon attack_range=30; spacing = 30*0.75 = 22.5
	assert_eq(def["spacing"], 22.5)

func test_spacing_computed_for_mortar() -> void:
	var def: Dictionary = bs.PLACEABLE_DEFS["mortar"]
	# mortar attack_range=50; spacing = 50*0.75 = 37.5
	assert_eq(def["spacing"], 37.5)

# ── can_place_item — team half guard ──────────────────────────────────────────
# z > 0 is team 0's half; z < 0 is team 1's half.

func test_team0_cannot_place_on_negative_z() -> void:
	var result: bool = bs.can_place_item(Vector3(0.0, 5.0, -10.0), 0, "cannon")
	assert_false(result, "Team 0 must not place in team 1's half (z < 0)")

func test_team1_cannot_place_on_positive_z() -> void:
	var result: bool = bs.can_place_item(Vector3(0.0, 5.0, 10.0), 1, "cannon")
	assert_false(result, "Team 1 must not place in team 0's half (z > 0)")

func test_unknown_item_type_always_returns_false() -> void:
	assert_false(bs.can_place_item(Vector3(0, 5, 10), 0, "nonexistent"))

# ── spacing check — nodes in tree ─────────────────────────────────────────────

func test_spacing_blocks_placement_too_close() -> void:
	_add_fake_tower(Vector3(0.0, 0.0, 50.0), "cannon")
	# slow spacing=13.5; cannon spacing=22.5; effective=22.5; distance=5 < 22.5 → blocked
	var result: bool = bs.can_place_item(Vector3(0.0, 0.0, 55.0), 0, "slow")
	assert_false(result, "Placement within existing tower's spacing should be rejected")

func test_spacing_allows_placement_far_enough() -> void:
	# x=40 z=40 is >10 units from all lane curves and on team 0's half.
	# Place fake cannon at same x but z=10; test pos is 30 units away > cannon spacing 22.5
	_add_fake_tower(Vector3(40.0, 0.0, 10.0), "cannon")
	var result: bool = bs.can_place_item(Vector3(40.0, 0.0, 40.0), 0, "slow")
	assert_true(result, "Placement outside all tower spacings should be allowed (headless)")

func test_drop_spacing_check_uses_supporter_drops_group() -> void:
	_add_fake_drop(Vector3(0.0, 0.0, 10.0))
	var result: bool = bs.can_place_item(Vector3(0.0, 0.0, 12.0), 0, "healthpack")
	assert_false(result, "Healthpack within existing drop's spacing (5 units) should be rejected")

# ── place_item — spend_points guard ──────────────────────────────────────────

func test_place_item_returns_empty_string_when_insufficient_funds() -> void:
	TeamData.sync_from_server(5, 5)  # less than cannon cost (25)
	var node_name: String = bs.place_item(Vector3(0.0, 5.0, 50.0), 0, "cannon", "")
	assert_eq(node_name, "", "place_item should fail and return '' when team has insufficient funds")

func test_place_item_returns_empty_string_on_bad_type() -> void:
	var node_name: String = bs.place_item(Vector3(0.0, 5.0, 50.0), 0, "bogus", "")
	assert_eq(node_name, "")

# ── PLACEABLE_DEFS integrity ──────────────────────────────────────────────────

func test_all_defs_have_scene_path() -> void:
	for key in bs.PLACEABLE_DEFS:
		var def: Dictionary = bs.PLACEABLE_DEFS[key]
		assert_true(def.has("scene") and def["scene"] != "",
			"PLACEABLE_DEFS[%s] missing scene path" % key)

func test_all_defs_have_is_tower_flag() -> void:
	for key in bs.PLACEABLE_DEFS:
		var def: Dictionary = bs.PLACEABLE_DEFS[key]
		assert_true(def.has("is_tower"),
			"PLACEABLE_DEFS[%s] missing is_tower flag" % key)

func test_all_tower_defs_have_spacing_after_ready() -> void:
	for key in bs.PLACEABLE_DEFS:
		var def: Dictionary = bs.PLACEABLE_DEFS[key]
		if def.get("is_tower", false):
			assert_true(def.has("spacing"),
				"Tower PLACEABLE_DEFS[%s] missing spacing (not computed in _ready?)" % key)

# ── spawn_item_local — attack_range injection from PLACEABLE_DEFS ─────────────
#
# spawn_item_local calls get_tree().root.get_node("Main") to add the tower node.
# We temporarily reparent a fake Main node under root so the call resolves.

func test_spawn_item_local_pushes_attack_range_from_defs() -> void:
	# Build a fake Main node at the tree root so spawn_item_local can find it.
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)

	TeamData.sync_from_server(200, 200)

	# Spawn a cannon — PLACEABLE_DEFS says attack_range = 30.0,
	# the .tscn previously had 7.5 (now fixed to 30.0 too).
	# Either way, spawn_item_local must override the node value with 30.0.
	var node_name: String = bs.spawn_item_local(Vector3(0.0, 5.0, 55.0), 0, "cannon", "")
	assert_ne(node_name, "", "spawn_item_local should succeed and return a node name")

	var spawned: Node = fake_main.get_node_or_null(node_name)
	assert_not_null(spawned, "Spawned node should be a child of fake Main")

	if spawned != null:
		var actual_range = spawned.get("attack_range")
		assert_almost_eq(float(actual_range), 30.0, 0.001,
			"attack_range on spawned cannon must equal PLACEABLE_DEFS value (30.0)")

	# Cleanup — remove fake Main so it doesn't leak into other tests.
	fake_main.queue_free()
	await get_tree().process_frame

func test_spawn_item_local_pushes_correct_range_for_mortar() -> void:
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)

	TeamData.sync_from_server(200, 200)

	var node_name: String = bs.spawn_item_local(Vector3(0.0, 5.0, 55.0), 0, "mortar", "")
	assert_ne(node_name, "", "mortar spawn should succeed")

	var spawned: Node = fake_main.get_node_or_null(node_name)
	if spawned != null:
		var actual_range = spawned.get("attack_range")
		assert_almost_eq(float(actual_range), 50.0, 0.001,
			"attack_range on spawned mortar must equal PLACEABLE_DEFS value (50.0)")

	fake_main.queue_free()
	await get_tree().process_frame

func test_attack_range_defs_match_documented_values() -> void:
	# Regression guard: if PLACEABLE_DEFS attack_range values drift from the
	# documented constants in AGENTS.md, this test catches it immediately.
	assert_almost_eq(float(bs.PLACEABLE_DEFS["cannon"]["attack_range"]),   30.0, 0.001)
	assert_almost_eq(float(bs.PLACEABLE_DEFS["mortar"]["attack_range"]),   50.0, 0.001)
	assert_almost_eq(float(bs.PLACEABLE_DEFS["machinegun"]["attack_range"]), 22.0, 0.001)
	assert_almost_eq(float(bs.PLACEABLE_DEFS["slow"]["attack_range"]),     18.0, 0.001)
	assert_almost_eq(float(bs.PLACEABLE_DEFS["launcher_missile"]["attack_range"]), 0.0, 0.001)

# ── Tree clearing on spawn ─────────────────────────────────────────────────────
#
# spawn_item_local must call tree_placer.clear_trees_at with radius 8.0 so that
# both collision trunks and visual meshes are removed in the area under the tower.

func test_spawn_item_local_clears_trees_with_radius_8() -> void:
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)

	# Attach a StubTreePlacer under World/TreePlacer so spawn_item_local finds it.
	var world_node := Node.new()
	world_node.name = "World"
	fake_main.add_child(world_node)
	var stub_tp := StubTreePlacer.new()
	stub_tp.name = "TreePlacer"
	world_node.add_child(stub_tp)

	TeamData.sync_from_server(200, 200)
	var place_pos := Vector3(0.0, 5.0, 55.0)
	var _node_name: String = bs.spawn_item_local(place_pos, 0, "cannon", "")

	assert_eq(stub_tp.clear_calls.size(), 1,
		"spawn_item_local must call clear_trees_at exactly once")
	if stub_tp.clear_calls.size() > 0:
		var call: Dictionary = stub_tp.clear_calls[0]
		assert_almost_eq(float(call["radius"]), 8.0, 0.001,
			"clear_trees_at must be called with radius 8.0")

	fake_main.queue_free()
	await get_tree().process_frame

func test_spawn_item_local_clears_trees_at_correct_position() -> void:
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)

	var world_node := Node.new()
	world_node.name = "World"
	fake_main.add_child(world_node)
	var stub_tp := StubTreePlacer.new()
	stub_tp.name = "TreePlacer"
	world_node.add_child(stub_tp)

	TeamData.sync_from_server(200, 200)
	var place_pos := Vector3(10.0, 5.0, 55.0)
	var _node_name: String = bs.spawn_item_local(place_pos, 0, "cannon", "")

	if stub_tp.clear_calls.size() > 0:
		var call_pos: Vector3 = stub_tp.clear_calls[0]["pos"]
		assert_almost_eq(call_pos.x, place_pos.x, 0.001,
			"clear_trees_at pos.x must match placement x")
		assert_almost_eq(call_pos.z, place_pos.z, 0.001,
			"clear_trees_at pos.z must match placement z")

	fake_main.queue_free()
	await get_tree().process_frame

# ── Supporter attribute: tower HP bonus ───────────────────────────────────────

func test_apply_tower_hp_bonuses_uses_placer_peer_bonus() -> void:
	LevelSystem.register_peer(42)
	SkillTree.register_peer(42, "Supporter")
	LevelSystem.award_xp(42, 70)
	LevelSystem.spend_point_local(42, "tower_hp")  # +5% bonus

	var s := GDScript.new()
	s.source_code = "extends Node\nvar _health: float = 500.0\nvar max_health: float = 500.0\nvar tower_type: String = \"cannon\"\n"
	s.reload()
	var tower_node := Node.new()
	tower_node.set_script(s)
	add_child_autofree(tower_node)

	bs._apply_tower_hp_bonuses(tower_node, "cannon", 42)
	var new_hp: float = tower_node.get("_health")
	var expected: float = 500.0 * (1.0 + LevelSystem.TOWER_HP_PER_POINT)
	assert_almost_eq(new_hp, expected, 0.01,
		"Tower HP should reflect placer's tower_hp attr bonus")

	LevelSystem.clear_peer(42)
	SkillTree.clear_peer(42)

# ── Supporter attribute: fire rate bonus ──────────────────────────────────────

func test_apply_tower_fire_rate_bonus_reduces_attack_interval() -> void:
	LevelSystem.register_peer(43)
	SkillTree.register_peer(43, "Supporter")
	LevelSystem.award_xp(43, 70)
	LevelSystem.spend_point_local(43, "tower_fire_rate")  # -5% interval

	var s := GDScript.new()
	s.source_code = "extends Node\nvar attack_interval: float = 1.0\n"
	s.reload()
	var tower_node := Node.new()
	tower_node.set_script(s)
	add_child_autofree(tower_node)

	bs._apply_tower_fire_rate_bonus(tower_node, 43)
	var new_interval: float = tower_node.get("attack_interval")
	var expected: float = 1.0 * (1.0 - LevelSystem.TOWER_FIRE_RATE_PER_POINT)
	assert_almost_eq(new_interval, expected, 0.0001,
		"attack_interval should be reduced by tower_fire_rate mult")

	LevelSystem.clear_peer(43)
	SkillTree.clear_peer(43)

# ── Supporter attribute: placement range reduction ────────────────────────────

func test_can_place_item_spacing_reduced_with_placement_range_attr() -> void:
	# Remove any stale tower nodes from prior tests (queue_free is deferred so
	# they may still be in the group when this test runs).
	for n in get_tree().get_nodes_in_group("towers"):
		n.remove_from_group("towers")

	SkillTree.clear_peer(44)
	LevelSystem.register_peer(44)
	SkillTree.register_peer(44, "Supporter")
	LevelSystem.award_xp(44, 999999)
	for _i in range(6):
		LevelSystem.spend_point_local(44, "placement_range")

	# cannon spacing = 30 * 0.75 = 22.5; 60% reduction: effective = max(22.5*0.4, 3.0) = 9.0
	# base tower at (40, 0, 70), test pos at (40, 0, 85) — 15 units away.
	# Without attr: 15 < 22.5 → blocked.
	# With max attr (effective 9.0): 15 > 9.0 → allowed.
	_add_fake_tower(Vector3(40.0, 0.0, 70.0), "cannon")
	var result_no_attr: bool = bs.can_place_item(Vector3(40.0, 0.0, 85.0), 0, "cannon", -1)
	var result_with_attr: bool = bs.can_place_item(Vector3(40.0, 0.0, 85.0), 0, "cannon", 44)
	assert_false(result_no_attr, "Without placement_range attr, 15-unit gap should be blocked")
	assert_true(result_with_attr, "With max placement_range attr, 15-unit gap should be allowed")

	LevelSystem.clear_peer(44)
	SkillTree.clear_peer(44)

# ── Retroactive fire rate: _on_attribute_spent ────────────────────────────────

func test_retroactive_fire_rate_update_on_attribute_spent() -> void:
	LevelSystem.register_peer(45)
	SkillTree.register_peer(45, "Supporter")

	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar attack_interval: float = 1.0\nvar placer_peer_id: int = 45\nvar tower_type: String = \"cannon\"\n"
	s.reload()
	var tower_node := Node3D.new()
	tower_node.set_script(s)
	add_child_autofree(tower_node)
	tower_node.add_to_group("towers")

	# Spend 1 point — triggers attribute_spent → _on_attribute_spent in BuildSystem
	LevelSystem.award_xp(45, 70)
	LevelSystem.spend_point_local(45, "tower_fire_rate")

	var expected: float = 1.0 * (1.0 - LevelSystem.TOWER_FIRE_RATE_PER_POINT)
	var actual: float = tower_node.get("attack_interval")
	assert_almost_eq(actual, expected, 0.0001,
		"Existing tower's attack_interval must be updated retroactively on attribute spend")

	LevelSystem.clear_peer(45)
	SkillTree.clear_peer(45)
