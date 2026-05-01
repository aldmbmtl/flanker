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
	# Fighters start with 1 SP (default dash grant) and f_dash pre-unlocked
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), 1)

func test_register_peer_idempotent() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.register_peer(FIGHTER_ID, "Supporter")  # should be ignored
	assert_eq(SkillTree.get_role(FIGHTER_ID), "Fighter")

func test_unregistered_peer_returns_defaults() -> void:
	assert_eq(SkillTree.get_role(99), "")
	assert_eq(SkillTree.get_skill_pts(99), 0)
	assert_false(SkillTree.is_unlocked(99, "f_field_medic"))
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

# Regression: leave_game() was missing SkillTree.clear_all(), causing stale
# role data when a peer rejoined with a different role in the next session.
func test_clear_all_allows_reregister_with_different_role() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_eq(SkillTree.get_role(FIGHTER_ID), "Fighter")
	# Simulate leave_game() clearing all state
	SkillTree.clear_all()
	# Peer rejoins next session as Supporter — must not be locked to old role
	SkillTree.register_peer(FIGHTER_ID, "Supporter")
	assert_eq(SkillTree.get_role(FIGHTER_ID), "Supporter")

func test_get_all_peers_returns_registered() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	var peers: Array = SkillTree.get_all_peers()
	assert_true(peers.has(FIGHTER_ID))
	assert_true(peers.has(SUPPORTER_ID))

# ── Level-up → SP award ──────────────────────────────────────────────────────

func test_level_up_awards_one_skill_point() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# Fighter starts with 1 SP from default dash grant
	SkillTree._on_level_up(FIGHTER_ID, 2)
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), 2)

func test_level_up_unregistered_peer_no_crash() -> void:
	# Unregistered peer must be silently ignored — no state created.
	SkillTree._on_level_up(99, 2)
	assert_eq(SkillTree.get_skill_pts(99), 0,
		"Unregistered peer must not have skill points created by level-up")

func test_level_up_emits_skill_pts_changed() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	watch_signals(SkillTree)
	SkillTree._on_level_up(FIGHTER_ID, 2)
	assert_signal_emitted(SkillTree, "skill_pts_changed")
	var params: Array = get_signal_parameters(SkillTree, "skill_pts_changed")
	assert_eq(params[0], FIGHTER_ID)
	assert_eq(params[1], 2)  # starts at 1 from default grant, +1 from level up

# ── Unlock validation ─────────────────────────────────────────────────────────

func test_cannot_unlock_without_points() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# Fighter starts with 1 SP — use it up, then verify can't unlock another
	SkillTree.unlock_node_local(FIGHTER_ID, "f_field_medic")
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "f_adrenaline"))

func test_can_unlock_tier1_with_1_point() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# Fighter starts with 1 SP from default grant — enough to unlock f_field_medic
	assert_true(SkillTree.can_unlock(FIGHTER_ID, "f_field_medic"))

func test_cannot_unlock_wrong_role() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "s_minion_hp"))

func test_cannot_unlock_unknown_node() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "nonexistent_node"))

func test_cannot_unlock_prereq_missing() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# f_rally_cry costs 2, prereq f_field_medic — even with SP, prereq blocks it
	SkillTree._on_level_up(FIGHTER_ID, 2)  # now 2 SP total
	assert_false(SkillTree.can_unlock(FIGHTER_ID, "f_rally_cry"))

func test_can_unlock_with_prereq_met() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# Starts with 1 SP. Unlock f_field_medic (costs 1) → 0 SP left.
	SkillTree.unlock_node_local(FIGHTER_ID, "f_field_medic")
	SkillTree._on_level_up(FIGHTER_ID, 3)
	SkillTree._on_level_up(FIGHTER_ID, 4)  # +2 SP → 2 total
	assert_true(SkillTree.can_unlock(FIGHTER_ID, "f_rally_cry"))

func test_unlock_deducts_skill_points() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# Starts at 1 SP. Unlock f_field_medic (cost 1) → 0 SP.
	SkillTree.unlock_node_local(FIGHTER_ID, "f_field_medic")
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), 0)

func test_unlock_marks_node_as_unlocked() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# f_dash is pre-unlocked by default
	assert_true(SkillTree.is_unlocked(FIGHTER_ID, "f_dash"))
	# Unlock another node using the default SP
	SkillTree.unlock_node_local(FIGHTER_ID, "f_field_medic")
	assert_true(SkillTree.is_unlocked(FIGHTER_ID, "f_field_medic"))

func test_unlock_emits_skill_unlocked_signal() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	watch_signals(SkillTree)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_field_medic")
	assert_signal_emitted(SkillTree, "skill_unlocked")
	var params: Array = get_signal_parameters(SkillTree, "skill_unlocked")
	assert_eq(params[0], FIGHTER_ID)
	assert_eq(params[1], "f_field_medic")

func test_cannot_unlock_already_unlocked() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# f_dash is pre-unlocked. Attempting to unlock it again should not deduct SP.
	var pts_before: int = SkillTree.get_skill_pts(FIGHTER_ID)
	SkillTree.unlock_node_local(FIGHTER_ID, "f_dash")
	assert_eq(SkillTree.get_skill_pts(FIGHTER_ID), pts_before)

# ── Passive bonus summing ─────────────────────────────────────────────────────
# Fighter tree has no passive nodes — all nodes are active.
# Passive bonus for any Fighter key is always 0.0 regardless of unlocks.

func test_fighter_passive_bonus_always_zero() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_eq(SkillTree.get_passive_bonus(FIGHTER_ID, "headshot_mult"), 0.0)

