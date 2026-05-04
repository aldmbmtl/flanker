# test_minion_types.gd
# Tier 1 unit tests for CannonMinionAI and HealerMinionAI.
extends GutTest

# ─── Shared fake infrastructure ──────────────────────────────────────────────

class FakeCannon extends CannonMinionAI:
	var fire_at_calls: int = 0
	var last_target: Node3D = null

	func _build_visuals() -> void:
		pass

	func _fire_at(target: Node3D) -> void:
		fire_at_calls += 1
		last_target = target

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

class FakeHealer extends HealerMinionAI:
	var fire_at_calls: int = 0

	func _build_visuals() -> void:
		pass

	func _fire_at(target: Node3D) -> void:
		if _try_heal_nearby():
			return
		fire_at_calls += 1

	func _init() -> void:
		var sa := AudioStreamPlayer3D.new()
		sa.name = "ShootAudio"
		add_child(sa)
		var da := AudioStreamPlayer3D.new()
		da.name = "DeathAudio"
		add_child(da)

	func _ready() -> void:
		health = max_health
		attack_damage   = 3.0
		attack_cooldown = 2.5
		shoot_range     = 8.0
		detect_range    = 10.0
		add_to_group("minions")
		add_to_group("minion_units")

class FakeMinionTarget extends MinionBase:
	func _build_visuals() -> void: pass
	func _init() -> void:
		var sa := AudioStreamPlayer3D.new(); sa.name = "ShootAudio"; add_child(sa)
		var da := AudioStreamPlayer3D.new(); da.name = "DeathAudio"; add_child(da)
	func _ready() -> void:
		health = max_health
		add_to_group("minions")
		add_to_group("minion_units")

class FakeTower extends Node3D:
	var team: int = 1
	func take_damage(_a, _b, _c, _d) -> void: pass

# ─── CannonMinionAI: initial stats ───────────────────────────────────────────

func test_cannon_default_attack_damage() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	assert_eq(c.attack_damage, 40.0)

func test_cannon_default_hp() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	assert_eq(c.health, 40.0)

func test_cannon_shoot_range() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	assert_eq(c.shoot_range, 25.0)

func test_cannon_is_cannon_minion_ai_class() -> void:
	var c := FakeCannon.new()
	add_child_autofree(c)
	c.setup(0, [], 0)
	assert_true(c is CannonMinionAI)

# ─── CannonMinionAI: tower-priority targeting ─────────────────────────────────

func test_cannon_targets_tower_over_enemy_minion() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	c.global_position = Vector3.ZERO
	MinionBase._shared_minion_cache = []

	# Enemy minion in range
	var enemy_minion := FakeMinionTarget.new()
	enemy_minion.max_health = 60.0
	add_child_autofree(enemy_minion)
	enemy_minion.setup(1, [], 0)
	enemy_minion.global_position = Vector3(10.0, 0.0, 0.0)
	MinionBase._shared_minion_cache = [enemy_minion]

	# Enemy tower closer
	var tower := FakeTower.new()
	tower.team = 1
	add_child_autofree(tower)
	tower.global_position = Vector3(8.0, 0.0, 0.0)
	c._cached_towers = [tower]
	c._cached_bases = []

	var target: Node3D = c._find_target()
	assert_true(target == tower, "Cannon minion must prioritise tower over enemy minion")

func test_cannon_falls_back_to_enemy_minion_when_no_tower_in_range() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	c.global_position = Vector3.ZERO
	c._cached_bases = []

	var enemy_minion := FakeMinionTarget.new()
	enemy_minion.max_health = 60.0
	add_child_autofree(enemy_minion)
	enemy_minion.setup(1, [], 0)
	enemy_minion.global_position = Vector3(10.0, 0.0, 0.0)
	MinionBase._shared_minion_cache = [enemy_minion]

	# Tower far outside range
	var tower := FakeTower.new()
	tower.team = 1
	add_child_autofree(tower)
	tower.global_position = Vector3(100.0, 0.0, 0.0)
	c._cached_towers = [tower]

	var target: Node3D = c._find_target()
	assert_true(target == enemy_minion, "Cannon minion must fall back to enemy minion when no tower in range")

