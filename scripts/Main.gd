extends Node

var game_over := false
var fps_mode := true

@onready var fps_player: CharacterBody3D = $FPSPlayer
@onready var rts_camera: Camera3D = $RTSCamera
@onready var mode_label: Label = $HUD/ModeLabel
@onready var game_over_label: Label = $HUD/GameOverLabel
@onready var wave_info_label: Label = $HUD/WaveInfoLabel
@onready var wave_announce_label: Label = $HUD/WaveAnnounceLabel
@onready var crosshair: Control = $HUD/Crosshair

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_bases()
	_set_mode(true)
	get_tree().set_auto_accept_quit(true)
	wave_announce_label.visible = false
	wave_info_label.text = "Wave: 0 | First wave in: 30s"
	# Wire reload bar to FPS controller
	fps_player.reload_bar = $HUD/Crosshair/ReloadBar

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
			if not game_over:
				_set_mode(!fps_mode)

func _set_mode(is_fps: bool) -> void:
	fps_mode = is_fps
	fps_player.set_active(is_fps)
	rts_camera.current = !is_fps
	crosshair.visible = is_fps
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
