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
##   _build_visuals()       — override for procedural mesh towers; default loads component models
##   _do_attack(target)     — override for non-projectile attacks (slow pulse, heal, raycast)
##                            default spawns projectile_scene and calls configure() on it
##
## Composite model system:
##   Towers are assembled from up to three component GLBs:
##     model_base     — static body/base (never rotates)
##     model_turret   — turret head, parented to _turret_pivot which yaws toward target
##     model_attachment — optional extra piece co-parented to _turret_pivot (e.g. a barrel)
##   Each component has its own scale and offset export.
##   Place a child node named "FirePoint" at the barrel tip for accurate projectile origin.
##
## Backward compatibility:
##   model_scene / model_scale / model_offset are kept as deprecated exports.
##   If model_base is null and model_scene is set, model_scene is used as the base.

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

# ── Composite model exports ───────────────────────────────────────────────────

## Static base / body of the tower. Never rotates.
@export var model_base: PackedScene = null
@export var model_base_scale: Vector3 = Vector3.ONE
@export var model_base_offset: Vector3 = Vector3.ZERO

## Middle section(s) stacked on top of the base (optional). Also static.
## model_mid_count controls how many times the same GLB is repeated.
## model_mid_offset is the position of the first repeat.
## model_mid_step is the per-repeat increment (stacking direction + distance).
@export var model_mid: PackedScene = null
@export var model_mid_scale: Vector3 = Vector3.ONE
@export var model_mid_offset: Vector3 = Vector3.ZERO
@export var model_mid_count: int = 1
@export var model_mid_step: Vector3 = Vector3(0.0, 1.0, 0.0)

## Top cap piece placed above all mid sections (optional). Also static.
@export var model_top: PackedScene = null
@export var model_top_scale: Vector3 = Vector3.ONE
@export var model_top_offset: Vector3 = Vector3.ZERO

## Turret head. Parented to _turret_pivot which yaws toward the current target.
@export var model_turret: PackedScene = null
@export var model_turret_scale: Vector3 = Vector3.ONE
## World-space Y height at which the turret pivot sits (relative to tower origin).
@export var model_turret_offset: Vector3 = Vector3(0.0, 3.0, 0.0)
## Euler rotation (degrees) applied to the turret model node inside the pivot.
## Use Vector3(0, 180, 0) to flip a cannon that faces the wrong way in its GLB.
@export var model_turret_rotation_deg: Vector3 = Vector3.ZERO

## Optional attachment (barrel, scope, flag). Co-parented to _turret_pivot — rotates with turret.
@export var model_attachment: PackedScene = null
@export var model_attachment_scale: Vector3 = Vector3.ONE
@export var model_attachment_offset: Vector3 = Vector3.ZERO

# ── Deprecated single-model exports (backward compat — use model_base instead) ──
## @deprecated Use model_base. If model_base is null, model_scene is used as base.
@export var model_scene: PackedScene = null
@export var model_scale: Vector3 = Vector3.ONE
@export var model_offset: Vector3 = Vector3.ZERO

## Y offset above global_position used as fire origin when no "FirePoint" child exists.
@export var fire_point_fallback_height: float = 2.0

## Base XP awarded to the killing player on tower death (uses LevelSystem.XP_TOWER if 0).
@export var xp_on_death: int = 0

## Seconds after placement before the tower becomes active and starts attacking.
## Tower is immediately visible; build_time only gates the first attack.
@export var build_time: float = 0.0

# ── Runtime state (set by BuildSystem after add_child, not designed in .tscn) ──

## Team that owns this tower. Set by BuildSystem.spawn_item_local() after add_child.
var team: int = 0
## Peer who placed this tower. -1 = unknown / singleplayer peer 1.
var placer_peer_id: int = -1
## Lane index this tower was placed in (0=Left, 1=Mid, 2=Right). -1 = unknown.
## Set by BuildSystem.spawn_item_local() via lane proximity check after spawn.
var _lane_index: int = -1

var _health: float = 0.0
var _dead: bool = false
var _attack_timer: float = 0.0
var _build_timer: float = 0.0   # counts down from build_time; 0 = active
var _area: Area3D = null
## All MeshInstance3D nodes across all components — used for hit-flash.
var _all_mesh_insts: Array[MeshInstance3D] = []
## First mesh in the subtree; kept for backward compat with subclasses that read _mesh_inst.
var _mesh_inst: MeshInstance3D = null
## Pivot node that yaws toward the current target. Created by _build_visuals().
var _turret_pivot: Node3D = null
var _killer_peer_id: int = -1
var _hit_flash_tween: Tween = null
var _hit_overlay_mat: StandardMaterial3D = null
## Model component roots added by _build_visuals(), with their original scales.
## Kept for subclass use; no longer used for build-phase animation.
var _model_roots: Array[Node3D] = []
var _model_root_scales: Array[Vector3] = []

# ── Entry point — called by BuildSystem.spawn_item_local() ───────────────────