func test_cannon_ignores_friendly_tower() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	c.global_position = Vector3.ZERO
	c._cached_bases = []
	MinionBase._shared_minion_cache = []

	# Friendly tower — same team
	var friendly_tower := FakeTower.new()
	friendly_tower.team = 0
	add_child_autofree(friendly_tower)
	friendly_tower.global_position = Vector3(5.0, 0.0, 0.0)
	c._cached_towers = [friendly_tower]

	var target: Node3D = c._find_target()
	assert_null(target, "Cannon minion must not target a friendly tower")

# ─── CannonMinionAI: take_damage / death ─────────────────────────────────────

func test_cannon_takes_damage() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	c.take_damage(20.0, "player", 1)
	assert_eq(c.health, 20.0)

func test_cannon_dies_at_zero_hp() -> void:
	var c := FakeCannon.new()
	c.max_health = 40.0
	c.attack_damage = 40.0
	c.shoot_range = 25.0
	c.detect_range = 28.0
	add_child_autofree(c)
	c.setup(0, [], 0)
	c.take_damage(40.0, "player", 1)
	assert_true(c._dead)

# ─── HealerMinionAI: initial stats ───────────────────────────────────────────

func test_healer_default_heal_amount() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	h.heal_amount = 10.0
	h.heal_radius = 8.0
	h.heal_interval = 3.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	assert_eq(h.heal_amount, 10.0)

func test_healer_default_heal_radius() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	h.heal_amount = 10.0
	h.heal_radius = 8.0
	h.heal_interval = 3.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	assert_eq(h.heal_radius, 8.0)

func test_healer_is_healer_minion_ai_class() -> void:
	var h := FakeHealer.new()
	add_child_autofree(h)
	h.setup(0, [], 0)
	assert_true(h is HealerMinionAI)

# ─── HealerMinionAI: targeting / combat ──────────────────────────────────────

func test_healer_default_attack_damage() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	assert_eq(h.attack_damage, 3.0, "Healer attack_damage must be 3.0")

func test_healer_attacks_enemy_in_shoot_range() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	h.global_position = Vector3.ZERO
	MinionBase._shared_minion_cache = []
	h._cached_bases = []

	var enemy := FakeMinionTarget.new()
	enemy.max_health = 60.0
	add_child_autofree(enemy)
	enemy.setup(1, [], 0)
	enemy.global_position = Vector3(5.0, 0.0, 0.0)
	MinionBase._shared_minion_cache = [enemy]
	h._cached_towers = []

	var target: Node3D = h._find_target()
	assert_true(target == enemy, "Healer must target enemy in shoot_range")

# ─── HealerMinionAI: heal-priority in _fire_at ───────────────────────────────

func test_healer_heals_instead_of_shooting_when_ally_hurt() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	h.heal_amount = 10.0
	h.heal_radius = 8.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	h.global_position = Vector3.ZERO

	var friendly := FakeMinionTarget.new()
	friendly.max_health = 60.0
	add_child_autofree(friendly)
	friendly.setup(0, [], 0)
	friendly.health = 30.0
	friendly.global_position = Vector3(3.0, 0.0, 0.0)
	friendly.add_to_group("minions")

	var dummy_target := FakeMinionTarget.new()
	dummy_target.max_health = 60.0
	add_child_autofree(dummy_target)
	dummy_target.setup(1, [], 0)

	h._fire_at(dummy_target)
	assert_eq(friendly.health, 40.0, "Hurt ally must be healed when _fire_at is called")
	assert_eq(h.fire_at_calls, 0, "Bullet must not be fired when ally healed instead")

