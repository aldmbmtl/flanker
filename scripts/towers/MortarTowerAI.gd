extends StaticBody3D
## Mortar Tower — long-range ballistic shell, high damage, large splash.

const TOWER_SCENE := preload("res://assets/kenney_pirate-kit/Models/GLB format/tower-complete-small.glb")
const SHELL_SCENE := "res://scenes/MortarShell.tscn"

var team := 0
var health := 700.0
const MAX_HEALTH := 700.0
var attack_range := 50.0
var attack_damage := 80.0
var attack_cooldown := 3.5
var _attack_timer := 0.0
var _dead := false
var _shell_scene: PackedScene = null

@onready var area: Area3D = $Area3D

func setup(p_team: int) -> void:
	team = p_team
	add_to_group("towers")
	_shell_scene = load(SHELL_SCENE)
	_load_model()
	var shape := SphereShape3D.new()
	shape.radius = attack_range
	$Area3D/CollisionShape3D.shape = shape

func _load_model() -> void:
	var root: Node3D = TOWER_SCENE.instantiate()
	# Scale slightly larger to visually distinguish from cannon tower
	root.scale = Vector3(1.1, 1.3, 1.1)
	add_child(root)

func _process(delta: float) -> void:
	if _dead:
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		var target := _find_target()
		if target:
			_fire_shell(target)
			_attack_timer = attack_cooldown

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist := attack_range + 1.0
	for body in area.get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		var body_team := -1
		var pt = body.get("player_team")
		if pt != null:
			body_team = pt as int
		else:
			var t = body.get("team")
			if t != null:
				body_team = t as int
		if body_team == team:
			continue
		var d: float = global_position.distance_to(body.global_position)
		if d < best_dist and _has_line_of_sight(body):
			best_dist = d
			best = body
	return best

func _has_line_of_sight(target: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3(0.0, 2.5, 0.0)
	var to: Vector3 = target.global_position + Vector3(0.0, 0.8, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var excluded: Array[RID] = [get_rid(), target.get_rid()]
	for _attempt in range(4):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excluded
		query.collision_mask = 0b11
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return true
		var body: Object = result.collider
		if body != null and body.has_meta("tree_trunk_height"):
			excluded.append(body.get_rid())
			continue
		return false
	return true

func _fire_shell(target: Node3D) -> void:
	if _shell_scene == null:
		return
	var spawn_pos: Vector3 = global_position + Vector3(0.0, 2.5, 0.0)
	var aim_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)
	var shell: Node3D = _shell_scene.instantiate()
	shell.damage = attack_damage
	shell.shooter_team = team
	shell.target_pos = aim_pos
	shell.position = spawn_pos
	get_tree().root.get_child(0).add_child(shell)

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if not multiplayer.is_server():
		return
	if _dead:
		return
	health -= amount
	if health <= 0:
		_die()

func _die() -> void:
	_dead = true
	if multiplayer.has_multiplayer_peer():
		LobbyManager.despawn_tower.rpc(name)
	else:
		queue_free()
