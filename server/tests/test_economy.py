"""Tests for server/economy.py — TeamEconomy class."""

from server.economy import TeamEconomy

# ── Fixture helper ────────────────────────────────────────────────────────────


def make() -> TeamEconomy:
    return TeamEconomy()


# ── Starting state ────────────────────────────────────────────────────────────


def test_starting_points_blue():
    assert make().get_points(0) == TeamEconomy.STARTING_POINTS


def test_starting_points_red():
    assert make().get_points(1) == TeamEconomy.STARTING_POINTS


def test_invalid_team_get_returns_zero():
    e = make()
    assert e.get_points(-1) == 0
    assert e.get_points(2) == 0


# ── add_points ────────────────────────────────────────────────────────────────


def test_add_points():
    e = make()
    e.add_points(0, 10)
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS + 10


def test_add_points_does_not_affect_other_team():
    e = make()
    e.add_points(0, 10)
    assert e.get_points(1) == TeamEconomy.STARTING_POINTS


def test_add_points_invalid_team_is_noop():
    e = make()
    e.add_points(5, 999)
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS


# ── spend_points ──────────────────────────────────────────────────────────────


def test_spend_points_success():
    e = make()
    assert e.spend_points(0, 25) is True
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS - 25


def test_spend_points_exact_balance():
    e = make()
    assert e.spend_points(0, TeamEconomy.STARTING_POINTS) is True
    assert e.get_points(0) == 0


def test_spend_points_insufficient_funds():
    e = make()
    assert e.spend_points(0, TeamEconomy.STARTING_POINTS + 1) is False
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS


def test_spend_points_invalid_team():
    e = make()
    assert e.spend_points(99, 10) is False


def test_spend_points_does_not_affect_other_team():
    e = make()
    e.spend_points(1, 10)
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS


# ── sync ──────────────────────────────────────────────────────────────────────


def test_sync_sets_both_teams():
    e = make()
    e.sync(200, 300)
    assert e.get_points(0) == 200
    assert e.get_points(1) == 300


# ── passive income ────────────────────────────────────────────────────────────


def test_passive_income_starts_zero():
    assert make().get_passive_income(0) == 0


def test_add_passive_income():
    e = make()
    e.add_passive_income(0, 5)
    assert e.get_passive_income(0) == 5


def test_add_passive_income_accumulates():
    e = make()
    e.add_passive_income(0, 3)
    e.add_passive_income(0, 7)
    assert e.get_passive_income(0) == 10


def test_passive_income_invalid_team():
    e = make()
    e.add_passive_income(-1, 99)
    assert e.get_passive_income(-1) == 0


def test_payout_adds_to_points_and_resets():
    e = make()
    e.add_passive_income(0, 12)
    paid = e.payout_passive_income(0)
    assert paid == 12
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS + 12
    assert e.get_passive_income(0) == 0


def test_payout_zero_income_returns_zero():
    e = make()
    paid = e.payout_passive_income(0)
    assert paid == 0
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS


def test_payout_invalid_team_returns_zero():
    e = make()
    assert e.payout_passive_income(5) == 0


# ── reset ─────────────────────────────────────────────────────────────────────


def test_reset_restores_starting_points():
    e = make()
    e.spend_points(0, 50)
    e.add_passive_income(1, 10)
    e.reset()
    assert e.get_points(0) == TeamEconomy.STARTING_POINTS
    assert e.get_points(1) == TeamEconomy.STARTING_POINTS
    assert e.get_passive_income(0) == 0
    assert e.get_passive_income(1) == 0
