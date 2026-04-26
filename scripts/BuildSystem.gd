extends Node

# ── Placeable definitions ─────────────────────────────────────────────────────
# Each entry: { cost, scene, spacing, is_tower, lane_setback }
# "weapon" cost is 0 — actual cost comes from WEAPON_COSTS keyed by subtype.
const PLACEABLE_DEFS := {
	"cannon":           { "cost": 25, "scene": "res://scenes/towers/Tower.tscn",                  "spacing": 20.0, "is_tower": true,  "lane_setback": true  },
	"mortar":           { "cost": 35, "scene": "res://scenes/towers/MortarTower.tscn",     "spacing": 20.0, "is_tower": true,  "lane_setback": true  },
	"slow":             { "cost": 30, "scene": "res://scenes/towers/SlowTower.tscn",       "spacing": 20.0, "is_tower": true,  "lane_setback": true  },
	"barrier":          { "cost": 10, "scene": "res://scenes/towers/BarrierTower.tscn",    "spacing":  5.0, "is_tower": true,  "lane_setback": false },
	"machinegun":       { "cost": 40, "scene": "res://scenes/towers/MachineGunTower.tscn", "spacing": 15.0, "is_tower": true,  "lane_setback": true  },
	"weapon":           { "cost":  0, "scene": "res://scenes/WeaponPickup.tscn",           "spacing":  5.0, "is_tower": false, "lane_setback": false },
	"healthpack":       { "cost": 15, "scene": "res://scenes/HealthPackPickup.tscn",       "spacing":  5.0, "is_tower": false, "lane_setback": false },
	"healstation":      { "cost": 25, "scene": "res://scenes/HealStation.tscn",            "spacing": 10.0, "is_tower": false, "lane_setback": false },
	# ── Launcher towers — one entry per type in LauncherDefs ─────────────────
	"launcher_missile": { "cost": 50, "scene": "res://scenes/towers/LauncherTower.tscn",          "spacing": 20.0, "is_tower": true,  "lane_setback": true, "is_launcher": true, "launcher_type": "launcher_missile" },
}

const WEAPON_COSTS := { "pistol": 10, "rifle": 20, "heavy": 30, "rocket_launcher": 60 }

# Legacy constants kept for any external references
const TOWER_SCENE    := "res://scenes/towers/Tower.tscn"
const TOWER_COST     := 25
const LANE_SETBACK   := 8.0
const SLOPE_THRESHOLD := 0.85
const MIN_TOWER_SPACING := 20.0

var _loaded_scenes: Dictionary = {}

func _ready() -> void:
	for key in PLACEABLE_DEFS:
		var path: String = PLACEABLE_DEFS[key]["scene"]
		_loaded_scenes[key] = load(path)

# ── Placement validation ──────────────────────────────────────────────────────

func get_item_cost(item_type: String, subtype: String) -> int:
	if item_type == "weapon":
		return WEAPON_COSTS.get(subtype, 0)
	var def: Dictionary = PLACEABLE_DEFS.get(item_type, {})
	return def.get("cost", 0)

func can_place_item(world_pos: Vector3, team: int, item_type: String) -> bool:
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
	var group: String = "towers" if def.get("is_tower", false) else "supporter_drops"
	for node in get_tree().get_nodes_in_group(group):
		if world_pos.distance_to(node.global_position) < spacing:
			return false

	return true

# Legacy shim
func can_place(world_pos: Vector3, team: int) -> bool:
	return can_place_item(world_pos, team, "cannon")

# ── Placement execution ───────────────────────────────────────────────────────

func place_item(world_pos: Vector3, team: int, item_type: String, subtype: String) -> String:
	world_pos.x = snappedf(world_pos.x, 2.0)
	world_pos.z = snappedf(world_pos.z, 2.0)

	if not can_place_item(world_pos, team, item_type):
		return ""

	var cost: int = get_item_cost(item_type, subtype)
	if not TeamData.spend_points(team, cost):
		return ""

	return spawn_item_local(world_pos, team, item_type, subtype)

# Legacy shim
func place_tower(world_pos: Vector3, team: int) -> bool:
	return place_item(world_pos, team, "cannon", "") != ""

func spawn_item_local(world_pos: Vector3, team: int, item_type: String, subtype: String, forced_name: String = "") -> String:
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
	elif item_type in ["cannon", "mortar", "slow", "barrier", "machinegun"]:
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
			# TowerBase subclasses take setup(team); launcher types take setup(team, type).
			if LauncherDefs.is_launcher_type(item_type):
				if node.has_method("setup"):
					node.setup(team, item_type)
			elif node.has_method("setup"):
				node.setup(team)

	# Clear nearby trees for all placements
	var tree_placer: Node = main.get_node_or_null("World/TreePlacer")
	if tree_placer and tree_placer.has_method("clear_trees_at"):
		tree_placer.clear_trees_at(world_pos, 5.0)

	return node.name

# Legacy shim
func spawn_tower_local(world_pos: Vector3, team: int) -> void:
	spawn_item_local(world_pos, team, "cannon", "")



func get_tower_cost() -> int:
	return TOWER_COST
