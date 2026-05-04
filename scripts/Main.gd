extends Node

enum Role { FIGHTER, SUPPORTER }

const CHARACTER_LETTERS := ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r"]
const BLUE_SPAWN    := Vector3(0.0, 10.0, 84.0)
const RED_SPAWN     := Vector3(0.0, 10.0, -84.0)

enum GameState { MENU, PLAYING, PAUSED }
var game_state: GameState = GameState.MENU

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
	"res://assets/weapons/weapon_rocket_launcher.tres",
]

var game_over    := false
var fps_mode     := true
var _respawning  := false
var _respawn_timer: float = 0.0
## Stores the server-provided respawn time from the player_died signal so that
## _on_player_died() can seed the countdown from the authoritative value.
var _server_respawn_time: float = 0.0
var player_start_team: int = 0
var player_role: Role = Role.FIGHTER
var time_seed: int = 1  # 0=sunrise 1=noon 2=sunset 3=night
var _blue_minion_char: String = ""
var _red_minion_char: String = ""
var _is_fps_mode: bool = true  # tracked so fog can be reapplied on settings change
var _player_avatar_char: String = "a"

var _active_pickup_positions: Array[Vector3] = []
var _pickup_sound: AudioStream = null
var _pending_respawns: Dictionary = {}

const FPSPlayerScene := preload("res://scenes/roles/FPSPlayer.tscn")
const MinionAI := preload("res://scripts/minions/MinionBase.gd")
const RoleSelectDialogScene := preload("res://scenes/ui/RoleSelectDialog.tscn")
const SupporterHUDScene := preload("res://scenes/ui/SupporterHUD.tscn")
const LauncherHUDScript := preload("res://scripts/ui/LauncherHUD.gd")
const CharacterScreenScene := preload("res://scenes/ui/CharacterScreen.tscn")
const LaneBoostHUDScript := preload("res://scripts/ui/LaneBoostHUD.gd")
# RamHUD merged into LaneBoostHUD — no separate script needed
const AISupporterControllerScript := preload("res://scripts/roles/supporter/AISupporterController.gd")
const EntityHUDScript             := preload("res://scripts/hud/EntityHUD.gd")
const PingHUDScript               := preload("res://scripts/hud/PingHUD.gd")
const FighterSkillBarScript       := preload("res://scripts/ui/FighterSkillBar.gd")
const CompassHUDScript            := preload("res://scripts/hud/CompassHUD.gd")
const WindParticlesScript := preload("res://scripts/WindParticles.gd")
const LanePressureHUDScript := preload("res://scripts/ui/LanePressureHUD.gd")

var _supporter_hud: Node = null
var _launcher_hud: Node = null
var _lane_boost_hud: Node = null
var _entity_hud: Control = null
var _ping_hud: Control    = null
var _compass_hud: Control = null
var _lane_pressure_hud: Control = null
var _level_up_dialog: Control = null  # retired — kept to avoid parse errors on any stale refs; remove after full cleanup

@onready var rts_camera:         Node        = $RTSCamera
@onready var vignette_rect:      ColorRect       = $HUD/VignetteRect
@onready var damage_flash_rect:  ColorRect       = $HUD/DamageFlashRect

# Vignette intensity targets — tune these to adjust feel.
# Shape (radius) is set in assets/vignette.gdshader shader_parameter/radius.
const VIGNETTE_NORMAL := 0.2  # subtle always-on strength
const VIGNETTE_ZOOM   := 0.55 # stronger when scoped in
const VIGNETTE_LERP   := 6.0  # transition speed

const DAMAGE_FLASH_INTENSITY := 0.45  # peak red alpha on hit
const DAMAGE_FLASH_DECAY     := 2.5   # how fast it fades (units/sec, timer starts at 1.0)
const HEAL_FLASH_INTENSITY   := 0.35  # peak green alpha on heal
const HEAL_FLASH_DECAY       := 3.5   # faster fade than damage
var _damage_flash_time := 0.0
var _heal_flash_time   := 0.0

const HIT_RING_DURATION := 0.2
var _hit_ring_time := 0.0
var _hit_ring_base_color: Color = Color.WHITE

var fps_player: CharacterBody3D = null

@onready var game_over_screen:   Control         = $HUD/GameOverScreen
@onready var wave_info_label:    Label           = $HUD/WaveInfoPanel/WaveVBox/WaveInfoLabel
@onready var wave_announce_panel: PanelContainer = $HUD/WaveAnnouncePanel
@onready var wave_announce_label: Label          = $HUD/WaveAnnouncePanel/WaveAnnounceLabel
@onready var crosshair:          Control         = $HUD/Crosshair
@onready var hit_ring_top:       ColorRect       = $HUD/Crosshair/HitIndicatorRing/RingTop
@onready var hit_ring_bottom:    ColorRect       = $HUD/Crosshair/HitIndicatorRing/RingBottom
@onready var hit_ring_left:      ColorRect       = $HUD/Crosshair/HitIndicatorRing/RingLeft
@onready var hit_ring_right:     ColorRect       = $HUD/Crosshair/HitIndicatorRing/RingRight
@onready var respawn_label:      Label           = $HUD/RespawnLabel
@onready var ammo_label:         Label           = $HUD/VitalsPanel/VitalsBox/AmmoLabel
@onready var weapon_slot1_row:   Control         = $HUD/VitalsPanel/VitalsBox/WeaponSlots/Slot1Row
@onready var weapon_slot2_row:   Control         = $HUD/VitalsPanel/VitalsBox/WeaponSlots/Slot2Row
@onready var weapon_slot1_icon:  TextureRect     = $HUD/VitalsPanel/VitalsBox/WeaponSlots/Slot1Row/Slot1Icon
@onready var weapon_slot2_icon:  TextureRect     = $HUD/VitalsPanel/VitalsBox/WeaponSlots/Slot2Row/Slot2Icon
@onready var vitals_panel:       PanelContainer  = $HUD/VitalsPanel
@onready var reload_prompt:      Label           = $HUD/ReloadPrompt
@onready var points_label:      Label           = $HUD/TopCenterPanel/TopCenterBox/PointsHBox/PointsLabel
@onready var blue_lives_bar:    ProgressBar     = $HUD/TopCenterPanel/TopCenterBox/LivesHBox/BlueBar
@onready var red_lives_bar:     ProgressBar     = $HUD/TopCenterPanel/TopCenterBox/LivesHBox/RedBar
@onready var minimap:            Control         = $HUD/MinimapPanel/Minimap
@onready var stamina_bar:        ProgressBar     = $HUD/VitalsPanel/VitalsBox/StaminaBar
@onready var health_bar:         ProgressBar     = $HUD/VitalsPanel/VitalsBox/HealthBar
@onready var xp_bar:             ProgressBar     = $HUD/TopCenterPanel/TopCenterBox/XPHBox/XPBar
@onready var level_label:        Label           = $HUD/TopCenterPanel/TopCenterBox/XPHBox/LevelLabel
@onready var pending_button:     Button          = $HUD/TopCenterPanel/TopCenterBox/XPHBox/PendingButton
@onready var audio_mode_switch:  AudioStreamPlayer = $AudioModeSwitch
@onready var audio_wave:         AudioStreamPlayer = $AudioWave
@onready var audio_respawn:      AudioStreamPlayer = $AudioRespawn
@onready var event_feed:         Control            = $HUD/WaveInfoPanel/WaveVBox/EventFeed