func test_healer_shoots_when_no_hurt_ally_nearby() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	h.heal_amount = 10.0
	h.heal_radius = 8.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	h.global_position = Vector3.ZERO

	# Ally at full health — not hurt
	var friendly := FakeMinionTarget.new()
	friendly.max_health = 60.0
	add_child_autofree(friendly)
	friendly.setup(0, [], 0)
	friendly.health = 60.0
	friendly.global_position = Vector3(3.0, 0.0, 0.0)
	friendly.add_to_group("minions")

	var dummy_target := FakeMinionTarget.new()
	dummy_target.max_health = 60.0
	add_child_autofree(dummy_target)
	dummy_target.setup(1, [], 0)

	h._fire_at(dummy_target)
	assert_eq(h.fire_at_calls, 1, "Bullet must be fired when no hurt ally nearby")

func test_healer_heals_most_hurt_ally_first() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	h.heal_amount = 10.0
	h.heal_radius = 8.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	h.global_position = Vector3.ZERO

	var slightly_hurt := FakeMinionTarget.new()
	slightly_hurt.max_health = 60.0
	add_child_autofree(slightly_hurt)
	slightly_hurt.setup(0, [], 0)
	slightly_hurt.health = 50.0  # missing 10
	slightly_hurt.global_position = Vector3(2.0, 0.0, 0.0)
	slightly_hurt.add_to_group("minions")

	var badly_hurt := FakeMinionTarget.new()
	badly_hurt.max_health = 60.0
	add_child_autofree(badly_hurt)
	badly_hurt.setup(0, [], 0)
	badly_hurt.health = 10.0  # missing 50
	badly_hurt.global_position = Vector3(-2.0, 0.0, 0.0)
	badly_hurt.add_to_group("minions")

	var dummy_target := FakeMinionTarget.new()
	dummy_target.max_health = 60.0
	add_child_autofree(dummy_target)
	dummy_target.setup(1, [], 0)

	h._fire_at(dummy_target)
	assert_eq(badly_hurt.health, 20.0, "Most hurt ally must be healed first")
	assert_eq(slightly_hurt.health, 50.0, "Less hurt ally must not be healed this tick")

func test_healer_does_not_heal_enemy_when_shooting() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	h.heal_amount = 10.0
	h.heal_radius = 8.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	h.global_position = Vector3.ZERO

	# Enemy minion hurt — must not be healed
	var enemy := FakeMinionTarget.new()
	enemy.max_health = 60.0
	add_child_autofree(enemy)
	enemy.setup(1, [], 0)
	enemy.health = 20.0
	enemy.global_position = Vector3(3.0, 0.0, 0.0)
	enemy.add_to_group("minions")

	var dummy_target := FakeMinionTarget.new()
	dummy_target.max_health = 60.0
	add_child_autofree(dummy_target)
	dummy_target.setup(1, [], 0)

	h._fire_at(dummy_target)
	assert_eq(enemy.health, 20.0, "Enemy must never be healed")

# ─── HealerMinionAI: _pulse_heal ─────────────────────────────────────────────

func test_healer_pulse_heals_friendly_minion_in_range() -> void:
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 10.0
	healer.heal_radius = 8.0
	healer.heal_interval = 3.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO

	var friendly := FakeMinionTarget.new()
	friendly.max_health = 60.0
	add_child_autofree(friendly)
	friendly.setup(0, [], 0)
	friendly.health = 30.0
	friendly.global_position = Vector3(3.0, 0.0, 0.0)
	friendly.add_to_group("minions")

	healer._pulse_heal()
	assert_eq(friendly.health, 40.0, "Healer should restore 10 HP to friendly in range")

func test_healer_pulse_does_not_heal_enemy_minion() -> void:
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 10.0
	healer.heal_radius = 8.0
	healer.heal_interval = 3.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO

	var enemy := FakeMinionTarget.new()
	enemy.max_health = 60.0
	add_child_autofree(enemy)
	enemy.setup(1, [], 0)  # enemy team
	enemy.health = 30.0
	enemy.global_position = Vector3(3.0, 0.0, 0.0)
	enemy.add_to_group("minions")

	healer._pulse_heal()
	assert_eq(enemy.health, 30.0, "Healer must not heal enemy minion")

