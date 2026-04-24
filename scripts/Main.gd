extends Node

const RESPAWN_DELAY := 5.0
const BLUE_SPAWN    := Vector3(0.0, 10.0, 84.0)
const RED_SPAWN     := Vector3(0.0, 10.0, -84.0)

enum GameState { MENU, PLAYING, PAUSED }
var game_state: GameState = GameState.MENU
var _is_singleplayer := true

# Weapon pickup spawns: 3 lane midpoints + 6 mountain positions
const MOUNTAIN_PICKUP_POSITIONS: Array = [
	Vector3(-60.0, 6.0, 20.0),
	Vector3(-50.0, 6.0, -15.0),
	Vector3(-55.0, 6.0, -45.0),
	Vector3(60.0,  6.0, 15.0),
	Vector3(52.0,  6.0, -20.0),
	Vector3(58.0,  6.0,  40.0),
]

# All 3 available weapon preset paths
const WEAPON_PRESETS: Array = [
	"res://assets/weapons/weapon_pistol.tres",
	"res://assets/weapons/weapon_rifle.tres",
	"res://assets/weapons/weapon_heavy.tres",
]

var game_over    := false
var fps_mode     := true
var _respawning  := false
var _respawn_timer: float = 0.0
var player_start_team: int = 0
var time_seed: int = 1  # 0=sunrise 1=noon 2=sunset 3=night

const FPSPlayerScene := preload("res://scenes/FPSPlayer.tscn")

@onready var rts_camera:         Camera3D        = $RTSCamera
@onready var entity_hud:         Node            = $HUD/HUDOverlay/EntityHUD

var fps_player: CharacterBody3D = null

@onready var mode_label:         Label           = $HUD/ModeLabel
@onready var game_over_label:    Label           = $HUD/GameOverLabel
@onready var wave_info_label:    Label           = $HUD/WaveInfoLabel
@onready var wave_announce_label: Label          = $HUD/WaveAnnounceLabel
@onready var crosshair:          Control         = $HUD/Crosshair
@onready var respawn_label:      Label           = $HUD/RespawnLabel
@onready var weapon_label:       Label           = $HUD/WeaponLabel
@onready var ammo_label:         Label           = $HUD/AmmoLabel
@onready var reload_prompt:      Label           = $HUD/ReloadPrompt
@onready var points_label:      Label           = $HUD/PointsLabel
@onready var minimap:            Control         = $HUD/Minimap
@onready var audio_mode_switch:  AudioStreamPlayer = $AudioModeSwitch
@onready var audio_wave:         AudioStreamPlayer = $AudioWave
@onready var audio_respawn:      AudioStreamPlayer = $AudioRespawn

const WeaponPickupScene := preload("res://scenes/WeaponPickup.tscn")
const PickupSoundPath   := "res://assets/kenney_ui-audio/Audio/switch1.ogg"
const StartMenuScene  := preload("res://scenes/StartMenu.tscn")
const PauseMenuScene  := preload("res://scenes/PauseMenu.tscn")

var _start_menu: Control
var _pause_menu: Control

func _ready() -> void:
	entity_hud.setup($HUD/HUDOverlay)
	
	var _has_network_peer: bool = NetworkManager._peer != null
	print("[Main] _ready: has_network_peer = ", _has_network_peer)
	
	if _has_network_peer:
		_is_singleplayer = false
		print("[Main] _ready: _is_singleplayer set to false")
		_setup_multiplayer_game()
	else:
		_is_singleplayer = true
		print("[Main] _ready: _is_singleplayer set to true")
		_setup_singleplayer_game()
		_on_start_game()

func _setup_singleplayer_game() -> void:
	_start_menu = StartMenuScene.instantiate()
	add_child(_start_menu)
	print("[Main] Connecting start_game signal")
	_start_menu.connect("start_game", _on_start_game)
	_start_menu.connect("quit_game", _on_quit_from_menu)
	_pause_menu = PauseMenuScene.instantiate()
	$HUD.add_child(_pause_menu)
	print("[Main] _setup_singleplayer_game: _pause_menu=", _pause_menu, " visible=", _pause_menu.visible)
	_HUD_set_visible(false)
	_randomize_time_of_day()