const WeaponPickupScene := preload("res://scenes/WeaponPickup.tscn")
const PortalGoalScene   := preload("res://scenes/PortalGoal.tscn")
const PickupSoundPath   := "res://assets/kenney_ui-audio/Audio/switch1.ogg"
const PauseMenuScene    := preload("res://scenes/ui/PauseMenu.tscn")
const LoadingScreenScene := preload("res://scenes/ui/LoadingScreen.tscn")

var _pause_menu: Control
var _role_dialog: Control
var _char_screen: Control = null

func _ready() -> void:
	# Pause wave spawning until the world is fully generated.
	$MinionSpawner.set_process(false)
	$MinionSpawner.set_physics_process(false)
	_setup_game()
	ClientSettings.settings_changed.connect(_apply_fog_settings)
	ClientSettings.settings_changed.connect(_apply_shadow_settings)
	TeamLives.life_lost.connect(_on_life_lost)
	TeamLives.game_over.connect(_on_team_lives_game_over)

func _setup_game() -> void:
	_pause_menu = PauseMenuScene.instantiate()
	$HUD.add_child(_pause_menu)
	_randomize_time_of_day()
	_spawn_remote_player_manager()
	_pick_minion_characters()
	LobbyManager.kicked_from_server.connect(_on_kicked_from_server)
	_start_multiplayer_game()

func _on_kicked_from_server() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/StartMenu.tscn")

func _spawn_remote_player_manager() -> void:
	var mgr_script := load("res://scripts/network/PlayerManager.gd")
	var mgr: Node = Node.new()
	mgr.set_script(mgr_script)
	mgr.name = "PlayerManager"
	add_child(mgr)

func _spawn_local_player() -> void:
	var my_id := BridgeClient.get_peer_id()
	fps_player = FPSPlayerScene.instantiate()
	fps_player.name = "FPSPlayer_%d" % my_id
	fps_player.setup(my_id, player_start_team, true, _player_avatar_char)
	add_child(fps_player)
	fps_player.add_to_group("player")
	var spawn_z: float = 84.0 if player_start_team == 0 else -84.0
	fps_player.global_position = Vector3(0.0, 10.0, spawn_z)
	# Blue spawns at +Z, must face -Z (toward red base). Red spawns at -Z, must face +Z (toward blue base).
	fps_player.rotation.y = 0.0 if player_start_team == 0 else PI

