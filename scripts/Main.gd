extends Node

const RESPAWN_DELAY := 5.0
# Blue base spawn point (same z offset as FPSPlayer start)
const BLUE_SPAWN := Vector3(0.0, 10.0, 70.0)

var game_over := false
var fps_mode := true
var _respawn_timer := 0.0
var _respawning := false

@onready var fps_player: CharacterBody3D = $FPSPlayer
@onready var rts_camera: Camera3D = $RTSCamera
@onready var mode_label: Label = $HUD/ModeLabel
@onready var game_over_label: Label = $HUD/GameOverLabel
@onready var wave_info_label: Label = $HUD/WaveInfoLabel
@onready var wave_announce_label: Label = $HUD/WaveAnnounceLabel
@onready var crosshair: Control = $HUD/Crosshair
@onready var respawn_label: Label = $HUD/RespawnLabel
@onready var minimap: Control = $HUD/Minimap

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_bases()
	_set_mode(true)
	get_tree().set_auto_accept_quit(true)
	wave_announce_label.visible = false
	wave_info_label.text = "Wave: 0 | First wave in: 30s"
	# Wire reload bar and health bar to FPS controller
	fps_player.reload_bar = $HUD/Crosshair/ReloadBar
	fps_player.health_bar = $HUD/HealthBar
	fps_player.connect("died", _on_player_died)

func _process(delta: float) -> void:
	if _respawning:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_do_respawn()
		else:
			respawn_label.text = "Respawning in %d..." % (int(_respawn_timer) + 1)

func _setup_bases() -> void:
	var blue_base = $World/BlueBase/BlueBaseInst
	var red_base = $World/RedBase/RedBaseInst
	if blue_base and blue_base.has_method("setup"):
		blue_base.setup(0)
	if red_base and red_base.has_method("setup"):
		red_base.setup(1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			get_tree().quit()
			return
		if event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB:
			if not game_over and not _respawning:
				_set_mode(!fps_mode)

func _set_mode(is_fps: bool) -> void:
	fps_mode = is_fps
	fps_player.set_active(is_fps)
	rts_camera.current = !is_fps
	crosshair.visible = is_fps
	minimap.visible = is_fps
	if is_fps:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mode_label.text = "Mode: FPS  [Tab] to switch"
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mode_label.text = "Mode: RTS  [Tab] to switch  [LMB] place tower  [Scroll] zoom"

func game_over_signal(winner: String) -> void:
	if game_over:
		return
	game_over = true
	game_over_label.text = winner + " WINS!\n[Esc] to quit"
	game_over_label.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func update_wave_info(wave_num: int, next_in: int) -> void:
	if wave_num == 0:
		wave_info_label.text = "First wave in: %ds" % next_in
	else:
		wave_info_label.text = "Wave: %d | Next in: %ds" % [wave_num, next_in]

func show_wave_announcement(wave_num: int) -> void:
	wave_announce_label.text = "— WAVE %d —" % wave_num
	wave_announce_label.modulate.a = 1.0
	wave_announce_label.visible = true
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(wave_announce_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): wave_announce_label.visible = false)

func _on_player_died() -> void:
	if game_over:
		return
	_respawning = true
	_respawn_timer = RESPAWN_DELAY
	respawn_label.visible = true
	crosshair.visible = false
	# Switch to RTS view while dead so the player isn't staring at the ground
	rts_camera.current = true
	fps_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mode_label.text = "DEAD — respawning..."

func _do_respawn() -> void:
	_respawning = false
	respawn_label.visible = false
	fps_player.respawn(BLUE_SPAWN)
	_set_mode(true)