func _setup_multiplayer_game() -> void:
	_pause_menu = PauseMenuScene.instantiate()
	$HUD.add_child(_pause_menu)
	_spawn_local_player()
	_spawn_remote_player_manager()
	_start_multiplayer_game()
	_randomize_time_of_day()

func _spawn_remote_player_manager() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var mgr_script := load("res://scripts/RemotePlayerManager.gd")
	var mgr: Node = Node.new()
	mgr.set_script(mgr_script)
	mgr.name = "RemotePlayerManager"
	add_child(mgr)

func _spawn_local_player() -> void:
	var my_id := multiplayer.get_unique_id()
	var info: Dictionary = LobbyManager.players.get(my_id, {})
	player_start_team = info.team if info.has("team") else 0
	
	fps_player = FPSPlayerScene.instantiate()
	fps_player.set("player_team", player_start_team)
	fps_player.name = "FPSPlayer_%d" % my_id
	add_child(fps_player)
	fps_player.add_to_group("player")
	
	var spawn_z: float = 84.0 if player_start_team == 0 else -84.0
	fps_player.global_position = Vector3(0.0, 10.0, spawn_z)

func _start_multiplayer_game() -> void:
	game_state = GameState.PLAYING
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_HUD_set_visible(true)
	_setup_bases()
	_set_mode(true)
	wave_announce_label.visible = false
	wave_info_label.text = "Wave: 0 | First wave in: 10s"
	audio_mode_switch.stream = load("res://assets/kenney_ui-audio/Audio/switch1.ogg")
	audio_wave.stream        = load("res://assets/kenney_ui-audio/Audio/switch5.ogg")
	audio_respawn.stream     = load("res://assets/kenney_ui-audio/Audio/click1.ogg")
	_setup_hud_for_player()
	call_deferred("_spawn_weapon_pickups")
	call_deferred("_setup_lane_data")
	call_deferred("_spawn_preset_towers")

func _setup_hud_for_player() -> void:
	if not fps_player:
		return
	fps_player.reload_bar    = $HUD/Crosshair/ReloadBar
	fps_player.health_bar    = $HUD/HealthBar
	fps_player.weapon_label  = weapon_label
	fps_player.ammo_label    = ammo_label
	fps_player.reload_prompt = reload_prompt
	fps_player.stamina_bar  = $HUD/StaminaBar
	fps_player.points_label = points_label
	fps_player.connect("died", _on_player_died)

func _randomize_time_of_day() -> void:
	time_seed = randi() % 4
	var sun := $World/SunLight
	var world_env := $World/WorldEnvironment
	
	match time_seed:
		0: # Sunrise
			sun.light_color = Color(1.0, 0.45, 0.18)
			sun.light_energy = 0.8
			sun.rotation_degrees = Vector3(-10, 30, 0)
			world_env.environment = load("res://assets/dusk_environment.tres")
		1: # Noon
			sun.light_color = Color(1.0, 0.95, 0.85)
			sun.light_energy = 1.0
			sun.rotation_degrees = Vector3(-50, 0, 0)
			world_env.environment = load("res://assets/day_environment.tres")
		2: # Sunset
			sun.light_color = Color(1.0, 0.35, 0.15)
			sun.light_energy = 0.6
			sun.rotation_degrees = Vector3(-10, 210, 0)
			world_env.environment = load("res://assets/dusk_environment.tres")
		3: # Night
			sun.light_color = Color(0.2, 0.35, 1.0)
			sun.light_energy = 0.25
			sun.rotation_degrees = Vector3(-70, 180, 0)
			world_env.environment = load("res://assets/night_environment.tres")

func _setup_lane_data() -> void:
	var terrain: Node = $World/Terrain
	if terrain and terrain.has_method("get_secret_paths"):
		var secret_paths: Array = terrain.get_secret_paths()
		LaneData.set_secret_paths(secret_paths)

func _process(delta: float) -> void:
	if _respawning:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_do_respawn()
		else:
			respawn_label.text = "Respawning in %d..." % (int(_respawn_timer) + 1)
	if entity_hud and entity_hud.has_method("process_entity_hud"):
		var cam: Camera3D
		var crosshair_pos: Vector2
		if fps_player and fps_player.has_node("Camera3D"):
			cam = fps_player.get_node("Camera3D") if fps_mode else rts_camera
			crosshair_pos = get_viewport().get_visible_rect().size * 0.5 if fps_mode else Vector2(-1, -1)
		entity_hud.call("process_entity_hud", delta, cam, crosshair_pos)
		if fps_player:
			var player_team_name := "BLUE" if fps_player.player_team == 0 else "RED"
			var player_pts := TeamData.get_points(fps_player.player_team)
			points_label.text = "%s: %d" % [player_team_name, player_pts]

