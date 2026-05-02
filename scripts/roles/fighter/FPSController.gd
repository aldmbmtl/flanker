extends BasePlayer

const SPEED             := 6.4
const SPRINT_SPEED      := 9.0
const CROUCH_SPEED      := 3.2

const MAX_STAMINA            := 10.0
const STAMINA_DRAIN_RATE    := 1.0
const STAMINA_REGEN_RATE    := 1.0
const STAMINA_EXHAUST_CD    := 5.0
const JUMP_VELOCITY     := 6.0
const MOUSE_SENSITIVITY := 0.003
const GRAVITY           := 20.0
const KILL_PLANE_Y      := -30.0  # below terrain floor; fall-off-map death trigger

const ROLE_STATS := {
	"Tank":    {"hp": 150, "speed_mult": 0.8, "damage_mult": 0.7},
	"DPS":     {"hp": 100, "speed_mult": 1.0, "damage_mult": 1.2},
	"Support": {"hp": 80,  "speed_mult": 1.0, "damage_mult": 0.8},
	"Sniper":  {"hp": 70,  "speed_mult": 1.0, "damage_mult": 1.5},
	"Flanker": {"hp": 90,  "speed_mult": 1.3, "damage_mult": 1.0},
}
const DEFAULT_HP := 200.0

var player_role: String = ""

var player_health_mult: float = 1.0
var player_speed_mult: float = 1.0
var player_damage_mult: float = 1.0

var _sync_frame: int = 0
var _last_sent_pos: Vector3 = Vector3.ZERO
var _last_sent_rot: Vector3 = Vector3.ZERO
const _TRANSFORM_POS_THRESHOLD_SQ: float = 0.0025  # 0.05 m dead-zone squared
const _TRANSFORM_ROT_THRESHOLD: float = 0.02        # 0.02 rad dead-zone

const FOV_NORMAL  := 75.0
const FOV_ZOOM    := 30.0
const FOV_LERP    := 12.0

const DOF_FOCUS_MAX         := 80.0  # fallback focus dist when ray misses (sky/open space)
const DOF_FOCUS_RAY         := 150.0 # max raycast length for focus detection
const DOF_FOCUS_LERP        := 8.0   # tracking speed — lower = lazier/dreamier, higher = snappy
const DOF_TRANSITION_NORMAL := 25.0  # far blur ramp length at normal FOV
const DOF_TRANSITION_ZOOM   := 10.0  # far blur ramp length when zoomed (tighter = crisper falloff)
# near blur distance/transition are read directly from assets/fps_camera_attributes.tres

const CAM_Y_STAND  := 0.8
const CAM_Y_CROUCH := 0.45
const CAP_H_STAND  := 1.8
const CAP_H_CROUCH := 0.9

const DEFAULT_WEAPON_PATH    := "res://assets/weapons/weapon_pistol.tres"
const DEFAULT_SECONDARY_PATH := "res://assets/weapons/weapon_rocket_launcher.tres"

const FOOTSTEP_SOUNDS: Array = [
	"res://assets/kenney_impact-sounds/Audio/footstep_grass_000.ogg",
	"res://assets/kenney_impact-sounds/Audio/footstep_grass_001.ogg",
	"res://assets/kenney_impact-sounds/Audio/footstep_grass_002.ogg",
	"res://assets/kenney_impact-sounds/Audio/footstep_grass_003.ogg",
	"res://assets/kenney_impact-sounds/Audio/footstep_grass_004.ogg",
]
const FOOTSTEP_INTERVAL_WALK   := 0.375
const FOOTSTEP_INTERVAL_SPRINT := 0.24

var active    := true
var hp: float  = GameSync.PLAYER_MAX_HP
var _dead         := false
var _crouching    := false
var _syncing_heal := false  # re-entrant guard: heal() → GameSync → _on_game_sync_health_changed

# Fire cooldown (inter-shot delay)
var _fire_timer: float = 0.0
var _fire_cooling := false

# True reload state
var _reload_timer: float = 0.0
var _reloading           := false
var _reload_tween: Tween = null
var _kick_tween: Tween = null
var _bob_time: float = 0.0
var _kicking: bool = false
var _stamina: float = MAX_STAMINA
var _stamina_exhausted: bool = false
var _exhaust_timer: float = 0.0

# Reload animation transforms — WEAPON_REST_* matches WeaponModel scene offset
const WEAPON_REST_POS   := Vector3(0.25, -0.2, -0.4)
const WEAPON_REST_ROT   := Vector3(0.0, 0.0, 0.0)
const WEAPON_RELOAD_POS := Vector3(0.25, -0.5, -0.1)
const WEAPON_RELOAD_ROT := Vector3(0.3, 0.0, 0.0)
const KICK_POS          := Vector3(0.25, -0.16, -0.25)
const KICK_TIME         := 0.04
const KICK_RETURN_TIME  := 0.08

const BOB_FREQ    := 8.0
const BOB_H_AMP   := 0.02
const BOB_V_AMP   := 0.01
const BOB_LERP    := 10.0

# Slow debuff (applied by Slow Tower)
var _slow_timer: float = 0.0
var _slow_mult:  float = 1.0
var _slow_trail: GPUParticles3D = null
var _step_timer: float = 0.0

# 2-slot weapon inventory; slot 0 = default pistol, slot 1 = empty initially
var weapons: Array = [null, null]
var active_slot: int = 0

# Per-slot ammo: [mag_ammo, reserve_ammo]
var _slot_ammo: Array = [[0, 0], [0, 0]]

