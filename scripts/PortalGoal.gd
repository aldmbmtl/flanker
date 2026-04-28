extends Area3D

# Portal goal zone. Replaces the old Base.tscn.
# One portal is spawned per lane endpoint per team.
# When an enemy minion walks into it the portal pulses, the minion dies,
# and the defending team loses a life.
#
# Kept in group "bases" so MinionBase targeting/marching is unchanged.
# Visual is 100% particles — no meshes. Sphere form, visible from all angles.

var team: int = 0
var lane_i: int = 0

# Team colors
const BLUE_COLOR := Color(0.2, 0.55, 1.0)
const RED_COLOR  := Color(1.0, 0.25, 0.25)

# Sphere centre height above portal origin
const SPHERE_Y := 2.8

# Particle emitters
var _swirl:    GPUParticles3D = null  # main vortex streaks on sphere surface
var _inner:    GPUParticles3D = null  # soft haze filling the interior
var _sparks:   GPUParticles3D = null  # short-lived surface flecks
var _tendrils: GPUParticles3D = null  # streaks shooting outward from surface

# Process materials kept for recolor
var _swirl_pm:    ParticleProcessMaterial = null
var _inner_pm:    ParticleProcessMaterial = null
var _sparks_pm:   ParticleProcessMaterial = null
var _tendrils_pm: ParticleProcessMaterial = null

# Lights
var _omni:  OmniLight3D = null
var _shaft: SpotLight3D = null

# Breathing oscillator
var _breathe_angle: float = 0.0
const BREATHE_SPEED := 2.0

# Pulse tween
var _pulse_tween: Tween = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("bases")
	_build_visuals()
	body_entered.connect(_on_body_entered)

func setup(p_team: int, p_lane_i: int = 0) -> void:
	team   = p_team
	lane_i = p_lane_i
	if _swirl_pm != null:
		_apply_team_color()

func _process(delta: float) -> void:
	_breathe_angle += BREATHE_SPEED * delta
	if _omni:
		_omni.light_energy = 2.5 + sin(_breathe_angle) * 0.5

# ── Visuals ───────────────────────────────────────────────────────────────────

