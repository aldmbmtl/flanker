extends Camera3D

const PAN_SPEED := 20.0
const ZOOM_SPEED := 5.0
const MIN_SIZE := 10.0
const MAX_SIZE := 60.0

var build_system: Node = null

func _ready() -> void:
	build_system = get_node_or_null("/root/Main/BuildSystem")

func _process(delta: float) -> void:
	if not current:
		return
	_handle_pan(delta)
	_handle_zoom(delta)

func _handle_pan(delta: float) -> void:
	var move := Vector3.ZERO
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

func _handle_zoom(delta: float) -> void:
	pass  # handled in _unhandled_input

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	# Zoom with scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			size = max(MIN_SIZE, size - ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size = min(MAX_SIZE, size + ZOOM_SPEED)
		# Place tower on left click
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_place_tower(event.position)

func _try_place_tower(screen_pos: Vector2) -> void:
	if build_system == null:
		build_system = get_node_or_null("/root/Main/BuildSystem")
	if build_system == null:
		return
	# Raycast from orthographic camera to ground plane (y=0)
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return
	var t := -from.y / dir.y
	var world_pos := from + dir * t
	build_system.place_tower(world_pos)
