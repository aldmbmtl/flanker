extends Node

# ── Placeable definitions ─────────────────────────────────────────────────────
# Each entry: { cost, scene, attack_range, is_tower, lane_setback, [spacing], [attack_interval_base] }
# Towers: spacing is computed in _ready() from attack_range (see SPACING_* constants).
#   Attacking towers: spacing = attack_range * SPACING_FACTOR (75% of range)
#   Passive towers (attack_range 0): spacing = SPACING_PASSIVE
# Non-tower drops: spacing is set explicitly here and left unchanged.
# "weapon" cost is 0 — actual cost comes from WEAPON_COSTS keyed by subtype.
# attack_interval_base: mirrors the .tscn export; used for retroactive fire-rate recalculation.
var PLACEABLE_DEFS := {
	"cannon":           { "cost": 25, "scene": "res://scenes/towers/Tower.tscn",           "attack_range": 30.0, "attack_interval_base": 1.0,  "is_tower": true,  "lane_setback": true  },
	"mortar":           { "cost": 35, "scene": "res://scenes/towers/MortarTower.tscn",     "attack_range": 50.0, "attack_interval_base": 3.5,  "is_tower": true,  "lane_setback": true  },
	"slow":             { "cost": 30, "scene": "res://scenes/towers/SlowTower.tscn",       "attack_range": 18.0, "attack_interval_base": 1.0,  "is_tower": true,  "lane_setback": true  },
	"machinegun":       { "cost": 40, "scene": "res://scenes/towers/MachineGunTower.tscn", "attack_range": 22.0, "attack_interval_base": 0.5,  "is_tower": true,  "lane_setback": true  },
	"weapon":           { "cost":  0, "scene": "res://scenes/WeaponPickup.tscn",           "spacing":  5.0,      "is_tower": false, "lane_setback": false },
	"healthpack":       { "cost": 15, "scene": "res://scenes/HealthPackPickup.tscn",       "spacing":  5.0,      "is_tower": false, "lane_setback": false },
	"healstation":      { "cost": 25, "scene": "res://scenes/HealStation.tscn",            "spacing": 10.0,      "is_tower": false, "lane_setback": false },
	# ── Launcher towers — one entry per type in LauncherDefs ─────────────────
	"launcher_missile": { "cost": 50, "scene": "res://scenes/towers/LauncherTower.tscn",  "attack_range":  0.0, "attack_interval_base": 0.0,  "is_tower": true,  "lane_setback": true, "is_launcher": true, "launcher_type": "launcher_missile" },
}

const WEAPON_COSTS := { "pistol": 10, "rifle": 20, "heavy": 30, "rocket_launcher": 60 }

# Legacy constants kept for any external references
const TOWER_SCENE    := "res://scenes/towers/Tower.tscn"
const TOWER_COST     := 25
const LANE_SETBACK   := 8.0
const SLOPE_THRESHOLD := 0.85
const MIN_TOWER_SPACING := 20.0

# Spacing formula constants for attacking towers
const SPACING_FACTOR  := 0.75  # multiplied by attack_range (75% of range)
const SPACING_PASSIVE := 3.0   # spacing for passive towers (attack_range == 0)

var _loaded_scenes: Dictionary = {}

func _ready() -> void:
	# Compute spacing for all tower entries from their attack_range
	for key in PLACEABLE_DEFS:
		var def: Dictionary = PLACEABLE_DEFS[key]
		if not def.get("is_tower", false):
			continue
		var r: float = def.get("attack_range", 0.0)
		def["spacing"] = SPACING_PASSIVE if r == 0.0 else r * SPACING_FACTOR
	for key in PLACEABLE_DEFS:
		var path: String = PLACEABLE_DEFS[key]["scene"]
		_loaded_scenes[key] = load(path)
	# Retroactive fire-rate update when a Supporter spends into tower_fire_rate
	LevelSystem.attribute_spent.connect(_on_attribute_spent)

# ── Placement validation ──────────────────────────────────────────────────────

func get_item_cost(item_type: String, subtype: String) -> int:
	var base: int
	if item_type == "weapon":
		base = WEAPON_COSTS.get(subtype, 0)
		# f_explosive: rocket launcher costs 30 less for an unlocked Fighter
		if subtype == "rocket_launcher":
			var discount: int = _get_skill_build_discount(0)  # team 0 as fallback; actual discount checked per-placer
			base = max(0, base - 30) if _any_team_has_explosive() else base
	else:
		var def: Dictionary = PLACEABLE_DEFS.get(item_type, {})
		base = def.get("cost", 0)
	return base

func _any_team_has_explosive() -> bool:
	# Check if any registered peer has f_explosive unlocked
	for peer_id in SkillTree.get_all_peers():
		if SkillTree.is_unlocked(peer_id, "f_explosive"):
			return true
	return false

