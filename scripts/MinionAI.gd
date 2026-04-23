extends CharacterBody3D

const GRAVITY          := 20.0
const MAX_HEALTH       := 60.0
const DETECT_RANGE     := 12.0
const SHOOT_RANGE      := 10.0
const SEPARATION_DIST  := 2.2
const SEPARATION_FORCE := 6.0
const BULLET_SPEED     := 120.0

const MINION_SHOOT_SOUND := "res://assets/kenney_sci-fi-sounds/Audio/laserSmall_002.ogg"
const MINION_DEATH_SOUND := "res://assets/kenney_sci-fi-sounds/Audio/impactMetal_000.ogg"

var team    := 0
var health  := MAX_HEALTH
var speed   := 4.0
var attack_range    := 2.5
var attack_damage   := 8.0
var attack_cooldown := 1.5
var _attack_timer   := 0.0
var _target: Node3D = null
var _lane_index     := 0
var _dead           := false
var _time           := 0.0
var _strafe_phase   := 0.0

var waypoints: Array[Vector3] = []
var current_waypoint := 0

@onready var char_blue:  Node3D               = $CharacterBlue
@onready var char_red:   Node3D               = $CharacterRed
@onready var hp_bar_bg:  MeshInstance3D       = $HPBar/Background
@onready var hp_bar_fg:  MeshInstance3D       = $HPBar/Foreground
@onready var shoot_audio: AudioStreamPlayer3D = $ShootAudio
@onready var death_audio: AudioStreamPlayer3D = $DeathAudio

var _team_mat: StandardMaterial3D
var _active_char: Node3D = null
var _anim: AnimationPlayer = null

const BulletScene := preload("res://scenes/Bullet.tscn")

const BLUE_MODEL_PATH := "res://assets/kenney_blocky-characters/Models/GLB format/character-e.glb"
const RED_MODEL_PATH  := "res://assets/kenney_blocky-characters/Models/GLB format/character-b.glb"

func _ready() -> void:
	add_to_group("minions")
	call_deferred("_init_visuals")

func _init_visuals() -> void:
	# Get character nodes from scene tree
	char_blue = $CharacterBlue
	char_red  = $CharacterRed
	
	# Load and add models at runtime
	var blue_scene: PackedScene = load(BLUE_MODEL_PATH)
	if blue_scene:
		var blue_model: Node = blue_scene.instantiate()
		char_blue.add_child(blue_model)
		blue_model.scale = Vector3(0.667, 0.667, 0.667)
		blue_model.rotate_y(PI)
	
	var red_scene: PackedScene = load(RED_MODEL_PATH)
	if red_scene:
		var red_model: Node = red_scene.instantiate()
		char_red.add_child(red_model)
		red_model.scale = Vector3(0.667, 0.667, 0.667)
		red_model.rotate_y(PI)
	
	# Show the correct character body for this team
	char_blue.visible = (team == 0)
	char_red.visible  = (team == 1)
	_active_char = char_blue if team == 0 else char_red

	# Find the AnimationPlayer embedded in the GLB subtree
	_anim = _find_anim_player(_active_char)

	# Load audio streams
	var shoot_stream: AudioStream = load(MINION_SHOOT_SOUND)
	if shoot_stream:
		shoot_audio.stream = shoot_stream
	var death_stream: AudioStream = load(MINION_DEATH_SOUND)
	if death_stream:
		death_audio.stream = death_stream

	_play_anim("idle")
	_update_hp_bar()

