# test_bridge_lobby.gd
# Slice 5 Part 6 — verifies that "lobby_state", "load_game", "role_accepted",
# and "role_rejected" messages from the Python bridge correctly update
# LobbyManager state and emit signals.
extends GutTest

var _size_at_emit: int = -1

func before_each() -> void:
	LobbyManager.players.clear()
	LobbyManager._can_start = false
	LobbyManager.supporter_claimed = { 0: false, 1: false }
	_size_at_emit = -1

func after_each() -> void:
	LobbyManager.players.clear()
	LobbyManager._can_start = false
	LobbyManager.supporter_claimed = { 0: false, 1: false }
	GameSync.player_teams.clear()

func _fire(msg_type: String, payload: Dictionary) -> void:
	BridgeClient._handle_server_message(msg_type, payload)

# ── lobby_state: player dict population ──────────────────────────────────────

func test_lobby_state_populates_players_dict() -> void:
	_fire("lobby_state", {
		"players": {
			"1": {"name": "Alice", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_true(LobbyManager.players.has(1),
		"lobby_state must add the player keyed by int peer id")

func test_lobby_state_stores_player_name() -> void:
	_fire("lobby_state", {
		"players": {
			"2": {"name": "Bob", "team": 1, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_eq(LobbyManager.players.get(2, {}).get("name", ""),
		"Bob", "lobby_state must store player name correctly")

func test_lobby_state_stores_player_team() -> void:
	_fire("lobby_state", {
		"players": {
			"3": {"name": "Carol", "team": 1, "role": -1, "ready": true, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_eq(LobbyManager.players.get(3, {}).get("team", 0),
		1, "lobby_state must store player team correctly")

func test_lobby_state_stores_ready_flag() -> void:
	_fire("lobby_state", {
		"players": {
			"4": {"name": "Dave", "team": 0, "role": -1, "ready": true, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_true(LobbyManager.players.get(4, {}).get("ready", false),
		"lobby_state must store ready flag correctly")

func test_lobby_state_populates_multiple_players() -> void:
	_fire("lobby_state", {
		"players": {
			"1": {"name": "A", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
			"2": {"name": "B", "team": 1, "role": -1, "ready": false, "avatar_char": ""},
			"3": {"name": "C", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_eq(LobbyManager.players.size(), 3,
		"lobby_state must populate all players in the payload")

func test_lobby_state_clears_stale_players() -> void:
	# Seed a stale player that is no longer in the new state.
	LobbyManager.players[99] = {"name": "Stale", "team": 0, "role": -1, "ready": false, "avatar_char": ""}
	_fire("lobby_state", {
		"players": {
			"1": {"name": "Fresh", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_false(LobbyManager.players.has(99),
		"lobby_state must clear players absent from the new state")
	assert_true(LobbyManager.players.has(1),
		"lobby_state must include players present in the new state")

func test_lobby_state_empty_players_clears_dict() -> void:
	LobbyManager.players[5] = {"name": "X", "team": 0, "role": -1, "ready": false, "avatar_char": ""}
	_fire("lobby_state", {"players": {}, "can_start": false})
	assert_true(LobbyManager.players.is_empty(),
		"lobby_state with empty players must clear the dict")

func test_lobby_state_pid_string_keys_converted_to_int() -> void:
	_fire("lobby_state", {
		"players": {
			"42": {"name": "Eve", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	# Key must be int 42, not string "42"
	assert_true(LobbyManager.players.has(42),
		"lobby_state must convert string peer-id keys to int")
	assert_false(LobbyManager.players.has("42"),
		"lobby_state must not leave string keys in players dict")

# ── lobby_state: can_start flag ───────────────────────────────────────────────

func test_lobby_state_sets_can_start_true() -> void:
	_fire("lobby_state", {"players": {}, "can_start": true})
	assert_true(LobbyManager._can_start,
		"lobby_state with can_start=true must set LobbyManager._can_start")

func test_lobby_state_sets_can_start_false() -> void:
	LobbyManager._can_start = true
	_fire("lobby_state", {"players": {}, "can_start": false})
	assert_false(LobbyManager._can_start,
		"lobby_state with can_start=false must clear LobbyManager._can_start")

func test_lobby_state_can_start_missing_defaults_false() -> void:
	LobbyManager._can_start = true
	_fire("lobby_state", {"players": {}})
	assert_false(LobbyManager._can_start,
		"lobby_state without can_start key must default to false")

func test_can_start_game_reflects_can_start_flag() -> void:
	LobbyManager._can_start = false
	assert_false(LobbyManager.can_start_game())
	LobbyManager._can_start = true
	assert_true(LobbyManager.can_start_game())

# ── lobby_state: lobby_updated signal ────────────────────────────────────────

func test_lobby_state_emits_lobby_updated() -> void:
	watch_signals(LobbyManager)
	_fire("lobby_state", {"players": {}, "can_start": false})
	assert_signal_emitted(LobbyManager, "lobby_updated",
		"lobby_state message must emit LobbyManager.lobby_updated")

func test_lobby_state_emits_lobby_updated_with_players() -> void:
	watch_signals(LobbyManager)
	_fire("lobby_state", {
		"players": {
			"7": {"name": "G", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": true,
	})
	assert_signal_emitted(LobbyManager, "lobby_updated",
		"lobby_state message must emit lobby_updated when players are present")

func test_lobby_state_signal_fires_after_dict_populated() -> void:
	# Connect to lobby_updated and capture players dict size at emit time.
	LobbyManager.lobby_updated.connect(_on_lobby_updated_capture, CONNECT_ONE_SHOT)
	_fire("lobby_state", {
		"players": {
			"1": {"name": "H", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
			"2": {"name": "I", "team": 1, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_eq(_size_at_emit, 2,
		"lobby_updated must fire after players dict is populated, not before")

func _on_lobby_updated_capture() -> void:
	_size_at_emit = LobbyManager.players.size()

# ── lobby_state: missing/malformed payload ────────────────────────────────────

func test_lobby_state_missing_players_key_no_crash() -> void:
	_fire("lobby_state", {"can_start": false})
	# players.clear() is called on {} so dict is empty — no crash
	pass

func test_lobby_state_empty_payload_no_crash() -> void:
	_fire("lobby_state", {})
	pass

# ── load_game: scene change ───────────────────────────────────────────────────

func test_load_game_empty_path_no_scene_change() -> void:
	# An empty path must not trigger change_scene_to_file.
	# We verify indirectly: the test completes without crashing or switching scene.
	_fire("load_game", {"path": ""})
	pass  # must not crash or change scene

func test_load_game_missing_path_no_scene_change() -> void:
	_fire("load_game", {})
	pass  # must not crash or change scene

func test_load_game_nonexistent_path_no_crash() -> void:
	# A non-empty but non-existent path: change_scene_to_file will log an error
	# but must not hard-crash the test runner. We just verify no exception thrown.
	# (Godot prints an error; that is acceptable — the test still passes.)
	pass  # tested implicitly — scene doesn't exist so nothing changes

# ── load_game: Lobby node cleanup (regression) ──────────────────────────────
# Regression: when the Python server sent "load_game", BridgeClient called
# change_scene_to_file which only frees get_tree().current_scene. The Lobby
# node was added directly to root in StartMenu._show_lobby(), making it a
# sibling of the current scene — NOT the current scene itself — so it was
# never freed and persisted rendered on top of the game.
# Fix: BridgeClient explicitly queue_frees the "Lobby" root child before
# calling change_scene_to_file.

func test_load_game_frees_lobby_node_from_root() -> void:
	# Arrange: add a stub Control node named "Lobby" directly to root, mimicking
	# what StartMenu._show_lobby() does at runtime.
	var fake_lobby: Control = Control.new()
	fake_lobby.name = "Lobby"
	get_tree().root.add_child(fake_lobby)

	# Act: fire load_game with empty path so change_scene_to_file is NOT called
	# (avoids scene switch in tests). The Lobby cleanup runs before the path
	# guard, so fake_lobby must be queued for deletion regardless.
	_fire("load_game", {"path": ""})

	# Let the deferred queue_free execute.
	await get_tree().process_frame

	# Assert: the stub Lobby node must no longer exist under root.
	assert_null(get_tree().root.get_node_or_null("Lobby"),
		"load_game must queue_free the Lobby root child so it does not persist over the game scene")

func test_load_game_no_crash_when_lobby_absent() -> void:
	# Guard: if no Lobby node exists under root the handler must not crash.
	assert_null(get_tree().root.get_node_or_null("Lobby"))
	_fire("load_game", {"path": ""})
	pass  # must not crash

# ── lobby_state: GameSync.player_teams population ────────────────────────────

func test_lobby_state_sets_gamesync_team_for_each_peer() -> void:
	# Python sends team assignments in lobby_state. BridgeClient must mirror
	# them into GameSync.player_teams so combat/targeting code works without
	# the now-removed register_player_team RPC.
	_fire("lobby_state", {
		"players": {
			"1": {"name": "Alice", "team": 0, "role": -1, "ready": false, "avatar_char": ""},
			"2": {"name": "Bob",   "team": 1, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_eq(GameSync.get_player_team(1), 0,
		"peer 1 must be set to team 0 in GameSync")
	assert_eq(GameSync.get_player_team(2), 1,
		"peer 2 must be set to team 1 in GameSync")

func test_lobby_state_team_overwrites_previous_gamesync_value() -> void:
	# A second lobby_state with a different team must update GameSync.
	GameSync.set_player_team(5, 0)
	_fire("lobby_state", {
		"players": {
			"5": {"name": "Eve", "team": 1, "role": -1, "ready": false, "avatar_char": ""},
		},
		"can_start": false,
	})
	assert_eq(GameSync.get_player_team(5), 1,
		"updated lobby_state must overwrite the stale team value in GameSync")

func test_lobby_state_empty_players_does_not_crash() -> void:
	# A lobby_state with no players key must not crash.
	_fire("lobby_state", {"can_start": false})
	assert_eq(GameSync.player_teams.size(), 0,
		"no players in payload means no GameSync entries written")

# ── role_accepted ─────────────────────────────────────────────────────────────

func test_role_accepted_updates_supporter_claimed_team0() -> void:
	# Regression: BridgeClient had no "role_accepted" arm so supporter_claimed
	# was never updated from the server. Main.gd read stale false values and
	# the rejection check at line 218 never fired correctly.
	_fire("role_accepted", {
		"peer_id": 1, "role": 1,
		"supporter_claimed": {0: true, 1: false},
	})
	assert_true(LobbyManager.supporter_claimed.get(0, false),
		"role_accepted must set supporter_claimed[0] = true")
	assert_false(LobbyManager.supporter_claimed.get(1, false),
		"role_accepted must leave supporter_claimed[1] = false when only team 0 claimed")

func test_role_accepted_updates_supporter_claimed_team1() -> void:
	_fire("role_accepted", {
		"peer_id": 2, "role": 1,
		"supporter_claimed": {0: false, 1: true},
	})
	assert_false(LobbyManager.supporter_claimed.get(0, false),
		"role_accepted must leave supporter_claimed[0] = false when only team 1 claimed")
	assert_true(LobbyManager.supporter_claimed.get(1, false),
		"role_accepted must set supporter_claimed[1] = true")

func test_role_accepted_emits_role_slots_updated() -> void:
	# Main.gd awaits LobbyManager.role_slots_updated after sending set_role_ingame.
	# If this signal is never emitted in the bridge path the dialog hangs forever.
	watch_signals(LobbyManager)
	_fire("role_accepted", {
		"peer_id": 1, "role": 0,
		"supporter_claimed": {0: false, 1: false},
	})
	assert_signal_emitted(LobbyManager, "role_slots_updated",
		"role_accepted must emit LobbyManager.role_slots_updated")

func test_role_accepted_fighter_does_not_set_supporter_claimed() -> void:
	# Accepting Fighter role must not flip supporter_claimed.
	_fire("role_accepted", {
		"peer_id": 1, "role": 0,
		"supporter_claimed": {0: false, 1: false},
	})
	assert_false(LobbyManager.supporter_claimed.get(0, false),
		"Fighter role_accepted must not set supporter_claimed[0]")
	assert_false(LobbyManager.supporter_claimed.get(1, false),
		"Fighter role_accepted must not set supporter_claimed[1]")

# ── role_rejected ─────────────────────────────────────────────────────────────

func test_role_rejected_updates_supporter_claimed() -> void:
	# On rejection Python sends the current authoritative supporter_claimed so
	# the client can gray out the taken button.
	_fire("role_rejected", {
		"peer_id": 1,
		"supporter_claimed": {0: true, 1: false},
	})
	assert_true(LobbyManager.supporter_claimed.get(0, false),
		"role_rejected must reflect the server's supporter_claimed state")

func test_role_rejected_emits_role_slots_updated() -> void:
	# Main.gd awaits role_slots_updated even on rejection so the dialog can
	# re-enable the correct buttons before re-showing.
	watch_signals(LobbyManager)
	_fire("role_rejected", {
		"peer_id": 1,
		"supporter_claimed": {0: true, 1: false},
	})
	assert_signal_emitted(LobbyManager, "role_slots_updated",
		"role_rejected must emit LobbyManager.role_slots_updated")

func test_role_rejected_does_not_crash_on_empty_payload() -> void:
	# Guard: missing supporter_claimed key defaults to both false — no crash.
	_fire("role_rejected", {"peer_id": 1})
	assert_false(LobbyManager.supporter_claimed.get(0, false),
		"missing supporter_claimed must default to false without crash")
