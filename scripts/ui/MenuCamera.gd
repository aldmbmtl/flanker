extends Camera3D

# Cinematic hotspot patrol camera for the start menu.
# Slowly travels between 5 interesting positions across the map, dwelling at
# each spot and smoothly lerping to the next. FOV breathes slightly.

# Each hotspot: [camera_position, look_at_target, dwell_time_seconds]
const HOTSPOTS: Array = [
	# Mid-lane clash — looking down the centre from blue side
	[Vector3(0.0, 28.0, 55.0),   Vector3(0.0,  4.0,  0.0),  12.0],
	# Left lane fight — offset view from the mountain flank
	[Vector3(-70.0, 22.0, 20.0), Vector3(-60.0, 3.0, -10.0), 10.0],
	# Red base overview — wide shot from high up
	[Vector3(30.0, 45.0, -95.0), Vector3(0.0,  0.0, -70.0),  11.0],
	# Right lane — low dramatic angle along the lane
	[Vector3(72.0, 18.0, -5.0),  Vector3(72.0, 2.0,  30.0),  10.0],
	# Blue base — sweeping overhead shot
	[Vector3(-25.0, 50.0, 95.0), Vector3(0.0,  0.0,  70.0),  11.0],
]

const TRANSITION_TIME := 4.0   # seconds to lerp between hotspots
const FOV_BASE := 62.0
const FOV_RANGE := 6.0
const FOV_SPEED := 0.08

var _hotspot_idx: int = 0
var _dwell_timer: float = 0.0
var _transition_timer: float = -1.0   # -1 = dwelling, >=0 = transitioning
var _from_pos: Vector3
var _from_target: Vector3
var _to_pos: Vector3
var _to_target: Vector3
var _current_target: Vector3
var _fov_time: float = 0.0

func _ready() -> void:
	# Start at first hotspot immediately
	var h: Array = HOTSPOTS[0]
	position = h[0]
	_current_target = h[1]
	look_at(_current_target)
	fov = FOV_BASE
	_dwell_timer = h[2]

func _process(delta: float) -> void:
	_fov_time += delta
	fov = FOV_BASE + sin(_fov_time * FOV_SPEED) * FOV_RANGE

	if _transition_timer >= 0.0:
		# Transitioning to next hotspot
		_transition_timer += delta
		var t: float = clampf(_transition_timer / TRANSITION_TIME, 0.0, 1.0)
		var smooth_t: float = t * t * (3.0 - 2.0 * t)  # smoothstep
		position = _from_pos.lerp(_to_pos, smooth_t)
		_current_target = _from_target.lerp(_to_target, smooth_t)
		look_at(_current_target)
		if _transition_timer >= TRANSITION_TIME:
			# Arrived — start dwelling
			_transition_timer = -1.0
			var h: Array = HOTSPOTS[_hotspot_idx]
			_dwell_timer = h[2]
	else:
		# Dwelling — gentle look sway so it feels alive
		var sway: Vector3 = Vector3(
			sin(_fov_time * 0.07) * 1.5,
			sin(_fov_time * 0.05) * 0.8,
			0.0
		)
		look_at(_current_target + sway)
		_dwell_timer -= delta
		if _dwell_timer <= 0.0:
			_start_transition()

func _start_transition() -> void:
	var next_idx: int = (_hotspot_idx + 1) % HOTSPOTS.size()
	_from_pos    = position
	_from_target = _current_target
	var h: Array = HOTSPOTS[next_idx]
	_to_pos    = h[0]
	_to_target = h[1]
	_hotspot_idx = next_idx
	_transition_timer = 0.0
