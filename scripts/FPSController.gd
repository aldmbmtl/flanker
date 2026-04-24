extends CharacterBody3D

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

const ROLE_STATS := {
	"Tank":    {"hp": 150, "speed_mult": 0.8, "damage_mult": 0.7},
	"DPS":     {"hp": 100, "speed_mult": 1.0, "damage_mult": 1.2},
	"Support": {"hp": 80,  "speed_mult": 1.0, "damage_mult": 0.8},
	"Sniper":  {"hp": 70,  "speed_mult": 1.0, "damage_mult": 1.5},
	"Flanker": {"hp": 90,  "speed_mult": 1.3, "damage_mult": 1.0},
}
const DEFAULT_HP := 100.0

var player_team: int = 0
var player_role: String = ""

var player_health_mult: float = 1.0
var player_speed_mult: float = 1.0
var player_damage_mult: float = 1.0

var _peer_id: int = 1
var _is_local: bool = true
var _sync_frame: int = 0

const FOV_NORMAL  := 75.0
const FOV_ZOOM    := 30.0
const FOV_LERP    := 12.0

const CAM_Y_STAND  := 0.8
const CAM_Y_CROUCH := 0.45
const CAP_H_STAND  := 1.8
const CAP_H_CROUCH := 0.9

const MAX_HP := 100.0

const DEFAULT_WEAPON_PATH := "res://assets/weapons/weapon_pistol.tres"

var active    := true
var hp: float  = MAX_HP
var _dead      := false
var _crouching := false
var hud_ui: Control = null
var hud_id: int = 0

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

# 2-slot weapon inventory; slot 0 = default pistol, slot 1 = empty initially
var weapons: Array = [null, null]
var active_slot: int = 0

# Per-slot ammo: [mag_ammo, reserve_ammo]
var _slot_ammo: Array = [[0, 0], [0, 0]]

# Set by Main.gd after scene ready
var reload_bar: ProgressBar  = null
var health_bar: ProgressBar  = null
var weapon_label: Label      = null
var ammo_label: Label        = null
var reload_prompt: Label     = null
var stamina_bar: ProgressBar = null
var points_label: Label    = null

signal died
signal weapon_changed(slot: int, weapon: WeaponData)

@onready var camera:      Camera3D           = $Camera3D
@onready var shoot_from:  Node3D             = $Camera3D/ShootFrom
@onready var weapon_model: Node3D            = $Camera3D/WeaponModel
@onready var col_shape:   CollisionShape3D   = $CollisionShape3D
@onready var shoot_audio: AudioStreamPlayer3D = $ShootAudio

const CAMERA_SHAKE_SPEED := 20.0
const CAMERA_SHAKE_AMP := 0.15

var camera_shake_time := 0.0
var _base_cam_y := 0.0

const BulletScene := preload("res://scenes/Bullet.tscn")
const PLAYER_SYNC_INTERVAL := 5

func _ready() -> void:
	add_to_group("players")
	_base_cam_y = camera.position.y
	var _has_network_peer: bool = NetworkManager._peer != null
	_peer_id = multiplayer.get_unique_id() if _has_network_peer else 1
	_is_local = not _has_network_peer or multiplayer.get_unique_id() == _peer_id
	
	if _has_network_peer:
		var my_id := multiplayer.get_unique_id()
		_is_local = (name == "FPSPlayer_%d" % my_id)
		var info: Dictionary = LobbyManager.players.get(my_id, {})
		if info.has("role"):
			player_role = info.role
			_apply_role_stats()
	
	# Register with GameSync so host can track us
	if _is_local:
		GameSync.set_player_team(_peer_id, player_team)
		GameSync.set_player_health(_peer_id, hp)
		GameSync.player_died.connect(_on_game_sync_died)
		GameSync.player_respawned.connect(_on_game_sync_respawned)
	
	_load_default_weapon()
	_refresh_viewmodel()
	_update_weapon_label()
	_update_ammo_hud()
	_create_hud_element(hud_id, MAX_HP, player_team)

func set_active(is_active: bool) -> void:
	active = is_active
	if not _dead:
		camera.current = is_active

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if _dead:
		return
	hp = max(0.0, hp - amount)
	camera_shake_time = 0.15
	_update_health_bar()
	_update_hud_health()
	if hp <= 0.0:
		_on_death()
		var awarding_team: int = _killer_team if _killer_team >= 0 else 1
		TeamData.add_points(awarding_team, 50)
		_update_points_label()

func _create_hud_element(_unused_id: int, max_health: float, team: int) -> void:
	var entity_hud := get_node_or_null("/root/Main/HUD/HUDOverlay/EntityHUD")
	if entity_hud and entity_hud.has_method("register_entity"):
		hud_id = entity_hud.call("register_entity", self, max_health, team)
		var entry: Dictionary = entity_hud.call("get_entity_by_id", hud_id)
		if not entry.is_empty():
			hud_ui = entry.ui_node

func _update_hud_health() -> void:
	var entity_hud := get_node_or_null("/root/Main/HUD/HUDOverlay/EntityHUD")
	if entity_hud and hud_ui and hud_id > 0:
		entity_hud.call("update_entity_health", hud_id, hp)

