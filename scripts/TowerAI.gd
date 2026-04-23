extends StaticBody3D

var team := 0  # which team OWNS this tower (attacks enemies)
var health := 150.0
var attack_range := 10.0
var attack_damage := 15.0
var attack_cooldown := 1.2
var _attack_timer := 0.0
var _dead := false

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var area: Area3D = $Area3D

func setup(p_team: int) -> void:
	team = p_team
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.6, 1.0) if team == 0 else Color(1.0, 0.4, 0.1)
	mesh.material_override = mat
	# Resize collision sphere
	var shape := SphereShape3D.new()
	shape.radius = attack_range
	$Area3D/CollisionShape3D.shape = shape

func _process(delta: float) -> void:
	if _dead:
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		var target := _find_target()
		if target:
			_shoot(target)
			_attack_timer = attack_cooldown

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist := attack_range + 1.0
	for body in area.get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		# Attack enemy minions (different team)
		var body_team := -1
		if body.has_method("get") and body.get("team") != null:
			body_team = body.team
		if body_team == team or body_team == -1:
			continue
		var d := global_position.distance_to(body.global_position)
		if d < best_dist:
			best_dist = d
			best = body
	return best

func _shoot(target: Node3D) -> void:
	target.take_damage(attack_damage, "tower")
	# Visual feedback: flash
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mesh.material_override = mat
	await get_tree().create_timer(0.1).timeout
	if not _dead:
		var base_mat := StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.1, 0.6, 1.0) if team == 0 else Color(1.0, 0.4, 0.1)
		mesh.material_override = base_mat

func take_damage(amount: float, _source: String) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0:
		_die()

func _die() -> void:
	_dead = true
	queue_free()
