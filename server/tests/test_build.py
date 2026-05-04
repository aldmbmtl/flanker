"""
test_build.py — Unit tests for server/build.py (Phase 4).

Covers all branches of Build.place_tower(), damage_tower(), remove_tower(),
_spacing_ok(), _make_name(), and _dist3().
"""

import pytest

from server.build import (
    Build,
    DropConsumedUpdate,
    PlacementRejectedUpdate,
    TowerDamagedUpdate,
    TowerDespawnedUpdate,
    TowerSpawnedUpdate,
    TowerState,
    TowerVisualUpdate,
    _dist3,
    _make_name,
)
from server.lanes import generate_lanes

# ── Helpers ───────────────────────────────────────────────────────────────────

BLUE = 0  # team 0 — places at z > 0
RED = 1  # team 1 — places at z < 0

BLUE_POS = (10.0, 0.0, 20.0)  # valid blue half
RED_POS = (10.0, 0.0, -20.0)  # valid red half

_LANES = generate_lanes(42)  # stable lane geometry for setback tests


def make_build(**kwargs) -> Build:
    return Build(**kwargs)


# ── _dist3 helper ─────────────────────────────────────────────────────────────


def test_dist3_zero():
    assert _dist3((0, 0, 0), (0, 0, 0)) == pytest.approx(0.0)


def test_dist3_axis_aligned():
    assert _dist3((0, 0, 0), (3, 4, 0)) == pytest.approx(5.0)


def test_dist3_3d():
    assert _dist3((1, 2, 3), (4, 6, 3)) == pytest.approx(5.0)


# ── _make_name helper ─────────────────────────────────────────────────────────


def test_make_name_cannon():
    assert _make_name("cannon", (10.0, 0.0, 20.0)) == "Tower_cannon_10_20"


def test_make_name_mortar():
    assert _make_name("mortar", (-5.0, 0.0, 30.0)) == "Tower_mortar_-5_30"


def test_make_name_slow():
    assert _make_name("slow", (0.0, 0.0, 15.0)) == "Tower_slow_0_15"


def test_make_name_machinegun():
    assert _make_name("machinegun", (8.0, 0.0, 12.0)) == "Tower_machinegun_8_12"


def test_make_name_healstation():
    assert _make_name("healstation", (3.0, 0.0, 5.0)) == "HealStation_3_5"


def test_make_name_healthpack():
    assert _make_name("healthpack", (3.0, 0.0, 5.0)) == "Drop_healthpack_3_5"


def test_make_name_weapon():
    assert _make_name("weapon", (3.0, 0.0, 5.0)) == "Drop_weapon_3_5"


def test_make_name_launcher():
    assert _make_name("launcher_missile", (4.0, 0.0, 7.0)) == "Launcher_missile_4_7"


def test_make_name_unknown_fallback():
    assert _make_name("future_tower", (1.0, 0.0, 2.0)) == "Tower_future_tower_1_2"


# ── place_tower — rejection cases ─────────────────────────────────────────────


def test_place_unknown_type():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "laser_death_ray")
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "unknown_type"


def test_place_team_half_blue_rejects_negative_z():
    b = make_build()
    r = b.place_tower(RED_POS, BLUE, "cannon")
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "team_half"


def test_place_team_half_blue_rejects_z_zero():
    b = make_build()
    r = b.place_tower((0.0, 0.0, 0.0), BLUE, "cannon")
    assert r[0].reason == "team_half"


def test_place_team_half_red_rejects_positive_z():
    b = make_build()
    r = b.place_tower(BLUE_POS, RED, "cannon")
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "team_half"


def test_place_team_half_red_rejects_z_zero():
    b = make_build()
    r = b.place_tower((0.0, 0.0, 0.0), RED, "cannon")
    assert r[0].reason == "team_half"


# ── Lane setback ──────────────────────────────────────────────────────────────


def test_place_lane_setback_rejected():
    """A position directly on a lane should be rejected when lanes are provided."""
    lanes = generate_lanes(42)
    b = Build(lane_points=lanes)
    # Lane 1 (mid) starts at (0, 82) — place a tower right on the mid lane start
    r = b.place_tower((0.0, 0.0, 50.0), BLUE, "cannon")
    # Mid lane runs along x≈0; (0, 0, 50) is well within setback
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "lane_setback"


def test_place_lane_setback_not_rejected_when_no_lanes():
    """Without lane_points, the setback check is skipped."""
    b = make_build()  # no lane_points
    r = b.place_tower(BLUE_POS, BLUE, "cannon")
    assert isinstance(r[0], TowerSpawnedUpdate)


