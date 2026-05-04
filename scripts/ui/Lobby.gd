extends Control

var _my_peer_id: int = 1
var _my_ready: bool = false
var _is_host: bool = false

var _blue_list: VBoxContainer
var _red_list: VBoxContainer
var _status_label: Label
var _player_count_label: Label
var _seed_label: Label
var _ready_btn: Button
var _start_btn: Button
var _actions_bar: HBoxContainer  # stored so host button can be injected after lobby_state arrives

# Settings overlay (host only)
var _settings_overlay: Control
var _settings_seed_edit: LineEdit
var _settings_time_buttons: Array[Button] = []
var _settings_time_idx: int = 0

const TIME_OPTIONS := ["RANDOM", "SUNRISE", "NOON", "SUNSET", "NIGHT"]
const TIME_VALUES  := [-1, 0, 1, 2, 3]

const BG_COLOR     := Color(0.04, 0.05, 0.06, 0.92)
const BORDER_COLOR := Color(0.85, 0.32, 0.05, 0.6)
const TITLE_COLOR  := Color(1.0, 0.35, 0.1, 1.0)
const LABEL_COLOR  := Color(0.55, 0.45, 0.35, 1.0)

func _ready() -> void:
	_my_peer_id = BridgeClient.get_peer_id()
	_is_host = BridgeClient.is_host()

	_build_ui()

	LobbyManager.lobby_updated.connect(_on_lobby_updated)

	call_deferred("_on_lobby_updated")

func _build_ui() -> void:
	var ui_theme: Theme = load("res://assets/ui_theme.tres")

	# Full-rect dark backdrop
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# CenterContainer fills screen, centers the card
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Card panel — sized to content
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.92)
	style.border_width_left = 2
	style.border_color = Color(0.85, 0.32, 0.05, 0.6)
	style.content_margin_left   = 32
	style.content_margin_right  = 32
	style.content_margin_top    = 32
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.1, 1.0))
	title.add_theme_font_size_override("font_size", 56)
	vbox.add_child(title)

	# Player count
	_player_count_label = Label.new()
	_player_count_label.text = "0 / 10 PLAYERS"
	_player_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_count_label.add_theme_color_override("font_color", Color(0.55, 0.45, 0.35, 1.0))
	_player_count_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_player_count_label)

	# Seed
	_seed_label = Label.new()
	_seed_label.text = "SEED  —"
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_label.add_theme_color_override("font_color", Color(0.35, 0.30, 0.25, 1.0))
	_seed_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_seed_label)

	# Separator
	var sep_top := HSeparator.new()
	vbox.add_child(sep_top)

	# Team columns
	var teams_hbox := HBoxContainer.new()
	teams_hbox.add_theme_constant_override("separation", 12)
	teams_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(teams_hbox)

	# Blue column
	var blue_col := VBoxContainer.new()
	blue_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blue_col.add_theme_constant_override("separation", 6)
	teams_hbox.add_child(blue_col)

	var blue_header := Label.new()
	blue_header.text = "BLUE TEAM"
	blue_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blue_header.add_theme_color_override("font_color", Color(0.3, 0.55, 1.0, 1.0))
	blue_header.add_theme_font_size_override("font_size", 13)
	blue_col.add_child(blue_header)
	blue_col.add_child(HSeparator.new())

	_blue_list = VBoxContainer.new()
	_blue_list.add_theme_constant_override("separation", 6)
	blue_col.add_child(_blue_list)

	# Vertical divider
	teams_hbox.add_child(VSeparator.new())

	# Red column
	var red_col := VBoxContainer.new()
	red_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	red_col.add_theme_constant_override("separation", 6)
	teams_hbox.add_child(red_col)

	var red_header := Label.new()
	red_header.text = "RED TEAM"
	red_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	red_header.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	red_header.add_theme_font_size_override("font_size", 13)
	red_col.add_child(red_header)
	red_col.add_child(HSeparator.new())

	_red_list = VBoxContainer.new()
	_red_list.add_theme_constant_override("separation", 6)
	red_col.add_child(_red_list)

	# Separator
	vbox.add_child(HSeparator.new())

	# Action buttons row
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)
	_actions_bar = actions

	_ready_btn = Button.new()
	_ready_btn.text = "READY"
	_ready_btn.custom_minimum_size = Vector2(140, 44)
	_ready_btn.theme = ui_theme
	_ready_btn.pressed.connect(_on_ready_pressed)
	actions.add_child(_ready_btn)

	if _is_host:
		_start_btn = Button.new()
		_start_btn.text = "START WAR"
		_start_btn.custom_minimum_size = Vector2(160, 50)
		_start_btn.theme = ui_theme
		_start_btn.pressed.connect(_on_start_pressed)
		actions.add_child(_start_btn)

		# Build settings overlay now (while in tree with correct size)
		_settings_overlay = _build_settings_overlay(ui_theme)
		add_child(_settings_overlay)

	var switch_btn := Button.new()
	switch_btn.text = "SWITCH TEAMS"
	switch_btn.custom_minimum_size = Vector2(140, 44)
	switch_btn.theme = ui_theme
	switch_btn.pressed.connect(func() -> void:
		var current_team: int = LobbyManager.players.get(_my_peer_id, {}).get("team", 0)
		var new_team: int = 1 - current_team
		BridgeClient.send("set_team", {"team": new_team})
	)
	actions.add_child(switch_btn)

	var leave_btn := Button.new()
	leave_btn.text = "LEAVE"
	leave_btn.custom_minimum_size = Vector2(120, 44)
	leave_btn.theme = ui_theme
	leave_btn.pressed.connect(_on_leave_pressed)
	actions.add_child(leave_btn)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Waiting for players..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_status_label)

