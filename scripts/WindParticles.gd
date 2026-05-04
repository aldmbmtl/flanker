extends Node3D
## WindParticles — bioluminescent ambient particles that ride the wind.
##
## Spawned at runtime by Main.gd as a child of $World.  Fixed in world-space
## (local_coords = false on both emitters) so particles drift freely across the
## map regardless of camera position.
##
## Materials are authored in wind_motes.tres and wind_streaks.tres.
## Set _tree_placer and _player immediately after add_child.

var _tree_placer: Node = null
var _player: Node3D = null

var _motes:   GPUParticles3D = null
var _streaks: GPUParticles3D = null

const _MOTES_MAT   := preload("res://assets/particles/wind_motes.tres")
const _STREAKS_MAT := preload("res://assets/particles/wind_streaks.tres")

func _ready() -> void:
	_motes = _build_emitter("WindMotes", 600, 5.5, _MOTES_MAT,
		AABB(Vector3(-100, -5, -100), Vector3(200, 30, 200)))
	_streaks = _build_emitter("WindStreaks", 250, 2.0, _STREAKS_MAT,
		AABB(Vector3(-100, -5, -100), Vector3(200, 30, 200)))
	add_child(_motes)
	add_child(_streaks)

func _process(_delta: float) -> void:
	if _player != null and is_instance_valid(_player):
		var p: Vector3 = _player.global_position
		global_position = Vector3(p.x, 0.0, p.z)

	var intensity: float = 0.3
	if _tree_placer != null and is_instance_valid(_tree_placer):
		intensity = _tree_placer.get_wind_intensity()

	_motes.amount_ratio   = lerpf(0.2, 1.0, intensity)
	_streaks.amount_ratio = lerpf(0.0, 1.0, intensity)

func _build_emitter(ename: String, amount: int, lifetime: float,
		mat: ParticleProcessMaterial, vis_aabb: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name             = ename
	p.amount           = amount
	p.lifetime         = lifetime
	p.explosiveness    = 0.0
	p.randomness       = 0.6
	p.one_shot         = false
	p.emitting         = true
	p.local_coords     = false
	p.visibility_aabb  = vis_aabb
	p.process_material = mat
	return p
