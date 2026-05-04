# test_team_data.gd
# Tier 1 — unit tests for TeamData autoload.
# TeamData is a plain Node with no networking; tests run against the live autoload.
extends GutTest

func before_each() -> void:
	# Reset to a clean known state before every test
	TeamData.team_points[0] = 0
	TeamData.team_points[1] = 0
	TeamData.passive_income[0] = 0
	TeamData.passive_income[1] = 0

# ── add_points ────────────────────────────────────────────────────────────────

func test_add_points_increases_balance() -> void:
	TeamData.add_points(0, 50)
	assert_eq(TeamData.get_points(0), 50, "Team 0 should have 50 points after add")

func test_add_points_independent_per_team() -> void:
	TeamData.add_points(0, 30)
	TeamData.add_points(1, 70)
	assert_eq(TeamData.get_points(0), 30, "Team 0 unaffected by team 1 add")
	assert_eq(TeamData.get_points(1), 70, "Team 1 unaffected by team 0 add")

func test_add_points_out_of_range_ignored() -> void:
	TeamData.add_points(2, 100)   # team 2 does not exist
	TeamData.add_points(-1, 100)  # negative team
	assert_eq(TeamData.get_points(0), 0, "Invalid team add should not affect team 0")
	assert_eq(TeamData.get_points(1), 0, "Invalid team add should not affect team 1")

func test_add_points_accumulates() -> void:
	TeamData.add_points(0, 10)
	TeamData.add_points(0, 25)
	assert_eq(TeamData.get_points(0), 35, "Multiple adds should accumulate")

# ── spend_points ──────────────────────────────────────────────────────────────

func test_spend_points_returns_true_and_deducts() -> void:
	TeamData.team_points[0] = 50
	var ok: bool = TeamData.spend_points(0, 25)
	assert_true(ok, "spend_points should return true when balance is sufficient")
	assert_eq(TeamData.get_points(0), 25, "Balance should be deducted")

func test_spend_points_exact_balance() -> void:
	TeamData.team_points[0] = 25
	var ok: bool = TeamData.spend_points(0, 25)
	assert_true(ok, "Should be able to spend entire balance")
	assert_eq(TeamData.get_points(0), 0, "Balance should reach zero")

func test_spend_points_insufficient_returns_false() -> void:
	TeamData.team_points[0] = 10
	var ok: bool = TeamData.spend_points(0, 25)
	assert_false(ok, "spend_points should return false when balance is insufficient")
	assert_eq(TeamData.get_points(0), 10, "Balance should be unchanged on failure")

func test_spend_points_zero_balance_fails() -> void:
	var ok: bool = TeamData.spend_points(1, 1)
	assert_false(ok, "Cannot spend from zero balance")

func test_spend_points_out_of_range_returns_false() -> void:
	var ok: bool = TeamData.spend_points(5, 10)
	assert_false(ok, "Out-of-range team spend should return false")

# ── get_points ────────────────────────────────────────────────────────────────

func test_get_points_out_of_range_returns_zero() -> void:
	assert_eq(TeamData.get_points(99), 0, "Out-of-range team returns 0")
	assert_eq(TeamData.get_points(-1), 0, "Negative team returns 0")

# ── sync_from_server ──────────────────────────────────────────────────────────

func test_sync_from_server_overwrites_both_teams() -> void:
	TeamData.team_points[0] = 999
	TeamData.team_points[1] = 999
	TeamData.sync_from_server(42, 77)
	assert_eq(TeamData.get_points(0), 42, "Blue team synced correctly")
	assert_eq(TeamData.get_points(1), 77, "Red team synced correctly")

func test_sync_from_server_zero_values() -> void:
	TeamData.team_points[0] = 100
	TeamData.sync_from_server(0, 0)
	assert_eq(TeamData.get_points(0), 0, "Sync to zero is valid")
	assert_eq(TeamData.get_points(1), 0, "Sync to zero is valid")

# ── initial state ─────────────────────────────────────────────────────────────

func test_both_teams_start_at_known_state_after_reset() -> void:
	# before_each sets both to 0 — verify our test isolation works
	assert_eq(TeamData.get_points(0), 0)
	assert_eq(TeamData.get_points(1), 0)

# ── passive_income ────────────────────────────────────────────────────────────

func test_get_passive_income_returns_zero_by_default() -> void:
	assert_eq(TeamData.get_passive_income(0), 0,
		"Team 0 passive income must start at 0")
	assert_eq(TeamData.get_passive_income(1), 0,
		"Team 1 passive income must start at 0")

func test_get_passive_income_out_of_range_returns_zero() -> void:
	assert_eq(TeamData.get_passive_income(99), 0,
		"Out-of-range team must return 0")
	assert_eq(TeamData.get_passive_income(-1), 0,
		"Negative team must return 0")

func test_add_passive_income_is_noop() -> void:
	# add_passive_income is server-authoritative — client calls are ignored.
	TeamData.add_passive_income(0, 99)
	TeamData.add_passive_income(1, 99)
	assert_eq(TeamData.get_passive_income(0), 0,
		"add_passive_income must be a no-op on the client")
	assert_eq(TeamData.get_passive_income(1), 0,
		"add_passive_income must be a no-op on the client")

# ── sync_income_from_server ───────────────────────────────────────────────────

func test_sync_income_from_server_sets_both_teams() -> void:
	TeamData.sync_income_from_server(3, 7)
	assert_eq(TeamData.get_passive_income(0), 3,
		"sync_income_from_server must set team 0 income rate")
	assert_eq(TeamData.get_passive_income(1), 7,
		"sync_income_from_server must set team 1 income rate")

func test_sync_income_from_server_overwrites_previous() -> void:
	TeamData.sync_income_from_server(5, 5)
	TeamData.sync_income_from_server(2, 9)
	assert_eq(TeamData.get_passive_income(0), 2,
		"sync_income_from_server must overwrite previous team 0 value")
	assert_eq(TeamData.get_passive_income(1), 9,
		"sync_income_from_server must overwrite previous team 1 value")

func test_sync_income_from_server_zero_clears_income() -> void:
	TeamData.sync_income_from_server(4, 6)
	TeamData.sync_income_from_server(0, 0)
	assert_eq(TeamData.get_passive_income(0), 0,
		"sync_income_from_server(0,0) must zero team 0 income")
	assert_eq(TeamData.get_passive_income(1), 0,
		"sync_income_from_server(0,0) must zero team 1 income")

func test_reset_zeroes_passive_income() -> void:
	TeamData.sync_income_from_server(10, 20)
	TeamData.reset()
	assert_eq(TeamData.get_passive_income(0), 0,
		"reset() must zero team 0 passive income")
	assert_eq(TeamData.get_passive_income(1), 0,
		"reset() must zero team 1 passive income")

func test_reset_also_restores_team_points() -> void:
	TeamData.team_points[0] = 999
	TeamData.team_points[1] = 999
	TeamData.reset()
	assert_eq(TeamData.get_points(0), 75,
		"reset() must restore team 0 points to 75")
	assert_eq(TeamData.get_points(1), 75,
		"reset() must restore team 1 points to 75")