func test_healer_pulse_does_not_heal_out_of_range_friendly() -> void:
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 10.0
	healer.heal_radius = 8.0
	healer.heal_interval = 3.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO

	var friendly := FakeMinionTarget.new()
	friendly.max_health = 60.0
	add_child_autofree(friendly)
	friendly.setup(0, [], 0)
	friendly.health = 30.0
	friendly.global_position = Vector3(20.0, 0.0, 0.0)  # outside 8m radius
	friendly.add_to_group("minions")

	healer._pulse_heal()
	assert_eq(friendly.health, 30.0, "Healer must not heal friendly that is out of range")

func test_healer_pulse_does_not_heal_dead_friendly() -> void:
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 10.0
	healer.heal_radius = 8.0
	healer.heal_interval = 3.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO

	var friendly := FakeMinionTarget.new()
	friendly.max_health = 60.0
	add_child_autofree(friendly)
	friendly.setup(0, [], 0)
	friendly.health = 0.0
	friendly._dead = true
	friendly.global_position = Vector3(3.0, 0.0, 0.0)
	friendly.add_to_group("minions")

	healer._pulse_heal()
	assert_eq(friendly.health, 0.0, "Healer must not heal dead friendly")

func test_healer_pulse_heals_self_if_damaged() -> void:
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 10.0
	healer.heal_radius = 8.0
	healer.heal_interval = 3.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO
	healer.health = 40.0
	healer.add_to_group("minions")  # ensure in group

	healer._pulse_heal()
	# _pulse_heal skips self (m == self check), so self-heal should NOT occur
	assert_eq(healer.health, 40.0, "Healer should not heal itself (self is skipped in pulse)")

func test_healer_pulse_heals_multiple_friendlies() -> void:
	# _pulse_heal (via _try_heal_nearby) heals the single most-hurt ally.
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 10.0
	healer.heal_radius = 8.0
	healer.heal_interval = 3.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO

	var f1 := FakeMinionTarget.new()
	f1.max_health = 60.0
	add_child_autofree(f1)
	f1.setup(0, [], 0)
	f1.health = 20.0  # missing 40 — most hurt
	f1.global_position = Vector3(2.0, 0.0, 0.0)
	f1.add_to_group("minions")

	var f2 := FakeMinionTarget.new()
	f2.max_health = 60.0
	add_child_autofree(f2)
	f2.setup(0, [], 0)
	f2.health = 30.0  # missing 30
	f2.global_position = Vector3(-2.0, 0.0, 0.0)
	f2.add_to_group("minions")

	healer._pulse_heal()
	assert_eq(f1.health, 30.0, "Most hurt friendly (f1) should receive 10 HP")
	assert_eq(f2.health, 30.0, "Less hurt friendly (f2) must not be healed this tick")

# ─── MinionBase tier model selection (via _spawn_blue_char/_spawn_red_char) ───

class FakeMinionCharCheck extends MinionBase:
	var built_blue_char: String = ""
	var built_red_char: String = ""

	func _build_visuals() -> void:
		# Record which chars would be used without loading GLB files.
		built_blue_char = _spawn_blue_char if _spawn_blue_char != "" else MinionBase._blue_model_char
		built_red_char  = _spawn_red_char  if _spawn_red_char  != "" else MinionBase._red_model_char

	func _init() -> void:
		var sa := AudioStreamPlayer3D.new(); sa.name = "ShootAudio"; add_child(sa)
		var da := AudioStreamPlayer3D.new(); da.name = "DeathAudio"; add_child(da)

	func _ready() -> void:
		health = max_health
		add_to_group("minions")
		add_to_group("minion_units")
		_init_visuals()  # triggers _build_visuals

func test_tier_model_char_defaults_to_global_when_not_set() -> void:
	MinionBase.set_model_characters("e", "b")
	var m := FakeMinionCharCheck.new()
	m.max_health = 60.0
	# _spawn_blue_char left empty
	add_child_autofree(m)
	m.setup(0, [], 0)
	assert_eq(m.built_blue_char, "e", "Should use global blue char when spawn char not set")