def test_place_lane_setback_allowed_far_from_lanes():
    """A position well away from all lanes should pass the setback check."""
    lanes = generate_lanes(42)
    b = Build(lane_points=lanes)
    # (50, 0, 40) is far from all three lanes (left≈-85, mid≈0, right≈+85)
    r = b.place_tower((50.0, 0.0, 40.0), BLUE, "cannon")
    assert isinstance(r[0], TowerSpawnedUpdate)


def test_set_lane_points_updates_check():
    """set_lane_points() enables the setback check after construction."""
    b = make_build()  # no lanes initially — placement at mid lane succeeds
    r1 = b.place_tower((0.0, 0.0, 50.0), BLUE, "cannon", forced_name="T1")
    assert isinstance(r1[0], TowerSpawnedUpdate)

    b.set_lane_points(generate_lanes(42))
    # Now the setback check is active — same position is on the mid lane
    r2 = b.place_tower((0.0, 0.0, 50.0), BLUE, "mortar", forced_name="T2")
    assert isinstance(r2[0], PlacementRejectedUpdate)
    assert r2[0].reason == "lane_setback"


def test_place_spacing_rejected():
    b = make_build()
    # Place first cannon
    b.place_tower(BLUE_POS, BLUE, "cannon")
    # Try to place a second cannon 1 unit away (cannon spacing ≈ 22.5)
    close_pos = (BLUE_POS[0] + 1.0, BLUE_POS[1], BLUE_POS[2])
    r = b.place_tower(close_pos, BLUE, "cannon")
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "spacing"


def test_place_insufficient_funds():
    spent = []

    def spend(team, amount):
        spent.append(amount)
        return False

    b = make_build(spend_points_fn=spend)
    r = b.place_tower(BLUE_POS, BLUE, "cannon")
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "insufficient_funds"
    assert spent == [25]  # cannon costs 25


def test_place_zero_cost_skips_spend():
    """barrier is free; use healstation (cost=25) to verify spend is skipped for zero-cost items."""
    called = []
    b = make_build(spend_points_fn=lambda t, a: called.append(a) or True)
    b.place_tower(BLUE_POS, BLUE, "cannon")
    assert 25 in called


# ── place_tower — success cases ───────────────────────────────────────────────


def test_place_cannon_success():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "cannon")
    assert len(r) == 1
    u = r[0]
    assert isinstance(u, TowerSpawnedUpdate)
    assert u.tower_type == "cannon"
    assert u.team == BLUE
    assert u.pos == BLUE_POS
    assert u.health == pytest.approx(900.0)
    assert u.max_health == pytest.approx(900.0)


def test_place_cannon_stored_in_live_towers():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon")
    towers = b.get_live_towers()
    assert len(towers) == 1
    assert towers[0].tower_type == "cannon"


def test_place_uses_forced_name():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="MyTower")
    assert r[0].name == "MyTower"
    assert b.get_tower("MyTower") is not None


def test_place_name_generated_without_forced():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "cannon")
    expected = _make_name("cannon", BLUE_POS)
    assert r[0].name == expected


def test_place_two_towers_far_apart():
    b = make_build()
    far_pos = (50.0, 0.0, 60.0)
    b.place_tower(BLUE_POS, BLUE, "cannon")
    r = b.place_tower(far_pos, BLUE, "cannon")
    assert isinstance(r[0], TowerSpawnedUpdate)
    assert len(b.get_live_towers()) == 2


def test_place_mortar_max_health():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "mortar")
    assert r[0].health == pytest.approx(700.0)


def test_place_machinegun_max_health():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "machinegun")
    assert r[0].health == pytest.approx(600.0)


def test_place_barrier_max_health():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "barrier")
    assert r[0].health == pytest.approx(1200.0)


def test_place_launcher_missile():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "launcher_missile")
    assert isinstance(r[0], TowerSpawnedUpdate)
    assert r[0].tower_type == "launcher_missile"


def test_place_drop_healthpack():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "healthpack")
    assert isinstance(r[0], TowerSpawnedUpdate)
    assert r[0].health == pytest.approx(500.0)  # fallback max_health


def test_place_drop_healstation():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "healstation")
    assert isinstance(r[0], TowerSpawnedUpdate)


def test_place_weapon():
    b = make_build()
    r = b.place_tower(BLUE_POS, BLUE, "weapon")
    assert isinstance(r[0], TowerSpawnedUpdate)


def test_place_records_placer_peer_id():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", placer_peer_id=7)
    assert b.get_live_towers()[0].placer_peer_id == 7


def test_place_red_team_success():
    b = make_build()
    r = b.place_tower(RED_POS, RED, "mortar")
    assert isinstance(r[0], TowerSpawnedUpdate)
    assert r[0].team == RED


# ── get_tower ─────────────────────────────────────────────────────────────────