func _get_skill_build_discount(team: int) -> int:
	# Sum build_discount passive from all peers on that team
	var total: int = 0
	for peer_id in SkillTree.get_all_peers():
		if SkillTree.get_role(peer_id) == "supporter":
			total += int(SkillTree.get_passive_bonus(peer_id, "build_discount"))
	return total

func can_place_item(world_pos: Vector3, team: int, item_type: String, placer_peer_id: int = -1) -> bool:
	var def: Dictionary = PLACEABLE_DEFS.get(item_type, {})
	if def.is_empty():
		return false

	# Must be on own team's half
	if team == 0 and world_pos.z < 0.0:
		return false
	if team == 1 and world_pos.z > 0.0:
		return false

	# Lane setback (towers only)
	if def.get("lane_setback", false):
		var p := Vector2(world_pos.x, world_pos.z)
		for lane_i in range(3):
			var pts: Array = LaneData.get_lane_points(lane_i)
			if LaneData.dist_to_polyline(p, pts) < LANE_SETBACK:
				return false

	# Slope check
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d().direct_space_state
	if space != null:
		var from := Vector3(world_pos.x, world_pos.y + 10.0, world_pos.z)
		var to   := Vector3(world_pos.x, world_pos.y - 10.0, world_pos.z)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var result: Dictionary = space.intersect_ray(query)
		if not result.is_empty():
			if result.normal.dot(Vector3.UP) < SLOPE_THRESHOLD:
				return false

	# Spacing — towers check "towers" group, drops check "supporter_drops" group
	var spacing: float = def.get("spacing", 5.0)
	var range_mult: float = 1.0 - LevelSystem.get_bonus_placement_range_mult(placer_peer_id)
	var group: String = "towers" if def.get("is_tower", false) else "supporter_drops"
	for node in get_tree().get_nodes_in_group(group):
		var existing_def: Dictionary = PLACEABLE_DEFS.get(node.get("tower_type") if node.get("tower_type") != null else "", {})
		var existing_spacing: float = existing_def.get("spacing", 5.0)
		var effective: float = maxf(spacing, existing_spacing) * range_mult
		# Floor at SPACING_PASSIVE so towers can never fully overlap
		effective = maxf(effective, SPACING_PASSIVE)
		var dist: float = world_pos.distance_to(node.global_position)
		if dist < effective:
			return false

	return true

# Legacy shim
func can_place(world_pos: Vector3, team: int) -> bool:
	return can_place_item(world_pos, team, "cannon")

# ── Placement execution ───────────────────────────────────────────────────────

func place_item(world_pos: Vector3, team: int, item_type: String, subtype: String, placer_peer_id: int = -1) -> String:
	world_pos.x = snappedf(world_pos.x, 2.0)
	world_pos.z = snappedf(world_pos.z, 2.0)

	if not can_place_item(world_pos, team, item_type, placer_peer_id):
		return ""

	var cost: int = get_item_cost(item_type, subtype)
	if not TeamData.spend_points(team, cost):
		return ""

	return spawn_item_local(world_pos, team, item_type, subtype, "", placer_peer_id)

# Legacy shim
func place_tower(world_pos: Vector3, team: int) -> bool:
	return place_item(world_pos, team, "cannon", "") != ""

