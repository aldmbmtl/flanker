extends Camera3D

const PAN_SPEED := 40.0
const ZOOM_SPEED := 5.0
const MIN_FOV := 30.0
const MAX_FOV := 100.0

const TOWER_MODEL_PATH := "res://assets/tower-defense-kit/Models/GLB format/tower-square-build-a.glb"
const RANGE_CIRCLE_SEGMENTS := 36
const PLAYER_VISION_RADIUS := 35.0
const MINION_VISION_RADIUS := 25.0

# Range per tower type (0 = no circle)
const TYPE_RANGES := {
	"cannon":      30.0,
	"mortar":      50.0,
	"slow":        18.0,
	"barrier":     0.0,
	"weapon":      0.0,
	"healthpack":  0.0,
	"healstation": 4.0,
}

var build_system: Node = null
# 0 = FIGHTER (view only), 1 = SUPPORTER (can build)
var player_role: int = 0

var _ghost: Node3D = null
var _ghost_mat_valid: StandardMaterial3D = null
var _ghost_mat_invalid: StandardMaterial3D = null
var _ghost_valid: bool = false
var _ghost_world_pos: Vector3 = Vector3.ZERO
var _player_team: int = 0

var _fog_overlay: MeshInstance3D = null
var _main: Node = null
var _fog_frame_counter: int = 0
var _los_frame_counter: int = 0

var _range_mesh_inst: MeshInstance3D = null
var _range_imesh: ImmediateMesh = null
var _range_mat_valid: StandardMaterial3D = null
var _range_mat_invalid: StandardMaterial3D = null

var _los_mesh_inst: MeshInstance3D = null
var _los_imesh: ImmediateMesh = null
var _los_mat: StandardMaterial3D = null

# Current placement selection — driven by SupporterHUD
var _selected_type:    String = "cannon"
var _selected_subtype: String = ""
var _supporter_hud: Node = null
var _launcher_hud: Node = null

func _ready() -> void:
	build_system = get_node_or_null("/root/Main/BuildSystem")
	_main = get_node_or_null("/root/Main")
	rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_build_ghost_materials()
	_create_fog_overlay()

func setup(team: int) -> void:
	_player_team = team
	var base_z: float = 84.0 if team == 0 else -93.0
	global_position = Vector3(0.0, 80.0, base_z)

func set_supporter_hud(hud: Node) -> void:
	_supporter_hud = hud
	if hud != null:
		hud.slot_changed.connect(_on_slot_changed)

func set_launcher_hud(hud: Node) -> void:
	_launcher_hud = hud
	if hud != null:
		hud.fire_requested.connect(_on_fire_requested)
		hud.reveal_requested.connect(_on_reveal_requested)

func _on_slot_changed(item_type: String, subtype: String) -> void:
	_selected_type    = item_type
	_selected_subtype = subtype
	_destroy_ghost()  # Rebuild ghost for new type

func _create_fog_overlay() -> void:
	var fog_script := load("res://scripts/FogOverlay.gd")
	_fog_overlay = MeshInstance3D.new()
	_fog_overlay.set_script(fog_script)
	_fog_overlay.name = "FogOverlay"
	call_deferred("_add_fog_to_world")

# ── Ghost materials ──────────────────────────────────────────────────────────

func _add_fog_to_world() -> void:
	var world: Node = get_node_or_null("/root/Main/World")
	if world and _fog_overlay:
		world.add_child(_fog_overlay)

func _build_ghost_materials() -> void:
	_ghost_mat_valid = StandardMaterial3D.new()
	_ghost_mat_valid.wireframe = true
	_ghost_mat_valid.albedo_color = Color(0.0, 1.0, 0.4, 1.0)

	_ghost_mat_invalid = StandardMaterial3D.new()
	_ghost_mat_invalid.wireframe = true
	_ghost_mat_invalid.albedo_color = Color(1.0, 0.2, 0.2, 1.0)

	_range_mat_valid = StandardMaterial3D.new()
	_range_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_mat_valid.no_depth_test = true
	_range_mat_valid.albedo_color = Color(0.0, 1.0, 0.4, 1.0)

	_range_mat_invalid = StandardMaterial3D.new()
	_range_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_mat_invalid.no_depth_test = true
	_range_mat_invalid.albedo_color = Color(1.0, 0.2, 0.2, 1.0)

	_los_mat = StandardMaterial3D.new()
	_los_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_los_mat.no_depth_test = true
	_los_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_los_mat.vertex_color_use_as_albedo = true
	_los_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