func _start_multiplayer_game() -> void:
	# Resolve team from lobby
	var my_id := BridgeClient.get_peer_id()
	var info: Dictionary = LobbyManager.players.get(my_id, {})
	player_start_team = info.team if info.has("team") else 0

	_setup_portals()
	_HUD_set_visible(true)
	wave_announce_panel.visible = false
	wave_info_label.text = "Wave: 0 | First wave in: 10s"
	audio_mode_switch.stream = load("res://assets/kenney_ui-audio/Audio/switch1.ogg")
	audio_wave.stream        = load("res://assets/kenney_ui-audio/Audio/switch5.ogg")
	audio_respawn.stream     = load("res://assets/kenney_ui-audio/Audio/click1.ogg")
	rts_camera.setup(player_start_team)

	# Show role dialog — live updates via LobbyManager.role_slots_updated
	_role_dialog = RoleSelectDialogScene.instantiate()
	$HUD.add_child(_role_dialog)
	_role_dialog.set_slots_from_network(LobbyManager.supporter_claimed, player_start_team)
	LobbyManager.role_slots_updated.connect(_role_dialog.on_slots_updated)
	_role_dialog.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var selected_role: int = await _role_dialog.role_selected

	# Send claim to server — server validates and broadcasts result.
	# In the bridge path both server and client send via BridgeClient and must
	# await role_slots_updated for the Python reply to arrive before reading
	# the result (role_accepted / role_rejected updates supporter_claimed).
	LobbyManager.set_role_ingame(selected_role)
	await LobbyManager.role_slots_updated

	LobbyManager.role_slots_updated.disconnect(_role_dialog.on_slots_updated)
	_role_dialog.visible = false

	# Verify we actually got the role (supporter could have been rejected)
	var granted_supporter: bool = LobbyManager.supporter_claimed.get(player_start_team, false)
	if selected_role == Role.SUPPORTER and not granted_supporter:
		# Rejected — re-show dialog with supporter grayed out, wait again.
		# Don't reconnect role_slots_updated — state is already current and
		# reconnecting would disable the button the moment the server confirms
		# a future grant (which would misread as "taken by someone else").
		_role_dialog.set_slots_from_network(LobbyManager.supporter_claimed, player_start_team)
		_role_dialog.visible = true
		selected_role = await _role_dialog.role_selected
		# Fighter is always available — send final claim
		LobbyManager.set_role_ingame(selected_role)
		await LobbyManager.role_slots_updated
		_role_dialog.visible = false

	player_role = selected_role as Role
	rts_camera.player_role = player_role
	game_state = GameState.PLAYING
	_setup_event_feed()
	_register_skill_tree_peer(BridgeClient.get_peer_id(), player_role)

	# Spawn AI Supporters for any team without a human Supporter (host only).
	# Done asynchronously so role selection doesn't block the host player's own
	# game setup. Waits up to 30s for all peers to confirm before spawning.
	if BridgeClient.is_host():
		LobbyManager.human_supporter_claimed.connect(_on_human_supporter_claimed)
		_spawn_ai_supporters_when_ready()

	if player_role == Role.FIGHTER:
		_spawn_local_player()
		_setup_hud_for_player()
		_set_mode(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		# Supporter: RTS-only
		_HUD_set_visible(true)
		_set_mode(false)
		crosshair.visible = false
		vitals_panel.visible = false
		ammo_label.visible = false
		reload_prompt.visible = false
		$HUD/MinimapPanel.visible = false
		# PointsLabel and LivesBar remain visible for Supporter
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# Spawn SupporterHUD toolbar
		_supporter_hud = SupporterHUDScene.instantiate()
		$HUD.add_child(_supporter_hud)
		_supporter_hud.setup(player_start_team)
		rts_camera.set_supporter_hud(_supporter_hud)
		# Spawn LauncherHUD — left-edge launcher toolbar (multiplayer)
		_launcher_hud = CanvasLayer.new()
		_launcher_hud.set_script(LauncherHUDScript)
		_launcher_hud.name = "LauncherHUD"
		$HUD.add_child(_launcher_hud)
		_launcher_hud.setup(player_start_team)
		rts_camera.set_launcher_hud(_launcher_hud)
		LobbyManager.item_spawned.connect(_launcher_hud._on_item_spawned)
		LobbyManager.tower_despawned.connect(_launcher_hud._on_tower_despawned)
		# Spawn LaneBoostHUD — right-edge reinforce toolbar (multiplayer)
		_lane_boost_hud = CanvasLayer.new()
		_lane_boost_hud.set_script(LaneBoostHUDScript)
		_lane_boost_hud.name = "LaneBoostHUD"
		$HUD.add_child(_lane_boost_hud)
		_lane_boost_hud.setup(player_start_team)
		LobbyManager.lane_boosts_synced.connect(_lane_boost_hud.apply_boost_sync)

		# Wire EntityHUD — player circles + tower health bars
		_entity_hud = $HUD/HUDOverlay
		_entity_hud.set_script(EntityHUDScript)
		_entity_hud.setup(player_start_team)
		# Build-limit line — shows world z=0 placement boundary in RTS view
		var build_limit_line := Control.new()
		build_limit_line.set_script(load("res://scripts/ui/BuildLimitLine.gd"))
		build_limit_line.name = "BuildLimitLine"
		$HUD.add_child(build_limit_line)
		build_limit_line.setup(rts_camera, player_start_team)
		# Wire leveling HUD — Supporter earns XP from tower/minion kills
		_setup_level_hud()

	# Wire PingHUD — blinking diamond overlay for all roles
	_setup_ping_hud()
	# Wire LanePressureHUD — territory push/rollback warnings for all roles
	_lane_pressure_hud = Control.new()
	_lane_pressure_hud.set_script(LanePressureHUDScript)
	_lane_pressure_hud.name = "LanePressureHUD"
	$HUD.add_child(_lane_pressure_hud)
	_lane_pressure_hud.setup(player_start_team)
	# Wire CompassHUD — CoD-style bearing strip (Fighter only)
	if player_role == Role.FIGHTER:
		_setup_compass_hud()

	# Spawn ambient wind particles — world-space, bioluminescent, gust-driven.
	var wind_particles := Node3D.new()
	wind_particles.set_script(WindParticlesScript)
	wind_particles.name = "WindParticles"
	$World.add_child(wind_particles)
	wind_particles.set("_tree_placer", $World/TreePlacer)
	wind_particles.set("_player", fps_player)

	call_deferred("_spawn_weapon_pickups")
	call_deferred("_setup_lane_data")

	# World generation is complete by the time the game scene loads
	# (the loading screen awaits terrain/trees/walls before transitioning).
	# Enable the spawner so the wave timer ticks.
	# MinionSpawner._process and _physics_process both guard on BridgeClient.is_host()
	# so enabling on all peers is safe — non-hosts return early each frame.
	$MinionSpawner.set_process(true)
	$MinionSpawner.set_physics_process(true)

func _setup_ping_hud() -> void:
	_ping_hud = Control.new()
	_ping_hud.name = "PingHUD"
	_ping_hud.set_script(PingHUDScript)
	$HUD.add_child(_ping_hud)
	_ping_hud.setup(player_start_team)

func _setup_compass_hud() -> void:
	if fps_player == null:
		return
	var cam: Camera3D = fps_player.get_node_or_null("Camera3D")
	if cam == null:
		return
	_compass_hud = Control.new()
	_compass_hud.name = "CompassHUD"
	_compass_hud.set_script(CompassHUDScript)
	$HUD.add_child(_compass_hud)
	_compass_hud.setup(fps_player, cam, player_start_team)

func _setup_hud_for_player() -> void:
	if not fps_player:
		return
	fps_player.reload_bar       = $HUD/Crosshair/ReloadBar
	fps_player.health_bar       = health_bar
	fps_player.ammo_label       = ammo_label
	fps_player.reload_prompt    = reload_prompt
	fps_player.stamina_bar      = stamina_bar
	fps_player.points_label     = points_label
	fps_player.weapon_slot1_row   = weapon_slot1_row
	fps_player.weapon_slot2_row   = weapon_slot2_row
	fps_player.weapon_slot1_icon  = weapon_slot1_icon
	fps_player.weapon_slot2_icon  = weapon_slot2_icon
	fps_player.connect("died", _on_player_died)
	# Capture the server-authoritative respawn_time from the bridge so that
	# _on_player_died() can seed the countdown accurately.
	GameSync.player_died.connect(_on_game_sync_player_died)
	# Force icon population now that refs are wired
	fps_player._update_weapon_label()
	# Skill bar — Fighter only
	if player_role == Role.FIGHTER:
		var peer_id: int = BridgeClient.get_peer_id()
		var skill_bar := CanvasLayer.new()
		skill_bar.set_script(FighterSkillBarScript)
		skill_bar.name = "FighterSkillBar"
		add_child(skill_bar)
		skill_bar.setup(peer_id)
	# Wire leveling HUD
	_setup_level_hud()

func _setup_level_hud() -> void:
	var my_peer: int = BridgeClient.get_peer_id()
	LevelSystem.xp_gained.connect(_on_xp_gained)
	LevelSystem.level_up.connect(_on_level_up_signal)
	pending_button.pressed.connect(_on_pending_button_pressed)
	_refresh_xp_bar(my_peer)
	_refresh_pending_button()

func _refresh_xp_bar(peer_id: int) -> void:
	if xp_bar == null or level_label == null:
		return
	var lvl: int    = LevelSystem.get_level(peer_id)
	var xp: int     = LevelSystem.get_xp(peer_id)
	var needed: int = LevelSystem.get_xp_needed(peer_id)
	level_label.text = "Lv.%d" % lvl
	xp_bar.max_value = needed
	xp_bar.value     = xp

func _refresh_pending_button() -> void:
	if pending_button == null:
		return
	var my_peer: int = BridgeClient.get_peer_id()
	var attr_pts: int  = LevelSystem.get_unspent_points(my_peer)
	var skill_pts: int = SkillTree.get_skill_pts(my_peer)
	var total: int     = attr_pts + skill_pts
	pending_button.visible = total > 0
	pending_button.text    = "↑ %d pt%s" % [total, "s" if total != 1 else ""]

func _on_pending_button_pressed() -> void:
	if _char_screen != null:
		_char_screen.toggle()

func _toggle_attributes_dialog() -> void:
	# Retired — CharacterScreen handles its own toggle via Tab key.
	# pending_button now calls _char_screen.toggle() directly.
	pass

func _on_xp_gained(peer_id: int, _amount: int, new_xp: int, xp_needed: int) -> void:
	var my_peer: int = BridgeClient.get_peer_id()
	if peer_id != my_peer:
		return
	if xp_bar == null:
		return
	xp_bar.max_value = xp_needed
	xp_bar.value     = new_xp
	level_label.text = "Lv.%d" % LevelSystem.get_level(peer_id)

func _on_level_up_signal(peer_id: int, _new_level: int) -> void:
	var my_peer: int = BridgeClient.get_peer_id()
	if peer_id != my_peer:
		return
	_refresh_xp_bar(peer_id)
	_refresh_pending_button()

func _on_level_dialog_point_spent(_attr: String) -> void:
	# Retired — attribute spending is now done inside CharacterScreen.
	pass

func _on_level_dialog_closed() -> void:
	# Retired — CharacterScreen handles its own mouse/active state.
	pass

# ── Event Feed ────────────────────────────────────────────────────────────────

const ITEM_DISPLAY_NAMES := {
	"cannon":      "Cannon Tower",
	"mortar":      "Mortar Tower",
	"slow":        "Slow Tower",
	"machinegun":  "Machine Gun Tower",
	"weapon":      "Weapon Drop",
	"healthpack":  "Health Pack",
	"healstation": "Heal Station",
}

const TOWER_ITEM_TYPES := ["cannon", "mortar", "slow", "machinegun", "healstation"]

func _setup_event_feed() -> void:
	GameSync.player_died.connect(_on_event_player_died)
	LobbyManager.item_spawned.connect(_on_event_item_spawned)
	LobbyManager.tower_despawned.connect(_on_event_tower_despawned)

func _register_skill_tree_peer(peer_id: int, role: Role) -> void:
	var role_str: String = "Fighter" if role == Role.FIGHTER else "Supporter"
	SkillTree.register_peer(peer_id, role_str)
	# Build and attach the unified CharacterScreen to HUD
	if _char_screen == null:
		_char_screen = CharacterScreenScene.instantiate()
		$HUD.add_child(_char_screen)
		_char_screen.setup(peer_id, true)
		_char_screen.set_role(role == Role.FIGHTER)
		_char_screen.connect("opened", _on_char_screen_opened)
		_char_screen.connect("closed", _on_char_screen_closed)
	# Connect SP badge notification on the pending_button (reuse existing button)
	if not SkillTree.skill_pts_changed.is_connected(_on_skill_pts_changed):
		SkillTree.skill_pts_changed.connect(_on_skill_pts_changed)

func _on_char_screen_opened() -> void:
	if fps_player and player_role == Role.FIGHTER:
		fps_player.set_active(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_char_screen_closed() -> void:
	if fps_player and player_role == Role.FIGHTER and game_state == GameState.PLAYING and not _respawning:
		fps_player.set_active(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_skill_pts_changed(peer_id: int, _pts: int) -> void:
	var my_peer: int = BridgeClient.get_peer_id()
	if peer_id != my_peer:
		return
	_refresh_pending_button()

func _team_name(team: int) -> String:
	return "Blue" if team == 0 else "Red"

func _on_event_player_died(peer_id: int, _respawn_time: float) -> void:
	var killed_team: int = GameSync.get_player_team(peer_id)
	if killed_team == -1:
		return  # unknown team, skip
	# Show for both: my teammate killed OR my team killed an enemy
	event_feed.add_event("[%s] Fighter killed" % _team_name(killed_team))

func _on_event_item_spawned(item_type: String, team: int) -> void:
	if team != player_start_team:
		return
	var display: String = ITEM_DISPLAY_NAMES.get(item_type, item_type.capitalize())
	if item_type in TOWER_ITEM_TYPES:
		event_feed.add_event("[%s] %s built" % [_team_name(team), display])
	else:
		event_feed.add_event("Supporter placed %s" % display)

func _on_event_tower_despawned(item_type: String, team: int, _tower_name: String) -> void:
	if team != player_start_team:
		return
	var display: String = ITEM_DISPLAY_NAMES.get(item_type, item_type.capitalize())
	event_feed.add_event("[%s] %s destroyed" % [_team_name(team), display])

func _randomize_time_of_day() -> void:
	if GameSync.time_seed >= 0:
		time_seed = GameSync.time_seed
		GameSync.time_seed = -1
	else:
		time_seed = randi() % 4
	var sun := $World/SunLight
	var world_env := $World/WorldEnvironment
	
	match time_seed:
		0: # Sunrise
			sun.light_color = Color(1.0, 0.45, 0.18)
			sun.light_energy = 0.8
			sun.rotation_degrees = Vector3(-10, 30, 0)
			sun.light_volumetric_fog_energy = 2.0
			sun.shadow_blur = 2.5
			world_env.environment = load("res://assets/dusk_environment.tres")
		1: # Noon
			sun.light_color = Color(1.0, 0.95, 0.85)
			sun.light_energy = 1.0
			sun.rotation_degrees = Vector3(-50, 0, 0)
			sun.light_volumetric_fog_energy = 0.8
			sun.shadow_blur = 0.8
			world_env.environment = load("res://assets/day_environment.tres")
		2: # Sunset
			sun.light_color = Color(1.0, 0.35, 0.15)
			sun.light_energy = 0.6
			sun.rotation_degrees = Vector3(-10, 210, 0)
			sun.light_volumetric_fog_energy = 2.5
			sun.shadow_blur = 2.5
			world_env.environment = load("res://assets/dusk_environment.tres")
		3: # Night
			sun.light_color = Color(0.2, 0.35, 1.0)
			sun.light_energy = 0.25
			sun.rotation_degrees = Vector3(-70, 180, 0)
			sun.light_volumetric_fog_energy = 0.05
			sun.shadow_blur = 3.0
			world_env.environment = load("res://assets/night_environment.tres")
	_apply_fog_settings()
	_apply_shadow_settings()


func _apply_fog_settings() -> void:
	var world_env := $World/WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	# Fog enabled only when in FPS mode AND GraphicsSettings allows it
	var want_fog: bool = _is_fps_mode and ClientSettings.fog_enabled
	env.fog_enabled = want_fog
	env.volumetric_fog_enabled = want_fog
	if want_fog:
		env.fog_density = ClientSettings.get_fog_density(time_seed)
		env.volumetric_fog_density = ClientSettings.get_vol_fog_density(time_seed)


func _apply_shadow_settings() -> void:
	var sun: DirectionalLight3D = get_node_or_null("World/SunLight")
	if sun == null:
		return
	match ClientSettings.shadow_quality:
		0: # Off
			sun.shadow_enabled = false
		1: # Low — orthogonal, 60 m
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 60.0
		2: # High — PSSM4, 100 m
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 100.0

func _pick_minion_characters() -> void:
	var shuffled := CHARACTER_LETTERS.duplicate()
	shuffled.shuffle()
	_blue_minion_char = shuffled[0]
	_red_minion_char  = shuffled[1]
	_player_avatar_char = shuffled[2]
	MinionAI.set_model_characters(_blue_minion_char, _red_minion_char)
	# Send avatar char to server so all peers can look it up via LobbyManager.players
	LobbyManager.report_avatar_char(_player_avatar_char)

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
	if fps_player:
		var player_team_name := "BLUE" if fps_player.player_team == 0 else "RED"
		var player_pts := TeamData.get_points(fps_player.player_team)
		points_label.text = "%s: $%d" % [player_team_name, player_pts]
	elif game_state == GameState.PLAYING:
		var player_team_name := "BLUE" if player_start_team == 0 else "RED"
		var player_pts := TeamData.get_points(player_start_team)
		points_label.text = "%s: $%d" % [player_team_name, player_pts]
	var completed_respawns: Array = []
	for pos in _pending_respawns.keys():
		_pending_respawns[pos] -= delta
		if _pending_respawns[pos] <= 0.0:
			_respawn_pickup(pos)
			completed_respawns.append(pos)
	for pos in completed_respawns:
		_pending_respawns.erase(pos)
	# Vignette intensity — tracks zoom state of the FPS camera.
	if vignette_rect.visible and fps_player and fps_player.has_node("Camera3D"):
		var cam: Camera3D = fps_player.get_node("Camera3D")
		var zoomed: bool = cam.fov < 52.5
		var target_intensity: float = VIGNETTE_ZOOM if zoomed else VIGNETTE_NORMAL
		var mat: ShaderMaterial = vignette_rect.material as ShaderMaterial
		if mat:
			var current: float = mat.get_shader_parameter("intensity")
			mat.set_shader_parameter("intensity", lerp(current, target_intensity, VIGNETTE_LERP * delta))
	# Damage / heal flash — shared ColorRect, damage takes priority.
	var flash_mat: ShaderMaterial = damage_flash_rect.material as ShaderMaterial
	if _damage_flash_time > 0.0:
		_damage_flash_time = max(0.0, _damage_flash_time - DAMAGE_FLASH_DECAY * delta)
		if flash_mat:
			flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.0, 0.0, 1.0))
			flash_mat.set_shader_parameter("intensity", _damage_flash_time * DAMAGE_FLASH_INTENSITY)
	elif _heal_flash_time > 0.0:
		_heal_flash_time = max(0.0, _heal_flash_time - HEAL_FLASH_DECAY * delta)
		if flash_mat:
			flash_mat.set_shader_parameter("flash_color", Color(0.1, 1.0, 0.3, 1.0))
			flash_mat.set_shader_parameter("intensity", _heal_flash_time * HEAL_FLASH_INTENSITY)
	else:
		if flash_mat:
			flash_mat.set_shader_parameter("intensity", 0.0)
	# Hit ring — fades out after showing on a successful hit.
	if _hit_ring_time > 0.0:
		_hit_ring_time = max(0.0, _hit_ring_time - delta)
		var t: float = _hit_ring_time / HIT_RING_DURATION
		var ring_alpha: float = t * t
		hit_ring_top.modulate.a = ring_alpha
		hit_ring_bottom.modulate.a = ring_alpha
		hit_ring_left.modulate.a = ring_alpha
		hit_ring_right.modulate.a = ring_alpha

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

func _on_bullet_hit_something(hit_type: String) -> void:
	var color: Color
	if hit_type == "minion":
		color = Color(1.0, 0.7, 0.0)
	elif hit_type == "tower":
		color = Color(0.4, 0.7, 1.0)
	elif hit_type == "player":
		color = Color(1.0, 0.2, 0.2)
	else:
		color = Color(0.9, 0.9, 0.9)
	hit_ring_top.color = color
	hit_ring_bottom.color = color
	hit_ring_left.color = color
	hit_ring_right.color = color
	_hit_ring_time = HIT_RING_DURATION
	hit_ring_top.modulate.a = 1.0
	hit_ring_bottom.modulate.a = 1.0
	hit_ring_left.modulate.a = 1.0
	hit_ring_right.modulate.a = 1.0

func _setup_portals() -> void:
	TeamLives.reset()
	_update_lives_bars()
	var portal_scene: PackedScene = PortalGoalScene
	# Spawn one portal per lane per team at the lane endpoints
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		if pts.size() == 0:
			continue
		# Blue minions march toward red base (last point in blue direction = pts.back())
		# Red portal sits at the end blue minions walk toward → pts.back() (z≈-82)
		var red_end: Vector2 = pts.back() as Vector2
		var red_portal: Area3D = portal_scene.instantiate()
		red_portal.team   = 1
		red_portal.lane_i = lane_i
		red_portal.name   = "PortalRed_%d" % lane_i
		$World.add_child(red_portal)
		red_portal.global_position = Vector3(red_end.x, 0.5, red_end.y)

		# Blue portal sits at the end red minions walk toward → pts.front() (z≈+82)
		var blue_end: Vector2 = pts.front() as Vector2
		var blue_portal: Area3D = portal_scene.instantiate()
		blue_portal.team   = 0
		blue_portal.lane_i = lane_i
		blue_portal.name   = "PortalBlue_%d" % lane_i
		$World.add_child(blue_portal)
		blue_portal.global_position = Vector3(blue_end.x, 0.5, blue_end.y)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			match game_state:
				GameState.MENU:
					_on_quit_from_menu()
				GameState.PLAYING:
					toggle_pause(true)
				GameState.PAUSED:
					toggle_pause(false)
			return
		if event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB:
			if game_state == GameState.PLAYING and not game_over and _char_screen != null:
				_char_screen.toggle()
				return

func _on_resume_game() -> void:
	toggle_pause(false)

func _on_quit_from_menu() -> void:
	get_tree().quit()

func leave_game() -> void:
	# Disconnect from the Python server and free the TCP connection.
	BridgeClient.disconnect_from_server()
	# Reset all autoload state so the start menu simulation and next game
	# start from a clean slate — no stale healths, pings, points, etc.
	GameSync.reset()
	LobbyManager.reset()
	TeamData.reset()
	TeamLives.reset()
	LevelSystem.clear_all()
	SkillTree.clear_all()
	LaneControl.reset()
	get_tree().change_scene_to_file("res://scenes/ui/StartMenu.tscn")

func toggle_pause(paused: bool) -> void:
	if paused:
		game_state = GameState.PAUSED
		_pause_menu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if fps_player:
			fps_player.set_active(false)
		# Only force the FPS camera current if we're actually in FPS mode.
		# If the Fighter is dead (_respawning), the RTS camera is already current — leave it.
		if fps_mode and fps_player and fps_player.has_node("Camera3D"):
			rts_camera.current = false
			fps_player.get_node("Camera3D").current = true
		crosshair.visible = false
	else:
		game_state = GameState.PLAYING
		_pause_menu.visible = false
		if player_role == Role.FIGHTER and fps_player and not _respawning:
			# Normal resume — return to FPS
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			fps_player.set_active(true)
			rts_camera.current = false
			fps_mode = true
			crosshair.visible = true
		elif player_role == Role.FIGHTER and _respawning:
			# Fighter is dead — stay in RTS view, keep waiting for respawn
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			rts_camera.current = true
			fps_mode = false
		else:
			# Supporter resumes RTS
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			rts_camera.current = true
			fps_mode = false

func _HUD_set_visible(visible: bool) -> void:
	if game_over_screen and game_over:
		game_over_screen.visible = visible
	wave_info_label.visible = visible
	crosshair.visible = visible and fps_mode
	minimap.visible = visible and fps_mode
	ammo_label.visible = visible and fps_mode
	vitals_panel.visible = visible and fps_mode
	reload_prompt.visible = visible and fps_mode
	vitals_panel.visible = visible
	points_label.visible = visible
	respawn_label.visible = visible and _respawning
	damage_flash_rect.visible = visible

func _set_mode(is_fps: bool) -> void:
	fps_mode = is_fps
	if fps_player:
		fps_player.set_active(is_fps)
	rts_camera.current  = !is_fps
	crosshair.visible   = is_fps
	minimap.visible     = is_fps
	vignette_rect.visible = is_fps
	damage_flash_rect.visible = is_fps
	ammo_label.visible  = is_fps
	vitals_panel.visible = is_fps
	if not is_fps and reload_prompt:
		reload_prompt.visible = false
	_is_fps_mode = is_fps
	_apply_fog_settings()
	if is_fps:
		# Defer capture by one frame — capturing immediately after a scene
		# transition or respawn can fail with "NO GRAB" on Linux X11 when the
		# window does not yet have focus.
		call_deferred("_capture_mouse")
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _capture_mouse() -> void:
	# Only capture if we are still in FPS mode when this deferred call fires.
	if _is_fps_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func flash_damage() -> void:
	_damage_flash_time = 1.0
	var flash_mat: ShaderMaterial = damage_flash_rect.material as ShaderMaterial
	if flash_mat:
		flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.0, 0.0, 1.0))
		flash_mat.set_shader_parameter("intensity", DAMAGE_FLASH_INTENSITY)

