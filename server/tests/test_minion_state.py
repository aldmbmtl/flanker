"""
test_minion_state.py — Unit tests for server/minion_state.py (Phase 4).

Covers all branches of MinionStateManager: spawn_wave, damage_minion,
clear_wave, reset, and the injected-callable side-effects.
"""

import pytest

from server.minion_state import (
    MinionDamagedUpdate,
    MinionDiedUpdate,
    MinionState,
    MinionStateManager,
    MinionWaveSpawnedUpdate,
)

# ── Helpers ───────────────────────────────────────────────────────────────────

BLUE = 0
RED = 1


def make_manager(**kwargs) -> MinionStateManager:
    return MinionStateManager(**kwargs)


# ── spawn_wave ────────────────────────────────────────────────────────────────


def test_spawn_wave_unknown_type_returns_empty():
    m = make_manager()
    assert m.spawn_wave(BLUE, 0, "dragon", 3) == []


def test_spawn_wave_zero_count_returns_empty():
    m = make_manager()
    assert m.spawn_wave(BLUE, 0, "standard", 0) == []


def test_spawn_wave_negative_count_returns_empty():
    m = make_manager()
    assert m.spawn_wave(BLUE, 0, "standard", -1) == []


def test_spawn_wave_returns_wave_update():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 3)
    assert len(r) == 1
    u = r[0]
    assert isinstance(u, MinionWaveSpawnedUpdate)
    assert u.team == BLUE
    assert u.lane == 0
    assert u.minion_type == "standard"
    assert len(u.minion_ids) == 3


def test_spawn_wave_ids_are_unique():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 5)
    ids = r[0].minion_ids
    assert len(ids) == len(set(ids))


def test_spawn_wave_minions_stored():
    m = make_manager()
    m.spawn_wave(BLUE, 0, "standard", 2)
    assert m.count() == 2


def test_spawn_wave_sets_correct_health():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    state = m.get_minion(mid)
    assert state.health == pytest.approx(60.0)  # standard max_health
    assert state.max_health == pytest.approx(60.0)


def test_spawn_wave_sets_team_and_lane():
    m = make_manager()
    r = m.spawn_wave(RED, 2, "cannon", 1)
    mid = r[0].minion_ids[0]
    state = m.get_minion(mid)
    assert state.team == RED
    assert state.lane == 2


def test_spawn_two_waves_accumulate_ids():
    m = make_manager()
    r1 = m.spawn_wave(BLUE, 0, "standard", 2)
    r2 = m.spawn_wave(RED, 1, "cannon", 2)
    all_ids = r1[0].minion_ids + r2[0].minion_ids
    assert len(set(all_ids)) == 4
    assert m.count() == 4


def test_spawn_cannon_minion():
    m = make_manager()
    r = m.spawn_wave(BLUE, 1, "cannon", 1)
    assert isinstance(r[0], MinionWaveSpawnedUpdate)
    mid = r[0].minion_ids[0]
    assert m.get_minion(mid).max_health == pytest.approx(100.0)


def test_spawn_healer_minion():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "healer", 1)
    assert isinstance(r[0], MinionWaveSpawnedUpdate)


# ── get_minion ────────────────────────────────────────────────────────────────


def test_get_minion_unknown_returns_none():
    m = make_manager()
    assert m.get_minion(9999) is None


def test_get_minion_returns_state():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    state = m.get_minion(mid)
    assert isinstance(state, MinionState)
    assert state.minion_id == mid


# ── damage_minion ─────────────────────────────────────────────────────────────


def test_damage_unknown_minion_returns_empty():
    m = make_manager()
    assert m.damage_minion(9999, 10.0, RED) == []


def test_damage_friendly_fire_returns_empty():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    assert m.damage_minion(mid, 10.0, BLUE) == []


def test_damage_returns_damaged_update():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    result = m.damage_minion(mid, 20.0, RED)
    assert len(result) == 1
    u = result[0]
    assert isinstance(u, MinionDamagedUpdate)
    assert u.minion_id == mid
    assert u.health == pytest.approx(40.0)


def test_damage_reduces_stored_health():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    m.damage_minion(mid, 30.0, RED)
    assert m.get_minion(mid).health == pytest.approx(30.0)


