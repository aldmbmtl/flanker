## VfxUtils — static helpers for runtime VFX construction.
## Not an autoload. Import via class_name or preload.
## All functions are purely functional — no state, no signals.
class_name VfxUtils

# ── Scene root helper ─────────────────────────────────────────────────────────

## Returns child 0 of the scene tree root — the active game scene node.
## Use instead of get_tree().root.get_child(0) throughout the codebase.
static func get_scene_root(node: Node) -> Node:
	return node.get_tree().root.get_child(0)

# ── Flash light ───────────────────────────────────────────────────────────────

## Spawn a one-shot OmniLight3D that fades to zero and frees itself.
## opts keys (all optional, sensible defaults):
##   color       : Color   — light colour             (default: Color(1,0.6,0.15))
##   energy      : float   — starting light_energy    (default: 8.0)
##   range       : float   — omni_range               (default: 8.0)
##   duration    : float   — tween fade duration (s)  (default: 0.4)
##   offset      : Vector3 — position offset from pos (default: Vector3(0,0.5,0))
static func spawn_flash_light(root: Node, pos: Vector3, opts: Dictionary = {}) -> OmniLight3D:
	var flash := OmniLight3D.new()
	flash.light_color     = opts.get("color",    Color(1.0, 0.6, 0.15))
	flash.light_energy    = opts.get("energy",   8.0)
	flash.omni_range      = opts.get("range",    8.0)
	flash.shadow_enabled  = false
	root.add_child(flash)
	flash.global_position = pos + opts.get("offset", Vector3(0.0, 0.5, 0.0))
	var tw: Tween = flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, opts.get("duration", 0.4))
	tw.tween_callback(flash.queue_free)
	return flash

# ── GPU particle burst ────────────────────────────────────────────────────────

## Spawn a one-shot GPUParticles3D burst, add it to root at pos, then auto-free.
##
## opts keys (all optional):
##   amount            : int      — particle count          (default: 20)
##   lifetime          : float    — particle lifetime (s)   (default: 0.6)
##   explosiveness     : float    — burst factor            (default: 1.0)
##   one_shot          : bool                               (default: true)
##
##   # ParticleProcessMaterial
##   emission_shape    : int      — ParticleProcessMaterial.EMISSION_SHAPE_* (default: POINT=0)
##   emission_radius   : float    — sphere emission radius  (default: 0.0)
##   direction         : Vector3  — emit direction          (default: Vector3.UP)
##   spread            : float    — spread degrees          (default: 90.0)
##   vel_min           : float    — initial_velocity_min    (default: 3.0)
##   vel_max           : float    — initial_velocity_max    (default: 8.0)
##   gravity           : Vector3  — gravity override        (default: Vector3(0,-9.8,0))
##   scale_min         : float                              (default: 0.2)
##   scale_max         : float                              (default: 0.5)
##
##   # Quad mesh
##   quad_size         : Vector2  — QuadMesh size           (default: Vector2(0.3,0.3))
##
##   # Material
##   color             : Color    — albedo_color            (default: Color(1,0.6,0.1,0.9))
##   alpha             : bool     — enable TRANSPARENCY_ALPHA (default: true)
##   billboard         : bool     — BILLBOARD_ENABLED       (default: true)
##   emission_enabled  : bool                               (default: false)
##   emission_color    : Color    — emission colour         (default: Color(1,0.8,0.2))
##   emission_energy   : float    — emission_energy_mult    (default: 3.0)
##
##   # Position
##   offset            : Vector3  — position offset from pos (default: Vector3.ZERO)
static func spawn_particles(root: Node, pos: Vector3, opts: Dictionary = {}) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()

	var em_shape: int = opts.get("emission_shape", ParticleProcessMaterial.EMISSION_SHAPE_POINT)
	pm.emission_shape = em_shape
	if em_shape == ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
		pm.emission_sphere_radius = opts.get("emission_radius", 0.0)

	pm.direction            = opts.get("direction",  Vector3.UP)
	pm.spread               = opts.get("spread",     90.0)
	pm.initial_velocity_min = opts.get("vel_min",    3.0)
	pm.initial_velocity_max = opts.get("vel_max",    8.0)
	pm.gravity              = opts.get("gravity",    Vector3(0.0, -9.8, 0.0))
	pm.scale_min            = opts.get("scale_min",  0.2)
	pm.scale_max            = opts.get("scale_max",  0.5)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = opts.get("color",  Color(1.0, 0.6, 0.1, 0.9))
	if opts.get("alpha", true):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if opts.get("billboard", true):
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if opts.get("emission_enabled", false):
		mat.emission_enabled           = true
		mat.emission                   = opts.get("emission_color", Color(1.0, 0.8, 0.2))
		mat.emission_energy_multiplier = opts.get("emission_energy", 3.0)

	var mesh := QuadMesh.new()
	mesh.size     = opts.get("quad_size", Vector2(0.3, 0.3))
	mesh.material = mat

	var ps := GPUParticles3D.new()
	ps.process_material = pm
	ps.draw_pass_1      = mesh
	ps.amount           = opts.get("amount",        20)
	ps.lifetime         = opts.get("lifetime",      0.6)
	ps.one_shot         = opts.get("one_shot",      true)
	ps.explosiveness    = opts.get("explosiveness", 1.0)
	root.add_child(ps)
	ps.global_position = pos + opts.get("offset", Vector3.ZERO)
	ps.emitting = true
	ps.restart()
	root.get_tree().create_timer(ps.lifetime + 0.1).timeout.connect(ps.queue_free)
	return ps