func _find_anim_player(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child
		var found: AnimationPlayer = _find_anim_player(child)
		if found:
			return found
	return null

func _play_anim(anim_name: String) -> void:
	if _anim == null:
		return
	if _anim.has_animation(anim_name):
		if _anim.current_animation != anim_name:
			_anim.play(anim_name)
	elif _anim.has_animation("idle") and anim_name != "idle":
		# Fallback to idle if requested anim doesn't exist
		if _anim.current_animation != "idle":
			_anim.play("idle")

func setup(p_team: int, p_waypoints: Array[Vector3], p_lane: int) -> void:
	team          = p_team
	waypoints     = p_waypoints
	_lane_index   = p_lane
	current_waypoint = 0
	_strafe_phase = randf() * TAU

func _physics_process(delta: float) -> void:
	if _dead:
		return

	_time += delta

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	_attack_timer -= delta
	_target = _find_target()

	var moving := false

	if _target != null:
		var dist: float = global_position.distance_to(_target.global_position)
		var is_base: bool = _target.is_in_group("bases")

		if dist <= attack_range and is_base:
			_face(_target.global_position)
			velocity.x = 0.0
			velocity.z = 0.0
			if _attack_timer <= 0.0:
				_fire_at(_target)
				_attack_timer = attack_cooldown
		elif dist <= SHOOT_RANGE:
			_face(_target.global_position)
			velocity.x = 0.0
			velocity.z = 0.0
			if _attack_timer <= 0.0:
				_fire_at(_target)
				_attack_timer = attack_cooldown
		else:
			_approach_with_strafe(_target, delta)
			moving = true
	else:
		_march(delta)
		moving = velocity.length() > 0.5

	# Drive walk/idle animation
	if moving:
		_play_anim("walk")
	else:
		_play_anim("idle")

	_apply_separation()
	move_and_slide()

func _approach_with_strafe(target: Node3D, _delta: float) -> void:
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var forward := to_target.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var strafe := sin(_time * 2.2 + _strafe_phase)
	var move_dir := (forward + right * strafe * 0.55).normalized()
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	_face(target.global_position)

func _apply_separation() -> void:
	var push := Vector3.ZERO
	for m in get_tree().get_nodes_in_group("minions"):
		if m == self:
			continue
		var diff: Vector3 = global_position - m.global_position
		diff.y = 0.0
		var d: float = diff.length()
		if d < SEPARATION_DIST and d > 0.01:
			push += diff.normalized() * (SEPARATION_DIST - d) / SEPARATION_DIST
	if push.length() > 0.01:
		velocity.x += push.x * SEPARATION_FORCE
		velocity.z += push.z * SEPARATION_FORCE

func _march(_delta: float) -> void:
	if current_waypoint >= waypoints.size():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dest := waypoints[current_waypoint]
	dest.y = global_position.y
	var dir := dest - global_position
	if dir.length() < 0.5:
		current_waypoint += 1
		return
	var horiz := dir.normalized()
	velocity.x = horiz.x * speed
	velocity.z = horiz.z * speed
	_face(dest)

func _face(target: Vector3) -> void:
	var dir := target - global_position
	dir.y = 0
	if dir.length() > 0.01:
		look_at(global_position + dir, Vector3.UP)

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist := DETECT_RANGE
	for m in get_tree().get_nodes_in_group("minions"):
		if m == self or m.team == team or m._dead:
			continue
		var d: float = global_position.distance_to(m.global_position)
		if d < best_dist:
			best_dist = d
			best = m
	for b in get_tree().get_nodes_in_group("bases"):
		if b.team == team:
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d < best_dist:
			best_dist = d
			best = b
	return best

func _fire_at(target: Node3D) -> void:
	if not is_inside_tree() or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var spawn_pos: Vector3 = global_position + Vector3(0.0, 0.8, 0.0)
	var aim_pos: Vector3   = target.global_position + Vector3(0.0, 0.5, 0.0)
	var dir: Vector3       = (aim_pos - spawn_pos).normalized()
	dir.y += 0.04
	dir = dir.normalized()

	var bullet: Node3D = BulletScene.instantiate()
	bullet.damage        = attack_damage
	bullet.source        = "minion"
	bullet.shooter_team  = team
	bullet.velocity      = dir * BULLET_SPEED
	bullet.global_position = spawn_pos
	get_tree().root.get_child(0).add_child(bullet)

	shoot_audio.play()

func take_damage(amount: float, _source: String) -> void:
	if _dead:
		return
	health -= amount
	_update_hp_bar()
	if health <= 0.0:
		_die()

func _update_hp_bar() -> void:
	if hp_bar_fg == null:
		return
	var pct: float = clamp(health / MAX_HEALTH, 0.0, 1.0)
	hp_bar_fg.scale.x = pct
	hp_bar_fg.position.x = (pct - 1.0) * 0.5
	var fg_mat := StandardMaterial3D.new()
	fg_mat.albedo_color = Color(1.0 - pct, pct * 0.8, 0.05)
	fg_mat.flags_unshaded = true
	hp_bar_fg.material_override = fg_mat

func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("minions")
	_play_anim("death")
	death_audio.play()
	var tween := create_tween()
	tween.tween_interval(0.3)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(queue_free)
