# test_level_system.gd
# Tier 1 — unit tests for LevelSystem autoload.
# All logic runs server-authoritative (OfflineMultiplayerPeer).
extends GutTest

const PEER_A := 10
const PEER_B := 20

func before_each() -> void:
	LevelSystem.clear_all()
	LevelSystem.register_peer(PEER_A)
	LevelSystem.register_peer(PEER_B)

# ── register_peer ─────────────────────────────────────────────────────────────

func test_register_peer_starts_at_level_1() -> void:
	assert_eq(LevelSystem.get_level(PEER_A), 1)

func test_register_peer_starts_at_zero_xp() -> void:
	assert_eq(LevelSystem.get_xp(PEER_A), 0)

func test_register_peer_starts_with_zero_points() -> void:
	assert_eq(LevelSystem.get_unspent_points(PEER_A), 0)

func test_register_peer_idempotent() -> void:
	LevelSystem.register_peer(PEER_A)  # second call
	assert_eq(LevelSystem.get_xp(PEER_A), 0, "Re-registering should not reset progress")

func test_peers_isolated() -> void:
	LevelSystem.award_xp(PEER_A, 50)
	assert_eq(LevelSystem.get_xp(PEER_B), 0, "XP awarded to A should not affect B")

# ── award_xp ──────────────────────────────────────────────────────────────────

func test_award_xp_increases_xp() -> void:
	LevelSystem.award_xp(PEER_A, 30)
	assert_eq(LevelSystem.get_xp(PEER_A), 30)

func test_award_xp_emits_xp_gained_signal() -> void:
	watch_signals(LevelSystem)
	LevelSystem.award_xp(PEER_A, 10)
	assert_signal_emitted(LevelSystem, "xp_gained")

func test_award_xp_triggers_level_up() -> void:
	# XP_PER_LEVEL[0] = 70 — award enough for level 1 → 2
	LevelSystem.award_xp(PEER_A, 70)
	assert_eq(LevelSystem.get_level(PEER_A), 2, "Should reach level 2 at 70 XP")

func test_award_xp_emits_level_up_signal() -> void:
	watch_signals(LevelSystem)
	LevelSystem.award_xp(PEER_A, 70)
	assert_signal_emitted(LevelSystem, "level_up")
	var params: Array = get_signal_parameters(LevelSystem, "level_up")
	assert_eq(params[1], 2)

func test_award_xp_awards_attribute_points_on_level_up() -> void:
	LevelSystem.award_xp(PEER_A, 70)  # level 2 = 1 point
	assert_eq(LevelSystem.get_unspent_points(PEER_A), 1)

func test_award_xp_multiple_level_ups() -> void:
	# Level 1→2: 70 XP, Level 2→3: 140 XP — award 210 total
	LevelSystem.award_xp(PEER_A, 210)
	assert_eq(LevelSystem.get_level(PEER_A), 3)

func test_award_xp_xp_carries_over_after_level_up() -> void:
	# Award 80 XP: 70 consumed for level-up, 10 carries over
	LevelSystem.award_xp(PEER_A, 80)
	assert_eq(LevelSystem.get_xp(PEER_A), 10, "Excess XP should carry over")

func test_award_xp_stops_at_max_level() -> void:
	# Burn through all levels
	LevelSystem.award_xp(PEER_A, 999999)
	assert_eq(LevelSystem.get_level(PEER_A), LevelSystem.MAX_LEVEL,
		"Level should cap at MAX_LEVEL")

func test_award_xp_no_gain_at_max_level() -> void:
	LevelSystem.award_xp(PEER_A, 999999)
	var xp_before: int = LevelSystem.get_xp(PEER_A)
	LevelSystem.award_xp(PEER_A, 100)
	assert_eq(LevelSystem.get_xp(PEER_A), xp_before, "No XP gain at max level")

# ── spend_point_local ─────────────────────────────────────────────────────────

func test_spend_point_deducts_unspent() -> void:
	LevelSystem.award_xp(PEER_A, 70)  # 1 unspent point
	LevelSystem.spend_point_local(PEER_A, "hp")
	assert_eq(LevelSystem.get_unspent_points(PEER_A), 0)

func test_spend_point_updates_attr() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "hp")
	var attrs: Dictionary = LevelSystem.get_attrs(PEER_A)
	assert_eq(attrs["hp"], 1)

