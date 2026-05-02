extends GutTest
## Tests for MinionSpawner._apply_type_bonuses() and _apply_tier_model().
## These methods mutate minion stat exports based on Supporter skill tier passives
## before add_child is called. All Tier 1 — no network or scene tree needed.

const MinionSpawnerScript := preload("res://scripts/MinionSpawner.gd")

const SUP_ID := 42
const TEAM   := 0

## Fake minion node with declared properties so Node.get()/set() works correctly.
class FakeMinion extends Node:
	var max_health:    float = 60.0
	var attack_damage: float = 8.0
	var shoot_range:   float = 10.0
	var detect_range:  float = 12.0
	var heal_amount:   float = 10.0
	var heal_radius:   float = 8.0
	var _spawn_blue_char: String = ""
	var _spawn_red_char:  String = ""

## Fake cannon minion with .tscn-matching defaults.
class FakeCannonMinion extends Node:
	var max_health:    float = 40.0
	var attack_damage: float = 40.0
	var shoot_range:   float = 25.0
	var detect_range:  float = 28.0
	var _spawn_blue_char: String = ""
	var _spawn_red_char:  String = ""

## Fake healer minion with .tscn-matching defaults.
class FakeHealerMinion extends Node:
	var max_health:    float = 60.0
	var attack_damage: float = 3.0
	var heal_amount:   float = 10.0
	var heal_radius:   float = 8.0
	var _spawn_blue_char: String = ""
	var _spawn_red_char:  String = ""

var _spawner: Node = null

func before_each() -> void:
	SkillTree.clear_all()
	LevelSystem.clear_all()
	LobbyManager.players.clear()
	# Register a Supporter peer on team 0 so get_supporter_peer(0) returns SUP_ID.
	LobbyManager.players[SUP_ID] = {"name": "sup", "team": TEAM, "role": 1}
	SkillTree.register_peer(SUP_ID, "Supporter")
	_spawner = Node.new()
	_spawner.set_script(MinionSpawnerScript)
	add_child_autofree(_spawner)

func after_each() -> void:
	SkillTree.clear_all()
	LevelSystem.clear_all()
	LobbyManager.players.clear()

# ─── _apply_type_bonuses: no supporter ────────────────────────────────────────

func test_no_bonus_when_sup_zero() -> void:
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "basic", 0)
	assert_almost_eq(m.max_health, 60.0, 0.01,
		"max_health must be unchanged when sup == 0")

func test_no_bonus_when_sup_negative() -> void:
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "basic", -1)
	assert_almost_eq(m.max_health, 60.0, 0.01,
		"max_health must be unchanged when sup < 0")

# ─── _apply_type_bonuses: basic ───────────────────────────────────────────────

func test_basic_t1_hp_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "basic", SUP_ID)
	assert_almost_eq(m.max_health, 60.0 * 1.20, 0.01,
		"basic tier1 must apply +20%% HP")

func test_basic_t1_no_damage_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "basic", SUP_ID)
	assert_almost_eq(m.attack_damage, 8.0, 0.01,
		"basic tier1 must NOT scale attack_damage (tier2 gate)")

func test_basic_t2_hp_bonus_still_applied() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t2")
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "basic", SUP_ID)
	assert_almost_eq(m.max_health, 60.0 * 1.20, 0.01,
		"basic tier2 must still apply +20%% HP (tier1 gate also fires)")

func test_basic_t2_damage_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t2")
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "basic", SUP_ID)
	assert_almost_eq(m.attack_damage, 8.0 * 1.20, 0.01,
		"basic tier2 must apply +20%% attack_damage")

# ─── _apply_type_bonuses: cannon ──────────────────────────────────────────────

func test_cannon_t1_damage_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	var m := FakeCannonMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "cannon", SUP_ID)
	assert_almost_eq(m.attack_damage, 40.0 * 1.25, 0.01,
		"cannon tier1 must apply +25%% attack_damage")

func test_cannon_t1_no_range_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	var m := FakeCannonMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "cannon", SUP_ID)
	assert_almost_eq(m.shoot_range, 25.0, 0.01,
		"cannon tier1 must NOT scale shoot_range (tier2 gate)")

func test_cannon_t2_range_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t2")
	var m := FakeCannonMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "cannon", SUP_ID)
	assert_almost_eq(m.shoot_range, 25.0 * 1.30, 0.01,
		"cannon tier2 must apply +30%% shoot_range")

func test_cannon_t2_detect_exceeds_shoot() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t2")
	var m := FakeCannonMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "cannon", SUP_ID)
	var expected_detect: float = m.shoot_range * 1.12
	assert_almost_eq(m.detect_range, expected_detect, 0.01,
		"cannon tier2 detect_range must be shoot_range * 1.12")
	assert_true(m.detect_range > m.shoot_range,
		"detect_range must exceed shoot_range after cannon tier2")

