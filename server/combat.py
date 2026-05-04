"""
combat.py — Python port of GameSync.gd (Phase 2).

Server-authoritative player combat state: health, death, respawn, shields,
ammo, kill streaks, and bounties.

All cross-system calls (XP award, team-point grant, passive bonus lookup,
bonus-HP lookup, supporter-peer lookup) are injected as callables so this
module is fully testable without the rest of the server stack.  In Phase 3
these callables will be wired to their real Python counterparts.

damage_player() and tick() return lists of update objects for the caller
(GameServer) to broadcast to all clients.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

# ── Update objects ────────────────────────────────────────────────────────────


@dataclass
class HealthUpdate:
    peer_id: int
    health: float


@dataclass
class PlayerDiedUpdate:
    peer_id: int
    respawn_time: float


@dataclass
class PlayerRespawnedUpdate:
    peer_id: int
    spawn_pos: tuple[float, float, float]
    health: float


@dataclass
class BountyActivatedUpdate:
    peer_id: int


@dataclass
class BountyClearedUpdate:
    peer_id: int


@dataclass
class TeamPointsUpdate:
    blue: int
    red: int
    income_blue: int = 0
    income_red: int = 0


# ── Combat ────────────────────────────────────────────────────────────────────


class Combat:
    """
    Owns all per-player combat state.  Mirrors GameSync.gd state dicts.

    Injected callables — all default to safe no-ops:
      award_xp_fn(peer_id, amount)           → called when a kill awards XP
      add_team_points_fn(team, amount)        → called for bounty payouts
      get_team_points_fn(team) -> int         → read back for TeamPointsUpdate
      get_passive_bonus_fn(peer_id, key) -> float
      get_bonus_hp_fn(peer_id) -> float
      get_supporter_peer_fn(team) -> int      → returns supporter peer id or 0
      respawn_time_fn(peer_id) -> float       → respawn duration for peer
    """

    PLAYER_MAX_HP: float = 200.0
    BOUNTY_THRESHOLD: int = 3
    BOUNTY_BASE: int = 10

    # Default spawn positions — (x, y, z) tuples matching GDScript Vector3 values.
    _DEFAULT_SPAWNS: dict[int, tuple[float, float, float]] = {
        0: (0.0, 1.0, 82.0),
        1: (0.0, 1.0, -82.0),
    }

    def __init__(
        self,
        award_xp_fn: Callable[[int, int], None] | None = None,
        add_team_points_fn: Callable[[int, int], None] | None = None,
        get_team_points_fn: Callable[[int], int] | None = None,
        get_passive_bonus_fn: Callable[[int, str], float] | None = None,
        get_bonus_hp_fn: Callable[[int], float] | None = None,
        get_supporter_peer_fn: Callable[[int], int] | None = None,
        respawn_time_fn: Callable[[int], float] | None = None,
    ) -> None:
        self._award_xp = award_xp_fn or (lambda pid, amt: None)
        self._add_team_points = add_team_points_fn or (lambda t, amt: None)
        self._get_team_points = get_team_points_fn or (lambda t: 0)
        self._get_passive_bonus = get_passive_bonus_fn or (lambda pid, k: 0.0)
        self._get_bonus_hp = get_bonus_hp_fn or (lambda pid: 0.0)
        self._get_supporter_peer = get_supporter_peer_fn or (lambda t: 0)
        self._respawn_time = respawn_time_fn or (lambda pid: 5.0)

        # ── Per-player state ──────────────────────────────────────────────────
        self.player_healths: dict[int, float] = {}
        self.player_teams: dict[int, int] = {}
        self.player_dead: dict[int, bool] = {}
        self.respawn_countdown: dict[int, float] = {}
        self.player_reserve_ammo: dict[int, int] = {}
        self.player_weapon_type: dict[int, str] = {}

        # Shields (Iron Skin)
        self.player_shield_hp: dict[int, float] = {}
        self.player_shield_timer: dict[int, float] = {}

        # Kill streaks
        self.player_minion_kill_streak: dict[int, int] = {}
        self.player_tower_kill_streak: dict[int, int] = {}
        self.player_kill_streak: dict[int, int] = {}
        self.player_is_bounty: dict[int, bool] = {}

        # Spawn positions (overridable per-team)
        self.player_spawn_positions: dict[int, tuple[float, float, float]] = dict(
            self._DEFAULT_SPAWNS
        )

    # ── Player registration ───────────────────────────────────────────────────

    def register_player(self, peer_id: int, team: int) -> None:
        """Register a new player with full HP on team *team*."""
        if peer_id in self.player_healths:
            return  # already registered — noop
        self.player_teams[peer_id] = team
        self.player_dead[peer_id] = False
        self.player_minion_kill_streak[peer_id] = 0
        self.player_tower_kill_streak[peer_id] = 0
        self.player_kill_streak[peer_id] = 0
        self.player_is_bounty[peer_id] = False
        max_hp = self.PLAYER_MAX_HP + self._get_bonus_hp(peer_id)
        self.player_healths[peer_id] = max_hp

    def remove_player(self, peer_id: int) -> None:
        """Remove all state for *peer_id*."""
        for d in (
            self.player_healths,
            self.player_teams,
            self.player_dead,
            self.respawn_countdown,
            self.player_reserve_ammo,
            self.player_weapon_type,
            self.player_shield_hp,
            self.player_shield_timer,
            self.player_minion_kill_streak,
            self.player_tower_kill_streak,
            self.player_kill_streak,
            self.player_is_bounty,
        ):
            d.pop(peer_id, None)

    # ── Health queries ────────────────────────────────────────────────────────

    def get_health(self, peer_id: int) -> float:
        return self.player_healths.get(peer_id, self.PLAYER_MAX_HP)

    def set_health(self, peer_id: int, hp: float) -> HealthUpdate:
        self.player_healths[peer_id] = hp
        return HealthUpdate(peer_id=peer_id, health=hp)

    def heal_player(self, peer_id: int, amount: float) -> HealthUpdate:
        """Heal by *amount*, capped at max HP (including bonus HP)."""
        if self.player_dead.get(peer_id, False):
            return HealthUpdate(peer_id=peer_id, health=self.player_healths.get(peer_id, 0.0))
        max_hp = self.PLAYER_MAX_HP + self._get_bonus_hp(peer_id)
        cur = self.player_healths.get(peer_id, max_hp)
        new_hp = min(cur + amount, max_hp)
        self.player_healths[peer_id] = new_hp
        return HealthUpdate(peer_id=peer_id, health=new_hp)

    # ── Damage ────────────────────────────────────────────────────────────────

    def damage_player(  # noqa: C901
        self,
        peer_id: int,
        amount: float,
        source_team: int,
        killer_peer_id: int = -1,
    ) -> list:
        """
        Apply *amount* damage to *peer_id*.

        Returns a list of update objects describing everything that changed.
        Possible elements (in emission order):
          HealthUpdate
          PlayerDiedUpdate         (if kill)
          BountyActivatedUpdate    (if killer reaches BOUNTY_THRESHOLD)
          BountyClearedUpdate      (if bounty target dies)
          TeamPointsUpdate         (if bounty payout changes team points)
        """
        if self.player_dead.get(peer_id, False):
            return []

        updates: list = []

        # ── Drain Iron Skin shield first ──────────────────────────────────────
        actual = amount
        shield = self.player_shield_hp.get(peer_id, 0.0)
        if shield > 0.0:
            absorbed = min(actual, shield)
            shield -= absorbed
            actual -= absorbed
            if shield <= 0.0:
                self.player_shield_hp.pop(peer_id, None)
                self.player_shield_timer.pop(peer_id, None)
            else:
                self.player_shield_hp[peer_id] = shield

        # ── Apply HP damage ───────────────────────────────────────────────────
        hp = self.player_healths.get(peer_id, self.PLAYER_MAX_HP) - actual
        self.player_healths[peer_id] = hp
        updates.append(HealthUpdate(peer_id=peer_id, health=hp))

        if hp > 0.0:
            return updates

        # ── Kill handling ─────────────────────────────────────────────────────
        self.player_dead[peer_id] = True
        respawn_t = self._respawn_time(peer_id)
        self.respawn_countdown[peer_id] = respawn_t
        updates.append(PlayerDiedUpdate(peer_id=peer_id, respawn_time=respawn_t))

        was_bounty = self.player_is_bounty.get(peer_id, False)
        dead_streak = self.player_kill_streak.get(peer_id, 0)

        # Reset dead player's streaks
        self.player_minion_kill_streak[peer_id] = 0
        self.player_tower_kill_streak[peer_id] = 0
        self.player_kill_streak[peer_id] = 0
        self.player_is_bounty[peer_id] = False
        if was_bounty:
            updates.append(BountyClearedUpdate(peer_id=peer_id))

        # ── XP + bounty payout ────────────────────────────────────────────────
        xp = 100  # XP_PLAYER equivalent (matches GDScript LevelSystem.XP_PLAYER)
        if was_bounty:
            xp *= 2

        if killer_peer_id > 0:
            self._award_xp(killer_peer_id, xp)
            if was_bounty:
                killer_team = self.player_teams.get(killer_peer_id, -1)
                if killer_team >= 0:
                    bounty_pts = dead_streak * self.BOUNTY_BASE
                    self._add_team_points(killer_team, bounty_pts)
                    updates.append(
                        TeamPointsUpdate(
                            blue=self._get_team_points(0),
                            red=self._get_team_points(1),
                        )
                    )
            # Update killer streak + bounty flag
            new_streak = self.player_kill_streak.get(killer_peer_id, 0) + 1
            self.player_kill_streak[killer_peer_id] = new_streak
            if new_streak >= self.BOUNTY_THRESHOLD:
                was_already = self.player_is_bounty.get(killer_peer_id, False)
                self.player_is_bounty[killer_peer_id] = True
                if not was_already:
                    updates.append(BountyActivatedUpdate(peer_id=killer_peer_id))

            # Killstreak-heal passive (Bloodrush)
            heal_bonus = self._get_passive_bonus(killer_peer_id, "killstreak_heal")
            if heal_bonus > 0.0:
                max_hp = self.PLAYER_MAX_HP + self._get_bonus_hp(killer_peer_id)
                cur_hp = self.player_healths.get(killer_peer_id, max_hp)
                new_hp = min(cur_hp + 30.0, max_hp)
                self.player_healths[killer_peer_id] = new_hp
                updates.append(HealthUpdate(peer_id=killer_peer_id, health=new_hp))

        elif source_team >= 0:
            sup = self._get_supporter_peer(source_team)
            if sup > 0:
                self._award_xp(sup, xp)

        return updates

    # ── Respawn tick ──────────────────────────────────────────────────────────

    def tick(self, delta: float) -> list[PlayerRespawnedUpdate]:
        """
        Advance all timers by *delta* seconds.

        Ticks:
          - Iron Skin shield duration timers
          - Respawn countdown timers

        Returns a list of PlayerRespawnedUpdate for every player whose
        respawn timer expired this tick.
        """
        # Shield timers
        for pid in list(self.player_shield_timer.keys()):
            t = self.player_shield_timer[pid] - delta
            if t <= 0.0:
                self.player_shield_timer.pop(pid, None)
                self.player_shield_hp.pop(pid, None)
            else:
                self.player_shield_timer[pid] = t

        # Respawn timers
        respawned: list[PlayerRespawnedUpdate] = []
        for pid in list(self.player_dead.keys()):
            if not self.player_dead.get(pid, False):
                continue
            if pid not in self.respawn_countdown:
                continue
            self.respawn_countdown[pid] -= delta
            if self.respawn_countdown[pid] <= 0.0:
                respawned.append(self._do_respawn(pid))
        return respawned

    def _do_respawn(self, peer_id: int) -> PlayerRespawnedUpdate:
        team = self.player_teams.get(peer_id, 0)
        spawn_pos = self.player_spawn_positions.get(team, (0.0, 1.0, 0.0))
        max_hp = self.PLAYER_MAX_HP + self._get_bonus_hp(peer_id)
        self.player_healths[peer_id] = max_hp
        self.player_dead[peer_id] = False
        self.respawn_countdown.pop(peer_id, None)
        return PlayerRespawnedUpdate(
            peer_id=peer_id,
            spawn_pos=spawn_pos,
            health=max_hp,
        )

    # ── Respawn (manual / immediate) ──────────────────────────────────────────

    def respawn_player(self, peer_id: int) -> PlayerRespawnedUpdate:
        """Immediately respawn *peer_id* (bypasses countdown)."""
        self.respawn_countdown.pop(peer_id, None)
        return self._do_respawn(peer_id)

    # ── Shield ────────────────────────────────────────────────────────────────

    def set_shield(self, peer_id: int, hp: float, duration: float) -> None:
        if hp > 0.0:
            self.player_shield_hp[peer_id] = hp
            self.player_shield_timer[peer_id] = duration
        else:
            self.player_shield_hp.pop(peer_id, None)
            self.player_shield_timer.pop(peer_id, None)

    def get_shield_hp(self, peer_id: int) -> float:
        return self.player_shield_hp.get(peer_id, 0.0)

    # ── Ammo ─────────────────────────────────────────────────────────────────

    def set_ammo(self, peer_id: int, reserve: int, weapon_type: str) -> None:
        self.player_reserve_ammo[peer_id] = reserve
        self.player_weapon_type[peer_id] = weapon_type

    def get_ammo(self, peer_id: int) -> int:
        return self.player_reserve_ammo.get(peer_id, 999)

    # ── Team ─────────────────────────────────────────────────────────────────

    def get_team(self, peer_id: int) -> int:
        return self.player_teams.get(peer_id, -1)

    def set_team(self, peer_id: int, team: int) -> None:
        self.player_teams[peer_id] = team

    # ── Spawn positions ───────────────────────────────────────────────────────

    def get_spawn_position(self, team: int) -> tuple[float, float, float]:
        return self.player_spawn_positions.get(team, (0.0, 1.0, 0.0))

    def set_spawn_position(self, team: int, pos: tuple[float, float, float]) -> None:
        self.player_spawn_positions[team] = pos

    # ── Streak helpers ────────────────────────────────────────────────────────

    def record_minion_kill(self, peer_id: int) -> int:
        """Increment minion kill streak for *peer_id*; returns new count."""
        n = self.player_minion_kill_streak.get(peer_id, 0) + 1
        self.player_minion_kill_streak[peer_id] = n
        return n

    def record_tower_kill(self, peer_id: int) -> int:
        """Increment tower kill streak for *peer_id*; returns new count."""
        n = self.player_tower_kill_streak.get(peer_id, 0) + 1
        self.player_tower_kill_streak[peer_id] = n
        return n

    # ── Reset ─────────────────────────────────────────────────────────────────

    def reset(self) -> None:
        """Clear all per-player state and restore default spawn positions."""
        self.player_healths.clear()
        self.player_teams.clear()
        self.player_dead.clear()
        self.respawn_countdown.clear()
        self.player_reserve_ammo.clear()
        self.player_weapon_type.clear()
        self.player_shield_hp.clear()
        self.player_shield_timer.clear()
        self.player_minion_kill_streak.clear()
        self.player_tower_kill_streak.clear()
        self.player_kill_streak.clear()
        self.player_is_bounty.clear()
        self.player_spawn_positions = dict(self._DEFAULT_SPAWNS)
