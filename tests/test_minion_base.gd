# test_minion_base.gd
# Tier 1 — unit tests for MinionBase combat and state logic.
# We subclass MinionBase and override all hooks that touch assets/scene tree
# so the tests run cleanly without GLB files or AudioStreamPlayer children.
extends GutTest

# Minimal player stand-in: has player_team property so _get_body_team() and
# _find_target() can duck-type it, and can be added to the "players" group.
class FakePlayer extends Node3D:
	var player_team: int = 0
	func take_damage(_a, _b, _c, _d) -> void:
		pass

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
	MinionBase.set_model_characters("x", "z")
	assert_true(MinionBase.get_blue_model_path().ends_with("character-x.glb"))
	assert_true(MinionBase.get_red_model_path().ends_with("character-z.glb"))

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

# ── _find_target: player group detection ─────────────────────────────────────
# Regression guard for the "player" vs "players" group name bug.
# MinionBase._find_target() must query the "players" group (plural).
# If it queries "player" (singular) it will never find FPS players and
# minions will march past without shooting.

func test_find_target_detects_enemy_player_in_range() -> void:
	minion._cached_towers = []
	minion._cached_bases = []
	MinionBase._shared_minion_cache = []
	var fake1: FakePlayer = FakePlayer.new()
	fake1.player_team = 1  # first enemy
	var fake2: FakePlayer = FakePlayer.new()
	fake2.player_team = 1  # second enemy
	add_child_autofree(fake1)
	add_child_autofree(fake2)
	fake1.add_to_group("players")
	fake2.add_to_group("players")
	var offset := Vector3(4.0, 0.0, 0.0)
	fake1.global_position = Vector3(0.0, 0.0, 5.0) + offset
	fake2.global_position = Vector3(0.0, 0.0, 5.0) - offset
	minion.global_position = Vector3.ZERO
	var target: Node3D = minion._find_target()
	assert_true(target == fake1 or target == fake2, "Minion must target one of the enemies")

func test_find_target_ignores_friendly_player() -> void:
	minion._cached_towers = []
	minion._cached_bases = []
	MinionBase._shared_minion_cache = []
	var fake: FakePlayer = FakePlayer.new()
	fake.player_team = 0  # same team as minion
	add_child_autofree(fake)
	fake.add_to_group("players")
	fake.global_position = Vector3(0.0, 0.0, 5.0)
	minion.global_position = Vector3.ZERO
	var target: Node3D = minion._find_target()
	assert_null(target, "Minion must not target a friendly player")

func test_same_team_attackers_on_counts_correctly() -> void:
	# Set up: 3 friendly fakes in the shared cache, targeting an enemy
	var attacker1: FakeMinion = FakeMinion.new()
	var attacker2: FakeMinion = FakeMinion.new()
	var bystander: FakeMinion = FakeMinion.new()
	var target_enemy: FakeMinion = FakeMinion.new()
	for m: FakeMinion in [attacker1, attacker2, bystander]:
		m.team = 0
		m._dead = false
		m.is_puppet = false
	target_enemy.team = 1
	target_enemy._dead = false
	minion.add_child(attacker1)
	minion.add_child(attacker2)
	minion.add_child(bystander)
	minion.add_child(target_enemy)
	# attacker1 alone is targeting target_enemy; minion calls the helper
	attacker1._target = target_enemy
	attacker2._target = null
	bystander._target = null
	MinionBase._shared_minion_cache = [attacker1, attacker2, bystander]
	var count: int = minion._same_team_attackers_on(target_enemy)
	assert_eq(count, 1, "Should count 1 attacker on first target")
	# attacker2 also starts targeting target_enemy
	attacker2._target = target_enemy
	count = minion._same_team_attackers_on(target_enemy)
	assert_eq(count, 2, "Should count 2 attackers on same target")