## Initialises the tower for the given team. Must be called after add_child().
func setup(p_team: int) -> void:
	team = p_team
	_health = max_health
	_build_timer = build_time

	_build_visuals()

	# If build_time is set, the tower is already fully visible — build_time only
	# gates the attack phase (tower does not fire until the timer elapses).

	# Build detection area entirely in code — no .tscn dependency
	if attack_range > 0.0:
		_build_detection_area()

	add_to_group("towers")

# ── Visual construction ───────────────────────────────────────────────────────

## Default: assemble tower from component GLBs (model_base, model_mid, model_turret,
## model_attachment). Falls back to legacy model_scene if model_base is null.
## Override entirely for fully procedural geometry (see LauncherTower).
func _build_visuals() -> void:
	# Determine effective base scene (new or legacy)
	var base_scene: PackedScene = model_base if model_base != null else model_scene
	var base_scale: Vector3    = model_base_scale if model_base != null else model_scale
	var base_offset: Vector3   = model_base_offset if model_base != null else model_offset

	# ── Base ──────────────────────────────────────────────────────────────────
	if base_scene != null:
		var root: Node3D = base_scene.instantiate() as Node3D
		if root == null:
			push_error("TowerBase(%s): model_base instantiate() returned null" % tower_type)
		else:
			root.scale    = base_scale
			root.position = base_offset
			add_child(root)
			_collect_meshes(root)
			_register_model_root(root)

	# ── Mid section(s) — repeated model_mid_count times ─────────────────────────
	if model_mid != null:
		for i in model_mid_count:
			var mid: Node3D = model_mid.instantiate() as Node3D
			if mid != null:
				mid.scale    = model_mid_scale
				mid.position = model_mid_offset + model_mid_step * i
				add_child(mid)
				_collect_meshes(mid)
				_register_model_root(mid)

	# ── Top cap ───────────────────────────────────────────────────────────────
	if model_top != null:
		var top: Node3D = model_top.instantiate() as Node3D
		if top != null:
			top.scale    = model_top_scale
			top.position = model_top_offset
			add_child(top)
			_collect_meshes(top)
			_register_model_root(top)

	# ── Turret pivot (always created so subclasses and _process can rely on it) ─
	_turret_pivot = Node3D.new()
	_turret_pivot.name = "TurretPivot"
	_turret_pivot.position = model_turret_offset
	add_child(_turret_pivot)
	_register_model_root(_turret_pivot)

	# ── Turret head ───────────────────────────────────────────────────────────
	if model_turret != null:
		var turret: Node3D = model_turret.instantiate() as Node3D
		if turret != null:
			turret.scale    = model_turret_scale
			turret.position = Vector3.ZERO
			turret.rotation_degrees = model_turret_rotation_deg
			_turret_pivot.add_child(turret)
			_collect_meshes(turret)

	# ── Attachment (co-rotates with turret) ───────────────────────────────────
	if model_attachment != null:
		var att: Node3D = model_attachment.instantiate() as Node3D
		if att != null:
			att.scale    = model_attachment_scale
			att.position = model_attachment_offset
			_turret_pivot.add_child(att)
			_collect_meshes(att)

	# Cache first mesh for backward compat
	if _all_mesh_insts.size() > 0:
		_mesh_inst = _all_mesh_insts[0]

	_build_hit_overlay()

## Collect all MeshInstance3D nodes from a subtree into _all_mesh_insts.
func _collect_meshes(root: Node3D) -> void:
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi != null and mi.mesh != null:
			_all_mesh_insts.append(mi)

## Prepares the hit-flash overlay material — does NOT apply it to any mesh yet.
## Applied only during _flash_hit() so GLB materials show at rest.
func _build_hit_overlay() -> void:
	if _all_mesh_insts.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2, 1.0)
	mat.emission_energy_multiplier = 3.0
	_hit_overlay_mat = mat

## Kept for backward compat — subclasses that called _add_hit_overlay(mi) directly.
## Delegates to _build_hit_overlay(); mi parameter is ignored.
func _add_hit_overlay(_mi: MeshInstance3D) -> void:
	_build_hit_overlay()

# ── Detection area ────────────────────────────────────────────────────────────

func _build_detection_area() -> void:
	_area = Area3D.new()
	_area.name = "DetectionArea"
	# Collision layer 0 — only detects; does not block physics
	_area.collision_layer = 0
	_area.collision_mask = 0b101   # layers 1+3: players/terrain (1) + minions (3)
	add_child(_area)

	var shape := SphereShape3D.new()
	shape.radius = attack_range
	var col := CollisionShape3D.new()
	col.shape = shape
	_area.add_child(col)

## Register a model component root for build-phase scale animation.
## Must be called AFTER the root has been add_child'd and its final scale set.
func _register_model_root(root: Node3D) -> void:
	_model_roots.append(root)
	_model_root_scales.append(root.scale)

## Sets scale of all model roots (kept for subclass use; no longer called during build phase).
## t=0.0 = scale 0; t=1.0 = original scale.
func _set_model_alpha(t: float) -> void:
	for i in _model_roots.size():
		var root: Node3D = _model_roots[i]
		if is_instance_valid(root):
			root.scale = _model_root_scales[i] * t

