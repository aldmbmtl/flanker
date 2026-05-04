"""Tests for server/skills/fighter.py — 100% line coverage required."""

import pytest

from server.skills.fighter import (
    ADRENALINE_HEAL,
    BARRAGE_MAX_TARGETS,
    DASH_DISTANCE,
    DASH_DURATION,
    DEPLOY_MG_LIFETIME,
    FIELD_MEDIC_HEAL,
    IRON_SKIN_DURATION,
    IRON_SKIN_HP,
    RALLY_CRY_BONUS,
    RALLY_CRY_DURATION,
    RAPID_FIRE_DURATION,
    RAPID_FIRE_MULT,
    REVIVE_PULSE_ALLY,
    REVIVE_PULSE_SELF,
    DashEffect,
    DeployMGEffect,
    HealEffect,
    RallyEffect,
    RapidFireEffect,
    RocketBarrageEffect,
    ShieldEffect,
    _dist3,
    _normalize_xz,
    execute,
)

ORIGIN = (0.0, 0.0, 0.0)
FORWARD = (0.0, 0.0, -1.0)


# ── Helper internals ──────────────────────────────────────────────────────────


def test_dist3_zero():
    assert _dist3(ORIGIN, ORIGIN) == pytest.approx(0.0)


def test_dist3_simple():
    assert _dist3((0.0, 0.0, 0.0), (3.0, 0.0, 4.0)) == pytest.approx(5.0)


def test_normalize_xz_forward():
    result = _normalize_xz((0.0, 5.0, -3.0))
    assert result[1] == 0.0
    length = (result[0] ** 2 + result[2] ** 2) ** 0.5
    assert length == pytest.approx(1.0)


def test_normalize_xz_zero_vector():
    assert _normalize_xz((0.0, 0.0, 0.0)) == (0.0, 0.0, 0.0)


def test_normalize_xz_near_zero():
    # Very small xz component but nonzero y
    assert _normalize_xz((0.0, 100.0, 0.0)) == (0.0, 0.0, 0.0)


# ── Unknown node_id ───────────────────────────────────────────────────────────


def test_unknown_node_returns_empty():
    result = execute("totally_unknown", 1, 0, ORIGIN, FORWARD)
    assert result == []


# ── f_adrenaline ──────────────────────────────────────────────────────────────


def test_adrenaline_returns_heal_effect():
    result = execute("f_adrenaline", 1, 0, ORIGIN, FORWARD)
    assert len(result) == 1
    h = result[0]
    assert isinstance(h, HealEffect)
    assert h.peer_id == 1
    assert h.amount == ADRENALINE_HEAL


# ── f_iron_skin ───────────────────────────────────────────────────────────────


def test_iron_skin_returns_shield_effect():
    result = execute("f_iron_skin", 1, 0, ORIGIN, FORWARD)
    assert len(result) == 1
    s = result[0]
    assert isinstance(s, ShieldEffect)
    assert s.peer_id == 1
    assert s.hp == IRON_SKIN_HP
    assert s.duration == IRON_SKIN_DURATION


# ── f_dash ────────────────────────────────────────────────────────────────────


def test_dash_returns_dash_effect():
    result = execute("f_dash", 1, 0, ORIGIN, FORWARD)
    assert len(result) == 1
    d = result[0]
    assert isinstance(d, DashEffect)
    assert d.peer_id == 1
    assert d.duration == DASH_DURATION


def test_dash_target_is_forward_distance():
    result = execute("f_dash", 1, 0, (0.0, 0.0, 0.0), (0.0, 0.0, -1.0))
    d = result[0]
    assert d.target[2] == pytest.approx(-DASH_DISTANCE)
    assert d.target[0] == pytest.approx(0.0)


def test_dash_zero_forward_returns_empty():
    result = execute("f_dash", 1, 0, ORIGIN, (0.0, 5.0, 0.0))
    assert result == []


def test_dash_origin_stored_correctly():
    pos = (3.0, 1.0, 5.0)
    result = execute("f_dash", 1, 0, pos, FORWARD)
    d = result[0]
    assert d.origin == pos


# ── f_rapid_fire ──────────────────────────────────────────────────────────────


def test_rapid_fire_returns_effect():
    result = execute("f_rapid_fire", 1, 0, ORIGIN, FORWARD, weapon_type="rifle")
    assert len(result) == 1
    r = result[0]
    assert isinstance(r, RapidFireEffect)
    assert r.peer_id == 1
    assert r.multiplier == RAPID_FIRE_MULT
    assert r.duration == RAPID_FIRE_DURATION
    assert r.weapon_type == "rifle"


def test_rapid_fire_empty_weapon_type():
    result = execute("f_rapid_fire", 1, 0, ORIGIN, FORWARD)
    assert result[0].weapon_type == ""


# ── f_field_medic ─────────────────────────────────────────────────────────────


def test_field_medic_heals_caster():
    result = execute("f_field_medic", 1, 0, ORIGIN, FORWARD)
    assert any(isinstance(e, HealEffect) and e.peer_id == 1 for e in result)


def test_field_medic_heals_nearby_ally():
    allies = [(2, (3.0, 0.0, 0.0))]  # within 8m
    result = execute("f_field_medic", 1, 0, ORIGIN, FORWARD, ally_positions=allies)
    assert any(isinstance(e, HealEffect) and e.peer_id == 2 for e in result)


