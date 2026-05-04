"""Tests for server/territory.py — 100% line coverage required."""

import pytest

from server.territory import BuildLimitUpdate, Territory, TowerDestroyedByPushUpdate

# ── Helpers ───────────────────────────────────────────────────────────────────


def make_territory():
    return Territory()


def frontmost(lane0, lane1, lane2):
    return [lane0, lane1, lane2]


# ── Initial state ─────────────────────────────────────────────────────────────


def test_initial_push_levels_zero():
    t = make_territory()
    assert t.get_push_level(0) == 0
    assert t.get_push_level(1) == 0


def test_initial_build_limits():
    t = make_territory()
    assert t.get_build_limit(0) == 0.0
    assert t.get_build_limit(1) == 0.0


def test_all_limits_accessible():
    for lvl in range(Territory.MAX_PUSH + 1):
        assert Territory.PUSH_LIMITS_BLUE[lvl] <= 0.0
        assert Territory.PUSH_LIMITS_RED[lvl] >= 0.0


# ── Push ──────────────────────────────────────────────────────────────────────


def test_push_timer_accumulates():
    t = make_territory()
    # team 0: need minion z < 0.0 in all lanes
    fz = frontmost(-5.0, -5.0, -5.0)
    t.tick(10.0, fz, [None, None, None])
    assert t.push_timer[0] == pytest.approx(10.0)


def test_push_fires_at_threshold():
    t = make_territory()
    fz = frontmost(-5.0, -5.0, -5.0)
    updates = t.tick(Territory.PUSH_TIME, fz, [None, None, None])
    assert any(isinstance(u, BuildLimitUpdate) for u in updates)
    assert t.get_push_level(0) == 1


def test_push_update_has_correct_team_and_z():
    t = make_territory()
    fz = frontmost(-5.0, -5.0, -5.0)
    updates = t.tick(Territory.PUSH_TIME, fz, [None, None, None])
    upd = next(u for u in updates if isinstance(u, BuildLimitUpdate))
    assert upd.team == 0
    assert upd.new_level == 1
    assert upd.new_z == Territory.PUSH_LIMITS_BLUE[1]


def test_push_timer_resets_after_level_up():
    t = make_territory()
    fz = frontmost(-5.0, -5.0, -5.0)
    t.tick(Territory.PUSH_TIME, fz, [None, None, None])
    assert t.push_timer[0] == pytest.approx(0.0)


def test_push_does_not_exceed_max():
    t = make_territory()
    t.push_level[0] = Territory.MAX_PUSH
    fz = frontmost(-50.0, -50.0, -50.0)
    updates = t.tick(Territory.PUSH_TIME * 2, fz, [None, None, None])
    assert not any(isinstance(u, BuildLimitUpdate) for u in updates)
    assert t.get_push_level(0) == Territory.MAX_PUSH


def test_push_requires_all_3_lanes():
    t = make_territory()
    # Only 2 lanes covered
    fz = frontmost(-5.0, -5.0, None)
    t.tick(Territory.PUSH_TIME, fz, [None, None, None])
    assert t.get_push_level(0) == 0


def test_push_requires_minion_past_limit():
    t = make_territory()
    # Minion at +5 (wrong side for team 0)
    fz = frontmost(5.0, 5.0, 5.0)
    t.tick(Territory.PUSH_TIME, fz, [None, None, None])
    assert t.get_push_level(0) == 0


def test_push_timer_resets_when_condition_breaks():
    t = make_territory()
    fz = frontmost(-5.0, -5.0, -5.0)
    t.tick(15.0, fz, [None, None, None])
    assert t.push_timer[0] == pytest.approx(15.0)
    # Break the condition
    t.tick(1.0, [None, None, None], [None, None, None])
    assert t.push_timer[0] == pytest.approx(0.0)


def test_push_capped_at_push_time():
    t = make_territory()
    fz = frontmost(-5.0, -5.0, -5.0)
    # Push only up to level 1 then stop
    t.tick(Territory.PUSH_TIME, fz, [None, None, None])
    assert t.push_timer[0] == 0.0
    # Continue pushing — accumulate again
    t.tick(5.0, frontmost(-20.0, -20.0, -20.0), [None, None, None])
    assert t.push_timer[0] == pytest.approx(5.0)


# ── Team 1 (red) push ─────────────────────────────────────────────────────────


def test_team1_push():
    t = make_territory()
    fz1 = frontmost(5.0, 5.0, 5.0)  # red minions pushing into blue (positive z)
    updates = t.tick(Territory.PUSH_TIME, [None, None, None], fz1)
    assert any(isinstance(u, BuildLimitUpdate) and u.team == 1 for u in updates)
    assert t.get_push_level(1) == 1


def test_team1_build_limit_increases():
    t = make_territory()
    fz1 = frontmost(5.0, 5.0, 5.0)
    t.tick(Territory.PUSH_TIME, [None, None, None], fz1)
    assert t.get_build_limit(1) == Territory.PUSH_LIMITS_RED[1]


# ── Rollback ──────────────────────────────────────────────────────────────────


def test_no_rollback_at_level_0():
    t = make_territory()
    # No minions anywhere — rollback condition check, but level is 0
    updates = t.tick(Territory.ROLLBACK_TIME * 2, [None, None, None], [None, None, None])
    assert not any(isinstance(u, BuildLimitUpdate) for u in updates)


