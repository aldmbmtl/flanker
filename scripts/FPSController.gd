extends CharacterBody3D

const SPEED             := 8.0
const SPRINT_SPEED      := 14.0
const CROUCH_SPEED      := 4.0
const JUMP_VELOCITY     := 6.0
const MOUSE_SENSITIVITY := 0.003
const GRAVITY           := 20.0

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

var _reload_timer: float = 0.0
var _reloading           := false

# 2-slot weapon inventory; slot 0 = default pistol, slot 1 = empty initially
var weapons: Array = [null, null]
var active_slot: int = 0

# Set by Main.gd after scene ready
var reload_bar: ProgressBar  = null
var health_bar: ProgressBar  = null
var weapon_label: Label      = null

signal died
signal weapon_changed(slot: int, weapon: WeaponData)

@onready var camera:      Camera3D           = $Camera3D
@onready var shoot_from:  Node3D             = $Camera3D/ShootFrom
@onready var weapon_model: Node3D            = $Camera3D/WeaponModel
@onready var col_shape:   CollisionShape3D   = $CollisionShape3D
@onready var shoot_audio: AudioStreamPlayer3D = $ShootAudio

const BulletScene := preload("res://scenes/Bullet.tscn")

func _ready() -> void:
	# Load default pistol into slot 0
	var default_weapon: WeaponData = load(DEFAULT_WEAPON_PATH)
	if default_weapon:
		weapons[0] = default_weapon
	_refresh_viewmodel()
	_update_weapon_label()

func set_active(is_active: bool) -> void:
	active = is_active
	if not _dead:
		camera.current = is_active

func take_damage(amount: float, _source: String) -> void:
	if _dead:
		return
	hp = max(0.0, hp - amount)
	_update_health_bar()
	if hp <= 0.0:
		_on_death()

func respawn(spawn_pos: Vector3) -> void:
	_dead        = false
	hp           = MAX_HP
	global_position = spawn_pos
	velocity     = Vector3.ZERO
	_reloading   = false
	_reload_timer = 0.0
	_update_health_bar()
	if reload_bar:
		reload_bar.visible = false

func pick_up_weapon(w: WeaponData) -> void:
	# If slot 1 is empty, fill it; otherwise replace active slot
	if weapons[1] == null:
		weapons[1] = w
		active_slot = 1
	else:
		weapons[active_slot] = w
	_refresh_viewmodel()
	_update_weapon_label()
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

func _update_weapon_label() -> void:
	if weapon_label == null:
		return
	var s1: String = weapons[0].weapon_name if weapons[0] else "—"
	var s2: String = weapons[1].weapon_name if weapons[1] else "—"
	var marker1: String = ">" if active_slot == 0 else " "
	var marker2: String = ">" if active_slot == 1 else " "
	weapon_label.text = "%s[1] %s   %s[2] %s" % [marker1, s1, marker2, s2]

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
	_reloading  = false
	_reload_timer = 0.0
	if reload_bar:
		reload_bar.visible = false
	_refresh_viewmodel()
	_update_weapon_label()

func _physics_process(delta: float) -> void:
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

	# Reload tick
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_reload_timer = 0.0
			_reloading    = false
		_update_reload_bar()

	# Movement
	var cur_speed: float = SPEED
	if _crouching:
		cur_speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
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
	if _reloading:
		return
	var w: WeaponData = _current_weapon()
	if w == null:
		return

	_reloading    = true
	_reload_timer = w.reload_time
	_update_reload_bar()

	# Play fire sound
	if shoot_audio.stream != null:
		shoot_audio.play()

	var bullet: Node3D = BulletScene.instantiate()
	bullet.damage        = w.damage
	bullet.source        = "player"
	bullet.shooter_team  = -1
	var dir: Vector3     = -camera.global_transform.basis.z
	bullet.velocity      = dir * w.bullet_speed
	get_tree().root.get_child(0).add_child(bullet)
	bullet.global_position = shoot_from.global_position

func _update_reload_bar() -> void:
	if reload_bar == null:
		return
	var w: WeaponData = _current_weapon()
	if not _reloading or w == null:
		reload_bar.visible = false
		return
	reload_bar.visible = true
	reload_bar.value   = (1.0 - _reload_timer / w.reload_time) * 100.0