func flash_heal() -> void:
	_heal_flash_time = 1.0
	var flash_mat: ShaderMaterial = damage_flash_rect.material as ShaderMaterial
	if flash_mat:
		flash_mat.set_shader_parameter("flash_color", Color(0.1, 1.0, 0.3, 1.0))
		flash_mat.set_shader_parameter("intensity", HEAL_FLASH_INTENSITY)

func game_over_signal(winner: String) -> void:
	if game_over:
		return
	game_over = true
	var winner_team: int = 0 if winner == "BLUE" else 1
	if game_over_screen:
		game_over_screen.show_winner(winner_team)

func _on_team_lives_game_over(winner_team: int) -> void:
	var winner_str: String = "BLUE" if winner_team == 0 else "RED"
	game_over_signal(winner_str)
	# In multiplayer the server broadcasts via LobbyManager; handled there.

func _on_life_lost(_team: int, _remaining: int) -> void:
	_update_lives_bars()

func _update_lives_bars() -> void:
	if blue_lives_bar == null or red_lives_bar == null:
		return
	var max_lives: int = ClientSettings.lives_per_team
	blue_lives_bar.max_value = max_lives
	red_lives_bar.max_value  = max_lives
	blue_lives_bar.value = TeamLives.get_lives(0)
	red_lives_bar.value  = TeamLives.get_lives(1)

