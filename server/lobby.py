"""
lobby.py — Player registry, role management, game-start orchestration.

Python port of the logic portions of LobbyManager.gd. Stateless with respect
to networking — no sockets, no GDScript. Returns lists of update dataclasses.

Constants that match GDScript:
    MAX_PLAYERS     = 10
    RESPAWN_BASE    = 10.0   (seconds)
    RESPAWN_INCREMENT = 0.0  (currently flat — kept for future scaling)
    RESPAWN_CAP     = 60.0
    ROLE_FIGHTER    = 0
    ROLE_SUPPORTER  = 1
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from typing import Any

# ---------------------------------------------------------------------------
# Update dataclasses  (Python → Godot)
# ---------------------------------------------------------------------------


@dataclass
class LobbyStateUpdate:
    """Full lobby snapshot — broadcast after any player-state change."""

    players: dict[int, dict]
    can_start: bool = False
    host_id: int = 0


@dataclass
class LoadGameUpdate:
    """Broadcast after game_started to tell clients to change scene."""

    path: str


@dataclass
class RoleAcceptedUpdate:
    """Sent to all clients when a role is successfully claimed."""

    peer_id: int
    role: int  # 0=Fighter 1=Supporter
    supporter_claimed: dict  # {0: bool, 1: bool}


@dataclass
class RoleRejectedUpdate:
    """Sent only to the peer whose role request was denied."""

    peer_id: int
    supporter_claimed: dict


@dataclass
class GameStartUpdate:
    """Broadcast when the host starts the game."""

    map_seed: int
    time_seed: int
    lane_points: list[list[tuple[float, float]]]


@dataclass
class PlayerLeftUpdate:
    """Broadcast when a peer disconnects."""

    peer_id: int


@dataclass
class DeathCountUpdate:
    """Broadcast when a player's death count increments."""

    peer_id: int
    count: int


@dataclass
class AllRolesConfirmedUpdate:
    """Broadcast once all pending role assignments have been received."""


# ---------------------------------------------------------------------------
# Player record
# ---------------------------------------------------------------------------


@dataclass
class PlayerInfo:
    name: str
    team: int
    role: int = -1  # -1 = not yet assigned
    ready: bool = False
    avatar_char: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "team": self.team,
            "role": self.role,
            "ready": self.ready,
            "avatar_char": self.avatar_char,
        }


# ---------------------------------------------------------------------------
# Lobby
# ---------------------------------------------------------------------------


