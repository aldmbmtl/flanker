extends Camera3D

const PAN_SPEED := 20.0
const ZOOM_SPEED := 5.0
const MIN_FOV := 30.0
const MAX_FOV := 100.0

var build_system: Node = null
var _panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO

func _ready() -> void:
	build_system = get_node_or_null("/root/Main/BuildSystem")
	rotation.x = -PI / 4.0
	rotation.y = PI

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return

	# Zoom with scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fov = max(MIN_FOV, fov - ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fov = min(MAX_FOV, fov + ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_panning = true
			_pan_start = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			_panning = false
	elif event is InputEventMouseMotion and _panning:
		var diff: Vector2 = event.position - _pan_start
		_pan_start = event.position
		global_position.x -= diff.x * 0.1
		global_position.z -= diff.y * 0.1

	# Place tower on left click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place_tower(event.position)

func _try_place_tower(screen_pos: Vector2) -> void:
	if build_system == null:
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = project_ray_origin(screen_pos)
	var dir: Vector3 = project_ray_normal(screen_pos)
	var to: Vector3 = from + dir * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return
	var player_team: int = 0
	var main: Node = get_node_or_null("/root/Main")
	if main and main.has_method("get") and main.get("fps_player") != null:
		player_team = main.fps_player.player_team
	build_system.place_tower(result.position, player_team)