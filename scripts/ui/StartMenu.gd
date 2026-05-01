extends Control

signal quit_game

const LobbyScene          := preload("res://scenes/ui/Lobby.tscn")
const TerrainScript       := preload("res://scripts/TerrainGenerator.gd")
const LaneVizScript       := preload("res://scripts/LaneVisualizer.gd")
const TreeScript          := preload("res://scripts/TreePlacer.gd")
const FencePlacerScript   := preload("res://scripts/FencePlacer.gd")
const WallPlacerScript    := preload("res://scripts/WallPlacer.gd")
const PortalGoalScene     := preload("res://scenes/PortalGoal.tscn")
const MenuSimScript       := preload("res://scripts/ui/MenuSimulation.gd")
const WindParticlesScript  := preload("res://scripts/WindParticles.gd")

var _lobby: Node
var _join_overlay: Control
var _host_overlay: Control
var _graphics_panel: Control
var _host_btn: Button
var _join_btn: Button
var _name_edit: LineEdit

# Shared style constants
const BG_COLOR        := Color(0.04, 0.05, 0.06, 0.92)
const BORDER_COLOR    := Color(0.85, 0.32, 0.05, 0.6)
const TITLE_COLOR     := Color(1.0, 0.35, 0.1, 1.0)
const LABEL_COLOR     := Color(0.55, 0.45, 0.35, 1.0)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_dialogs()
	# Cache button and name field references from the .tscn
	_host_btn  = $MenuPanel/VBox/HostButton
	_join_btn  = $MenuPanel/VBox/JoinButton
	_name_edit = $MenuPanel/VBox/NameEdit
	# Pre-fill saved name and apply initial button state
	_name_edit.text = GameSettings.player_name
	_update_name_buttons()
	_name_edit.text_changed.connect(_on_name_changed)
	# Only spawn the background simulation when we are the root scene.
	# When Main adds us as a child (singleplayer flow) it calls _on_start_game()
	# immediately — spawning a world here would overwrite GameSync.game_seed and
	# LaneData with a random menu seed, diverging the terrain from Main's world.
	if get_parent() is Window:
		_spawn_menu_world()
	_graphics_panel = $SettingsPanelInstance
	_graphics_panel.back_pressed.connect(_on_graphics_settings_back)

func _on_name_changed(new_text: String) -> void:
	GameSettings.player_name = new_text.strip_edges()
	GameSettings.save_settings()
	_update_name_buttons()

func _update_name_buttons() -> void:
	var has_name: bool = _name_edit.text.strip_edges().length() > 0
	_host_btn.disabled = not has_name
	_join_btn.disabled = not has_name

func _build_dialogs() -> void:
	var ui_theme: Theme = load("res://assets/ui_theme.tres")

	_host_overlay = _build_overlay("HOST GAME", ["Port:"], ["8910"], ["PortEdit"], "Host", _on_host_confirmed, ui_theme)
	add_child(_host_overlay)

	_join_overlay = _build_overlay("JOIN GAME", ["Host IP Address:", "Port:"], ["127.0.0.1", "8910"], ["AddressEdit", "PortEdit"], "Join", _on_join_confirmed, ui_theme)
	add_child(_join_overlay)

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

func _spawn_menu_world() -> void:
	# Random seed each launch — different view every time
	GameSync.game_seed = randi_range(1, 2147483647)
	LaneData.regenerate_for_new_game()

	var world: Node3D = $World3D

	# Replace the camera's environment with the day (noon) one.
	# Camera3D.environment takes priority over WorldEnvironment nodes, so we
	# must swap it here rather than adding a separate WorldEnvironment.
	# Duplicate so we don't mutate the shared asset used by the actual game.
	var day_env: Environment = load("res://assets/day_environment.tres").duplicate()
	day_env.fog_density *= 0.06
	day_env.volumetric_fog_density *= 0.06
	var camera: Camera3D = $MenuCamera
	camera.environment = day_env

	# Noon sun — matches Main.gd time_seed=1 (noon) settings exactly
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-50.0, 0.0, 0.0)
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 0.8
	sun.shadow_blur = 0.8
	world.add_child(sun)

	# Terrain (StaticBody3D, builds HeightMapShape3D + mesh in _ready via call_deferred)
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

	# Kick off the async coroutine — does not block _ready()
	_start_simulation_when_ready(terrain, trees, world)