# Set by Main.gd after scene ready
var reload_bar: ProgressBar  = null
var health_bar: ProgressBar  = null
var ammo_label: Label        = null
var reload_prompt: Label     = null
var stamina_bar: ProgressBar = null
var points_label: Label    = null
var weapon_slot1_row:   Control       = null
var weapon_slot2_row:   Control       = null
var weapon_slot1_icon:  TextureRect   = null
var weapon_slot2_icon:  TextureRect   = null

const _WEAPON_ICONS: Dictionary = {
	"Pistol":          "res://assets/kenney_blaster-kit/Previews/blaster-a.png",
	"Rifle":           "res://assets/kenney_blaster-kit/Previews/blaster-f.png",
	"Heavy Blaster":   "res://assets/kenney_blaster-kit/Previews/blaster-k.png",
	"Rocket Launcher": "res://assets/kenney_blaster-kit/Previews/blaster-q.png",
}

signal died
signal weapon_changed(slot: int, weapon: WeaponData)

@onready var camera:      Camera3D           = $Camera3D
@onready var shoot_from:  Node3D             = $Camera3D/ShootFrom
@onready var weapon_model: Node3D            = $Camera3D/WeaponModel
@onready var col_shape:   CollisionShape3D   = $CollisionShape3D
@onready var shoot_audio: AudioStreamPlayer3D = $ShootAudio

const CAMERA_SHAKE_SPEED := 20.0
const CAMERA_SHAKE_AMP := 0.45

var camera_shake_time := 0.0
var _base_cam_y := 0.0

const BulletScene  := preload("res://scenes/projectiles/Bullet.tscn")
const RocketScene  := preload("res://scenes/projectiles/Rocket.tscn")
const PLAYER_SYNC_INTERVAL := 5

func _ready() -> void:
	super._ready()
	_base_cam_y = camera.position.y
	camera.far = 250.0
	var my_id := multiplayer.get_unique_id()
	is_local = (name == "FPSPlayer_%d" % my_id)
	peer_id = name.substr(10).to_int() if name.begins_with("FPSPlayer_") else my_id

	print("[FPS] _ready peer_id=", peer_id,
		" is_local=", is_local,
		" team=", player_team,
		" role='", player_role, "'",
		" name=", name)

	# Register with LevelSystem so bonuses are available immediately
	if is_local:
		LevelSystem.register_peer(peer_id)

	# Register with GameSync so host can track us
	if is_local:
		GameSync.set_player_team(peer_id, player_team)
		GameSync.set_player_health(peer_id, hp)
		GameSync.player_died.connect(_on_game_sync_died)
		GameSync.player_respawned.connect(_on_game_sync_respawned)
		GameSync.player_health_changed.connect(_on_game_sync_health_changed)
		if not multiplayer.is_server():
			LobbyManager.register_player_team.rpc_id(1, peer_id, player_team)
		# Reconnect level bonuses when attributes are spent
		LevelSystem.attribute_spent.connect(_on_level_attribute_spent)

	_load_default_weapon()
	_refresh_viewmodel()
	_update_weapon_label()
	_update_ammo_hud()
	call_deferred("_init_slow_trail")
	if is_local:
		call_deferred("_apply_dof_settings")
		GraphicsSettings.settings_changed.connect(_apply_dof_settings)

func _apply_dof_settings() -> void:
	if camera.attributes == null:
		return
	camera.attributes.dof_blur_far_enabled = GraphicsSettings.dof_enabled
	camera.attributes.dof_blur_near_enabled = false  # re-controlled per-frame when zoomed

func _init_slow_trail() -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0.0, 2.0, 0.0)
	pm.scale_min = 0.08
	pm.scale_max = 0.2
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.15)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.5, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.amount = 20
	p.lifetime = 0.6
	p.emitting = false
	p.position = Vector3(0.0, 0.5, 0.0)
	add_child(p)
	_slow_trail = p
	camera.attributes.dof_blur_amount = GraphicsSettings.dof_blur_amount

func _on_level_attribute_spent(p_peer_id: int, _attr: String, _new_attrs: Dictionary) -> void:
	if p_peer_id != peer_id:
		return
	# Recompute health cap — increase current HP by the bonus delta
	var new_max: float = _get_max_hp()
	if hp > new_max:
		hp = new_max
	_update_health_bar()

func _get_level_speed_mult() -> float:
	return 1.0 + LevelSystem.get_bonus_speed_mult(peer_id)

func _get_max_stamina() -> float:
	return MAX_STAMINA + LevelSystem.get_bonus_stamina(peer_id)

func _get_level_damage_mult() -> float:
	return 1.0 + LevelSystem.get_bonus_damage_mult(peer_id)

# ── Skill tree passive helpers ─────────────────────────────────────────────────

func _get_skill_damage_reduction() -> float:
	return SkillTree.get_passive_bonus(peer_id, "damage_reduction")

func _get_skill_reload_mult() -> float:
	# Returns a multiplier < 1.0 (e.g. 0.75 when f_reload is unlocked)
	return 1.0 - SkillTree.get_passive_bonus(peer_id, "reload_speed")

func _get_skill_sprint_mult() -> float:
	return 1.0 + SkillTree.get_passive_bonus(peer_id, "sprint_mult")

func _get_skill_stamina_drain_mult() -> float:
	return 1.0 - SkillTree.get_passive_bonus(peer_id, "stamina_drain_reduction")

func _get_skill_headshot_mult() -> float:
	return 1.0 + SkillTree.get_passive_bonus(peer_id, "headshot_mult")

