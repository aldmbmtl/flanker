## TowerBase.gd
## Multiplayer-ready base class for all tower types.
##
## Usage — create a new tower:
##   1. Create a .tscn inheriting StaticBody3D, attach a script that extends TowerBase.
##   2. Set @export vars in the .tscn (or override in _ready() before super.setup() is called).
##   3. Register the tower in BuildSystem.PLACEABLE_DEFS.
##   4. Done — all multiplayer plumbing, collision, targeting, death/despawn, and hit-flash
##      are handled here with no extra wiring.
##
## Overridable hooks:
##   _build_visuals()       — override for procedural mesh towers; default loads model_scene
##   _do_attack(target)     — override for non-projectile attacks (slow pulse, heal, raycast)
##                            default spawns projectile_scene and calls configure() on it
##
## Multi-part models with rotating turrets:
##   Set turret_node_name to the name of the child node to rotate toward the target.
##   The node is found via find_child() so it may be at any depth in the hierarchy.
##   Place a child node named "FirePoint" at the barrel tip for accurate projectile origin.

class_name TowerBase
extends StaticBody3D

# ── Per-tower configuration (set via @export in .tscn or in subclass _ready()) ──

## Identifier key used by BuildSystem naming scheme and despawn_tower signal.
## Must match the key in BuildSystem.PLACEABLE_DEFS.
@export var tower_type: String = ""

## Maximum and starting health points.
@export var max_health: float = 500.0

## Detection sphere radius in world units. Set to 0.0 for passive towers (no Area3D built).
@export var attack_range: float = 30.0

## Seconds between attack attempts.
@export var attack_interval: float = 3.0

## Projectile scene to instantiate on attack. null = override _do_attack() instead.
@export var projectile_scene: PackedScene = null

## Name of child node to rotate toward target each frame. "" = no rotation.
## Searched recursively via find_child() — may be at any depth in the hierarchy.
@export var turret_node_name: String = ""

## Scene (GLB or subscene) to instantiate as the tower model.
## null = override _build_visuals() to build procedural geometry.
@export var model_scene: PackedScene = null

## Scale applied to the instantiated model_scene root.
@export var model_scale: Vector3 = Vector3.ONE

## Local position offset applied to the instantiated model_scene root.
@export var model_offset: Vector3 = Vector3.ZERO

## Y offset above global_position used as fire origin when no "FirePoint" child exists.
@export var fire_point_fallback_height: float = 2.0

## Base XP awarded to the killing player on tower death (uses LevelSystem.XP_TOWER if 0).
@export var xp_on_death: int = 0

# ── Runtime state (set by BuildSystem after add_child, not designed in .tscn) ──

## Team that owns this tower. Set by BuildSystem.spawn_item_local() after add_child.
var team: int = 0

var _health: float = 0.0
var _dead: bool = false
var _attack_timer: float = 0.0
var _area: Area3D = null
var _mesh_inst: MeshInstance3D = null   # first mesh in model subtree; used for hit flash
var _turret_node: Node3D = null          # cached ref to the turret rotation node
var _killer_peer_id: int = -1
var _hit_flash_tween: Tween = null
var _hit_overlay_mat: StandardMaterial3D = null

# ── Entry point — called by BuildSystem.spawn_item_local() ───────────────────

## Initialises the tower for the given team. Must be called after add_child().
func setup(p_team: int) -> void:
	team = p_team
	_health = max_health

	_build_visuals()

	# Cache turret node
	if turret_node_name != "":
		_turret_node = find_child(turret_node_name, true, false) as Node3D

	# Build detection area entirely in code — no .tscn dependency
	if attack_range > 0.0:
		_build_detection_area()

	add_to_group("towers")

# ── Visual construction ───────────────────────────────────────────────────────