def test_field_medic_ignores_far_ally():
    allies = [(2, (100.0, 0.0, 0.0))]  # outside 8m
    result = execute("f_field_medic", 1, 0, ORIGIN, FORWARD, ally_positions=allies)
    assert not any(isinstance(e, HealEffect) and e.peer_id == 2 for e in result)


def test_field_medic_heal_amount():
    result = execute("f_field_medic", 1, 0, ORIGIN, FORWARD)
    h = next(e for e in result if isinstance(e, HealEffect) and e.peer_id == 1)
    assert h.amount == FIELD_MEDIC_HEAL


# ── f_rally_cry ───────────────────────────────────────────────────────────────


def test_rally_cry_applies_to_caster():
    result = execute("f_rally_cry", 1, 0, ORIGIN, FORWARD)
    assert any(isinstance(e, RallyEffect) and e.peer_id == 1 for e in result)


def test_rally_cry_applies_to_nearby_ally():
    allies = [(2, (5.0, 0.0, 0.0))]
    result = execute("f_rally_cry", 1, 0, ORIGIN, FORWARD, ally_positions=allies)
    assert any(isinstance(e, RallyEffect) and e.peer_id == 2 for e in result)


def test_rally_cry_ignores_far_ally():
    allies = [(2, (100.0, 0.0, 0.0))]
    result = execute("f_rally_cry", 1, 0, ORIGIN, FORWARD, ally_positions=allies)
    assert not any(isinstance(e, RallyEffect) and e.peer_id == 2 for e in result)


def test_rally_cry_bonus_and_duration():
    result = execute("f_rally_cry", 1, 0, ORIGIN, FORWARD)
    r = next(e for e in result if isinstance(e, RallyEffect))
    assert r.bonus == RALLY_CRY_BONUS
    assert r.duration == RALLY_CRY_DURATION


# ── f_revive_pulse ────────────────────────────────────────────────────────────


def test_revive_pulse_heals_self():
    result = execute("f_revive_pulse", 1, 0, ORIGIN, FORWARD)
    assert any(
        isinstance(e, HealEffect) and e.peer_id == 1 and e.amount == REVIVE_PULSE_SELF
        for e in result
    )


def test_revive_pulse_heals_nearby_ally():
    allies = [(2, (5.0, 0.0, 0.0))]
    result = execute("f_revive_pulse", 1, 0, ORIGIN, FORWARD, ally_positions=allies)
    assert any(
        isinstance(e, HealEffect) and e.peer_id == 2 and e.amount == REVIVE_PULSE_ALLY
        for e in result
    )


def test_revive_pulse_ignores_far_ally():
    allies = [(2, (100.0, 0.0, 0.0))]
    result = execute("f_revive_pulse", 1, 0, ORIGIN, FORWARD, ally_positions=allies)
    assert not any(isinstance(e, HealEffect) and e.peer_id == 2 for e in result)


# ── f_rocket_barrage ──────────────────────────────────────────────────────────


def test_rocket_barrage_no_targets_returns_empty():
    result = execute("f_rocket_barrage", 1, 0, ORIGIN, FORWARD, enemy_towers=[])
    assert result == []


def test_rocket_barrage_fires_at_in_range_tower():
    towers = [("TowerA", (10.0, 0.0, 0.0))]
    result = execute("f_rocket_barrage", 1, 0, ORIGIN, FORWARD, enemy_towers=towers)
    assert len(result) == 1
    rb = result[0]
    assert isinstance(rb, RocketBarrageEffect)
    assert rb.peer_id == 1
    assert any(name == "TowerA" for name, _ in rb.targets)


def test_rocket_barrage_ignores_out_of_range_tower():
    towers = [("FarTower", (200.0, 0.0, 0.0))]
    result = execute("f_rocket_barrage", 1, 0, ORIGIN, FORWARD, enemy_towers=towers)
    assert result == []


def test_rocket_barrage_caps_at_max_targets():
    towers = [(f"T{i}", (float(i) * 2, 0.0, 0.0)) for i in range(BARRAGE_MAX_TARGETS + 3)]
    result = execute("f_rocket_barrage", 1, 0, ORIGIN, FORWARD, enemy_towers=towers)
    assert len(result[0].targets) == BARRAGE_MAX_TARGETS


def test_rocket_barrage_sorts_by_distance():
    towers = [
        ("Far", (40.0, 0.0, 0.0)),
        ("Near", (5.0, 0.0, 0.0)),
    ]
    result = execute("f_rocket_barrage", 1, 0, ORIGIN, FORWARD, enemy_towers=towers)
    names = [name for name, _ in result[0].targets]
    assert names[0] == "Near"


# ── f_deploy_mg ───────────────────────────────────────────────────────────────


def test_deploy_mg_returns_effect():
    pos = (5.0, 0.0, 5.0)
    result = execute("f_deploy_mg", 1, 0, pos, FORWARD)
    assert len(result) == 1
    mg = result[0]
    assert isinstance(mg, DeployMGEffect)
    assert mg.peer_id == 1
    assert mg.team == 0
    assert mg.position == pos
    assert mg.lifetime == DEPLOY_MG_LIFETIME