def test_rollback_fires_at_threshold():
    t = make_territory()
    t.push_level[0] = 1
    # No minions past limit
    updates = t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None])
    assert any(isinstance(u, BuildLimitUpdate) for u in updates)
    assert t.get_push_level(0) == 0


def test_rollback_update_correct_level_and_z():
    t = make_territory()
    t.push_level[0] = 2
    updates = t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None])
    upd = next(u for u in updates if isinstance(u, BuildLimitUpdate) and u.team == 0)
    assert upd.new_level == 1
    assert upd.new_z == Territory.PUSH_LIMITS_BLUE[1]


def test_rollback_timer_resets():
    t = make_territory()
    t.push_level[0] = 1
    t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None])
    assert t.rollback_timer[0] == pytest.approx(0.0)


def test_rollback_push_timer_also_resets():
    t = make_territory()
    t.push_level[0] = 1
    t.push_timer[0] = 15.0
    t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None])
    assert t.push_timer[0] == pytest.approx(0.0)


def test_rollback_blocked_when_minion_still_past_limit():
    t = make_territory()
    t.push_level[0] = Territory.MAX_PUSH  # already at max — push can't advance further
    cur_limit = t.get_build_limit(0)
    # Minion is still past the current limit (more negative)
    fz = frontmost(cur_limit - 1.0, cur_limit - 1.0, cur_limit - 1.0)
    t.tick(Territory.ROLLBACK_TIME * 2, fz, [None, None, None])
    assert t.get_push_level(0) == Territory.MAX_PUSH  # no rollback — minion still past limit


def test_rollback_blocked_team1_minion_still_past_limit():
    """Covers territory.py:171 — team-1 branch of still_past check."""
    t = make_territory()
    t.push_level[1] = Territory.MAX_PUSH  # already at max — push can't advance
    cur_limit = t.get_build_limit(1)
    # Red minion still past limit (more positive than cur_limit)
    fz1 = frontmost(cur_limit + 1.0, cur_limit + 1.0, cur_limit + 1.0)
    t.tick(Territory.ROLLBACK_TIME * 2, [None, None, None], fz1)
    assert t.get_push_level(1) == Territory.MAX_PUSH


def test_rollback_timer_clears_when_minion_reappears():
    t = make_territory()
    t.push_level[0] = 1
    cur_limit = t.get_build_limit(0)
    # Build rollback timer
    t.tick(Territory.ROLLBACK_TIME * 0.5, [None, None, None], [None, None, None])
    assert t.rollback_timer[0] > 0.0
    # Minion re-appears past limit — timer should reset
    fz = frontmost(cur_limit - 1.0, cur_limit - 1.0, cur_limit - 1.0)
    t.tick(1.0, fz, [None, None, None])
    assert t.rollback_timer[0] == pytest.approx(0.0)


# ── Rollback tower destruction ────────────────────────────────────────────────


def test_rollback_destroys_out_of_bounds_towers():
    t = make_territory()
    t.push_level[0] = 2
    new_limit = Territory.PUSH_LIMITS_BLUE[1]  # rollback target
    # Tower is past the new limit for team 0 (z < new_limit)
    towers = [("TowerA", 0, new_limit - 5.0)]
    updates = t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None], towers=towers)
    destroy_updates = [u for u in updates if isinstance(u, TowerDestroyedByPushUpdate)]
    assert any(u.tower_name == "TowerA" for u in destroy_updates)


def test_rollback_spares_in_bounds_towers():
    t = make_territory()
    t.push_level[0] = 2
    new_limit = Territory.PUSH_LIMITS_BLUE[1]
    # Tower is inside the new limit (z > new_limit for team 0 means safe)
    towers = [("SafeTower", 0, new_limit + 5.0)]
    updates = t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None], towers=towers)
    destroy_updates = [u for u in updates if isinstance(u, TowerDestroyedByPushUpdate)]
    assert not destroy_updates


def test_rollback_ignores_enemy_towers():
    t = make_territory()
    t.push_level[0] = 2
    new_limit = Territory.PUSH_LIMITS_BLUE[1]
    # Tower belongs to enemy (team 1)
    towers = [("EnemyTower", 1, new_limit - 5.0)]
    updates = t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None], towers=towers)
    destroy_updates = [u for u in updates if isinstance(u, TowerDestroyedByPushUpdate)]
    assert not destroy_updates


def test_rollback_team1_out_of_bounds_towers():
    t = make_territory()
    t.push_level[1] = 2
    new_limit = Territory.PUSH_LIMITS_RED[1]
    # Red tower that is past new_limit in +z direction
    towers = [("RedTower", 1, new_limit + 3.0)]
    updates = t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None], towers=towers)
    destroy_updates = [u for u in updates if isinstance(u, TowerDestroyedByPushUpdate)]
    assert any(u.tower_name == "RedTower" for u in destroy_updates)


def test_towers_none_defaults_to_empty():
    t = make_territory()
    t.push_level[0] = 1
    updates = t.tick(Territory.ROLLBACK_TIME, [None, None, None], [None, None, None], towers=None)
    assert isinstance(updates, list)


# ── Reset ─────────────────────────────────────────────────────────────────────


def test_reset():
    t = make_territory()
    t.push_level = [2, 3]
    t.push_timer = [10.0, 20.0]
    t.rollback_timer = [5.0, 7.0]
    t.reset()
    assert t.push_level == [0, 0]
    assert t.push_timer == [0.0, 0.0]
    assert t.rollback_timer == [0.0, 0.0]
