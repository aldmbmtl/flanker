"""Tests for server/registry.py — SkillDef, TowerDef, WeaponDef, DropDef, MinionDef and helpers."""

import pytest

from server.registry import (
    DROP_REGISTRY,
    MINION_REGISTRY,
    SKILL_REGISTRY,
    SPACING_FACTOR,
    SPACING_PASSIVE,
    TOWER_REGISTRY,
    WEAPON_REGISTRY,
    MinionDef,
    SkillDef,
    _tower_spacing,
    get_branches_for_role,
    get_drop,
    get_skill,
    get_skills_for_role,
    get_skills_in_branch,
    get_tower,
    get_weapon,
)

# ── SKILL_REGISTRY count and completeness ─────────────────────────────────────


def test_skill_registry_has_21_entries():
    assert len(SKILL_REGISTRY) == 21


def test_all_skill_ids_are_unique():
    ids = list(SKILL_REGISTRY.keys())
    assert len(ids) == len(set(ids))


def test_all_skills_have_required_fields():
    for node_id, sd in SKILL_REGISTRY.items():
        assert isinstance(sd, SkillDef), node_id
        assert sd.role in ("Fighter", "Supporter"), node_id
        assert sd.type in ("passive", "active", "unlock", "utility"), node_id
        assert 1 <= sd.tier <= 3, node_id
        assert sd.cost == sd.tier, node_id
        assert sd.cooldown >= 0.0, node_id


# ── Fighter skills ────────────────────────────────────────────────────────────


def test_fighter_skill_count():
    assert len(get_skills_for_role("Fighter")) == 10


def test_fighter_branches():
    branches = get_branches_for_role("Fighter")
    assert set(branches) == {"Guardian", "DPS", "Tank"}


def test_guardian_branch_order():
    branch = get_skills_in_branch("Fighter", "Guardian")
    assert [s.node_id for s in branch] == ["f_field_medic", "f_rally_cry", "f_revive_pulse"]


def test_dps_branch_nodes():
    branch = get_skills_in_branch("Fighter", "DPS")
    ids = [s.node_id for s in branch]
    assert "f_dash" in ids
    assert "f_rapid_fire" in ids
    assert "f_rocket_barrage" in ids
    assert "f_killstreak_heal" in ids


def test_tank_branch_order():
    branch = get_skills_in_branch("Fighter", "Tank")
    assert [s.node_id for s in branch] == ["f_adrenaline", "f_iron_skin", "f_deploy_mg"]


def test_f_field_medic_cooldown():
    assert get_skill("f_field_medic").cooldown == pytest.approx(15.0)


def test_f_rally_cry_prereq():
    assert get_skill("f_rally_cry").prereqs == ("f_field_medic",)


def test_f_revive_pulse_prereq():
    assert get_skill("f_revive_pulse").prereqs == ("f_rally_cry",)


def test_f_dash_cooldown():
    assert get_skill("f_dash").cooldown == pytest.approx(6.0)


def test_f_killstreak_heal_passive_key():
    sd = get_skill("f_killstreak_heal")
    assert sd.passive_key == "killstreak_heal"
    assert sd.passive_val == pytest.approx(1.0)
    assert sd.type == "passive"


def test_f_deploy_mg_cooldown():
    assert get_skill("f_deploy_mg").cooldown == pytest.approx(60.0)


# ── Supporter skills ──────────────────────────────────────────────────────────


def test_supporter_skill_count():
    assert len(get_skills_for_role("Supporter")) == 11


def test_supporter_branches():
    branches = get_branches_for_role("Supporter")
    assert set(branches) == {
        "Basic Minion",
        "Cannon Minion",
        "Healer Minion",
        "Logistics",
        "Defense",
    }


def test_basic_minion_branch_order():
    branch = get_skills_in_branch("Supporter", "Basic Minion")
    assert [s.node_id for s in branch] == ["s_basic_t1", "s_basic_t2", "s_basic_t3"]


def test_cannon_minion_branch_order():
    branch = get_skills_in_branch("Supporter", "Cannon Minion")
    assert [s.node_id for s in branch] == ["s_cannon_t1", "s_cannon_t2", "s_cannon_t3"]


def test_healer_minion_branch_order():
    branch = get_skills_in_branch("Supporter", "Healer Minion")
    assert [s.node_id for s in branch] == ["s_healer_t1", "s_healer_t2", "s_healer_t3"]


def test_s_basic_t1_passive_key():
    sd = get_skill("s_basic_t1")
    assert sd.passive_key == "basic_tier"
    assert sd.passive_val == pytest.approx(1.0)


def test_s_cannon_t1_passive_key():
    sd = get_skill("s_cannon_t1")
    assert sd.passive_key == "cannon_tier"
    assert sd.passive_val == pytest.approx(1.0)