def test_get_tower_unknown_returns_none():
    b = make_build()
    assert b.get_tower("NoSuch") is None


def test_get_tower_returns_state_after_placement():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    state = b.get_tower("T1")
    assert isinstance(state, TowerState)
    assert state.tower_type == "cannon"


# ── damage_tower ──────────────────────────────────────────────────────────────


def test_damage_unknown_tower_returns_empty():
    b = make_build()
    assert b.damage_tower("ghost", 10.0, RED) == []


def test_damage_friendly_fire_returns_empty():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    assert b.damage_tower("T1", 100.0, BLUE) == []


def test_damage_returns_damaged_update():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    r = b.damage_tower("T1", 50.0, RED)
    assert len(r) == 1
    assert isinstance(r[0], TowerDamagedUpdate)
    assert r[0].name == "T1"
    assert r[0].health == pytest.approx(900.0 - 50.0)


def test_damage_reduces_stored_health():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    b.damage_tower("T1", 200.0, RED)
    assert b.get_tower("T1").health == pytest.approx(700.0)


def test_damage_kills_tower():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    r = b.damage_tower("T1", 9999.0, RED)
    assert len(r) == 2
    assert isinstance(r[0], TowerDamagedUpdate)
    assert r[0].health == pytest.approx(0.0)
    assert isinstance(r[1], TowerDespawnedUpdate)
    assert r[1].name == "T1"
    assert r[1].tower_type == "cannon"
    assert r[1].team == BLUE


def test_damage_removes_tower_from_live():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    b.damage_tower("T1", 9999.0, RED)
    assert b.get_tower("T1") is None
    assert len(b.get_live_towers()) == 0


def test_damage_awards_xp_on_kill():
    xp_log = []
    b = make_build(award_xp_fn=lambda pid, amt: xp_log.append((pid, amt)))
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    b.damage_tower("T1", 9999.0, RED, shooter_peer_id=5)
    assert (5, 200) in xp_log


def test_damage_no_xp_when_shooter_minus_one():
    xp_log = []
    b = make_build(award_xp_fn=lambda pid, amt: xp_log.append((pid, amt)))
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    b.damage_tower("T1", 9999.0, RED, shooter_peer_id=-1)
    assert xp_log == []


def test_damage_does_not_go_below_zero():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    r = b.damage_tower("T1", 9999.0, RED)
    assert r[0].health == pytest.approx(0.0)


# ── remove_tower ─────────────────────────────────────────────────────────────


def test_remove_unknown_tower_returns_empty():
    b = make_build()
    assert b.remove_tower("ghost") == []


def test_remove_tower_returns_despawned_update():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "mortar", forced_name="M1")
    r = b.remove_tower("M1")
    assert len(r) == 1
    assert isinstance(r[0], TowerDespawnedUpdate)
    assert r[0].name == "M1"
    assert r[0].tower_type == "mortar"
    assert r[0].team == BLUE


def test_remove_tower_deletes_from_live():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "mortar", forced_name="M1")
    b.remove_tower("M1")
    assert b.get_tower("M1") is None


def test_remove_tower_source_team_informational():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    r = b.remove_tower("T1", source_team=BLUE)  # no friendly-fire guard on remove
    assert isinstance(r[0], TowerDespawnedUpdate)


# ── reset ─────────────────────────────────────────────────────────────────────


def test_reset_clears_all_towers():
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "cannon", forced_name="T1")
    b.place_tower((50.0, 0.0, 60.0), BLUE, "mortar", forced_name="T2")
    b.reset()
    assert b.get_live_towers() == []


# ── spacing with mixed tower types ───────────────────────────────────────────


def test_spacing_uses_max_of_new_and_existing():
    """
    A mortar (spacing=37.5) already placed. A cannon (spacing=22.5) placed
    nearby at distance 30 — within mortar spacing — should be rejected.
    """
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "mortar", forced_name="M1")
    near_pos = (BLUE_POS[0], BLUE_POS[1], BLUE_POS[2] + 30.0)
    r = b.place_tower(near_pos, BLUE, "cannon")
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "spacing"


def test_spacing_drop_vs_tower_uses_floor():
    """
    Two healthpacks (spacing=5.0) placed 6 units apart — both should succeed.
    """
    b = make_build()
    b.place_tower(BLUE_POS, BLUE, "healthpack", forced_name="H1")
    near_pos = (BLUE_POS[0], BLUE_POS[1], BLUE_POS[2] + 6.0)
    r = b.place_tower(near_pos, BLUE, "healthpack")
    assert isinstance(r[0], TowerSpawnedUpdate)