func test_spend_point_emits_attribute_spent() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	watch_signals(LevelSystem)
	LevelSystem.spend_point_local(PEER_A, "hp")
	assert_signal_emitted(LevelSystem, "attribute_spent")

func test_spend_point_no_effect_when_zero_points() -> void:
	var attrs_before: Dictionary = LevelSystem.get_attrs(PEER_A)
	LevelSystem.spend_point_local(PEER_A, "hp")
	assert_eq(LevelSystem.get_attrs(PEER_A)["hp"], attrs_before["hp"],
		"No change without unspent points")

func test_spend_point_invalid_attr_ignored() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "nonexistent")
	assert_eq(LevelSystem.get_unspent_points(PEER_A), 1, "Invalid attr should not deduct points")

func test_spend_point_capped_at_attr_cap() -> void:
	# Award enough XP for ATTR_CAP + 1 points and try to spend all into hp
	LevelSystem.award_xp(PEER_A, 999999)
	for i in range(LevelSystem.ATTR_CAP + 5):
		LevelSystem.spend_point_local(PEER_A, "hp")
	var attrs: Dictionary = LevelSystem.get_attrs(PEER_A)
	assert_lte(attrs["hp"], LevelSystem.ATTR_CAP, "HP attribute must not exceed ATTR_CAP")

# ── stat bonus queries ────────────────────────────────────────────────────────

func test_get_bonus_hp_zero_before_spending() -> void:
	assert_eq(LevelSystem.get_bonus_hp(PEER_A), 0.0)

func test_get_bonus_hp_correct_after_spending() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "hp")
	assert_eq(LevelSystem.get_bonus_hp(PEER_A), LevelSystem.HP_PER_POINT)

func test_get_bonus_speed_zero_before_spending() -> void:
	assert_eq(LevelSystem.get_bonus_speed_mult(PEER_A), 0.0)

func test_get_bonus_damage_zero_before_spending() -> void:
	assert_eq(LevelSystem.get_bonus_damage_mult(PEER_A), 0.0)

# ── clear_peer ────────────────────────────────────────────────────────────────

func test_clear_peer_removes_all_data() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.clear_peer(PEER_A)
	assert_eq(LevelSystem.get_level(PEER_A), 1,
		"After clear, level falls back to default 1")
	assert_eq(LevelSystem.get_xp(PEER_A), 0)

func test_clear_peer_does_not_affect_other_peers() -> void:
	LevelSystem.award_xp(PEER_B, 70)
	LevelSystem.clear_peer(PEER_A)
	assert_eq(LevelSystem.get_level(PEER_B), 2, "Clearing A should not affect B")

# ── xp_for_next_level sanity ──────────────────────────────────────────────────

func test_xp_needed_increases_each_level() -> void:
	var prev: int = 0
	for lvl in range(1, LevelSystem.MAX_LEVEL):
		var needed: int = LevelSystem.get_xp_needed(PEER_A)
		LevelSystem.award_xp(PEER_A, needed)
		var new_needed: int = LevelSystem.get_xp_needed(PEER_A)
		if LevelSystem.get_level(PEER_A) < LevelSystem.MAX_LEVEL:
			assert_gte(new_needed, prev, "XP required should not decrease between levels")
		prev = new_needed

# ── stamina attribute ─────────────────────────────────────────────────────────

func test_get_bonus_stamina_zero_before_spending() -> void:
	assert_eq(LevelSystem.get_bonus_stamina(PEER_A), 0.0,
		"No stamina bonus before spending any points")

func test_get_bonus_stamina_correct_after_one_spend() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "stamina")
	assert_eq(LevelSystem.get_bonus_stamina(PEER_A), LevelSystem.STAMINA_PER_POINT,
		"Bonus should be exactly STAMINA_PER_POINT after 1 spend")

func test_stamina_attr_capped_at_attr_cap() -> void:
	LevelSystem.award_xp(PEER_A, 999999)
	for i in range(LevelSystem.ATTR_CAP + 5):
		LevelSystem.spend_point_local(PEER_A, "stamina")
	var attrs: Dictionary = LevelSystem.get_attrs(PEER_A)
	assert_lte(attrs["stamina"], LevelSystem.ATTR_CAP,
		"Stamina attribute must not exceed ATTR_CAP")

