extends Camera3D

const ORBIT_RADIUS := 130.0
const ORBIT_HEIGHT := 80.0
const ORBIT_SPEED  := 0.06   # radians per second — slow cinematic pan

# Slight vertical bob so it feels alive
const BOB_AMPLITUDE := 6.0
const BOB_SPEED     := 0.18

# FOV breathe
const FOV_BASE := 68.0
const FOV_RANGE := 5.0
const FOV_SPEED := 0.12

var _time := 0.0

func _ready() -> void:
	_update_position(0.0)

func _process(delta: float) -> void:
	_time += delta
	_update_position(_time)

func _update_position(t: float) -> void:
	var angle: float = t * ORBIT_SPEED
	var height: float = ORBIT_HEIGHT + sin(t * BOB_SPEED) * BOB_AMPLITUDE
	position = Vector3(cos(angle) * ORBIT_RADIUS, height, sin(angle) * ORBIT_RADIUS)
	# Look at a point slightly above the map center so we see the terrain
	look_at(Vector3(0.0, 8.0, 0.0))
	fov = FOV_BASE + sin(t * FOV_SPEED) * FOV_RANGE