func _get_rally_speed_bonus() -> float:
	if not has_meta("rally_speed_bonus"):
		return 0.0
	return float(get_meta("rally_speed_bonus"))

func set_active(is_active: bool) -> void:
	active = is_active
	if not _dead:
		camera.current = is_active

func take_damage(amount: float, _source: String, _killer_team: int = -1, killer_peer_id: int = -1) -> void:
	if _dead:
		return
	# Apply armor passive (flat damage reduction)
	var reduction: float = _get_skill_damage_reduction()
	var actual: float = maxf(0.0, amount - reduction)
	# f_iron_skin: absorb into shield before HP
	if has_meta("shield_hp") and get_meta("shield_hp") > 0.0:
		var shield: float = float(get_meta("shield_hp"))
		var absorbed: float = minf(actual, shield)
		shield -= absorbed
		actual  -= absorbed
		if shield <= 0.0:
			remove_meta("shield_hp")
			if has_meta("shield_timer"):
				remove_meta("shield_timer")
		else:
			set_meta("shield_hp", shield)
	hp = max(0.0, hp - actual)
	camera_shake_time = 0.35
	var _main := get_tree().current_scene
	if _main != null and _main.has_method("flash_damage"):
		_main.flash_damage()
	_update_health_bar()
	# second_wind: auto-heal to 30 HP once per life when below 10
	if hp > 0.0 and hp < 10.0 and SkillTree.is_unlocked(peer_id, "f_second_wind") and not SkillTree.is_second_wind_used(peer_id):
		SkillTree.consume_second_wind(peer_id)
		hp = minf(30.0, _get_max_hp())
		_update_health_bar()
	if hp <= 0.0:
		_on_death()
		var awarding_team: int = _killer_team if _killer_team >= 0 else 1
		TeamData.add_points(awarding_team, 50)
		_update_points_label()
		# Singleplayer: award XP to killer
		if killer_peer_id > 0 and not multiplayer.has_multiplayer_peer():
			LevelSystem.award_xp(killer_peer_id, LevelSystem.XP_PLAYER)
			# killstreak_heal: heal killer
			var heal_amt: float = SkillTree.get_passive_bonus(killer_peer_id, "killstreak_heal")
			if heal_amt > 0.0:
				var killer_node: Node = get_tree().root.get_node_or_null("Main/FPSPlayer_%d" % killer_peer_id)
				if killer_node != null and killer_node.has_method("heal"):
					killer_node.heal(heal_amt)

func _get_max_hp() -> float:
	return (DEFAULT_HP * player_health_mult) + LevelSystem.get_bonus_hp(peer_id)

func heal(amount: float) -> void:
	if _dead:
		return
	var hp_before: float = hp
	hp = min(hp + amount, _get_max_hp())
	_update_health_bar()
	if hp > hp_before:
		_syncing_heal = true
		GameSync.set_player_health(peer_id, hp)
		_syncing_heal = false
		_emit_heal_flash()

## Overridable — called when HP actually increases. Default triggers screen flash.
func _emit_heal_flash() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("flash_heal"):
		main.flash_heal()

func apply_slow(duration: float, mult: float) -> void:
	if not is_local:
		return
	_slow_timer = max(_slow_timer, duration)
	_slow_mult  = min(_slow_mult, mult)
	if _slow_trail != null and is_instance_valid(_slow_trail):
		_slow_trail.emitting = true

func _load_default_weapon() -> void:
	var default_weapon: WeaponData = load(DEFAULT_WEAPON_PATH)
	if default_weapon:
		weapons[0] = default_weapon
		_slot_ammo[0] = [default_weapon.magazine_size, default_weapon.reserve_ammo]
	var secondary_weapon: WeaponData = load(DEFAULT_SECONDARY_PATH)
	if secondary_weapon:
		weapons[1] = secondary_weapon
		_slot_ammo[1] = [secondary_weapon.magazine_size, secondary_weapon.reserve_ammo]

func _apply_role_stats() -> void:
	if player_role.is_empty():
		return
	var stats: Dictionary = ROLE_STATS.get(player_role, {})
	if stats.is_empty():
		return
	player_health_mult = float(stats.get("hp", 100)) / 100.0
	player_speed_mult = float(stats.get("speed_mult", 1.0))
	player_damage_mult = float(stats.get("damage_mult", 1.0))

func respawn(spawn_pos: Vector3) -> void:
	print("[FPS] respawn peer_id=", peer_id,
		" spawn_pos=", spawn_pos,
		" hp=", _get_max_hp())
	_dead        = false
	var max_hp: float = _get_max_hp()
	hp           = max_hp
	global_position = spawn_pos
	# Blue spawns at +Z faces -Z (toward red base); red spawns at -Z faces +Z (toward blue base).
	rotation.y      = 0.0 if player_team == 0 else PI
	camera.rotation.x = 0.0
	velocity     = Vector3.ZERO
	_reloading    = false
	_reload_timer = 0.0
	_fire_cooling = false
	_fire_timer   = 0.0
	if _reload_tween:
		_reload_tween.kill()
		_reload_tween = null
	if _kick_tween:
		_kick_tween.kill()
		_kick_tween = null
	_kicking = false
	weapon_model.position = WEAPON_REST_POS
	weapon_model.rotation = WEAPON_REST_ROT
	_load_default_weapon()
	if weapons[0] != null:
		_slot_ammo = [
			[weapons[0].magazine_size, weapons[0].reserve_ammo],
			[0, 0],
		]
	_update_health_bar()
	_update_ammo_hud()
	_report_ammo_to_server()
	if reload_bar:
		reload_bar.visible = false
	if reload_prompt:
		reload_prompt.visible = false
	col_shape.disabled = false
	$PlayerBody.visible = true

