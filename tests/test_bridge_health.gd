# test_bridge_health.gd
# Slice 3 — verifies that "player_health", "player_died", and "player_respawned"
# messages from the Python bridge update GameSync state and emit the correct signals.
extends GutTest

const PEER_A := 101

func before_each() -> void:
	GameSync.reset()
	GameSync.set_player_health(PEER_A, GameSync.PLAYER_MAX_HP)
	GameSync.set_player_team(PEER_A, 0)

func after_each() -> void:
	GameSync.reset()

func _fire(msg_type: String, payload: Dictionary) -> void:
	BridgeClient._handle_server_message(msg_type, payload)

# ── player_health ─────────────────────────────────────────────────────────────

func test_player_health_sets_game_sync_hp() -> void:
	_fire("player_health", {"peer_id": PEER_A, "health": 42.0})
	assert_almost_eq(GameSync.get_player_health(PEER_A), 42.0, 0.01,
		"player_health message must update GameSync health")

func test_player_health_emits_signal() -> void:
	watch_signals(GameSync)
	_fire("player_health", {"peer_id": PEER_A, "health": 75.0})
	assert_signal_emitted(GameSync, "player_health_changed",
		"player_health message must emit player_health_changed")

func test_player_health_invalid_peer_no_crash() -> void:
	_fire("player_health", {"peer_id": -1, "health": 50.0})
	pass  # must not crash

func test_player_health_missing_peer_no_crash() -> void:
	_fire("player_health", {"health": 50.0})
	pass

# ── player_died ───────────────────────────────────────────────────────────────

func test_player_died_marks_dead() -> void:
	_fire("player_died", {"peer_id": PEER_A, "respawn_time": 10.0})
	assert_true(GameSync.player_dead.get(PEER_A, false),
		"player_died message must set player_dead[peer_id] = true")

func test_player_died_emits_signal() -> void:
	watch_signals(GameSync)
	_fire("player_died", {"peer_id": PEER_A, "respawn_time": 10.0})
	assert_signal_emitted(GameSync, "player_died",
		"player_died message must emit GameSync.player_died signal")

func test_player_died_signal_carries_peer_id() -> void:
	watch_signals(GameSync)
	_fire("player_died", {"peer_id": PEER_A, "respawn_time": 10.0})
	var params: Array = get_signal_parameters(GameSync, "player_died")
	assert_eq(params[0], PEER_A, "player_died signal must carry the correct peer_id")

func test_player_died_signal_carries_respawn_time() -> void:
	watch_signals(GameSync)
	_fire("player_died", {"peer_id": PEER_A, "respawn_time": 15.5})
	var params: Array = get_signal_parameters(GameSync, "player_died")
	assert_almost_eq(float(params[1]), 15.5, 0.01,
		"player_died signal must carry the server-provided respawn_time")

func test_player_died_respawn_time_defaults_to_ten() -> void:
	watch_signals(GameSync)
	_fire("player_died", {"peer_id": PEER_A})  # no respawn_time key
	var params: Array = get_signal_parameters(GameSync, "player_died")
	assert_almost_eq(float(params[1]), 10.0, 0.01,
		"player_died signal must default respawn_time to 10.0 when not provided")

func test_player_died_invalid_peer_no_crash() -> void:
	_fire("player_died", {"peer_id": -1, "respawn_time": 10.0})
	pass

# ── player_respawned ──────────────────────────────────────────────────────────

func test_player_respawned_clears_dead_flag() -> void:
	GameSync.player_dead[PEER_A] = true
	_fire("player_respawned", {"peer_id": PEER_A, "spawn_pos": [0.0, 1.0, 82.0], "health": 100.0})
	assert_false(GameSync.player_dead.get(PEER_A, true),
		"player_respawned message must clear player_dead flag")

func test_player_respawned_sets_health() -> void:
	_fire("player_respawned", {"peer_id": PEER_A, "spawn_pos": [0.0, 1.0, 82.0], "health": 80.0})
	assert_almost_eq(GameSync.get_player_health(PEER_A), 80.0, 0.01,
		"player_respawned message must set health from payload")

func test_player_respawned_emits_signal() -> void:
	watch_signals(GameSync)
	_fire("player_respawned", {"peer_id": PEER_A, "spawn_pos": [5.0, 1.0, 82.0], "health": 100.0})
	assert_signal_emitted(GameSync, "player_respawned",
		"player_respawned message must emit GameSync.player_respawned signal")

func test_player_respawned_signal_carries_spawn_pos() -> void:
	watch_signals(GameSync)
	_fire("player_respawned", {"peer_id": PEER_A, "spawn_pos": [3.0, 1.5, 80.0], "health": 100.0})
	var params: Array = get_signal_parameters(GameSync, "player_respawned")
	assert_eq(params[0], PEER_A, "signal peer_id must match")
	assert_almost_eq((params[1] as Vector3).x, 3.0, 0.01, "spawn_pos.x must match")
	assert_almost_eq((params[1] as Vector3).z, 80.0, 0.01, "spawn_pos.z must match")

func test_player_respawned_invalid_peer_no_crash() -> void:
	_fire("player_respawned", {"peer_id": -1, "spawn_pos": [0.0, 0.0, 0.0], "health": 100.0})
	pass