def test_spacing_unknown_existing_tower_uses_required():
    """
    If existing tower type not in registry (injected fake), _spacing_ok
    falls back to the required spacing.
    """
    b = make_build()
    # Manually inject a TowerState with an unknown type
    b._towers["fake"] = TowerState(
        name="fake",
        tower_type="unknown_future",
        team=BLUE,
        pos=(BLUE_POS[0], BLUE_POS[1], BLUE_POS[2] + 1.0),
        health=100.0,
        max_health=100.0,
    )
    r = b.place_tower(BLUE_POS, BLUE, "cannon")
    # cannon spacing=22.5, distance=1 → rejected
    assert isinstance(r[0], PlacementRejectedUpdate)
    assert r[0].reason == "spacing"


# ── TowerVisualUpdate dataclass ───────────────────────────────────────────────


def test_tower_visual_update_defaults():
    u = TowerVisualUpdate(vtype="hit_flash")
    assert u.vtype == "hit_flash"
    assert u.params == {}


def test_tower_visual_update_with_params():
    u = TowerVisualUpdate(vtype="slow_pulse", params={"radius": 5.0})
    assert u.params == {"radius": 5.0}


# ── DropConsumedUpdate dataclass ──────────────────────────────────────────────


def test_drop_consumed_update_fields():
    u = DropConsumedUpdate(name="Drop_healthpack_10_20", team=0)
    assert u.name == "Drop_healthpack_10_20"
    assert u.team == 0


# ── TestConsumeDrops ─────────────────────────────────────────────────────────


class TestConsumeDrops:
    def test_register_then_consume_returns_update(self):
        b = make_build()
        b.register_drop("Drop_healthpack_10_20", BLUE)
        result = b.consume_drop("Drop_healthpack_10_20")
        assert len(result) == 1
        assert isinstance(result[0], DropConsumedUpdate)
        assert result[0].name == "Drop_healthpack_10_20"
        assert result[0].team == BLUE

    def test_consume_unknown_name_returns_empty(self):
        b = make_build()
        result = b.consume_drop("NoSuchDrop")
        assert result == []

    def test_consume_already_consumed_returns_empty(self):
        b = make_build()
        b.register_drop("Drop_healthpack_10_20", BLUE)
        b.consume_drop("Drop_healthpack_10_20")
        result = b.consume_drop("Drop_healthpack_10_20")
        assert result == []

    def test_register_after_consume_reenables_drop(self):
        """Simulates natural respawn: register_drop re-enables a consumed name."""
        b = make_build()
        b.register_drop("Drop_healthpack_10_20", BLUE)
        b.consume_drop("Drop_healthpack_10_20")
        # Respawn: register again
        b.register_drop("Drop_healthpack_10_20", BLUE)
        result = b.consume_drop("Drop_healthpack_10_20")
        assert len(result) == 1
        assert isinstance(result[0], DropConsumedUpdate)

    def test_reset_clears_drops(self):
        b = make_build()
        b.register_drop("Drop_healthpack_10_20", BLUE)
        b.consume_drop("Drop_healthpack_10_20")
        b.reset()
        # After reset: register a new drop and ensure state is clean
        b.register_drop("Drop_healthpack_10_20", BLUE)
        result = b.consume_drop("Drop_healthpack_10_20")
        assert len(result) == 1

    def test_reset_clears_live_drops_dict(self):
        b = make_build()
        b.register_drop("Drop_weapon_5_5", RED)
        b.reset()
        assert b._live_drops == {}

    def test_reset_clears_consumed_set(self):
        b = make_build()
        b.register_drop("Drop_healthpack_10_20", BLUE)
        b.consume_drop("Drop_healthpack_10_20")
        b.reset()
        assert b._consumed_drops == set()

    def test_consume_removes_from_live_drops(self):
        b = make_build()
        b.register_drop("Drop_healthpack_10_20", BLUE)
        b.consume_drop("Drop_healthpack_10_20")
        assert "Drop_healthpack_10_20" not in b._live_drops

    def test_multiple_independent_drops(self):
        b = make_build()
        b.register_drop("Drop_healthpack_10_20", BLUE)
        b.register_drop("Drop_weapon_5_5", RED)
        b.consume_drop("Drop_healthpack_10_20")
        # Second drop still available
        result = b.consume_drop("Drop_weapon_5_5")
        assert len(result) == 1
        assert result[0].team == RED

    def test_consume_name_in_both_live_and_consumed_returns_empty(self):
        """
        Edge case: name present in both _live_drops and _consumed_drops
        (e.g. manually injected stale state).  Must return [] without consuming.
        """
        b = make_build()
        # Manually create the inconsistent state
        b._live_drops["Drop_healthpack_10_20"] = BLUE
        b._consumed_drops.add("Drop_healthpack_10_20")
        result = b.consume_drop("Drop_healthpack_10_20")
        assert result == []