# ── Attack loop ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if NetworkManager._peer != null and not multiplayer.is_server():
		return
	if _dead or _area == null:
		return
	# ── Build phase ────────────────────────────────────────────────────────────
	if _build_timer > 0.0:
		_build_timer -= delta
		if _build_timer <= 0.0:
			_build_timer = 0.0
		return
	# ── Attack phase ───────────────────────────────────────────────────────────
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	var target: Node3D = _find_target()
	if target == null:
		return
	# Yaw turret pivot toward target (horizontal only — no barrel tilt)
	if _turret_pivot != null and is_instance_valid(_turret_pivot) and model_turret != null:
		var look_pos: Vector3 = target.global_position
		look_pos.y = _turret_pivot.global_position.y
		if look_pos.distance_squared_to(_turret_pivot.global_position) > 0.01:
			_turret_pivot.look_at(look_pos, Vector3.UP)
			_on_turret_rotated(_turret_pivot.rotation.y)
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
	var hit_body: Node = target.get_node_or_null("HitBody")
	if hit_body != null:
		excluded.append(hit_body.get_rid())
	for _attempt in range(4):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excluded
		query.collision_mask = 0b01   # layer 1 (terrain) only — fences/walls (layer 2) must not block tower LOS
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

## Shared helper for ballistic-arc towers (Cannon, Mortar).
## Instantiates proj_scene, sets damage/source/team/spawner, adds to scene root,
## plays sound, and calls rpc_callable on the server peer.
## rpc_callable signature: (spawn_pos, aim_pos, dmg, team)
func _fire_ballistic(proj_scene: PackedScene, dmg: float, source_tag: String,
		snd: String, snd_vol: float, pitch_min: float, pitch_max: float,
		target: Node3D, rpc_callable: Callable) -> void:
	var spawn_pos: Vector3 = get_fire_position()
	var aim_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)
	var proj: Node3D = proj_scene.instantiate()
	proj.set("damage",       dmg)
	proj.set("source",       source_tag)
	proj.set("shooter_team", team)
	proj.set("spawner_rid",  get_rid())
	proj.set("target_pos",   aim_pos)
	proj.position = spawn_pos   # before add_child so _ready() sees origin
	VfxUtils.get_scene_root(self).add_child(proj)
	SoundManager.play_3d(snd, spawn_pos, snd_vol, randf_range(pitch_min, pitch_max))
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_callable.rpc(spawn_pos, aim_pos, dmg, team)

## Called by _process after _turret_pivot.look_at() when the pivot actually moved.
## Override in subclasses that need to broadcast the new yaw to remote peers.
func _on_turret_rotated(_yaw_rad: float) -> void:
	pass

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
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		LobbyManager.notify_tower_hit.rpc(name)
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
	else:
		# No known killer — award to local player (peer id 1 in SP, no-op in MP)
		LevelSystem.award_xp(1, xp)

	# ── Tower-kill streak: send free ram minion(s) to the killer's team ──────
	# Only runs server/singleplayer; only when a player landed the killing blow.
	if _killer_peer_id > 0 and (multiplayer.is_server() or not multiplayer.has_multiplayer_peer()):
		var killer_team: int = GameSync.get_player_team(_killer_peer_id)
		if killer_team >= 0 and _lane_index >= 0:
			var spawner: Node = get_tree().root.get_node_or_null("Main/MinionSpawner")
			if spawner != null and spawner.has_method("spawn_free_ram"):
				# Increment tower kill streak
				var streak: int = GameSync.player_tower_kill_streak.get(_killer_peer_id, 0) + 1
				GameSync.player_tower_kill_streak[_killer_peer_id] = streak
				# tier: 0 at kill 1, 1 at kill 2, 2 at kill 3+
				var ram_tier: int = mini(streak - 1, 2)
				# ram count: 1 for kills 1-3, then +1 per kill beyond 3
				var ram_count: int = 1 if streak <= 3 else (streak - 2)
				for _i in ram_count:
					spawner.spawn_free_ram(killer_team, ram_tier, _lane_index)

	# Broadcast despawn to all peers (call_local — runs locally in SP too)
	LobbyManager.despawn_tower.rpc(name)

# ── Hit flash ─────────────────────────────────────────────────────────────────

func _flash_hit() -> void:
	if _all_mesh_insts.is_empty() or _hit_overlay_mat == null:
		return
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	# Reset emission energy before applying (previous tween may have left it at 0)
	_hit_overlay_mat.emission_energy_multiplier = 3.0
	# Apply overlay to all mesh surfaces
	for mi in _all_mesh_insts:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _hit_overlay_mat)
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_overlay_mat, "emission_energy_multiplier", 0.0, 0.3)
	_hit_flash_tween.tween_callback(func() -> void:
		for mi in _all_mesh_insts:
			if not is_instance_valid(mi) or mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, null)
	)