## Default: instantiate model_scene, apply scale/offset, cache first MeshInstance3D.
## Override for procedural geometry (no model_scene).
func _build_visuals() -> void:
	if model_scene == null:
		return
	var root: Node3D = model_scene.instantiate() as Node3D
	if root == null:
		push_error("TowerBase(%s): model_scene.instantiate() returned null" % tower_type)
		return
	root.scale = model_scale
	root.position = model_offset
	add_child(root)

	# Cache first MeshInstance3D in the subtree for hit-flash
	var meshes: Array = find_children("*", "MeshInstance3D", true, false)
	if meshes.size() > 0:
		_mesh_inst = meshes[0] as MeshInstance3D
		_add_hit_overlay(_mesh_inst)

## Prepares the hit-flash overlay material — does NOT apply it to the mesh yet.
## Applied only during _flash_hit() so the GLB's own material shows at rest.
func _add_hit_overlay(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2, 1.0)
	mat.emission_energy_multiplier = 3.0
	_hit_overlay_mat = mat

# ── Detection area ────────────────────────────────────────────────────────────

func _build_detection_area() -> void:
	_area = Area3D.new()
	_area.name = "DetectionArea"
	# Collision layer 0 — only detects; does not block physics
	_area.collision_layer = 0
	_area.collision_mask = 0b11   # layers 1+2: terrain + units
	add_child(_area)

	var shape := SphereShape3D.new()
	shape.radius = attack_range
	var col := CollisionShape3D.new()
	col.shape = shape
	_area.add_child(col)

# ── Attack loop ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _dead or _area == null:
		return
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	var target: Node3D = _find_target()
	if target == null:
		return
	# Rotate turret toward target before firing
	if _turret_node != null and is_instance_valid(_turret_node):
		var look_pos: Vector3 = target.global_position
		look_pos.y = _turret_node.global_position.y   # keep level on y-axis
		if look_pos.distance_squared_to(_turret_node.global_position) > 0.01:
			_turret_node.look_at(look_pos, Vector3.UP)
	_do_attack(target)
	_attack_timer = attack_interval

## Finds the nearest enemy body within the detection area with line-of-sight.
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist: float = attack_range + 1.0

	# Area3D overlap — catches minions, local FPSPlayer, and any ghosts in range
	for body in _area.get_overlapping_bodies():
		var body_team: int = _resolve_body_team(body)
		if body_team < 0 or body_team == team:
			continue
		var d: float = global_position.distance_to(body.global_position)
		if d < best_dist and _has_line_of_sight(body):
			best_dist = d
			best = body

	# Direct group scan — catches players whose ghosts haven't entered the Area3D yet
	if multiplayer.has_multiplayer_peer():
		for player in get_tree().get_nodes_in_group("players"):
			if not player.has_method("take_damage"):
				continue
			var body_team: int = _get_body_team(player)
			if body_team < 0 or body_team == team:
				continue
			var d: float = global_position.distance_to(player.global_position)
			if d < best_dist and d <= attack_range and _has_line_of_sight(player):
				best_dist = d
				best = player
		for ghost in get_tree().get_nodes_in_group("remote_players"):
			var pid: int = ghost.get("peer_id") as int
			var body_team: int = GameSync.get_player_team(pid)
			if body_team < 0 or body_team == team:
				continue
			var d: float = global_position.distance_to(ghost.global_position)
			# Use HitBody (StaticBody3D) for LOS so get_rid() is valid;
			# fall back to skipping LOS check if HitBody is absent.
			var hit_body: Node3D = ghost.get_node_or_null("HitBody")
			var los_target: Node3D = hit_body if hit_body != null else null
			if los_target == null:
				continue
			if d < best_dist and d <= attack_range and _has_line_of_sight(los_target):
				best_dist = d
				best = ghost

	return best

## Resolves the team for a body — handles both direct nodes (take_damage) and
## RemotePlayerGhost HitBody nodes (ghost_peer_id meta + GameSync lookup).
func _resolve_body_team(body: Object) -> int:
	if body.has_method("take_damage"):
		return _get_body_team(body)
	if body.has_meta("ghost_peer_id"):
		return GameSync.get_player_team(body.get_meta("ghost_peer_id") as int)
	return -1