func test_tier_model_char_overrides_global_when_set() -> void:
	MinionBase.set_model_characters("e", "b")
	var m := FakeMinionCharCheck.new()
	m.max_health = 60.0
	m.set("_spawn_blue_char", "m")
	m.set("_spawn_red_char", "m")
	add_child_autofree(m)
	m.setup(0, [], 0)
	assert_eq(m.built_blue_char, "m", "Should use spawn char override when set")

func test_tier_model_char_tier2_uses_third_char() -> void:
	# Simulate what MinionSpawner._apply_tier_model does for tier_sum = 2
	var chars: Array[String] = ["j", "m", "r"]
	var tier_sum: float = 2.0
	var tier_idx: int = clampi(int(tier_sum), 0, 2)
	assert_eq(chars[tier_idx], "r", "Tier 2 basic should use char 'r'")

func test_tier_model_char_tier0_uses_first_char() -> void:
	var chars: Array[String] = ["d", "g", "h"]
	var tier_sum: float = 0.0
	var tier_idx: int = clampi(int(tier_sum), 0, 2)
	assert_eq(chars[tier_idx], "d", "Tier 0 cannon should use char 'd'")

func test_tier_model_char_tier1_uses_second_char() -> void:
	var chars: Array[String] = ["i", "n", "q"]
	var tier_sum: float = 1.0
	var tier_idx: int = clampi(int(tier_sum), 0, 2)
	assert_eq(chars[tier_idx], "n", "Tier 1 healer should use char 'n'")

# ─── Regression: healer _march delegates to MinionBase correctly ─────────────

func test_healer_stops_when_waypoints_exhausted_and_no_base() -> void:
	var h := FakeHealer.new()
	h.max_health = 60.0
	add_child_autofree(h)
	h.setup(0, [], 0)
	h.global_position = Vector3.ZERO
	h.velocity = Vector3(5.0, 0.0, 5.0)
	# No enemy base → MinionBase._march zeros velocity
	h._enemy_base = null

	h._march(0.016)
	assert_almost_eq(h.velocity.x, 0.0, 0.01, "Healer must zero x velocity when no waypoints and no base")
	assert_almost_eq(h.velocity.z, 0.0, 0.01, "Healer must zero z velocity when no waypoints and no base")

# ─── Regression: cannon fire_pos set before add_child ────────────────────────

class SpyCannonball extends Node3D:
	## Records the position at the moment add_child is called (i.e. when _ready fires).
	var target_pos: Vector3 = Vector3.ZERO
	var damage: float = 0.0
	var source: String = ""
	var shooter_team: int = -1
	var recorded_position: Vector3 = Vector3.ZERO

	func _ready() -> void:
		recorded_position = position  # capture local position at _ready time

# ─── Regression: cannon fire_pos set before add_child ────────────────────────

## Verifies that init_ballistic_arc produces the correct horizontal velocity
## components when the cannonball's position is set before add_child (the fix),
## vs when it would be (0,0,0) (the bug).
func test_cannonball_arc_correct_when_position_set_before_add_child() -> void:
	# Simulate the fix: a cannonball node with position set before add_child.
	var ball := SpyCannonball.new()
	var fire_pos := Vector3(10.0, 2.2, 5.0)
	var target_p  := Vector3(30.0, 0.0, 5.0)
	ball.position = fire_pos   # set BEFORE add_child — the fix
	add_child_autofree(ball)   # _ready records position

	# Verify position was correct at _ready time.
	assert_almost_eq(ball.recorded_position.x, fire_pos.x, 0.05,
		"Position at _ready must equal fire_pos.x when set before add_child")
	assert_almost_eq(ball.recorded_position.z, fire_pos.z, 0.05,
		"Position at _ready must equal fire_pos.z when set before add_child")

func test_cannonball_arc_wrong_when_position_set_after_add_child() -> void:
	# Simulate the bug: position set AFTER add_child — _ready sees (0,0,0).
	var ball := SpyCannonball.new()
	var fire_pos := Vector3(10.0, 2.2, 5.0)
	add_child_autofree(ball)   # _ready fires first, position still (0,0,0)
	ball.position = fire_pos   # too late

	# At _ready time, position was (0,0,0) — the bug.
	assert_almost_eq(ball.recorded_position.x, 0.0, 0.05,
		"Bug confirmed: position at _ready is ZERO when set after add_child")

