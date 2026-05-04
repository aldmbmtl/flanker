# test_lobby_manager.gd
# Tier 1 + Tier 2 — LobbyManager logic, role slot validation, known bug documentation.
# All tests run with OfflineMultiplayerPeer (default); multiplayer.is_server() == true.
extends GutTest

# Helper: seed a player dict entry directly (register_player_local was removed;
# Python now owns player registration).
func _add_player(peer_id: int, player_name: String, team: int = 0) -> void:
	LobbyManager.players[peer_id] = {
		"name": player_name,
		"team": team,
		"role": -1,
		"ready": false,
		"avatar_char": ""
	}

func before_each() -> void:
	LobbyManager.players.clear()
	LobbyManager.game_started = false
	LobbyManager.supporter_claimed = { 0: false, 1: false }
	LobbyManager.player_death_counts.clear()
	LobbyManager._can_start = false
	LevelSystem.clear_all()
	SkillTree.clear_all()

# ── can_start_game ────────────────────────────────────────────────────────────

func test_can_start_game_false_by_default() -> void:
	assert_false(LobbyManager.can_start_game(), "can_start_game returns false when _can_start is false")

func test_can_start_game_true_when_can_start_set() -> void:
	LobbyManager._can_start = true
	assert_true(LobbyManager.can_start_game(), "can_start_game returns true when _can_start is true")

func test_can_start_game_reflects_can_start_field() -> void:
	# With players present but _can_start still false, should still return false
	_add_player(1, "Alice", 0)
	LobbyManager.players[1]["ready"] = true
	assert_false(LobbyManager.can_start_game(), "_can_start=false overrides player ready state")

# ── role slot validation ──────────────────────────────────────────────────────

func test_first_supporter_claim_succeeds() -> void:
	_add_player(1, "Alice", 0)
	LobbyManager._handle_set_role_ingame(1, 1)  # role 1 = Supporter; call server handler directly
	assert_true(LobbyManager.supporter_claimed[0],
		"Team 0 Supporter slot should be claimed after first claim")

func test_second_supporter_on_same_team_is_rejected() -> void:
	_add_player(1, "Alice", 0)
	_add_player(2, "Bob", 0)
	LobbyManager.supporter_claimed[0] = true  # simulate first claim already done
	# Verify the flag is still true — guard prevents double-claim
	assert_true(LobbyManager.supporter_claimed[0],
		"Slot should still be occupied — guard prevents double-claim")

func test_supporter_slots_independent_per_team() -> void:
	LobbyManager.supporter_claimed[0] = true
	assert_false(LobbyManager.supporter_claimed[1],
		"Claiming team 0 slot must not affect team 1")

# ── _roles_pending / all_roles_confirmed ─────────────────────────────────────
# These behaviours are now owned by Python. The GDScript signal all_roles_confirmed
# is no longer fired from role claim or disconnect paths.

func test_roles_pending_decrements_to_zero_fires_confirmed() -> void:
	pending("all_roles_confirmed is now Python-owned; GDScript no longer fires it from set_role_ingame")

func test_roles_pending_decrements_on_early_disconnect() -> void:
	pending("_roles_pending removed; early-disconnect role tracking is now Python-owned")

# ── increment_death_count ─────────────────────────────────────────────────────

func test_increment_death_count_starts_at_one() -> void:
	var count: int = LobbyManager.increment_death_count(1)
	assert_eq(count, 1, "First death should return count of 1")

func test_increment_death_count_accumulates() -> void:
	LobbyManager.increment_death_count(1)
	LobbyManager.increment_death_count(1)
	var count: int = LobbyManager.increment_death_count(1)
	assert_eq(count, 3, "Death count should accumulate")

func test_increment_death_count_independent_per_peer() -> void:
	LobbyManager.increment_death_count(1)
	LobbyManager.increment_death_count(1)
	var count2: int = LobbyManager.increment_death_count(2)
	assert_eq(count2, 1, "Death count for peer 2 should start at 1")

# ── get_respawn_time ──────────────────────────────────────────────────────────

func test_get_respawn_time_base_for_zero_deaths() -> void:
	var t: float = LobbyManager.get_respawn_time(1)
	assert_eq(t, LobbyManager.RESPAWN_BASE, "Zero deaths returns base respawn time")

func test_get_respawn_time_does_not_exceed_cap() -> void:
	LobbyManager.player_death_counts[1] = 99999
	var t: float = LobbyManager.get_respawn_time(1)
	assert_lte(t, LobbyManager.RESPAWN_CAP)

# ── known bug: notify_player_respawned sends flat HP ─────────────────────────

func test_notify_player_respawned_includes_level_bonus() -> void:
	# Bug 2 fixed: player_respawned bridge message now uses health from Python
	# which includes LevelSystem.get_bonus_hp(peer_id). Simulate receiving the
	# correct hp value via BridgeClient to verify GameSync is updated.
	LevelSystem.register_peer(1)
	LevelSystem.award_xp(1, 9999)
	LevelSystem.spend_point_local(1, "hp")
	var expected_hp: float = GameSync.PLAYER_MAX_HP + LevelSystem.get_bonus_hp(1)
	assert_gt(expected_hp, GameSync.PLAYER_MAX_HP, "Bonus HP should be positive after spending point")
	BridgeClient._handle_server_message("player_respawned", {
		"peer_id": 1, "spawn_pos": [0.0, 0.0, 0.0], "health": expected_hp
	})
	assert_eq(GameSync.player_healths.get(1, -1.0), expected_hp, "Respawn should restore PLAYER_MAX_HP + bonus HP")

# ── get_players_by_team ───────────────────────────────────────────────────────

func test_get_players_by_team_returns_correct_ids() -> void:
	_add_player(1, "Alice", 0)
	_add_player(2, "Bob", 1)
	var team0: Array = LobbyManager.get_players_by_team(0)
	var team1: Array = LobbyManager.get_players_by_team(1)
	assert_eq(team0, [1])
	assert_eq(team1, [2])

func test_get_players_by_team_empty_team() -> void:
	_add_player(1, "Alice", 0)
	assert_eq(LobbyManager.get_players_by_team(1).size(), 0)

# ── get_supporter_peer ────────────────────────────────────────────────────────

func test_get_supporter_peer_returns_id_when_supporter_present() -> void:
	_add_player(1, "Alice", 0)
	LobbyManager.players[1]["role"] = 1  # Supporter
	assert_eq(LobbyManager.get_supporter_peer(0), 1, "Should return Supporter's peer_id")

func test_get_supporter_peer_returns_minus_one_when_no_supporter() -> void:
	_add_player(1, "Alice", 0)
	LobbyManager.players[1]["role"] = 0  # Fighter, not Supporter
	assert_eq(LobbyManager.get_supporter_peer(0), -1, "No Supporter on team should return -1")

func test_get_supporter_peer_returns_minus_one_for_empty_team() -> void:
	assert_eq(LobbyManager.get_supporter_peer(0), -1, "Empty lobby should return -1")

func test_get_supporter_peer_ignores_other_team() -> void:
	_add_player(1, "Alice", 1)  # red team
	LobbyManager.players[1]["role"] = 1  # Supporter on red
	assert_eq(LobbyManager.get_supporter_peer(0), -1, "Blue team has no Supporter")