func _load_default_weapon() -> void:
	var default_weapon: WeaponData = load(DEFAULT_WEAPON_PATH)
	if default_weapon:
		weapons[0] = default_weapon
		_slot_ammo[0] = [default_weapon.magazine_size, default_weapon.reserve_ammo]

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
	_dead        = false
	var max_hp: float = DEFAULT_HP * player_health_mult
	hp           = max_hp
	global_position = spawn_pos
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
	_slot_ammo = [
		[weapons[0].magazine_size, weapons[0].reserve_ammo],
		[0, 0],
	]
	_update_health_bar()
	_update_ammo_hud()
	if reload_bar:
		reload_bar.visible = false
	if reload_prompt:
		reload_prompt.visible = false

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
	emit_signal("weapon_changed", active_slot, w)

func _on_death() -> void:
	_dead         = true
	active        = false
	camera.current = false
	emit_signal("died")

func _update_health_bar() -> void:
	if health_bar == null:
		return
	health_bar.value = (hp / MAX_HP) * 100.0
	
	var fill_style: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	if fill_style == null:
		fill_style = StyleBoxFlat.new()
		health_bar.add_theme_stylebox_override("fill", fill_style)
	
	var health_pct: float = hp / MAX_HP
	if health_pct > 0.6:
		fill_style.bg_color = Color(0.2, 0.9, 0.2, 1)
	elif health_pct > 0.3:
		fill_style.bg_color = Color(1, 0.9, 0.2, 1)
	else:
		fill_style.bg_color = Color(0.9, 0.2, 0.2, 1)

func _update_weapon_label() -> void:
	if weapon_label == null:
		return
	var s1: String = weapons[0].weapon_name if weapons[0] else "—"
	var s2: String = weapons[1].weapon_name if weapons[1] else "—"
	var marker1: String = ">" if active_slot == 0 else " "
	var marker2: String = ">" if active_slot == 1 else " "
	weapon_label.text = "%s[1] %s   %s[2] %s" % [marker1, s1, marker2, s2]

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
	if event is InputEventKey and event.pressed:
		print("[FPSController] _unhandled_input: keycode=", event.keycode)
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
	if not _is_local:
		return
	
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
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if not _reloading and not _kicking and is_on_floor() and speed > 0.5:
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
	if want_sprint and _stamina > 0.0:
		_stamina = max(0.0, _stamina - STAMINA_DRAIN_RATE * delta)
		_stamina_exhausted = false
		_exhaust_timer = 0.0
	elif not want_sprint and _stamina < MAX_STAMINA:
		if _stamina_exhausted:
			_exhaust_timer -= delta
			if _exhaust_timer <= 0.0:
				_stamina_exhausted = false
		else:
			_stamina = min(MAX_STAMINA, _stamina + STAMINA_REGEN_RATE * delta)
	elif _stamina <= 0.0 and not _stamina_exhausted:
		_stamina_exhausted = true
		_exhaust_timer = STAMINA_EXHAUST_CD
	_update_stamina_bar()

	# Movement
	var cur_speed: float = SPEED * player_speed_mult
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
	if dir.length() > 0:
		dir = dir.normalized()
	velocity.x = dir.x * cur_speed
	velocity.z = dir.z * cur_speed
	move_and_slide()

	# Broadcast transform to host every N frames (local player only)
	if multiplayer.has_multiplayer_peer() and _is_local and _peer_id != multiplayer.get_unique_id():
		_sync_frame += 1
		if _sync_frame >= PLAYER_SYNC_INTERVAL:
			_sync_frame = 0
			var cam_rot: Vector3 = camera.global_rotation
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

	# Start fire cooldown
	_fire_cooling = true
	_fire_timer   = w.fire_rate

	# Play fire sound
	if shoot_audio.stream != null:
		shoot_audio.play()

	var bullet: Node3D = BulletScene.instantiate()
	bullet.damage        = w.damage
	bullet.source        = "player"
	bullet.shooter_team  = player_team
	var dir: Vector3     = -camera.global_transform.basis.z
	bullet.velocity      = dir * w.bullet_speed
	get_tree().root.get_child(0).add_child(bullet)
	bullet.global_position = shoot_from.global_position

	# Send to host for authoritative validation + broadcast to other clients
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			LobbyManager.spawn_bullet_visuals.rpc(shoot_from.global_position, dir, w.damage, player_team)
		else:
			LobbyManager.validate_shot.rpc_id(1, shoot_from.global_position, dir, w.damage * player_damage_mult, player_team, _peer_id)

	_update_ammo_hud()
	_play_kick_animation()

	# Auto-reload when mag hits 0
	if _slot_ammo[active_slot][0] == 0:
		_start_reload()

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
	_reload_timer = w.reload_time
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
	stamina_bar.value = (_stamina / MAX_STAMINA) * 100.0

func _update_points_label() -> void:
	if points_label == null:
		return
	var blue_pts: int = TeamData.get_points(0)
	var red_pts: int = TeamData.get_points(1)
	points_label.text = "BLUE: %d | RED: %d" % [blue_pts, red_pts]

func _on_game_sync_died(peer_id: int) -> void:
	if peer_id != _peer_id:
		return
	# Local player death already handled by take_damage → _on_death.
	# This fires when host authoritatively kills us (network damage path).
	if not _dead:
		_on_death()

func _on_game_sync_respawned(peer_id: int, spawn_pos: Vector3) -> void:
	if peer_id != _peer_id:
		return
	respawn(spawn_pos)