func _build_visuals() -> void:
	var color: Color = BLUE_COLOR if team == 0 else RED_COLOR

	# ── Shared quad material ───────────────────────────────────────────────
	# Billboard so quads always face the camera regardless of viewing angle.
	# Unshaded + vertex_color_use_as_albedo so ParticleProcessMaterial color
	# tinting is applied correctly. Alpha transparency for soft particle edges.
	# Without this every QuadMesh uses the default StandardMaterial3D which
	# has cull_back enabled and no billboard — the back hemisphere is invisible.

	# ── Swirl — main vortex, orbit Y-axis around sphere surface ───────────
	_swirl_pm = ParticleProcessMaterial.new()
	_swirl_pm.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_swirl_pm.emission_sphere_radius = 2.8
	_swirl_pm.direction              = Vector3(0.0, 1.0, 0.0)
	_swirl_pm.spread                 = 15.0
	_swirl_pm.initial_velocity_min   = 0.2
	_swirl_pm.initial_velocity_max   = 0.7
	_swirl_pm.orbit_velocity_min     = 3.0
	_swirl_pm.orbit_velocity_max     = 5.0
	_swirl_pm.gravity                = Vector3(0.0, 0.0, 0.0)
	_swirl_pm.scale_min              = 0.5
	_swirl_pm.scale_max              = 1.3
	_swirl_pm.color                  = color

	var swirl_quad := QuadMesh.new()
	swirl_quad.size     = Vector2(0.06, 0.5)
	swirl_quad.material = _make_particle_mat()

	_swirl = GPUParticles3D.new()
	_swirl.amount           = 200
	_swirl.lifetime         = 1.8
	_swirl.explosiveness    = 0.0
	_swirl.randomness       = 0.2
	_swirl.emitting         = true
	_swirl.process_material = _swirl_pm
	_swirl.draw_pass_1      = swirl_quad
	_swirl.position         = Vector3(0.0, SPHERE_Y, 0.0)
	add_child(_swirl)

	# ── Inner haze — soft fill inside the sphere ───────────────────────────
	_inner_pm = ParticleProcessMaterial.new()
	_inner_pm.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_inner_pm.emission_sphere_radius = 1.2
	_inner_pm.direction              = Vector3(0.0, 1.0, 0.0)
	_inner_pm.spread                 = 180.0
	_inner_pm.initial_velocity_min   = 0.05
	_inner_pm.initial_velocity_max   = 0.3
	_inner_pm.orbit_velocity_min     = 0.5
	_inner_pm.orbit_velocity_max     = 1.2
	_inner_pm.gravity                = Vector3(0.0, 0.0, 0.0)
	_inner_pm.scale_min              = 0.5
	_inner_pm.scale_max              = 1.1
	_inner_pm.color                  = color

	var inner_quad := QuadMesh.new()
	inner_quad.size     = Vector2(0.3, 0.3)
	inner_quad.material = _make_particle_mat()

	_inner = GPUParticles3D.new()
	_inner.amount           = 60
	_inner.lifetime         = 2.4
	_inner.explosiveness    = 0.0
	_inner.randomness       = 0.5
	_inner.emitting         = true
	_inner.process_material = _inner_pm
	_inner.draw_pass_1      = inner_quad
	_inner.position         = Vector3(0.0, SPHERE_Y, 0.0)
	add_child(_inner)

	# ── Sparks — short-lived bright flecks popping on the surface ─────────
	_sparks_pm = ParticleProcessMaterial.new()
	_sparks_pm.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_sparks_pm.emission_sphere_radius = 2.9
	_sparks_pm.direction              = Vector3(0.0, 1.0, 0.0)
	_sparks_pm.spread                 = 180.0
	_sparks_pm.initial_velocity_min   = 4.0
	_sparks_pm.initial_velocity_max   = 8.0
	_sparks_pm.orbit_velocity_min     = 1.0
	_sparks_pm.orbit_velocity_max     = 2.5
	_sparks_pm.gravity                = Vector3(0.0, -3.0, 0.0)
	_sparks_pm.scale_min              = 0.04
	_sparks_pm.scale_max              = 0.10
	_sparks_pm.color                  = color

	var sparks_quad := QuadMesh.new()
	sparks_quad.size     = Vector2(0.06, 0.06)
	sparks_quad.material = _make_particle_mat()

	_sparks = GPUParticles3D.new()
	_sparks.amount           = 70
	_sparks.lifetime         = 0.7
	_sparks.explosiveness    = 0.0
	_sparks.randomness       = 0.4
	_sparks.emitting         = true
	_sparks.process_material = _sparks_pm
	_sparks.draw_pass_1      = sparks_quad
	_sparks.position         = Vector3(0.0, SPHERE_Y, 0.0)
	add_child(_sparks)

	# ── Tendrils — streaks shooting outward from sphere surface ───────────
	_tendrils_pm = ParticleProcessMaterial.new()
	_tendrils_pm.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_tendrils_pm.emission_sphere_radius = 2.6
	_tendrils_pm.direction              = Vector3(0.0, 1.0, 0.0)
	_tendrils_pm.spread                 = 180.0
	_tendrils_pm.initial_velocity_min   = 6.0
	_tendrils_pm.initial_velocity_max   = 12.0
	_tendrils_pm.orbit_velocity_min     = 0.3
	_tendrils_pm.orbit_velocity_max     = 1.0
	_tendrils_pm.gravity                = Vector3(0.0, -1.0, 0.0)
	_tendrils_pm.scale_min              = 0.4
	_tendrils_pm.scale_max              = 1.0
	_tendrils_pm.color                  = color

	var tendril_quad := QuadMesh.new()
	tendril_quad.size     = Vector2(0.07, 0.6)
	tendril_quad.material = _make_particle_mat()

	_tendrils = GPUParticles3D.new()
	_tendrils.amount           = 45
	_tendrils.lifetime         = 0.9
	_tendrils.explosiveness    = 0.0
	_tendrils.randomness       = 0.35
	_tendrils.emitting         = true
	_tendrils.process_material = _tendrils_pm
	_tendrils.draw_pass_1      = tendril_quad
	_tendrils.position         = Vector3(0.0, SPHERE_Y, 0.0)
	add_child(_tendrils)

	# ── OmniLight — ambient sphere glow ───────────────────────────────────
	_omni = OmniLight3D.new()
	_omni.light_color    = color
	_omni.light_energy   = 2.5
	_omni.omni_range     = 10.0
	_omni.shadow_enabled = false
	_omni.position       = Vector3(0.0, SPHERE_Y, 0.0)
	add_child(_omni)

	# ── SpotLight — sky beacon pointing up ────────────────────────────────
	_shaft = SpotLight3D.new()
	_shaft.light_color      = color
	_shaft.light_energy     = 4.0
	_shaft.spot_range       = 28.0
	_shaft.spot_angle       = 10.0
	_shaft.spot_attenuation = 0.4
	_shaft.shadow_enabled   = false
	_shaft.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_shaft.position         = Vector3(0.0, SPHERE_Y + 0.2, 0.0)
	add_child(_shaft)

func _make_particle_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode            = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode                 = BaseMaterial3D.CULL_DISABLED
	return mat

func _apply_team_color() -> void:
	var color: Color = BLUE_COLOR if team == 0 else RED_COLOR
	if _swirl_pm:    _swirl_pm.color    = color
	if _inner_pm:    _inner_pm.color    = color
	if _sparks_pm:   _sparks_pm.color   = color
	if _tendrils_pm: _tendrils_pm.color = color
	if _omni:        _omni.light_color  = color
	if _shaft:       _shaft.light_color = color

# ── Body detection ────────────────────────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("minions"):
		return
	var body_team: int = body.get("team") if body.get("team") != null else -1
	if body_team == team or body_team == -1:
		return

	# Multiplayer: server-authoritative only
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if body.has_method("force_die"):
		body.force_die()
	else:
		body.queue_free()

	TeamLives.lose_life(team)
	_pulse()

# ── Pulse VFX ─────────────────────────────────────────────────────────────────

func _pulse() -> void:
	if _pulse_tween and _pulse_tween.is_running():
		_pulse_tween.kill()

	# Flash up
	_pulse_tween = create_tween().set_parallel(true)
	if _shaft: _pulse_tween.tween_property(_shaft, "light_energy", 18.0, 0.07)
	if _omni:  _pulse_tween.tween_property(_omni,  "light_energy", 12.0, 0.07)

	# Settle back
	var settle: Tween = create_tween().set_parallel(true)
	if _shaft: settle.tween_property(_shaft, "light_energy", 4.0, 0.5).set_delay(0.1)
	if _omni:  settle.tween_property(_omni,  "light_energy", 2.5, 0.5).set_delay(0.1)

	# Burst all emitters
	if _swirl:    _swirl.restart()
	if _inner:    _inner.restart()
	if _sparks:   _sparks.restart()
	if _tendrils: _tendrils.restart()
