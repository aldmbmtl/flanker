extends Control

var _my_peer_id: int = 1
var _my_team: int = 0
var _my_role: String = ""
var _my_ready: bool = false
var _is_host: bool = false
var _role_buttons: Array = []

func _ready() -> void:
	_my_peer_id = multiplayer.get_unique_id()
	_is_host = NetworkManager.is_host()
	_update_host_ui()
	
	LobbyManager.lobby_updated.connect(_on_lobby_updated)
	LobbyManager.game_start_requested.connect(_on_game_start_requested)
	
	_build_role_dialog()
	call_deferred("_on_lobby_updated")

func _update_host_ui() -> void:
	var start_btn: Button = $VBox/Actions/StartButton
	start_btn.visible = _is_host

func _build_role_dialog() -> void:
	var container: VBoxContainer = $RoleDialog/RoleList
	for child in container.get_children():
		child.queue_free()
	_role_buttons.clear()
	
	for role in LobbyManager.ROLES:
		var btn := CheckBox.new()
		btn.text = role
		btn.toggled.connect(_on_role_toggled.bind(role))
		container.add_child(btn)
		_role_buttons.append(btn)

func _on_role_toggled(pressed: bool, role: String) -> void:
	if not pressed:
		return
	for btn in _role_buttons:
		if btn.text != role:
			btn.set_pressed_no_signal(false)
	_my_role = role
	LobbyManager.set_role.rpc_id(1, role)

func _on_lobby_updated() -> void:
	_refresh_player_list()
	_update_my_status()
	_check_can_start()

func _refresh_player_list() -> void:
	var blue_list: VBoxContainer = $VBox/HSplit/TeamsContainer/BlueTeam/PlayerList0
	var red_list: VBoxContainer = $VBox/HSplit/TeamsContainer/RedTeam/PlayerList1
	
	for child in blue_list.get_children():
		child.queue_free()
	for child in red_list.get_children():
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
		blue_list.add_child(entry)
	for entry in red_players:
		red_list.add_child(entry)
	
	_ensure_empty_slots(blue_list, 5)
	_ensure_empty_slots(red_list, 5)

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
	
	var is_me := id == _my_peer_id
	if is_me:
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
	var status: Label = $VBox/StatusLabel
	var info: Dictionary = LobbyManager.players.get(_my_peer_id, {})
	
	if info.is_empty():
		status.text = "Connecting..."
		return
	
	_my_team = info.team
	_my_role = info.role
	_my_ready = info.ready
	
	var parts: Array = []
	parts.append("Team: %s" % ("BLUE" if _my_team == 0 else "RED"))
	parts.append(" | Role: %s" % (_my_role if _my_role != "" else "None"))
	parts.append(" | %s" % ("Ready" if _my_ready else "Not Ready"))
	
	var player_count: int = LobbyManager.players.size()
	parts.append(" | %d/10 players" % player_count)
	
	status.text = " ".join(parts)
	_update_role_buttons()

func _update_role_buttons() -> void:
	for btn in _role_buttons:
		btn.set_pressed_no_signal(btn.text == _my_role)
	
	var role_btn: Button = $VBox/Actions/RoleButton
	role_btn.text = _my_role if _my_role != "" else "Select Role"
	
	var ready_btn: Button = $VBox/Actions/ReadyButton
	ready_btn.text = "Not Ready" if _my_ready else "Ready"
	if _my_ready:
		ready_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
	else:
		ready_btn.remove_theme_color_override("font_color")

func _check_can_start() -> void:
	if not _is_host:
		return
	var can_start: bool = LobbyManager.can_start_game()
	$VBox/Actions/StartButton.disabled = not can_start

func _on_switch_team_pressed() -> void:
	var new_team := 1 - _my_team
	LobbyManager.set_team.rpc_id(1, new_team)

func _on_role_pressed() -> void:
	$RoleDialog.popup_centered()

func _on_ready_pressed() -> void:
	var new_ready := not _my_ready
	LobbyManager.set_ready.rpc_id(1, new_ready)

func _on_start_pressed() -> void:
	if not _is_host:
		return
	LobbyManager.request_start_game.rpc_id(1)

func _on_game_start_requested() -> void:
	LobbyManager.load_game_scene.rpc_id(1, "res://scenes/Main.tscn")

func _on_leave_pressed() -> void:
	NetworkManager.close_connection()
	queue_free()
	get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")