func _create_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		return
	# Direct-cast strikes (recon_strike etc.) have no placement ghost
	if LauncherDefs.is_direct_cast(_selected_type):
		return
	var packed := load(TOWER_MODEL_PATH) as PackedScene
	if packed == null:
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		return

	_ghost = Node3D.new()
	# Scale smaller for non-tower items
	match _selected_type:
		"weapon", "healthpack":
			root.scale = Vector3(0.4, 0.4, 0.4)
		"healstation":
			root.scale = Vector3(0.6, 0.3, 0.6)
		"barrier":
			root.scale = Vector3(0.8, 1.4, 0.4)
		_:
			pass  # default scale

	_ghost.add_child(root)

	# Range circle — parented to scene root (NOT ghost) to avoid position double-offset
	var range_val: float = TYPE_RANGES.get(_selected_type, 0.0)
	if range_val > 0.0:
		_range_imesh = ImmediateMesh.new()
		_range_mesh_inst = MeshInstance3D.new()
		_range_mesh_inst.mesh = _range_imesh
		_range_mesh_inst.material_override = _range_mat_invalid
		get_tree().root.get_child(0).add_child(_range_mesh_inst)

		_los_imesh = ImmediateMesh.new()
		_los_mesh_inst = MeshInstance3D.new()
		_los_mesh_inst.mesh = _los_imesh
		_los_mesh_inst.material_override = _los_mat
		get_tree().root.get_child(0).add_child(_los_mesh_inst)
	else:
		_range_imesh = null
		_range_mesh_inst = null
		_los_imesh = null
		_los_mesh_inst = null

	get_tree().root.get_child(0).add_child(_ghost)
	_apply_ghost_material(_ghost_mat_invalid)

func _destroy_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if _range_mesh_inst != null and is_instance_valid(_range_mesh_inst):
		_range_mesh_inst.queue_free()
	_range_mesh_inst = null
	_range_imesh = null
	if _los_mesh_inst != null and is_instance_valid(_los_mesh_inst):
		_los_mesh_inst.queue_free()
	_los_mesh_inst = null
	_los_imesh = null
	_los_frame_counter = 0

func _apply_ghost_material(mat: StandardMaterial3D) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	_set_material_recursive(_ghost, mat)
	if _range_mesh_inst != null and is_instance_valid(_range_mesh_inst):
		_range_mesh_inst.material_override = _range_mat_valid if mat == _ghost_mat_valid else _range_mat_invalid

func _set_material_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_set_material_recursive(child, mat)

func _draw_range_circle(center: Vector3) -> void:
	if _range_imesh == null or not is_instance_valid(_range_imesh):
		return
	var range_val: float = TYPE_RANGES.get(_selected_type, 0.0)
	if range_val <= 0.0:
		return
	# Position the mesh node at the ghost world position so vertices can be local-space
	_range_mesh_inst.global_position = Vector3(center.x, center.y + 0.3, center.z)
	_range_imesh.clear_surfaces()
	_range_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(RANGE_CIRCLE_SEGMENTS):
		var a0: float = (float(i)       / float(RANGE_CIRCLE_SEGMENTS)) * TAU
		var a1: float = (float(i + 1)   / float(RANGE_CIRCLE_SEGMENTS)) * TAU
		var p0 := Vector3(cos(a0) * range_val, 0.0, sin(a0) * range_val)
		var p1 := Vector3(cos(a1) * range_val, 0.0, sin(a1) * range_val)
		_range_imesh.surface_add_vertex(p0)
		_range_imesh.surface_add_vertex(p1)
	_range_imesh.surface_end()

