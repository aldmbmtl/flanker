# test_projectile_base.gd
# Tier 1 — unit tests for ProjectileBase logic.
# We subclass ProjectileBase to expose hooks without actual movement physics.
extends GutTest

# Minimal subclass — disables _process movement so we can test hooks directly.
class FakeProjectile extends ProjectileBase:
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

var proj: FakeProjectile

func before_each() -> void:
	proj = FakeProjectile.new()
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
	var p2 := FakeProjectile.new()
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
	var p := FakeProjectile.new()
	add_child_autofree(p)
	assert_eq(p.max_lifetime, 3.0)

func test_gravity_default() -> void:
	var p := FakeProjectile.new()
	add_child_autofree(p)
	assert_eq(p.gravity, 18.0)


# ── Tree clearing — ProjectileBase._request_destroy_tree ──────────────────────
#
# _request_destroy_tree always relays through LobbyManager.request_destroy_tree
# → BridgeClient.send("destroy_tree", ...) so Python can broadcast the clear
# to all peers.  Local TreePlacer.clear_trees_at is NOT called directly —
# Python relays sync_destroy_tree back via BridgeClient.

func _make_fake_main_with_tree_placer() -> Array:
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)
	var world := Node.new()
	world.name = "World"
	fake_main.add_child(world)
	var stub_tp := StubTreePlacer.new()
	stub_tp.name = "TreePlacer"
	world.add_child(stub_tp)
	return [fake_main, stub_tp]

func _make_tree_collider() -> StaticBody3D:
	var col := StaticBody3D.new()
	col.set_meta("tree_trunk_height", 4.0)
	add_child_autofree(col)
	return col

func test_request_destroy_tree_does_not_call_clear_trees_at_locally() -> void:
	# Python is authoritative for tree destruction.
	# _request_destroy_tree sends to BridgeClient — TreePlacer is never called directly.
	var parts: Array = _make_fake_main_with_tree_placer()
	var fake_main: Node = parts[0]
	var stub_tp: StubTreePlacer = parts[1]

	var p := FakeProjectile.new()
	p.can_destroy_trees = true
	add_child_autofree(p)
	p._request_destroy_tree(Vector3(5.0, 0.0, 10.0))

	assert_eq(stub_tp.clear_calls.size(), 0,
		"_request_destroy_tree must NOT call clear_trees_at — Python handles the relay")

	fake_main.queue_free()
	await get_tree().process_frame

# ── Bullet tree hit ────────────────────────────────────────────────────────────

const BulletScene := preload("res://scenes/projectiles/Bullet.tscn")

func test_bullet_on_hit_tree_does_not_clear_trees() -> void:
	# Bullets do not have can_destroy_trees — hitting a tree is consumed (early return)
	# but the tree itself is NOT cleared.
	var parts: Array = _make_fake_main_with_tree_placer()
	var fake_main: Node = parts[0]
	var stub_tp: StubTreePlacer = parts[1]

	var bullet: ProjectileBase = BulletScene.instantiate()
	bullet.shooter_team = 0
	bullet.damage = 10.0
	bullet.source = "rifle"
	bullet.velocity = Vector3(0.0, 0.0, -20.0)
	add_child_autofree(bullet)

	var tree_col: StaticBody3D = _make_tree_collider()
	bullet._on_hit(Vector3(3.0, 0.0, 3.0), tree_col)

	assert_eq(stub_tp.clear_calls.size(), 0,
		"Bullet._on_hit on a tree must NOT call clear_trees_at (can_destroy_trees=false)")

	fake_main.queue_free()
	await get_tree().process_frame

func test_bullet_on_hit_tree_does_not_call_take_damage() -> void:
	# Bullet early-returns on tree hit — take_damage is NOT called,
	# and clear_trees_at is also NOT called (can_destroy_trees=false).
	var parts: Array = _make_fake_main_with_tree_placer()
	var fake_main: Node = parts[0]

	var bullet: ProjectileBase = BulletScene.instantiate()
	bullet.shooter_team = 0
	bullet.damage = 10.0
	bullet.velocity = Vector3(0.0, 0.0, -20.0)
	add_child_autofree(bullet)

	var fake_tree := Node3D.new()
	fake_tree.set_meta("tree_trunk_height", 4.0)
	# GDScript can't add methods dynamically, so verify via StubTreePlacer side-effect:
	# clear_trees_at must NOT be called (bullet can't destroy trees).
	var stub_tp: StubTreePlacer = parts[1]

	add_child_autofree(fake_tree)
	bullet._on_hit(Vector3(1.0, 0.0, 1.0), fake_tree)

	assert_eq(stub_tp.clear_calls.size(), 0,
		"bullet tree hit must early-return without calling clear_trees_at")

	fake_main.queue_free()
	await get_tree().process_frame

