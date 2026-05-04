extends GutTest
# test_skill_client_sync.gd — regression tests for skill system client sync bugs.
#
# Bug 1: sync_skill_state silently no-oped when the client had no local state
#         (_states.get(my_id) == null -> return).  Fixed: auto-create state.
# Bug 2: sync_skill_state only emitted skill_pts_changed; never emitted
#         skill_unlocked or active_slots_changed.  Fixed: diff + emit.
# Bug 3: active_used never emitted on clients — fixed: detect cooldown onset.
# Bug 4: Dash/RapidFire/IronSkin/RallyCry metas not delivered to client —
#         fixed: apply_* RPCs wired in FighterSkills; apply_* RPC bodies
#         set metas on the local FPSPlayer node.
#
# All tests use OfflineMultiplayerPeer (Tier 1).
# Under OfflineMultiplayerPeer, multiplayer.get_unique_id() == 1, so
# sync_skill_state uses peer_id 1 as "my_id".

# ── Fake player inner class ───────────────────────────────────────────────────

class FakePlayer extends CharacterBody3D:
	var team: int = 0

# ── Scene helpers ─────────────────────────────────────────────────────────────

var _main: Node = null

func _ensure_main() -> void:
	var existing: Node = get_tree().root.get_node_or_null("Main")
	if existing != null:
		_main = existing
		return
	_main = Node.new()
	_main.name = "Main"
	get_tree().root.add_child(_main)

func _make_fake_player(peer_id: int) -> FakePlayer:
	_ensure_main()
	var fp := FakePlayer.new()
	fp.name = "FPSPlayer_%d" % peer_id
	_main.add_child(fp)
	return fp

# ── Setup / teardown ──────────────────────────────────────────────────────────

func before_each() -> void:
	BridgeClient._local_peer_id = 1
	SkillTree.clear_all()
	# Remove any Main node from prior tests to start clean.
	var old_main: Node = get_tree().root.get_node_or_null("Main")
	if old_main != null:
		old_main.free()
	_main = null

func after_each() -> void:
	BridgeClient._local_peer_id = 0
	SkillTree.clear_all()
	if _main != null and is_instance_valid(_main):
		_main.free()
	_main = null

# ── Bug 1: sync_skill_state auto-registers client state ───────────────────────

func test_sync_creates_state_when_missing() -> void:
	# No register_peer call — client state is absent.
	var my_id: int = 1  # OfflineMultiplayerPeer unique_id
	assert_eq(SkillTree.get_skill_pts(my_id), 0, "pre-condition: no state")
	# Simulate server pushing state to a client that has no local SkillTreeState.
	SkillTree.sync_skill_state(3, ["f_dash"], ["f_dash", ""], {})
	assert_eq(SkillTree.get_skill_pts(my_id), 3,
		"skill_pts must be populated from sync even when state was absent")
	assert_true(SkillTree.is_unlocked(my_id, "f_dash"),
		"unlocked array must be populated from sync")

func test_sync_does_not_duplicate_state_when_present() -> void:
	SkillTree.register_peer(1, "Fighter")
	SkillTree.sync_skill_state(5, ["f_dash", "f_adrenaline"], ["f_dash", ""], {})
	assert_eq(SkillTree.get_skill_pts(1), 5, "pts must overwrite existing value")
	assert_true(SkillTree.is_unlocked(1, "f_adrenaline"))

# ── Bug 2a: skill_unlocked emitted for each new node ──────────────────────────

func test_sync_emits_skill_unlocked_for_new_nodes() -> void:
	SkillTree.register_peer(1, "Fighter")
	# Start with f_dash already unlocked.
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {})
	watch_signals(SkillTree)
	# Now sync arrives with an additional node.
	SkillTree.sync_skill_state(1, ["f_dash", "f_adrenaline"], ["f_dash", ""], {})
	assert_signal_emitted_with_parameters(SkillTree, "skill_unlocked", [1, "f_adrenaline"])

func test_sync_does_not_emit_skill_unlocked_for_already_known_nodes() -> void:
	SkillTree.register_peer(1, "Fighter")
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {})
	watch_signals(SkillTree)
	# Sync with same unlocked list — no new entries.
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {})
	assert_signal_emit_count(SkillTree, "skill_unlocked", 0)

# ── Bug 2b: active_slots_changed emitted when slots differ ────────────────────

func test_sync_emits_active_slots_changed_when_slots_change() -> void:
	SkillTree.register_peer(1, "Fighter")
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {})
	watch_signals(SkillTree)
	# Slots change: slot 1 now assigned.
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", "f_dash"], {})
	assert_signal_emitted(SkillTree, "active_slots_changed")

func test_sync_does_not_emit_active_slots_changed_when_slots_same() -> void:
	SkillTree.register_peer(1, "Fighter")
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {})
	watch_signals(SkillTree)
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {})
	assert_signal_emit_count(SkillTree, "active_slots_changed", 0)

# ── Bug 3: active_used emitted when a cooldown newly appears ──────────────────

