"""
server/skills/supporter.py — Python port of SupporterSkills.gd.

Pure functions that compute the *effects* of each Supporter active ability.
No scene-tree access; the caller passes in living minion/player state.

Returns a list of effect dataclasses.  The caller is responsible for
applying the effects (setting attack timers, healing, etc.).
"""

from __future__ import annotations

from dataclasses import dataclass

# ── Effect dataclasses ────────────────────────────────────────────────────────


@dataclass
class MinionFireEffect:
    """
    Force a specific living minion to fire immediately (set _attack_timer = 0).
    minion_id: the unique integer ID of the minion to fire.
    """

    minion_id: int


@dataclass
class MassHealMinionEffect:
    """Heal a specific living minion by *amount* HP."""

    minion_id: int
    amount: float


@dataclass
class MassHealPlayerEffect:
    """Heal a specific living player by *amount* HP."""

    peer_id: int
    amount: float


# ── Constants ─────────────────────────────────────────────────────────────────

MASS_HEAL_AMOUNT = 30.0


# ── Minion type tags (mirrors GDScript class_name usage) ─────────────────────
# Callers tag each minion dict with "minion_type": "basic" | "cannon" | "healer".

BASIC_MINION_TYPE = "basic"
CANNON_MINION_TYPE = "cannon"
HEALER_MINION_TYPE = "healer"


# ── Dispatch ──────────────────────────────────────────────────────────────────


def execute(
    node_id: str,
    peer_id: int,
    team: int,
    living_minions: list[dict],
    living_players: list[tuple[int, int]],
) -> list:
    """
    Execute a Supporter active ability and return a list of effect objects.

    Parameters
    ----------
    node_id        : skill node ID (e.g. "s_basic_t3")
    peer_id        : caster peer ID (unused for most abilities; kept for symmetry)
    team           : caster team (0 = blue, 1 = red)
    living_minions : list of dicts with keys:
                       "id"          int   — unique minion ID
                       "team"        int
                       "minion_type" str   — "basic" | "cannon" | "healer"
                       (dead minions must be excluded by caller)
    living_players : list of (peer_id, team) tuples
                       (dead players must be excluded by caller)
    """
    match = {
        "s_basic_t3": lambda: _basic_barrage(team, living_minions),
        "s_cannon_t3": lambda: _cannon_barrage(team, living_minions),
        "s_healer_t3": lambda: _mass_heal(team, living_minions, living_players),
    }
    fn = match.get(node_id)
    if fn is None:
        return []
    return fn()


# ── s_basic_t3: force all living basic minions to fire immediately ─────────────


def _basic_barrage(
    team: int,
    living_minions: list[dict],
) -> list:
    effects: list = []
    for m in living_minions:
        if m.get("team") != team:
            continue
        if m.get("minion_type") != BASIC_MINION_TYPE:
            continue
        effects.append(MinionFireEffect(minion_id=m["id"]))
    return effects


# ── s_cannon_t3: force all living cannon minions to fire immediately ───────────


def _cannon_barrage(
    team: int,
    living_minions: list[dict],
) -> list:
    effects: list = []
    for m in living_minions:
        if m.get("team") != team:
            continue
        if m.get("minion_type") != CANNON_MINION_TYPE:
            continue
        effects.append(MinionFireEffect(minion_id=m["id"]))
    return effects


# ── s_healer_t3: instantly heal 30 HP to all friendly minions and players ──────


def _mass_heal(
    team: int,
    living_minions: list[dict],
    living_players: list[tuple[int, int]],
) -> list:
    effects: list = []
    for m in living_minions:
        if m.get("team") != team:
            continue
        effects.append(MassHealMinionEffect(minion_id=m["id"], amount=MASS_HEAL_AMOUNT))
    for pid, pteam in living_players:
        if pteam != team:
            continue
        effects.append(MassHealPlayerEffect(peer_id=pid, amount=MASS_HEAL_AMOUNT))
    return effects
