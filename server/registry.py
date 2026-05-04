"""
registry.py — Static definitions for skills, towers, and weapons (Phase 1).

Python port of SkillDefs.gd (canonical source of truth) plus the pure-data
sections of BuildSystem.gd. No GDScript, no sockets, no state.

All three registries are module-level constants so callers can:
    from server.registry import SKILL_REGISTRY, TOWER_REGISTRY, WEAPON_REGISTRY
"""

from __future__ import annotations

from dataclasses import dataclass

# ── SkillDef ──────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class SkillDef:
    node_id: str
    role: str  # "Fighter" | "Supporter"
    branch: str
    type: str  # "passive" | "active" | "unlock" | "utility"
    tier: int  # 1–3
    cost: int
    prereqs: tuple[str, ...]
    level_req: int
    name: str
    description: str
    passive_key: str
    passive_val: float
    cooldown: float


# ── TowerDef ──────────────────────────────────────────────────────────────────

SPACING_FACTOR: float = 0.75  # attack_range * factor for attacking towers
SPACING_PASSIVE: float = 3.0  # passive towers (attack_range == 0)


@dataclass(frozen=True)
class TowerDef:
    tower_type: str
    cost: int
    attack_range: float
    attack_interval_base: float
    spacing: float
    lane_setback: bool
    build_time: float
    is_launcher: bool = False
    launcher_type: str = ""


# ── WeaponDef ─────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class WeaponDef:
    weapon_type: str
    cost: int


# ── DropDef (non-tower supporter drops) ──────────────────────────────────────


@dataclass(frozen=True)
class DropDef:
    item_type: str
    cost: int
    spacing: float
    lane_setback: bool


# ── MinionDef ─────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class MinionDef:
    minion_type: str
    max_health: float
    speed: float
    attack_damage: float
    attack_cooldown: float
    shoot_range: float
    detect_range: float
    kill_points: int  # team points awarded to killing team on death


# ── Helpers ───────────────────────────────────────────────────────────────────


def _tower_spacing(attack_range: float) -> float:
    return SPACING_PASSIVE if attack_range == 0.0 else attack_range * SPACING_FACTOR


# ── Skill registry ────────────────────────────────────────────────────────────


def _s(node_id: str, **kw) -> SkillDef:
    """Shorthand constructor — fills in defaults for optional fields."""
    return SkillDef(
        node_id=node_id,
        prereqs=tuple(kw.pop("prereqs", [])),
        passive_key=kw.pop("passive_key", ""),
        passive_val=float(kw.pop("passive_val", 0.0)),
        cooldown=float(kw.pop("cooldown", 0.0)),
        **kw,
    )