func _draw_los_fan(center: Vector3) -> void:
	if _los_imesh == null or not is_instance_valid(_los_imesh):
		return
	var range_val: float = TYPE_RANGES.get(_selected_type, 0.0)
	if range_val <= 0.0:
		return

	var origin: Vector3 = center + Vector3(0.0, 1.5, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	# Anchor mesh node at center so triangle vertices are local-space
	_los_mesh_inst.global_position = Vector3(center.x, center.y + 0.25, center.z)

	var col_clear := Color(0.1, 1.0, 0.3, 0.22)
	var col_block := Color(1.0, 0.15, 0.05, 0.15)

	_los_imesh.clear_surfaces()
	_los_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(RANGE_CIRCLE_SEGMENTS):
		var a0: float = (float(i)     / float(RANGE_CIRCLE_SEGMENTS)) * TAU
		var a1: float = (float(i + 1) / float(RANGE_CIRCLE_SEGMENTS)) * TAU
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))

		var p0_clear: bool = _los_ray(space, origin, d0, range_val, center)
		var p1_clear: bool = _los_ray(space, origin, d1, range_val, center)

		# Endpoint in local space (mesh is at center, y at ground level)
		var p0: Vector3 = d0 * range_val
		var p1: Vector3 = d1 * range_val

		if not p0_clear:
			# Find actual blocker position for this ray
			var hit_pos: Vector3 = _los_ray_hit_pos(space, origin, d0, range_val, center)
			var h: Vector3 = hit_pos - Vector3(center.x, center.y + 0.25, center.z)
			p0 = Vector3(h.x, 0.0, h.z)

		if not p1_clear:
			var hit_pos: Vector3 = _los_ray_hit_pos(space, origin, d1, range_val, center)
			var h: Vector3 = hit_pos - Vector3(center.x, center.y + 0.25, center.z)
			p1 = Vector3(h.x, 0.0, h.z)

		var col: Color = col_clear if (p0_clear and p1_clear) else col_block

		# Triangle: origin, p0, p1
		_los_imesh.surface_set_color(col)
		_los_imesh.surface_add_vertex(Vector3.ZERO)
		_los_imesh.surface_set_color(col)
		_los_imesh.surface_add_vertex(p0)
		_los_imesh.surface_set_color(col)
		_los_imesh.surface_add_vertex(p1)

	_los_imesh.surface_end()

# Returns true if the ray in direction d is unobstructed (ignoring short trees and clearing-radius trees).
func _los_ray(space: PhysicsDirectSpaceState3D, origin: Vector3, d: Vector3, range_val: float, ghost_center: Vector3) -> bool:
	var excluded: Array[RID] = []
	for _attempt in range(4):
		var target: Vector3 = origin + d * range_val
		var query := PhysicsRayQueryParameters3D.create(origin, target)
		query.collision_mask = 0b11
		query.exclude = excluded
		var res: Dictionary = space.intersect_ray(query)
		if res.is_empty():
			return true
		var body: Object = res.collider
		if _los_tree_passthrough(body, ghost_center):
			excluded.append(body.get_rid())
			continue
		return false
	return true

# Returns the world-space hit position of the first real blocker along this ray.
func _los_ray_hit_pos(space: PhysicsDirectSpaceState3D, origin: Vector3, d: Vector3, range_val: float, ghost_center: Vector3) -> Vector3:
	var excluded: Array[RID] = []
	for _attempt in range(4):
		var target: Vector3 = origin + d * range_val
		var query := PhysicsRayQueryParameters3D.create(origin, target)
		query.collision_mask = 0b11
		query.exclude = excluded
		var res: Dictionary = space.intersect_ray(query)
		if res.is_empty():
			return origin + d * range_val
		var body: Object = res.collider
		if _los_tree_passthrough(body, ghost_center):
			excluded.append(body.get_rid())
			continue
		return res.position
	return origin + d * range_val

# Returns true if this hit body should be ignored for LOS purposes:
#   - tree within the tower's clearing radius (will be removed on placement)
#   - tree shorter than the tower barrel height (1.5 u)
func _los_tree_passthrough(body: Object, ghost_center: Vector3) -> bool:
	if body == null or not body.has_meta("tree_trunk_height"):
		return false
	# Within clearing radius — will be removed when tower is placed
	var xz_dist: float = Vector2(body.global_position.x - ghost_center.x,
								 body.global_position.z - ghost_center.z).length()
	if xz_dist <= 5.0:
		return true
	# Too short to block the tower barrel
	var trunk_h: float = body.get_meta("tree_trunk_height")
	if trunk_h <= 1.5:
		return true
	return false

# ── Process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not current:
		_destroy_ghost()
		_restore_fog()
		return

	# Sync selection from SupporterHUD each frame
	if _supporter_hud != null and is_instance_valid(_supporter_hud):
		var new_type:    String = _supporter_hud.selected_type
		var new_subtype: String = _supporter_hud.selected_subtype
		if new_type != _selected_type or new_subtype != _selected_subtype:
			_selected_type    = new_type
			_selected_subtype = new_subtype
			_destroy_ghost()

	# Fighters get view-only RTS — no placement ghost
	if player_role == 1:
		_create_ghost()

	# Zoom
	if Input.is_action_just_pressed("rts_zoom_in"):
		fov = max(MIN_FOV, fov - ZOOM_SPEED)
	elif Input.is_action_just_pressed("rts_zoom_out"):
		fov = min(MAX_FOV, fov + ZOOM_SPEED)

	# WASD pan
	var dir := Vector2.ZERO
	if Input.is_action_pressed("rts_pan_up"):    dir.y -= 1.0
	if Input.is_action_pressed("rts_pan_down"):  dir.y += 1.0
	if Input.is_action_pressed("rts_pan_left"):  dir.x -= 1.0
	if Input.is_action_pressed("rts_pan_right"): dir.x += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		global_position.x += dir.x * PAN_SPEED * delta
		global_position.z += dir.y * PAN_SPEED * delta

	_update_ghost()
	_fog_frame_counter += 1
	if _fog_frame_counter >= 4:
		_fog_frame_counter = 0
		_update_fog()