def test_damage_kills_minion():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    result = m.damage_minion(mid, 9999.0, RED, shooter_peer_id=3)
    assert len(result) == 2
    assert isinstance(result[0], MinionDamagedUpdate)
    assert result[0].health == pytest.approx(0.0)
    assert isinstance(result[1], MinionDiedUpdate)
    assert result[1].minion_id == mid
    assert result[1].minion_type == "standard"
    assert result[1].team == BLUE
    assert result[1].killer_peer_id == 3


def test_damage_removes_killed_minion_from_live():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    m.damage_minion(mid, 9999.0, RED)
    assert m.get_minion(mid) is None
    assert m.count() == 0


def test_damage_awards_xp_on_kill():
    xp_log = []
    m = make_manager(award_xp_fn=lambda pid, amt: xp_log.append((pid, amt)))
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    m.damage_minion(mid, 9999.0, RED, shooter_peer_id=7)
    assert (7, 10) in xp_log


def test_damage_no_xp_when_no_shooter():
    xp_log = []
    m = make_manager(award_xp_fn=lambda pid, amt: xp_log.append((pid, amt)))
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    m.damage_minion(mid, 9999.0, RED, shooter_peer_id=-1)
    assert xp_log == []


def test_damage_awards_team_points_on_kill():
    pts_log = []
    m = make_manager(add_team_points_fn=lambda t, a: pts_log.append((t, a)))
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    m.damage_minion(mid, 9999.0, RED)
    # standard kill_points=5, killer_team = 1 - BLUE = RED
    assert (RED, 5) in pts_log


def test_damage_cannon_kill_points():
    pts_log = []
    m = make_manager(add_team_points_fn=lambda t, a: pts_log.append((t, a)))
    r = m.spawn_wave(RED, 0, "cannon", 1)
    mid = r[0].minion_ids[0]
    m.damage_minion(mid, 9999.0, BLUE)
    # cannon kill_points=10, killer_team = 1 - RED = BLUE
    assert (BLUE, 10) in pts_log


def test_damage_does_not_go_below_zero():
    m = make_manager()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    mid = r[0].minion_ids[0]
    result = m.damage_minion(mid, 9999.0, RED)
    assert result[0].health == pytest.approx(0.0)


# ── clear_wave ────────────────────────────────────────────────────────────────


def test_clear_wave_empty_returns_empty():
    m = make_manager()
    assert m.clear_wave(BLUE) == []


def test_clear_wave_removes_only_target_team():
    m = make_manager()
    m.spawn_wave(BLUE, 0, "standard", 2)
    m.spawn_wave(RED, 0, "standard", 3)
    updates = m.clear_wave(BLUE)
    assert len(updates) == 2
    assert all(isinstance(u, MinionDiedUpdate) for u in updates)
    assert all(u.team == BLUE for u in updates)
    # Red minions survive
    assert m.count() == 3


def test_clear_wave_sets_killer_minus_one():
    m = make_manager()
    m.spawn_wave(BLUE, 0, "standard", 1)
    updates = m.clear_wave(BLUE)
    assert updates[0].killer_peer_id == -1


def test_clear_wave_removes_from_live():
    m = make_manager()
    m.spawn_wave(BLUE, 0, "standard", 3)
    m.clear_wave(BLUE)
    assert m.count() == 0


# ── reset ─────────────────────────────────────────────────────────────────────


def test_reset_clears_all_minions():
    m = make_manager()
    m.spawn_wave(BLUE, 0, "standard", 5)
    m.spawn_wave(RED, 1, "cannon", 3)
    m.reset()
    assert m.count() == 0


def test_reset_resets_id_counter():
    m = make_manager()
    m.spawn_wave(BLUE, 0, "standard", 3)
    m.reset()
    r = m.spawn_wave(BLUE, 0, "standard", 1)
    # After reset next_id should be 1 again
    assert r[0].minion_ids[0] == 1


# ── get_live_minions ──────────────────────────────────────────────────────────


def test_get_live_minions_returns_all():
    m = make_manager()
    m.spawn_wave(BLUE, 0, "standard", 2)
    m.spawn_wave(RED, 1, "cannon", 1)
    live = m.get_live_minions()
    assert len(live) == 3
    assert all(isinstance(x, MinionState) for x in live)