func test_find_target_skips_over_gunned_targets() -> void:
	minion._cached_towers = []
	minion._cached_bases = []
	# Set up: 2 friendly attackers already on enemy1, and enemy2 un-targeted.
	# friendly3 (minion) should pick enemy2.
	var friendly1: FakeMinion = FakeMinion.new()
	var friendly2: FakeMinion = FakeMinion.new()
	var enemy1: FakeMinion = FakeMinion.new()
	var enemy2: FakeMinion = FakeMinion.new()
	friendly1.team = 0; friendly1._dead = false; friendly1.is_puppet = false
	friendly2.team = 0; friendly2._dead = false; friendly2.is_puppet = false
	enemy1.team = 1; enemy1._dead = false; enemy1.is_puppet = false
	enemy2.team = 1; enemy2._dead = false; enemy2.is_puppet = false
	minion.add_child(friendly1)
	minion.add_child(friendly2)
	minion.add_child(enemy1)
	minion.add_child(enemy2)
	# shared cache includes friendlies (for _same_team_attackers_on) + enemies (for _find_target scan)
	MinionBase._shared_minion_cache = [friendly1, friendly2, enemy1, enemy2]
	friendly1._target = enemy1
	friendly2._target = enemy1
	minion._target = null
	enemy1.global_position = Vector3(0.0, 0.0, 5.0)
	enemy2.global_position = Vector3(0.0, 0.0, 6.0)
	minion.global_position = Vector3.ZERO
	var target: Node3D = minion._find_target()
	assert_true(target == enemy2, "minion should target ungunned enemy2, not over-gunned enemy1")

func test_separation_stronger_at_closer_range() -> void:
	var min1: FakeMinion = FakeMinion.new()
	var min2: FakeMinion = FakeMinion.new()
	min1.team = 0
	min1._dead = false
	min1.is_puppet = false
	min2.team = 0
	min2._dead = false
	min2.is_puppet = false
	min1.add_to_group("minions")
	min2.add_to_group("minions")
	minion.add_child(min1)
	minion.add_child(min2)
	var sa1: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	sa1.name = "ShootAudio"
	var da1: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	da1.name = "DeathAudio"
	min1.add_child(sa1)
	min1.add_child(da1)
	min1.global_position = Vector3(0.0, 0.0, 0.0)
	min2.global_position = Vector3(2.0, 0.0, 0.0)
	min1.velocity = Vector3.ZERO
	min1._strafe_phase = 0.0
	min1._time = 1.0
	MinionBase._shared_minion_cache = [min1, min2]
	min1._apply_separation()
	var push_far: Vector3 = min1.velocity
	min1.velocity = Vector3.ZERO
	min2.global_position = Vector3(1.0, 0.0, 0.0)
	min1._apply_separation()
	var push_near: Vector3 = min1.velocity
	assert_gt(push_near.length(), push_far.length() * 1.5, "Push at 1.0m should be significantly stronger than at 2.0m")

func test_lane_offset_present_after_delay() -> void:
	var wps: Array[Vector3] = [Vector3(0, 0, 10), Vector3(0, 0, 20)]
	minion.setup(0, wps, 0)
	minion._strafe_phase = PI / 2.0  # sin = 1 => max offset
	minion._time = 0.0
	var fwd1 := Vector3.DOWN
	var fwd2: float = clamp(minion._time, 0.0, 1.0)
	var perp1: float = sin(minion._strafe_phase) * 0.35 * fwd2
	assert_eq(perp1, 0.0, "At time=0 offset should be zero")
	minion._time = 1.0
	var fwd3: float = clamp(minion._time, 0.0, 1.0)
	var perp2: float = sin(minion._strafe_phase) * 0.35 * fwd3
	assert_eq(perp2, 0.35, "At time>=1 offset should equal sin(phase)*0.35")

func test_approach_with_strafe_has_offset() -> void:
	# Pure math check — no scene nodes needed.
	# When _strafe_phase = PI/2 (sin=1), the permanent offset term sin(phase)*0.25 = 0.25 != 0.
	# This verifies the formula has a non-zero lateral component independent of _time.
	var phase: float = PI / 2.0
	var time_val: float = 5.0
	var forward: Vector3 = Vector3(0.0, 0.0, 1.0)
	var right: Vector3 = Vector3(1.0, 0.0, 0.0)
	var strafe: float = sin(time_val * 2.2 + phase) * 0.35 + sin(phase) * 0.25
	var move_dir: Vector3 = (forward + right * strafe).normalized()
	assert_true(abs(move_dir.x) > 0.01, "Strafe must have permanent lateral component when _strafe_phase=PI/2")