_SKILL_LIST: list[SkillDef] = [
    # ── Fighter — Guardian branch ─────────────────────────────────────────────
    _s(
        "f_field_medic",
        role="Fighter",
        branch="Guardian",
        type="active",
        tier=1,
        cost=1,
        prereqs=[],
        level_req=0,
        name="Field Medic",
        description="Heal yourself and nearby allies within 8 m for 25 HP. 15 s cooldown.",
        cooldown=15.0,
    ),
    _s(
        "f_rally_cry",
        role="Fighter",
        branch="Guardian",
        type="active",
        tier=2,
        cost=2,
        prereqs=["f_field_medic"],
        level_req=0,
        name="Rally Cry",
        description="Grant nearby allies +20% move speed for 5 s. 30 s cooldown.",
        cooldown=30.0,
    ),
    _s(
        "f_revive_pulse",
        role="Fighter",
        branch="Guardian",
        type="active",
        tier=3,
        cost=3,
        prereqs=["f_rally_cry"],
        level_req=0,
        name="Revive Pulse",
        description="Fully heal yourself and restore 30 HP to all allies within 10 m. 60 s cooldown.",  # noqa: E501
        cooldown=60.0,
    ),
    # ── Fighter — DPS branch ──────────────────────────────────────────────────
    _s(
        "f_dash",
        role="Fighter",
        branch="DPS",
        type="active",
        tier=1,
        cost=1,
        prereqs=[],
        level_req=0,
        name="Dash",
        description="Dash 5 m forward. 6 s cooldown.",
        cooldown=6.0,
    ),
    _s(
        "f_rapid_fire",
        role="Fighter",
        branch="DPS",
        type="active",
        tier=2,
        cost=2,
        prereqs=["f_dash"],
        level_req=0,
        name="Rapid Fire",
        description="Current weapon fires 3× faster for 3 s. 20 s cooldown.",
        cooldown=20.0,
    ),
    _s(
        "f_rocket_barrage",
        role="Fighter",
        branch="DPS",
        type="active",
        tier=3,
        cost=3,
        prereqs=["f_rapid_fire"],
        level_req=0,
        name="Rocket Barrage",
        description="Fire one rocket at each enemy tower within 50 m (up to 5). No targets = no effect. 45 s cooldown.",  # noqa: E501
        cooldown=45.0,
    ),
    _s(
        "f_killstreak_heal",
        role="Fighter",
        branch="DPS",
        type="passive",
        tier=2,
        cost=2,
        prereqs=["f_dash"],
        level_req=0,
        name="Bloodrush",
        description="Killing an enemy player restores 30 HP.",
        passive_key="killstreak_heal",
        passive_val=1.0,
    ),
    # ── Fighter — Tank branch ─────────────────────────────────────────────────
    _s(
        "f_adrenaline",
        role="Fighter",
        branch="Tank",
        type="active",
        tier=1,
        cost=1,
        prereqs=[],
        level_req=0,
        name="Adrenaline",
        description="Instantly heal 40 HP. 20 s cooldown.",
        cooldown=20.0,
    ),
    _s(
        "f_iron_skin",
        role="Fighter",
        branch="Tank",
        type="active",
        tier=2,
        cost=2,
        prereqs=["f_adrenaline"],
        level_req=0,
        name="Iron Skin",
        description="Absorb the next 60 incoming damage as a shield for 8 s. 30 s cooldown.",
        cooldown=30.0,
    ),
    _s(
        "f_deploy_mg",
        role="Fighter",
        branch="Tank",
        type="active",
        tier=3,
        cost=3,
        prereqs=["f_iron_skin"],
        level_req=0,
        name="Deploy MG",
        description="Deploy a MachineGun turret at your feet for 20 s (no team point cost). 60 s cooldown.",  # noqa: E501
        cooldown=60.0,
    ),
    # ── Supporter — Basic Minion branch ───────────────────────────────────────
    _s(
        "s_basic_t1",
        role="Supporter",
        branch="Basic Minion",
        type="passive",
        tier=1,
        cost=1,
        prereqs=[],
        level_req=0,
        name="Veteran Troops",
        description="Basic minions use upgraded model (j→m) and spawn with +20% HP.",
        passive_key="basic_tier",
        passive_val=1.0,
    ),
    _s(
        "s_basic_t2",
        role="Supporter",
        branch="Basic Minion",
        type="passive",
        tier=2,
        cost=2,
        prereqs=["s_basic_t1"],
        level_req=0,
        name="Elite Troops",
        description="Basic minions use elite model (m→r) and deal +20% damage.",
        passive_key="basic_tier",
        passive_val=1.0,
    ),
    _s(
        "s_basic_t3",
        role="Supporter",
        branch="Basic Minion",
        type="active",
        tier=3,
        cost=3,
        prereqs=["s_basic_t2"],
        level_req=0,
        name="Coordinated Fire",
        description="All living basic minions fire immediately. 30 s cooldown.",
        cooldown=30.0,
    ),
    # ── Supporter — Cannon Minion branch ──────────────────────────────────────
    _s(
        "s_cannon_t1",
        role="Supporter",
        branch="Cannon Minion",
        type="passive",
        tier=1,
        cost=1,
        prereqs=[],
        level_req=0,
        name="Heavy Ordnance",
        description="Cannon minions use upgraded model (d→g) and deal +25% damage.",
        passive_key="cannon_tier",
        passive_val=1.0,
    ),
    _s(
        "s_cannon_t2",
        role="Supporter",
        branch="Cannon Minion",
        type="passive",
        tier=2,
        cost=2,
        prereqs=["s_cannon_t1"],
        level_req=0,
        name="Long Range",
        description="Cannon minions use elite model (g→h) and gain +30% shoot range.",
        passive_key="cannon_tier",
        passive_val=1.0,
    ),
    _s(
        "s_cannon_t3",
        role="Supporter",
        branch="Cannon Minion",
        type="active",
        tier=3,
        cost=3,
        prereqs=["s_cannon_t2"],
        level_req=0,
        name="Rocket Barrage",
        description="All living cannon minions fire immediately. 45 s cooldown.",
        cooldown=45.0,
    ),
    # ── Supporter — Healer Minion branch ──────────────────────────────────────
    _s(
        "s_healer_t1",
        role="Supporter",
        branch="Healer Minion",
        type="passive",
        tier=1,
        cost=1,
        prereqs=[],
        level_req=0,
        name="Field Medicine",
        description="Healer minions use upgraded model (i→n); heal pulses +5 HP (15 total).",
        passive_key="healer_tier",
        passive_val=1.0,
    ),
    _s(
        "s_healer_t2",
        role="Supporter",
        branch="Healer Minion",
        type="passive",
        tier=2,
        cost=2,
        prereqs=["s_healer_t1"],
        level_req=0,
        name="Extended Care",
        description="Healer minions use elite model (n→q); heal range +4 m (12 m total).",
        passive_key="healer_tier",
        passive_val=1.0,
    ),
    _s(
        "s_healer_t3",
        role="Supporter",
        branch="Healer Minion",
        type="active",
        tier=3,
        cost=3,
        prereqs=["s_healer_t2"],
        level_req=0,
        name="Mass Heal",
        description="Instantly restore 30 HP to all living friendly minions and players on the map. 60 s cooldown.",  # noqa: E501
        cooldown=60.0,
    ),
    # ── Supporter — Logistics branch ──────────────────────────────────────────
    _s(
        "s_minion_revive",
        role="Supporter",
        branch="Logistics",
        type="passive",
        tier=2,
        cost=2,
        prereqs=["s_healer_t1"],
        level_req=0,
        name="Last Stand",
        description="Once per wave, the first friendly minion that would die is revived at 30% HP instead.",  # noqa: E501
        passive_key="minion_revive",
        passive_val=1.0,
    ),
    # ── Supporter — Defense branch ────────────────────────────────────────────
    _s(
        "s_minion_dmg_reduce",
        role="Supporter",
        branch="Defense",
        type="passive",
        tier=2,
        cost=2,
        prereqs=["s_basic_t1"],
        level_req=0,
        name="Battle Hardened",
        description="All friendly minions take 15% less damage.",
        passive_key="minion_damage_reduction",
        passive_val=0.15,
    ),
]