## Duck-types team out of a body node (players use player_team, minions use team).
func _get_body_team(body: Object) -> int:
	if body.has_method("get"):
		var pt = body.get("player_team")
		if pt != null:
			return pt as int
		var t = body.get("team")
		if t != null:
			return t as int
	return -1

## Raycast LOS check; ignores tree trunks (meta "tree_trunk_height").
func _has_line_of_sight(target: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3(0.0, 2.0, 0.0)
	var to: Vector3 = target.global_position + Vector3(0.0, 0.8, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var excluded: Array[RID] = [get_rid(), target.get_rid()]
	for _attempt in range(4):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excluded
		query.collision_mask = 0b11
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return true
		var hit: Object = result.collider
		if hit != null and hit.has_meta("tree_trunk_height"):
			excluded.append(hit.get_rid())
			continue
		return false
	return true

## Default attack: spawn projectile_scene, position it at fire origin, add to scene root.
## The projectile must accept property assignment for: shooter_team.
## Override this method for non-projectile attacks (slow, heal, raycast, custom arc).
func _do_attack(target: Node3D) -> void:
	if projectile_scene == null:
		return
	var proj: Node3D = projectile_scene.instantiate() as Node3D
	if proj == null:
		return
	var fire_pos: Vector3 = get_fire_position()
	proj.set("shooter_team", team)
	proj.position = fire_pos   # set before add_child so _ready() sees origin
	get_tree().root.get_child(0).add_child(proj)

## Returns world-space fire origin.
## Looks for a child node named "FirePoint"; falls back to global_position + fallback height.
func get_fire_position() -> Vector3:
	var fp: Node3D = find_child("FirePoint", true, false) as Node3D
	if fp != null:
		return fp.global_position
	return global_position + Vector3(0.0, fire_point_fallback_height, 0.0)

# ── Public health accessors ───────────────────────────────────────────────────

func get_health() -> float:
	return _health

func get_max_health() -> float:
	return max_health

# ── Damage / death ────────────────────────────────────────────────────────────

## Server-authoritative damage entry point.
## source_team: team of the attacker — used to block friendly fire.
## shooter_peer_id: peer_id of the killing player for XP award (-1 = unknown / minion).
func take_damage(amount: float, _source: String, source_team: int = -1, shooter_peer_id: int = -1) -> void:
	if _dead:
		return
	if source_team == team:
		return   # friendly fire — ignore
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return   # clients never apply damage; server is authoritative
	_killer_peer_id = shooter_peer_id
	_health -= amount
	_flash_hit()
	if _health <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true

	# XP award (server-authoritative)
	var xp: int = xp_on_death if xp_on_death > 0 else LevelSystem.XP_TOWER
	if _killer_peer_id > 0:
		LevelSystem.award_xp(_killer_peer_id, xp)
	elif not multiplayer.has_multiplayer_peer():
		# Singleplayer — award to local player (peer id 1)
		LevelSystem.award_xp(1, xp)

	if multiplayer.has_multiplayer_peer():
		# Multiplayer: server broadcasts despawn to all peers (call_local)
		LobbyManager.despawn_tower.rpc(name)
	else:
		# Singleplayer: capture vars before queue_free, emit signal manually
		var t: int = team
		var tt: String = tower_type
		var n: String = name
		queue_free()
		LobbyManager.tower_despawned.emit(tt, t, n)

# ── Hit flash ─────────────────────────────────────────────────────────────────

func _flash_hit() -> void:
	if _mesh_inst == null or not is_instance_valid(_mesh_inst):
		return
	if _hit_overlay_mat == null:
		return
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	# Apply overlay, tween emission down, then clear the override so base mat returns
	for i in _mesh_inst.mesh.get_surface_count():
		_mesh_inst.set_surface_override_material(i, _hit_overlay_mat)
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_overlay_mat, "emission_energy_multiplier", 0.0, 0.3)
	_hit_flash_tween.tween_callback(func() -> void:
		if is_instance_valid(_mesh_inst):
			for i in _mesh_inst.mesh.get_surface_count():
				_mesh_inst.set_surface_override_material(i, null)
	)