func update_wave_info(wave_num: int, next_in: int) -> void:
	if wave_num == 0:
		wave_info_label.text = "First wave in: %ds" % next_in
	else:
		wave_info_label.text = "Wave: %d | Next in: %ds" % [wave_num, next_in]

func show_wave_announcement(wave_num: int) -> void:
	wave_announce_label.text = "— WAVE %d —" % wave_num
	wave_announce_panel.modulate.a = 1.0
	wave_announce_panel.visible = true
	audio_wave.play()
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(wave_announce_panel, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): wave_announce_panel.visible = false)

func _on_game_sync_player_died(peer_id: int, respawn_time: float) -> void:
	# Store the server-provided respawn time so _on_player_died() can use it
	# to seed the countdown label with the authoritative value.
	if peer_id == BridgeClient.get_peer_id():
		_server_respawn_time = respawn_time

func _on_player_died() -> void:
	if game_over:
		return
	if player_role != Role.FIGHTER:
		return
	# respawn_time is now seeded via _on_game_sync_died which receives the
	# server-authoritative value from the player_died signal. This method
	# is the "died" signal from the FPS player node (local path). Use the
	# last value stored in _server_respawn_time if available, otherwise fall
	# back to LobbyManager.
	var respawn_time: float = _server_respawn_time if _server_respawn_time > 0.0 \
		else LobbyManager.get_respawn_time(BridgeClient.get_peer_id())
	_server_respawn_time = 0.0
	_respawning     = true
	_respawn_timer  = respawn_time
	respawn_label.visible = true
	crosshair.visible     = false
	rts_camera.current    = true
	fps_mode = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _do_respawn() -> void:
	_respawning = false
	respawn_label.visible = false
	if fps_player:
		var spawn_pos: Vector3 = BLUE_SPAWN if fps_player.player_team == 0 else RED_SPAWN
		fps_player.respawn(spawn_pos)
	SkillTree.reset_per_life(BridgeClient.get_peer_id())
	_set_mode(true)

