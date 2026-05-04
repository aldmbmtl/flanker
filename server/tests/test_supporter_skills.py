"""Tests for server/skills/supporter.py — 100% line coverage required."""

from server.skills.supporter import (
    BASIC_MINION_TYPE,
    CANNON_MINION_TYPE,
    HEALER_MINION_TYPE,
    MASS_HEAL_AMOUNT,
    MassHealMinionEffect,
    MassHealPlayerEffect,
    MinionFireEffect,
    execute,
)

# ── Helpers ───────────────────────────────────────────────────────────────────


def basic(mid, team=0):
    return {"id": mid, "team": team, "minion_type": BASIC_MINION_TYPE}


def cannon(mid, team=0):
    return {"id": mid, "team": team, "minion_type": CANNON_MINION_TYPE}


def healer(mid, team=0):
    return {"id": mid, "team": team, "minion_type": HEALER_MINION_TYPE}


# ── Unknown node_id ───────────────────────────────────────────────────────────


def test_unknown_node_returns_empty():
    result = execute("totally_unknown", 1, 0, [], [])
    assert result == []


# ── s_basic_t3 (basic barrage) ────────────────────────────────────────────────


def test_basic_barrage_fires_basic_minions():
    minions = [basic(1), basic(2)]
    result = execute("s_basic_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {1, 2}


def test_basic_barrage_ignores_cannon():
    minions = [basic(1), cannon(2)]
    result = execute("s_basic_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {1}


def test_basic_barrage_ignores_healer():
    minions = [basic(1), healer(2)]
    result = execute("s_basic_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {1}


def test_basic_barrage_ignores_enemy_team():
    minions = [basic(1, team=0), basic(2, team=1)]
    result = execute("s_basic_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {1}


def test_basic_barrage_no_minions_returns_empty():
    result = execute("s_basic_t3", 10, 0, [], [])
    assert result == []


def test_basic_barrage_only_fire_effects():
    minions = [basic(1), basic(2)]
    result = execute("s_basic_t3", 10, 0, minions, [])
    assert all(isinstance(e, MinionFireEffect) for e in result)


# ── s_cannon_t3 (cannon barrage) ──────────────────────────────────────────────


def test_cannon_barrage_fires_cannon_minions():
    minions = [cannon(1), cannon(2)]
    result = execute("s_cannon_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {1, 2}


def test_cannon_barrage_ignores_basic():
    minions = [basic(1), cannon(2)]
    result = execute("s_cannon_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {2}


def test_cannon_barrage_ignores_healer():
    minions = [healer(1), cannon(2)]
    result = execute("s_cannon_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {2}


def test_cannon_barrage_ignores_enemy_team():
    minions = [cannon(1, team=0), cannon(2, team=1)]
    result = execute("s_cannon_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MinionFireEffect)}
    assert ids == {1}


def test_cannon_barrage_no_minions_returns_empty():
    result = execute("s_cannon_t3", 10, 0, [], [])
    assert result == []


# ── s_healer_t3 (mass heal) ───────────────────────────────────────────────────


def test_mass_heal_heals_all_friendly_minions():
    minions = [basic(1), cannon(2), healer(3)]
    result = execute("s_healer_t3", 10, 0, minions, [])
    minion_heals = [e for e in result if isinstance(e, MassHealMinionEffect)]
    ids = {e.minion_id for e in minion_heals}
    assert ids == {1, 2, 3}


def test_mass_heal_ignores_enemy_minions():
    minions = [basic(1, team=0), basic(2, team=1)]
    result = execute("s_healer_t3", 10, 0, minions, [])
    ids = {e.minion_id for e in result if isinstance(e, MassHealMinionEffect)}
    assert ids == {1}


def test_mass_heal_heals_friendly_players():
    players = [(5, 0), (6, 0)]
    result = execute("s_healer_t3", 10, 0, [], players)
    pids = {e.peer_id for e in result if isinstance(e, MassHealPlayerEffect)}
    assert pids == {5, 6}


def test_mass_heal_ignores_enemy_players():
    players = [(5, 0), (6, 1)]
    result = execute("s_healer_t3", 10, 0, [], players)
    pids = {e.peer_id for e in result if isinstance(e, MassHealPlayerEffect)}
    assert pids == {5}


def test_mass_heal_correct_amount_minion():
    minions = [basic(1)]
    result = execute("s_healer_t3", 10, 0, minions, [])
    h = next(e for e in result if isinstance(e, MassHealMinionEffect))
    assert h.amount == MASS_HEAL_AMOUNT


def test_mass_heal_correct_amount_player():
    result = execute("s_healer_t3", 10, 0, [], [(5, 0)])
    h = next(e for e in result if isinstance(e, MassHealPlayerEffect))
    assert h.amount == MASS_HEAL_AMOUNT


def test_mass_heal_mixed_effects():
    minions = [basic(1)]
    players = [(5, 0)]
    result = execute("s_healer_t3", 10, 0, minions, players)
    assert any(isinstance(e, MassHealMinionEffect) for e in result)
    assert any(isinstance(e, MassHealPlayerEffect) for e in result)


def test_mass_heal_empty_inputs_returns_empty():
    result = execute("s_healer_t3", 10, 0, [], [])
    assert result == []
