"""
economy.py — Python port of TeamData.gd (Phase 1).

Manages team points and passive income. Pure Python — no Godot, no sockets,
no signals. All state is owned by a single TeamEconomy instance.
"""

from __future__ import annotations


class TeamEconomy:
    """
    Tracks points and passive income for each team.

    team 0 = blue, team 1 = red.
    Out-of-range team indices are silently ignored (matches GDScript behaviour).
    """

    TEAM_COUNT: int = 2
    STARTING_POINTS: int = 75

    def __init__(self) -> None:
        self._points: list[int] = [self.STARTING_POINTS] * self.TEAM_COUNT
        self._passive_income: list[int] = [0] * self.TEAM_COUNT

    # ── Points ────────────────────────────────────────────────────────────────

    def add_points(self, team: int, amount: int) -> None:
        """Add *amount* points to *team*. No-op for invalid team index."""
        if 0 <= team < self.TEAM_COUNT:
            self._points[team] += amount

    def get_points(self, team: int) -> int:
        """Return current points for *team*, or 0 for invalid team index."""
        if 0 <= team < self.TEAM_COUNT:
            return self._points[team]
        return 0

    def spend_points(self, team: int, amount: int) -> bool:
        """
        Deduct *amount* from *team* if funds are sufficient.

        Returns True on success, False if the team cannot afford it or the
        team index is invalid.
        """
        if 0 <= team < self.TEAM_COUNT and self._points[team] >= amount:
            self._points[team] -= amount
            return True
        return False

    def sync(self, blue: int, red: int) -> None:
        """Overwrite both teams' points directly (replaces sync_from_server)."""
        self._points[0] = blue
        self._points[1] = red

    # ── Passive income ────────────────────────────────────────────────────────

    def add_passive_income(self, team: int, amount: int) -> None:
        """Accumulate *amount* into *team*'s pending passive income."""
        if 0 <= team < self.TEAM_COUNT:
            self._passive_income[team] += amount

    def get_passive_income(self, team: int) -> int:
        """Return the pending passive income for *team*."""
        if 0 <= team < self.TEAM_COUNT:
            return self._passive_income[team]
        return 0

    def payout_passive_income(self, team: int) -> int:
        """
        Add the accumulated passive income to *team*'s points, reset the
        accumulator to 0, and return the amount paid out.

        Returns 0 for invalid team or when no income was pending.
        """
        if 0 <= team < self.TEAM_COUNT:
            payout = self._passive_income[team]
            self._passive_income[team] = 0
            if payout > 0:
                self.add_points(team, payout)
            return payout
        return 0

    # ── Reset ─────────────────────────────────────────────────────────────────

    def reset(self) -> None:
        """Reset both teams to starting points and clear all passive income."""
        self._points = [self.STARTING_POINTS] * self.TEAM_COUNT
        self._passive_income = [0] * self.TEAM_COUNT
