"""
territory.py — Python port of LaneControl.gd.

Server-authoritative territory / push-limit system.  Tracks per-team push
levels and timers; returns update objects that the caller broadcasts.

No scene-tree access.  The caller passes in the per-lane frontmost minion z-
values (or None if that lane has no minions) so this module remains testable
without Godot.

The caller is also responsible for actually destroying out-of-bounds towers;
TowerDestroyedByPushUpdate names the tower that should be destroyed.
"""

from __future__ import annotations

from dataclasses import dataclass

# ── Update objects ────────────────────────────────────────────────────────────


@dataclass
class BuildLimitUpdate:
    team: int
    new_level: int
    new_z: float


@dataclass
class TowerDestroyedByPushUpdate:
    team: int
    tower_name: str
    tower_z: float


# ── Territory ─────────────────────────────────────────────────────────────────


class Territory:
    """
    Mirrors LaneControl.gd state and logic.

    Push limits (z-values) for each push level (0–3):
      team 0 (blue): limits move in the -z direction (toward red base z=-82)
      team 1 (red):  limits move in the +z direction (toward blue base z=+82)

    tick() accepts:
      - delta: elapsed seconds
      - frontmost_z: list of 3 elements, one per lane.  Each element is either
        a float (the deepest own-minion z for that lane) or None (no minion on
        that lane).  Caller computes these from the live scene tree.
      - towers: list of (name, team, z) tuples for out-of-bounds checks on
        rollback.

    tick() returns a list of update objects:
      BuildLimitUpdate      — when push_level changes (push or rollback)
      TowerDestroyedByPushUpdate — for every tower that falls outside the new
                                   limit after a rollback
    """

    PUSH_LIMITS_BLUE: list[float] = [0.0, -13.7, -27.4, -41.0]
    PUSH_LIMITS_RED: list[float] = [0.0, 13.7, 27.4, 41.0]

    MAX_PUSH: int = 3
    PUSH_TIME: float = 30.0
    ROLLBACK_TIME: float = 15.0

    def __init__(self) -> None:
        self.push_level: list[int] = [0, 0]
        self.push_timer: list[float] = [0.0, 0.0]
        self.rollback_timer: list[float] = [0.0, 0.0]

    # ── Queries ───────────────────────────────────────────────────────────────

    def get_build_limit(self, team: int) -> float:
        if team == 0:
            return self.PUSH_LIMITS_BLUE[self.push_level[0]]
        return self.PUSH_LIMITS_RED[self.push_level[1]]

    def get_push_level(self, team: int) -> int:
        return self.push_level[team]

    # ── Tick ──────────────────────────────────────────────────────────────────

    def tick(
        self,
        delta: float,
        frontmost_z_team0: list[float | None],
        frontmost_z_team1: list[float | None],
        towers: list[tuple[str, int, float]] | None = None,
    ) -> list:
        """
        Advance territory state by *delta* seconds.

        frontmost_z_team0 / frontmost_z_team1: list of 3 elements (one per lane).
          Each element is the deepest own-minion z for that lane, or None if no
          minion is present on that lane.

        towers: optional list of (name, team, z) for destroyed-tower detection on
          rollback.  Pass an empty list or None if no rollback-destroy check is needed.

        Returns a flat list of BuildLimitUpdate and TowerDestroyedByPushUpdate objects.
        """
        if towers is None:
            towers = []
        updates: list = []
        updates += self._tick_team(0, delta, frontmost_z_team0, towers)
        updates += self._tick_team(1, delta, frontmost_z_team1, towers)
        return updates

    def _tick_team(  # noqa: C901
        self,
        t: int,
        delta: float,
        frontmost_z: list[float | None],
        towers: list[tuple[str, int, float]],
    ) -> list:
        updates: list = []
        own_limit_z = self.get_build_limit(t)

        # ── Push condition ────────────────────────────────────────────────────
        # All 3 lanes must have an own minion past (further into enemy territory
        # than) the current build limit.
        all_pushed = True
        for lane_i in range(3):
            fz = frontmost_z[lane_i]
            if fz is None:
                all_pushed = False
                break
            if t == 0:
                past = fz < own_limit_z
            else:
                past = fz > own_limit_z
            if not past:
                all_pushed = False
                break

        if all_pushed:
            self.push_timer[t] = min(self.push_timer[t] + delta, self.PUSH_TIME)
        else:
            self.push_timer[t] = 0.0

        just_pushed = False
        if self.push_timer[t] >= self.PUSH_TIME and self.push_level[t] < self.MAX_PUSH:
            self.push_level[t] += 1
            self.push_timer[t] = 0.0
            self.rollback_timer[t] = 0.0
            just_pushed = True
            updates.append(
                BuildLimitUpdate(
                    team=t,
                    new_level=self.push_level[t],
                    new_z=self.get_build_limit(t),
                )
            )

        # ── Rollback condition ────────────────────────────────────────────────
        # No own minion past the (updated) build limit in ANY lane → start rollback.
        # Skip if a push just fired this tick (avoids same-tick push+rollback).
        if just_pushed:
            return updates
        if self.push_level[t] == 0:
            all_clear = False
        else:
            cur_limit = self.get_build_limit(t)
            all_clear = True
            for lane_i in range(3):
                fz = frontmost_z[lane_i]
                if fz is None:
                    continue
                if t == 0:
                    still_past = fz < cur_limit
                else:
                    still_past = fz > cur_limit
                if still_past:
                    all_clear = False
                    break

        if all_clear and self.push_level[t] > 0:
            self.rollback_timer[t] = min(self.rollback_timer[t] + delta, self.ROLLBACK_TIME)
        else:
            self.rollback_timer[t] = 0.0

        if self.rollback_timer[t] >= self.ROLLBACK_TIME and self.push_level[t] > 0:
            self.push_level[t] -= 1
            self.rollback_timer[t] = 0.0
            self.push_timer[t] = 0.0
            new_limit = self.get_build_limit(t)
            updates.append(
                BuildLimitUpdate(
                    team=t,
                    new_level=self.push_level[t],
                    new_z=new_limit,
                )
            )
            # Identify out-of-bounds towers for destruction
            for name, team, tz in towers:
                if team != t:
                    continue
                outside = (t == 0 and tz < new_limit) or (t == 1 and tz > new_limit)
                if outside:
                    updates.append(TowerDestroyedByPushUpdate(team=t, tower_name=name, tower_z=tz))

        return updates

    # ── Reset ─────────────────────────────────────────────────────────────────

    def reset(self) -> None:
        self.push_level = [0, 0]
        self.push_timer = [0.0, 0.0]
        self.rollback_timer = [0.0, 0.0]