func pick_up_weapon(w: WeaponData) -> void:
	# Check if we already have this weapon type in any slot — top up ammo
	for i in range(weapons.size()):
		if weapons[i] != null and weapons[i].weapon_name == w.weapon_name:
			var mag: int = _slot_ammo[i][0]
			var reserve: int = _slot_ammo[i][1]
			var max_reserve: int = w.reserve_ammo
			_slot_ammo[i][1] = min(reserve + w.reserve_ammo, max_reserve)
			if i == active_slot:
				_update_ammo_hud()
			_report_ammo_to_server()
			return

	# New weapon — fill slot 1 if empty, else replace active slot
	if weapons[1] == null:
		weapons[1] = w
		_slot_ammo[1] = [w.magazine_size, w.reserve_ammo]
		active_slot = 1
	else:
		weapons[active_slot] = w
		_slot_ammo[active_slot] = [w.magazine_size, w.reserve_ammo]
	_refresh_viewmodel()
	_update_weapon_label()
	_update_ammo_hud()
	_report_ammo_to_server()
	emit_signal("weapon_changed", active_slot, w)

func _on_death() -> void:
	print("[FPS] _on_death peer_id=", peer_id, " hp=", hp)
	_dead         = true
	active        = false
	camera.current = false
	col_shape.disabled = true
	$PlayerBody.visible = false
	emit_signal("died")

func _update_health_bar() -> void:
	if health_bar == null:
		return
	health_bar.value = (hp / GameSync.PLAYER_MAX_HP) * 100.0
	var fill_style: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	if fill_style == null:
		fill_style = StyleBoxFlat.new()
		health_bar.add_theme_stylebox_override("fill", fill_style)
	var health_pct: float = hp / GameSync.PLAYER_MAX_HP
	if health_pct > 0.6:
		fill_style.bg_color = Color(0.2, 0.9, 0.2, 1)
	elif health_pct > 0.3:
		fill_style.bg_color = Color(1, 0.9, 0.2, 1)
	else:
		fill_style.bg_color = Color(0.9, 0.2, 0.2, 1)

func _update_weapon_label() -> void:
	var s1: String = weapons[0].weapon_name if weapons[0] else ""
	var s2: String = weapons[1].weapon_name if weapons[1] else ""

	# Slot icons
	if weapon_slot1_icon != null:
		var path1: String = _WEAPON_ICONS.get(s1, "")
		weapon_slot1_icon.texture = load(path1) if path1 != "" else null
	if weapon_slot2_icon != null:
		var path2: String = _WEAPON_ICONS.get(s2, "")
		weapon_slot2_icon.texture = load(path2) if path2 != "" else null

	# Active slot highlight — dim inactive row
	if weapon_slot1_row != null:
		weapon_slot1_row.modulate = Color(1, 1, 1, 1) if active_slot == 0 else Color(1, 1, 1, 0.40)
	if weapon_slot2_row != null:
		weapon_slot2_row.modulate = Color(1, 1, 1, 1) if active_slot == 1 else Color(1, 1, 1, 0.40)

func _update_ammo_hud() -> void:
	var w: WeaponData = _current_weapon()
	var mag: int = _slot_ammo[active_slot][0]
	var reserve: int = _slot_ammo[active_slot][1]

	if ammo_label != null:
		if w != null:
			ammo_label.text = "%d / %d" % [mag, reserve]
		else:
			ammo_label.text = "— / —"

	# Show reload prompt when mag <= 20% and not already reloading
	if reload_prompt != null:
		if w != null and not _reloading and mag <= int(w.magazine_size * 0.2) and mag > 0:
			reload_prompt.visible = true
		else:
			reload_prompt.visible = false

func _report_ammo_to_server() -> void:
	var w: WeaponData = _current_weapon()
	var wname: String = w.weapon_name if w != null else ""
	var total: int = _slot_ammo[0][1] + _slot_ammo[1][1]
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			GameSync.set_player_reserve_ammo(peer_id, total, wname)
		else:
			LobbyManager.report_ammo.rpc_id(1, total, wname)

func _refresh_viewmodel() -> void:
	# Remove old model children
	for child in weapon_model.get_children():
		child.queue_free()
	var w: WeaponData = weapons[active_slot]
	if w == null or w.mesh_path == "":
		return
	var packed: PackedScene = load(w.mesh_path)
	if packed == null:
		return
	var model: Node3D = packed.instantiate()
	model.scale = Vector3(0.5, 0.5, 0.5)
	weapon_model.add_child(model)
	# Wire shoot audio
	if w.fire_sound_path != "":
		var stream: AudioStream = load(w.fire_sound_path)
		if stream:
			shoot_audio.stream = stream