func _spawn_weapon_pickups() -> void:
	_pickup_sound = load(PickupSoundPath)
	_active_pickup_positions.clear()
	_pending_respawns.clear()
	for existing in get_tree().get_nodes_in_group("weapon_pickups"):
		existing.queue_free()
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		if pts.size() < 21:
			continue
		var mid: Vector2 = pts[20]
		var prev: Vector2 = pts[19]
		var tang: Vector2 = (mid - prev).normalized()
		var perp := Vector2(-tang.y, tang.x)
		var offset_pos := mid + perp * 3.0
		var pos := Vector3(offset_pos.x, 0.0, offset_pos.y)
		if _is_far_enough(pos, _active_pickup_positions, 20.0):
			_place_pickup(Vector3(pos.x, 3.0, pos.z), _pickup_sound)
			_active_pickup_positions.append(pos)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for i in range(17):
		var attempts: int = 0
		var pos_candidate: Vector3 = Vector3.ZERO
		var found: bool = false
		while attempts < 30 and not found:
			var x: float = rng.randf_range(-75.0, -15.0) if rng.randi() % 2 == 0 else rng.randf_range(15.0, 75.0)
			var z: float = rng.randf_range(-65.0, 65.0)
			pos_candidate = Vector3(x, 0.0, z)
			if _is_far_enough(pos_candidate, _active_pickup_positions, 20.0):
				found = true
			attempts += 1
		if found:
			_place_pickup(Vector3(pos_candidate.x, pos_candidate.y + 3.0, pos_candidate.z), _pickup_sound)
			_active_pickup_positions.append(pos_candidate)

