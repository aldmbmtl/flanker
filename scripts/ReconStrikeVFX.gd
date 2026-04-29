## ReconStrikeVFX.gd
## Spawned at target_pos + 5 units above terrain when a Recon Strike is activated.
## Produces three simultaneous 3D effects visible to nearby FPS players:
##   1. Expanding shockwave ring (TorusMesh, scales out + fades over 1.5s)
##   2. Pulse light (OmniLight3D, blue-white, tweens to 0 over 1.0s)
##   3. Particle burst (blue sparks, 30 particles, 1.2s)
## Self-destructs after all effects complete.

extends Node3D

const RING_EXPAND_DURATION := 1.5
const RING_TARGET_SCALE    := 40.0   # world units radius at full expansion
const LIGHT_DURATION       := 1.0
const PARTICLE_LIFETIME    := 1.2

func _ready() -> void:
	_spawn_ring()
	_spawn_light()
	_spawn_particles()
	# Self-destruct after longest effect
	get_tree().create_timer(RING_EXPAND_DURATION + 0.2).timeout.connect(queue_free)

func _spawn_ring() -> void:
	var mesh_inst := MeshInstance3D.new()

	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 1.0
	torus.rings        = 16
	torus.ring_segments = 64

	var mat := StandardMaterial3D.new()
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color       = Color(0.4, 0.8, 1.0, 0.65)
	mat.emission_enabled   = true
	mat.emission           = Color(0.3, 0.7, 1.0, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.cull_mode          = BaseMaterial3D.CULL_DISABLED

	torus.material = mat
	mesh_inst.mesh = torus
	mesh_inst.scale = Vector3(0.01, 0.01, 0.01)
	add_child(mesh_inst)

	# Expand ring outward
	var tw: Tween = mesh_inst.create_tween()
	var target_scale: float = RING_TARGET_SCALE
	tw.set_parallel(true)
	tw.tween_property(mesh_inst, "scale",
		Vector3(target_scale, target_scale, target_scale),
		RING_EXPAND_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fade out alpha as ring expands
	tw.tween_method(
		func(a: float) -> void:
			mat.albedo_color = Color(0.4, 0.8, 1.0, a),
		0.65, 0.0, RING_EXPAND_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _spawn_light() -> void:
	var light := OmniLight3D.new()
	light.light_color       = Color(0.5, 0.8, 1.0)
	light.light_energy      = 12.0
	light.omni_range        = 50.0
	light.position          = Vector3(0.0, -2.0, 0.0)
	add_child(light)

	var tw: Tween = light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, LIGHT_DURATION)
	tw.tween_callback(light.queue_free)

func _spawn_particles() -> void:
	var p := GPUParticles3D.new()

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction              = Vector3(0.0, 1.0, 0.0)
	pm.spread                 = 180.0
	pm.initial_velocity_min   = 5.0
	pm.initial_velocity_max   = 10.0
	pm.gravity                = Vector3(0.0, -1.5, 0.0)
	pm.scale_min              = 0.15
	pm.scale_max              = 0.35

	# Color: bright blue → transparent
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.9, 1.0, 1.0))
	grad.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex

	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color   = Color(0.5, 0.9, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission       = Color(0.4, 0.8, 1.0, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat

	p.process_material = pm
	p.draw_pass_1      = quad
	p.amount           = 30
	p.lifetime         = PARTICLE_LIFETIME
	p.one_shot         = true
	p.explosiveness    = 1.0
	add_child(p)
	p.emitting = true
	p.restart()
	get_tree().create_timer(PARTICLE_LIFETIME + 0.2).timeout.connect(p.queue_free)
