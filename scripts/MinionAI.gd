extends CharacterBody3D

const GRAVITY          := 20.0
const MAX_HEALTH       := 60.0
const DETECT_RANGE     := 12.0
const DARK_DETECT_RANGE := 5.0
const DARK_MISS_CHANCE  := 0.60
const SHOOT_RANGE      := 10.0
const SEPARATION_DIST  := 2.2
const SEPARATION_FORCE := 6.0
const BULLET_SPEED     := 84.0

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
var points_label: Label = null
var hud_ui: Control = null

var waypoints: Array[Vector3] = []
var current_waypoint := 0

@onready var char_blue:  Node3D               = $CharacterBlue
@onready var char_red:   Node3D               = $CharacterRed
@onready var shoot_audio: AudioStreamPlayer3D = $ShootAudio
@onready var death_audio: AudioStreamPlayer3D = $DeathAudio

var _team_mat: StandardMaterial3D
var _active_char: Node3D = null
var _anim: AnimationPlayer = null

const BulletScene := preload("res://scenes/Bullet.tscn")

static var _blue_model_char := "e"
static var _red_model_char  := "b"

static var _blue_scene_cache: PackedScene = null
static var _red_scene_cache:  PackedScene = null

static func set_model_characters(blue_char: String, red_char: String) -> void:
	_blue_model_char = blue_char
	_red_model_char  = red_char
	_blue_scene_cache = null
	_red_scene_cache  = null

static func get_blue_model_path() -> String:
	return "res://assets/kenney_blocky-characters/Models/GLB format/character-%s.glb" % _blue_model_char

static func get_red_model_path() -> String:
	return "res://assets/kenney_blocky-characters/Models/GLB format/character-%s.glb" % _red_model_char

# Throttle counters
const TARGET_INTERVAL    := 10  # frames between target rescans
const SEPARATION_INTERVAL := 3  # frames between separation passes
var _target_frame   := 0
var _sep_frame      := 0

# Cached node references
var _cached_towers: Array = []
var _cached_bases:  Array = []
var _enemy_base: Node3D = null

func _ready() -> void:
	add_to_group("minions")
	add_to_group("minion_units")
	call_deferred("_init_visuals")
	call_deferred("_create_hud_element")
	call_deferred("_cache_static_refs")

func _init_visuals() -> void:
	# Get character nodes from scene tree
	char_blue = $CharacterBlue
	char_red  = $CharacterRed
	
	# Load and add models — use static cache so load() only runs once ever
	if _blue_scene_cache == null:
		_blue_scene_cache = load(get_blue_model_path())
	if _red_scene_cache == null:
		_red_scene_cache = load(get_red_model_path())

	if _blue_scene_cache:
		var blue_model: Node = _blue_scene_cache.instantiate()
		char_blue.add_child(blue_model)
		blue_model.scale = Vector3(0.667, 0.667, 0.667)
		blue_model.rotate_y(PI)
		_disable_shadows(blue_model)

	if _red_scene_cache:
		var red_model: Node = _red_scene_cache.instantiate()
		char_red.add_child(red_model)
		red_model.scale = Vector3(0.667, 0.667, 0.667)
		red_model.rotate_y(PI)
		_disable_shadows(red_model)
	
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
	_add_shadow_proxy()

func _add_shadow_proxy() -> void:
	var proxy := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	proxy.mesh = mesh
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(proxy)

func _disable_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)

