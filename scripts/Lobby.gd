extends Control

var _my_peer_id: int = 1
var _my_ready: bool = false
var _is_host: bool = false

var _player_list: VBoxContainer
var _status_label: Label
var _player_count_label: Label
var _seed_label: Label
var _ready_btn: Button
var _start_btn: Button

func _ready() -> void:
	_my_peer_id = multiplayer.get_unique_id()
	_is_host = NetworkManager.is_host()

	_build_ui()

	LobbyManager.lobby_updated.connect(_on_lobby_updated)
	LobbyManager.game_start_requested.connect(_on_game_start_requested)

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
	panel.custom_minimum_size = Vector2(480, 0)

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

	# Player list
	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 6)
	_player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_player_list)

	# Separator
	vbox.add_child(HSeparator.new())

	# Action buttons row
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)

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
	if not _player_list:
		return

	for child in _player_list.get_children():
		child.queue_free()

	for id in LobbyManager.players:
		var info: Dictionary = LobbyManager.players[id]
		_player_list.add_child(_make_player_entry(id, info))

func _make_player_entry(id: int, info: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = info.name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.add_theme_font_size_override("font_size", 15)
	if id == _my_peer_id:
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
	else:
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.75, 1.0))
	row.add_child(name_lbl)

	var ready_lbl := Label.new()
	ready_lbl.text = "READY" if info.ready else "—"
	ready_lbl.custom_minimum_size.x = 60.0
	ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ready_lbl.add_theme_font_size_override("font_size", 12)
	if info.ready:
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

	_my_ready = info.ready

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

func _on_ready_pressed() -> void:
	if _is_host:
		LobbyManager.set_ready(not _my_ready)
	else:
		LobbyManager.set_ready.rpc_id(1, not _my_ready)

func _on_start_pressed() -> void:
	if not _is_host:
		return
	LobbyManager.start_game("res://scenes/Main.tscn")

func _on_game_start_requested() -> void:
	queue_free()

func _on_leave_pressed() -> void:
	NetworkManager.close_connection()
	queue_free()
	get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")