func _is_far_enough(pos: Vector3, placed: Array[Vector3], min_dist: float) -> bool:
	for p in placed:
		if p.distance_to(pos) < min_dist:
			return false
	return true

func _find_alternate_position() -> Vector3:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for attempt in range(30):
		var x: float = rng.randf_range(-75.0, -15.0) if rng.randi() % 2 == 0 else rng.randf_range(15.0, 75.0)
		var z: float = rng.randf_range(-65.0, 65.0)
		var pos := Vector3(x, 0.0, z)
		if _is_far_enough(pos, _active_pickup_positions, 20.0):
			return pos
	return Vector3.INF

func _respawn_pickup(original_pos: Vector3) -> void:
	var pos: Vector3 = original_pos
	if not _is_far_enough(pos, _active_pickup_positions, 20.0):
		pos = _find_alternate_position()
	if pos == Vector3.INF:
		return
	_place_pickup(Vector3(pos.x, pos.y + 3.0, pos.z), _pickup_sound)
	_active_pickup_positions.append(pos)

func _on_weapon_pickup(pos: Vector3) -> void:
	_active_pickup_positions.erase(pos)
	_pending_respawns[pos] = 90.0

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
	pickup.position = Vector3(pos.x, ground_y + 0.15, pos.z)
	if pickup.has_node("AudioStreamPlayer3D") and pickup_sound:
		pickup.get_node("AudioStreamPlayer3D").stream = pickup_sound
	add_child(pickup)
	pickup.add_to_group("weapon_pickups")
	(pickup as Node).connect("weapon_picked_up", _on_weapon_pickup)
	if BridgeClient.is_connected_to_server():
		BridgeClient.send("register_drop", {"name": str(pickup.name), "team": 0})