func _spawn_preset_towers() -> void:
	const TOWER_SCENE := preload("res://scenes/Tower.tscn")
	var blue_lane_positions: Array = [
		Vector3(-28.0, 0.0, 70.0),
		Vector3(-3.0, 0.0, 70.0),
		Vector3(28.0, 0.0, 70.0),
	]
	var red_lane_positions: Array = [
		Vector3(28.0, 0.0, -70.0),
		Vector3(3.0, 0.0, -70.0),
		Vector3(-28.0, 0.0, -70.0),
	]
	for pos in blue_lane_positions:
		var tower = TOWER_SCENE.instantiate()
		pos.y = 0
		$World.add_child(tower)
		tower.global_position = pos
		tower.setup(0)
	for pos in red_lane_positions:
		var tower = TOWER_SCENE.instantiate()
		pos.y = 0
		$World.add_child(tower)
		tower.global_position = pos
		tower.setup(1)

func _get_terrain_height(pos: Vector3) -> float:
	var world_3d: World3D = get_tree().root.get_world_3d()
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space == null:
		return 0.0
	var from: Vector3 = Vector3(pos.x, 50.0, pos.z)
	var to: Vector3 = Vector3(pos.x, -10.0, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result.position.y

func _setup_bases() -> void:
	var blue_base = $World/BlueBase/BlueBaseInst
	var red_base  = $World/RedBase/RedBaseInst
	if blue_base and blue_base.has_method("setup"):
		blue_base.setup(0)
	if red_base and red_base.has_method("setup"):
		red_base.setup(1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		print("[Main] _input: keycode=", event.keycode, " game_state=", game_state, " _is_singleplayer=", _is_singleplayer)
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			match game_state:
				GameState.MENU:
					print("[Main] ESCAPE - MENU case")
					_on_quit_from_menu()
				GameState.PLAYING:
					print("[Main] ESCAPE - PLAYING case, _is_singleplayer=", _is_singleplayer)
					if _is_singleplayer:
						toggle_pause(true)
					else:
						print("[Main] ESCAPE - NOT singleplayer, skipping toggle_pause")
				GameState.PAUSED:
					print("[Main] ESCAPE - PAUSED case, _is_singleplayer=", _is_singleplayer)
					if _is_singleplayer:
						toggle_pause(false)
			return
			match game_state:
				GameState.MENU:
					_on_quit_from_menu()
				GameState.PLAYING:
					toggle_pause(true)
				GameState.PAUSED:
					toggle_pause(false)
			return
		if event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB:
			if game_state == GameState.PLAYING and not game_over and not _respawning:
				_set_mode(!fps_mode)
				audio_mode_switch.play()

func _on_start_game() -> void:
	print("[Main] _on_start_game: game_state=", game_state, " _is_singleplayer=", _is_singleplayer)
	player_start_team = randi() % 2
	fps_player = FPSPlayerScene.instantiate()
	fps_player.set("player_team", player_start_team)
	add_child(fps_player)
	fps_player.add_to_group("player")
	game_state = GameState.PLAYING
	_start_menu.visible = false
	var menu_cam: Node = _start_menu.get_node_or_null("MenuCamera")
	if menu_cam:
		menu_cam.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_HUD_set_visible(true)
	_setup_bases()
	_set_mode(true)
	get_tree().set_auto_accept_quit(true)
	wave_announce_label.visible = false
	wave_info_label.text = "Wave: 0 | First wave in: 10s"
	audio_mode_switch.stream = load("res://assets/kenney_ui-audio/Audio/switch1.ogg")
	audio_wave.stream        = load("res://assets/kenney_ui-audio/Audio/switch5.ogg")
	audio_respawn.stream     = load("res://assets/kenney_ui-audio/Audio/click1.ogg")
	_setup_hud_for_player()
	var spawn_z: float = 84.0 if player_start_team == 0 else -84.0
	fps_player.global_position = Vector3(0.0, 10.0, spawn_z)
	call_deferred("_spawn_weapon_pickups")
	call_deferred("_setup_lane_data")
	call_deferred("_spawn_preset_towers")

func _on_resume_game() -> void:
	toggle_pause(false)

func _on_quit_from_menu() -> void:
	get_tree().quit()

func toggle_pause(paused: bool) -> void:
	print("[Main] toggle_pause: paused=", paused, " _is_singleplayer=", _is_singleplayer, " _pause_menu=", _pause_menu)
	if paused:
		game_state = GameState.PAUSED
		_pause_menu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		fps_player.set_active(false)
		rts_camera.current = false
		crosshair.visible = false
	else:
		game_state = GameState.PLAYING
		_pause_menu.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if fps_player:
			fps_player.set_active(true)
		rts_camera.current = false
		fps_mode = true
		crosshair.visible = true
		mode_label.text = "Mode: FPS  [Tab] to switch"

func _HUD_set_visible(visible: bool) -> void:
	mode_label.visible = visible
	game_over_label.visible = visible and game_over
	wave_info_label.visible = visible
	crosshair.visible = visible and fps_mode
	minimap.visible = visible and fps_mode
	ammo_label.visible = visible and fps_mode
	$HUD/StaminaBar.visible = visible and fps_mode
	reload_prompt.visible = visible and fps_mode
	weapon_label.visible = visible
	points_label.visible = visible
	respawn_label.visible = visible and _respawning

func _set_mode(is_fps: bool) -> void:
	fps_mode = is_fps
	if fps_player:
		fps_player.set_active(is_fps)
	rts_camera.current  = !is_fps
	crosshair.visible   = is_fps
	minimap.visible     = is_fps
	ammo_label.visible  = is_fps
	$HUD/StaminaBar.visible = is_fps
	if not is_fps and reload_prompt:
		reload_prompt.visible = false
	var world_env := $World/WorldEnvironment
	if world_env and world_env.environment:
		world_env.environment.fog_enabled = is_fps
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
	audio_wave.play()
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(wave_announce_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): wave_announce_label.visible = false)

func _on_player_died() -> void:
	if game_over:
		return
	_respawning     = true
	_respawn_timer  = RESPAWN_DELAY
	respawn_label.visible = true
	crosshair.visible     = false
	rts_camera.current    = true
	fps_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mode_label.text = "DEAD — respawning..."

func _do_respawn() -> void:
	_respawning = false
	respawn_label.visible = false
	if fps_player:
		var spawn_pos: Vector3 = BLUE_SPAWN if fps_player.player_team == 0 else RED_SPAWN
		fps_player.respawn(spawn_pos)
	audio_respawn.play()
	_set_mode(true)

func _spawn_weapon_pickups() -> void:
	var pickup_sound: AudioStream = load(PickupSoundPath)
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		if pts.size() < 21:
			continue
		var mid: Vector2 = pts[20]
		var prev: Vector2 = pts[19]
		var tang: Vector2 = (mid - prev).normalized()
		var perp := Vector2(-tang.y, tang.x)
		var offset_pos := mid + perp * 3.0
		_place_pickup(Vector3(offset_pos.x, 3.0, offset_pos.y), pickup_sound)
	for pos in MOUNTAIN_PICKUP_POSITIONS:
		_place_pickup(pos, pickup_sound)

func _place_pickup(pos: Vector3, pickup_sound: AudioStream) -> void:
	var space: PhysicsDirectSpaceState3D = get_node("World/Terrain").get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, 200.0, pos.z),
		Vector3(pos.x, -200.0, pos.z)
	)
	ray.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(ray)
	var ground_y: float = pos.y
	if hit:
		ground_y = hit.position.y
	var pickup: Node3D = WeaponPickupScene.instantiate()
	var preset_index: int = randi() % WEAPON_PRESETS.size()
	var w: WeaponData = load(WEAPON_PRESETS[preset_index])
	pickup.weapon_data = w
	pickup.position = Vector3(pos.x, ground_y + 0.8, pos.z)
	if pickup.has_node("AudioStreamPlayer3D") and pickup_sound:
		pickup.get_node("AudioStreamPlayer3D").stream = pickup_sound
	add_child(pickup)