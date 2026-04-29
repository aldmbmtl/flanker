extends GutTest
# test_skill_tree.gd — unit tests for SkillTree autoload
# Covers: registration, SP award on level-up, unlock validation, prereqs,
# passive bonus summing, cooldown tick, active slot assignment, use_active,
# reset_per_life (second_wind), clear_peer / clear_all, RPC helpers.
#
# All tests use OfflineMultiplayerPeer (Tier 1) so multiplayer.is_server() == true.

const FIGHTER_ID   := 10
const SUPPORTER_ID := 20

func before_each() -> void:
	SkillTree.clear_all()

func after_each() -> void:
	SkillTree.clear_all()

# ── Registration ──────────────────────────────────────────────────────────────

func test_register_peer_creates_state() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_eq(SkillTree.get_role(FIGHTER_ID), "Fighter")
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), 0)

func test_register_peer_idempotent() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.register_peer(FIGHTER_ID, "Supporter")  # should be ignored
	assert_eq(SkillTree.get_role(FIGHTER_ID), "Fighter")

func test_unregistered_peer_returns_defaults() -> void:
	assert_eq(SkillTree.get_role(99), "")
	assert_eq(SkillTree.get_skill_pts(99), 0)
	assert_false(SkillTree.is_unlocked(99, "f_headshot"))
	assert_eq(SkillTree.get_passive_bonus(99, "headshot_mult"), 0.0)

func test_clear_peer_removes_state() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.clear_peer(FIGHTER_ID)
	assert_eq(SkillTree.get_role(FIGHTER_ID), "")

func test_clear_all_removes_all_peers() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	SkillTree.clear_all()
	assert_eq(SkillTree.get_role(FIGHTER_ID), "")
	assert_eq(SkillTree.get_role(SUPPORTER_ID), "")

func test_get_all_peers_returns_registered() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	var peers: Array = SkillTree.get_all_peers()
	assert_true(peers.has(FIGHTER_ID))
	assert_true(peers.has(SUPPORTER_ID))

# ── Level-up → SP award ──────────────────────────────────────────────────────

func test_level_up_awards_one_skill_point() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), 1)

func test_level_up_unregistered_peer_no_crash() -> void:
	SkillTree._on_level_up(99, 2)
	# Should not crash

func test_level_up_emits_skill_pts_changed() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	watch_signals(SkillTree)
	SkillTree._on_level_up(FIGHTER_ID, 2)
	assert_signal_emitted(SkillTree, "skill_pts_changed")
	var params: Array = get_signal_parameters(SkillTree, "skill_pts_changed")
	assert_eq(params[0], FIGHTER_ID)
	assert_eq(params[1], 1)

# ── Unlock validation ─────────────────────────────────────────────────────────

func test_cannot_unlock_without_points() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "f_headshot"))

func test_can_unlock_tier1_with_1_point() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)  # +1 SP
	assert_true(SkillTree.can_unlock(FIGHTER_ID, "f_headshot"))

func test_cannot_unlock_wrong_role() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "s_build_discount"))

func test_cannot_unlock_unknown_node() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "nonexistent_node"))

func test_cannot_unlock_prereq_missing() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# f_reload costs 2, prereq f_headshot
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree._on_level_up(FIGHTER_ID, 3)  # 2 SP total
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "f_reload"))

func test_can_unlock_with_prereq_met() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")  # costs 1
	SkillTree._on_level_up(FIGHTER_ID, 3)
	SkillTree._on_level_up(FIGHTER_ID, 4)  # +2 more SP
	assert_true(SkillTree.can_unlock(FIGHTER_ID, "f_reload"))

func test_unlock_deducts_skill_points() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), 0)

func test_unlock_marks_node_as_unlocked() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	assert_true(SkillTree.is_unlocked(FIGHTER_ID, "f_headshot"))

func test_unlock_emits_skill_unlocked_signal() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	watch_signals(SkillTree)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	assert_signal_emitted(SkillTree, "skill_unlocked")
	var params: Array = get_signal_parameters(SkillTree, "skill_unlocked")
	assert_eq(params[0], FIGHTER_ID)
	assert_eq(params[1], "f_headshot")

func test_cannot_unlock_already_unlocked() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	SkillTree._on_level_up(FIGHTER_ID, 3)  # +1 more SP
	# Attempt to unlock again — points should NOT decrease again
	var pts_before: int = SkillTree.get_skill_pts(FIGHTER_ID)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), pts_before)

# ── Passive bonus summing ─────────────────────────────────────────────────────

func test_passive_bonus_zero_before_unlock() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_eq(SkillTree.get_passive_bonus(FIGHTER_ID, "headshot_mult"), 0.0)

func test_passive_bonus_correct_after_unlock() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	assert_almost_eq(SkillTree.get_passive_bonus(FIGHTER_ID, "headshot_mult"), 0.15, 0.001)

func test_passive_bonus_unrelated_key_still_zero() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	assert_eq(SkillTree.get_passive_bonus(FIGHTER_ID, "damage_reduction"), 0.0)

# ── Active slot assignment ─────────────────────────────────────────────────────

func test_active_slots_empty_by_default() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	var slots: Array = SkillTree.get_active_slots(FIGHTER_ID)
	assert_eq(slots[0], "")
	assert_eq(slots[1], "")

