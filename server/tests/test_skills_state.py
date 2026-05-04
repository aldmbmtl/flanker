"""Tests for server/skills_state.py — 100% line coverage required."""

import pytest

from server.skills_state import (
    ActiveSlotsChangedEvent,
    ActiveUsedEvent,
    CooldownTickEvent,
    SkillPtsChangedEvent,
    SkillState,
    SkillUnlockedEvent,
)

# ── Helpers ───────────────────────────────────────────────────────────────────


def make_state(**kwargs):
    return SkillState(**kwargs)


# ── register_peer ─────────────────────────────────────────────────────────────


def test_register_fighter_grants_dash():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.is_unlocked(1, "f_dash")


def test_register_fighter_events():
    s = make_state()
    events = s.register_peer(1, "Fighter")
    assert any(isinstance(e, SkillUnlockedEvent) for e in events)
    assert any(isinstance(e, SkillPtsChangedEvent) for e in events)
    assert any(isinstance(e, ActiveSlotsChangedEvent) for e in events)


def test_register_fighter_dash_in_slot0():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.get_active_slots(1)[0] == "f_dash"


def test_register_fighter_skill_pts_1():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.get_skill_pts(1) == 1


def test_register_supporter_no_default_unlock():
    s = make_state()
    events = s.register_peer(1, "Supporter")
    assert events == []
    assert s.get_skill_pts(1) == 0


def test_register_twice_noop():
    s = make_state()
    s.register_peer(1, "Fighter")
    events = s.register_peer(1, "Fighter")
    assert events == []
    assert s.get_skill_pts(1) == 1  # unchanged


def test_clear_peer():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.clear_peer(1)
    assert s.get_role(1) == ""


def test_clear_all():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.register_peer(2, "Supporter")
    s.clear_all()
    assert s.get_all_peers() == []


# ── Queries on unknown peer ───────────────────────────────────────────────────


def test_get_skill_pts_unknown():
    s = make_state()
    assert s.get_skill_pts(99) == 0


def test_is_unlocked_unknown():
    s = make_state()
    assert not s.is_unlocked(99, "f_dash")


def test_get_active_slots_unknown():
    s = make_state()
    assert s.get_active_slots(99) == ["", ""]


def test_get_cooldown_unknown():
    s = make_state()
    assert s.get_cooldown(99, "f_dash") == 0.0


def test_get_role_unknown():
    s = make_state()
    assert s.get_role(99) == ""


def test_get_passive_bonus_unknown():
    s = make_state()
    assert s.get_passive_bonus(99, "killstreak_heal") == 0.0


# ── can_unlock ────────────────────────────────────────────────────────────────


def test_can_unlock_unknown_peer_false():
    s = make_state()
    assert not s.can_unlock(99, "f_adrenaline")


def test_can_unlock_already_unlocked_false():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert not s.can_unlock(1, "f_dash")  # already unlocked by registration


def test_can_unlock_unknown_node_false():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert not s.can_unlock(1, "nonexistent_node")


def test_can_unlock_wrong_role_false():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.debug_grant_pts(1, 10)
    assert not s.can_unlock(1, "s_basic_t1")  # Supporter node


def test_can_unlock_sufficient_pts_true():
    s = make_state()
    s.register_peer(1, "Fighter")
    # Fighter starts with 1 pt; f_adrenaline costs 1, no prereqs → can unlock
    assert s.can_unlock(1, "f_adrenaline")


def test_can_unlock_insufficient_pts_false():
    s = make_state()
    s.register_peer(1, "Fighter")
    # f_rapid_fire costs 2 pts; Fighter starts with 1 → insufficient
    assert not s.can_unlock(1, "f_rapid_fire")


def test_can_unlock_prereq_missing_false():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.debug_grant_pts(1, 10)
    # f_revive_pulse prereq = f_field_medic + f_rally_cry (not unlocked)
    assert not s.can_unlock(1, "f_revive_pulse")


def test_can_unlock_level_req_not_met_false():
    # Temporarily patch a skill's level_req to be > 1 to test the level gate.
    from server import registry

    original = registry.SKILL_REGISTRY["f_adrenaline"]
    from server.registry import SkillDef

    patched = SkillDef(
        node_id=original.node_id,
        role=original.role,
        branch=original.branch,
        type=original.type,
        tier=original.tier,
        cost=original.cost,
        prereqs=original.prereqs,
        level_req=5,
        name=original.name,
        description=original.description,
        passive_key=original.passive_key,
        passive_val=original.passive_val,
        cooldown=original.cooldown,
    )
    registry.SKILL_REGISTRY["f_adrenaline"] = patched
    try:
        s = make_state(get_level_fn=lambda pid: 1)
        s.register_peer(1, "Fighter")
        s.debug_grant_pts(1, 10)
        result = s.can_unlock(1, "f_adrenaline")
        assert not result
    finally:
        registry.SKILL_REGISTRY["f_adrenaline"] = original


