extends Control

signal start_game
signal quit_game

const LobbyScene    := preload("res://scenes/ui/Lobby.tscn")
const TerrainScript := preload("res://scripts/TerrainGenerator.gd")
const LaneVizScript := preload("res://scripts/LaneVisualizer.gd")
const TreeScript    := preload("res://scripts/TreePlacer.gd")

var _lobby: Node
var _join_overlay: Control
var _host_overlay: Control
var _settings_overlay: Control
var _graphics_panel: Control

# Indices match TIME_VALUES
const TIME_OPTIONS := ["RANDOM", "SUNRISE", "NOON", "SUNSET", "NIGHT"]
const TIME_VALUES  := [-1, 0, 1, 2, 3]
var _settings_time_idx: int = 0
var _settings_time_buttons: Array[Button] = []
var _settings_seed_edit: LineEdit
var _settings_lives_spin: SpinBox

# Shared style constants
const BG_COLOR        := Color(0.04, 0.05, 0.06, 0.92)
const BORDER_COLOR    := Color(0.85, 0.32, 0.05, 0.6)
const TITLE_COLOR     := Color(1.0, 0.35, 0.1, 1.0)
const LABEL_COLOR     := Color(0.55, 0.45, 0.35, 1.0)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_dialogs()
	_spawn_menu_world()
	_graphics_panel = $SettingsPanelInstance
	_graphics_panel.back_pressed.connect(_on_graphics_settings_back)

func _build_dialogs() -> void:
	var ui_theme: Theme = load("res://assets/ui_theme.tres")

	_host_overlay = _build_overlay("HOST GAME", ["Port:"], ["8910"], ["PortEdit"], "Host", _on_host_confirmed, ui_theme)
	add_child(_host_overlay)

	_join_overlay = _build_overlay("JOIN GAME", ["Host IP Address:", "Port:"], ["127.0.0.1", "8910"], ["AddressEdit", "PortEdit"], "Join", _on_join_confirmed, ui_theme)
	add_child(_join_overlay)

	_settings_overlay = _build_settings_overlay(ui_theme)
	add_child(_settings_overlay)

func _build_overlay(
	title_text: String,
	labels: Array,
	placeholders: Array,
	edit_names: Array,
	confirm_text: String,
	confirm_cb: Callable,
	ui_theme: Theme
) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false

	# Dark backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)
	backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			overlay.visible = false
	)

	# CenterContainer fills screen, centers the card
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	# Card panel — sized to content
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 2
	style.border_color = BORDER_COLOR
	style.content_margin_left   = 28
	style.content_margin_right  = 28
	style.content_margin_top    = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	# Spacer
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(sp)

	# Input rows
	for i in labels.size():
		var lbl := Label.new()
		lbl.text = labels[i]
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		lbl.add_theme_font_size_override("font_size", 13)
		vbox.add_child(lbl)

		var edit := LineEdit.new()
		edit.name = edit_names[i]
		edit.placeholder_text = placeholders[i]
		if placeholders[i] != "":
			edit.text = placeholders[i]
		edit.custom_minimum_size = Vector2(320, 38)
		edit.theme = ui_theme
		vbox.add_child(edit)

	# Spacer
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(sp2)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = confirm_text.to_upper()
	confirm_btn.custom_minimum_size = Vector2(140, 44)
	confirm_btn.theme = ui_theme
	confirm_btn.pressed.connect(func() -> void:
		confirm_cb.call(overlay)
	)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.theme = ui_theme
	cancel_btn.pressed.connect(func() -> void:
		overlay.visible = false
	)
	btn_row.add_child(cancel_btn)

	return overlay