func test_assign_active_slot_requires_unlock() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# f_dash not unlocked yet
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[0], "")

func test_assign_active_slot_succeeds_when_unlocked() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# Unlock path to f_dash: f_sprint_boost (1 SP) then f_dash (2 SP)
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_sprint_boost")
	SkillTree._on_level_up(FIGHTER_ID, 3)
	SkillTree._on_level_up(FIGHTER_ID, 4)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_dash")
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[0], "f_dash")

func test_cannot_assign_non_active_node_to_slot() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_headshot")
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_headshot")
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[0], "")

func test_assign_active_emits_slots_changed() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree._on_level_up(FIGHTER_ID, 2)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_sprint_boost")
	SkillTree._on_level_up(FIGHTER_ID, 3)
	SkillTree._on_level_up(FIGHTER_ID, 4)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_dash")
	watch_signals(SkillTree)
	SkillTree.assign_active_slot(FIGHTER_ID, 1, "f_dash")
	assert_signal_emitted(SkillTree, "active_slots_changed")

func test_assign_active_slot_out_of_range_ignored() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.assign_active_slot(FIGHTER_ID, 5, "f_dash")  # should not crash

# ── use_active / cooldown ─────────────────────────────────────────────────────

func test_use_active_empty_slot_no_crash() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.use_active_local(FIGHTER_ID, 0)

func test_use_active_starts_cooldown() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	SkillTree.use_active_local(FIGHTER_ID, 0)
	assert_gt(SkillTree.get_cooldown(FIGHTER_ID, "f_dash"), 0.0)

func test_use_active_on_cooldown_no_second_fire() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	SkillTree.use_active_local(FIGHTER_ID, 0)
	var cd1: float = SkillTree.get_cooldown(FIGHTER_ID, "f_dash")
	watch_signals(SkillTree)
	SkillTree.use_active_local(FIGHTER_ID, 0)  # should be blocked
	# active_used should have been emitted only once (from first use above)
	# Since we started watching after first use, it should NOT fire again
	assert_signal_not_emitted(SkillTree, "active_used")

func test_cooldown_ticks_down() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	SkillTree.use_active_local(FIGHTER_ID, 0)
	var cd_before: float = SkillTree.get_cooldown(FIGHTER_ID, "f_dash")
	SkillTree._tick_cooldowns_for(FIGHTER_ID, 1.0)
	var cd_after: float = SkillTree.get_cooldown(FIGHTER_ID, "f_dash")
	assert_almost_eq(cd_after, cd_before - 1.0, 0.001)

func test_cooldown_clamps_at_zero() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	SkillTree.use_active_local(FIGHTER_ID, 0)
	SkillTree._tick_cooldowns_for(FIGHTER_ID, 9999.0)
	assert_eq(SkillTree.get_cooldown(FIGHTER_ID, "f_dash"), 0.0)

# ── second_wind / reset_per_life ──────────────────────────────────────────────

func test_second_wind_not_used_by_default() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_false(SkillTree.is_second_wind_used(FIGHTER_ID))

func test_consume_second_wind_marks_as_used() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.consume_second_wind(FIGHTER_ID)
	assert_true(SkillTree.is_second_wind_used(FIGHTER_ID))

func test_reset_per_life_clears_second_wind() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.consume_second_wind(FIGHTER_ID)
	SkillTree.reset_per_life(FIGHTER_ID)
	assert_false(SkillTree.is_second_wind_used(FIGHTER_ID))

func test_second_wind_unregistered_returns_true_safely() -> void:
	assert_true(SkillTree.is_second_wind_used(99))

# ── Supporter passive bonus ───────────────────────────────────────────────────

func test_supporter_respawn_reduction_passive() -> void:
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	SkillTree._on_level_up(SUPPORTER_ID, 2)
	SkillTree.unlock_node_local(SUPPORTER_ID, "s_fast_respawn")
	assert_almost_eq(SkillTree.get_passive_bonus(SUPPORTER_ID, "respawn_reduction"), 2.0, 0.001)

func test_supporter_build_discount_passive() -> void:
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	SkillTree._on_level_up(SUPPORTER_ID, 2)
	SkillTree.unlock_node_local(SUPPORTER_ID, "s_build_discount")
	assert_almost_eq(SkillTree.get_passive_bonus(SUPPORTER_ID, "build_discount"), 2.0, 0.001)

# ── get_active_slots returns copy, not reference ──────────────────────────────

func test_get_active_slots_returns_copy() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	var slots: Array = SkillTree.get_active_slots(FIGHTER_ID)
	slots[0] = "tampered"
	# Internal state should be unchanged
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[0], "")

# ── Helper ────────────────────────────────────────────────────────────────────

func _unlock_dash(peer_id: int) -> void:
	# Unlock the minimal path to f_dash: f_sprint_boost (1 SP) + f_dash (2 SP)
	SkillTree._on_level_up(peer_id, 2)   # +1 SP
	SkillTree.unlock_node_local(peer_id, "f_sprint_boost")
	SkillTree._on_level_up(peer_id, 3)   # +1 SP
	SkillTree._on_level_up(peer_id, 4)   # +1 SP (total 2 for f_dash)
	SkillTree.unlock_node_local(peer_id, "f_dash")