# Coroutine: waits for terrain collision AND trees to finish (guarded by
# generation_done so we never hang if a signal already fired), then waits
# one physics frame so HeightMapShape3D is registered before raycasts run.
func _start_simulation_when_ready(terrain: Node, trees: Node, world: Node3D) -> void:
	if not terrain.get("generation_done"):
		await terrain.done
	if not trees.get("generation_done"):
		await trees.done
	await get_tree().physics_frame
	_on_menu_world_ready(trees, world)

func _on_menu_world_ready(trees: Node, world: Node3D) -> void:
	# Fences + torches along lane edges
	var fence := Node3D.new()
	fence.set_script(FencePlacerScript)
	fence.name = "FencePlacer"
	world.add_child(fence)

	# Rocks and grass/sand scatter — same as in-game world
	var walls := Node3D.new()
	walls.set_script(WallPlacerScript)
	walls.name = "WallPlacer"
	world.add_child(walls)

	# Portals — one per lane per team at lane endpoints.
	# body_entered is disconnected immediately after _ready() connects it so
	# the menu simulation never calls TeamLives.lose_life() on scoring.
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		if pts.is_empty():
			continue
		var red_end: Vector2 = pts.back() as Vector2
		var red_portal: Area3D = PortalGoalScene.instantiate()
		red_portal.team   = 1
		red_portal.lane_i = lane_i
		red_portal.name   = "PortalRed_%d" % lane_i
		world.add_child(red_portal)
		red_portal.global_position = Vector3(red_end.x, 0.5, red_end.y)
		red_portal.body_entered.disconnect(red_portal._on_body_entered)

		var blue_end: Vector2 = pts.front() as Vector2
		var blue_portal: Area3D = PortalGoalScene.instantiate()
		blue_portal.team   = 0
		blue_portal.lane_i = lane_i
		blue_portal.name   = "PortalBlue_%d" % lane_i
		world.add_child(blue_portal)
		blue_portal.global_position = Vector3(blue_end.x, 0.5, blue_end.y)
		blue_portal.body_entered.disconnect(blue_portal._on_body_entered)

	# Wind particles — bioluminescent ambient particles riding the wind
	var wind := Node3D.new()
	wind.set_script(WindParticlesScript)
	wind.name = "WindParticles"
	world.add_child(wind)
	wind.set("_tree_placer", trees)
	# No player reference needed — WindParticles gracefully handles null player

	# Battle simulation — minions + towers
	var sim := Node.new()
	sim.set_script(MenuSimScript)
	sim.name = "MenuSimulation"
	world.add_child(sim)
	sim.start(world)

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

func _on_host_confirmed(overlay: Control) -> void:
	var port_edit: LineEdit = overlay.find_child("PortEdit", true, false)
	var port_text: String = port_edit.text.strip_edges() if port_edit else ""
	var port: int = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT

	var err: int = NetworkManager.start_host(port)
	if err != OK:
		_show_connection_status("Failed to host: port may be in use")
		return

	# Stop simulation synchronously so no more autoload mutations happen
	_stop_menu_simulation()
	# Reset sim-dirtied autoload state before entering the lobby
	_reset_autoloads_for_new_game()
	overlay.visible = false
	# Host registers itself directly — no RPC needed, peer id 1 is always the server
	LobbyManager.register_player_local(1, GameSettings.player_name)
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

	# Stop simulation synchronously so no more autoload mutations happen
	_stop_menu_simulation()
	# Reset sim-dirtied autoload state before joining
	_reset_autoloads_for_new_game()
	overlay.visible = false
	_show_connection_status("Connecting...")
	var err: int = NetworkManager.join_game(address, port)
	if err != OK:
		_show_connection_status("Failed to connect")
		return

	NetworkManager.connected_to_server.connect(_on_connected_to_lobby, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)

func _on_connected_to_lobby() -> void:
	# Send the player's chosen name to the server
	LobbyManager.register_player.rpc_id(1, GameSettings.player_name)
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

func _stop_menu_simulation() -> void:
	# Disable and free all menu minions/towers without running _die() logic —
	# prevents further TeamData/LevelSystem mutations before the autoload reset.
	var world: Node3D = get_node_or_null("World3D")
	if world == null:
		return
	for child in world.get_children():
		if child.name.begins_with("MenuMinion_") or child.is_in_group("towers"):
			child.set_process(false)
			child.set_physics_process(false)
			child.queue_free()
	var sim: Node = world.get_node_or_null("MenuSimulation")
	if sim != null:
		sim.set_process(false)
		sim.queue_free()

func _reset_autoloads_for_new_game() -> void:
	# Clear all state dirtied by the menu simulation so every new game starts clean.
	GameSync.reset()
	LobbyManager.reset()
	TeamData.reset()
	TeamLives.reset()
	LevelSystem.clear_all()
