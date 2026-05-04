"""
minion_state.py — Minion health and death authority (Phase 4).

Python owns:
  - Wave spawning (lane, type, count → MinionWaveSpawnedUpdate with IDs)
  - Per-minion health tracking
  - Death handling (XP award, team points, MinionDiedUpdate)
  - Bulk clear (end-of-game / base taken)

Python does NOT own:
  - Minion movement / targeting (stays in GDScript unreliable_ordered push)
  - Puppet sync broadcasts (GDScript MinionSpawner / MinionBase)

Cross-system callables are injected at construction (same pattern as
combat.py and build.py) so the module is testable without the full stack.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from server.registry import MINION_REGISTRY

# ── Update / event objects ────────────────────────────────────────────────────


@dataclass
class MinionWaveSpawnedUpdate:
    team: int
    lane: int
    minion_type: str
    minion_ids: list[int]


@dataclass
class MinionDamagedUpdate:
    minion_id: int
    health: float


@dataclass
class MinionDiedUpdate:
    minion_id: int
    minion_type: str
    team: int
    killer_peer_id: int


# ── Internal minion state ─────────────────────────────────────────────────────


@dataclass
class MinionState:
    minion_id: int
    minion_type: str
    team: int
    lane: int
    health: float
    max_health: float


# ── MinionState manager ───────────────────────────────────────────────────────


class MinionStateManager:
    """
    Tracks live minion health and handles wave spawning and kill resolution.

    Injected callables (all default to safe no-ops):
      award_xp_fn(peer_id, amount)         — called when a kill awards XP
      add_team_points_fn(team, amount)     — called for kill-point payout
      get_team_points_fn(team) -> int      — read back (currently unused in broadcasts)
    """

    # XP per minion kill — matches LevelSystem.XP_MINION = 10
    XP_MINION: int = 10

    def __init__(
        self,
        award_xp_fn: Callable[[int, int], None] | None = None,
        add_team_points_fn: Callable[[int, int], None] | None = None,
        get_team_points_fn: Callable[[int], int] | None = None,
    ) -> None:
        self._award_xp = award_xp_fn or (lambda pid, a: None)
        self._add_team_points = add_team_points_fn or (lambda t, a: None)
        self._get_team_points = get_team_points_fn or (lambda t: 0)

        # minion_id → MinionState
        self._minions: dict[int, MinionState] = {}
        self._next_id: int = 1

    # ── Queries ───────────────────────────────────────────────────────────────

    def get_live_minions(self) -> list[MinionState]:
        return list(self._minions.values())

    def get_minion(self, minion_id: int) -> MinionState | None:
        return self._minions.get(minion_id)

    def count(self) -> int:
        return len(self._minions)

    # ── Spawning ─────────────────────────────────────────────────────────────

    def spawn_wave(self, team: int, lane: int, minion_type: str, count: int) -> list:
        """
        Spawn *count* minions of *minion_type* for *team* on *lane*.

        Returns:
          [MinionWaveSpawnedUpdate]  — success
          []                         — unknown minion_type or count ≤ 0
        """
        defn = MINION_REGISTRY.get(minion_type)
        if defn is None or count <= 0:
            return []

        ids: list[int] = []
        for _ in range(count):
            mid = self._next_id
            self._next_id += 1
            self._minions[mid] = MinionState(
                minion_id=mid,
                minion_type=minion_type,
                team=team,
                lane=lane,
                health=defn.max_health,
                max_health=defn.max_health,
            )
            ids.append(mid)

        return [
            MinionWaveSpawnedUpdate(team=team, lane=lane, minion_type=minion_type, minion_ids=ids)
        ]

    # ── Damage ────────────────────────────────────────────────────────────────

    def damage_minion(
        self,
        minion_id: int,
        amount: float,
        source_team: int,
        shooter_peer_id: int = -1,
    ) -> list:
        """
        Apply *amount* damage to minion *minion_id*.

        Friendly-fire guard: source_team == minion.team → no-op.

        Returns:
          []                              — unknown minion or friendly fire
          [MinionDamagedUpdate]           — alive after hit
          [MinionDamagedUpdate, MinionDiedUpdate] — killed
        """
        state = self._minions.get(minion_id)
        if state is None:
            return []
        if source_team == state.team:
            return []

        new_hp = max(0.0, state.health - amount)
        state.health = new_hp
        updates: list = [MinionDamagedUpdate(minion_id=minion_id, health=new_hp)]

        if new_hp <= 0.0:
            self._minions.pop(minion_id, None)
            updates.append(
                MinionDiedUpdate(
                    minion_id=minion_id,
                    minion_type=state.minion_type,
                    team=state.team,
                    killer_peer_id=shooter_peer_id,
                )
            )
            # XP to killer player (if a peer fired the killing shot)
            if shooter_peer_id > 0:
                self._award_xp(shooter_peer_id, self.XP_MINION)
            # Kill points to the killing team
            defn = MINION_REGISTRY.get(state.minion_type)
            kill_pts = defn.kill_points if defn is not None else 5
            killer_team = 1 - state.team  # enemy team gets the kill points
            self._add_team_points(killer_team, kill_pts)

        return updates

    # ── Bulk clear ────────────────────────────────────────────────────────────

    def clear_wave(self, team: int) -> list:
        """
        Remove all living minions for *team*.

        Returns a list of MinionDiedUpdate for every removed minion
        (killer_peer_id = -1 for administrative clears).
        """
        to_remove = [m for m in self._minions.values() if m.team == team]
        updates: list = []
        for m in to_remove:
            self._minions.pop(m.minion_id, None)
            updates.append(
                MinionDiedUpdate(
                    minion_id=m.minion_id,
                    minion_type=m.minion_type,
                    team=m.team,
                    killer_peer_id=-1,
                )
            )
        return updates

    # ── Reset ─────────────────────────────────────────────────────────────────

    def reset(self) -> None:
        self._minions.clear()
        self._next_id = 1
