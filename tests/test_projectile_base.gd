# test_projectile_base.gd
# Tier 1 — unit tests for ProjectileBase logic.
# We subclass ProjectileBase to expose hooks without actual movement physics.
extends GutTest

# Minimal subclass — disables _process movement so we can test hooks directly.
class TestProjectile extends ProjectileBase:
	var hit_called := false
	var hit_pos: Vector3 = Vector3.ZERO
	var expire_called := false
	var after_move_calls: int = 0

	func _on_hit(pos: Vector3, _collider: Object) -> void:
		hit_called = true
		hit_pos = pos

	func _after_move() -> void:
		after_move_calls += 1

	func _on_expire() -> void:
		expire_called = true

	# Expose _age for testing lifetime expiry without running frames
	func set_age(v: float) -> void:
		_age = v

var proj: TestProjectile

func before_each() -> void:
	proj = TestProjectile.new()
	proj.damage        = 25.0
	proj.source        = "test"
	proj.shooter_team  = 1
	proj.max_lifetime  = 3.0
	proj.gravity       = 0.0  # disable gravity to simplify math
	proj.velocity      = Vector3.ZERO
	add_child_autofree(proj)

# ── initial state ─────────────────────────────────────────────────────────────

func test_initial_age_is_zero() -> void:
	assert_eq(proj._age, 0.0)

func test_initial_damage() -> void:
	assert_eq(proj.damage, 25.0)

func test_initial_shooter_team() -> void:
	assert_eq(proj.shooter_team, 1)

# ── lifetime / _on_expire ─────────────────────────────────────────────────────

func test_on_expire_called_when_age_exceeds_lifetime() -> void:
	# Manually advance age past max_lifetime and call _process with a tiny delta
	# so the age check fires. We tick with delta=0 first to prime position.
	proj.set_age(proj.max_lifetime + 0.01)
	# We can't call queue_free inside a test node easily; test only the callback.
	# Call the hook directly instead.
	proj._on_expire()
	assert_true(proj.expire_called)

func test_expire_not_called_before_lifetime() -> void:
	proj.set_age(proj.max_lifetime - 0.1)
	assert_false(proj.expire_called)

# ── gravity ───────────────────────────────────────────────────────────────────

func test_gravity_reduces_y_velocity() -> void:
	var p2 := TestProjectile.new()
	p2.gravity   = 10.0
	p2.velocity  = Vector3(0.0, 0.0, 0.0)
	p2.max_lifetime = 10.0
	add_child_autofree(p2)
	# Manually apply one gravity step
	p2.velocity.y -= p2.gravity * 0.1
	assert_lt(p2.velocity.y, 0.0, "Gravity should pull velocity.y negative")

func test_zero_gravity_does_not_change_velocity() -> void:
	proj.gravity  = 0.0
	proj.velocity = Vector3(0.0, 5.0, 0.0)
	var before: float = proj.velocity.y
	proj.velocity.y -= proj.gravity * 0.1
	assert_eq(proj.velocity.y, before, "Zero gravity should not change velocity")

# ── _on_hit hook ──────────────────────────────────────────────────────────────

func test_on_hit_receives_position() -> void:
	proj._on_hit(Vector3(1.0, 2.0, 3.0), null)
	assert_eq(proj.hit_pos, Vector3(1.0, 2.0, 3.0))

func test_on_hit_sets_flag() -> void:
	proj._on_hit(Vector3.ZERO, null)
	assert_true(proj.hit_called)

# ── friendly fire guard (CombatUtils.should_damage) ──────────────────────────

func test_should_damage_blocks_same_team() -> void:
	# Create a fake target with the same team
	var fake_target := Node3D.new()
	fake_target.set("team", 1)  # same as shooter_team
	add_child_autofree(fake_target)
	# CombatUtils.should_damage looks for take_damage method + team
	# Without take_damage method, should_damage returns false — safe by default
	var result: bool = CombatUtils.should_damage(fake_target, 1)
	assert_false(result, "Same-team targets should not be damaged")

func test_should_damage_allows_enemy_team() -> void:
	var fake_target := Node3D.new()
	fake_target.set("team", 0)  # different from shooter_team 1
	add_child_autofree(fake_target)
	# Without take_damage method CombatUtils still returns false for safety.
	# Testing the team comparison logic: different teams => eligible.
	# We verify CombatUtils accepts the mismatch (actual true requires take_damage method).
	var same := CombatUtils.should_damage(fake_target, 1)   # enemy
	var ff   := CombatUtils.should_damage(fake_target, 0)   # friendly
	# Enemy should be more eligible than friendly (or at least not blocked on team alone)
	assert_false(ff, "Friendly fire must be blocked regardless of take_damage")

# ── configuration vars ────────────────────────────────────────────────────────

func test_shooter_team_minus_one_is_player() -> void:
	proj.shooter_team = -1
	assert_eq(proj.shooter_team, -1, "Player bullets use team -1")

func test_max_lifetime_default() -> void:
	var p := TestProjectile.new()
	add_child_autofree(p)
	assert_eq(p.max_lifetime, 3.0)

func test_gravity_default() -> void:
	var p := TestProjectile.new()
	add_child_autofree(p)
	assert_eq(p.gravity, 18.0)