func _update_ghost() -> void:
	if _ghost == null or not is_instance_valid(_ghost) or build_system == null:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = project_ray_origin(mouse_pos)
	var dir: Vector3  = project_ray_normal(mouse_pos)
	var to: Vector3   = from + dir * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)

	if result.is_empty():
		_ghost.visible = false
		if _range_mesh_inst != null and is_instance_valid(_range_mesh_inst):
			_range_mesh_inst.visible = false
		if _los_mesh_inst != null and is_instance_valid(_los_mesh_inst):
			_los_mesh_inst.visible = false
		return

	_ghost.visible = true
	if _range_mesh_inst != null and is_instance_valid(_range_mesh_inst):
		_range_mesh_inst.visible = true
	if _los_mesh_inst != null and is_instance_valid(_los_mesh_inst):
		_los_mesh_inst.visible = true
	var snapped := Vector3(
		snappedf(result.position.x, 2.0),
		result.position.y,
		snappedf(result.position.z, 2.0)
	)
	_ghost.global_position = snapped
	_ghost_world_pos = snapped

	var normal: Vector3 = result.normal
	var on_flat_enough: bool = normal.dot(Vector3.UP) >= build_system.SLOPE_THRESHOLD

	var valid: bool = on_flat_enough and build_system.can_place_item(snapped, _player_team, _selected_type)
	if valid != _ghost_valid:
		_ghost_valid = valid
		_apply_ghost_material(_ghost_mat_valid if valid else _ghost_mat_invalid)

	_draw_range_circle(snapped)
	_los_frame_counter += 1
	if _los_frame_counter >= 4:
		_los_frame_counter = 0
		_draw_los_fan(snapped)

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Cancel launcher targeting first; otherwise cancel placement selection
		if _launcher_hud != null and is_instance_valid(_launcher_hud) and _launcher_hud.is_targeting():
			_launcher_hud.cancel_targeting()
			get_viewport().set_input_as_handled()
			return
		if player_role == 1:
			_destroy_ghost()
			if _supporter_hud != null and is_instance_valid(_supporter_hud):
				_supporter_hud.deselect()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Launcher targeting mode takes priority over placement
		if _launcher_hud != null and is_instance_valid(_launcher_hud) and _launcher_hud.is_targeting():
			_try_fire_missile(event.position)
			return
		if player_role == 1:
			_try_place_item(event.position)

func _try_place_item(_screen_pos: Vector2) -> void:
	# Direct-cast strikes are handled via LauncherHUD targeting, not placement
	if LauncherDefs.is_direct_cast(_selected_type):
		return
	if build_system == null or not _ghost_valid:
		return
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			var assigned_name: String = build_system.place_item(_ghost_world_pos, _player_team, _selected_type, _selected_subtype)
			if assigned_name != "":
				LobbyManager.spawn_item_visuals.rpc(_ghost_world_pos, _player_team, _selected_type, _selected_subtype, assigned_name)
				LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
				LobbyManager.item_spawned.emit(_selected_type, _player_team)
		else:
			LobbyManager.request_place_item.rpc_id(1, _ghost_world_pos, _player_team, _selected_type, _selected_subtype)
	else:
		if build_system.place_item(_ghost_world_pos, _player_team, _selected_type, _selected_subtype) != "":
			LobbyManager.item_spawned.emit(_selected_type, _player_team)

func _try_fire_missile(screen_pos: Vector2) -> void:
	if _launcher_hud == null or not is_instance_valid(_launcher_hud):
		return
	# Raycast mouse to terrain
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = project_ray_origin(screen_pos)
	var dir: Vector3  = project_ray_normal(screen_pos)
	var to: Vector3   = from + dir * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return
	# Confirm target in LauncherHUD — it will emit fire_requested after spending points
	_launcher_hud.confirm_target(result.position)

func _on_fire_requested(launcher_name: String, launcher_type: String, target_pos: Vector3) -> void:
	# Find the launcher node to get its fire position
	var launcher: Node = get_tree().root.get_node_or_null("Main/" + launcher_name)
	if launcher == null:
		return
	var fire_pos: Vector3 = launcher.get_fire_position() if launcher.has_method("get_fire_position") else launcher.global_position + Vector3(0.0, 6.0, 0.0)

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_server_spawn_missile(fire_pos, target_pos, _player_team, launcher_type)
			LobbyManager.spawn_missile_visuals.rpc(fire_pos, target_pos, _player_team, launcher_type)
			LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
		else:
			LobbyManager.request_fire_missile.rpc_id(1, launcher_name, target_pos, _player_team, launcher_type)
	else:
		_server_spawn_missile(fire_pos, target_pos, _player_team, launcher_type)