func test_stamina_spend_does_not_affect_other_attrs() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "stamina")
	var attrs: Dictionary = LevelSystem.get_attrs(PEER_A)
	assert_eq(attrs["hp"], 0, "hp unchanged after stamina spend")
	assert_eq(attrs["speed"], 0, "speed unchanged after stamina spend")
	assert_eq(attrs["damage"], 0, "damage unchanged after stamina spend")

func test_stamina_isolated_between_peers() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "stamina")
	assert_eq(LevelSystem.get_bonus_stamina(PEER_B), 0.0,
		"Peer B stamina unaffected by Peer A spend")

func test_stamina_attr_in_get_attrs() -> void:
	var attrs: Dictionary = LevelSystem.get_attrs(PEER_A)
	assert_true(attrs.has("stamina"), "get_attrs must include 'stamina' key")
	assert_eq(attrs["stamina"], 0, "stamina starts at 0")

# ── Supporter attributes: tower_hp, placement_range, tower_fire_rate ──────────

func test_get_bonus_tower_hp_mult_zero_before_spending() -> void:
	assert_eq(LevelSystem.get_bonus_tower_hp_mult(PEER_A), 0.0,
		"No tower_hp bonus before spending any points")

func test_get_bonus_tower_hp_mult_correct_after_one_spend() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "tower_hp")
	assert_almost_eq(LevelSystem.get_bonus_tower_hp_mult(PEER_A),
		LevelSystem.TOWER_HP_PER_POINT, 0.0001,
		"Bonus should be exactly TOWER_HP_PER_POINT after 1 spend")

func test_get_bonus_placement_range_mult_zero_before_spending() -> void:
	assert_eq(LevelSystem.get_bonus_placement_range_mult(PEER_A), 0.0,
		"No placement_range bonus before spending any points")

func test_get_bonus_placement_range_mult_correct_after_one_spend() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "placement_range")
	assert_almost_eq(LevelSystem.get_bonus_placement_range_mult(PEER_A),
		LevelSystem.PLACEMENT_RANGE_PER_POINT, 0.0001,
		"Bonus should be exactly PLACEMENT_RANGE_PER_POINT after 1 spend")

func test_get_bonus_tower_fire_rate_mult_zero_before_spending() -> void:
	assert_eq(LevelSystem.get_bonus_tower_fire_rate_mult(PEER_A), 0.0,
		"No tower_fire_rate bonus before spending any points")

func test_get_bonus_tower_fire_rate_mult_correct_after_one_spend() -> void:
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "tower_fire_rate")
	assert_almost_eq(LevelSystem.get_bonus_tower_fire_rate_mult(PEER_A),
		LevelSystem.TOWER_FIRE_RATE_PER_POINT, 0.0001,
		"Bonus should be exactly TOWER_FIRE_RATE_PER_POINT after 1 spend")

# ── Role gate tests ───────────────────────────────────────────────────────────

func test_fighter_cannot_spend_supporter_attr() -> void:
	SkillTree.clear_peer(PEER_A)
	SkillTree.register_peer(PEER_A, "Fighter")
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "tower_fire_rate")
	var attrs: Dictionary = LevelSystem.get_attrs(PEER_A)
	assert_eq(attrs.get("tower_fire_rate", 0), 0,
		"Fighter spending tower_fire_rate must be a no-op")
	SkillTree.clear_peer(PEER_A)

func test_supporter_cannot_spend_fighter_attr() -> void:
	SkillTree.clear_peer(PEER_A)
	SkillTree.register_peer(PEER_A, "Supporter")
	LevelSystem.award_xp(PEER_A, 70)
	LevelSystem.spend_point_local(PEER_A, "stamina")
	var attrs: Dictionary = LevelSystem.get_attrs(PEER_A)
	assert_eq(attrs.get("stamina", 0), 0,
		"Supporter spending stamina must be a no-op")
	SkillTree.clear_peer(PEER_A)

# ── XP sync regression ────────────────────────────────────────────────────────

func test_award_xp_emits_xp_gained_with_correct_accumulated_total() -> void:
	# Regression guard: award_xp must emit xp_gained with the running total so
	# the HUD (and sync path) always reflects current XP between level-ups.
	watch_signals(LevelSystem)
	LevelSystem.award_xp(PEER_A, 10)
	LevelSystem.award_xp(PEER_A, 15)
	# After two awards, running total must be 25
	assert_eq(LevelSystem.get_xp(PEER_A), 25, "accumulated XP must be 25 after two awards")
	# xp_gained must have fired twice
	assert_signal_emit_count(LevelSystem, "xp_gained", 2)