func _build_settings_overlay(ui_theme: Theme) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 2
	style.border_color = BORDER_COLOR
	style.content_margin_left   = 32
	style.content_margin_right  = 32
	style.content_margin_top    = 32
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "GAME SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Time of day label
	var time_lbl := Label.new()
	time_lbl.text = "TIME OF DAY"
	time_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	time_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(time_lbl)

	# Time buttons
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	vbox.add_child(time_row)

	_settings_time_buttons.clear()
	for i in TIME_OPTIONS.size():
		var btn := Button.new()
		btn.text = TIME_OPTIONS[i]
		btn.custom_minimum_size = Vector2(74, 38)
		btn.theme = ui_theme
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func() -> void: _settings_select_time(idx))
		time_row.add_child(btn)
		_settings_time_buttons.append(btn)
	_settings_select_time(0)

	vbox.add_child(HSeparator.new())

	# Seed label
	var seed_lbl := Label.new()
	seed_lbl.text = "MAP SEED"
	seed_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	seed_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(seed_lbl)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	vbox.add_child(seed_row)

	_settings_seed_edit = LineEdit.new()
	_settings_seed_edit.text = str(randi_range(1, 2147483647))
	_settings_seed_edit.custom_minimum_size = Vector2(0, 38)
	_settings_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_seed_edit.theme = ui_theme
	seed_row.add_child(_settings_seed_edit)

	var rand_btn := Button.new()
	rand_btn.text = "RANDOMIZE"
	rand_btn.custom_minimum_size = Vector2(120, 38)
	rand_btn.theme = ui_theme
	rand_btn.pressed.connect(func() -> void:
		_settings_seed_edit.text = str(randi_range(1, 2147483647))
	)
	seed_row.add_child(rand_btn)

	vbox.add_child(HSeparator.new())

	# Lives per team
	var lives_lbl := Label.new()
	lives_lbl.text = "LIVES PER TEAM"
	lives_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	lives_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(lives_lbl)

	_settings_lives_spin = SpinBox.new()
	_settings_lives_spin.min_value = 1
	_settings_lives_spin.max_value = 99
	_settings_lives_spin.step = 1
	_settings_lives_spin.value = GameSettings.lives_per_team
	_settings_lives_spin.custom_minimum_size = Vector2(120, 38)
	_settings_lives_spin.theme = ui_theme
	vbox.add_child(_settings_lives_spin)

	vbox.add_child(HSeparator.new())

	# Confirm / cancel
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var start_btn := Button.new()
	start_btn.text = "START"
	start_btn.custom_minimum_size = Vector2(150, 48)
	start_btn.theme = ui_theme
	start_btn.pressed.connect(_on_settings_confirmed)
	btn_row.add_child(start_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(120, 48)
	cancel_btn.theme = ui_theme
	cancel_btn.pressed.connect(func() -> void: overlay.visible = false)
	btn_row.add_child(cancel_btn)

	return overlay

func _settings_select_time(idx: int) -> void:
	_settings_time_idx = idx
	for i in _settings_time_buttons.size():
		var btn: Button = _settings_time_buttons[i]
		if i == idx:
			btn.modulate = Color(1.0, 0.75, 0.3, 1.0)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_settings_confirmed() -> void:
	_settings_overlay.visible = false
	var raw: String = _settings_seed_edit.text.strip_edges()
	var map_seed: int
	if raw.is_valid_int():
		map_seed = raw.to_int()
		if map_seed <= 0:
			map_seed = randi_range(1, 2147483647)
	else:
		map_seed = randi_range(1, 2147483647)
	GameSettings.lives_per_team = int(_settings_lives_spin.value)
	GameSettings.save_settings()
	GameSync.time_seed = TIME_VALUES[_settings_time_idx]
	GameSync.game_seed = map_seed
	LaneData.regenerate_for_new_game()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _spawn_menu_world() -> void:
	# Random seed each launch — different view every time
	GameSync.game_seed = randi_range(1, 2147483647)

	var world: Node3D = $World3D

	# Terrain (StaticBody3D, builds HeightMapShape3D + mesh in _ready)
	var terrain := StaticBody3D.new()
	terrain.set_script(TerrainScript)
	terrain.name = "Terrain"
	world.add_child(terrain)

	# Lane ribbon visuals
	var lane_viz := Node3D.new()
	lane_viz.set_script(LaneVizScript)
	lane_viz.name = "LaneVisualizer"
	world.add_child(lane_viz)

	# Trees — low density for menu background performance
	var trees := Node3D.new()
	trees.set_script(TreeScript)
	trees.name = "TreePlacer"
	# Must set before add_child so _ready() sees the override
	trees.set("menu_density", 0.1)
	world.add_child(trees)

	# Reset seed to 0 so multiplayer seed guard works correctly if RPC is missed
	GameSync.game_seed = 0

func _on_host_pressed() -> void:
	_host_overlay.visible = true

func _on_join_pressed() -> void:
	_join_overlay.visible = true

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_settings_pressed() -> void:
	_graphics_panel.visible = true

func _on_graphics_settings_back() -> void:
	_graphics_panel.visible = false

func _on_local_pressed() -> void:
	_settings_seed_edit.text = str(randi_range(1, 2147483647))
	_settings_select_time(0)
	_settings_overlay.visible = true

func _on_host_confirmed(overlay: Control) -> void:
	var port_edit: LineEdit = overlay.find_child("PortEdit", true, false)
	var port_text: String = port_edit.text.strip_edges() if port_edit else ""
	var port: int = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT

	var err: int = NetworkManager.start_host(port)
	if err != OK:
		_show_connection_status("Failed to host: port may be in use")
		return

	overlay.visible = false
	# Host registers itself directly — no RPC needed, peer id 1 is always the server
	LobbyManager.register_player_local(1, "Host")
	_show_lobby()

func _on_join_confirmed(overlay: Control) -> void:
	var address_edit: LineEdit = overlay.find_child("AddressEdit", true, false)
	var port_edit: LineEdit = overlay.find_child("PortEdit", true, false)

	var address: String = address_edit.text.strip_edges() if address_edit else ""
	var port_text: String = port_edit.text.strip_edges() if port_edit else ""

	if address.is_empty():
		_show_connection_status("Enter host IP address")
		return

	var port: int = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT

	overlay.visible = false
	_show_connection_status("Connecting...")
	var err: int = NetworkManager.join_game(address, port)
	if err != OK:
		_show_connection_status("Failed to connect")
		return

	NetworkManager.connected_to_server.connect(_on_connected_to_lobby, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)

func _on_connected_to_lobby() -> void:
	# Send a default name to the server — server uses get_remote_sender_id() to know who we are
	LobbyManager.register_player.rpc_id(1, "Player")
	_show_lobby()

func _on_connection_failed() -> void:
	_show_connection_status("Connection failed")

func _show_lobby() -> void:
	visible = false
	_lobby = LobbyScene.instantiate()
	get_tree().root.add_child(_lobby)

func _show_connection_status(msg: String) -> void:
	var status: Label = $ConnectionStatus
	status.text = msg
	status.visible = true
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(status, "visible", false, 0.0)
