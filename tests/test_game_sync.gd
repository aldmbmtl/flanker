# test_game_sync.gd
# Tier 1 — unit tests for GameSync autoload.
# OfflineMultiplayerPeer is the default — multiplayer.is_server() == true,
# so the server-authoritative code paths run without guards firing.
extends GutTest

func before_each() -> void:
	# Reset GameSync to a pristine state
	GameSync.player_healths.clear()
	GameSync.player_teams.clear()
	GameSync.player_dead.clear()
	GameSync.respawn_countdown.clear()
	LobbyManager.player_death_counts.clear()
	LobbyManager.players.clear()
	LevelSystem.clear_all()

# ── get/set player health ─────────────────────────────────────────────────────

func test_get_player_health_default_is_max() -> void:
	var hp: float = GameSync.get_player_health(42)
	assert_eq(hp, GameSync.PLAYER_MAX_HP, "Unknown peer returns max HP")

func test_set_player_health_stores_and_signals() -> void:
	watch_signals(GameSync)
	GameSync.set_player_health(1, 75.0)
	assert_eq(GameSync.get_player_health(1), 75.0, "Health stored correctly")
	assert_signal_emitted(GameSync, "player_health_changed", "player_health_changed should fire")
	var params: Array = get_signal_parameters(GameSync, "player_health_changed")
	assert_eq(params[1], 75.0, "Signal carries correct HP value")

# ── get/set player team ───────────────────────────────────────────────────────

func test_get_player_team_unknown_returns_minus_one() -> void:
	assert_eq(GameSync.get_player_team(999), -1)

func test_set_and_get_player_team() -> void:
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	assert_eq(GameSync.get_player_team(1), 0)
	assert_eq(GameSync.get_player_team(2), 1)

# ── damage_player ─────────────────────────────────────────────────────────────

func test_damage_player_reduces_health() -> void:
	GameSync.set_player_health(1, 100.0)
	var remaining: float = GameSync.damage_player(1, 30.0, 1)
	assert_eq(remaining, 70.0, "HP should drop by damage amount")
	assert_eq(GameSync.get_player_health(1), 70.0)

func test_damage_player_emits_health_changed_signal() -> void:
	GameSync.set_player_health(1, 100.0)
	watch_signals(GameSync)
	GameSync.damage_player(1, 10.0, 1)
	assert_signal_emitted(GameSync, "player_health_changed")

func test_damage_player_to_zero_marks_dead() -> void:
	GameSync.set_player_health(1, 50.0)
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	GameSync.damage_player(1, 50.0, 1)
	assert_true(GameSync.player_dead.get(1, false), "Player should be marked dead at 0 HP")

func test_damage_player_to_zero_emits_died_signal() -> void:
	GameSync.set_player_health(1, 50.0)
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	watch_signals(GameSync)
	GameSync.damage_player(1, 50.0, 1)
	assert_signal_emitted(GameSync, "player_died", "player_died signal should fire on death")

func test_damage_player_already_dead_is_ignored() -> void:
	GameSync.set_player_health(1, 0.0)
	GameSync.player_dead[1] = true
	var hp_before: float = GameSync.get_player_health(1)
	GameSync.damage_player(1, 50.0, 1)
	assert_eq(GameSync.get_player_health(1), hp_before, "Dead player takes no damage")

func test_damage_player_sets_respawn_countdown() -> void:
	GameSync.set_player_health(1, 30.0)
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	GameSync.damage_player(1, 30.0, 1)
	assert_true(GameSync.respawn_countdown.has(1), "Respawn countdown should be set on death")
	assert_gt(GameSync.respawn_countdown[1], 0.0, "Respawn countdown must be positive")

# ── respawn timer escalation ──────────────────────────────────────────────────

func test_respawn_time_escalates_with_deaths() -> void:
	# First death: RESPAWN_BASE + 0 * RESPAWN_INCREMENT
	var t0: float = LobbyManager.get_respawn_time(1)
	LobbyManager.player_death_counts[1] = 0
	var first: float = LobbyManager.get_respawn_time(1)
	LobbyManager.player_death_counts[1] = 3
	var third: float = LobbyManager.get_respawn_time(1)
	assert_true(third >= first, "Respawn time should not decrease with more deaths")

func test_respawn_time_capped_at_respawn_cap() -> void:
	LobbyManager.player_death_counts[1] = 9999
	var t: float = LobbyManager.get_respawn_time(1)
	assert_lte(t, LobbyManager.RESPAWN_CAP, "Respawn time must not exceed RESPAWN_CAP")

# ── respawn_player ────────────────────────────────────────────────────────────

func test_respawn_player_clears_dead_flag() -> void:
	GameSync.set_player_health(1, 0.0)
	GameSync.player_dead[1] = true
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	GameSync.respawn_player(1)
	assert_false(GameSync.player_dead.get(1, false), "Dead flag should be cleared on respawn")