func _on_lobby_updated() -> void:
	# Re-read peer identity on every update — the first lobby_state from Python
	# assigns our peer_id and host flag (BridgeClient._local_peer_id starts at 0).
	if BridgeClient.get_peer_id() != 0:
		_my_peer_id = BridgeClient.get_peer_id()
		_is_host = BridgeClient.is_host()
	# If we just learned we are the host and the start button hasn't been built
	# yet (because _build_ui() ran before the first lobby_state arrived), create it now.
	if _is_host and _start_btn == null and _actions_bar != null:
		var ui_theme: Theme = load("res://assets/ui_theme.tres")
		_start_btn = Button.new()
		_start_btn.text = "START WAR"
		_start_btn.custom_minimum_size = Vector2(160, 50)
		_start_btn.theme = ui_theme
		_start_btn.pressed.connect(_on_start_pressed)
		_actions_bar.add_child(_start_btn)
		# Move to front so it appears before the Ready/Switch/Leave buttons
		_actions_bar.move_child(_start_btn, 0)
		if _settings_overlay == null:
			_settings_overlay = _build_settings_overlay(ui_theme)
			add_child(_settings_overlay)
	_refresh_player_list()
	_update_my_status()
	_check_can_start()
	_update_seed_label()

func _update_seed_label() -> void:
	if not _seed_label:
		return
	var seed_val: int = GameSync.game_seed
	if seed_val == 0:
		_seed_label.text = "SEED  —"
	else:
		_seed_label.text = "SEED  #%d" % seed_val

func _refresh_player_list() -> void:
	if not _blue_list or not _red_list:
		return

	for child in _blue_list.get_children():
		child.queue_free()
	for child in _red_list.get_children():
		child.queue_free()

	var ui_theme: Theme = load("res://assets/ui_theme.tres")
	for id in LobbyManager.players:
		var info: Dictionary = LobbyManager.players[id]
		var team: int = info.get("team", 0)
		var entry: HBoxContainer = _make_player_entry(id, info, ui_theme)
		if team == 0:
			_blue_list.add_child(entry)
		else:
			_red_list.add_child(entry)

func _make_player_entry(id: int, info: Dictionary, ui_theme: Theme) -> HBoxContainer:
	var row := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = info.get("name", "")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.add_theme_font_size_override("font_size", 15)
	if id == _my_peer_id:
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
	else:
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.75, 1.0))
	row.add_child(name_lbl)

	var ready_lbl := Label.new()
	var is_ready: bool = info.get("ready", false)
	ready_lbl.text = "READY" if is_ready else "—"
	ready_lbl.custom_minimum_size.x = 48.0
	ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ready_lbl.add_theme_font_size_override("font_size", 12)
	if is_ready:
		ready_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
	else:
		ready_lbl.add_theme_color_override("font_color", Color(0.35, 0.30, 0.25, 1.0))
	row.add_child(ready_lbl)

	return row

func _update_my_status() -> void:
	if not _status_label or not _player_count_label:
		return

	var player_count: int = LobbyManager.players.size()
	_player_count_label.text = "%d / 10 PLAYERS" % player_count

	var info: Dictionary = LobbyManager.players.get(_my_peer_id, {})

	if info.is_empty():
		_status_label.text = "Connecting..."
		return

	_my_ready = info.get("ready", false)
	print("[Lobby] _update_my_status: peer=", _my_peer_id, " ready=", _my_ready)

	if _my_ready:
		_status_label.text = "You are ready."
		_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
	else:
		_status_label.text = "Waiting for players..."
		_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))

	if _ready_btn:
		_ready_btn.text = "NOT READY" if _my_ready else "READY"

func _check_can_start() -> void:
	if not _is_host or not _start_btn:
		return
	_start_btn.disabled = not LobbyManager.can_start_game()

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

	var title := Label.new()
	title.text = "GAME SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var time_lbl := Label.new()
	time_lbl.text = "TIME OF DAY"
	time_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	time_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(time_lbl)

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

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var start_btn := Button.new()
	start_btn.text = "START WAR"
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
		btn.modulate = Color(1.0, 0.75, 0.3, 1.0) if i == idx else Color(1.0, 1.0, 1.0, 1.0)

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
	var chosen_time: int = TIME_VALUES[_settings_time_idx]
	BridgeClient.send("start_game", {"seed": map_seed, "time_seed": chosen_time})

func _on_ready_pressed() -> void:
	print("[Lobby] _on_ready_pressed: sending set_ready=", not _my_ready, " connected=", BridgeClient.is_connected_to_server())
	BridgeClient.send("set_ready", {"ready": not _my_ready})

func _on_start_pressed() -> void:
	if not _is_host:
		return
	_settings_seed_edit.text = str(randi_range(1, 2147483647))
	_settings_select_time(0)
	_settings_overlay.visible = true

func _on_leave_pressed() -> void:
	BridgeClient.send("player_left", {})
	queue_free()
	get_tree().change_scene_to_file("res://scenes/ui/StartMenu.tscn")
