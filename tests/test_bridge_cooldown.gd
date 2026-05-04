# test_bridge_cooldown.gd
# Slice 2 — verifies that a "cooldown_tick" message from the bridge server
# updates SkillTree state for the specified peer via _apply_bridge_cooldown_tick.
extends GutTest

# ─── helpers ──────────────────────────────────────────────────────────────────

func _fire_bridge_message(msg_type: String, payload: Dictionary) -> void:
	BridgeClient._handle_server_message(msg_type, payload)

func after_each() -> void:
	# Always clean up any peer state we may have created so we don't
	# pollute other test files (SkillTree register_peer is idempotent only
	# when the peer doesn't already exist — stale state causes role mismatches).
	SkillTree.clear_peer(42)
	SkillTree.clear_peer(43)
	SkillTree.clear_peer(99)

# ─── cooldown_tick ────────────────────────────────────────────────────────────

func test_cooldown_tick_updates_skill_tree_state() -> void:
	SkillTree.clear_peer(42)
	SkillTree.register_peer(42, "Fighter")
	var cooldowns := {"f_dash": 4.5}
	_fire_bridge_message("cooldown_tick", {"peer_id": 42, "cooldowns": cooldowns})
	assert_eq(SkillTree.get_cooldown(42, "f_dash"), 4.5,
		"cooldown_tick bridge message must update SkillTree cooldowns")

func test_cooldown_tick_unknown_peer_creates_state() -> void:
	SkillTree.clear_peer(99)
	_fire_bridge_message("cooldown_tick", {"peer_id": 99, "cooldowns": {"f_dash": 2.0}})
	assert_eq(SkillTree.get_cooldown(99, "f_dash"), 2.0,
		"cooldown_tick for unknown peer must create state entry")

func test_cooldown_tick_empty_cooldowns_clears_state() -> void:
	SkillTree.clear_peer(43)
	SkillTree.register_peer(43, "Fighter")
	SkillTree._apply_bridge_cooldown_tick(43, {"f_dash": 3.0})
	SkillTree._apply_bridge_cooldown_tick(43, {})
	assert_eq(SkillTree.get_cooldown(43, "f_dash"), 0.0,
		"empty cooldowns dict must clear all cooldowns for the peer")

func test_cooldown_tick_invalid_peer_id_no_crash() -> void:
	_fire_bridge_message("cooldown_tick", {"peer_id": -1, "cooldowns": {"f_dash": 1.0}})
	pass

func test_cooldown_tick_missing_peer_id_no_crash() -> void:
	_fire_bridge_message("cooldown_tick", {"cooldowns": {"f_dash": 1.0}})
	pass