func test_sync_emits_active_used_when_cooldown_set_for_slot_node() -> void:
	SkillTree.register_peer(1, "Fighter")
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {})
	watch_signals(SkillTree)
	# New sync: f_dash now has a cooldown (ability was just used on server).
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {"f_dash": 6.0})
	assert_signal_emitted_with_parameters(SkillTree, "active_used", [1, "f_dash"])

func test_sync_does_not_emit_active_used_when_cooldown_already_running() -> void:
	SkillTree.register_peer(1, "Fighter")
	# Sync with existing cooldown.
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {"f_dash": 6.0})
	watch_signals(SkillTree)
	# Another sync with same cooldown still running — NOT a new use.
	SkillTree.sync_skill_state(2, ["f_dash"], ["f_dash", ""], {"f_dash": 4.5})
	assert_signal_emit_count(SkillTree, "active_used", 0)

func test_sync_does_not_emit_active_used_for_unslotted_node_cooldown() -> void:
	# A node might appear in cooldowns dict but not be in an active slot.
	SkillTree.register_peer(1, "Fighter")
	SkillTree.sync_skill_state(2, ["f_dash"], ["", ""], {})
	watch_signals(SkillTree)
	# f_dash has a cooldown but is NOT in any slot.
	SkillTree.sync_skill_state(2, ["f_dash"], ["", ""], {"f_dash": 6.0})
	assert_signal_emit_count(SkillTree, "active_used", 0)

# ── Bug 4: apply_* RPCs set metas on local player node ───────────────────────

func test_apply_dash_sets_metas_on_local_player() -> void:
	var fp := _make_fake_player(1)
	var origin := Vector3(1.0, 0.0, 2.0)
	var target := Vector3(6.0, 0.0, 2.0)
	SkillTree.apply_dash(origin, target, 0.0, 0.5)
	assert_true(fp.has_meta("dash_origin"),   "dash_origin meta must be set")
	assert_true(fp.has_meta("dash_target"),   "dash_target meta must be set")
	assert_true(fp.has_meta("dash_elapsed"),  "dash_elapsed meta must be set")
	assert_true(fp.has_meta("dash_duration"), "dash_duration meta must be set")
	assert_eq(fp.get_meta("dash_origin"),   origin)
	assert_eq(fp.get_meta("dash_target"),   target)
	assert_eq(fp.get_meta("dash_elapsed"),  0.0)
	assert_eq(fp.get_meta("dash_duration"), 0.5)

func test_apply_rapid_fire_sets_metas_on_local_player() -> void:
	var fp := _make_fake_player(1)
	SkillTree.apply_rapid_fire(3.0, "rifle")
	assert_true(fp.has_meta("rapid_fire_timer"),  "rapid_fire_timer must be set")
	assert_true(fp.has_meta("rapid_fire_weapon"), "rapid_fire_weapon must be set")
	assert_eq(fp.get_meta("rapid_fire_timer"),  3.0)
	assert_eq(fp.get_meta("rapid_fire_weapon"), "rifle")

func test_apply_iron_skin_sets_metas_on_local_player() -> void:
	var fp := _make_fake_player(1)
	SkillTree.apply_iron_skin(60.0, 8.0)
	assert_true(fp.has_meta("shield_hp"),    "shield_hp must be set")
	assert_true(fp.has_meta("shield_timer"), "shield_timer must be set")
	assert_eq(fp.get_meta("shield_hp"),    60.0)
	assert_eq(fp.get_meta("shield_timer"), 8.0)

func test_apply_rally_cry_sets_metas_on_local_player() -> void:
	var fp := _make_fake_player(1)
	SkillTree.apply_rally_cry(0.20, 5.0)
	assert_true(fp.has_meta("rally_speed_bonus"), "rally_speed_bonus must be set")
	assert_true(fp.has_meta("rally_cry_timer"),   "rally_cry_timer must be set")
	assert_eq(fp.get_meta("rally_speed_bonus"), 0.20)
	assert_eq(fp.get_meta("rally_cry_timer"),   5.0)

func test_apply_dash_no_crash_when_player_absent() -> void:
	# No FPSPlayer_1 node — must not crash.
	SkillTree.apply_dash(Vector3.ZERO, Vector3.ONE, 0.0, 0.5)
	pass  # reaching here = no crash

func test_apply_rapid_fire_no_crash_when_player_absent() -> void:
	SkillTree.apply_rapid_fire(3.0, "rifle")
	pass

func test_apply_iron_skin_no_crash_when_player_absent() -> void:
	SkillTree.apply_iron_skin(60.0, 8.0)
	pass

func test_apply_rally_cry_no_crash_when_player_absent() -> void:
	SkillTree.apply_rally_cry(0.20, 5.0)
	pass

# ── Bug 1 regression: passive_bonus readable after sync ───────────────────────

func test_get_passive_bonus_readable_after_sync_with_no_prior_state() -> void:
	# Simulates a client that never called register_peer but received a sync.
	# s_basic_t1 has passive_key "basic_tier", passive_val 1.0.
	SkillTree.sync_skill_state(0, ["s_basic_t1"], ["", ""], {})
	var bonus: float = SkillTree.get_passive_bonus(1, "basic_tier")
	assert_eq(bonus, 1.0, "passive bonus must be readable after sync creates state")
