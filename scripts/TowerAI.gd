extends StaticBody3D

const BULLET_SPEED := 84.0
const BulletScene := preload("res://scenes/Bullet.tscn")

var team := 0  # which team OWNS this tower (attacks enemies)
var health := 300.0
const MAX_HEALTH := 300.0
var attack_range := 15.0
var attack_damage := 50.0
var attack_cooldown := 1.0
var _attack_timer := 0.0
var _dead := false
var _team_mat: StandardMaterial3D = null

var hud_id := -1

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var area: Area3D = $Area3D
@onready var debug_collision: StaticBody3D = $DebugCollision

const TOWER_MODEL_PATH := "res://assets/kenney_pirate-kit/Models/GLB format/tower-complete-small.glb"

func setup(p_team: int) -> void:
	team = p_team
	add_to_group("towers")
	# Load and instance the model in code
	_load_team_model()
	# Enable debug collision visual
	debug_collision.visible = true
	# Resize collision sphere
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = attack_range
	$Area3D/CollisionShape3D.shape = shape
	# Register health bar
	var entity_hud := get_node_or_null("/root/Main/HUD/HUDOverlay/EntityHUD")
	if entity_hud and entity_hud.has_method("register_entity"):
		hud_id = entity_hud.call("register_entity", self, MAX_HEALTH, team)

func _load_team_model() -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(TOWER_MODEL_PATH, state)
	if err != OK:
		print("TowerAI: GLTF failed error=", err)
		return
	var root: Node3D = gltf.generate_scene(state)
	if not root:
		print("TowerAI: generate_scene failed")
		return
	add_child(root)
	_add_hit_overlay()
	print("TowerAI: loaded model")

func _add_hit_overlay() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var overlay_mat := StandardMaterial3D.new()
			overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			overlay_mat.albedo_color = Color(1, 0.2, 0.2, 0.0)
			overlay_mat.emission_enabled = true
			overlay_mat.emission = Color(1, 0.2, 0.2, 1)
			overlay_mat.emission_energy_multiplier = 3.0
			child.set("material_override", overlay_mat)

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
		# Get team: minions use .team, player uses .player_team
		var body_team := -1
		if body.has_method("get"):
			var pt = body.get("player_team")
			if pt != null:
				body_team = pt as int
			else:
				var t = body.get("team")
				if t != null:
					body_team = t as int
		if body_team == team:
			continue
		var d := global_position.distance_to(body.global_position)
		if d < best_dist:
			best_dist = d
			best = body
	return best

func _shoot(target: Node3D) -> void:
	var spawn_pos: Vector3 = global_position + Vector3(0.0, 2.0, 0.0)
	var aim_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)
	var dir: Vector3 = (aim_pos - spawn_pos).normalized()
	dir.y += 0.04
	dir = dir.normalized()

	var bullet: Node3D = BulletScene.instantiate()
	bullet.damage = attack_damage
	bullet.source = "tower"
	bullet.shooter_team = team
	bullet.velocity = dir * BULLET_SPEED
	get_tree().root.get_child(0).add_child(bullet)
	bullet.global_position = spawn_pos

	if multiplayer.is_server():
		LobbyManager.spawn_bullet_visuals.rpc(bullet.global_position, dir, attack_damage, team)

	# Visual feedback: flash
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mesh.material_override = mat
	await get_tree().create_timer(0.1).timeout
	if not _dead:
		var base_mat := StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.1, 0.6, 1.0) if team == 0 else Color(1.0, 0.4, 0.1)
		mesh.material_override = base_mat

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if _dead:
		return
	health -= amount
	_hit_flash()
	if hud_id > 0:
		var entity_hud := get_node_or_null("/root/Main/HUD/HUDOverlay/EntityHUD")
		if entity_hud and entity_hud.has_method("update_entity_health"):
			entity_hud.call("update_entity_health", hud_id, health)
	if health <= 0:
		_die()

var _hit_flash_tween: Tween

func _hit_flash() -> void:
	if mesh == null:
		return
	
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	
	var mat: StandardMaterial3D = mesh.get("material_override")
	if mat != null and mat is StandardMaterial3D:
		mat.albedo_color = Color(1, 0.2, 0.2, 0.8)
		
		_hit_flash_tween = create_tween()
		_hit_flash_tween.tween_property(mat, "albedo_color", Color(1, 0.2, 0.2, 0.0), 0.3)

func _die() -> void:
	_dead = true
	queue_free()