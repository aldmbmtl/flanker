"""
server/skills/fighter.py — Python port of FighterSkills.gd.

Pure functions that compute the *effects* of each Fighter active ability.
No scene-tree access; spatial context (ally distances, tower list) is
passed in by the caller.

All functions return a list of effect dataclasses.  The caller (GameServer)
is responsible for:
  - applying HP changes via Combat
  - setting shields via Combat.set_shield
  - broadcasting the effects to clients
  - spawning rockets / MG turrets in the scene tree (Phase 3/4)
"""

from __future__ import annotations

from dataclasses import dataclass

# ── Effect dataclasses ────────────────────────────────────────────────────────


@dataclass
class HealEffect:
    """Direct HP heal for one player."""

    peer_id: int
    amount: float


@dataclass
class DashEffect:
    """Dash: move caster forward DASH_DISTANCE metres."""

    peer_id: int
    origin: tuple[float, float, float]
    target: tuple[float, float, float]
    duration: float


@dataclass
class RapidFireEffect:
    """Rapid fire: multiply fire rate for a duration."""

    peer_id: int
    multiplier: float
    duration: float
    weapon_type: str


@dataclass
class ShieldEffect:
    """Iron Skin: absorb incoming damage for a duration."""

    peer_id: int
    hp: float
    duration: float


@dataclass
class RallyEffect:
    """Rally Cry: speed bonus applied to caster + nearby allies."""

    peer_id: int
    bonus: float  # fractional speed multiplier bonus e.g. 0.20
    duration: float


@dataclass
class RocketBarrageEffect:
    """Rocket Barrage: list of enemy tower positions to fire at."""

    peer_id: int
    targets: list[tuple[str, tuple[float, float, float]]]  # [(tower_name, pos), ...]


@dataclass
class DeployMGEffect:
    """Deploy MG: spawn a MachineGun turret at the caster's feet."""

    peer_id: int
    team: int
    position: tuple[float, float, float]
    lifetime: float


# ── Constants ─────────────────────────────────────────────────────────────────

DASH_DISTANCE = 5.0
DASH_DURATION = 0.5
ADRENALINE_HEAL = 40.0
FIELD_MEDIC_HEAL = 25.0
FIELD_MEDIC_RANGE = 8.0
RALLY_CRY_BONUS = 0.20
RALLY_CRY_DURATION = 5.0
RALLY_CRY_RANGE = 8.0
REVIVE_PULSE_RANGE = 10.0
REVIVE_PULSE_ALLY = 30.0
REVIVE_PULSE_SELF = 999.0  # effectively full heal; capped by max HP in Combat
RAPID_FIRE_MULT = 3.0
RAPID_FIRE_DURATION = 3.0
BARRAGE_RANGE = 50.0
BARRAGE_MAX_TARGETS = 5
IRON_SKIN_HP = 60.0
IRON_SKIN_DURATION = 8.0
DEPLOY_MG_LIFETIME = 20.0


# ── Dispatch ──────────────────────────────────────────────────────────────────


def execute(
    node_id: str,
    peer_id: int,
    team: int,
    caster_pos: tuple[float, float, float],
    caster_forward: tuple[float, float, float],
    weapon_type: str = "",
    ally_positions: list[tuple[int, tuple[float, float, float]]] | None = None,
    enemy_towers: list[tuple[str, tuple[float, float, float]]] | None = None,
) -> list:
    """
    Execute a Fighter active ability and return a list of effect objects.

    Parameters
    ----------
    node_id        : skill node ID (e.g. "f_dash")
    peer_id        : caster peer ID
    team           : caster team (0 = blue, 1 = red)
    caster_pos     : (x, y, z) world position of the caster
    caster_forward : unit forward vector of the caster (y component ignored for dash)
    weapon_type    : weapon_type string from Combat (used by rapid fire)
    ally_positions : list of (peer_id, (x,y,z)) for same-team players (excl. caster)
    enemy_towers   : list of (name, (x,y,z)) for enemy towers (used by barrage)
    """
    if ally_positions is None:
        ally_positions = []
    if enemy_towers is None:
        enemy_towers = []

    match = {
        "f_field_medic": lambda: _field_medic(peer_id, caster_pos, ally_positions),
        "f_rally_cry": lambda: _rally_cry(peer_id, caster_pos, ally_positions),
        "f_revive_pulse": lambda: _revive_pulse(peer_id, caster_pos, ally_positions),
        "f_dash": lambda: _dash(peer_id, caster_pos, caster_forward),
        "f_rapid_fire": lambda: _rapid_fire(peer_id, weapon_type),
        "f_rocket_barrage": lambda: _rocket_barrage(peer_id, caster_pos, team, enemy_towers),
        "f_adrenaline": lambda: _adrenaline(peer_id),
        "f_iron_skin": lambda: _iron_skin(peer_id),
        "f_deploy_mg": lambda: _deploy_mg(peer_id, team, caster_pos),
    }
    fn = match.get(node_id)
    if fn is None:
        return []
    return fn()


