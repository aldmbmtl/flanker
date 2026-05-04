"""
game_state.py — Python port of TeamLives.gd + GamePhase state machine (Phase 1).

Fixes the double-broadcast game_over bug by construction: lose_life() is a
pure function that returns a list of update objects. The caller (GameServer)
broadcasts them. There is exactly one place game_over can be produced.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

# ── Phase enum ────────────────────────────────────────────────────────────────


class GamePhase(Enum):
    LOBBY = "lobby"
    LOADING = "loading"
    PLAYING = "playing"
    GAME_OVER = "game_over"


_VALID_TRANSITIONS: dict[GamePhase, list[GamePhase]] = {
    GamePhase.LOBBY: [GamePhase.LOADING],
    GamePhase.LOADING: [GamePhase.PLAYING],
    GamePhase.PLAYING: [GamePhase.GAME_OVER],
    GamePhase.GAME_OVER: [],
}


# ── Update objects (returned by lose_life) ────────────────────────────────────


@dataclass
class LivesUpdate:
    """Emitted each time a team loses a life (but the game is not over)."""

    team: int
    lives: int


@dataclass
class GameOverUpdate:
    """Emitted exactly once when a team's lives reach zero."""

    winner: int


# ── State machine ─────────────────────────────────────────────────────────────


class GameStateMachine:
    """
    Authoritative lives tracker and phase state machine.

    lose_life() returns a list containing either:
      - [LivesUpdate]   — life lost, game continues
      - [GameOverUpdate] — lives hit zero, game ends (fires exactly once)
      - []               — called outside PLAYING phase (guard, no-op)
    """

    def __init__(self, lives_per_team: int = 20) -> None:
        self._phase: GamePhase = GamePhase.LOBBY
        self._lives: list[int] = [lives_per_team, lives_per_team]
        self._lives_per_team: int = lives_per_team

    # ── Queries ───────────────────────────────────────────────────────────────

    @property
    def phase(self) -> GamePhase:
        return self._phase

    def get_lives(self, team: int) -> int:
        """Return current lives for *team* (0 or 1)."""
        if 0 <= team < 2:
            return self._lives[team]
        return 0

    # ── Mutations ─────────────────────────────────────────────────────────────

    def transition(self, new_phase: GamePhase) -> None:
        """
        Move to *new_phase*.

        Raises ValueError for illegal transitions (e.g. LOBBY → GAME_OVER).
        """
        allowed = _VALID_TRANSITIONS[self._phase]
        if new_phase not in allowed:
            raise ValueError(f"Invalid transition: {self._phase.value} → {new_phase.value}")
        self._phase = new_phase

    def lose_life(self, team: int) -> list[LivesUpdate | GameOverUpdate]:
        """
        Deduct one life from *team*.

        Returns a list of state update objects for the caller to broadcast.
        Returns [] if called outside PLAYING phase or with invalid team index.
        """
        if self._phase != GamePhase.PLAYING:
            return []
        if team not in (0, 1):
            return []

        self._lives[team] = max(0, self._lives[team] - 1)
        remaining = self._lives[team]

        if remaining <= 0:
            self._phase = GamePhase.GAME_OVER
            winner = 1 - team
            return [GameOverUpdate(winner=winner)]

        return [LivesUpdate(team=team, lives=remaining)]

    def reset(self, lives_per_team: int | None = None) -> None:
        """Reset to LOBBY phase with fresh lives."""
        if lives_per_team is not None:
            self._lives_per_team = lives_per_team
        self._phase = GamePhase.LOBBY
        self._lives = [self._lives_per_team, self._lives_per_team]