func test_respawn_player_restores_health() -> void:
	GameSync.set_player_health(1, 0.0)
	GameSync.player_dead[1] = true
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	GameSync.respawn_player(1)
	assert_gt(GameSync.get_player_health(1), 0.0, "Health should be restored on respawn")

func test_respawn_player_includes_level_bonus_hp() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.spend_point_local(1, "hp")  # no-op if 0 points; just ensure no error
	GameSync.set_player_team(1, 0)
	GameSync.player_dead[1] = true
	GameSync.respawn_player(1)
	var expected: float = GameSync.PLAYER_MAX_HP + LevelSystem.get_bonus_hp(1)
	assert_eq(GameSync.get_player_health(1), expected,
		"Respawned HP should equal PLAYER_MAX_HP + level bonus")

func test_respawn_player_emits_signal() -> void:
	GameSync.set_player_team(1, 0)
	GameSync.player_dead[1] = true
	LevelSystem.register_peer(1)
	watch_signals(GameSync)
	GameSync.respawn_player(1)
	assert_signal_emitted(GameSync, "player_respawned", "player_respawned signal should fire")

func test_respawn_player_removes_countdown() -> void:
	GameSync.set_player_team(1, 0)
	GameSync.player_dead[1] = true
	GameSync.respawn_countdown[1] = 5.0
	LevelSystem.register_peer(1)
	GameSync.respawn_player(1)
	assert_false(GameSync.respawn_countdown.has(1), "Countdown entry should be erased after respawn")

# ── spawn positions ───────────────────────────────────────────────────────────

func test_team_0_spawns_at_positive_z() -> void:
	var pos: Vector3 = GameSync.get_spawn_position(0)
	assert_gt(pos.z, 0.0, "Team 0 (blue) spawns at positive Z")

func test_team_1_spawns_at_negative_z() -> void:
	var pos: Vector3 = GameSync.get_spawn_position(1)
	assert_lt(pos.z, 0.0, "Team 1 (red) spawns at negative Z")

# ── _sender_id pattern (singleplayer) ────────────────────────────────────────

func test_sender_id_returns_1_when_offline() -> void:
	# In OfflineMultiplayerPeer, get_remote_sender_id() returns 0.
	# LobbyManager._sender_id() should map 0 -> 1 (server peer id).
	var id: int = LobbyManager._sender_id()
	assert_eq(id, 1, "_sender_id() should return 1 in offline/singleplayer context")

# ── ammo sync ─────────────────────────────────────────────────────────────────

func test_set_player_reserve_ammo_emits_signal() -> void:
	watch_signals(GameSync)
	GameSync.set_player_reserve_ammo(1, 30, "rifle")
	assert_signal_emitted(GameSync, "player_ammo_changed", "player_ammo_changed should fire")
	var params: Array = get_signal_parameters(GameSync, "player_ammo_changed")
	assert_eq(params[1], 30)

func test_get_player_reserve_ammo_unknown_returns_999() -> void:
	assert_eq(GameSync.get_player_reserve_ammo(999), 999)

# ── Supporter XP from tower/minion kills ──────────────────────────────────────

func test_tower_kill_awards_xp_to_supporter_on_attacking_team() -> void:
	# Peer 2 is a Supporter on team 0 (the attacking team).
	LobbyManager.register_player_local(2, "Sup")
	LobbyManager.players[2]["team"] = 0
	LobbyManager.players[2]["role"] = 1
	LevelSystem.register_peer(2)
	# Peer 1 is the victim on team 1.
	GameSync.set_player_health(1, 50.0)
	var xp_before: int = LevelSystem.get_xp(2)
	# No player peer killed peer 1 (killer_peer_id = -1), source_team = 0 (tower's team).
	GameSync.damage_player(1, 9999.0, 0, -1)
	var xp_after: int = LevelSystem.get_xp(2)
	assert_gt(xp_after, xp_before, "Supporter should receive XP when team tower kills a player")

func test_player_kill_does_not_award_xp_to_supporter() -> void:
	# Peer 2 is a Supporter on team 0.
	LobbyManager.register_player_local(2, "Sup")
	LobbyManager.players[2]["team"] = 0
	LobbyManager.players[2]["role"] = 1
	LevelSystem.register_peer(2)
	# Peer 3 is a Fighter on team 0 who gets the kill.
	LevelSystem.register_peer(3)
	GameSync.set_player_health(1, 50.0)
	var sup_xp_before: int = LevelSystem.get_xp(2)
	# Valid player kill: killer_peer_id = 3.
	GameSync.damage_player(1, 9999.0, 0, 3)
	var sup_xp_after: int = LevelSystem.get_xp(2)
	assert_eq(sup_xp_after, sup_xp_before, "Supporter should not receive XP when a player gets the kill")

func test_no_supporter_on_team_does_not_crash_on_tower_kill() -> void:
	# No Supporter registered for team 0.
	GameSync.set_player_health(1, 50.0)
	# Should not crash; XP simply goes uncredited.
	GameSync.damage_player(1, 9999.0, 0, -1)
	assert_true(GameSync.player_dead.get(1, false), "Player should be dead after lethal damage")
