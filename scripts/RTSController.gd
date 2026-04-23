extends Camera3D

const PAN_SPEED := 20.0
const ZOOM_SPEED := 5.0
const MIN_FOV := 30.0
const MAX_FOV := 100.0
const TILT_SPEED := 0.005
const MIN_TILT_PITCH := -0.5
const MAX_TILT_PITCH := 0.5
const MIN_TILT_YAW := -0.3
const MAX_TILT_YAW := 0.3

var build_system: Node = null
var _tilting: bool = false
var _tilt_mouse_start: Vector2 = Vector2.ZERO

func _ready() -> void:
	build_system = get_node_or_null("/root/Main/BuildSystem")

func _process(delta: float) -> void:
	if not current:
		return
	_handle_pan(delta)
	_handle_tilt(delta)

func _handle_pan(delta: float) -> void:
	var move: Vector3 = Vector3.ZERO
	if Input.is_action_pressed("rts_pan_up"):
		move.z -= 1
	if Input.is_action_pressed("rts_pan_down"):
		move.z += 1
	if Input.is_action_pressed("rts_pan_left"):
		move.x -= 1
	if Input.is_action_pressed("rts_pan_right"):
		move.x += 1
	if move.length() > 0:
		move = move.normalized() * PAN_SPEED * delta
		global_position += move

func _handle_tilt(delta: float) -> void:
	if _tilting:
		var input_x: float = 0.0
		var input_y: float = 0.0
		if Input.is_action_pressed("rts_pan_up"):
			input_y -= 1
		if Input.is_action_pressed("rts_pan_down"):
			input_y += 1
		if Input.is_action_pressed("rts_pan_left"):
			input_x -= 1
		if Input.is_action_pressed("rts_pan_right"):
			input_x += 1

		var delta_rot: Vector3 = Vector3(-input_y * TILT_SPEED * delta, -input_x * TILT_SPEED * delta, 0.0)
		rotation.x = clamp(rotation.x + delta_rot.x, MIN_TILT_PITCH, MAX_TILT_PITCH)
		rotation.y = clamp(rotation.y + delta_rot.y, MIN_TILT_YAW, MAX_TILT_YAW)

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return

	# Zoom with scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fov = max(MIN_FOV, fov - ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fov = min(MAX_FOV, fov + ZOOM_SPEED)

		# Start tilt with right click
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_tilting = true
			_tilt_mouse_start = event.position

		# Stop tilt
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			_tilting = false

	elif event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_RIGHT:
		if _tilting:
			var diff: Vector2 = event.position - _tilt_mouse_start
			_tilt_mouse_start = event.position
			rotation.x = clamp(rotation.x - diff.y * TILT_SPEED, MIN_TILT_PITCH, MAX_TILT_PITCH)
			rotation.y = clamp(rotation.y + diff.x * TILT_SPEED, MIN_TILT_YAW, MAX_TILT_YAW)

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