func _server_spawn_missile(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	var def: Dictionary = LauncherDefs.DEFS.get(launcher_type, {})
	if def.is_empty():
		return
	var missile_scene: PackedScene = load(LauncherDefs.get_missile_scene(launcher_type)) as PackedScene
	if missile_scene == null:
		return
	var missile: Node3D = missile_scene.instantiate() as Node3D
	missile.configure(def, team, fire_pos, target_pos, launcher_type)
	get_tree().root.get_child(0).add_child(missile)
	missile.global_position = fire_pos

func _on_reveal_requested(target_pos: Vector3, reveal_radius: float, reveal_duration: float) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			LobbyManager.broadcast_recon_reveal.rpc(target_pos, reveal_radius, reveal_duration, _player_team)
			LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
		else:
			LobbyManager.request_recon_reveal.rpc_id(1, target_pos, reveal_radius, reveal_duration, _player_team)
	else:
		# Singleplayer — apply directly via Main
		var main: Node = get_node_or_null("/root/Main")
		if main != null and main.has_method("apply_recon_reveal"):
			main.apply_recon_reveal(target_pos, reveal_radius, reveal_duration)

# ── Fog of war ───────────────────────────────────────────────────────────────

func _restore_fog() -> void:
	if _fog_overlay and is_instance_valid(_fog_overlay):
		_fog_overlay.visible = false
	for node in get_tree().get_nodes_in_group("towers"):
		if is_instance_valid(node):
			node.visible = true
	for node in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(node):
			node.visible = true

func _update_fog() -> void:
	var main: Node = _main
	var player_pos := Vector3(0.0, 0.0, 84.0 if _player_team == 0 else -84.0)
	if main and main.get("fps_player") != null and is_instance_valid(main.fps_player):
		player_pos = main.fps_player.global_position

	var all_minions: Array = get_tree().get_nodes_in_group("minions")
	var all_towers: Array  = get_tree().get_nodes_in_group("towers")

	# Pre-collect friendly positions — avoids per-entity team check in inner loop
	var friendly_minion_positions: PackedVector3Array = PackedVector3Array()
	var tower_positions: Array = []

	for minion in all_minions:
		if not is_instance_valid(minion):
			continue
		var t: int = minion.get("team") if minion.get("team") != null else -1
		if t == _player_team:
			friendly_minion_positions.append(minion.global_position)

	for tower in all_towers:
		if not is_instance_valid(tower):
			continue
		var t: int = tower.get("team") if tower.get("team") != null else -1
		if t == _player_team:
			tower_positions.append(tower.global_position)

	if _fog_overlay and is_instance_valid(_fog_overlay):
		_fog_overlay.visible = true
		_fog_overlay.call("update_sources", player_pos, PLAYER_VISION_RADIUS,
				Array(friendly_minion_positions), MINION_VISION_RADIUS,
				tower_positions, 30.0)

	_apply_fog_to_group(all_towers, player_pos, friendly_minion_positions, tower_positions)
	_apply_fog_to_group(all_minions, player_pos, friendly_minion_positions, tower_positions)


func _apply_fog_to_group(nodes: Array, player_pos: Vector3, friendly_minion_positions: PackedVector3Array, friendly_tower_positions: Array) -> void:
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var node_team: int = node.get("team") if node.get("team") != null else -1
		if node_team == _player_team:
			node.visible = true
			continue
		node.visible = _is_visible_to_sources(node.global_position, player_pos, friendly_minion_positions, friendly_tower_positions)


func _is_visible_to_sources(world_pos: Vector3, player_pos: Vector3, friendly_minion_positions: PackedVector3Array, friendly_tower_positions: Array) -> bool:
	if world_pos.distance_squared_to(player_pos) <= PLAYER_VISION_RADIUS * PLAYER_VISION_RADIUS:
		return true

	var minion_vis_sq: float = MINION_VISION_RADIUS * MINION_VISION_RADIUS
	for mp in friendly_minion_positions:
		if world_pos.distance_squared_to(mp) <= minion_vis_sq:
			return true

	var tower_vision_sq: float = 30.0 * 30.0
	for tp in friendly_tower_positions:
		if world_pos.distance_squared_to(tp) <= tower_vision_sq:
			return true

	return false