func _current_weapon() -> WeaponData:
	return weapons[active_slot]

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI / 2.2, PI / 2.2)
	if event.is_action_pressed("shoot"):
		_shoot()
	if event.is_action_pressed("reload"):
		_start_reload()
	if event.is_action_pressed("weapon_slot_1"):
		_select_slot(0)
	if event.is_action_pressed("weapon_slot_2"):
		_select_slot(1)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_slot(0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot(1)
	if event.is_action_pressed("ping"):
		_fire_ping()
	if event.is_action_pressed("skill_active_1"):
		_use_skill_active(0)
	if event.is_action_pressed("skill_active_2"):
		_use_skill_active(1)
	# DEBUG: F9 = force-unlock dash + assign to slot 0 (singleplayer only)
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F9 and not multiplayer.has_multiplayer_peer():
			var needed: int = 1 - SkillTree.get_skill_pts(peer_id)
			if needed > 0:
				SkillTree.debug_grant_pts(peer_id, needed)
			SkillTree.unlock_node_local(peer_id, "f_dash")
			SkillTree.assign_active_slot(peer_id, 0, "f_dash")
			print("[DEBUG] F9: dash unlocked and assigned to slot 0")

func _use_skill_active(slot: int) -> void:
	if not is_local:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SkillTree.request_use_active.rpc_id(1, slot)
	else:
		SkillTree.use_active_local(peer_id, slot)

func _select_slot(slot: int) -> void:
	if slot == active_slot:
		return
	if weapons[slot] == null:
		return
	active_slot = slot
	_reloading    = false
	_reload_timer = 0.0
	_fire_cooling = false
	_fire_timer   = 0.0
	if reload_bar:
		reload_bar.visible = false
	if _reload_tween:
		_reload_tween.kill()
		_reload_tween = null
	if _kick_tween:
		_kick_tween.kill()
		_kick_tween = null
	weapon_model.position = WEAPON_REST_POS
	weapon_model.rotation = WEAPON_REST_ROT
	_refresh_viewmodel()
	_update_weapon_label()
	_update_ammo_hud()

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	# Slow debuff tick
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_timer = 0.0
			_slow_mult = 1.0
			if _slow_trail != null and is_instance_valid(_slow_trail):
				_slow_trail.emitting = false

	# f_rapid_fire timer tick
	if has_meta("rapid_fire_timer"):
		var rft: float = float(get_meta("rapid_fire_timer")) - delta
		if rft <= 0.0:
			remove_meta("rapid_fire_timer")
			if has_meta("rapid_fire_weapon"):
				remove_meta("rapid_fire_weapon")
		else:
			set_meta("rapid_fire_timer", rft)

	# f_iron_skin shield timer tick
	if has_meta("shield_timer"):
		var st: float = float(get_meta("shield_timer")) - delta
		if st <= 0.0:
			remove_meta("shield_timer")
			if has_meta("shield_hp"):
				remove_meta("shield_hp")
		else:
			set_meta("shield_timer", st)

	# rally_cry_timer tick (set by FighterSkills._rally_cry on teammates)
	if has_meta("rally_cry_timer"):
		var rct: float = float(get_meta("rally_cry_timer")) - delta
		if rct <= 0.0:
			remove_meta("rally_cry_timer")
			if has_meta("rally_speed_bonus"):
				remove_meta("rally_speed_bonus")
		else:
			set_meta("rally_cry_timer", rct)

	# Camera shake
	if camera_shake_time > 0.0:
		camera_shake_time -= delta
		var shake := sin(camera_shake_time * CAMERA_SHAKE_SPEED) * CAMERA_SHAKE_AMP
		var offset := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake
		camera.position = Vector3(0, _base_cam_y, 0) + offset
	elif camera.position.y != _base_cam_y:
		camera.position.y = _base_cam_y

	if not active:
		return

	# Kill plane — player fell off or through the map
	if global_position.y < KILL_PLANE_Y and not _dead:
		take_damage(999999.0, "void", -1, -1)

	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not _crouching:
		velocity.y = JUMP_VELOCITY

	# Crouch
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch != _crouching:
		_set_crouch(want_crouch)

	# Zoom FOV
	var target_fov: float = FOV_ZOOM if Input.is_action_pressed("zoom") else FOV_NORMAL
	camera.fov = lerp(camera.fov, target_fov, FOV_LERP * delta)

	# Depth of Field — focus tracks whatever the crosshair is pointing at.
	# Tune constants DOF_FOCUS_MAX / DOF_FOCUS_LERP / DOF_TRANSITION_* at the top of this file.
	# dof_blur_amount lives in assets/fps_camera_attributes.tres (overridden by GraphicsSettings).
	if camera.attributes != null and GraphicsSettings.dof_enabled:
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var focus_dist: float = DOF_FOCUS_MAX
		if space != null:
			var origin: Vector3 = camera.global_position
			var forward: Vector3 = -camera.global_transform.basis.z
			var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * DOF_FOCUS_RAY)
			query.exclude = [self]
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty():
				focus_dist = origin.distance_to(hit.position)
		var zoomed: bool = camera.fov < (FOV_NORMAL + FOV_ZOOM) * 0.5
		var target_transition: float = DOF_TRANSITION_ZOOM if zoomed else DOF_TRANSITION_NORMAL
		camera.attributes.dof_blur_far_distance   = lerp(camera.attributes.dof_blur_far_distance,   focus_dist,        DOF_FOCUS_LERP * delta)
		camera.attributes.dof_blur_far_transition = lerp(camera.attributes.dof_blur_far_transition, target_transition, FOV_LERP * delta)
		camera.attributes.dof_blur_near_enabled    = zoomed
		# near distance/transition stay as set in assets/fps_camera_attributes.tres

	# Fire cooldown tick
	if _fire_cooling:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer   = 0.0
			_fire_cooling = false

	# Reload tick
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_reload_timer = 0.0
			_reloading    = false
			_finish_reload()
		_update_reload_bar()

	# Gun bob — suppressed during reload or kick (tween owns position)
	var speed_sq: float = Vector2(velocity.x, velocity.z).length_squared()
	if not _reloading and not _kicking and is_on_floor() and speed_sq > 0.25:
		_bob_time += delta * BOB_FREQ
		var h: float = sin(_bob_time) * BOB_H_AMP
		var v: float = abs(sin(_bob_time)) * BOB_V_AMP
		weapon_model.position = WEAPON_REST_POS + Vector3(h, -v, 0.0)
	else:
		if _bob_time != 0.0:
			_bob_time = 0.0
		if not _reloading:
			weapon_model.position = weapon_model.position.lerp(WEAPON_REST_POS, BOB_LERP * delta)

	# Stamina
	var want_sprint: bool = Input.is_action_pressed("sprint")
	var drain_rate: float = STAMINA_DRAIN_RATE * _get_skill_stamina_drain_mult()
	if want_sprint and _stamina > 0.0:
		_stamina = max(0.0, _stamina - drain_rate * delta)
		_stamina_exhausted = false
		_exhaust_timer = 0.0
	elif not want_sprint and _stamina < _get_max_stamina():
		if _stamina_exhausted:
			_exhaust_timer -= delta
			if _exhaust_timer <= 0.0:
				_stamina_exhausted = false
		else:
			_stamina = min(_get_max_stamina(), _stamina + STAMINA_REGEN_RATE * delta)
	elif _stamina <= 0.0 and not _stamina_exhausted:
		_stamina_exhausted = true
		_exhaust_timer = STAMINA_EXHAUST_CD
	_update_stamina_bar()

	# Dash animation — velocity-driven so move_and_slide() respects collision.
	# If a wall/fence is hit mid-dash, the dash is cancelled immediately to
	# prevent the player from being teleported through or getting stuck.
	if has_meta("dash_elapsed"):
		var elapsed: float  = float(get_meta("dash_elapsed")) + delta
		var duration: float = float(get_meta("dash_duration"))
		var origin: Vector3 = get_meta("dash_origin")  as Vector3
		var target: Vector3 = get_meta("dash_target")  as Vector3
		var t: float = minf(elapsed / duration, 1.0)
		# Cubic ease-out derivative used as speed scalar so the feel is preserved.
		var t_prev: float = minf((elapsed - delta) / duration, 1.0)
		var ease_cur:  float = 1.0 - pow(1.0 - t, 3.0)
		var ease_prev: float = 1.0 - pow(1.0 - t_prev, 3.0)
		var total_dist: float = origin.distance_to(target)
		var frame_dist: float = (ease_cur - ease_prev) * total_dist
		var dash_dir: Vector3 = (target - origin)
		if dash_dir.length_squared() > 0.0:
			dash_dir = dash_dir.normalized()
		velocity.x = dash_dir.x * (frame_dist / delta)
		velocity.z = dash_dir.z * (frame_dist / delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()

		# Cancel dash on collision (hit a fence/wall) or when complete.
		var finished: bool = t >= 1.0 or is_on_wall()
		if finished:
			velocity.x = 0.0
			velocity.z = 0.0
			for key in ["dash_origin", "dash_target", "dash_elapsed", "dash_duration"]:
				if has_meta(key):
					remove_meta(key)
			if has_meta("dash_effect"):
				var eff: GPUParticles3D = get_meta("dash_effect") as GPUParticles3D
				if is_instance_valid(eff):
					eff.emitting = false
					var t2: SceneTreeTimer = get_tree().create_timer(0.5)
					t2.timeout.connect(func() -> void:
						if is_instance_valid(eff):
							eff.queue_free())
				remove_meta("dash_effect")
		else:
			set_meta("dash_elapsed", elapsed)
		return

	# Movement
	var cur_speed: float = SPEED * player_speed_mult * _slow_mult * _get_level_speed_mult()
	if _crouching:
		cur_speed = CROUCH_SPEED
	elif want_sprint and _stamina > 0.0 and not _stamina_exhausted:
		cur_speed = SPRINT_SPEED

	var dir := Vector3.ZERO
	var basis := global_transform.basis
	if Input.is_action_pressed("move_forward"): dir -= basis.z
	if Input.is_action_pressed("move_back"):    dir += basis.z
	if Input.is_action_pressed("move_left"):    dir -= basis.x
	if Input.is_action_pressed("move_right"):   dir += basis.x
	dir.y = 0
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
	velocity.x = dir.x * cur_speed
	velocity.z = dir.z * cur_speed
	move_and_slide()

	# Footsteps — play only for the local player when grounded and moving
	var horiz_sq: float = Vector2(velocity.x, velocity.z).length_squared()
	if is_on_floor() and horiz_sq > 0.5:
		_step_timer -= delta
		if _step_timer <= 0.0:
			var is_sprinting: bool = want_sprint and _stamina > 0.0 and not _stamina_exhausted
			_step_timer = FOOTSTEP_INTERVAL_SPRINT if is_sprinting else FOOTSTEP_INTERVAL_WALK
			var snd: String = FOOTSTEP_SOUNDS[randi() % FOOTSTEP_SOUNDS.size()]
			SoundManager.play_3d(snd, global_position, -8.0, randf_range(0.9, 1.1))
	else:
		_step_timer = 0.0

	# Drive avatar walk/idle animation from actual velocity
	if _anim != null and _anim.is_inside_tree():
		var horiz_speed_sq: float = Vector2(velocity.x, velocity.z).length_squared()
		var want_anim: String = "walk" if horiz_speed_sq > 0.25 else "idle"
		if _anim.current_animation != want_anim:
			_anim.play(want_anim)

	# Broadcast transform to host every N frames (local player only)
	if is_local:
		_sync_frame += 1
		if _sync_frame >= PLAYER_SYNC_INTERVAL:
			_sync_frame = 0
			var cam_rot: Vector3 = camera.global_rotation
			var pos_delta_sq: float = global_position.distance_squared_to(_last_sent_pos)
			var rot_delta: float = (cam_rot - _last_sent_rot).length()
			if pos_delta_sq >= _TRANSFORM_POS_THRESHOLD_SQ or rot_delta >= _TRANSFORM_ROT_THRESHOLD:
				_last_sent_pos = global_position
				_last_sent_rot = cam_rot
				# report_player_transform is call_local — works for both host and clients.
				# Host calls rpc_id(1, ...) which executes locally (call_local), then
				# broadcast_player_transform.rpc() fans out to all clients exactly once.
				LobbyManager.report_player_transform.rpc_id(1, global_position, cam_rot, player_team)

func _set_crouch(crouch: bool) -> void:
	_crouching = crouch
	if crouch:
		camera.position.y = CAM_Y_CROUCH
		(col_shape.shape as CapsuleShape3D).height = CAP_H_CROUCH
	else:
		camera.position.y = CAM_Y_STAND
		(col_shape.shape as CapsuleShape3D).height = CAP_H_STAND

func _shoot() -> void:
	if not is_inside_tree() or not is_instance_valid(shoot_from) or not shoot_from.is_inside_tree():
		return
	if _reloading or _fire_cooling:
		return
	var w: WeaponData = _current_weapon()
	if w == null:
		return

	var mag: int = _slot_ammo[active_slot][0]
	if mag <= 0:
		# Auto-trigger reload on empty
		_start_reload()
		return

	# Consume ammo
	_slot_ammo[active_slot][0] = mag - 1

	# Start fire cooldown — f_rapid_fire reduces interval for current weapon
	_fire_cooling = true
	var _rapid_fire_active: bool = has_meta("rapid_fire_timer") and \
		(get_meta("rapid_fire_weapon", "") == "" or get_meta("rapid_fire_weapon", "") == w.weapon_name)
	_fire_timer = w.fire_rate / (3.0 if _rapid_fire_active else 1.0)

	# Play fire sound
	if shoot_audio.stream != null:
		shoot_audio.play()

	var dir: Vector3 = -camera.global_transform.basis.z
	var is_rocket: bool = (w.weapon_name == "Rocket Launcher")

	if is_rocket:
		var rocket: Node3D = RocketScene.instantiate()
		rocket.damage         = w.damage * player_damage_mult * _get_level_damage_mult()
		rocket.source         = "rocket"
		rocket.shooter_team   = player_team
		rocket.shooter_peer_id = peer_id
		rocket.velocity       = dir * w.bullet_speed
		VfxUtils.get_scene_root(self).add_child(rocket)
		rocket.global_position = shoot_from.global_position
		# Multiplayer: server broadcasts rocket spawn to all clients
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				LobbyManager.spawn_bullet_visuals.rpc(shoot_from.global_position, dir, w.damage, player_team, peer_id, "rocket")
			else:
				var rocket_hit_info: Dictionary = _local_raycast_hit(shoot_from.global_position, dir)
				LobbyManager.validate_shot.rpc_id(1, shoot_from.global_position, dir, w.damage * player_damage_mult * _get_level_damage_mult(), player_team, peer_id, rocket_hit_info, "rocket")
	else:
		var bullet: Node3D = BulletScene.instantiate()
		bullet.damage        = w.damage * player_damage_mult * _get_level_damage_mult()
		bullet.source        = "player"
		bullet.shooter_team  = player_team
		bullet.set_meta("shooter_peer_id", peer_id)
		bullet.set("shooter_peer_id", peer_id)
		bullet.velocity      = dir * w.bullet_speed
		VfxUtils.get_scene_root(self).add_child(bullet)
		bullet.global_position = shoot_from.global_position
		var main: Node = get_tree().root.get_node("Main")
		if main.has_method("_on_bullet_hit_something") and bullet.shooter_peer_id == peer_id:
			bullet.hit_something.connect(main._on_bullet_hit_something)
		# Send to host for authoritative validation + broadcast to other clients
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				LobbyManager.spawn_bullet_visuals.rpc(shoot_from.global_position, dir, w.damage, player_team, peer_id)
			else:
				var hit_info: Dictionary = _local_raycast_hit(shoot_from.global_position, dir)
				LobbyManager.validate_shot.rpc_id(1, shoot_from.global_position, dir, w.damage * player_damage_mult * _get_level_damage_mult(), player_team, peer_id, hit_info)

	_update_ammo_hud()
	_play_kick_animation()

	# Auto-reload when mag hits 0
	if _slot_ammo[active_slot][0] == 0:
		_start_reload()

# Client-side instant raycast at fire time — identifies what was aimed at so the
# server can apply damage without needing a server-side raycast (which can't see
# other clients' player bodies or accurately place puppet minions).
func _local_raycast_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 500.0)
	query.exclude = [self]
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return {}
	var node: Node = result.collider if result.collider is Node else null
	if node == null:
		return {}
	var check: Node = node
	while check != null and check != get_tree().root:
		if check == self:
			return {}
		if check.has_meta("ghost_peer_id"):
			var ghost_peer: int = check.get_meta("ghost_peer_id") as int
			if ghost_peer > 0 and ghost_peer != peer_id:
				return {"peer_id": ghost_peer}
		if check.name.begins_with("FPSPlayer_") and check.get("player_team") != null:
			var id_str: String = check.name.substr(10)
			if id_str.is_valid_int():
				var host_peer: int = id_str.to_int()
				var target_team: int = GameSync.get_player_team(host_peer)
				if host_peer != peer_id:
					if target_team != player_team:
						return {"peer_id": host_peer}
					return {}
		if check.get("_minion_id") != null and check.get("is_puppet") == true:
			var mid: int = check.get("_minion_id") as int
			var mteam: int = check.get("team") as int
			if mteam == player_team:
				return {}
			return {"minion_id": mid}
		# Tower hit — report hit position to server for proximity lookup
		if check.is_in_group("towers"):
			return {"tower_pos": result.position}
		if check.get_parent() != null and check.get_parent().is_in_group("towers"):
			return {"tower_pos": result.position}
		check = check.get_parent()
	return {}