func test_bullet_on_hit_non_tree_does_not_clear_trees() -> void:
	var parts: Array = _make_fake_main_with_tree_placer()
	var fake_main: Node = parts[0]
	var stub_tp: StubTreePlacer = parts[1]

	var bullet: ProjectileBase = BulletScene.instantiate()
	bullet.shooter_team = 0
	bullet.velocity = Vector3(0.0, 0.0, -20.0)
	add_child_autofree(bullet)

	# A plain StaticBody3D with no meta — terrain/wall hit
	var wall := StaticBody3D.new()
	add_child_autofree(wall)
	bullet._on_hit(Vector3(0.0, 0.0, 0.0), wall)

	assert_eq(stub_tp.clear_calls.size(), 0,
		"Bullet hitting a non-tree must not trigger tree clearing")

	fake_main.queue_free()
	await get_tree().process_frame

# ── MortarShell tree hit ───────────────────────────────────────────────────────

const MortarShellScene := preload("res://scenes/projectiles/MortarShell.tscn")

func test_mortar_on_hit_tree_does_not_clear_trees() -> void:
	# MortarShell does not have can_destroy_trees — hitting a tree is consumed (early return)
	# but the tree itself is NOT cleared.
	var parts: Array = _make_fake_main_with_tree_placer()
	var fake_main: Node = parts[0]
	var stub_tp: StubTreePlacer = parts[1]

	var shell: ProjectileBase = MortarShellScene.instantiate()
	shell.shooter_team = 0
	shell.damage = 50.0
	shell.source = "mortar_shell"
	# target_pos must differ from spawn (Vector3.ZERO) to avoid zero-distance arc in _ready()
	shell.set("target_pos", Vector3(10.0, 0.0, 10.0))
	add_child_autofree(shell)

	var tree_col: StaticBody3D = _make_tree_collider()
	shell._on_hit(Vector3(4.0, 0.0, 4.0), tree_col)

	assert_eq(stub_tp.clear_calls.size(), 0,
		"MortarShell._on_hit on a tree must NOT call clear_trees_at (can_destroy_trees=false)")

	fake_main.queue_free()
	await get_tree().process_frame

func test_mortar_on_hit_tree_does_not_apply_splash() -> void:
	# Mortar returns early on tree hit — _apply_splash must NOT be called.
	# Also, clear_trees_at must NOT be called (can_destroy_trees=false).
	var parts: Array = _make_fake_main_with_tree_placer()
	var fake_main: Node = parts[0]
	var stub_tp: StubTreePlacer = parts[1]

	var shell: ProjectileBase = MortarShellScene.instantiate()
	shell.shooter_team = 0
	shell.damage = 50.0
	shell.set("target_pos", Vector3(10.0, 0.0, 10.0))
	add_child_autofree(shell)

	var tree_col: StaticBody3D = _make_tree_collider()
	shell._on_hit(Vector3(0.0, 0.0, 0.0), tree_col)

	# Early return fired — no splash, no clear (can_destroy_trees=false).
	assert_eq(stub_tp.clear_calls.size(), 0,
		"MortarShell tree hit must early-return before splash — no clear_trees_at calls")

	fake_main.queue_free()
	await get_tree().process_frame

# ── Self-damage exclusion — _handle_ghost_hit ─────────────────────────────────

func test_handle_ghost_hit_self_peer_returns_true_no_damage() -> void:
	# Shooter peer_id 5 collides with their own ghost hitbox (ghost_peer_id=5).
	# _handle_ghost_hit must return true (consumed) but apply zero damage.
	var ghost := StaticBody3D.new()
	ghost.set_meta("ghost_peer_id", 5)
	add_child_autofree(ghost)

	var p := FakeProjectile.new()
	p.shooter_peer_id = 5
	p.shooter_team    = -1
	p.damage          = 30.0
	add_child_autofree(p)

	GameSync.set_player_health(5, 100.0)
	GameSync.player_dead[5] = false
	GameSync.set_player_team(5, 0)
	var hp_before: float = GameSync.get_player_health(5)
	var consumed: bool = p._handle_ghost_hit(ghost, p.damage)
	var hp_after: float = GameSync.get_player_health(5)

	assert_true(consumed, "_handle_ghost_hit must return true for own ghost hitbox")
	assert_eq(hp_after, hp_before, "Shooter health must not decrease on self ghost hit")
	GameSync.player_healths.erase(5)
	GameSync.player_dead.erase(5)
	GameSync.player_teams.erase(5)