# ── Helpers ───────────────────────────────────────────────────────────────────


def _dist3(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def _normalize_xz(v: tuple[float, float, float]) -> tuple[float, float, float]:
    """Flatten y then normalize; returns (0,0,0) if near-zero length."""
    x, _, z = v
    length = (x * x + z * z) ** 0.5
    if length < 1e-4:
        return (0.0, 0.0, 0.0)
    return (x / length, 0.0, z / length)


# ── Guardian branch ───────────────────────────────────────────────────────────


def _field_medic(
    peer_id: int,
    caster_pos: tuple[float, float, float],
    ally_positions: list[tuple[int, tuple[float, float, float]]],
) -> list:
    effects: list = [HealEffect(peer_id=peer_id, amount=FIELD_MEDIC_HEAL)]
    for ally_pid, apos in ally_positions:
        if _dist3(caster_pos, apos) <= FIELD_MEDIC_RANGE:
            effects.append(HealEffect(peer_id=ally_pid, amount=FIELD_MEDIC_HEAL))
    return effects


def _rally_cry(
    peer_id: int,
    caster_pos: tuple[float, float, float],
    ally_positions: list[tuple[int, tuple[float, float, float]]],
) -> list:
    effects: list = [
        RallyEffect(peer_id=peer_id, bonus=RALLY_CRY_BONUS, duration=RALLY_CRY_DURATION)
    ]
    for ally_pid, apos in ally_positions:
        if _dist3(caster_pos, apos) <= RALLY_CRY_RANGE:
            effects.append(
                RallyEffect(peer_id=ally_pid, bonus=RALLY_CRY_BONUS, duration=RALLY_CRY_DURATION)
            )
    return effects


def _revive_pulse(
    peer_id: int,
    caster_pos: tuple[float, float, float],
    ally_positions: list[tuple[int, tuple[float, float, float]]],
) -> list:
    effects: list = [HealEffect(peer_id=peer_id, amount=REVIVE_PULSE_SELF)]
    for ally_pid, apos in ally_positions:
        if _dist3(caster_pos, apos) <= REVIVE_PULSE_RANGE:
            effects.append(HealEffect(peer_id=ally_pid, amount=REVIVE_PULSE_ALLY))
    return effects


# ── DPS branch ────────────────────────────────────────────────────────────────


def _dash(
    peer_id: int,
    caster_pos: tuple[float, float, float],
    caster_forward: tuple[float, float, float],
) -> list:
    fwd = _normalize_xz(caster_forward)
    if fwd == (0.0, 0.0, 0.0):
        return []
    target = (
        caster_pos[0] + fwd[0] * DASH_DISTANCE,
        caster_pos[1],
        caster_pos[2] + fwd[2] * DASH_DISTANCE,
    )
    return [
        DashEffect(
            peer_id=peer_id,
            origin=caster_pos,
            target=target,
            duration=DASH_DURATION,
        )
    ]


def _rapid_fire(peer_id: int, weapon_type: str) -> list:
    return [
        RapidFireEffect(
            peer_id=peer_id,
            multiplier=RAPID_FIRE_MULT,
            duration=RAPID_FIRE_DURATION,
            weapon_type=weapon_type,
        )
    ]


def _rocket_barrage(
    peer_id: int,
    caster_pos: tuple[float, float, float],
    team: int,
    enemy_towers: list[tuple[str, tuple[float, float, float]]],
) -> list:
    in_range = [
        (name, pos) for name, pos in enemy_towers if _dist3(caster_pos, pos) <= BARRAGE_RANGE
    ]
    if not in_range:
        return []
    # Sort by distance, cap at BARRAGE_MAX_TARGETS
    in_range.sort(key=lambda t: _dist3(caster_pos, t[1]))
    targets = in_range[:BARRAGE_MAX_TARGETS]
    return [RocketBarrageEffect(peer_id=peer_id, targets=targets)]


# ── Tank branch ───────────────────────────────────────────────────────────────


def _adrenaline(peer_id: int) -> list:
    return [HealEffect(peer_id=peer_id, amount=ADRENALINE_HEAL)]


def _iron_skin(peer_id: int) -> list:
    return [ShieldEffect(peer_id=peer_id, hp=IRON_SKIN_HP, duration=IRON_SKIN_DURATION)]


def _deploy_mg(
    peer_id: int,
    team: int,
    caster_pos: tuple[float, float, float],
) -> list:
    return [
        DeployMGEffect(
            peer_id=peer_id,
            team=team,
            position=caster_pos,
            lifetime=DEPLOY_MG_LIFETIME,
        )
    ]