SKILL_REGISTRY: dict[str, SkillDef] = {sd.node_id: sd for sd in _SKILL_LIST}


# ── Tower registry ────────────────────────────────────────────────────────────

_TOWER_LIST: list[TowerDef] = [
    TowerDef(
        "cannon",
        cost=25,
        attack_range=30.0,
        attack_interval_base=1.0,
        spacing=_tower_spacing(30.0),
        lane_setback=True,
        build_time=20.0,
    ),
    TowerDef(
        "mortar",
        cost=35,
        attack_range=50.0,
        attack_interval_base=3.5,
        spacing=_tower_spacing(50.0),
        lane_setback=True,
        build_time=30.0,
    ),
    TowerDef(
        "slow",
        cost=30,
        attack_range=18.0,
        attack_interval_base=1.0,
        spacing=_tower_spacing(18.0),
        lane_setback=True,
        build_time=15.0,
    ),
    TowerDef(
        "machinegun",
        cost=40,
        attack_range=22.0,
        attack_interval_base=0.5,
        spacing=_tower_spacing(22.0),
        lane_setback=True,
        build_time=15.0,
    ),
    TowerDef(
        "barrier",
        cost=10,
        attack_range=0.0,
        attack_interval_base=0.0,
        spacing=SPACING_PASSIVE,
        lane_setback=True,
        build_time=0.0,
    ),
    TowerDef(
        "launcher_missile",
        cost=50,
        attack_range=0.0,
        attack_interval_base=0.0,
        spacing=SPACING_PASSIVE,
        lane_setback=True,
        build_time=25.0,
        is_launcher=True,
        launcher_type="launcher_missile",
    ),
]