# ── AI Supporter spawning ─────────────────────────────────────────────────────

# Multiplayer: called on server only. Check LobbyManager.supporter_claimed.
func _spawn_ai_supporters_multiplayer() -> void:
	for t in [0, 1]:
		if not LobbyManager.supporter_claimed.get(t, false):
			_spawn_ai_supporter(t)

# Async wrapper: waits for all peers to confirm roles (up to 30s) then spawns.
# Python sends "all_roles_confirmed" via bridge which emits LobbyManager.all_roles_confirmed.
# Timeout guard ensures we never hang if a peer disconnects before picking a role.
func _spawn_ai_supporters_when_ready() -> void:
	var _timeout_timer := get_tree().create_timer(30.0)
	_timeout_timer.timeout.connect(func() -> void:
		LobbyManager.all_roles_confirmed.emit()
	)
	await LobbyManager.all_roles_confirmed
	_spawn_ai_supporters_multiplayer()

func _spawn_ai_supporter(t: int) -> void:
	# Avoid duplicates
	for child in get_children():
		if child is Node and child.get_script() == AISupporterControllerScript \
				and child.get("team") == t:
			return
	var ai: Node = AISupporterControllerScript.new()
	ai.name = "AISupporterTeam%d" % t
	ai.set("team", t)
	LobbyManager.ai_supporter_teams.append(t)
	add_child(ai)

func _on_human_supporter_claimed(team: int) -> void:
	# A human player has taken the Supporter slot — remove any AI Supporter
	# that was already running for that team (can happen if the server spawned
	# one before all role confirmations arrived).
	var ai_name := "AISupporterTeam%d" % team
	var ai := get_node_or_null(ai_name)
	if ai != null:
		ai.queue_free()
	var idx: int = LobbyManager.ai_supporter_teams.find(team)
	if idx != -1:
		LobbyManager.ai_supporter_teams.remove_at(idx)

# ── Recon Strike ──────────────────────────────────────────────────────────────

# Called on all peers via LobbyManager.broadcast_recon_reveal (and directly in SP).
# Reveals fog at target_pos for duration seconds and spawns 3D shockwave VFX.
func apply_recon_reveal(target_pos: Vector3, reveal_radius: float, reveal_duration: float) -> void:
	# Fog reveal — RTSController's FogOverlay (held under World)
	var fog: Node = get_node_or_null("World/FogOverlay")
	if fog != null and fog.has_method("add_timed_reveal"):
		fog.call("add_timed_reveal", target_pos, reveal_radius, reveal_duration)

	# Shockwave VFX — visible to FPS players in range
	_spawn_recon_vfx(Vector3(target_pos.x, target_pos.y + 5.0, target_pos.z))

# ── Recon Strike VFX (inlined from ReconStrikeVFX.gd) ────────────────────────
func _spawn_recon_vfx(pos: Vector3) -> void:
	var root: Node = VfxUtils.get_scene_root(self)

	# 1. Expanding torus shockwave ring
	var mesh_inst := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 1.0
	torus.rings = 16
	torus.ring_segments = 64
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.65)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.3, 0.7, 1.0, 1.0)
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	torus.material = ring_mat
	mesh_inst.mesh = torus
	mesh_inst.scale = Vector3(0.01, 0.01, 0.01)
	root.add_child(mesh_inst)
	mesh_inst.global_position = pos
	var tw: Tween = mesh_inst.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mesh_inst, "scale", Vector3(40.0, 40.0, 40.0), 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float) -> void: ring_mat.albedo_color = Color(0.4, 0.8, 1.0, a),
		0.65, 0.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	get_tree().create_timer(1.7).timeout.connect(mesh_inst.queue_free)

	# 2. Pulse light
	VfxUtils.spawn_flash_light(root, pos, {
		"color": Color(0.5, 0.8, 1.0), "energy": 12.0, "range": 50.0,
		"duration": 1.0, "offset": Vector3(0.0, -2.0, 0.0)
	})

	# 3. Particle burst
	VfxUtils.spawn_particles(root, pos, {
		"amount": 30, "lifetime": 1.2, "explosiveness": 1.0,
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.5, "spread": 180.0,
		"vel_min": 5.0, "vel_max": 10.0, "gravity": Vector3(0.0, -1.5, 0.0),
		"scale_min": 0.15, "scale_max": 0.35,
		"color": Color(0.5, 0.9, 1.0, 1.0),
		"emission_enabled": true, "emission_color": Color(0.4, 0.8, 1.0), "emission_energy": 5.0,
	})