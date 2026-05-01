extends StaticBody3D
## Heal Station — persistent structure that heals nearby friendly units at 5 HP/s.
## Expires after LIFETIME seconds. Emits a continuous radial green particle burst.

const HEAL_RATE    := 5.0   # HP per second
const HEAL_RADIUS  := 4.0
const MAX_HEALTH   := 200.0
const LIFETIME     := 180.0  # 3 minutes
const PILLAR_MODEL_PATH := "res://assets/kenney_fantasy-town-kit/Models/GLB format/pillar-stone.glb"

var team: int = 0
var health: float = MAX_HEALTH
var _dead := false
var _age: float = 0.0
var _bodies_in_range: Array = []

func setup(p_team: int) -> void:
	team = p_team
	add_to_group("supporter_drops")
	_build_visuals()
	_setup_heal_zone()

func _build_visuals() -> void:
	# Pillar-stone model as the visual anchor
	var packed: PackedScene = load(PILLAR_MODEL_PATH)
	if packed:
		var pillar: Node3D = packed.instantiate()
		pillar.scale = Vector3(2.0, 2.5, 2.0)
		add_child(pillar)

	# Radial green particle burst — continuous, spreads outward from the heal zone
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = HEAL_RADIUS * 0.5
	pm.direction             = Vector3(0.0, 0.0, 0.0)
	pm.spread                = 180.0
	pm.initial_velocity_min  = 1.5
	pm.initial_velocity_max  = 4.0
	pm.gravity               = Vector3(0.0, -2.0, 0.0)
	pm.scale_min             = 0.15
	pm.scale_max             = 0.3

	var mat := StandardMaterial3D.new()
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color       = Color(0.1, 1.0, 0.2, 0.8)
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode     = BaseMaterial3D.BILLBOARD_ENABLED
	mat.emission_enabled           = true
	mat.emission                   = Color(0.1, 1.0, 0.2)
	mat.emission_energy_multiplier = 2.0

	var mesh := QuadMesh.new()
	mesh.size     = Vector2(0.25, 0.25)
	mesh.material = mat

	var ps := GPUParticles3D.new()
	ps.process_material = pm
	ps.draw_pass_1      = mesh
	ps.amount           = 40
	ps.lifetime         = 1.5
	ps.one_shot         = false
	ps.explosiveness    = 0.0
	ps.position         = Vector3(0.0, 0.3, 0.0)
	ps.emitting         = true
	add_child(ps)

	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 1.0, 0.3)
	light.light_energy = 1.8
	light.omni_range = HEAL_RADIUS + 2.0
	light.position = Vector3(0.0, 2.0, 0.0)
	add_child(light)

func _setup_heal_zone() -> void:
	# Platform collision — box at base so players can't walk through the pillar
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 3.0, 0.8)
	col.shape = box
	col.position = Vector3(0.0, 1.5, 0.0)
	add_child(col)

	# Heal zone Area3D
	var zone := Area3D.new()
	zone.name = "HealZone"
	var zone_col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HEAL_RADIUS
	zone_col.shape = sphere
	zone_col.position = Vector3(0.0, 0.5, 0.0)
	zone.add_child(zone_col)
	zone.connect("body_entered", _on_body_entered_zone)
	zone.connect("body_exited", _on_body_exited_zone)
	add_child(zone)

func _on_body_entered_zone(body: Node3D) -> void:
	if body.has_method("heal"):
		_bodies_in_range.append(body)

func _on_body_exited_zone(body: Node3D) -> void:
	_bodies_in_range.erase(body)

func _process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age >= LIFETIME:
		_die()
		return
	for body in _bodies_in_range:
		if not is_instance_valid(body):
			continue
		var body_team := -1
		var pt = body.get("player_team")
		if pt != null:
			body_team = pt as int
		else:
			var t = body.get("team")
			if t != null:
				body_team = t as int
		if body_team != team:
			continue
		body.heal(HEAL_RATE * delta)
	_bodies_in_range = _bodies_in_range.filter(func(b): return is_instance_valid(b))

func take_damage(amount: float, _source: String, _killer_team: int = -1, _shooter_peer_id: int = -1) -> void:
	if not multiplayer.is_server():
		return
	if _dead:
		return
	health -= amount
	if health <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	if multiplayer.has_multiplayer_peer():
		LobbyManager.despawn_tower.rpc(name)
	else:
		queue_free()