# ─── _apply_type_bonuses: healer ──────────────────────────────────────────────

func test_healer_t1_heal_amount_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	var m := FakeHealerMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "healer", SUP_ID)
	assert_almost_eq(m.heal_amount, 10.0 + 5.0, 0.01,
		"healer tier1 must add +5 to heal_amount")

func test_healer_t1_no_radius_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	var m := FakeHealerMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "healer", SUP_ID)
	assert_almost_eq(m.heal_radius, 8.0, 0.01,
		"healer tier1 must NOT expand heal_radius (tier2 gate)")

func test_healer_t2_radius_bonus() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t2")
	var m := FakeHealerMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "healer", SUP_ID)
	assert_almost_eq(m.heal_radius, 8.0 + 4.0, 0.01,
		"healer tier2 must add +4 to heal_radius")

func test_healer_t2_heal_amount_still_applied() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t2")
	var m := FakeHealerMinion.new()
	add_child_autofree(m)
	_spawner._apply_type_bonuses(m, "healer", SUP_ID)
	assert_almost_eq(m.heal_amount, 10.0 + 5.0, 0.01,
		"healer tier2 must still apply +5 heal_amount (tier1 gate also fires)")

func test_unknown_type_no_crash() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	var m := FakeMinion.new()
	add_child_autofree(m)
	# Must not crash; no stats should change.
	_spawner._apply_type_bonuses(m, "bogus", SUP_ID)
	assert_almost_eq(m.max_health, 60.0, 0.01,
		"unknown mtype must not mutate stats")

# ─── _apply_tier_model: basic ─────────────────────────────────────────────────

func test_basic_tier0_char() -> void:
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "basic", 0)
	assert_eq(m._spawn_blue_char, "j", "basic tier0 must use char 'j'")
	assert_eq(m._spawn_red_char,  "j")

func test_basic_tier1_char() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "basic", SUP_ID)
	assert_eq(m._spawn_blue_char, "m", "basic tier1 must use char 'm'")

func test_basic_tier2_char() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t2")
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "basic", SUP_ID)
	assert_eq(m._spawn_blue_char, "r", "basic tier2 must use char 'r'")

# ─── _apply_tier_model: cannon ────────────────────────────────────────────────

func test_cannon_tier0_char() -> void:
	var m := FakeCannonMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "cannon", 0)
	assert_eq(m._spawn_blue_char, "d", "cannon tier0 must use char 'd'")

func test_cannon_tier1_char() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	var m := FakeCannonMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "cannon", SUP_ID)
	assert_eq(m._spawn_blue_char, "g", "cannon tier1 must use char 'g'")

func test_cannon_tier2_char() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t2")
	var m := FakeCannonMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "cannon", SUP_ID)
	assert_eq(m._spawn_blue_char, "h", "cannon tier2 must use char 'h'")

# ─── _apply_tier_model: healer ────────────────────────────────────────────────

func test_healer_tier0_char() -> void:
	var m := FakeHealerMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "healer", 0)
	assert_eq(m._spawn_blue_char, "i", "healer tier0 must use char 'i'")

func test_healer_tier1_char() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	var m := FakeHealerMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "healer", SUP_ID)
	assert_eq(m._spawn_blue_char, "n", "healer tier1 must use char 'n'")

func test_healer_tier2_char() -> void:
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t2")
	var m := FakeHealerMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "healer", SUP_ID)
	assert_eq(m._spawn_blue_char, "q", "healer tier2 must use char 'q'")

# ─── _apply_tier_model: edge cases ───────────────────────────────────────────

func test_no_supporter_gives_tier0_basic() -> void:
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "basic", 0)
	assert_eq(m._spawn_blue_char, "j",
		"no supporter must always produce tier0 char")

func test_tier_clamped_at_2() -> void:
	# Manually inject an impossible tier_sum via extra unlocks —
	# simulate by calling with a sup that has both t1 and t2 unlocked
	# then verify the char is still the tier2 char (clampi cap).
	# Since max real tier_sum == 2.0, we verify clamp holds by
	# checking that tier2 char == tier2 char (no out-of-bounds crash).
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t2")
	var m := FakeMinion.new()
	add_child_autofree(m)
	_spawner._apply_tier_model(m, "basic", SUP_ID)
	# tier_sum == 2.0 → clampi(2,0,2) == 2 → BASIC_CHARS[2] == "r"
	assert_eq(m._spawn_blue_char, "r",
		"tier_sum at max (2) must clamp to index 2 without crash")