# ── unlock_node ───────────────────────────────────────────────────────────────


def test_unlock_node_success():
    s = make_state()
    s.register_peer(1, "Fighter")
    # f_adrenaline: cost 1, no prereqs — Fighter starts with 1 pt
    events = s.unlock_node(1, "f_adrenaline")
    assert any(isinstance(e, SkillUnlockedEvent) for e in events)
    assert s.is_unlocked(1, "f_adrenaline")


def test_unlock_node_spends_pts():
    s = make_state()
    s.register_peer(1, "Fighter")
    pts_before = s.get_skill_pts(1)
    s.unlock_node(1, "f_adrenaline")
    from server.registry import SKILL_REGISTRY

    cost = SKILL_REGISTRY["f_adrenaline"].cost
    assert s.get_skill_pts(1) == pts_before - cost


def test_unlock_node_rejected_returns_empty():
    s = make_state()
    s.register_peer(1, "Fighter")
    # f_adrenaline needs more pts; grant none extra
    events = s.unlock_node(1, "s_basic_t1")  # wrong role
    assert events == []


# ── debug_grant_pts ───────────────────────────────────────────────────────────


def test_debug_grant_pts():
    s = make_state()
    s.register_peer(1, "Fighter")
    events = s.debug_grant_pts(1, 5)
    assert s.get_skill_pts(1) == 6
    assert any(isinstance(e, SkillPtsChangedEvent) for e in events)


def test_debug_grant_pts_unknown_returns_empty():
    s = make_state()
    events = s.debug_grant_pts(99, 5)
    assert events == []


# ── assign_active_slot ────────────────────────────────────────────────────────


def test_assign_active_slot_success():
    s = make_state()
    s.register_peer(1, "Fighter")
    # Unlock f_adrenaline (cost 1, no prereqs, active) using the 1 starting pt
    s.unlock_node(1, "f_adrenaline")
    events = s.assign_active_slot(1, 1, "f_adrenaline")
    assert any(isinstance(e, ActiveSlotsChangedEvent) for e in events)
    assert s.get_active_slots(1)[1] == "f_adrenaline"


def test_assign_active_slot_clear():
    s = make_state()
    s.register_peer(1, "Fighter")
    events = s.assign_active_slot(1, 0, "")
    assert any(isinstance(e, ActiveSlotsChangedEvent) for e in events)
    assert s.get_active_slots(1)[0] == ""


def test_assign_active_slot_unknown_peer():
    s = make_state()
    assert s.assign_active_slot(99, 0, "") == []


def test_assign_active_slot_invalid_slot():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.assign_active_slot(1, 5, "") == []


def test_assign_active_slot_not_unlocked():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.assign_active_slot(1, 0, "f_rapid_fire") == []


def test_assign_active_slot_not_active_type():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.debug_grant_pts(1, 5)
    # f_killstreak_heal prereq is f_dash (already unlocked), cost 2
    s.unlock_node(1, "f_killstreak_heal")
    # Try to assign passive to slot — should fail
    assert s.assign_active_slot(1, 0, "f_killstreak_heal") == []


def test_assign_active_slot_unknown_node_id():
    s = make_state()
    s.register_peer(1, "Fighter")
    # node_id not "" and not in registry
    assert s.assign_active_slot(1, 0, "nonexistent") == []


def test_assign_active_slot_node_not_in_registry_but_unlocked():
    """Covers the defn is None branch (line 219) in assign_active_slot."""
    s = make_state()
    s.register_peer(1, "Fighter")
    # Manually inject a ghost node_id into unlocked (bypasses can_unlock)
    s._states[1].unlocked.append("ghost_node")
    assert s.assign_active_slot(1, 0, "ghost_node") == []


# ── use_active ────────────────────────────────────────────────────────────────


def test_use_active_success():
    s = make_state()
    s.register_peer(1, "Fighter")
    events = s.use_active(1, 0)
    assert any(isinstance(e, ActiveUsedEvent) for e in events)
    assert events[0].node_id == "f_dash"


def test_use_active_sets_cooldown():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.use_active(1, 0)
    from server.registry import SKILL_REGISTRY

    cd = SKILL_REGISTRY["f_dash"].cooldown
    assert s.get_cooldown(1, "f_dash") == pytest.approx(cd)


def test_use_active_on_cooldown_returns_empty():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.use_active(1, 0)
    assert s.use_active(1, 0) == []


