# test_autoload_reset.gd
# Tier 1 — verifies that each autoload reset() method returns state to a
# clean baseline, matching the exact post-leave_game() expectations.
extends GutTest

# ── GameSync.reset() ──────────────────────────────────────────────────────────

func test_game_sync_reset_clears_healths() -> void:
	GameSync.player_healths[1] = 50.0
	GameSync.reset()
	assert_true(GameSync.player_healths.is_empty(), "player_healths cleared after reset")

func test_game_sync_reset_clears_teams() -> void:
	GameSync.player_teams[1] = 0
	GameSync.reset()
	assert_true(GameSync.player_teams.is_empty(), "player_teams cleared after reset")

func test_game_sync_reset_clears_dead() -> void:
	GameSync.player_dead[1] = true
	GameSync.reset()
	assert_true(GameSync.player_dead.is_empty(), "player_dead cleared after reset")

func test_game_sync_reset_clears_ammo_and_weapon() -> void:
	GameSync.player_reserve_ammo[1] = 30
	GameSync.player_weapon_type[1] = "rifle"
	GameSync.reset()
	assert_true(GameSync.player_reserve_ammo.is_empty(), "reserve_ammo cleared after reset")
	assert_true(GameSync.player_weapon_type.is_empty(), "weapon_type cleared after reset")

func test_game_sync_reset_zeroes_seed() -> void:
	GameSync.game_seed = 12345
	GameSync.reset()
	assert_eq(GameSync.game_seed, 0, "game_seed reset to 0")

func test_game_sync_reset_restores_spawn_positions() -> void:
	GameSync.player_spawn_positions.clear()
	GameSync.reset()
	assert_true(GameSync.player_spawn_positions.has(0), "spawn pos team 0 restored")
	assert_true(GameSync.player_spawn_positions.has(1), "spawn pos team 1 restored")
	assert_eq(GameSync.player_spawn_positions[0], Vector3(0.0, 0.0, 82.0), "team 0 spawn correct")
	assert_eq(GameSync.player_spawn_positions[1], Vector3(0.0, 0.0, -82.0), "team 1 spawn correct")

# ── TeamData.reset() ──────────────────────────────────────────────────────────

func test_team_data_reset_restores_starting_points() -> void:
	TeamData.team_points[0] = 200
	TeamData.team_points[1] = 0
	TeamData.reset()
	assert_eq(TeamData.get_points(0), 75, "team 0 reset to 75")
	assert_eq(TeamData.get_points(1), 75, "team 1 reset to 75")

# ── TeamLives.reset() ─────────────────────────────────────────────────────────

func test_team_lives_reset_restores_lives() -> void:
	TeamLives.blue_lives = 0
	TeamLives.red_lives  = 0
	TeamLives.reset()
	assert_eq(TeamLives.blue_lives, ClientSettings.lives_per_team, "blue lives restored")
	assert_eq(TeamLives.red_lives,  ClientSettings.lives_per_team, "red lives restored")

# ── LobbyManager.reset() ─────────────────────────────────────────────────────

func test_lobby_manager_reset_clears_players() -> void:
	LobbyManager.players[1] = {"name": "Test", "team": 0, "role": -1, "ready": false, "avatar_char": ""}
	LobbyManager.reset()
	assert_true(LobbyManager.players.is_empty(), "players dict cleared after reset")

func test_lobby_manager_reset_clears_game_started() -> void:
	LobbyManager.game_started = true
	LobbyManager.reset()
	assert_false(LobbyManager.game_started, "game_started reset to false")

func test_lobby_manager_reset_resets_supporter_claimed() -> void:
	LobbyManager.supporter_claimed[0] = true
	LobbyManager.supporter_claimed[1] = true
	LobbyManager.reset()
	assert_false(LobbyManager.supporter_claimed[0], "supporter_claimed[0] reset")
	assert_false(LobbyManager.supporter_claimed[1], "supporter_claimed[1] reset")

func test_lobby_manager_reset_clears_death_counts() -> void:
	LobbyManager.player_death_counts[1] = 5
	LobbyManager.reset()
	assert_true(LobbyManager.player_death_counts.is_empty(), "death counts cleared after reset")

func test_lobby_manager_reset_clears_ai_supporter_teams() -> void:
	LobbyManager.ai_supporter_teams.append(0)
	LobbyManager.reset()
	assert_true(LobbyManager.ai_supporter_teams.is_empty(), "ai_supporter_teams cleared after reset")

func test_lobby_manager_reset_clears_can_start() -> void:
	LobbyManager._can_start = true
	LobbyManager.reset()
	assert_false(LobbyManager._can_start, "_can_start reset to false")

# ── after_each: restore clean state for other test files ──────────────────────

func after_each() -> void:
	GameSync.reset()
	TeamData.reset()
	TeamLives.reset()
	LobbyManager.reset()
	LevelSystem.clear_all()
