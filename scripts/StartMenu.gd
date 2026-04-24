extends Control

signal start_game
signal quit_game
signal host_started(port: int, player_name: String)
signal join_requested(address: String, port: int, player_name: String)

const LobbyScene := preload("res://scenes/Lobby.tscn")

var _lobby: Node
var _player_name := ""

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_host_pressed() -> void:
	$HostDialog.show()

func _on_join_pressed() -> void:
	$JoinDialog.show()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_host_confirmed() -> void:
	var port_edit: LineEdit = $HostDialog/VBoxContainer/PortEdit
	var name_edit: LineEdit = $HostDialog/VBoxContainer/NameEdit
	
	var port_text: String = port_edit.text.strip_edges()
	var name_text: String = name_edit.text.strip_edges()
	
	var port: int = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	_player_name = name_text if name_text.length() > 0 else "Host"
	
	var err: int = NetworkManager.start_host(port)
	if err != OK:
		_show_connection_status("Failed to host: port may be in use")
		return
	
	LobbyManager.register_player.rpc_id(1, _player_name)
	_show_lobby()

func _on_join_confirmed() -> void:
	var address_edit: LineEdit = $JoinDialog/VBoxContainer/AddressEdit
	var port_edit: LineEdit = $JoinDialog/VBoxContainer/PortEdit
	var name_edit: LineEdit = $JoinDialog/VBoxContainer/NameEdit
	
	var address: String = address_edit.text.strip_edges()
	var port_text: String = port_edit.text.strip_edges()
	var name_text: String = name_edit.text.strip_edges()
	
	if address.is_empty():
		_show_connection_status("Enter host IP address")
		return
	
	var port: int = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	_player_name = name_text if name_text.length() > 0 else "Player"
	
	_show_connection_status("Connecting...")
	var err: int = NetworkManager.join_game(address, port)
	if err != OK:
		_show_connection_status("Failed to connect")
		return
	
	NetworkManager.connected_to_server.connect(_on_connected_to_lobby, CONNECT_ONE_SHOT)

func _on_connected_to_lobby() -> void:
	register_player.rpc_id(1, _player_name)
	_show_lobby()

@rpc("any_peer", "reliable")
func register_player(new_player_name: String) -> void:
	if not multiplayer.is_server():
		return
	LobbyManager.register_player.rpc(new_player_name)

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