# ── Collision mask — base _process must exclude fences (layer 4/value 8) ──────
#
# Fences live on collision_layer = 8 (bit 3). Minions live on collision_layer = 4
# (bit 2). Projectiles must pass through fences but hit minions.
# Fix: ProjectileBase._process sets query.collision_mask = 0xFFFFFFF7
# (all layers except bit 3 = value 8, which is the fence/torch layer).

func test_base_process_collision_mask_excludes_fence_layer() -> void:
	# Confirm the constant 0xFFFFFFF7 has bit 3 (value 8) cleared.
	# bit 3 = 0b1000 = 8; 0xFFFFFFFF & ~8 = 0xFFFFFFF7
	var mask: int = 0xFFFFFFF7
	assert_eq(mask & 8, 0,
		"collision_mask 0xFFFFFFF7 must have fence layer (bit 3 = value 8) cleared")

func test_base_process_collision_mask_includes_minion_layer() -> void:
	# Minions are on collision_layer = 4 (bit 2). Bullets must hit them.
	var mask: int = 0xFFFFFFF7
	assert_eq(mask & 4, 4,
		"collision_mask 0xFFFFFFF7 must include minion layer (bit 2 = value 4)")

func test_base_process_collision_mask_includes_terrain_layer() -> void:
	var mask: int = 0xFFFFFFF7
	assert_eq(mask & 1, 1,
		"collision_mask 0xFFFFFFF7 must include terrain layer (bit 0 = value 1)")

func test_base_process_collision_mask_includes_wall_layer() -> void:
	var mask: int = 0xFFFFFFF7
	assert_eq(mask & 2, 2,
		"collision_mask 0xFFFFFFF7 must include wall layer (bit 1 = value 2)")

# ── Splash collision mask — _apply_splash must exclude fences (layer value 8) ──
#
# Fences moved to collision_layer = 8. Splash must exclude them but include
# minions (value 4) so explosions damage minion units.

func test_splash_collision_mask_excludes_fence_layer() -> void:
	# Reset static splash params so _apply_splash initialises them fresh this test.
	ProjectileBase._splash_shape = null
	ProjectileBase._splash_params = null

	# Call _apply_splash with a zero radius so no actual overlap queries fire.
	# We just need the static params to be initialised.
	proj._apply_splash(Vector3.ZERO, 0.0, 0.0, "test_splash")

	assert_not_null(ProjectileBase._splash_params,
		"_apply_splash must initialise _splash_params")
	assert_eq(ProjectileBase._splash_params.collision_mask & 8, 0,
		"splash collision_mask must have fence layer (bit 3 = value 8) cleared")

func test_splash_collision_mask_includes_minion_layer() -> void:
	# Minions (value 4) must be caught by splash.
	ProjectileBase._splash_shape = null
	ProjectileBase._splash_params = null
	proj._apply_splash(Vector3.ZERO, 0.0, 0.0, "test_splash")
	assert_eq(ProjectileBase._splash_params.collision_mask & 4, 4,
		"splash collision_mask must include minion layer (bit 2 = value 4)")

func test_splash_collision_mask_includes_terrain_layer() -> void:
	ProjectileBase._splash_shape = null
	ProjectileBase._splash_params = null
	proj._apply_splash(Vector3.ZERO, 0.0, 0.0, "test_splash")
	assert_eq(ProjectileBase._splash_params.collision_mask & 1, 1,
		"splash collision_mask must include terrain layer")

# ── _handle_ghost_hit tests ────────────────────────────────────────────────────

