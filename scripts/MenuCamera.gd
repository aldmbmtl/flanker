extends Camera3D

const PAN_RADIUS := 120.0
const PAN_HEIGHT := 60.0
const PAN_SPEED := 0.15

var _time := 0.0

func _ready() -> void:
	position = Vector3(PAN_RADIUS, PAN_HEIGHT, 0.0)
	look_at(Vector3.ZERO)

func _process(delta: float) -> void:
	_time += delta * PAN_SPEED
	var angle: float = _time
	position.x = cos(angle) * PAN_RADIUS
	position.z = sin(angle) * PAN_RADIUS
	position.y = PAN_HEIGHT + sin(_time * 2.0) * 8.0
	look_at(Vector3.ZERO)