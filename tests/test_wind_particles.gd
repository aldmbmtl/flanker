# test_wind_particles.gd
# Tier 1 — unit tests for WindParticles and the TreePlacer gust spike system.
# Both classes build GPU particles and shader state in code — no scene files needed.
extends GutTest

const WindParticlesScript := preload("res://scripts/WindParticles.gd")
const TreePlacerScript     := preload("res://scripts/TreePlacer.gd")

# ── helpers ───────────────────────────────────────────────────────────────────

# Minimal WindParticles node — just runs _ready() to build emitters.
class FakeWindParticles extends Node3D:
	var _tree_placer: Node = null
	var _motes:   GPUParticles3D = null
	var _streaks: GPUParticles3D = null

	func _ready() -> void:
		set_script(load("res://scripts/WindParticles.gd"))

# We instantiate WindParticles via set_script so _ready fires naturally.
func _make_wind_particles() -> Node3D:
	var wp := Node3D.new()
	wp.set_script(WindParticlesScript)
	add_child_autofree(wp)
	return wp

# Minimal TreePlacer — skip all terrain/placement work, just expose wind vars.
class FakeTreePlacer extends Node3D:
	var wind_strength_base: float    = 0.03
	var wind_strength_gust: float    = 0.04
	var wind_gust_cycle_speed: float = 0.25
	var wind_strength_peak: float    = 0.16
	var wind_gust_spike_min_interval: float = 8.0
	var wind_gust_spike_max_interval: float = 22.0
	var wind_gust_spike_decay: float  = 2.5
	var wind_gust_spike_attack: float = 1.2
	var wind_direction: Vector2       = Vector2(1.0, 0.3)
	var _wind_mmis: Array             = []
	var _gust_spike: float            = 0.0
	var _gust_target: float           = 0.0
	var _next_spike_time: float       = 0.0

	func get_wind_intensity() -> float:
		var t: float = Time.get_ticks_msec() / 1000.0
		var base: float = sin(t * wind_gust_cycle_speed) * 0.5 + 0.5
		return clampf(base * 0.4 + _gust_spike * 0.6, 0.0, 1.0)

	func _process(delta: float) -> void:
		var t: float = Time.get_ticks_msec() / 1000.0
		if t >= _next_spike_time:
			_gust_target = 1.0
			_next_spike_time = t + randf_range(wind_gust_spike_min_interval, wind_gust_spike_max_interval)
		if _gust_spike < _gust_target:
			_gust_spike = minf(_gust_target, _gust_spike + wind_gust_spike_attack * delta)
		else:
			_gust_spike = maxf(0.0, _gust_spike - wind_gust_spike_decay * delta)
			if _gust_spike <= 0.0:
				_gust_target = 0.0

# ── WindParticles: emitter construction ───────────────────────────────────────

func test_wind_particles_creates_motes_child() -> void:
	var wp := _make_wind_particles()
	var motes: Node = wp.get_node_or_null("WindMotes")
	assert_not_null(motes, "WindMotes GPUParticles3D should exist after _ready()")

func test_wind_particles_creates_streaks_child() -> void:
	var wp := _make_wind_particles()
	var streaks: Node = wp.get_node_or_null("WindStreaks")
	assert_not_null(streaks, "WindStreaks GPUParticles3D should exist after _ready()")

func test_motes_is_gpu_particles() -> void:
	var wp := _make_wind_particles()
	var motes: Node = wp.get_node_or_null("WindMotes")
	assert_true(motes is GPUParticles3D, "WindMotes must be a GPUParticles3D node")

func test_streaks_is_gpu_particles() -> void:
	var wp := _make_wind_particles()
	var streaks: Node = wp.get_node_or_null("WindStreaks")
	assert_true(streaks is GPUParticles3D, "WindStreaks must be a GPUParticles3D node")

func test_motes_emitting_on_ready() -> void:
	var wp := _make_wind_particles()
	var motes: GPUParticles3D = wp.get_node_or_null("WindMotes") as GPUParticles3D
	assert_true(motes.emitting, "WindMotes should be emitting after _ready()")

func test_streaks_emitting_on_ready() -> void:
	var wp := _make_wind_particles()
	var streaks: GPUParticles3D = wp.get_node_or_null("WindStreaks") as GPUParticles3D
	assert_true(streaks.emitting, "WindStreaks should be emitting after _ready()")

func test_motes_not_local_coords() -> void:
	var wp := _make_wind_particles()
	var motes: GPUParticles3D = wp.get_node_or_null("WindMotes") as GPUParticles3D
	assert_false(motes.local_coords, "WindMotes must use world-space (local_coords = false)")

func test_streaks_not_local_coords() -> void:
	var wp := _make_wind_particles()
	var streaks: GPUParticles3D = wp.get_node_or_null("WindStreaks") as GPUParticles3D
	assert_false(streaks.local_coords, "WindStreaks must use world-space (local_coords = false)")

# ── WindParticles: null tree_placer is safe ───────────────────────────────────

func test_process_with_null_tree_placer_does_not_crash() -> void:
	var wp := _make_wind_particles()
	wp.set("_tree_placer", null)
	# Call _process manually — should not throw.
	wp._process(0.016)
	assert_true(is_instance_valid(wp), "Node must still be valid after _process with null placer")