def test_s_healer_t3_cooldown():
    assert get_skill("s_healer_t3").cooldown == pytest.approx(60.0)


def test_s_minion_revive_prereq():
    assert get_skill("s_minion_revive").prereqs == ("s_healer_t1",)


def test_s_minion_dmg_reduce_passive_val():
    sd = get_skill("s_minion_dmg_reduce")
    assert sd.passive_key == "minion_damage_reduction"
    assert sd.passive_val == pytest.approx(0.15)


# ── get_skill helpers ─────────────────────────────────────────────────────────


def test_get_skill_unknown_returns_none():
    assert get_skill("no_such_skill") is None


def test_get_skills_in_branch_sorted_by_tier():
    branch = get_skills_in_branch("Supporter", "Cannon Minion")
    tiers = [s.tier for s in branch]
    assert tiers == sorted(tiers)


def test_get_branches_unknown_role_returns_empty():
    assert get_branches_for_role("Robot") == []


# ── TOWER_REGISTRY ────────────────────────────────────────────────────────────


def test_tower_registry_has_6_entries():
    assert len(TOWER_REGISTRY) == 6


def test_tower_ids_unique():
    ids = list(TOWER_REGISTRY.keys())
    assert len(ids) == len(set(ids))


def test_cannon_spacing():
    td = get_tower("cannon")
    assert td.spacing == pytest.approx(30.0 * SPACING_FACTOR)


def test_mortar_spacing():
    td = get_tower("mortar")
    assert td.spacing == pytest.approx(50.0 * SPACING_FACTOR)


def test_barrier_spacing_passive():
    td = get_tower("barrier")
    assert td.spacing == pytest.approx(SPACING_PASSIVE)


def test_launcher_is_launcher_flag():
    td = get_tower("launcher_missile")
    assert td.is_launcher is True
    assert td.launcher_type == "launcher_missile"
    assert td.spacing == pytest.approx(SPACING_PASSIVE)


def test_all_towers_have_positive_cost():
    for k, td in TOWER_REGISTRY.items():
        assert td.cost > 0, k


def test_tower_spacing_helper_passive():
    assert _tower_spacing(0.0) == pytest.approx(SPACING_PASSIVE)


def test_tower_spacing_helper_attacking():
    assert _tower_spacing(30.0) == pytest.approx(30.0 * SPACING_FACTOR)


def test_get_tower_unknown_returns_none():
    assert get_tower("not_a_tower") is None


# ── WEAPON_REGISTRY ───────────────────────────────────────────────────────────


def test_weapon_registry_has_4_entries():
    assert len(WEAPON_REGISTRY) == 4


def test_weapon_costs():
    assert get_weapon("pistol").cost == 10
    assert get_weapon("rifle").cost == 20
    assert get_weapon("heavy").cost == 30
    assert get_weapon("rocket_launcher").cost == 60


def test_get_weapon_unknown_returns_none():
    assert get_weapon("banana_gun") is None


# ── DROP_REGISTRY ─────────────────────────────────────────────────────────────


def test_drop_registry_has_2_entries():
    assert len(DROP_REGISTRY) == 2


def test_healthpack_cost():
    assert get_drop("healthpack").cost == 15


def test_healstation_cost_and_spacing():
    dd = get_drop("healstation")
    assert dd.cost == 25
    assert dd.spacing == pytest.approx(10.0)


def test_get_drop_unknown_returns_none():
    assert get_drop("mystery_box") is None


# ── MINION_REGISTRY ───────────────────────────────────────────────────────────


def test_minion_registry_has_3_entries():
    assert len(MINION_REGISTRY) == 3


def test_minion_ids_unique():
    ids = list(MINION_REGISTRY.keys())
    assert len(ids) == len(set(ids))


def test_all_minions_are_miniondef():
    for k, md in MINION_REGISTRY.items():
        assert isinstance(md, MinionDef), k


def test_standard_minion_stats():
    md = MINION_REGISTRY["standard"]
    assert md.max_health == pytest.approx(60.0)
    assert md.speed == pytest.approx(4.0)
    assert md.kill_points == 5


def test_cannon_minion_stats():
    md = MINION_REGISTRY["cannon"]
    assert md.max_health == pytest.approx(100.0)
    assert md.attack_damage == pytest.approx(30.0)
    assert md.kill_points == 10


def test_healer_minion_zero_damage():
    md = MINION_REGISTRY["healer"]
    assert md.attack_damage == pytest.approx(0.0)
    assert md.kill_points == 8


def test_all_minions_positive_health():
    for k, md in MINION_REGISTRY.items():
        assert md.max_health > 0, k