func test_fighter_passive_bonus_zero_after_unlock() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# f_dash is already unlocked by default; passive_key "" contributes 0.0
	assert_eq(SkillTree.get_passive_bonus(FIGHTER_ID, "damage_reduction"), 0.0)
	assert_eq(SkillTree.get_passive_bonus(FIGHTER_ID, "headshot_mult"), 0.0)

func test_fighter_passive_bonus_unrelated_key_zero() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	assert_eq(SkillTree.get_passive_bonus(FIGHTER_ID, "damage_reduction"), 0.0)

# ── Active slot assignment ─────────────────────────────────────────────────────

func test_active_slots_empty_by_default() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	var slots: Array = SkillTree.get_active_slots(FIGHTER_ID)
	# f_dash is pre-assigned to slot 0 by default
	assert_eq(slots[0], "f_dash")
	assert_eq(slots[1], "")

func test_assign_active_slot_requires_unlock() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	# f_adrenaline is not unlocked — assigning it should fail
	SkillTree.assign_active_slot(FIGHTER_ID, 1, "f_adrenaline")
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[1], "")

func test_assign_active_slot_succeeds_when_unlocked() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[0], "f_dash")

func test_cannot_assign_non_active_node_to_slot() -> void:
	# s_minion_hp is type "passive" — should be rejected from active slot
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	SkillTree._on_level_up(SUPPORTER_ID, 2)
	SkillTree.unlock_node_local(SUPPORTER_ID, "s_minion_hp")
	SkillTree.assign_active_slot(SUPPORTER_ID, 0, "s_minion_hp")
	assert_eq(SkillTree.get_active_slots(SUPPORTER_ID)[0], "")

func test_assign_active_emits_slots_changed() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	watch_signals(SkillTree)
	SkillTree.assign_active_slot(FIGHTER_ID, 1, "f_dash")
	assert_signal_emitted(SkillTree, "active_slots_changed")

func test_assign_active_slot_out_of_range_ignored() -> void:
	# Slot 5 is out of range (valid: 0–1) — must be silently rejected.
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	var slots_before: Array = SkillTree.get_active_slots(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 5, "f_dash")
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID), slots_before,
		"Out-of-range slot assignment must not mutate active_slots")

# ── use_active / cooldown ─────────────────────────────────────────────────────

func test_use_active_empty_slot_no_crash() -> void:
	# Slot 1 is empty by default — using it must be a silent no-op.
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	SkillTree.use_active_local(FIGHTER_ID, 1)
	# Empty slot has no node_id → no cooldown entry should be created.
	assert_almost_eq(SkillTree.get_cooldown(FIGHTER_ID, ""), 0.0, 0.001,
		"Using an empty slot must not start any cooldown")

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

func test_supporter_minion_hp_passive() -> void:
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	SkillTree._on_level_up(SUPPORTER_ID, 2)
	SkillTree.unlock_node_local(SUPPORTER_ID, "s_minion_hp")
	assert_almost_eq(SkillTree.get_passive_bonus(SUPPORTER_ID, "minion_hp_bonus"), 0.25, 0.001)

func test_supporter_minion_damage_passive() -> void:
	SkillTree.register_peer(SUPPORTER_ID, "Supporter")
	SkillTree._on_level_up(SUPPORTER_ID, 2)
	SkillTree.unlock_node_local(SUPPORTER_ID, "s_minion_damage")
	assert_almost_eq(SkillTree.get_passive_bonus(SUPPORTER_ID, "minion_damage_bonus"), 0.20, 0.001)

# ── Explicit slot targeting (Q=0, E=1) ───────────────────────────────────────

func test_assign_slot0_explicit_leaves_slot1_empty() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	var slots: Array = SkillTree.get_active_slots(FIGHTER_ID)
	assert_eq(slots[0], "f_dash")
	assert_eq(slots[1], "")

func test_assign_slot1_explicit_leaves_slot0_empty() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 1, "f_dash")
	var slots: Array = SkillTree.get_active_slots(FIGHTER_ID)
	# slot 0 already has f_dash from default grant; slot 1 now also has it
	assert_eq(slots[0], "f_dash")
	assert_eq(slots[1], "f_dash")

func test_assign_both_slots_independently() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	# Assign the same active skill to both slots independently — valid use case
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	SkillTree.assign_active_slot(FIGHTER_ID, 1, "f_dash")
	var slots: Array = SkillTree.get_active_slots(FIGHTER_ID)
	assert_eq(slots[0], "f_dash")
	assert_eq(slots[1], "f_dash")

func test_clear_slot_with_empty_string() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	_unlock_dash(FIGHTER_ID)
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "f_dash")
	SkillTree.assign_active_slot(FIGHTER_ID, 0, "")
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[0], "")

# ── get_active_slots returns copy, not reference ──────────────────────────────

func test_get_active_slots_returns_copy() -> void:
	SkillTree.register_peer(FIGHTER_ID, "Fighter")
	var slots: Array = SkillTree.get_active_slots(FIGHTER_ID)
	slots[0] = "tampered"
	# Internal state should be unchanged — slot 0 still has default f_dash
	assert_eq(SkillTree.get_active_slots(FIGHTER_ID)[0], "f_dash")

# ── Helper ────────────────────────────────────────────────────────────────────

func _unlock_dash(peer_id: int) -> void:
	# f_dash is DPS tier 1, cost 1, no prereqs — just needs 1 SP
	SkillTree._on_level_up(peer_id, 2)   # +1 SP
	SkillTree.unlock_node_local(peer_id, "f_dash")