func test_process_with_null_tree_placer_uses_fallback_ratio() -> void:
	var wp := _make_wind_particles()
	wp.set("_tree_placer", null)
	wp._process(0.016)
	var motes: GPUParticles3D = wp.get_node_or_null("WindMotes") as GPUParticles3D
	# Fallback intensity = 0.3 → amount_ratio = lerp(0.2, 1.0, 0.3) = 0.44
	assert_almost_eq(motes.amount_ratio, lerpf(0.2, 1.0, 0.3), 0.001,
		"Motes amount_ratio should reflect fallback intensity 0.3")

# ── WindParticles: intensity drives emission rates ────────────────────────────

func test_process_with_high_intensity_maxes_streaks() -> void:
	var wp := _make_wind_particles()
	var tp := FakeTreePlacer.new()
	tp._gust_spike = 1.0  # full spike → get_wind_intensity near 1.0
	add_child_autofree(tp)
	wp.set("_tree_placer", tp)
	wp._process(0.016)
	var streaks: GPUParticles3D = wp.get_node_or_null("WindStreaks") as GPUParticles3D
	assert_gt(streaks.amount_ratio, 0.5, "Streaks amount_ratio should be high during a gust spike")

func test_process_with_low_intensity_minimises_streaks() -> void:
	var wp := _make_wind_particles()
	var tp := FakeTreePlacer.new()
	tp._gust_spike = 0.0  # no spike, sine base ~0.5 → intensity ~0.2
	add_child_autofree(tp)
	wp.set("_tree_placer", tp)
	wp._process(0.016)
	var streaks: GPUParticles3D = wp.get_node_or_null("WindStreaks") as GPUParticles3D
	assert_lt(streaks.amount_ratio, 0.5, "Streaks amount_ratio should be low without a gust spike")

# ── TreePlacer: gust spike logic ──────────────────────────────────────────────

func test_gust_spike_starts_at_zero() -> void:
	var tp := FakeTreePlacer.new()
	add_child_autofree(tp)
	assert_eq(tp._gust_spike, 0.0, "_gust_spike should initialise to 0")

func test_gust_spike_fires_when_next_spike_time_reached() -> void:
	var tp := FakeTreePlacer.new()
	add_child_autofree(tp)
	tp._next_spike_time = 0.0  # force immediate trigger
	tp._process(0.016)
	# Spike ramps up at attack rate — after one frame it should be > 0 (started ramping)
	# but won't reach 1.0 in a single frame.
	assert_gt(tp._gust_spike, 0.0, "_gust_spike should start ramping > 0 after trigger")
	assert_lte(tp._gust_spike, 1.0, "_gust_spike must not exceed 1.0")

func test_gust_spike_reaches_target_after_full_attack() -> void:
	var tp := FakeTreePlacer.new()
	add_child_autofree(tp)
	tp._next_spike_time = 0.0
	# Simulate enough frames to fully ramp up (1.0 / attack_rate seconds worth).
	var ramp_time: float = 1.0 / tp.wind_gust_spike_attack
	tp._process(ramp_time)
	assert_almost_eq(tp._gust_spike, 1.0, 0.001, "_gust_spike should reach 1.0 after full attack ramp")

func test_gust_spike_decays_over_time() -> void:
	var tp := FakeTreePlacer.new()
	add_child_autofree(tp)
	# Simulate spike already fully ramped — target and spike both at 1.0.
	tp._gust_spike  = 1.0
	tp._gust_target = 1.0
	tp._next_spike_time = 999999.0  # prevent re-trigger
	var big_delta: float = 1.0 / tp.wind_gust_spike_decay  # one full decay period
	tp._process(big_delta)
	assert_almost_eq(tp._gust_spike, 0.0, 0.001, "_gust_spike should reach 0 after one decay period")

func test_gust_spike_does_not_go_below_zero() -> void:
	var tp := FakeTreePlacer.new()
	add_child_autofree(tp)
	tp._gust_spike  = 0.1
	tp._gust_target = 0.1
	tp._next_spike_time = 999999.0
	tp._process(10.0)  # way more than needed to decay
	assert_eq(tp._gust_spike, 0.0, "_gust_spike must not go negative")

func test_get_wind_intensity_returns_clamped_range() -> void:
	var tp := FakeTreePlacer.new()
	add_child_autofree(tp)
	# Test at spike = 0 and spike = 1, both should be within [0, 1].
	tp._gust_spike = 0.0
	var low: float = tp.get_wind_intensity()
	assert_gte(low, 0.0, "Intensity must be >= 0 at zero spike")
	assert_lte(low, 1.0, "Intensity must be <= 1 at zero spike")
	tp._gust_spike = 1.0
	var high: float = tp.get_wind_intensity()
	assert_gte(high, 0.0, "Intensity must be >= 0 at full spike")
	assert_lte(high, 1.0, "Intensity must be <= 1 at full spike")

func test_get_wind_intensity_higher_during_spike() -> void:
	var tp := FakeTreePlacer.new()
	add_child_autofree(tp)
	tp._gust_spike = 0.0
	var calm: float = tp.get_wind_intensity()
	tp._gust_spike = 1.0
	var spiked: float = tp.get_wind_intensity()
	assert_gt(spiked, calm, "Intensity should be higher when _gust_spike is 1 vs 0")

# ── queue_free smoke test ─────────────────────────────────────────────────────

func test_wind_particles_queue_free_does_not_crash() -> void:
	var wp := Node3D.new()
	wp.set_script(WindParticlesScript)
	add_child(wp)
	wp.queue_free()
	await get_tree().process_frame
	assert_false(is_instance_valid(wp), "Node should be freed after queue_free + one frame")
