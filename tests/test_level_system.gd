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