def test_use_active_unknown_peer():
    s = make_state()
    assert s.use_active(99, 0) == []


def test_use_active_invalid_slot():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.use_active(1, 5) == []


def test_use_active_empty_slot():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.use_active(1, 1) == []  # slot 1 is empty


def test_use_active_not_unlocked():
    s = make_state()
    s.register_peer(1, "Fighter")
    # Manually set slot without going through unlock
    s._states[1].active_slots[1] = "f_rapid_fire"
    assert s.use_active(1, 1) == []


# ── tick (cooldowns) ──────────────────────────────────────────────────────────


def test_tick_reduces_cooldown():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.use_active(1, 0)
    from server.registry import SKILL_REGISTRY

    cd = SKILL_REGISTRY["f_dash"].cooldown
    s.tick(2.0)
    assert s.get_cooldown(1, "f_dash") == pytest.approx(cd - 2.0)


def test_tick_expires_cooldown():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.use_active(1, 0)
    from server.registry import SKILL_REGISTRY

    cd = SKILL_REGISTRY["f_dash"].cooldown
    s.tick(cd + 1.0)
    assert s.get_cooldown(1, "f_dash") == 0.0


def test_tick_after_expire_can_use_again():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.use_active(1, 0)
    from server.registry import SKILL_REGISTRY

    cd = SKILL_REGISTRY["f_dash"].cooldown
    s.tick(cd + 1.0)
    events = s.use_active(1, 0)
    assert any(isinstance(e, ActiveUsedEvent) for e in events)


# ── on_level_up ───────────────────────────────────────────────────────────────


def test_on_level_up_grants_pt():
    s = make_state()
    s.register_peer(1, "Fighter")
    pts_before = s.get_skill_pts(1)
    events = s.on_level_up(1, 2)
    assert s.get_skill_pts(1) == pts_before + 1
    assert any(isinstance(e, SkillPtsChangedEvent) for e in events)


def test_on_level_up_unknown_returns_empty():
    s = make_state()
    assert s.on_level_up(99, 2) == []


# ── get_passive_bonus ─────────────────────────────────────────────────────────


def test_passive_bonus_for_unlocked_node():
    s = make_state()
    s.register_peer(1, "Fighter")
    # f_killstreak_heal: prereq=f_dash (already unlocked), cost 2 → grant 1 more pt
    s.debug_grant_pts(1, 1)
    s.unlock_node(1, "f_killstreak_heal")
    bonus = s.get_passive_bonus(1, "killstreak_heal")
    assert bonus > 0.0


def test_passive_bonus_no_match_returns_zero():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert s.get_passive_bonus(1, "nonexistent_key") == 0.0


# ── second_wind ───────────────────────────────────────────────────────────────


def test_second_wind_initial_not_used():
    s = make_state()
    s.register_peer(1, "Fighter")
    assert not s.is_second_wind_used(1)


def test_consume_second_wind():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.consume_second_wind(1)
    assert s.is_second_wind_used(1)


def test_reset_per_life_clears_second_wind():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.consume_second_wind(1)
    s.reset_per_life(1)
    assert not s.is_second_wind_used(1)


def test_second_wind_unknown_peer_returns_true():
    s = make_state()
    assert s.is_second_wind_used(99)


def test_second_wind_unknown_peer_noop():
    s = make_state()
    s.consume_second_wind(99)  # must not raise
    s.reset_per_life(99)  # must not raise


# ── tick returns CooldownTickEvent list ──────────────────────────────────────


def test_tick_returns_empty_when_no_cooldowns():
    s = make_state()
    s.register_peer(1, "Fighter")
    events = s.tick(1.0)
    assert events == []


def test_tick_returns_cooldown_event_when_active():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.use_active(1, 0)  # f_dash goes on cooldown
    events = s.tick(1.0)
    assert len(events) == 1
    assert isinstance(events[0], CooldownTickEvent)
    assert events[0].peer_id == 1
    assert "f_dash" in events[0].cooldowns


def test_tick_no_event_after_cooldown_expires():
    from server.registry import SKILL_REGISTRY

    s = make_state()
    s.register_peer(1, "Fighter")
    s.use_active(1, 0)
    cd = SKILL_REGISTRY["f_dash"].cooldown
    events = s.tick(cd + 1.0)
    assert events == []


def test_tick_multiple_peers_each_get_event():
    s = make_state()
    s.register_peer(1, "Fighter")
    s.register_peer(2, "Fighter")
    s.use_active(1, 0)
    s.use_active(2, 0)
    events = s.tick(0.5)
    peer_ids = {e.peer_id for e in events}
    assert peer_ids == {1, 2}