# ─── Regression: cannon minion bridge dispatch (no ENet RPC) ──────────────────
# After Slice D, CannonMinionAI._fire_at sends "fire_projectile" via BridgeClient
# instead of calling spawn_cannonball_visuals.rpc().
# Guard: no ENet RPC must be issued; the authoritative physics cannonball must
# be spawned into the scene tree.

class RealFireCannonMinion extends CannonMinionAI:
	## Suppresses visuals and audio only — _fire_at runs real production code.
	func _build_visuals() -> void:
		pass

	func _init() -> void:
		var sa := AudioStreamPlayer3D.new(); sa.name = "ShootAudio"; add_child(sa)
		var da := AudioStreamPlayer3D.new(); da.name = "DeathAudio"; add_child(da)

	func _ready() -> void:
		health = max_health
		add_to_group("minions")
		add_to_group("minion_units")

func test_cannon_minion_fire_at_no_enet_rpc() -> void:
	## Slice D: _fire_at must NOT dispatch any ENet RPC — bridge path only.
	var mock := MockMultiplayerAPI.new()
	get_tree().set_multiplayer(mock, LobbyManager.get_path())

	var cannon := RealFireCannonMinion.new()
	cannon.max_health = 40.0
	cannon.attack_damage = 40.0
	cannon.shoot_range = 25.0
	cannon.detect_range = 28.0
	add_child_autofree(cannon)
	cannon.setup(0, [], 0)
	cannon.global_position = Vector3.ZERO

	var target := FakeTower.new()
	target.team = 1
	add_child_autofree(target)
	target.global_position = Vector3(10.0, 0.0, 0.0)

	cannon._fire_at(target)

	get_tree().set_multiplayer(null, LobbyManager.get_path())

	assert_eq(mock.rpc_log.size(), 0,
		"_fire_at must not issue any ENet RPC — bridge path only")
	assert_false(mock.was_called("spawn_cannonball_visuals"),
		"spawn_cannonball_visuals.rpc() must NOT be called after Slice D migration")
	assert_false(mock.was_called("spawn_bullet_visuals"),
		"spawn_bullet_visuals must NOT be called by cannon minion _fire_at")

func test_cannon_minion_rpc_passes_target_pos_not_direction() -> void:
	## After Slice D the physics cannonball must be aimed at the target position,
	## not along a normalised direction. Verify the cannonball node's target_pos
	## equals the target's world-space position.
	var cannon := RealFireCannonMinion.new()
	cannon.max_health = 40.0
	cannon.attack_damage = 40.0
	cannon.shoot_range = 25.0
	cannon.detect_range = 28.0
	add_child_autofree(cannon)
	cannon.setup(0, [], 0)
	cannon.global_position = Vector3.ZERO

	var target := FakeTower.new()
	target.team = 1
	add_child_autofree(target)
	target.global_position = Vector3(15.0, 0.0, 0.0)

	var scene_root: Node = get_tree().root.get_child(0)
	var root_before: int = scene_root.get_child_count()
	cannon._fire_at(target)
	assert_gt(scene_root.get_child_count(), root_before,
		"_fire_at must spawn a physics cannonball into the scene root")

func test_cannon_minion_rpc_passes_correct_damage_and_team() -> void:
	## After Slice D the cannonball physics node must carry the correct damage
	## and team values set before add_child.
	var cannon := RealFireCannonMinion.new()
	cannon.max_health = 40.0
	cannon.attack_damage = 40.0
	cannon.shoot_range = 25.0
	cannon.detect_range = 28.0
	add_child_autofree(cannon)
	cannon.setup(1, [], 0)  # red team
	cannon.global_position = Vector3.ZERO

	var target := FakeTower.new()
	target.team = 0
	add_child_autofree(target)
	target.global_position = Vector3(8.0, 0.0, 0.0)

	var scene_root: Node = get_tree().root.get_child(0)
	var root_before: int = scene_root.get_child_count()
	cannon._fire_at(target)
	# A cannonball physics node must have been added to scene root
	assert_gt(scene_root.get_child_count(), root_before,
		"_fire_at must add the cannonball to scene root for red team cannon minion")