func spawn_item_local(world_pos: Vector3, team: int, item_type: String, subtype: String, forced_name: String = "", placer_peer_id: int = -1) -> String:
	var scene: PackedScene = _loaded_scenes.get(item_type)
	if scene == null:
		scene = load(PLACEABLE_DEFS[item_type]["scene"])
		if scene == null:
			push_error("BuildSystem: scene not found for type=" + item_type)
			return ""

	var node: Node = scene.instantiate()

	# Weapon pickups must have weapon_data set BEFORE add_child so _ready() sees it
	if item_type == "weapon":
		var preset_paths := {
			"pistol":           "res://assets/weapons/weapon_pistol.tres",
			"rifle":            "res://assets/weapons/weapon_rifle.tres",
			"heavy":            "res://assets/weapons/weapon_heavy.tres",
			"rocket_launcher":  "res://assets/weapons/weapon_rocket_launcher.tres",
		}
		var path: String = preset_paths.get(subtype, preset_paths["pistol"])
		var wd = load(path)
		if wd != null:
			node.set("weapon_data", wd)

	# Use server-assigned name if provided, otherwise compute deterministically
	if forced_name != "":
		node.name = forced_name
	elif item_type in ["healthpack", "weapon"]:
		var sx: int = int(world_pos.x)
		var sz: int = int(world_pos.z)
		node.name = "Drop_%s_%d_%d" % [item_type, sx, sz]
	elif item_type in ["cannon", "mortar", "slow", "machinegun"]:
		var sx: int = int(world_pos.x)
		var sz: int = int(world_pos.z)
		node.name = "Tower_%s_%d_%d" % [item_type, sx, sz]
	elif item_type == "healstation":
		var sx: int = int(world_pos.x)
		var sz: int = int(world_pos.z)
		node.name = "HealStation_%d_%d" % [sx, sz]
	elif LauncherDefs.is_launcher_type(item_type):
		var sx: int = int(world_pos.x)
		var sz: int = int(world_pos.z)
		node.name = "Launcher_%s_%d_%d" % [item_type.replace("launcher_", ""), sx, sz]

	var main: Node = get_tree().root.get_node("Main")
	main.add_child(node)
	# Set position AFTER add_child — global_position requires the node to be in the tree
	node.global_position = world_pos

	# Type-specific post-add setup
	match item_type:
		"weapon":
			# weapon_data already set pre-add; tag the node for group membership
			node.set_meta("supporter_placed", true)
			node.add_to_group("supporter_drops")
		_:
			# All towers, launchers, healthpacks, healstations, and future types.
			# For tower entries that carry attack_range in PLACEABLE_DEFS, push the
			# authoritative value onto the node BEFORE setup() so TowerBase builds
			# its detection sphere with the correct radius.  This prevents silent
			# drift when .tscn export values diverge from PLACEABLE_DEFS.
			var def: Dictionary = PLACEABLE_DEFS.get(item_type, {})
			if def.has("attack_range") and node.get("attack_range") != null:
				node.set("attack_range", def["attack_range"])
			# TowerBase subclasses take setup(team); launcher types take setup(team, type).
			if LauncherDefs.is_launcher_type(item_type):
				if node.has_method("setup"):
					node.setup(team, item_type)
			elif node.has_method("setup"):
				node.setup(team)
			# Store who placed this tower (for per-placer bonuses)
			node.set("placer_peer_id", placer_peer_id)
			# Apply Supporter attribute and skill tree tower HP bonuses (server/singleplayer only)
			_apply_tower_hp_bonuses(node, item_type, placer_peer_id)
			# Apply Supporter attribute fire rate bonus
			_apply_tower_fire_rate_bonus(node, placer_peer_id)

	# Clear nearby trees for all placements
	var tree_placer: Node = main.get_node_or_null("World/TreePlacer")
	if tree_placer and tree_placer.has_method("clear_trees_at"):
		tree_placer.clear_trees_at(world_pos, 8.0)

	return node.name

# Legacy shim
func spawn_tower_local(world_pos: Vector3, team: int) -> void:
	spawn_item_local(world_pos, team, "cannon", "")



func get_tower_cost() -> int:
	return TOWER_COST

func _apply_tower_hp_bonuses(node: Node, item_type: String, placer_peer_id: int) -> void:
	# Attr bonus: from the placing Supporter's tower_hp attribute
	var hp_bonus_pct: float = LevelSystem.get_bonus_tower_hp_mult(placer_peer_id)
	# Skill tree bonus: s_tower_hp passive (stacks on top of attr bonus)
	hp_bonus_pct += SkillTree.get_passive_bonus(placer_peer_id, "tower_hp_bonus")
	# Barrier ×2 HP from skill tree (s_fortify) — scoped to placer
	var barrier_mult: float = 1.0
	if item_type == "barrier":
		barrier_mult = maxf(barrier_mult, 1.0 + SkillTree.get_passive_bonus(placer_peer_id, "barrier_hp_mult"))
	if hp_bonus_pct == 0.0 and barrier_mult == 1.0:
		return
	var current_hp: float = node.get("_health") if node.get("_health") != null else 0.0
	if current_hp <= 0.0:
		return
	var new_hp: float = current_hp * (1.0 + hp_bonus_pct) * barrier_mult
	node.set("_health", new_hp)
	node.set("max_health", new_hp)

func _apply_tower_fire_rate_bonus(node: Node, placer_peer_id: int) -> void:
	var mult: float = LevelSystem.get_bonus_tower_fire_rate_mult(placer_peer_id)
	if mult == 0.0:
		return
	var interval: float = node.get("attack_interval") if node.get("attack_interval") != null else 0.0
	if interval <= 0.0:
		return  # passive tower — no attack timer
	node.set("attack_interval", interval * (1.0 - mult))

# Called when any peer spends an attribute point.
# When a Supporter spends into tower_fire_rate, retroactively update all towers they placed.
func _on_attribute_spent(peer_id: int, attr: String, _new_attrs: Dictionary) -> void:
	if attr != "tower_fire_rate":
		return
	var mult: float = LevelSystem.get_bonus_tower_fire_rate_mult(peer_id)
	for tower in get_tree().get_nodes_in_group("towers"):
		if tower.get("placer_peer_id") != peer_id:
			continue
		var tower_type: String = tower.get("tower_type") if tower.get("tower_type") != null else ""
		var base_interval: float = PLACEABLE_DEFS.get(tower_type, {}).get("attack_interval_base", 0.0)
		if base_interval <= 0.0:
			continue
		tower.set("attack_interval", base_interval * (1.0 - mult))
