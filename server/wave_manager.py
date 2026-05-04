"""
wave_manager.py — Authoritative wave timer and composition (Slice 4).

Python owns:
  - The 20-second wave interval timer
  - Wave composition (base_count, lane boosts, ram injection)
  - SpawnWaveEvent objects returned from tick() and consumed by GameServer,
    which broadcasts spawn_wave messages to all Godot clients.

Python does NOT own:
  - Scene instantiation (stays in MinionSpawner.gd)
  - Minion movement / targeting (stays in MinionBase.gd physics)
  - Puppet sync broadcasts (stays in MinionSpawner._broadcast_minion_states)

SpawnWaveEvent is consumed by GameServer._dispatch_updates → _serialise →
wire dict {"type": "spawn_wave", "payload": {...}} → BridgeClient →
MinionSpawner._on_bridge_spawn_wave.
"""

from __future__ import annotations

import random
from collections.abc import Callable
from dataclasses import dataclass

# ── Constants (mirrors MinionSpawner.gd) ──────────────────────────────────────

WAVE_INTERVAL: float = 20.0
MAX_WAVE_SIZE: int = 6
# Slot indices: 0-3 → basic, 4 → cannon, 5 → healer
_SLOT_TYPE: list[str] = ["basic", "basic", "basic", "basic", "cannon", "healer"]
# Probability that a free tier-0 ram spawns each wave (25%)
RAM_SPAWN_CHANCE: float = 0.25


# ── Wire event objects ────────────────────────────────────────────────────────


@dataclass
class SpawnWaveEvent:
    """Tells all clients to spawn one batch of minions."""

    wave_number: int
    team: int
    lane: int
    minion_type: str  # "basic" | "cannon" | "healer" | "ram_t1" | "ram_t2" | "ram_t3"
    count: int


@dataclass
class WaveAnnouncedEvent:
    """Tells all clients to show the wave announcement banner."""

    wave_number: int


@dataclass
class WaveInfoUpdate:
    """
    Tells all clients the current wave number and seconds until the next wave.

    Emitted by WaveManager.tick() once per second (when the countdown changes by
    ≥1 second) so the HUD can display 'Wave N in Xs'.
    """

    wave_number: int
    next_in_seconds: float


# ── WaveManager ───────────────────────────────────────────────────────────────


class WaveManager:
    """
    Drives the per-wave timer and emits SpawnWaveEvents.

    Injected callables (default to safe no-ops):
      rng_fn() -> float   — returns a random float in [0, 1); inject for testing
      rng_int_fn(n) -> int — returns random int in [0, n); inject for testing
    """

    def __init__(
        self,
        rng_fn: Callable[[], float] | None = None,
        rng_int_fn: Callable[[int], int] | None = None,
    ) -> None:
        self._rng = rng_fn if rng_fn is not None else random.random
        self._rng_int = rng_int_fn if rng_int_fn is not None else random.randrange

        self._timer: float = 0.0
        self.wave_number: int = 0

        # Per-team lane boosts: _lane_boosts[team][lane] = extra count for next wave.
        # Consumed (zeroed) after each wave fires.
        self._lane_boosts: list[list[int]] = [[0, 0, 0], [0, 0, 0]]

        # Track last broadcast countdown (integer seconds) to avoid spamming.
        self._last_info_broadcast: int = -1

    # ── Public API ────────────────────────────────────────────────────────────

    def tick(self, delta: float) -> list:
        """
        Advance the wave timer by *delta* seconds.

        Returns a (possibly empty) list of SpawnWaveEvent / WaveAnnouncedEvent /
        WaveInfoUpdate objects if a wave fires or the countdown changes this tick.
        """
        self._timer += delta
        if self._timer >= WAVE_INTERVAL:
            self._timer -= WAVE_INTERVAL
            self.wave_number += 1
            self._last_info_broadcast = -1  # reset so next tick re-broadcasts
            return self._launch_wave()

        # Emit WaveInfoUpdate once per second while counting down.
        countdown_int = int(self.get_time_until_next_wave())
        if countdown_int != self._last_info_broadcast:
            self._last_info_broadcast = countdown_int
            return [
                WaveInfoUpdate(wave_number=self.wave_number, next_in_seconds=float(countdown_int))
            ]

        return []

    def boost_lane(self, team: int, lane: int, amount: int) -> None:
        """Add *amount* extra minions for *team* on *lane* for the next wave."""
        if team < 0 or team > 1:
            return
        if lane < 0 or lane > 2:
            return
        self._lane_boosts[team][lane] += amount

    def boost_all_lanes(self, team: int) -> None:
        """Add 1 extra minion per lane for *team* for the next wave."""
        if team < 0 or team > 1:
            return
        for lane in range(3):
            self._lane_boosts[team][lane] += 1

    def get_time_until_next_wave(self) -> float:
        """Seconds remaining until the next wave fires."""
        return max(0.0, WAVE_INTERVAL - self._timer)

    def reset(self) -> None:
        """Full reset — used at game-over / new game."""
        self._timer = 0.0
        self.wave_number = 0
        self._lane_boosts = [[0, 0, 0], [0, 0, 0]]
        self._last_info_broadcast = -1

    # ── Internal ──────────────────────────────────────────────────────────────

    def _launch_wave(self) -> list:
        events: list = [WaveAnnouncedEvent(wave_number=self.wave_number)]

        base_count = min(self.wave_number, MAX_WAVE_SIZE)

        for lane in range(3):
            for team in range(2):
                extra = self._lane_boosts[team][lane]
                count = base_count + extra
                # Group by minion_type to produce one event per type per lane/team
                type_counts: dict[str, int] = {}
                for slot in range(count):
                    mtype = _SLOT_TYPE[slot] if slot < len(_SLOT_TYPE) else "basic"
                    type_counts[mtype] = type_counts.get(mtype, 0) + 1
                for mtype, n in type_counts.items():
                    events.append(
                        SpawnWaveEvent(
                            wave_number=self.wave_number,
                            team=team,
                            lane=lane,
                            minion_type=mtype,
                            count=n,
                        )
                    )

        # Reset boosts
        self._lane_boosts = [[0, 0, 0], [0, 0, 0]]

        # 25% chance: free tier-0 ram (beaver) on a random team + lane
        if self._rng() < RAM_SPAWN_CHANCE:
            rteam = self._rng_int(2)
            rlane = self._rng_int(3)
            events.append(
                SpawnWaveEvent(
                    wave_number=self.wave_number,
                    team=rteam,
                    lane=rlane,
                    minion_type="ram_t1",
                    count=1,
                )
            )

        return events