TOWER_REGISTRY: dict[str, TowerDef] = {td.tower_type: td for td in _TOWER_LIST}


# ── Weapon registry ───────────────────────────────────────────────────────────

_WEAPON_LIST: list[WeaponDef] = [
    WeaponDef("pistol", cost=10),
    WeaponDef("rifle", cost=20),
    WeaponDef("heavy", cost=30),
    WeaponDef("rocket_launcher", cost=60),
]

WEAPON_REGISTRY: dict[str, WeaponDef] = {wd.weapon_type: wd for wd in _WEAPON_LIST}


# ── Drop registry (non-tower supporter drops) ─────────────────────────────────

_DROP_LIST: list[DropDef] = [
    DropDef("healthpack", cost=15, spacing=5.0, lane_setback=False),
    DropDef("healstation", cost=25, spacing=10.0, lane_setback=False),
]

DROP_REGISTRY: dict[str, DropDef] = {dd.item_type: dd for dd in _DROP_LIST}


# ── Minion registry ───────────────────────────────────────────────────────────
# Stats match MinionBase.gd @export defaults and AGENTS.md documentation.

_MINION_LIST: list[MinionDef] = [
    MinionDef(
        minion_type="standard",
        max_health=60.0,
        speed=4.0,
        attack_damage=8.0,
        attack_cooldown=1.5,
        shoot_range=10.0,
        detect_range=12.0,
        kill_points=5,
    ),
    MinionDef(
        minion_type="cannon",
        max_health=100.0,
        speed=3.0,
        attack_damage=30.0,
        attack_cooldown=3.0,
        shoot_range=14.0,
        detect_range=14.0,
        kill_points=10,
    ),
    MinionDef(
        minion_type="healer",
        max_health=50.0,
        speed=3.5,
        attack_damage=0.0,
        attack_cooldown=0.0,
        shoot_range=0.0,
        detect_range=8.0,
        kill_points=8,
    ),
]

MINION_REGISTRY: dict[str, MinionDef] = {md.minion_type: md for md in _MINION_LIST}


# ── Query helpers (mirror SkillDefs.gd helper functions) ─────────────────────


def get_skill(node_id: str) -> SkillDef | None:
    return SKILL_REGISTRY.get(node_id)


def get_skills_for_role(role: str) -> list[SkillDef]:
    return [sd for sd in SKILL_REGISTRY.values() if sd.role == role]


def get_branches_for_role(role: str) -> list[str]:
    seen: list[str] = []
    for sd in SKILL_REGISTRY.values():
        if sd.role == role and sd.branch not in seen:
            seen.append(sd.branch)
    return seen


def get_skills_in_branch(role: str, branch: str) -> list[SkillDef]:
    result = [sd for sd in SKILL_REGISTRY.values() if sd.role == role and sd.branch == branch]
    return sorted(result, key=lambda sd: sd.tier)


def get_tower(tower_type: str) -> TowerDef | None:
    return TOWER_REGISTRY.get(tower_type)


def get_weapon(weapon_type: str) -> WeaponDef | None:
    return WEAPON_REGISTRY.get(weapon_type)


def get_drop(item_type: str) -> DropDef | None:
    return DROP_REGISTRY.get(item_type)
