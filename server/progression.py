"""
progression.py — Python port of LevelSystem.gd (Phase 1).

Manages per-peer XP, levels, and attribute points. Pure Python — no Godot,
no RPCs, no signals.

Role gating (Fighters may not spend Supporter attrs and vice versa) requires
knowing a peer's role. Because SkillTree does not exist in Python yet, the
role lookup is injected via get_role_fn at construction time. In Phase 3 this
will call the real Python skill registry. In tests a lambda is passed.

award_xp() returns a list of LevelUpEvent objects so callers know which peers
levelled up and how many points were awarded. The caller (GameServer) is
responsible for broadcasting these to clients.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

# ── Event object ──────────────────────────────────────────────────────────────


@dataclass
class LevelUpEvent:
    peer_id: int
    new_level: int
    pts_awarded: int


# ── Progression ───────────────────────────────────────────────────────────────


class Progression:
    """
    Tracks XP, level, unspent attribute points, and spent attributes for every
    registered peer.

    All dicts are keyed by peer_id (int).
    """

    # ── Constants (exact match to LevelSystem.gd) ─────────────────────────────

    MAX_LEVEL: int = 12

    # XP required to reach level N+1 (index 0 = level 1→2, index 10 = level 11→12)
    XP_PER_LEVEL: list[int] = [70, 140, 250, 390, 560, 770, 1020, 1300, 1610, 1960, 2350]

    # Attribute points awarded on reaching each level (index 0 = level 2, …)
    POINTS_PER_LEVEL: list[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3]

    # Kill XP rewards
    XP_MINION: int = 10
    XP_PLAYER: int = 100
    XP_TOWER: int = 200

    # Stat bonus per attribute point
    HP_PER_POINT: float = 15.0
    SPEED_PER_POINT: float = 0.15
    DAMAGE_PER_POINT: float = 0.10
    STAMINA_PER_POINT: float = 2.0
    TOWER_HP_PER_POINT: float = 0.05
    PLACEMENT_RANGE_PER_POINT: float = 0.10
    TOWER_FIRE_RATE_PER_POINT: float = 0.05

    ATTR_CAP: int = 6

    FIGHTER_ATTRS: list[str] = ["hp", "speed", "damage", "stamina"]
    SUPPORTER_ATTRS: list[str] = ["tower_hp", "placement_range", "tower_fire_rate"]
    ALL_ATTRS: list[str] = FIGHTER_ATTRS + SUPPORTER_ATTRS

    _EMPTY_ATTRS: dict[str, int] = {
        "hp": 0,
        "speed": 0,
        "damage": 0,
        "stamina": 0,
        "tower_hp": 0,
        "placement_range": 0,
        "tower_fire_rate": 0,
    }

    def __init__(self, get_role_fn: Callable[[int], str] | None = None) -> None:
        """
        get_role_fn: callable(peer_id) -> "Fighter" | "Supporter" | "".
        If None, role gating is skipped (all attrs are spendable).
        """
        self._get_role: Callable[[int], str] = get_role_fn or (lambda _: "")
        self._xp: dict[int, int] = {}
        self._level: dict[int, int] = {}
        self._points: dict[int, int] = {}
        self._attrs: dict[int, dict[str, int]] = {}

    # ── Peer lifecycle ────────────────────────────────────────────────────────

    def register_peer(self, peer_id: int) -> None:
        """Register a new peer. No-op if already registered."""
        if peer_id in self._xp:
            return
        self._xp[peer_id] = 0
        self._level[peer_id] = 1
        self._points[peer_id] = 0
        self._attrs[peer_id] = dict(self._EMPTY_ATTRS)

    def clear_peer(self, peer_id: int) -> None:
        """Remove all state for *peer_id*."""
        self._xp.pop(peer_id, None)
        self._level.pop(peer_id, None)
        self._points.pop(peer_id, None)
        self._attrs.pop(peer_id, None)

    def clear_all(self) -> None:
        """Remove all per-peer state."""
        self._xp.clear()
        self._level.clear()
        self._points.clear()
        self._attrs.clear()

    # ── XP and levelling ──────────────────────────────────────────────────────

    def award_xp(self, peer_id: int, amount: int) -> list[LevelUpEvent]:
        """
        Award *amount* XP to *peer_id*. Auto-registers the peer if unknown.

        Returns a list of LevelUpEvent objects (one per level gained). The
        list is empty when no level-up occurred or when the peer is already
        at MAX_LEVEL.
        """
        if peer_id not in self._xp:
            self.register_peer(peer_id)

        if self._level[peer_id] >= self.MAX_LEVEL:
            return []

        self._xp[peer_id] += amount
        events: list[LevelUpEvent] = []

        while self._level[peer_id] < self.MAX_LEVEL and self._xp[
            peer_id
        ] >= self._xp_for_next_level(self._level[peer_id]):
            needed = self._xp_for_next_level(self._level[peer_id])
            self._xp[peer_id] -= needed
            self._level[peer_id] += 1
            pts = self.POINTS_PER_LEVEL[self._level[peer_id] - 2]  # index 0 = level 2
            self._points[peer_id] += pts
            events.append(
                LevelUpEvent(
                    peer_id=peer_id,
                    new_level=self._level[peer_id],
                    pts_awarded=pts,
                )
            )

        return events

    # ── Attribute spending ────────────────────────────────────────────────────

    def spend_point(self, peer_id: int, attr: str) -> bool:
        """
        Spend one unspent point on *attr* for *peer_id*.

        Returns True on success. Returns False if:
          - peer is not registered
          - no unspent points remain
          - attr is not a valid attribute name
          - role gate: Fighter spending Supporter attr or vice versa
          - the attribute is already at ATTR_CAP
        """
        if peer_id not in self._attrs:
            return False
        if self._points.get(peer_id, 0) <= 0:
            return False
        if attr not in self.ALL_ATTRS:
            return False

        role = self._get_role(peer_id)
        if role == "Fighter" and attr in self.SUPPORTER_ATTRS:
            return False
        if role == "Supporter" and attr in self.FIGHTER_ATTRS:
            return False

        cur = self._attrs[peer_id].get(attr, 0)
        if cur >= self.ATTR_CAP:
            return False

        self._attrs[peer_id][attr] = cur + 1
        self._points[peer_id] -= 1
        return True

    # ── Queries ───────────────────────────────────────────────────────────────

    def get_level(self, peer_id: int) -> int:
        return self._level.get(peer_id, 1)

    def get_xp(self, peer_id: int) -> int:
        return self._xp.get(peer_id, 0)

    def get_xp_needed(self, peer_id: int) -> int:
        return self._xp_for_next_level(self._level.get(peer_id, 1))

    def get_unspent_points(self, peer_id: int) -> int:
        return self._points.get(peer_id, 0)

    def get_attrs(self, peer_id: int) -> dict[str, int]:
        return dict(self._attrs.get(peer_id, self._EMPTY_ATTRS))

    # ── Stat bonus helpers ────────────────────────────────────────────────────

    def get_bonus_hp(self, peer_id: int) -> float:
        return float(self._attrs.get(peer_id, {}).get("hp", 0)) * self.HP_PER_POINT

    def get_bonus_speed_mult(self, peer_id: int) -> float:
        return float(self._attrs.get(peer_id, {}).get("speed", 0)) * self.SPEED_PER_POINT

    def get_bonus_damage_mult(self, peer_id: int) -> float:
        return float(self._attrs.get(peer_id, {}).get("damage", 0)) * self.DAMAGE_PER_POINT

    def get_bonus_stamina(self, peer_id: int) -> float:
        return float(self._attrs.get(peer_id, {}).get("stamina", 0)) * self.STAMINA_PER_POINT

    def get_bonus_tower_hp_mult(self, peer_id: int) -> float:
        return float(self._attrs.get(peer_id, {}).get("tower_hp", 0)) * self.TOWER_HP_PER_POINT

    def get_bonus_placement_range_mult(self, peer_id: int) -> float:
        return (
            float(self._attrs.get(peer_id, {}).get("placement_range", 0))
            * self.PLACEMENT_RANGE_PER_POINT
        )

    def get_bonus_tower_fire_rate_mult(self, peer_id: int) -> float:
        return (
            float(self._attrs.get(peer_id, {}).get("tower_fire_rate", 0))
            * self.TOWER_FIRE_RATE_PER_POINT
        )

    # ── Internal ──────────────────────────────────────────────────────────────

    def _xp_for_next_level(self, lvl: int) -> int:
        """XP threshold to go from *lvl* to lvl+1. Returns a sentinel at MAX."""
        if 1 <= lvl <= len(self.XP_PER_LEVEL):
            return self.XP_PER_LEVEL[lvl - 1]
        return 999_999
