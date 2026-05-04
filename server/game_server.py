"""
game_server.py — Core server: client registry, event dispatch, broadcast.

Phase 0: ping/pong.
Phase 3: lobby events (register_player, set_role, set_ready, start_game,
         set_team, peer_disconnected).
Phase 4: entity sync contracts — all game-state events wired through one
         broadcast path. Host-only bugs are structurally eliminated.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Protocol

from server.build import (
    Build,
    DropConsumedUpdate,
    PlacementRejectedUpdate,
    TowerDamagedUpdate,
    TowerDespawnedUpdate,
    TowerSpawnedUpdate,
    TowerVisualUpdate,
)
from server.combat import (
    BountyActivatedUpdate,
    BountyClearedUpdate,
    Combat,
    HealthUpdate,
    PlayerDiedUpdate,
    PlayerRespawnedUpdate,
    TeamPointsUpdate,
)
from server.economy import TeamEconomy
from server.game_state import GameOverUpdate, GameStateMachine, LivesUpdate
from server.lanes import generate_lanes
from server.lobby import (
    AllRolesConfirmedUpdate,
    DeathCountUpdate,
    GameStartUpdate,
    LoadGameUpdate,
    Lobby,
    LobbyStateUpdate,
    PlayerLeftUpdate,
    RoleAcceptedUpdate,
    RoleRejectedUpdate,
)
from server.minion_state import (
    MinionDamagedUpdate,
    MinionDiedUpdate,
    MinionStateManager,
    MinionWaveSpawnedUpdate,
)
from server.progression import LevelUpEvent, Progression
from server.protocol import make_update
from server.skills_state import (
    ActiveSlotsChangedEvent,
    ActiveUsedEvent,
    CooldownTickEvent,
    SkillPtsChangedEvent,
    SkillState,
    SkillUnlockedEvent,
)
from server.territory import BuildLimitUpdate, Territory, TowerDestroyedByPushUpdate
from server.wave_manager import SpawnWaveEvent, WaveAnnouncedEvent, WaveInfoUpdate, WaveManager


class ClientHandle(Protocol):
    """Interface expected by GameServer for each connected client."""

    def send_update(self, update: dict) -> None:
        """Send a StateUpdate dict to this client."""
        ...


# ---------------------------------------------------------------------------
# Local update dataclasses (visual relay — no game-state meaning)
# ---------------------------------------------------------------------------

log = logging.getLogger(__name__)


@dataclass
class SpawnVisualUpdate:
    """Opaque visual broadcast: Python relays params unchanged to all clients."""

    visual_type: str
    params: dict = field(default_factory=dict)


@dataclass
class BroadcastTransformUpdate:
    """Relay a player position update to all other peers."""

    peer_id: int
    pos: list
    rot: list
    team: int


@dataclass
class SeedTransformUpdate:
    """Reliable initial-position seed for a peer at spawn time."""

    peer_id: int
    pos: list
    rot: list
    team: int


@dataclass
class SyncMinionStatesUpdate:
    """Batch minion puppet state relay."""

    ids: list
    positions: list
    rotations: list
    healths: list


@dataclass
class SpawnMissileVisualsUpdate:
    """Relay a missile spawn visual to all clients."""

    fire_pos: list
    target_pos: list
    team: int
    launcher_type: str


@dataclass
class SyncDestroyTreeUpdate:
    """Relay a tree-destruction event to all clients."""

    pos: list


@dataclass
class SyncLaneBoostsUpdate:
    """Relay current lane boost state to all clients."""

    boosts_team0: list
    boosts_team1: list


@dataclass
class BroadcastReconRevealUpdate:
    """Relay a recon-reveal effect to all clients."""

    target_pos: list
    radius: float
    duration: float
    team: int


@dataclass
class BroadcastPingUpdate:
    """Relay a map ping to all clients."""

    world_pos: list
    team: int
    color: list


@dataclass
class SkillEffectUpdate:
    """Deliver a skill effect (dash, rapid_fire, iron_skin, rally_cry) to one peer."""

    effect: str
    target_peer_id: int
    params: dict = field(default_factory=dict)


@dataclass
class SyncLimitStateUpdate:
    """Relay territory push-limit state to all clients."""

    team: int
    level: int
    p_timer: float
    r_timer: float


# WaveInfoUpdate is imported from wave_manager — no local duplicate needed.

# ---------------------------------------------------------------------------
# Update → wire dict serialisation
# ---------------------------------------------------------------------------


def _serialise(update: object) -> dict:  # noqa: C901
    """Convert any update/event dataclass to a wire-format dict."""
    # ── Lobby ──────────────────────────────────────────────────────────────
    if isinstance(update, LobbyStateUpdate):
        return make_update(
            "lobby_state",
            {
                "players": update.players,
                "can_start": update.can_start,
                "host_id": update.host_id,
                "your_peer_id": 0,  # overwritten per-client in _dispatch_updates
            },
        )
    if isinstance(update, RoleAcceptedUpdate):
        return make_update(
            "role_accepted",
            {
                "peer_id": update.peer_id,
                "role": update.role,
                "supporter_claimed": update.supporter_claimed,
            },
        )
    if isinstance(update, RoleRejectedUpdate):
        return make_update(
            "role_rejected",
            {
                "peer_id": update.peer_id,
                "supporter_claimed": update.supporter_claimed,
            },
        )
    if isinstance(update, GameStartUpdate):
        return make_update(
            "game_started",
            {
                "map_seed": update.map_seed,
                "time_seed": update.time_seed,
                "lane_points": update.lane_points,
            },
        )
    if isinstance(update, PlayerLeftUpdate):
        return make_update("player_left", {"peer_id": update.peer_id})
    if isinstance(update, LoadGameUpdate):
        return make_update("load_game", {"path": update.path})
    if isinstance(update, DeathCountUpdate):
        return make_update(
            "death_count",
            {"peer_id": update.peer_id, "count": update.count},
        )
    if isinstance(update, AllRolesConfirmedUpdate):
        return make_update("all_roles_confirmed", {})

    # ── Combat ─────────────────────────────────────────────────────────────
    if isinstance(update, HealthUpdate):
        return make_update("player_health", {"peer_id": update.peer_id, "health": update.health})
    if isinstance(update, PlayerDiedUpdate):
        return make_update(
            "player_died",
            {"peer_id": update.peer_id, "respawn_time": update.respawn_time},
        )
    if isinstance(update, PlayerRespawnedUpdate):
        return make_update(
            "player_respawned",
            {
                "peer_id": update.peer_id,
                "spawn_pos": list(update.spawn_pos),
                "health": update.health,
            },
        )
    if isinstance(update, TeamPointsUpdate):
        return make_update(
            "team_points",
            {
                "blue": update.blue,
                "red": update.red,
                "income_blue": update.income_blue,
                "income_red": update.income_red,
            },
        )
    if isinstance(update, BountyActivatedUpdate):
        return make_update("bounty_activated", {"peer_id": update.peer_id})
    if isinstance(update, BountyClearedUpdate):
        return make_update("bounty_cleared", {"peer_id": update.peer_id})

    # ── Towers ─────────────────────────────────────────────────────────────
    if isinstance(update, TowerSpawnedUpdate):
        return make_update(
            "tower_spawned",
            {
                "name": update.name,
                "tower_type": update.tower_type,
                "team": update.team,
                "pos": list(update.pos),
                "health": update.health,
                "max_health": update.max_health,
            },
        )
    if isinstance(update, TowerDamagedUpdate):
        return make_update("tower_damaged", {"name": update.name, "health": update.health})
    if isinstance(update, TowerDespawnedUpdate):
        return make_update(
            "tower_despawned",
            {"name": update.name, "tower_type": update.tower_type, "team": update.team},
        )
    if isinstance(update, PlacementRejectedUpdate):
        return make_update("placement_rejected", {"reason": update.reason})

    # ── Minions ────────────────────────────────────────────────────────────
    if isinstance(update, MinionWaveSpawnedUpdate):
        return make_update(
            "minion_wave_spawned",
            {
                "team": update.team,
                "lane": update.lane,
                "minion_type": update.minion_type,
                "minion_ids": update.minion_ids,
            },
        )
    if isinstance(update, MinionDamagedUpdate):
        return make_update(
            "minion_damaged", {"minion_id": update.minion_id, "health": update.health}
        )
    if isinstance(update, MinionDiedUpdate):
        return make_update(
            "minion_died",
            {
                "minion_id": update.minion_id,
                "minion_type": update.minion_type,
                "team": update.team,
                "killer_peer_id": update.killer_peer_id,
            },
        )

    # ── Game state ─────────────────────────────────────────────────────────
    if isinstance(update, LivesUpdate):
        return make_update("team_lives", {"team": update.team, "lives": update.lives})
    if isinstance(update, GameOverUpdate):
        return make_update("game_over", {"winner": update.winner})

    # ── Progression ────────────────────────────────────────────────────────
    if isinstance(update, LevelUpEvent):
        return make_update(
            "level_up",
            {
                "peer_id": update.peer_id,
                "new_level": update.new_level,
                "pts_awarded": update.pts_awarded,
            },
        )

    # ── Skills ─────────────────────────────────────────────────────────────
    if isinstance(update, SkillUnlockedEvent):
        return make_update("skill_unlocked", {"peer_id": update.peer_id, "node_id": update.node_id})
    if isinstance(update, SkillPtsChangedEvent):
        return make_update("skill_pts_changed", {"peer_id": update.peer_id, "pts": update.pts})
    if isinstance(update, ActiveSlotsChangedEvent):
        return make_update(
            "active_slots_changed", {"peer_id": update.peer_id, "slots": update.slots}
        )
    if isinstance(update, ActiveUsedEvent):
        return make_update("active_used", {"peer_id": update.peer_id, "node_id": update.node_id})
    if isinstance(update, CooldownTickEvent):
        return make_update(
            "cooldown_tick", {"peer_id": update.peer_id, "cooldowns": update.cooldowns}
        )

    # ── Territory ──────────────────────────────────────────────────────────
    if isinstance(update, BuildLimitUpdate):
        return make_update(
            "build_limit",
            {"team": update.team, "new_level": update.new_level, "new_z": update.new_z},
        )
    if isinstance(update, TowerDestroyedByPushUpdate):
        return make_update(
            "tower_destroyed_by_push",
            {"team": update.team, "tower_name": update.tower_name, "tower_z": update.tower_z},
        )

    # ── Waves ──────────────────────────────────────────────────────────────────
    if isinstance(update, WaveAnnouncedEvent):
        return make_update("wave_announced", {"wave_number": update.wave_number})
    if isinstance(update, SpawnWaveEvent):
        return make_update(
            "spawn_wave",
            {
                "wave_number": update.wave_number,
                "team": update.team,
                "lane": update.lane,
                "minion_type": update.minion_type,
                "count": update.count,
            },
        )

    # ── Visual relay ───────────────────────────────────────────────────────────
    if isinstance(update, SpawnVisualUpdate):
        return make_update(
            "spawn_visual",
            {"visual_type": update.visual_type, "params": update.params},
        )
    if isinstance(update, TowerVisualUpdate):
        return make_update("tower_visual", {"type": update.vtype, **update.params})
    if isinstance(update, DropConsumedUpdate):
        return make_update("drop_despawned", {"name": update.name, "team": update.team})

    # ── Relay updates (positional / visual, no game-state meaning) ─────────────
    if isinstance(update, BroadcastTransformUpdate):
        return make_update(
            "broadcast_transform",
            {
                "peer_id": update.peer_id,
                "pos": update.pos,
                "rot": update.rot,
                "team": update.team,
            },
        )
    if isinstance(update, SeedTransformUpdate):
        return make_update(
            "seed_transform",
            {
                "peer_id": update.peer_id,
                "pos": update.pos,
                "rot": update.rot,
                "team": update.team,
            },
        )
    if isinstance(update, SyncMinionStatesUpdate):
        return make_update(
            "sync_minion_states",
            {
                "ids": update.ids,
                "positions": update.positions,
                "rotations": update.rotations,
                "healths": update.healths,
            },
        )
    if isinstance(update, SpawnMissileVisualsUpdate):
        return make_update(
            "spawn_missile_visuals",
            {
                "fire_pos": update.fire_pos,
                "target_pos": update.target_pos,
                "team": update.team,
                "launcher_type": update.launcher_type,
            },
        )
    if isinstance(update, SyncDestroyTreeUpdate):
        return make_update("sync_destroy_tree", {"pos": update.pos})
    if isinstance(update, SyncLaneBoostsUpdate):
        return make_update(
            "sync_lane_boosts",
            {"boosts_team0": update.boosts_team0, "boosts_team1": update.boosts_team1},
        )
    if isinstance(update, BroadcastReconRevealUpdate):
        return make_update(
            "broadcast_recon_reveal",
            {
                "target_pos": update.target_pos,
                "radius": update.radius,
                "duration": update.duration,
                "team": update.team,
            },
        )
    if isinstance(update, BroadcastPingUpdate):
        return make_update(
            "broadcast_ping",
            {"world_pos": update.world_pos, "team": update.team, "color": update.color},
        )
    if isinstance(update, SkillEffectUpdate):
        return make_update(
            "skill_effect",
            {
                "effect": update.effect,
                "target_peer_id": update.target_peer_id,
                "params": update.params,
            },
        )
    if isinstance(update, SyncLimitStateUpdate):
        return make_update(
            "sync_limit_state",
            {
                "team": update.team,
                "level": update.level,
                "p_timer": update.p_timer,
                "r_timer": update.r_timer,
            },
        )
    if isinstance(update, WaveInfoUpdate):
        return make_update(
            "wave_info",
            {"wave_number": update.wave_number, "next_in_seconds": update.next_in_seconds},
        )

    # Fallback — should not be reached in normal operation
    return make_update("unknown", {})


class GameServer:
    """
    Central game server.

    Clients register themselves with register(). The server dispatches
    incoming events via handle() and broadcasts StateUpdates to all
    registered clients via _broadcast().

    Phase 3: Lobby wired in for full pre-game flow.
    Phase 4: All game-state modules wired in; single broadcast path for every
             entity type eliminates host-only bugs by construction.
    """

    def __init__(self) -> None:
        # peer_id → ClientHandle
        self._clients: dict[int, ClientHandle] = {}

        # ── Subsystems (constructed here; callables wired together) ────────
        self.lobby = Lobby()
        self.economy = TeamEconomy()
        self.game_state = GameStateMachine()
        self.progression = Progression(
            get_role_fn=lambda pid: self.skills.get_role(pid),
        )
        self.skills = SkillState(
            get_level_fn=lambda pid: self.progression.get_level(pid),
        )
        self.combat = Combat(
            award_xp_fn=lambda pid, amt: self._award_xp_and_broadcast(pid, amt),
            add_team_points_fn=lambda t, a: self.economy.add_points(t, a),
            get_team_points_fn=lambda t: self.economy.get_points(t),
            get_passive_bonus_fn=lambda pid, k: self.skills.get_passive_bonus(pid, k),
            get_bonus_hp_fn=lambda pid: self.progression.get_bonus_hp(pid),
            get_supporter_peer_fn=lambda t: self._get_supporter_peer(t),
            respawn_time_fn=lambda pid: self.lobby.get_respawn_time(pid),
        )
        self.build = Build(
            spend_points_fn=lambda t, a: self.economy.spend_points(t, a),
            award_xp_fn=lambda pid, amt: self._award_xp_and_broadcast(pid, amt),
            add_team_points_fn=lambda t, a: self.economy.add_points(t, a),
            get_team_points_fn=lambda t: self.economy.get_points(t),
        )
        self.minions = MinionStateManager(
            award_xp_fn=lambda pid, amt: self._award_xp_and_broadcast(pid, amt),
            add_team_points_fn=lambda t, a: self.economy.add_points(t, a),
            get_team_points_fn=lambda t: self.economy.get_points(t),
        )
        self.territory = Territory()
        self.waves = WaveManager()

        # Dispatch table built after all subsystems are ready
        self._dispatch: dict = self._build_dispatch_table()

    # ------------------------------------------------------------------
    # Client lifecycle
    # ------------------------------------------------------------------

    def register(self, peer_id: int, client: ClientHandle) -> None:
        """Register a connected Godot client."""
        self._clients[peer_id] = client

    def unregister(self, peer_id: int) -> None:
        """
        Remove a disconnected client and notify the lobby.
        Broadcasts PlayerLeftUpdate + LobbyStateUpdate to remaining clients.
        When the last client disconnects, resets all subsystems so the next
        group of players gets a clean server without a process restart.
        """
        self._clients.pop(peer_id, None)
        self.combat.remove_player(peer_id)
        self.progression.clear_peer(peer_id)
        self.skills.clear_peer(peer_id)
        updates = self.lobby.peer_disconnected(peer_id)
        self._dispatch_updates(updates, directed_peer=None)

        if not self._clients:
            self._reset_all_subsystems()

    def _reset_all_subsystems(self) -> None:
        """Reset all stateful subsystems to pre-game state."""
        self.lobby.reset()
        self.economy.reset()
        self.combat.reset()
        self.build.reset()
        self.waves.reset()
        self.minions.reset()
        self.territory.reset()
        self.game_state.reset()
        self.progression.clear_all()
        self.skills.clear_all()

    def client_count(self) -> int:
        return len(self._clients)

    def tick(self, delta: float) -> None:
        """Advance all time-based subsystems by *delta* seconds and broadcast results."""
        combat_updates = self.combat.tick(delta)
        self._dispatch_updates(combat_updates, directed_peer=None)

        skill_updates = self.skills.tick(delta)
        self._dispatch_updates(skill_updates, directed_peer=None)

        territory_updates = self.territory.tick(delta, [None, None, None], [None, None, None])
        self._dispatch_updates(territory_updates, directed_peer=None)

        wave_updates = self.waves.tick(delta)
        self._dispatch_updates(wave_updates, directed_peer=None)
        # Pay out passive income every wave tick and broadcast updated economy.
        if any(isinstance(u, WaveAnnouncedEvent) for u in wave_updates):
            for team in range(2):
                self.economy.payout_passive_income(team)
            self._broadcast(_serialise(self._make_pts_update()))

    def _build_dispatch_table(self) -> dict:
        """Return a mapping of event type string → handler callable."""
        return {
            "ping": self._handle_ping,
            "register_player": self._handle_register_player,
            "set_team": self._handle_set_team,
            "set_role": self._handle_set_role,
            "set_role_ingame": self._handle_set_role,
            "set_ready": self._handle_set_ready,
            "start_game": self._handle_start_game,
            "place_tower": self._handle_place_tower,
            "remove_tower": self._handle_remove_tower,
            "damage_tower": self._handle_damage_tower,
            "damage_player": self._handle_damage_player,
            "player_respawned": self._handle_player_respawned,
            "spawn_minion_wave": self._handle_spawn_minion_wave,
            "damage_minion": self._handle_damage_minion,
            "use_skill": self._handle_use_skill,
            "unlock_skill": self._handle_unlock_skill,
            "assign_active": self._handle_assign_active,
            "spend_attribute": self._handle_spend_attribute,
            "lose_life": self._handle_lose_life,
            "request_lane_boost": self._handle_boost_lane,
            "fire_projectile": self._handle_fire_projectile,
            "heal_player": self._handle_heal_player,
            "register_drop": self._handle_register_drop,
            "drop_picked_up": self._handle_drop_picked_up,
            "tower_hit_visual": self._handle_tower_hit_visual,
            "tower_visual": self._handle_tower_visual,
            "minion_hit_visual": self._handle_minion_hit_visual,
            # ── Positional / visual relay ──────────────────────────────────────
            "report_transform": self._handle_report_transform,
            "report_initial_transform": self._handle_report_initial_transform,
            "report_avatar": self._handle_report_avatar,
            "sync_minion_states": self._handle_sync_minion_states,
            "request_fire_missile": self._handle_request_fire_missile,
            "destroy_tree": self._handle_destroy_tree,
            "recon_reveal": self._handle_recon_reveal,
            "request_recon_reveal": self._handle_recon_reveal,
            "request_ping": self._handle_request_ping,
            "apply_skill_effect": self._handle_apply_skill_effect,
            "sync_limit_state": self._handle_sync_limit_state_relay,
            "report_lane_boosts": self._handle_report_lane_boosts,
            "request_ram_minion": self._handle_request_ram_minion,
            "bounty_state": self._handle_bounty_state_notify,
            "spawn_visual": self._handle_spawn_visual_relay,
        }

    # ------------------------------------------------------------------
    # Event processing
    # ------------------------------------------------------------------

    def handle(self, sender_id: int, event: dict) -> None:
        """
        Process one incoming event dict.

        event format: {"type": str, "sender_id": int, "payload": dict}
        """
        event_type = event.get("type", "")
        payload = event.get("payload", {})
        handler = self._dispatch.get(event_type)
        if handler is not None:
            handler(sender_id, payload)

    # ------------------------------------------------------------------
    # Lobby event handlers
    # ------------------------------------------------------------------

    def _handle_register_player(self, sender_id: int, payload: dict) -> None:
        name = payload.get("name", f"Player_{sender_id}")
        updates = self.lobby.register_player(sender_id, name)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_set_team(self, sender_id: int, payload: dict) -> None:
        team = payload.get("team", 0)
        updates = self.lobby.set_team(sender_id, team)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_set_role(self, sender_id: int, payload: dict) -> None:
        role = payload.get("role", 0)
        updates = self.lobby.set_role(sender_id, role)
        for update in updates:
            if isinstance(update, RoleRejectedUpdate):
                self._send_to(sender_id, _serialise(update))
            else:
                self._broadcast(_serialise(update))
                if isinstance(update, RoleAcceptedUpdate):
                    # Wire subsystems that need per-peer registration at role-confirm time.
                    role_str = "Supporter" if update.role == 1 else "Fighter"
                    player_info = self.lobby.players.get(sender_id)
                    team = player_info.team if player_info is not None else 0
                    self.progression.register_peer(sender_id)
                    skill_updates = self.skills.register_peer(sender_id, role_str)
                    self.combat.register_player(sender_id, team)
                    self._dispatch_updates(skill_updates, directed_peer=None)

    def _handle_set_ready(self, sender_id: int, payload: dict) -> None:
        ready = payload.get("ready", False)
        updates = self.lobby.set_ready(sender_id, ready)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_start_game(self, sender_id: int, payload: dict) -> None:
        map_seed = payload.get("map_seed", 0)
        time_seed = payload.get("time_seed", -1)
        # Generate lane geometry server-side; wire into Build and broadcast.
        lanes = generate_lanes(map_seed)
        self.build.set_lane_points(lanes)
        self.waves.reset()
        updates = self.lobby.start_game(map_seed=map_seed, time_seed=time_seed, lane_points=lanes)
        self._dispatch_updates(updates, directed_peer=None)
        # Tell all clients to change scene.
        self._broadcast(_serialise(LoadGameUpdate(path="res://scenes/Main.tscn")))

    # ------------------------------------------------------------------
    # Tower event handlers
    # ------------------------------------------------------------------

    def _handle_place_tower(self, sender_id: int, payload: dict) -> None:
        raw_pos = payload.get("pos", [0.0, 0.0, 0.0])
        pos: tuple[float, float, float] = (
            float(raw_pos[0]),
            float(raw_pos[1]),
            float(raw_pos[2]),
        )
        team = payload.get("team", 0)
        item_type = payload.get("tower_type", "")
        placer_peer_id = payload.get("placer_peer_id", sender_id)
        forced_name = payload.get("forced_name", "")
        spacing_mult = float(payload.get("spacing_mult", 1.0))
        updates = self.build.place_tower(
            pos, team, item_type, placer_peer_id, forced_name, spacing_mult=spacing_mult
        )
        pts_update = self._make_pts_update()
        if updates and isinstance(updates[0], TowerSpawnedUpdate):
            # Success: broadcast spawn + updated economy to all clients.
            updates.append(pts_update)
            self._dispatch_updates(updates, directed_peer=None)
        else:
            # Rejection: broadcast the rejection, then correct only the requester's economy.
            self._dispatch_updates(updates, directed_peer=None)
            self._dispatch_updates([pts_update], directed_peer=sender_id)

    def _handle_remove_tower(self, sender_id: int, payload: dict) -> None:
        name = payload.get("name", "")
        source_team = payload.get("source_team", -1)
        updates = self.build.remove_tower(name, source_team)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_damage_tower(self, sender_id: int, payload: dict) -> None:
        name = payload.get("name", "")
        amount = float(payload.get("amount", 0.0))
        source_team = payload.get("source_team", -1)
        shooter_peer_id = payload.get("shooter_peer_id", -1)
        updates = self.build.damage_tower(name, amount, source_team, shooter_peer_id)
        self._dispatch_updates(updates, directed_peer=None)

    # ------------------------------------------------------------------
    # Player event handlers
    # ------------------------------------------------------------------

    def _handle_damage_player(self, sender_id: int, payload: dict) -> None:
        peer_id = payload.get("peer_id", sender_id)
        amount = float(payload.get("amount", 0.0))
        source_team = payload.get("source_team", -1)
        killer_peer_id = payload.get("killer_peer_id", -1)
        updates = self.combat.damage_player(peer_id, amount, source_team, killer_peer_id)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_player_respawned(self, sender_id: int, payload: dict) -> None:
        peer_id = payload.get("peer_id", sender_id)
        update = self.combat.respawn_player(peer_id)
        self._broadcast(_serialise(update))

    def _handle_fire_projectile(self, sender_id: int, payload: dict) -> None:
        """Relay visual-only projectile spawn to all clients except the sender."""
        visual_type = payload.get("visual_type", "bullet")
        params = payload.get("params", {})
        relay_targets = [pid for pid in self._clients if pid != sender_id]
        # Bullets use array keys "pos"/"dir"; ballistic projectiles (cannonball,
        # mortar) use flat scalar keys "pos_x/y/z" and "target_x/y/z".  Fall back
        # to the flat keys so the log line is meaningful for all projectile types.
        log_pos = params.get("pos") or (
            [params.get("pos_x"), params.get("pos_y"), params.get("pos_z")]
            if params.get("pos_x") is not None
            else None
        )
        log_dir = params.get("dir") or (
            [params.get("target_x"), params.get("target_y"), params.get("target_z")]
            if params.get("target_x") is not None
            else None
        )
        log.debug(
            "fire_projectile from peer %d: type=%s pos=%s dir/target=%s "
            "team=%s shooter_peer_id=%s damage=%s → relaying to peers %s",
            sender_id,
            visual_type,
            log_pos,
            log_dir,
            params.get("shooter_team") or params.get("team"),
            params.get("shooter_peer_id"),
            params.get("damage"),
            relay_targets,
        )
        update = _serialise(SpawnVisualUpdate(visual_type=visual_type, params=params))
        for pid, client in self._clients.items():
            if pid != sender_id:
                log.debug("  → sending spawn_visual type=%s to peer %d", visual_type, pid)
                client.send_update(update)

    def _handle_heal_player(self, sender_id: int, payload: dict) -> None:
        peer_id = payload.get("peer_id", sender_id)
        amount = float(payload.get("amount", 0.0))
        update = self.combat.heal_player(peer_id, amount)
        self._broadcast(_serialise(update))

    # ------------------------------------------------------------------
    # Drop event handlers
    # ------------------------------------------------------------------

    def _handle_register_drop(self, sender_id: int, payload: dict) -> None:
        """Register a pickup as live on the map (called when Godot spawns it)."""
        name = payload.get("name", "")
        team = payload.get("team", 0)
        self.build.register_drop(name, team)

    def _handle_drop_picked_up(self, sender_id: int, payload: dict) -> None:
        """
        Validate a pickup attempt.  On success, broadcast drop_despawned to all.
        On failure (unknown or already consumed), no broadcast is sent.
        """
        name = payload.get("name", "")
        updates = self.build.consume_drop(name)
        self._dispatch_updates(updates, directed_peer=None)

    # ------------------------------------------------------------------
    # Tower/minion visual relay handlers
    # ------------------------------------------------------------------

    def _handle_tower_hit_visual(self, sender_id: int, payload: dict) -> None:
        """Relay a tower hit-flash visual to all clients."""
        self._broadcast(_serialise(TowerVisualUpdate(vtype="tower_hit", params=dict(payload))))

    def _handle_tower_visual(self, sender_id: int, payload: dict) -> None:
        """Relay an arbitrary tower visual (MG rotation, slow pulse, etc.) to all clients."""
        vtype = payload.get("vtype", "")
        params = {k: v for k, v in payload.items() if k != "vtype"}
        self._broadcast(_serialise(TowerVisualUpdate(vtype=vtype, params=params)))

    def _handle_minion_hit_visual(self, sender_id: int, payload: dict) -> None:
        """Relay a minion hit-flash visual to all clients."""
        self._broadcast(_serialise(TowerVisualUpdate(vtype="minion_hit", params=dict(payload))))

    def _handle_spawn_visual_relay(self, sender_id: int, payload: dict) -> None:
        """Relay a spawn_visual message from the host to all non-sender clients.

        Used to propagate minion_spawn (and similar) visuals so non-host clients
        can create puppet nodes for newly-spawned minions.
        """
        visual_type = payload.get("visual_type", "")
        params = payload.get("params", {})
        update = _serialise(SpawnVisualUpdate(visual_type=visual_type, params=params))
        for pid, client in self._clients.items():
            if pid != sender_id:
                client.send_update(update)

    # ------------------------------------------------------------------
    # Positional / visual relay handlers
    # ------------------------------------------------------------------

    def _handle_report_transform(self, sender_id: int, payload: dict) -> None:
        """Relay unreliable player transform to all other clients (exclude sender)."""
        update = BroadcastTransformUpdate(
            peer_id=sender_id,
            pos=payload.get("pos", [0.0, 0.0, 0.0]),
            rot=payload.get("rot", [0.0, 0.0, 0.0]),
            team=payload.get("team", 0),
        )
        msg = _serialise(update)
        for pid, client in self._clients.items():
            if pid != sender_id:
                client.send_update(msg)

    def _handle_report_initial_transform(self, sender_id: int, payload: dict) -> None:
        """Relay reliable initial transform seed to all other clients."""
        update = SeedTransformUpdate(
            peer_id=sender_id,
            pos=payload.get("pos", [0.0, 0.0, 0.0]),
            rot=payload.get("rot", [0.0, 0.0, 0.0]),
            team=payload.get("team", 0),
        )
        msg = _serialise(update)
        for pid, client in self._clients.items():
            if pid != sender_id:
                client.send_update(msg)

    def _handle_report_avatar(self, sender_id: int, payload: dict) -> None:
        """Store avatar char and broadcast updated lobby_state to all clients."""
        char = payload.get("char", "")
        player = self.lobby.players.get(sender_id)
        if player is not None and char:
            player.avatar_char = char
        self._broadcast(_serialise(self.lobby._lobby_snapshot()))

    def _handle_sync_minion_states(self, sender_id: int, payload: dict) -> None:
        """Relay batch minion puppet state to all other clients."""
        update = SyncMinionStatesUpdate(
            ids=payload.get("ids", []),
            positions=payload.get("positions", []),
            rotations=payload.get("rotations", []),
            healths=payload.get("healths", []),
        )
        msg = _serialise(update)
        for pid, client in self._clients.items():
            if pid != sender_id:
                client.send_update(msg)

    def _handle_request_fire_missile(self, sender_id: int, payload: dict) -> None:
        """Relay missile spawn visual to all clients."""
        update = SpawnMissileVisualsUpdate(
            fire_pos=payload.get("fire_pos", [0.0, 0.0, 0.0]),
            target_pos=payload.get("target_pos", [0.0, 0.0, 0.0]),
            team=payload.get("team", 0),
            launcher_type=payload.get("launcher_type", ""),
        )
        self._broadcast(_serialise(update))

    def _handle_destroy_tree(self, sender_id: int, payload: dict) -> None:
        """Relay tree-destruction to all clients."""
        update = SyncDestroyTreeUpdate(pos=payload.get("pos", [0.0, 0.0, 0.0]))
        self._broadcast(_serialise(update))

    def _handle_recon_reveal(self, sender_id: int, payload: dict) -> None:
        """Relay recon reveal to all clients."""
        update = BroadcastReconRevealUpdate(
            target_pos=payload.get("target_pos", [0.0, 0.0, 0.0]),
            radius=float(payload.get("radius", 0.0)),
            duration=float(payload.get("duration", 0.0)),
            team=payload.get("team", 0),
        )
        self._broadcast(_serialise(update))

    def _handle_request_ping(self, sender_id: int, payload: dict) -> None:
        """Relay map ping to all clients."""
        update = BroadcastPingUpdate(
            world_pos=payload.get("world_pos", [0.0, 0.0, 0.0]),
            team=payload.get("team", 0),
            color=payload.get("color", [0.62, 0.0, 1.0, 1.0]),
        )
        self._broadcast(_serialise(update))

    def _handle_apply_skill_effect(self, sender_id: int, payload: dict) -> None:
        """Forward a skill effect only to the target peer."""
        target_peer_id = payload.get("target_peer_id", sender_id)
        update = SkillEffectUpdate(
            effect=payload.get("effect", ""),
            target_peer_id=target_peer_id,
            params=payload.get("params", {}),
        )
        self._send_to(target_peer_id, _serialise(update))

    def _handle_sync_limit_state_relay(self, sender_id: int, payload: dict) -> None:
        """Relay territory push-limit state to all clients."""
        update = SyncLimitStateUpdate(
            team=payload.get("team", 0),
            level=payload.get("level", 0),
            p_timer=float(payload.get("p_timer", 0.0)),
            r_timer=float(payload.get("r_timer", 0.0)),
        )
        self._broadcast(_serialise(update))

    def _handle_report_lane_boosts(self, sender_id: int, payload: dict) -> None:
        """Relay current lane boost state to all clients."""
        update = SyncLaneBoostsUpdate(
            boosts_team0=payload.get("boosts_team0", []),
            boosts_team1=payload.get("boosts_team1", []),
        )
        self._broadcast(_serialise(update))

    # ------------------------------------------------------------------
    # Minion event handlers
    # ------------------------------------------------------------------

    def _handle_spawn_minion_wave(self, sender_id: int, payload: dict) -> None:
        team = payload.get("team", 0)
        lane = payload.get("lane", 0)
        minion_type = payload.get("minion_type", "standard")
        count = payload.get("count", 1)
        updates = self.minions.spawn_wave(team, lane, minion_type, count)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_damage_minion(self, sender_id: int, payload: dict) -> None:
        minion_id = payload.get("minion_id", -1)
        amount = float(payload.get("amount", 0.0))
        source_team = payload.get("source_team", -1)
        shooter_peer_id = payload.get("shooter_peer_id", -1)
        updates = self.minions.damage_minion(minion_id, amount, source_team, shooter_peer_id)
        self._dispatch_updates(updates, directed_peer=None)

    # ------------------------------------------------------------------
    # Skill event handlers
    # ------------------------------------------------------------------

    def _handle_use_skill(self, sender_id: int, payload: dict) -> None:
        slot = payload.get("slot", 0)
        updates = self.skills.use_active(sender_id, slot)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_unlock_skill(self, sender_id: int, payload: dict) -> None:
        node_id = payload.get("node_id", "")
        updates = self.skills.unlock_node(sender_id, node_id)
        self._dispatch_updates(updates, directed_peer=None)

    def _handle_assign_active(self, sender_id: int, payload: dict) -> None:
        slot = payload.get("slot", 0)
        node_id = payload.get("node_id", "")
        updates = self.skills.assign_active_slot(sender_id, slot, node_id)
        self._dispatch_updates(updates, directed_peer=None)

    # ------------------------------------------------------------------
    # Progression event handlers
    # ------------------------------------------------------------------

    def _handle_spend_attribute(self, sender_id: int, payload: dict) -> None:
        attr = payload.get("attr", "")
        self.progression.spend_point(sender_id, attr)

    # ------------------------------------------------------------------
    # Game state event handlers
    # ------------------------------------------------------------------

    def _handle_lose_life(self, sender_id: int, payload: dict) -> None:
        team = payload.get("team", 0)
        updates = self.game_state.lose_life(team)
        self._dispatch_updates(updates, directed_peer=None)

    # ------------------------------------------------------------------
    # Wave event handlers
    # ------------------------------------------------------------------

    def _handle_boost_lane(self, sender_id: int, payload: dict) -> None:
        team = payload.get("team", 0)
        lane = payload.get("lane", payload.get("lane_i", 0))
        amount = int(payload.get("amount", 1))
        if lane == -1:
            self.waves.boost_all_lanes(team)
        else:
            self.waves.boost_lane(team, lane, amount)
        self.economy.add_passive_income(team, 1)
        self._broadcast(_serialise(self._make_pts_update()))

    def _handle_request_ram_minion(self, sender_id: int, payload: dict) -> None:
        team = int(payload.get("team", 0))
        tier = int(payload.get("tier", 0))
        lane_i = int(payload.get("lane_i", 0))
        t = max(0, min(tier, 2))
        minion_type = f"ram_t{t + 1}"
        lanes = [0, 1, 2] if lane_i == -1 else [max(0, min(lane_i, 2))]
        ram_costs = [20, 35, 55]
        total_cost = ram_costs[t] * len(lanes)
        if not self.economy.spend_points(team, total_cost):
            return
        self.economy.add_passive_income(team, 1)
        self._broadcast(_serialise(self._make_pts_update()))
        wave_number = self.waves.wave_number
        for li in lanes:
            spawn = SpawnWaveEvent(
                team=team,
                lane=li,
                minion_type=minion_type,
                count=1,
                wave_number=wave_number,
            )
            self._dispatch_updates([spawn], directed_peer=None)

    def _handle_bounty_state_notify(self, sender_id: int, payload: dict) -> None:
        """Godot reports a bounty state change — Python combat is authoritative, discard."""

    # ------------------------------------------------------------------
    # Ping handler
    # ------------------------------------------------------------------

    def _handle_ping(self, sender_id: int, payload: dict) -> None:
        """Respond to a ping with a pong directed at the sender only."""
        ts = payload.get("timestamp", time.time())
        update = make_update("pong", {"timestamp": ts})
        self._send_to(sender_id, update)

    # ------------------------------------------------------------------
    # Routing helpers
    # ------------------------------------------------------------------

    def _make_pts_update(self) -> TeamPointsUpdate:
        """Build a TeamPointsUpdate snapshot from current economy state."""
        return TeamPointsUpdate(
            blue=self.economy.get_points(0),
            red=self.economy.get_points(1),
            income_blue=self.economy.get_passive_income(0),
            income_red=self.economy.get_passive_income(1),
        )

    def _dispatch_updates(self, updates: list, directed_peer: int | None) -> None:
        """Send all updates.

        When *directed_peer* is None, broadcast to every client.
        When *directed_peer* is set, send only to that peer.

        LobbyStateUpdate is always sent individually to each client so that
        each receiver's own peer_id can be injected as ``your_peer_id``.
        """
        for update in updates:
            if isinstance(update, LobbyStateUpdate) and directed_peer is None:
                for pid, client in self._clients.items():
                    msg = _serialise(update)
                    msg["payload"]["your_peer_id"] = pid
                    client.send_update(msg)
                continue
            msg = _serialise(update)
            if directed_peer is None:
                self._broadcast(msg)
            else:
                self._send_to(directed_peer, msg)

    def _broadcast(self, update: dict) -> None:
        """Send a StateUpdate to every registered client."""
        for client in self._clients.values():
            client.send_update(update)

    def _send_to(self, peer_id: int, update: dict) -> None:
        """Send a StateUpdate to a single registered client."""
        client = self._clients.get(peer_id)
        if client is not None:
            client.send_update(update)

    # ------------------------------------------------------------------
    # Cross-system helpers
    # ------------------------------------------------------------------

    def _award_xp_and_broadcast(self, peer_id: int, amount: int) -> None:
        """Award XP, broadcast any level-up events that result."""
        level_ups = self.progression.award_xp(peer_id, amount)
        for evt in level_ups:
            self._broadcast(_serialise(evt))

    def _get_supporter_peer(self, team: int) -> int:
        """Return the Supporter peer id for *team*, or 0 if none."""
        for pid, info in self.lobby.players.items():
            if info.team == team and info.role == Lobby.ROLE_SUPPORTER:
                return pid
        return 0
