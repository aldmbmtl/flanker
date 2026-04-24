extends Control

var _my_peer_id: int = 1
var _my_team: int = 0
var _my_role: String = ""
var _my_ready: bool = false
var _is_host: bool = false
var _role_buttons: Array = []

# Built in _ready — no scene tree deps
var _blue_list: VBoxContainer
var _red_list: VBoxContainer
var _status_label: Label
var _role_btn: Button
var _ready_btn: Button
var _start_btn: Button
var _role_dialog: AcceptDialog
var _role_list: VBoxContainer

func _ready() -> void:
	_my_peer_id = multiplayer.get_unique_id()
	_is_host = NetworkManager.is_host()

	_build_ui()
	_build_role_dialog()

	LobbyManager.lobby_updated.connect(_on_lobby_updated)
	LobbyManager.game_start_requested.connect(_on_game_start_requested)

	call_deferred("_on_lobby_updated")

func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centered VBox
	var vbox := VBoxContainer.new()
	vbox.set_anchor_and_offset(SIDE_LEFT,   0.5, -450)
	vbox.set_anchor_and_offset(SIDE_RIGHT,  0.5,  450)
	vbox.set_anchor_and_offset(SIDE_TOP,    0.5, -300)
	vbox.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  300)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.1, 1))
	title.add_theme_font_size_override("font_size", 60)
	vbox.add_child(title)

	# Connection info
	var info := Label.new()
	info.text = "Share your IP and port with friends"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	vbox.add_child(info)

	# Teams row
	var teams := HBoxContainer.new()
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(teams)

	# Blue team column
	var blue_col := VBoxContainer.new()
	blue_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blue_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	teams.add_child(blue_col)

	var blue_hdr := Label.new()
	blue_hdr.text = "BLUE TEAM"
	blue_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blue_hdr.add_theme_color_override("font_color", Color(0.3, 0.5, 1.0, 1))
	blue_hdr.add_theme_font_size_override("font_size", 24)
	blue_col.add_child(blue_hdr)

	_blue_list = VBoxContainer.new()
	_blue_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blue_col.add_child(_blue_list)

	# Separator
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(20, 0)
	teams.add_child(sep)

	# Red team column
	var red_col := VBoxContainer.new()
	red_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	red_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	teams.add_child(red_col)

	var red_hdr := Label.new()
	red_hdr.text = "RED TEAM"
	red_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	red_hdr.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1))
	red_hdr.add_theme_font_size_override("font_size", 24)
	red_col.add_child(red_hdr)

	_red_list = VBoxContainer.new()
	_red_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	red_col.add_child(_red_list)

	# Horizontal separator
	vbox.add_child(HSeparator.new())

	# Action buttons row
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions)

	var spacer_l := Control.new()
	spacer_l.custom_minimum_size = Vector2(100, 0)
	actions.add_child(spacer_l)

	var switch_btn := Button.new()
	switch_btn.text = "Switch Team"
	switch_btn.custom_minimum_size = Vector2(140, 40)
	switch_btn.pressed.connect(_on_switch_team_pressed)
	actions.add_child(switch_btn)

	var spacer_r := Control.new()
	spacer_r.custom_minimum_size = Vector2(20, 0)
	actions.add_child(spacer_r)

	_role_btn = Button.new()
	_role_btn.text = "Select Role"
	_role_btn.custom_minimum_size = Vector2(160, 40)
	_role_btn.pressed.connect(_on_role_pressed)
	actions.add_child(_role_btn)

	var spacer_r2 := Control.new()
	spacer_r2.custom_minimum_size = Vector2(20, 0)
	actions.add_child(spacer_r2)

	_ready_btn = Button.new()
	_ready_btn.text = "Ready"
	_ready_btn.custom_minimum_size = Vector2(120, 40)
	_ready_btn.pressed.connect(_on_ready_pressed)
	actions.add_child(_ready_btn)

	var spacer_r3 := Control.new()
	spacer_r3.custom_minimum_size = Vector2(60, 0)
	actions.add_child(spacer_r3)

	_start_btn = Button.new()
	_start_btn.text = "Start War"
	_start_btn.custom_minimum_size = Vector2(160, 50)
	_start_btn.visible = _is_host
	_start_btn.pressed.connect(_on_start_pressed)
	actions.add_child(_start_btn)

	var spacer_l2 := Control.new()
	spacer_l2.custom_minimum_size = Vector2(20, 0)
	actions.add_child(spacer_l2)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.custom_minimum_size = Vector2(120, 40)
	leave_btn.pressed.connect(_on_leave_pressed)
	actions.add_child(leave_btn)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Waiting for players..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	vbox.add_child(_status_label)

