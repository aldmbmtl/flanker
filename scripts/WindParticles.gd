extends Node3D
## WindParticles — bioluminescent ambient particles that ride the wind.
##
## Spawned at runtime by Main.gd as a child of $World.  Fixed in world-space
## (local_coords = false on both emitters) so particles drift freely across the
## map regardless of camera position.
##
## Two emitters:
##   _motes   — small glowing spheres, slow drift, long lifetime.
##   _streaks — faster spheres, short lifetime, heavy gust response.
##
## Set _tree_placer to the live TreePlacer node after add_child so intensity
## tracks the same gust signal that drives tree sway.

# Reference to the live TreePlacer — set by Main.gd immediately after add_child.
var _tree_placer: Node = null

# Reference to the local FPS player — set by Main.gd immediately after add_child.
# Emitters follow the player in XZ so particles appear everywhere the player goes.
var _player: Node3D = null

var _motes:   GPUParticles3D = null
var _streaks: GPUParticles3D = null

# Wind direction in XZ (normalised).  Kept in sync with TreePlacer.wind_direction.
var _wind_dir: Vector3 = Vector3(1.0, 0.0, 0.3).normalized()

# Three accent colours — green, gold, cyan.
const COL_GREEN := Color(0.3, 1.0, 0.2, 1.0)
const COL_GOLD  := Color(1.0, 0.85, 0.1, 1.0)
const COL_CYAN  := Color(0.1, 0.9, 1.0, 1.0)

func _ready() -> void:
	_motes   = _build_motes()
	_streaks = _build_streaks()
	add_child(_motes)
	add_child(_streaks)

func _process(_delta: float) -> void:
	# Follow the player in XZ so particles spawn around them wherever they are.
	if _player != null and is_instance_valid(_player):
		var p: Vector3 = _player.global_position
		global_position = Vector3(p.x, 0.0, p.z)

	var intensity: float = 0.3  # calm fallback
	if _tree_placer != null and is_instance_valid(_tree_placer):
		intensity = _tree_placer.get_wind_intensity()
		# Keep wind direction in sync if the placer exposes it.
		if "wind_direction" in _tree_placer:
			var d2: Vector2 = _tree_placer.wind_direction
			_wind_dir = Vector3(d2.x, 0.0, d2.y).normalized()

	# Motes: always some, swell during gusts.
	_motes.amount_ratio  = lerpf(0.2, 1.0, intensity)
	# Streaks: only visible during gusts.
	_streaks.amount_ratio = lerpf(0.0, 1.0, intensity)

# Builds a GradientTexture1D used as color_initial_ramp so each particle picks
# a random colour from green / gold / cyan at spawn.
func _build_color_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_color(0,    COL_GREEN)
	grad.add_point(0.45, COL_GOLD)
	grad.set_color(1,    COL_CYAN)
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

# ── Motes emitter ────────────────────────────────────────────────────────────
func _build_motes() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name        = "WindMotes"
	p.amount      = 600
	p.lifetime    = 5.5
	p.explosiveness = 0.0
	p.randomness  = 0.6
	p.one_shot    = false
	p.emitting    = true
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-100, -5, -100), Vector3(200, 30, 200))

	var mat := ParticleProcessMaterial.new()

	# Emission box — tighter than the full map so density is visible near the player.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(30.0, 8.0, 30.0)

	# Velocity: 50% slower than original (was spd=7.0).
	var spd: float = 3.5
	mat.initial_velocity_min = spd * 0.6
	mat.initial_velocity_max = spd * 1.2
	mat.direction = _wind_dir + Vector3(0.0, 0.08, 0.0)
	mat.spread    = 18.0

	# No gravity — float.
	mat.gravity = Vector3.ZERO

	# Dampen so they slow gently rather than dead-stopping.
	mat.damping_min = 0.4
	mat.damping_max = 0.8

	# Scale: 50% larger (was 0.015–0.10).
	mat.scale_min = 0.0225
	mat.scale_max = 0.15

	# Random colour per particle: green / gold / cyan picked at spawn.
	mat.color_initial_ramp = _build_color_ramp()

	# Fade out over lifetime via alpha in color_ramp.
	var fade_grad := Gradient.new()
	fade_grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade_grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade_grad
	mat.color_ramp = fade_tex

	p.process_material = mat

	# Draw pass: tiny sphere mesh — 50% larger (was 0.02).
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 4
	mesh.rings = 2
	var surf := StandardMaterial3D.new()
	surf.transparency           = BaseMaterial3D.TRANSPARENCY_ALPHA
	surf.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
	surf.albedo_color           = Color(1.0, 1.0, 1.0, 1.0)  # tinted by particle color
	surf.vertex_color_use_as_albedo = true
	surf.emission_enabled       = true
	surf.emission               = Color(1.0, 1.0, 1.0)
	surf.emission_energy_multiplier = 3.0
	mesh.surface_set_material(0, surf)
	p.draw_pass_1 = mesh

	return p

# ── Streaks emitter ───────────────────────────────────────────────────────────
func _build_streaks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name        = "WindStreaks"
	p.amount      = 250
	p.lifetime    = 2.0
	p.explosiveness = 0.0
	p.randomness  = 0.5
	p.one_shot    = false
	p.emitting    = true
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-100, -5, -100), Vector3(200, 30, 200))

	var mat := ParticleProcessMaterial.new()

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(35.0, 6.0, 35.0)

	# Velocity: 50% slower (was spd=18.0).
	var spd: float = 9.0
	mat.initial_velocity_min = spd * 0.7
	mat.initial_velocity_max = spd * 1.3
	mat.direction = _wind_dir
	mat.spread    = 8.0

	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.2
	mat.damping_max = 0.5

	# Scale: 50% larger (was 0.3–0.6).
	mat.scale_min = 0.45
	mat.scale_max = 0.9

	# Random colour per particle: green / gold / cyan picked at spawn.
	mat.color_initial_ramp = _build_color_ramp()

	# Flash in then fade out.
	var fade_grad := Gradient.new()
	fade_grad.set_color(0, Color(1.0, 1.0, 1.0, 0.0))    # transparent spawn
	fade_grad.add_point(0.1, Color(1.0, 1.0, 1.0, 0.75)) # flash in
	fade_grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))    # fade out
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade_grad
	mat.color_ramp = fade_tex

	p.process_material = mat

	# Draw pass: sphere mesh — 50% larger (was 0.03).
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 4
	mesh.rings = 2
	var surf := StandardMaterial3D.new()
	surf.transparency           = BaseMaterial3D.TRANSPARENCY_ALPHA
	surf.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
	surf.albedo_color           = Color(1.0, 1.0, 1.0, 0.7)  # tinted by particle color
	surf.vertex_color_use_as_albedo = true
	surf.emission_enabled       = true
	surf.emission               = Color(1.0, 1.0, 1.0)
	surf.emission_energy_multiplier = 4.0
	mesh.surface_set_material(0, surf)
	p.draw_pass_1 = mesh

	return p