func _cache_static_refs() -> void:
	_cached_towers = get_tree().get_nodes_in_group("towers")
	_cached_bases  = get_tree().get_nodes_in_group("bases")
	var enemy_team: int = 1 if team == 0 else 0
	for b in _cached_bases:
		if b.team == enemy_team:
			_enemy_base = b
			break

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

	# Throttle: rescan for target every TARGET_INTERVAL frames
	_target_frame += 1
	if _target_frame >= TARGET_INTERVAL:
		_target_frame = 0
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

	# Throttle: apply separation every SEPARATION_INTERVAL frames
	_sep_frame += 1
	if _sep_frame >= SEPARATION_INTERVAL:
		_sep_frame = 0
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
	if current_waypoint < waypoints.size():
		# Follow waypoints
		var dest := waypoints[current_waypoint]
		dest.y = global_position.y
		var dir: Vector3 = dest - global_position
		if dir.length() < 0.5:
			current_waypoint += 1
			return
		var horiz: Vector3 = dir.normalized()
		velocity.x = horiz.x * speed
		velocity.z = horiz.z * speed
		_face(dest)
	elif _target == null:
		# Waypoints exhausted, continue to enemy base using cached ref
		if _enemy_base and is_instance_valid(_enemy_base):
			var to_base: Vector3 = _enemy_base.global_position - global_position
			to_base.y = 0.0
			if to_base.length() > 2.0:
				var dir: Vector3 = to_base.normalized()
				velocity.x = dir.x * speed
				velocity.z = dir.z * speed
				_face(to_base)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		# We have a target, don't move (already handled in main logic)
		velocity.x = 0.0
		velocity.z = 0.0

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
		var effective_range: float = DARK_DETECT_RANGE if _is_in_darkness(m.global_position) else DETECT_RANGE
		if d < effective_range and d < best_dist:
			best_dist = d
			best = m
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get"):
		var p_team: int = player.get("player_team") if player.get("player_team") != null else -1
		if p_team != team and p_team >= 0:
			var d: float = global_position.distance_to(player.global_position)
			var effective_range: float = DARK_DETECT_RANGE if _is_in_darkness(player.global_position) else DETECT_RANGE
			if d < effective_range and d < best_dist:
				best_dist = d
				best = player
	for t in _cached_towers:
		if not is_instance_valid(t) or t.team == team:
			continue
		var d: float = global_position.distance_to(t.global_position)
		if d < best_dist:
			best_dist = d
			best = t
	for b in _cached_bases:
		if not is_instance_valid(b) or b.team == team:
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d < best_dist:
			best_dist = d
			best = b
	return best

func _is_in_darkness(pos: Vector3) -> bool:
	var lamp_placer: Node = get_node_or_null("/root/Main/World/LampPlacer")
	if lamp_placer == null:
		return false
	var scripts: Array = lamp_placer.get("lamp_scripts") if lamp_placer.get("lamp_scripts") != null else []
	for lamp in scripts:
		if lamp.is_dark:
			continue
		# lamp position is its parent StaticBody3D world position
		var lamp_pos: Vector3 = lamp.get_parent().global_position
		if lamp_pos.distance_to(pos) <= 22.0:
			return false
	return true

func _fire_at(target: Node3D) -> void:
	if not is_inside_tree() or not is_instance_valid(target) or not target.is_inside_tree():
		return
	# Miss chance when target is in darkness
	if _is_in_darkness(target.global_position) and randf() < DARK_MISS_CHANCE:
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
	get_tree().root.get_child(0).add_child(bullet)
	bullet.global_position = spawn_pos

	if multiplayer.is_server():
		LobbyManager.spawn_bullet_visuals.rpc(bullet.global_position, dir, attack_damage, team)

	shoot_audio.play()

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if _dead:
					return
	health -= amount
	if health <= 0.0:
		_die()
		var awarding_team: int = _killer_team if _killer_team >= 0 else 0
		var pts: int = 10 if _killer_team == -1 else 5
		TeamData.add_points(awarding_team, pts)
		_update_points_label()

func _create_hud_element() -> void:
	var entity_hud := get_node_or_null("/root/Main/HUD/HUDOverlay/EntityHUD")
	if entity_hud and entity_hud.has_method("register_entity"):
		var id: int = entity_hud.call("register_entity", self, MAX_HEALTH, team)
		var entry: Dictionary = entity_hud.call("get_entity_by_id", id)
		if not entry.is_empty():
			hud_ui = entry.ui_node

func _update_points_label() -> void:
	if points_label == null:
		return
	var blue_pts: int = TeamData.get_points(0)
	var red_pts: int = TeamData.get_points(1)
	points_label.text = "BLUE: %d | RED: %d" % [blue_pts, red_pts]

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

	if multiplayer.is_server():
		var path: NodePath = get_path()
		LobbyManager.kill_minion_visuals.rpc(path)

func force_die() -> void:
	_die()