func _build_role_dialog() -> void:
	_role_dialog = AcceptDialog.new()
	_role_dialog.title = "Select Role"
	_role_dialog.size = Vector2i(300, 350)
	_role_dialog.unresizable = true
	_role_dialog.ok_button_text = "Confirm"
	_role_dialog.dialog_hide_on_ok = false
	_role_dialog.visible = false
	add_child(_role_dialog)

	_role_list = VBoxContainer.new()
	_role_dialog.add_child(_role_list)

	_role_buttons.clear()
	for role in LobbyManager.ROLES:
		var btn := CheckBox.new()
		btn.text = role
		btn.toggled.connect(_on_role_toggled.bind(role))
		_role_list.add_child(btn)
		_role_buttons.append(btn)

func _on_role_toggled(pressed: bool, role: String) -> void:
	if not pressed:
		return
	for btn in _role_buttons:
		if btn.text != role:
			btn.set_pressed_no_signal(false)
	_my_role = role
	if _is_host:
		LobbyManager.set_role(role)
	else:
		LobbyManager.set_role.rpc_id(1, role)

func _on_lobby_updated() -> void:
	_refresh_player_list()
	_update_my_status()
	_check_can_start()

func _refresh_player_list() -> void:
	if not _blue_list or not _red_list:
		return

	for child in _blue_list.get_children():
		child.queue_free()
	for child in _red_list.get_children():
		child.queue_free()

	var blue_players: Array = []
	var red_players: Array = []

	for id in LobbyManager.players:
		var info: Dictionary = LobbyManager.players[id]
		var entry := _make_player_entry(id, info)
		if info.team == 0:
			blue_players.append(entry)
		else:
			red_players.append(entry)

	for entry in blue_players:
		_blue_list.add_child(entry)
	for entry in red_players:
		_red_list.add_child(entry)

	_ensure_empty_slots(_blue_list, 5)
	_ensure_empty_slots(_red_list, 5)

func _make_player_entry(id: int, info: Dictionary) -> HBoxContainer:
	var container := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = info.name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_lbl)

	var role_lbl := Label.new()
	role_lbl.text = info.role if info.role != "" else "—"
	role_lbl.custom_minimum_size.x = 80.0
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(role_lbl)

	var ready_lbl := Label.new()
	ready_lbl.text = "✓" if info.ready else "○"
	ready_lbl.custom_minimum_size.x = 30.0
	if info.ready:
		ready_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
	else:
		ready_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(ready_lbl)

	if id == _my_peer_id:
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1))

	return container

func _ensure_empty_slots(list: VBoxContainer, count: int) -> void:
	var current := list.get_child_count()
	for i in range(current, count):
		var empty := Label.new()
		empty.text = "— Empty —"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
		list.add_child(empty)

func _update_my_status() -> void:
	if not _status_label:
		return
	var info: Dictionary = LobbyManager.players.get(_my_peer_id, {})

	if info.is_empty():
		_status_label.text = "Connecting..."
		return

	_my_team = info.team
	_my_role = info.role
	_my_ready = info.ready

	var parts: Array = []
	parts.append("Team: %s" % ("BLUE" if _my_team == 0 else "RED"))
	parts.append(" | Role: %s" % (_my_role if _my_role != "" else "None"))
	parts.append(" | %s" % ("Ready" if _my_ready else "Not Ready"))
	parts.append(" | %d/10 players" % LobbyManager.players.size())

	_status_label.text = " ".join(parts)
	_update_role_buttons()

func _update_role_buttons() -> void:
	for btn in _role_buttons:
		btn.set_pressed_no_signal(btn.text == _my_role)

	if _role_btn:
		_role_btn.text = _my_role if _my_role != "" else "Select Role"

	if _ready_btn:
		_ready_btn.text = "Not Ready" if _my_ready else "Ready"
		if _my_ready:
			_ready_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
		else:
			_ready_btn.remove_theme_color_override("font_color")

func _check_can_start() -> void:
	if not _is_host or not _start_btn:
		return
	_start_btn.disabled = not LobbyManager.can_start_game()

func _on_switch_team_pressed() -> void:
	if _is_host:
		LobbyManager.set_team(1 - _my_team)
	else:
		LobbyManager.set_team.rpc_id(1, 1 - _my_team)

func _on_role_pressed() -> void:
	_role_dialog.popup_centered()

func _on_ready_pressed() -> void:
	if _is_host:
		LobbyManager.set_ready(not _my_ready)
	else:
		LobbyManager.set_ready.rpc_id(1, not _my_ready)

func _on_start_pressed() -> void:
	if not _is_host:
		return
	LobbyManager.request_start_game()

func _on_game_start_requested() -> void:
	queue_free()
	if _is_host:
		LobbyManager.start_game("res://scenes/Main.tscn")

func _on_leave_pressed() -> void:
	NetworkManager.close_connection()
	queue_free()
	get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")
