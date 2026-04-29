# test_minion_base.gd
# Tier 1 — unit tests for MinionBase combat and state logic.
# We subclass MinionBase and override all hooks that touch assets/scene tree
# so the tests run cleanly without GLB files or AudioStreamPlayer children.
extends GutTest

class FakeMinion extends MinionBase:
	var death_hook_called := false
	var fire_at_calls: int = 0

	func _build_visuals() -> void:
		pass  # skip GLB loading

	func _on_death() -> void:
		death_hook_called = true

	func _fire_at(_target: Node3D) -> void:
		fire_at_calls += 1

	# @onready vars (shoot_audio, death_audio) resolve after _ready fires.
	# We create stub nodes in _init (before entering the tree) so they are
	# found by name when the engine resolves @onready bindings.
	func _init() -> void:
		var sa := AudioStreamPlayer3D.new()
		sa.name = "ShootAudio"
		add_child(sa)
		var da := AudioStreamPlayer3D.new()
		da.name = "DeathAudio"
		add_child(da)

	func _ready() -> void:
		health = max_health
		add_to_group("minions")
		add_to_group("minion_units")
		# Do NOT call _init_visuals or _cache_static_refs; we have no scene tree deps

var minion: FakeMinion

func before_each() -> void:
	minion = FakeMinion.new()
	minion.max_health     = 80.0
	minion.attack_damage  = 10.0
	minion.detect_range   = 12.0
	minion.attack_cooldown = 1.5
	minion.speed           = 4.0
	add_child_autofree(minion)
	minion.setup(0, [], 0)
	LevelSystem.clear_all()
	LevelSystem.register_peer(1)

# ── setup / initial state ─────────────────────────────────────────────────────

func test_setup_health_equals_max() -> void:
	assert_eq(minion.health, 80.0)

func test_setup_assigns_team() -> void:
	assert_eq(minion.team, 0)

func test_setup_adds_to_minions_group() -> void:
	assert_true(minion.is_in_group("minions"))

func test_setup_adds_to_minion_units_group() -> void:
	assert_true(minion.is_in_group("minion_units"))

func test_initial_not_dead() -> void:
	assert_false(minion._dead)

# ── take_damage ───────────────────────────────────────────────────────────────

func test_take_damage_reduces_health() -> void:
	minion.take_damage(20.0, "player", 1)
	assert_eq(minion.health, 60.0)

func test_take_damage_friendly_fire_ignored() -> void:
	minion.take_damage(20.0, "player", 0)  # same team
	assert_eq(minion.health, 80.0, "Friendly fire must not reduce health")

func test_take_damage_puppet_ignored() -> void:
	minion.is_puppet = true
	minion.take_damage(20.0, "player", 1)
	assert_eq(minion.health, 80.0, "Puppet minion should not process damage")

func test_take_damage_already_dead_ignored() -> void:
	minion._dead = true
	minion.take_damage(20.0, "player", 1)
	assert_eq(minion.health, 80.0, "Dead minion should not take further damage")

func test_take_damage_accumulates() -> void:
	minion.take_damage(15.0, "player", 1)
	minion.take_damage(25.0, "player", 1)
	assert_eq(minion.health, 40.0)

# ── death ─────────────────────────────────────────────────────────────────────

func test_death_at_zero_hp() -> void:
	minion.take_damage(80.0, "player", 1)
	assert_true(minion._dead)

func test_death_at_negative_hp() -> void:
	minion.take_damage(999.0, "player", 1)
	assert_true(minion._dead)

func test_death_removes_from_minions_group() -> void:
	minion.take_damage(80.0, "player", 1)
	assert_false(minion.is_in_group("minions"), "Dead minion must leave 'minions' group")

func test_on_death_hook_called() -> void:
	minion.take_damage(80.0, "player", 1)
	assert_true(minion.death_hook_called)