class Lobby:
    """
    Server-authoritative lobby state.

    Mirrors LobbyManager.gd's pure-logic responsibilities:
      - Player registration and team balancing
      - Role claiming (one Supporter per team max)
      - Ready state
      - Game-start orchestration (seed, _roles_pending counter)
      - Death count tracking and respawn time calculation
      - Peer disconnect handling

    All methods return a list of update objects. Callers (GameServer) are
    responsible for routing updates to the correct clients.

    Known bug preserved from GDScript (documented in AGENTS.md):
      _roles_pending never decrements when a peer disconnects *before* the
      game starts (role == -1 at disconnect time with game_started=False).
      The original check was `if game_started and role == -1`, which skips
      the decrement for pre-game disconnects. This is intentional parity.
    """

    MAX_PLAYERS: int = 10
    RESPAWN_BASE: float = 10.0
    RESPAWN_INCREMENT: float = 0.0
    RESPAWN_CAP: float = 60.0

    ROLE_FIGHTER: int = 0
    ROLE_SUPPORTER: int = 1

    def __init__(self) -> None:
        self.players: dict[int, PlayerInfo] = {}
        self.game_started: bool = False
        self.supporter_claimed: dict[int, bool] = {0: False, 1: False}
        self.player_death_counts: dict[int, int] = {}
        self._roles_pending: int = 0
        self.host_id: int = 0  # peer_id of first registered player

    # ------------------------------------------------------------------
    # Registration
    # ------------------------------------------------------------------

    def register_player(self, peer_id: int, name: str) -> list:
        """
        Register a new peer. Assigns team by balance.
        The first peer to register becomes the host.
        Returns [LobbyStateUpdate].
        """
        if not self.players:
            self.host_id = peer_id
        team = self._assign_team()
        self.players[peer_id] = PlayerInfo(name=name, team=team)
        return [self._lobby_snapshot()]

    def _assign_team(self) -> int:
        blue = sum(1 for p in self.players.values() if p.team == 0)
        red = sum(1 for p in self.players.values() if p.team == 1)
        return 0 if blue <= red else 1

    # ------------------------------------------------------------------
    # Team override (pre-game only)
    # ------------------------------------------------------------------

    def set_team(self, peer_id: int, team: int) -> list:
        """
        Allow a player to manually switch team (pre-game only).
        Returns [LobbyStateUpdate] or [] if peer unknown / game started.
        """
        if peer_id not in self.players or self.game_started:
            return []
        self.players[peer_id].team = team
        return [self._lobby_snapshot()]

    # ------------------------------------------------------------------
    # Role assignment
    # ------------------------------------------------------------------

    def set_role(self, peer_id: int, role: int) -> list:
        """
        Claim a role for peer_id.

        Fighter: always accepted.
        Supporter: accepted only if the slot for this team is free.

        Returns one of:
          [RoleAcceptedUpdate, LobbyStateUpdate]          — success
          [RoleRejectedUpdate]                            — Supporter slot taken
          []                                              — peer unknown
        """
        if peer_id not in self.players:
            return []

        team = self.players[peer_id].team

        if role == self.ROLE_SUPPORTER:
            if self.supporter_claimed.get(team, False):
                return [
                    RoleRejectedUpdate(
                        peer_id=peer_id, supporter_claimed=dict(self.supporter_claimed)
                    )
                ]
            self.supporter_claimed[team] = True

        self.players[peer_id].role = role
        self._roles_pending -= 1
        if self._roles_pending < 0:
            self._roles_pending = 0

        updates: list = [
            RoleAcceptedUpdate(
                peer_id=peer_id,
                role=role,
                supporter_claimed=dict(self.supporter_claimed),
            ),
            self._lobby_snapshot(),
        ]

        if self._roles_pending == 0:
            updates.append(AllRolesConfirmedUpdate())

        return updates

    # ------------------------------------------------------------------
    # Ready state
    # ------------------------------------------------------------------

    def set_ready(self, peer_id: int, ready: bool) -> list:
        """
        Toggle ready state for peer_id.
        Returns [LobbyStateUpdate] or [] if peer unknown / game started.
        """
        if peer_id not in self.players or self.game_started:
            return []
        self.players[peer_id].ready = ready
        return [self._lobby_snapshot()]

    def can_start_game(self) -> bool:
        """True iff at least one player exists and all players are ready."""
        if not self.players:
            return False
        return all(p.ready for p in self.players.values())

    # ------------------------------------------------------------------
    # Game start
    # ------------------------------------------------------------------

    def start_game(
        self,
        map_seed: int = 0,
        time_seed: int = -1,
        lane_points: list[list[tuple[float, float]]] | None = None,
    ) -> list:
        """
        Transition to in-game state.

        Generates a non-zero map_seed if none is provided (mirrors
        GDScript guard: seed=0 causes TerrainGenerator divergence).

        lane_points — pre-generated lane geometry from lanes.generate_lanes().
                      Defaults to an empty list when None (callers should always
                      pass the result of generate_lanes(map_seed)).

        Returns [GameStartUpdate].
        """
        s = map_seed if map_seed > 0 else random.randint(1, 2**31 - 1)
        # randint(1, ...) never returns 0, but guard defensively
        s = s or 1

        self.supporter_claimed = {0: False, 1: False}
        self.player_death_counts.clear()
        self._roles_pending = len(self.players)
        self.game_started = True

        return [GameStartUpdate(map_seed=s, time_seed=time_seed, lane_points=lane_points or [])]

    # ------------------------------------------------------------------
    # Death counts and respawn time
    # ------------------------------------------------------------------

    def increment_death_count(self, peer_id: int) -> list:
        """
        Increment death count for peer_id and return [DeathCountUpdate].
        """
        self.player_death_counts[peer_id] = self.player_death_counts.get(peer_id, 0) + 1
        count = self.player_death_counts[peer_id]
        return [DeathCountUpdate(peer_id=peer_id, count=count)]

    def get_respawn_time(self, peer_id: int) -> float:
        """
        Respawn timer for peer_id: RESPAWN_BASE + deaths * RESPAWN_INCREMENT,
        capped at RESPAWN_CAP, minimum 1.0 s.
        """
        deaths = self.player_death_counts.get(peer_id, 0)
        t = self.RESPAWN_BASE + deaths * self.RESPAWN_INCREMENT
        t = min(t, self.RESPAWN_CAP)
        return max(1.0, t)

    # ------------------------------------------------------------------
    # Peer disconnect
    # ------------------------------------------------------------------

    def peer_disconnected(self, peer_id: int) -> list:
        """
        Handle a peer disconnecting.

        Mirrors GDScript known-bug behaviour:
          _roles_pending only decrements when game_started=True AND
          the peer had role == -1 at disconnect time. Pre-game disconnects
          with unset roles do NOT decrement (intentional parity with bug).

        Returns [PlayerLeftUpdate, LobbyStateUpdate].
        """
        updates: list = []

        if peer_id in self.players:
            info = self.players[peer_id]
            # Known bug parity: only decrement when in-game and role unset
            if self.game_started and info.role == -1:
                self._roles_pending -= 1
                if self._roles_pending <= 0:
                    self._roles_pending = 0
                    updates.append(AllRolesConfirmedUpdate())

            del self.players[peer_id]

        updates.append(PlayerLeftUpdate(peer_id=peer_id))
        updates.append(self._lobby_snapshot())
        return updates

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    def get_players_by_team(self, team: int) -> list[int]:
        """Return peer_ids on *team*."""
        return [pid for pid, p in self.players.items() if p.team == team]

    def get_supporter_peer(self, team: int) -> int:
        """Return peer_id of the human Supporter on *team*, or -1 if none."""
        for pid, p in self.players.items():
            if p.team == team and p.role == self.ROLE_SUPPORTER:
                return pid
        return -1

    def player_count(self) -> int:
        return len(self.players)

    def reset(self) -> None:
        """
        Reset the lobby to its pre-game state.

        Called by GameServer when the last client disconnects so that the
        next group of players gets a clean lobby without restarting the
        Python process.
        """
        self.players.clear()
        self.game_started = False
        self.supporter_claimed = {0: False, 1: False}
        self.player_death_counts.clear()
        self._roles_pending = 0
        self.host_id = 0

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _lobby_snapshot(self) -> LobbyStateUpdate:
        return LobbyStateUpdate(
            players={pid: p.to_dict() for pid, p in self.players.items()},
            can_start=self.can_start_game(),
            host_id=self.host_id,
        )


# ---------------------------------------------------------------------------
# Module-level registry (used by GameServer)
# ---------------------------------------------------------------------------

_lobby: Lobby | None = None


def get_lobby() -> Lobby:  # pragma: no cover
    global _lobby
    if _lobby is None:
        _lobby = Lobby()
    return _lobby