func _start_reload() -> void:
	if _reloading:
		return
	var w: WeaponData = _current_weapon()
	if w == null:
		return
	var mag: int = _slot_ammo[active_slot][0]
	var reserve: int = _slot_ammo[active_slot][1]
	# Nothing to reload
	if mag >= w.magazine_size or reserve <= 0:
		return
	_reloading    = true
	_reload_timer = w.reload_time * _get_skill_reload_mult()
	if reload_prompt != null:
		reload_prompt.visible = false
	_update_reload_bar()
	_play_reload_animation()

func _play_reload_animation() -> void:
	if _reload_tween:
		_reload_tween.kill()
	weapon_model.position = WEAPON_REST_POS
	weapon_model.rotation = WEAPON_REST_ROT

	_reload_tween = create_tween()
	var t: float = _reload_timer

	# Phase 1: drop out (40% of reload time)
	_reload_tween.tween_property(weapon_model, "position", WEAPON_RELOAD_POS, t * 0.4)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_reload_tween.parallel().tween_property(weapon_model, "rotation", WEAPON_RELOAD_ROT, t * 0.4)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Phase 2: hold at reload position (20%)
	_reload_tween.tween_interval(t * 0.2)

	# Phase 3: return to rest (40%)
	_reload_tween.tween_property(weapon_model, "position", WEAPON_REST_POS, t * 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_reload_tween.parallel().tween_property(weapon_model, "rotation", WEAPON_REST_ROT, t * 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_reload_tween.parallel().tween_property(weapon_model, "rotation", WEAPON_REST_ROT, t * 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _play_kick_animation() -> void:
	if _kick_tween:
		_kick_tween.kill()
	_kicking = true
	_kick_tween = create_tween()
	_kick_tween.tween_property(weapon_model, "position", KICK_POS, KICK_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_kick_tween.tween_property(weapon_model, "position", WEAPON_REST_POS, KICK_RETURN_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_kick_tween.chain().tween_callback(func():
		_kicking = false
	)

func _finish_reload() -> void:
	var w: WeaponData = _current_weapon()
	if w == null:
		return
	var mag: int = _slot_ammo[active_slot][0]
	var reserve: int = _slot_ammo[active_slot][1]
	var needed: int = w.magazine_size - mag
	var transfer: int = min(needed, reserve)
	_slot_ammo[active_slot][0] = mag + transfer
	_slot_ammo[active_slot][1] = reserve - transfer
	if reload_bar:
		reload_bar.visible = false
	_update_ammo_hud()
	_report_ammo_to_server()

func _update_reload_bar() -> void:
	if reload_bar == null:
		return
	var w: WeaponData = _current_weapon()
	if not _reloading or w == null:
		reload_bar.visible = false
		return
	reload_bar.visible = true
	reload_bar.value   = (1.0 - _reload_timer / w.reload_time) * 100.0

func _update_stamina_bar() -> void:
	if stamina_bar == null:
		return
	stamina_bar.value = (_stamina / _get_max_stamina()) * 100.0

func _update_points_label() -> void:
	if points_label == null:
		return
	var blue_pts: int = TeamData.get_points(0)
	var red_pts: int = TeamData.get_points(1)
	points_label.text = "BLUE: %d | RED: %d" % [blue_pts, red_pts]

func _on_game_sync_died(p_peer_id: int) -> void:
	if p_peer_id != peer_id:
		return
	# Fallback — health_changed handler handles death now, but keep as safety net.
	if not _dead:
		_on_death()

func _on_game_sync_health_changed(p_peer_id: int, new_hp: float) -> void:
	if p_peer_id != peer_id:
		return
	if _dead:
		return
	if _syncing_heal:
		return
	var was_damaged: bool = new_hp < hp
	hp = new_hp
	if was_damaged:
		camera_shake_time = 0.35
		var _main := get_tree().current_scene
		if _main != null and _main.has_method("flash_damage"):
			_main.flash_damage()
	_update_health_bar()
	if hp <= 0.0:
		_on_death()
		var awarding_team: int = 1 - player_team
		TeamData.add_points(awarding_team, 50)
		_update_points_label()

func _on_game_sync_respawned(p_peer_id: int, spawn_pos: Vector3) -> void:
	if p_peer_id != peer_id:
		return
	respawn(spawn_pos)

func _fire_ping() -> void:
	print("[PING-FPS] _fire_ping called, player_team=%d" % player_team)
	# Raycast from camera forward to get world position for ping.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = shoot_from.global_position
	var dir: Vector3 = -shoot_from.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 500.0)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	var world_pos: Vector3 = result.get("position", origin + dir * 100.0) as Vector3
	if multiplayer.is_server():
		print("[PING-FPS] is_server=true")
		LobbyManager.request_ping(world_pos, player_team)
	else:
		print("[PING-FPS] client path, rpc to server")
		LobbyManager.request_ping.rpc_id(1, world_pos, player_team)
