## SlowTowerAI.gd — Slow tower (TowerBase subclass).
## Pulses every 2s, applies speed debuff to nearby enemies.
## Stats configured via @export in SlowTower.tscn.
## Overrides _process (pulse-based, not attack-based).
## Overrides _build_visuals to apply permanent cyan tint.

class_name SlowTowerAI
extends TowerBase

const PULSE_INTERVAL := 2.0
const SLOW_DURATION  := 3.0
const SLOW_MULT      := 0.4

var _pulse_timer: float = 0.0

# ── Visuals — cyan tint applied permanently via surface override ──────────────

func _build_visuals() -> void:
	super._build_visuals()
	if _all_mesh_insts.is_empty():
		return
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(0.3, 0.9, 1.0)
	tint.emission_enabled = true
	tint.emission = Color(0.3, 0.9, 1.0)
	tint.emission_energy_multiplier = 0.6
	for mi in _all_mesh_insts:
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, tint)
	# Tint is permanent — disable flash so it doesn't clobber the cyan tint
	_hit_overlay_mat = null

# ── Pulse loop — replaces TowerBase._process ─────────────────────────────────

func _process(delta: float) -> void:
	# Server-authoritative only — mirrors the guard in TowerBase._process.
	if not BridgeClient.is_host():
		return
	if _dead:
		return
	_pulse_timer += delta
	if _pulse_timer >= PULSE_INTERVAL:
		_pulse_timer = 0.0
		_emit_pulse()

# ── Pulse logic ───────────────────────────────────────────────────────────────

func _emit_pulse() -> void:
	_spawn_pulse_vfx()
	if BridgeClient.is_host():
		var origin: Vector3 = global_position + Vector3(0.0, 0.3, 0.0)
		BridgeClient.send("tower_visual", {
			"vtype": "slow_pulse",
			"tower_name": name,
			"origin": [origin.x, origin.y, origin.z],
		})
	if _area == null:
		return
	for body in _area.get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		var body_team: int = _get_body_team(body)
		if body_team == team or body_team == -1:
			continue
		if not _has_line_of_sight(body):
			continue
		if body.has_method("apply_slow"):
			body.apply_slow(SLOW_DURATION, SLOW_MULT)

func _spawn_pulse_vfx() -> void:
	var root: Node = get_tree().root
	var origin: Vector3 = global_position + Vector3(0.0, 0.3, 0.0)

	VfxUtils.spawn_particles(root, origin, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.5, "direction": Vector3(0.0, 0.05, 0.0), "spread": 180.0,
		"vel_min": 6.0, "vel_max": 12.0, "gravity": Vector3(0.0, -28.0, 0.0),
		"scale_min": 0.15, "scale_max": 0.35, "quad_size": Vector2(0.25, 0.25),
		"color": Color(0.4, 0.95, 1.0, 0.9), "billboard": false,
		"emission_enabled": true, "emission_color": Color(0.1, 0.85, 1.0), "emission_energy": 4.0,
		"amount": 60, "lifetime": 0.5, "explosiveness": 1.0})

	var p2_opts: Dictionary = {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": attack_range * 0.35, "direction": Vector3.UP, "spread": 30.0,
		"vel_min": 3.0, "vel_max": 8.0, "gravity": Vector3(0.0, -1.5, 0.0),
		"scale_min": 0.08, "scale_max": 0.2, "quad_size": Vector2(0.15, 0.4),
		"color": Color(0.55, 0.9, 1.0, 0.75),
		"emission_enabled": true, "emission_color": Color(0.2, 0.7, 1.0), "emission_energy": 2.5,
		"amount": 30, "lifetime": 0.8, "explosiveness": 0.85}
	VfxUtils.spawn_particles(root, origin, p2_opts)

	VfxUtils.spawn_particles(root, origin, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.2, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 3.0, "vel_max": 7.0, "gravity": Vector3.ZERO,
		"scale_min": 0.3, "scale_max": 0.7, "quad_size": Vector2(0.6, 0.6),
		"color": Color(0.85, 0.98, 1.0, 0.95), "billboard": false,
		"emission_enabled": true, "emission_color": Color(0.5, 0.95, 1.0), "emission_energy": 6.0,
		"amount": 15, "lifetime": 0.2, "explosiveness": 1.0})

	# Flash light
	VfxUtils.spawn_flash_light(root, origin, {
		"color": Color(0.3, 0.9, 1.0), "energy": 5.0, "range": 8.0,
		"duration": 0.3, "offset": Vector3(0.0, 1.0, 0.0)})