func test_death_only_once() -> void:
	minion.take_damage(80.0, "player", 1)
	# Calling _die() a second time should be a no-op
	minion._die()
	assert_true(minion._dead)  # still dead, didn't crash

func test_xp_awarded_to_killer_in_singleplayer() -> void:
	minion._killer_peer_id = 1
	var xp_before: int = LevelSystem.get_xp(1)
	minion.take_damage(80.0, "player", 1, 1)
	var xp_after: int = LevelSystem.get_xp(1)
	assert_gt(xp_after, xp_before, "Killer should receive XP on minion death (singleplayer)")

# ── apply_slow ────────────────────────────────────────────────────────────────

func test_apply_slow_sets_timer_and_mult() -> void:
	minion.apply_slow(3.0, 0.5)
	assert_eq(minion._slow_timer, 3.0)
	assert_eq(minion._slow_mult, 0.5)

func test_apply_slow_does_not_decrease_existing_timer() -> void:
	minion.apply_slow(5.0, 0.5)
	minion.apply_slow(2.0, 0.3)
	assert_eq(minion._slow_timer, 5.0, "Slow timer should not decrease below existing value")

func test_apply_slow_stacks_stronger_mult() -> void:
	minion.apply_slow(2.0, 0.6)
	minion.apply_slow(2.0, 0.3)
	assert_eq(minion._slow_mult, 0.3, "Stronger slow (lower mult) should replace weaker one")

# ── apply_puppet_state ────────────────────────────────────────────────────────

func test_apply_puppet_state_updates_target_position() -> void:
	minion.is_puppet = true
	minion.apply_puppet_state(Vector3(5.0, 0.0, 3.0), 0.0, 80.0)
	assert_eq(minion._puppet_target_pos, Vector3(5.0, 0.0, 3.0))

func test_apply_puppet_state_triggers_die_at_zero_hp() -> void:
	minion.is_puppet = true
	minion.apply_puppet_state(Vector3.ZERO, 0.0, 0.0)
	assert_true(minion._dead, "Puppet should die when hp <= 0 arrives via state update")

func test_apply_puppet_state_does_not_rediie() -> void:
	minion.is_puppet = true
	minion._dead = true
	minion.apply_puppet_state(Vector3.ZERO, 0.0, 0.0)
	assert_true(minion._dead)  # still dead, should not crash

# ── static model helpers ──────────────────────────────────────────────────────

func test_set_model_characters_updates_paths() -> void:
	# Goblin GLBs are fixed — set_model_characters is a no-op for paths now.
	MinionBase.set_model_characters("x", "z")
	assert_true(MinionBase.get_blue_model_path().ends_with("goblin_blue.glb"),
		"Blue model path should point to goblin_blue.glb")
	assert_true(MinionBase.get_red_model_path().ends_with("goblin_red.glb"),
		"Red model path should point to goblin_red.glb")

func test_set_model_characters_clears_cache() -> void:
	MinionBase._blue_scene_cache = PackedScene.new()  # simulate cached value
	MinionBase.set_model_characters("a", "b")
	assert_null(MinionBase._blue_scene_cache, "Cache should be cleared after character change")

# ── waypoint marching (unit logic, no physics) ────────────────────────────────

func test_waypoints_assigned_by_setup() -> void:
	var wps: Array[Vector3] = [Vector3(0, 0, 10), Vector3(0, 0, 20)]
	minion.setup(0, wps, 1)
	assert_eq(minion.waypoints.size(), 2)

func test_current_waypoint_reset_on_setup() -> void:
	minion.current_waypoint = 5
	minion.setup(0, [], 0)
	assert_eq(minion.current_waypoint, 0)

# ── force_die ─────────────────────────────────────────────────────────────────

func test_force_die_marks_dead() -> void:
	minion.force_die()
	assert_true(minion._dead)

func test_force_die_calls_on_death_hook() -> void:
	minion.force_die()
	assert_true(minion.death_hook_called)