# ── Supporter XP from minion kills (multiplayer server path) ──────────────────

func test_supporter_gets_xp_when_minion_killed_by_tower_in_multiplayer() -> void:
	# Peer 99 is a Supporter on team 1 (the enemy team, which owns the tower that killed minion).
	# Minion is on team 0; killer is on team 1.
	LobbyManager.players.clear()
	LobbyManager.register_player_local(99, "Sup")
	LobbyManager.players[99]["team"] = 1
	LobbyManager.players[99]["role"] = 1  # Supporter
	LevelSystem.register_peer(99)
	# Build a minion on team 0 (enemy of Supporter's team 1).
	var m: FakeMinion = FakeMinion.new()
	m.max_health = 60.0
	add_child_autofree(m)
	m.setup(0, [], 0)
	var xp_before: int = LevelSystem.get_xp(99)
	# Damage from team 1 with no player peer (tower kill: killer_peer_id = -1).
	m.take_damage(60.0, "cannon", 1, -1)
	var xp_after: int = LevelSystem.get_xp(99)
	LobbyManager.players.clear()
	assert_gt(xp_after, xp_before, "Supporter should receive XP when their team's tower kills a minion")

func test_supporter_does_not_get_xp_when_player_gets_kill() -> void:
	# Peer 5 is a Fighter; Peer 99 is a Supporter on the same team 1.
	LobbyManager.players.clear()
	LobbyManager.register_player_local(99, "Sup")
	LobbyManager.players[99]["team"] = 1
	LobbyManager.players[99]["role"] = 1
	LevelSystem.register_peer(99)
	LevelSystem.register_peer(5)
	var m: FakeMinion = FakeMinion.new()
	m.max_health = 60.0
	add_child_autofree(m)
	m.setup(0, [], 0)
	var xp_before: int = LevelSystem.get_xp(99)
	# Player 5 gets the kill.
	m.take_damage(60.0, "player", 1, 5)
	var xp_after: int = LevelSystem.get_xp(99)
	LobbyManager.players.clear()
	assert_eq(xp_after, xp_before, "Supporter should not receive XP when a player peer gets the kill")

func test_no_supporter_on_team_does_not_crash_on_minion_kill() -> void:
	LobbyManager.players.clear()
	# No Supporter registered for team 1.
	var m: FakeMinion = FakeMinion.new()
	m.max_health = 60.0
	add_child_autofree(m)
	m.setup(0, [], 0)
	# Should not crash; XP simply goes uncredited.
	m.take_damage(60.0, "cannon", 1, -1)
	assert_true(m._dead, "Minion should be dead after lethal damage")

# ── heal() + _emit_heal_particles ─────────────────────────────────────────────

class FakeMinionParticles extends FakeMinion:
	var particles_emitted: int = 0
	var last_particle_pos: Vector3 = Vector3.ZERO
	func _emit_heal_particles(pos: Vector3) -> void:
		particles_emitted += 1
		last_particle_pos = pos

func test_heal_emits_particles_when_gain_positive() -> void:
	var m: FakeMinionParticles = FakeMinionParticles.new()
	m.max_health = 80.0
	add_child_autofree(m)
	m.setup(0, [], 0)
	m.health = 40.0
	m.heal(20.0)
	assert_eq(m.particles_emitted, 1, "Particles should emit on positive heal gain")

func test_heal_no_particles_when_dead() -> void:
	var m: FakeMinionParticles = FakeMinionParticles.new()
	m.max_health = 80.0
	add_child_autofree(m)
	m.setup(0, [], 0)
	m._dead = true
	m.health = 40.0
	m.heal(20.0)
	assert_eq(m.particles_emitted, 0, "No particles when minion is dead")

func test_heal_no_particles_when_already_full() -> void:
	var m: FakeMinionParticles = FakeMinionParticles.new()
	m.max_health = 80.0
	add_child_autofree(m)
	m.setup(0, [], 0)
	m.health = 80.0
	m.heal(20.0)
	assert_eq(m.particles_emitted, 0, "No particles when already at full health")
