"""
skills_state.py — Python port of SkillTree.gd.

Server-authoritative skill tree state: skill points, unlocked nodes, active
slot assignments, cooldown tracking, and passive bonus queries.

All cross-system calls (level query, passive bonus lookup) are injected as
callables so this module is fully testable without the rest of the server stack.

use_active() returns a list of effect dataclasses that the caller dispatches
to FighterSkills.execute() / SupporterSkills.execute() and broadcasts.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field

from server.registry import SKILL_REGISTRY, SkillDef

# ── Update / event objects ────────────────────────────────────────────────────


@dataclass
class SkillUnlockedEvent:
    peer_id: int
    node_id: str


@dataclass
class SkillPtsChangedEvent:
    peer_id: int
    pts: int


@dataclass
class ActiveSlotsChangedEvent:
    peer_id: int
    slots: list[str]


@dataclass
class ActiveUsedEvent:
    peer_id: int
    node_id: str


@dataclass
class CooldownTickEvent:
    """Emitted when cooldowns change; carries the full cooldowns dict."""

    peer_id: int
    cooldowns: dict[str, float]


# ── Per-peer state container ──────────────────────────────────────────────────


@dataclass
class _PeerState:
    role: str
    skill_pts: int = 0
    unlocked: list[str] = field(default_factory=list)
    active_slots: list[str] = field(default_factory=lambda: ["", ""])
    cooldowns: dict[str, float] = field(default_factory=dict)
    second_wind_used: bool = False


# ── SkillState ────────────────────────────────────────────────────────────────


class SkillState:
    """
    Mirrors SkillTree.gd state and logic.

    Injected callables:
      get_level_fn(peer_id) -> int    — returns current level for prereq checks
    """

    def __init__(
        self,
        get_level_fn: Callable[[int], int] | None = None,
    ) -> None:
        self._get_level: Callable[[int], int] = get_level_fn or (lambda pid: 1)
        self._states: dict[int, _PeerState] = {}

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    def register_peer(self, peer_id: int, role: str) -> list:
        """
        Register *peer_id* with the given *role*.

        Mirrors SkillTree.register_peer: Fighters also receive a free dash unlock.

        Returns list of events (SkillPtsChangedEvent, SkillUnlockedEvent,
        ActiveSlotsChangedEvent) emitted during registration.
        """
        if peer_id in self._states:
            return []
        s = _PeerState(role=role)
        self._states[peer_id] = s

        events: list = []
        if role == "Fighter":
            s.skill_pts += 1
            s.unlocked.append("f_dash")
            s.active_slots[0] = "f_dash"
            events.append(SkillPtsChangedEvent(peer_id=peer_id, pts=s.skill_pts))
            events.append(SkillUnlockedEvent(peer_id=peer_id, node_id="f_dash"))
            events.append(ActiveSlotsChangedEvent(peer_id=peer_id, slots=list(s.active_slots)))
        return events

    def clear_peer(self, peer_id: int) -> None:
        self._states.pop(peer_id, None)

    def clear_all(self) -> None:
        self._states.clear()

    # ── Queries ───────────────────────────────────────────────────────────────

    def get_skill_pts(self, peer_id: int) -> int:
        s = self._states.get(peer_id)
        return s.skill_pts if s else 0

    def is_unlocked(self, peer_id: int, node_id: str) -> bool:
        s = self._states.get(peer_id)
        return node_id in s.unlocked if s else False

    def get_active_slots(self, peer_id: int) -> list[str]:
        s = self._states.get(peer_id)
        return list(s.active_slots) if s else ["", ""]

    def get_cooldown(self, peer_id: int, node_id: str) -> float:
        s = self._states.get(peer_id)
        return s.cooldowns.get(node_id, 0.0) if s else 0.0

    def get_role(self, peer_id: int) -> str:
        s = self._states.get(peer_id)
        return s.role if s else ""

    def get_all_peers(self) -> list[int]:
        return list(self._states.keys())

    def get_passive_bonus(self, peer_id: int, passive_key: str) -> float:
        """Sum passive_val for all unlocked nodes whose passive_key matches."""
        s = self._states.get(peer_id)
        if not s:
            return 0.0
        total = 0.0
        for nid in s.unlocked:
            defn: SkillDef | None = SKILL_REGISTRY.get(nid)
            if defn and defn.passive_key == passive_key:
                total += defn.passive_val
        return total

    # ── Debug helpers ─────────────────────────────────────────────────────────

    def debug_grant_pts(self, peer_id: int, amount: int) -> list[SkillPtsChangedEvent]:
        s = self._states.get(peer_id)
        if not s:
            return []
        s.skill_pts += amount
        return [SkillPtsChangedEvent(peer_id=peer_id, pts=s.skill_pts)]

    # ── Unlock ────────────────────────────────────────────────────────────────

    def can_unlock(self, peer_id: int, node_id: str) -> bool:
        s = self._states.get(peer_id)
        if not s:
            return False
        if node_id in s.unlocked:
            return False
        defn: SkillDef | None = SKILL_REGISTRY.get(node_id)
        if defn is None:
            return False
        if defn.role != s.role:
            return False
        if s.skill_pts < defn.cost:
            return False
        if defn.level_req > 0 and self._get_level(peer_id) < defn.level_req:
            return False
        for prereq in defn.prereqs:
            if prereq not in s.unlocked:
                return False
        return True

    def unlock_node(self, peer_id: int, node_id: str) -> list:
        """
        Unlock *node_id* for *peer_id* if allowed.

        Returns list of events (SkillUnlockedEvent, SkillPtsChangedEvent).
        Returns empty list if unlock was rejected.
        """
        if not self.can_unlock(peer_id, node_id):
            return []
        s = self._states[peer_id]
        defn = SKILL_REGISTRY[node_id]
        s.skill_pts -= defn.cost
        s.unlocked.append(node_id)
        return [
            SkillUnlockedEvent(peer_id=peer_id, node_id=node_id),
            SkillPtsChangedEvent(peer_id=peer_id, pts=s.skill_pts),
        ]

    # ── Active slot assignment ────────────────────────────────────────────────

    def assign_active_slot(self, peer_id: int, slot: int, node_id: str) -> list:
        """
        Assign *node_id* (or "" to clear) to active *slot* (0 or 1).

        Returns [ActiveSlotsChangedEvent] on success, [] on rejection.
        """
        s = self._states.get(peer_id)
        if s is None or slot not in (0, 1):
            return []
        if node_id != "" and node_id not in s.unlocked:
            return []
        if node_id != "":
            defn = SKILL_REGISTRY.get(node_id)
            if defn is None or defn.type != "active":
                return []
        s.active_slots[slot] = node_id
        return [ActiveSlotsChangedEvent(peer_id=peer_id, slots=list(s.active_slots))]

    # ── Cooldown tick ─────────────────────────────────────────────────────────

    def tick(self, delta: float) -> list[CooldownTickEvent]:
        """Advance all cooldown timers by *delta* seconds.

        Returns one CooldownTickEvent per peer that has active cooldowns,
        carrying a snapshot of the remaining cooldowns after the tick.
        """
        events: list[CooldownTickEvent] = []
        for peer_id, s in self._states.items():
            if not s.cooldowns:
                continue
            for key in list(s.cooldowns.keys()):
                new_cd = max(0.0, s.cooldowns[key] - delta)
                if new_cd == 0.0:
                    del s.cooldowns[key]
                else:
                    s.cooldowns[key] = new_cd
            if s.cooldowns:
                events.append(CooldownTickEvent(peer_id=peer_id, cooldowns=dict(s.cooldowns)))
        return events

    # ── Use active ability ────────────────────────────────────────────────────

    def use_active(self, peer_id: int, slot: int) -> list:
        """
        Attempt to use the active ability in *slot*.

        Returns [ActiveUsedEvent] on success (the event carries the node_id so
        the caller can dispatch to FighterSkills / SupporterSkills).
        Returns [] if: peer unknown, slot invalid, empty slot, not unlocked, on cooldown.
        """
        s = self._states.get(peer_id)
        if s is None or slot not in (0, 1):
            return []
        node_id = s.active_slots[slot]
        if not node_id:
            return []
        if node_id not in s.unlocked:
            return []
        if s.cooldowns.get(node_id, 0.0) > 0.0:
            return []
        # Apply cooldown
        defn = SKILL_REGISTRY.get(node_id)
        if defn and defn.cooldown > 0.0:
            s.cooldowns[node_id] = defn.cooldown
        return [ActiveUsedEvent(peer_id=peer_id, node_id=node_id)]

    # ── Level-up hook ─────────────────────────────────────────────────────────

    def on_level_up(self, peer_id: int, _new_level: int) -> list[SkillPtsChangedEvent]:
        """Award 1 skill point on level-up.  Returns [SkillPtsChangedEvent] or []."""
        s = self._states.get(peer_id)
        if not s:
            return []
        s.skill_pts += 1
        return [SkillPtsChangedEvent(peer_id=peer_id, pts=s.skill_pts)]

    # ── Second Wind ───────────────────────────────────────────────────────────

    def reset_per_life(self, peer_id: int) -> None:
        s = self._states.get(peer_id)
        if s:
            s.second_wind_used = False

    def is_second_wind_used(self, peer_id: int) -> bool:
        s = self._states.get(peer_id)
        return s.second_wind_used if s else True

    def consume_second_wind(self, peer_id: int) -> None:
        s = self._states.get(peer_id)
        if s:
            s.second_wind_used = True
