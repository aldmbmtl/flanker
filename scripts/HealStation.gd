extends StaticBody3D
## Heal Station — persistent structure that heals nearby friendly units at 5 HP/s.

const HEAL_RATE    := 5.0   # HP per second
const HEAL_RADIUS  := 4.0
const MAX_HEALTH   := 200.0
const PILLAR_MODEL_PATH := "res://assets/kenney_fantasy-town-kit/Models/GLB format/pillar-stone.glb"

var team: int = 0
var health: float = MAX_HEALTH
var _dead := false
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

	# Green glow ring on the ground to show heal radius
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = HEAL_RADIUS * 0.95
	cyl.bottom_radius = HEAL_RADIUS * 0.95
	cyl.height = 0.08
	cyl.rings = 1
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.05, 0.8, 0.15, 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.0, 1.0, 0.1)
	ring_mat.emission_energy_multiplier = 1.5
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.mesh = cyl
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 0.05, 0.0)
	add_child(ring)

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