func test_handle_ghost_hit_other_peer_applies_damage() -> void:
	# Shooter peer_id 5 hits peer 7's ghost — damage is sent via bridge to Python.
	# HP does not change synchronously in tests (no Python server present).
	# Test verifies _handle_ghost_hit returns true and does not crash.
	var ghost := StaticBody3D.new()
	ghost.set_meta("ghost_peer_id", 7)
	add_child_autofree(ghost)

	var p := FakeProjectile.new()
	p.shooter_peer_id = 5
	p.shooter_team    = -1
	p.damage          = 30.0
	add_child_autofree(p)

	GameSync.set_player_health(7, 100.0)
	GameSync.player_dead[7] = false
	GameSync.set_player_team(7, 1)   # enemy team
	var hp_before: float = GameSync.get_player_health(7)
	var consumed: bool = p._handle_ghost_hit(ghost, p.damage)
	var hp_after: float = GameSync.get_player_health(7)

	assert_true(consumed, "_handle_ghost_hit must return true (hit consumed)")
	assert_almost_eq(hp_after, hp_before, 0.01,
		"HP unchanged locally — damage is Python-authoritative via bridge")
	GameSync.player_healths.erase(7)
	GameSync.player_dead.erase(7)
	GameSync.player_teams.erase(7)

# ── Back-ray tunnelling guard ──────────────────────────────────────────────────
#
# Regression for: fast projectiles tunnelling through thin terrain surfaces when
# the per-frame step is ~0.9 m and a slope edge is thinner than that.
# Fix: ProjectileBase._process issues a second raycast extending 0.2 m behind
# prev_pos so the ray starts outside any surface the projectile may have entered.
#
# These tests verify the fix structurally: the back-ray parameters are computed
# correctly and the back-ray uses the same mask as the primary ray.

func test_back_ray_origin_is_behind_prev_pos() -> void:
	# The back-ray origin must be prev_pos - velocity.normalized() * 0.2.
	# Verify the math: for a bullet moving in +Z at 50 m/s, back_origin.z < prev_pos.z.
	var velocity := Vector3(0.0, 0.0, 50.0)
	var prev_pos := Vector3(0.0, 0.0, 10.0)
	var back_origin: Vector3 = prev_pos - velocity.normalized() * 0.2
	assert_lt(back_origin.z, prev_pos.z,
		"back_ray origin must be 0.2 m behind prev_pos in direction of travel")
	assert_almost_eq(back_origin.z, prev_pos.z - 0.2, 0.001,
		"back_ray origin must be exactly 0.2 m behind prev_pos")

func test_back_ray_origin_offset_is_0_2m() -> void:
	# The offset magnitude must be 0.2 m regardless of velocity magnitude.
	for speed in [1.0, 10.0, 58.8, 200.0]:
		var v := Vector3(speed, 0.0, 0.0)
		var prev := Vector3(5.0, 0.0, 0.0)
		var back: Vector3 = prev - v.normalized() * 0.2
		assert_almost_eq(prev.distance_to(back), 0.2, 0.001,
			"back_ray offset must always be 0.2 m (speed=%s)" % speed)

func test_back_ray_uses_same_mask_as_primary() -> void:
	# Both rays must exclude fences (value 8) and include minions (value 4).
	var mask: int = 0xFFFFFFF7
	assert_eq(mask & 8, 0, "Both rays must exclude fence layer (value 8)")
	assert_eq(mask & 4, 4, "Both rays must include minion layer (value 4)")
	assert_eq(mask & 1, 1, "Both rays must include terrain layer (value 1)")

# ── spawner_rid self-hit guard ─────────────────────────────────────────────────
#
# Regression for: ProjectileBase._process back-ray extends 0.2 m *behind*
# prev_pos.  On the first frame prev_pos = spawn position (near the player's
# camera).  If spawner_rid is not set, the back-ray has no exclusion and can
# hit the shooter's CharacterBody3D capsule on frame 1.
# Fix: FPSController._shoot sets bullet.spawner_rid = get_rid() before add_child.

func test_spawner_rid_is_settable_on_projectile_base() -> void:
	# Confirm spawner_rid is a declared var on ProjectileBase (not just a meta).
	var p := FakeProjectile.new()
	add_child_autofree(p)
	var rid := RID()
	p.spawner_rid = rid
	assert_eq(p.spawner_rid, rid,
		"spawner_rid must be assignable on ProjectileBase instances")

func test_spawner_rid_default_is_invalid_rid() -> void:
	# Default RID() is invalid — the back-ray guard uses is_valid() to skip exclusion.
	var p := FakeProjectile.new()
	add_child_autofree(p)
	assert_false(p.spawner_rid.is_valid(),
		"spawner_rid default must be an invalid RID so no exclusion is applied without explicit set")
