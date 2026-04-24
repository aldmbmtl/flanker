extends Node

const RESPAWN_TIME       := 15.0
const BASE_ENERGY        := 5.0
const FLICKER_SHOOT_TIME := 0.6   # how long the shoot-out flicker lasts
const FLICKER_ON_TIME    := 1.2   # how long the turn-on flicker lasts

var is_dark: bool = false
var _light: OmniLight3D = null
var _bulb_mi: MeshInstance3D = null
var _bulb_mat: StandardMaterial3D = null
var _respawn_timer: float = 0.0

# Flicker state
enum FlickerMode { NONE, SHOOTING_OUT, TURNING_ON }
var _flicker_mode: FlickerMode = FlickerMode.NONE
var _flicker_timer: float = 0.0
var _flicker_interval: float = 0.0
var _flicker_elapsed: float = 0.0

# Called by LampPlacer after building the lamp geometry
func setup(light: OmniLight3D, bulb_mi: MeshInstance3D, bulb_mat: StandardMaterial3D) -> void:
	_light    = light
	_bulb_mi  = bulb_mi
	_bulb_mat = bulb_mat

func shoot_out() -> void:
	if is_dark:
		return
	is_dark = true
	_respawn_timer = RESPAWN_TIME
	_start_flicker(FlickerMode.SHOOTING_OUT)

func _start_flicker(mode: FlickerMode) -> void:
	_flicker_mode     = mode
	_flicker_elapsed  = 0.0
	_flicker_interval = 0.05  # start fast
	_flicker_timer    = _flicker_interval
	_light.visible    = true
	_bulb_mat.emission_energy_multiplier = BASE_ENERGY

func _process(delta: float) -> void:
	# Countdown to respawn (only while dark and not currently flickering back on)
	if is_dark and _flicker_mode == FlickerMode.NONE:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_start_flicker(FlickerMode.TURNING_ON)
		return

	if _flicker_mode == FlickerMode.NONE:
		return

	_flicker_elapsed += delta
	_flicker_timer   -= delta

	var duration: float = FLICKER_SHOOT_TIME if _flicker_mode == FlickerMode.SHOOTING_OUT else FLICKER_ON_TIME
	var progress: float = _flicker_elapsed / duration  # 0→1

	# Flicker interval grows over time: fast at start, slow toward end
	_flicker_interval = lerp(0.04, 0.22, progress)

	if _flicker_timer <= 0.0:
		_flicker_timer = _flicker_interval
		# Toggle light visibility for flicker effect
		_light.visible = not _light.visible
		if _light.visible:
			# Randomise energy a bit for organic feel
			_light.light_energy = BASE_ENERGY * randf_range(0.5, 1.0)
			_bulb_mat.emission_energy_multiplier = _light.light_energy
		else:
			_bulb_mat.emission_energy_multiplier = 0.0

	if _flicker_elapsed >= duration:
		_finish_flicker()

func _finish_flicker() -> void:
	var was_shooting_out: bool = (_flicker_mode == FlickerMode.SHOOTING_OUT)
	_flicker_mode = FlickerMode.NONE
	if was_shooting_out:
		# Shooting-out flicker done → go fully dark
		_light.visible = false
		_bulb_mat.emission_energy_multiplier = 0.0
		_bulb_mat.albedo_color = Color(0.15, 0.12, 0.08)
	else:
		# Turning-on flicker done → settle to full brightness
		is_dark = false
		_light.visible = true
		_light.light_energy = BASE_ENERGY
		_bulb_mat.emission_energy_multiplier = BASE_ENERGY
		_bulb_mat.albedo_color = Color(1.0, 0.88, 0.55)
