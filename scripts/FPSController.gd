extends CharacterBody3D

const SPEED         := 8.0
const SPRINT_SPEED  := 14.0
const CROUCH_SPEED  := 4.0
const JUMP_VELOCITY := 6.0
const MOUSE_SENSITIVITY := 0.003
const GRAVITY       := 20.0
const SHOOT_DAMAGE  := 25.0
const BULLET_SPEED  := 280.0
const RELOAD_TIME   := 1.5

const FOV_NORMAL  := 75.0
const FOV_ZOOM    := 30.0
const FOV_LERP    := 12.0

const CAM_Y_STAND  := 0.8
const CAM_Y_CROUCH := 0.45
const CAP_H_STAND  := 1.8
const CAP_H_CROUCH := 0.9

const MAX_HP := 100.0

var active := true
var hp: float = MAX_HP
var _dead := false
var _crouching := false
var _reload_timer := 0.0
var _reloading := false

# Set by Main.gd after scene ready
var reload_bar: ProgressBar = null
var health_bar: ProgressBar = null

signal died

@onready var camera: Camera3D            = $Camera3D
@onready var shoot_from: Node3D          = $Camera3D/ShootFrom
@onready var col_shape: CollisionShape3D = $CollisionShape3D

const BulletScene := preload("res://scenes/Bullet.tscn")

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
	_dead = false
	hp = MAX_HP
	global_position = spawn_pos
	velocity = Vector3.ZERO
	_reloading = false
	_reload_timer = 0.0
	_update_health_bar()
	if reload_bar:
		reload_bar.visible = false

func _on_death() -> void:
	_dead = true
	active = false
	camera.current = false
	emit_signal("died")

func _update_health_bar() -> void:
	if health_bar == null:
		return
	health_bar.value = (hp / MAX_HP) * 100.0

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2.2, PI/2.2)
	if event.is_action_pressed("shoot"):
		_shoot()

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
	var target_fov := FOV_ZOOM if Input.is_action_pressed("zoom") else FOV_NORMAL
	camera.fov = lerp(camera.fov, target_fov, FOV_LERP * delta)

	# Reload tick
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_reload_timer = 0.0
			_reloading = false
		_update_reload_bar()

	# Movement speed
	var cur_speed := SPEED
	if _crouching:
		cur_speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		cur_speed = SPRINT_SPEED

	var dir := Vector3.ZERO
	var basis := global_transform.basis
	if Input.is_action_pressed("move_forward"):
		dir -= basis.z
	if Input.is_action_pressed("move_back"):
		dir += basis.z
	if Input.is_action_pressed("move_left"):
		dir -= basis.x
	if Input.is_action_pressed("move_right"):
		dir += basis.x
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
	if _reloading:
		return
	_reloading = true
	_reload_timer = RELOAD_TIME
	_update_reload_bar()

	var bullet: Node3D = BulletScene.instantiate()
	bullet.damage       = SHOOT_DAMAGE
	bullet.source       = "player"
	bullet.shooter_team = -1
	var dir: Vector3    = -camera.global_transform.basis.z
	bullet.velocity     = dir * BULLET_SPEED
	bullet.global_position = shoot_from.global_position
	get_tree().root.get_child(0).add_child(bullet)

func _update_reload_bar() -> void:
	if reload_bar == null:
		return
	if not _reloading:
		reload_bar.visible = false
		return
	reload_bar.visible = true
	reload_bar.value = (1.0 - _reload_timer / RELOAD_TIME) * 100.0