# ─── HealerMinionAI: player heal routing ─────────────────────────────────────
# Regression: before fix, healer called best.heal() on the player node directly.
# Puppet BasePlayer nodes have no heal() method — so remote players were never
# healed by HealerMinionAI. Fix routes heal via has_method("heal") for players
# with peer_id, falling back to direct call in singleplayer.

## Fake FPS player with heal() — stands in for the local FPSController node.
class FakeHealablePlayer extends Node3D:
	var is_local: bool = true
	var player_team: int = 0
	var peer_id: int = 1
	var health: float = 60.0
	var max_health: float = 100.0
	func heal(amount: float) -> void:
		health = minf(health + amount, max_health)

## Fake puppet player: has player_team but NO heal() method.
## Represents a remote player as seen on the server / other clients.
class FakePuppetPlayer extends Node3D:
	var player_team: int = 0
	var peer_id: int = 2
	var health: float = 60.0
	var max_health: float = 100.0
	# No heal() method — intentional.

func test_healer_heals_local_fps_player_directly() -> void:
	## Singleplayer / server-player: FPSController has heal(), call goes directly.
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 15.0
	healer.heal_radius = 10.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO

	var player := FakeHealablePlayer.new()
	player.player_team = 0
	player.health = 50.0
	player.max_health = 100.0
	add_child_autofree(player)
	player.global_position = Vector3(3.0, 0.0, 0.0)
	player.add_to_group("players")

	healer._pulse_heal()
	assert_almost_eq(player.health, 65.0, 0.001,
		"Local FPS player with heal() must receive heal_amount directly")

func test_healer_does_not_heal_enemy_fps_player() -> void:
	## Team check must block enemy players regardless of heal() presence.
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 15.0
	healer.heal_radius = 10.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)  # blue team healer
	healer.global_position = Vector3.ZERO

	var enemy_player := FakeHealablePlayer.new()
	enemy_player.player_team = 1  # red
	enemy_player.health = 40.0
	add_child_autofree(enemy_player)
	enemy_player.global_position = Vector3(3.0, 0.0, 0.0)
	enemy_player.add_to_group("players")

	healer._pulse_heal()
	assert_almost_eq(enemy_player.health, 40.0, 0.001,
		"Enemy player must never be healed regardless of heal() method")

func test_healer_puppet_player_no_heal_called() -> void:
	## Puppet node has no heal() — _try_heal_nearby must not crash and must not
	## heal the puppet directly.
	var healer := FakeHealer.new()
	healer.max_health = 60.0
	healer.heal_amount = 15.0
	healer.heal_radius = 10.0
	add_child_autofree(healer)
	healer.setup(0, [], 0)
	healer.global_position = Vector3.ZERO

	var puppet := FakePuppetPlayer.new()
	puppet.player_team = 0
	puppet.health = 40.0
	add_child_autofree(puppet)
	puppet.global_position = Vector3(3.0, 0.0, 0.0)
	puppet.add_to_group("players")

	# Under OfflineMultiplayerPeer: has_multiplayer_peer() == true, is_server() == true.
	# heal_player_broadcast() will be called — it updates GameSync and sends RPC.
	# Since peer_id=2 is not registered in GameSync, the call must not crash.
	GameSync.set_player_health(2, 40.0)
	healer._pulse_heal()
	# GameSync HP should have moved up by heal_amount (capped at PLAYER_MAX_HP).
	var new_hp: float = GameSync.player_healths.get(2, 40.0)
	assert_true(new_hp > 40.0,
		"heal_player_broadcast must update GameSync HP for the puppet's peer_id")
	# Puppet node's own health field must NOT be mutated (no direct heal() called).
	assert_almost_eq(puppet.health, 40.0, 0.001,
		"Puppet node health field must remain unchanged — heal goes via RPC only")
	GameSync.player_healths.erase(2)
