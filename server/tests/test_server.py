"""
test_server.py — Tests for server/game_server.py

Phase 0: verifies client registration, ping/pong dispatch, and broadcast.
Phase 3: lobby-flow integration tests through GameServer with FakeClient objects.
All tests are pure unit tests — no network sockets, no Godot.
"""

import time

from server.build import (
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
    HealthUpdate,
    PlayerDiedUpdate,
    PlayerRespawnedUpdate,
    TeamPointsUpdate,
)
from server.game_server import (
    BroadcastPingUpdate,
    BroadcastReconRevealUpdate,
    BroadcastTransformUpdate,
    GameServer,
    SeedTransformUpdate,
    SkillEffectUpdate,
    SpawnMissileVisualsUpdate,
    SpawnVisualUpdate,
    SyncDestroyTreeUpdate,
    SyncLimitStateUpdate,
    SyncMinionStatesUpdate,
    _serialise,
)
from server.game_state import GameOverUpdate, LivesUpdate
from server.lobby import (
    AllRolesConfirmedUpdate,
    DeathCountUpdate,
    GameStartUpdate,
    Lobby,
    LobbyStateUpdate,
    PlayerLeftUpdate,
    RoleAcceptedUpdate,
    RoleRejectedUpdate,
)
from server.minion_state import MinionDamagedUpdate, MinionDiedUpdate, MinionWaveSpawnedUpdate
from server.progression import LevelUpEvent
from server.protocol import make_event
from server.skills_state import (
    ActiveSlotsChangedEvent,
    ActiveUsedEvent,
    CooldownTickEvent,
    SkillPtsChangedEvent,
    SkillUnlockedEvent,
)

# ---------------------------------------------------------------------------
# Test double: in-memory fake client
# ---------------------------------------------------------------------------


class FakeClient:
    def __init__(self) -> None:
        self._received: list[dict] = []

    def send_update(self, update: dict) -> None:
        self._received.append(update)

    def received(self) -> list[dict]:
        return list(self._received)

    def received_types(self) -> list[str]:
        return [m["type"] for m in self._received]

    def last(self) -> dict | None:
        return self._received[-1] if self._received else None

    def count(self) -> int:
        return len(self._received)

    def reset(self) -> None:
        self._received.clear()


# ---------------------------------------------------------------------------
# Client registry
# ---------------------------------------------------------------------------


class TestClientRegistry:
    def test_register_one_client(self):
        server = GameServer()
        client = FakeClient()
        server.register(1, client)
        assert server.client_count() == 1

    def test_register_multiple_clients(self):
        server = GameServer()
        server.register(1, FakeClient())
        server.register(2, FakeClient())
        server.register(3, FakeClient())
        assert server.client_count() == 3

    def test_unregister_removes_client(self):
        server = GameServer()
        server.register(1, FakeClient())
        server.unregister(1)
        assert server.client_count() == 0

    def test_unregister_unknown_peer_is_safe(self):
        server = GameServer()
        server.unregister(999)  # should not raise

    def test_register_overwrites_same_peer_id(self):
        server = GameServer()
        server.register(1, FakeClient())
        server.register(1, FakeClient())
        assert server.client_count() == 1


# ---------------------------------------------------------------------------
# Ping / pong
# ---------------------------------------------------------------------------


class TestPingPong:
    def test_ping_produces_pong(self):
        server = GameServer()
        client = FakeClient()
        server.register(1, client)

        server.handle(1, make_event("ping", 1, {"timestamp": 100.0}))

        assert client.count() == 1
        assert client.last()["type"] == "pong"

    def test_pong_carries_timestamp(self):
        server = GameServer()
        client = FakeClient()
        server.register(1, client)

        ts = 12345.678
        server.handle(1, make_event("ping", 1, {"timestamp": ts}))

        assert client.last()["payload"]["timestamp"] == ts

    def test_pong_echoes_missing_timestamp(self):
        """If sender omits timestamp, server fills in a current time."""
        server = GameServer()
        client = FakeClient()
        server.register(1, client)

        before = time.time()
        server.handle(1, make_event("ping", 1, {}))
        after = time.time()

        ts = client.last()["payload"]["timestamp"]
        assert before <= ts <= after

    def test_ping_only_replies_to_sender(self):
        """Pong must not be sent to other clients."""
        server = GameServer()
        sender = FakeClient()
        bystander = FakeClient()
        server.register(1, sender)
        server.register(2, bystander)

        server.handle(1, make_event("ping", 1, {"timestamp": 1.0}))

        assert sender.count() == 1
        assert bystander.count() == 0

    def test_ping_from_unregistered_peer_is_safe(self):
        """No registered client for sender_id — should not raise."""
        server = GameServer()
        server.handle(99, make_event("ping", 99, {"timestamp": 1.0}))

    def test_multiple_pings_each_get_pong(self):
        server = GameServer()
        client = FakeClient()
        server.register(1, client)

        for i in range(5):
            server.handle(1, make_event("ping", 1, {"timestamp": float(i)}))

        assert client.count() == 5
        assert all(m["type"] == "pong" for m in client.received())
        tss = [m["payload"]["timestamp"] for m in client.received()]
        assert tss == [0.0, 1.0, 2.0, 3.0, 4.0]


# ---------------------------------------------------------------------------
# Unknown events
# ---------------------------------------------------------------------------


class TestUnknownEvents:
    def test_unknown_event_does_not_raise(self):
        server = GameServer()
        client = FakeClient()
        server.register(1, client)
        server.handle(1, make_event("this_does_not_exist", 1, {}))

    def test_unknown_event_produces_no_update(self):
        server = GameServer()
        client = FakeClient()
        server.register(1, client)
        server.handle(1, make_event("noop", 1, {"data": 42}))
        assert client.count() == 0


# ---------------------------------------------------------------------------
# Broadcast
# ---------------------------------------------------------------------------


class TestBroadcast:
    def test_broadcast_reaches_all_clients(self):
        server = GameServer()
        clients = [FakeClient() for _ in range(4)]
        for i, c in enumerate(clients):
            server.register(i + 1, c)

        # Access internal _broadcast for direct test
        update = {"type": "test_broadcast", "payload": {"val": 1}}
        server._broadcast(update)

        for c in clients:
            assert c.count() == 1
            assert c.last()["type"] == "test_broadcast"

    def test_broadcast_to_no_clients_is_safe(self):
        server = GameServer()
        server._broadcast({"type": "test", "payload": {}})

    def test_broadcast_after_unregister(self):
        server = GameServer()
        c1 = FakeClient()
        c2 = FakeClient()
        server.register(1, c1)
        server.register(2, c2)
        server.unregister(1)
        c2.reset()  # clear lobby updates triggered by unregister

        server._broadcast({"type": "test", "payload": {}})

        assert c1.count() == 0  # unregistered, receives nothing
        assert c2.count() == 1


# ---------------------------------------------------------------------------
# _serialise helper
# ---------------------------------------------------------------------------


class TestSerialise:
    def test_serialise_lobby_state(self):
        w = _serialise(LobbyStateUpdate(players={1: {"name": "A"}}))
        assert w["type"] == "lobby_state"
        assert w["payload"]["players"][1]["name"] == "A"

    def test_serialise_role_accepted(self):
        w = _serialise(
            RoleAcceptedUpdate(peer_id=1, role=0, supporter_claimed={0: False, 1: False})
        )
        assert w["type"] == "role_accepted"
        assert w["payload"]["peer_id"] == 1

    def test_serialise_role_rejected(self):
        w = _serialise(RoleRejectedUpdate(peer_id=2, supporter_claimed={0: True, 1: False}))
        assert w["type"] == "role_rejected"
        assert w["payload"]["peer_id"] == 2

    def test_serialise_game_started(self):
        w = _serialise(GameStartUpdate(map_seed=42, time_seed=7, lane_points=[]))
        assert w["type"] == "game_started"
        assert w["payload"]["map_seed"] == 42
        assert w["payload"]["lane_points"] == []

    def test_serialise_game_started_with_lane_points(self):
        lanes = [[(0.0, 1.0), (2.0, 3.0)], [(4.0, 5.0)]]
        w = _serialise(GameStartUpdate(map_seed=1, time_seed=0, lane_points=lanes))
        assert w["payload"]["lane_points"] == lanes

    def test_serialise_player_left(self):
        w = _serialise(PlayerLeftUpdate(peer_id=3))
        assert w["type"] == "player_left"
        assert w["payload"]["peer_id"] == 3

    def test_serialise_death_count(self):
        w = _serialise(DeathCountUpdate(peer_id=1, count=2))
        assert w["type"] == "death_count"
        assert w["payload"]["count"] == 2

    def test_serialise_all_roles_confirmed(self):
        w = _serialise(AllRolesConfirmedUpdate())
        assert w["type"] == "all_roles_confirmed"

    def test_serialise_unknown_fallback(self):
        w = _serialise(object())
        assert w["type"] == "unknown"


# ---------------------------------------------------------------------------
# Phase 3 — Lobby event integration through GameServer
# ---------------------------------------------------------------------------


class TestLobbyEvents:
    # ---- register_player ---------------------------------------------------

    def test_register_player_broadcasts_lobby_state(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))

        assert "lobby_state" in c1.received_types()

    def test_register_player_uses_sender_id(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))

        snap = next(m for m in c1.received() if m["type"] == "lobby_state")
        assert 1 in snap["payload"]["players"]

    def test_register_player_default_name_when_missing(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("register_player", 1, {}))

        snap = next(m for m in c1.received() if m["type"] == "lobby_state")
        assert "Player_1" in snap["payload"]["players"][1]["name"]

    def test_register_player_broadcasts_to_all_clients(self):
        server = GameServer()
        c1, c2 = FakeClient(), FakeClient()
        server.register(1, c1)
        server.register(2, c2)

        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))

        assert "lobby_state" in c1.received_types()
        assert "lobby_state" in c2.received_types()

    # ---- set_team ----------------------------------------------------------

    def test_set_team_broadcasts_lobby_state(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        c1.reset()

        server.handle(1, make_event("set_team", 1, {"team": 1}))

        assert "lobby_state" in c1.received_types()

    def test_set_team_unknown_peer_produces_no_update(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("set_team", 1, {"team": 0}))

        assert c1.count() == 0  # not registered in lobby yet

    # ---- set_role ----------------------------------------------------------

    def test_set_role_accepted_broadcasts_to_all(self):
        server = GameServer()
        c1, c2 = FakeClient(), FakeClient()
        server.register(1, c1)
        server.register(2, c2)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        c1.reset()
        c2.reset()

        server.handle(1, make_event("set_role", 1, {"role": Lobby.ROLE_FIGHTER}))

        assert "role_accepted" in c1.received_types()
        assert "role_accepted" in c2.received_types()

    def test_set_role_rejected_only_sent_to_requester(self):
        server = GameServer()
        c1, c2 = FakeClient(), FakeClient()
        server.register(1, c1)
        server.register(2, c2)
        # Register both players on team 0
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        server.handle(2, make_event("register_player", 2, {"name": "Bob"}))
        server.lobby.players[2].team = 0  # force onto same team as peer 1
        c1.reset()
        c2.reset()

        # Peer 1 claims Supporter slot
        server.handle(1, make_event("set_role", 1, {"role": Lobby.ROLE_SUPPORTER}))
        c1.reset()
        c2.reset()

        # Peer 2 tries to claim same slot — should be rejected
        server.handle(2, make_event("set_role", 2, {"role": Lobby.ROLE_SUPPORTER}))

        assert "role_rejected" in c2.received_types()
        assert "role_rejected" not in c1.received_types()

    # ---- set_ready ---------------------------------------------------------

    def test_set_ready_broadcasts_lobby_state(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        c1.reset()

        server.handle(1, make_event("set_ready", 1, {"ready": True}))

        assert "lobby_state" in c1.received_types()

    def test_set_ready_unknown_peer_produces_no_update(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("set_ready", 1, {"ready": True}))

        assert c1.count() == 0

    # ---- start_game --------------------------------------------------------

    def test_start_game_broadcasts_game_started(self):
        server = GameServer()
        c1, c2 = FakeClient(), FakeClient()
        server.register(1, c1)
        server.register(2, c2)

        server.handle(1, make_event("start_game", 1, {"map_seed": 99, "time_seed": 0}))

        assert "game_started" in c1.received_types()
        assert "game_started" in c2.received_types()

    def test_start_game_seed_in_payload(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("start_game", 1, {"map_seed": 77, "time_seed": -1}))

        gs = next(m for m in c1.received() if m["type"] == "game_started")
        assert gs["payload"]["map_seed"] == 77

    def test_start_game_lane_points_in_payload(self):
        """game_started payload must contain lane_points with 3 lanes of 41 points each."""
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("start_game", 1, {"map_seed": 55, "time_seed": 0}))

        gs = next(m for m in c1.received() if m["type"] == "game_started")
        lanes = gs["payload"]["lane_points"]
        assert len(lanes) == 3
        assert all(len(lane) == 41 for lane in lanes)

    def test_start_game_wires_lane_points_into_build(self):
        """After start_game, Build must reject placements on lane centreline."""

        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.handle(1, make_event("start_game", 1, {"map_seed": 42, "time_seed": 0}))

        # Mid lane runs near x=0; (0, 0, 50) is well within LANE_SETBACK
        server.handle(
            1,
            make_event(
                "place_tower", 1, {"pos": [0.0, 0.0, 50.0], "tower_type": "cannon", "team": 0}
            ),
        )
        # The client should have received a placement_rejected with reason lane_setback
        rejected = [m for m in c1.received() if m["type"] == "placement_rejected"]
        assert any(m["payload"].get("reason") == "lane_setback" for m in rejected)

    # ---- unregister (disconnect) -------------------------------------------

    def test_unregister_broadcasts_player_left(self):
        server = GameServer()
        c1, c2 = FakeClient(), FakeClient()
        server.register(1, c1)
        server.register(2, c2)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        c1.reset()
        c2.reset()

        server.unregister(1)

        # c1 is unregistered so receives nothing; c2 gets the broadcast
        assert "player_left" in c2.received_types()
        assert c1.count() == 0

    def test_unregister_unknown_peer_safe_and_no_broadcast(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)

        server.unregister(99)  # unknown — should not raise, minimal output
        # c1 should only get a LobbyStateUpdate (empty snapshot)
        assert all(m["type"] in {"lobby_state", "player_left"} for m in c1.received())

    # ---- full lobby flow ---------------------------------------------------

    def test_full_lobby_flow(self):
        """
        Two clients register → pick roles → set ready → host starts game.
        Asserts that every client receives every broadcast in correct order.
        """
        server = GameServer()
        c1, c2 = FakeClient(), FakeClient()
        server.register(1, c1)
        server.register(2, c2)

        # Registration
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        server.handle(2, make_event("register_player", 2, {"name": "Bob"}))

        # Roles
        server.handle(1, make_event("set_role", 1, {"role": Lobby.ROLE_FIGHTER}))
        server.handle(2, make_event("set_role", 2, {"role": Lobby.ROLE_FIGHTER}))

        # Ready
        server.handle(1, make_event("set_ready", 1, {"ready": True}))
        server.handle(2, make_event("set_ready", 2, {"ready": True}))

        # Start
        server.handle(1, make_event("start_game", 1, {"map_seed": 1234, "time_seed": 0}))

        for client in (c1, c2):
            types = client.received_types()
            assert "lobby_state" in types
            assert "role_accepted" in types
            assert "game_started" in types


# ---------------------------------------------------------------------------
# _serialise — extended coverage for Phase 4 update types
# ---------------------------------------------------------------------------


class TestSerialiseExtended:
    # ── Combat ────────────────────────────────────────────────────────────

    def test_serialise_health_update(self):
        w = _serialise(HealthUpdate(peer_id=1, health=75.0))
        assert w["type"] == "player_health"
        assert w["payload"]["peer_id"] == 1
        assert w["payload"]["health"] == 75.0

    def test_serialise_player_died(self):
        w = _serialise(PlayerDiedUpdate(peer_id=2, respawn_time=5.0))
        assert w["type"] == "player_died"
        assert w["payload"]["respawn_time"] == 5.0

    def test_serialise_player_respawned(self):
        w = _serialise(PlayerRespawnedUpdate(peer_id=3, spawn_pos=(1.0, 0.0, 2.0), health=100.0))
        assert w["type"] == "player_respawned"
        assert w["payload"]["spawn_pos"] == [1.0, 0.0, 2.0]

    def test_serialise_team_points(self):
        w = _serialise(TeamPointsUpdate(blue=50, red=30))
        assert w["type"] == "team_points"
        assert w["payload"]["blue"] == 50

    def test_serialise_bounty_activated(self):
        w = _serialise(BountyActivatedUpdate(peer_id=1))
        assert w["type"] == "bounty_activated"

    def test_serialise_bounty_cleared(self):
        w = _serialise(BountyClearedUpdate(peer_id=1))
        assert w["type"] == "bounty_cleared"

    # ── Towers ────────────────────────────────────────────────────────────

    def test_serialise_tower_spawned(self):
        w = _serialise(
            TowerSpawnedUpdate(
                name="Cannon_1",
                tower_type="cannon",
                team=0,
                pos=(10.0, 0.0, 50.0),
                health=900.0,
                max_health=900.0,
            )
        )
        assert w["type"] == "tower_spawned"
        assert w["payload"]["name"] == "Cannon_1"
        assert w["payload"]["pos"] == [10.0, 0.0, 50.0]

    def test_serialise_tower_damaged(self):
        w = _serialise(TowerDamagedUpdate(name="Cannon_1", health=400.0))
        assert w["type"] == "tower_damaged"
        assert w["payload"]["health"] == 400.0

    def test_serialise_tower_despawned(self):
        w = _serialise(TowerDespawnedUpdate(name="Cannon_1", tower_type="cannon", team=0))
        assert w["type"] == "tower_despawned"
        assert w["payload"]["tower_type"] == "cannon"

    def test_serialise_placement_rejected(self):
        w = _serialise(PlacementRejectedUpdate(reason="spacing"))
        assert w["type"] == "placement_rejected"
        assert w["payload"]["reason"] == "spacing"

    # ── Minions ───────────────────────────────────────────────────────────

    def test_serialise_minion_wave_spawned(self):
        w = _serialise(
            MinionWaveSpawnedUpdate(team=0, lane=1, minion_type="standard", minion_ids=[1, 2])
        )
        assert w["type"] == "minion_wave_spawned"
        assert w["payload"]["minion_ids"] == [1, 2]

    def test_serialise_minion_damaged(self):
        w = _serialise(MinionDamagedUpdate(minion_id=1, health=30.0))
        assert w["type"] == "minion_damaged"
        assert w["payload"]["minion_id"] == 1

    def test_serialise_minion_died(self):
        w = _serialise(
            MinionDiedUpdate(minion_id=1, minion_type="standard", team=0, killer_peer_id=2)
        )
        assert w["type"] == "minion_died"
        assert w["payload"]["killer_peer_id"] == 2

    # ── Game state ────────────────────────────────────────────────────────

    def test_serialise_team_lives(self):
        w = _serialise(LivesUpdate(team=0, lives=19))
        assert w["type"] == "team_lives"
        assert w["payload"]["lives"] == 19

    def test_serialise_game_over(self):
        w = _serialise(GameOverUpdate(winner=1))
        assert w["type"] == "game_over"
        assert w["payload"]["winner"] == 1

    # ── Progression ───────────────────────────────────────────────────────

    def test_serialise_level_up(self):
        w = _serialise(LevelUpEvent(peer_id=1, new_level=2, pts_awarded=1))
        assert w["type"] == "level_up"
        assert w["payload"]["new_level"] == 2

    # ── Skills ────────────────────────────────────────────────────────────

    def test_serialise_skill_unlocked(self):
        w = _serialise(SkillUnlockedEvent(peer_id=1, node_id="f_dash"))
        assert w["type"] == "skill_unlocked"
        assert w["payload"]["node_id"] == "f_dash"

    def test_serialise_skill_pts_changed(self):
        w = _serialise(SkillPtsChangedEvent(peer_id=1, pts=3))
        assert w["type"] == "skill_pts_changed"
        assert w["payload"]["pts"] == 3

    def test_serialise_active_slots_changed(self):
        w = _serialise(ActiveSlotsChangedEvent(peer_id=1, slots=["f_dash", ""]))
        assert w["type"] == "active_slots_changed"
        assert w["payload"]["slots"] == ["f_dash", ""]

    def test_serialise_active_used(self):
        w = _serialise(ActiveUsedEvent(peer_id=1, node_id="f_dash"))
        assert w["type"] == "active_used"
        assert w["payload"]["node_id"] == "f_dash"

    def test_serialise_cooldown_tick(self):
        w = _serialise(CooldownTickEvent(peer_id=1, cooldowns={"f_dash": 4.5}))
        assert w["type"] == "cooldown_tick"
        assert w["payload"]["cooldowns"] == {"f_dash": 4.5}


# ---------------------------------------------------------------------------
# Phase 4 — Entity sync contracts: all event types reach all clients
# ---------------------------------------------------------------------------


def _make_server_with_two_clients() -> tuple[GameServer, FakeClient, FakeClient]:
    """Return a fresh server with two registered + lobby-registered clients."""
    server = GameServer()
    c1, c2 = FakeClient(), FakeClient()
    server.register(1, c1)
    server.register(2, c2)
    return server, c1, c2


def _setup_lobby(server: GameServer, *peer_ids: int) -> None:
    """Register peers in the lobby so combat/skills handlers have valid state."""
    for pid in peer_ids:
        server.handle(pid, make_event("register_player", pid, {"name": f"P{pid}"}))
    for c in (server._clients.get(pid) for pid in peer_ids):
        if c is not None:
            c.reset()  # type: ignore[union-attr]


class TestEntitySyncContracts:
    """
    For every Phase-4 entity event type:
      - Trigger the event through GameServer.handle()
      - Assert that BOTH c1 and c2 receive the expected update type.

    This structurally proves there is no host-only broadcast path.
    """

    # ── Towers ────────────────────────────────────────────────────────────

    def test_place_tower_spawned_reaches_both_clients(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)  # fund the placement
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {
                    "pos": [5.0, 0.0, 50.0],
                    "team": 0,
                    "tower_type": "cannon",
                    "placer_peer_id": 1,
                    "forced_name": "Cannon_test",
                },
            ),
        )
        assert "tower_spawned" in c1.received_types()
        assert "tower_spawned" in c2.received_types()

    def test_place_tower_broadcasts_team_points(self):
        """Successful placement must broadcast team_points to all clients."""
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {
                    "pos": [5.0, 0.0, 50.0],
                    "team": 0,
                    "tower_type": "cannon",
                    "placer_peer_id": 1,
                    "forced_name": "Cannon_tp",
                },
            ),
        )
        assert "team_points" in c1.received_types()
        assert "team_points" in c2.received_types()
        # Points should reflect the cost deduction (cannon costs 25; started at 75+100=175)
        tp = next(m for m in c1.received() if m["type"] == "team_points")
        assert tp["payload"]["blue"] == 150  # 175 - 25

    def test_place_tower_rejected_sends_team_points_to_requester(self):
        """Rejected placement must send team_points directed to the requester only."""
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy._points[0] = 0
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {"pos": [5.0, 0.0, 50.0], "team": 0, "tower_type": "cannon"},
            ),
        )
        # Requester (c1, peer 1) gets corrected; non-requester (c2, peer 2) does not.
        assert "team_points" in c1.received_types()
        assert "team_points" not in c2.received_types()
        tp = next(m for m in c1.received() if m["type"] == "team_points")
        assert tp["payload"]["blue"] == 0

    def test_place_tower_rejected_reaches_both_clients(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        # Drain all team 0 points so placement is rejected for insufficient funds
        server.economy._points[0] = 0
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {"pos": [5.0, 0.0, 50.0], "team": 0, "tower_type": "cannon"},
            ),
        )
        assert "placement_rejected" in c1.received_types()
        assert "placement_rejected" in c2.received_types()

    def test_place_tower_spacing_mult_allows_closer_placement(self):
        """spacing_mult < 1.0 reduces effective radius so a nearby placement succeeds."""
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 200)
        base_payload = {
            "pos": [5.0, 0.0, 50.0],
            "team": 0,
            "tower_type": "cannon",
            "forced_name": "Cannon_first",
        }
        server.handle(1, make_event("place_tower", 1, base_payload))
        c1.reset()
        c2.reset()
        # cannon spacing = 30 * 0.75 = 22.5; place 20 units away — rejected at mult=1.0
        nearby_payload = {
            "pos": [5.0, 0.0, 70.0],  # 20 units from first tower
            "team": 0,
            "tower_type": "cannon",
            "forced_name": "Cannon_nearby",
            "spacing_mult": 0.8,  # effective = 22.5 * 0.8 = 18.0 < 20 → allowed
        }
        server.handle(1, make_event("place_tower", 1, nearby_payload))
        assert "tower_spawned" in c1.received_types()

    def test_place_tower_spacing_mult_floor(self):
        """spacing_mult cannot push effective spacing below _SPACING_FLOOR (3.0)."""
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 200)
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {"pos": [5.0, 0.0, 50.0], "team": 0, "tower_type": "barrier", "forced_name": "B1"},
            ),
        )
        c1.reset()
        c2.reset()
        # barrier spacing = SPACING_PASSIVE = 3.0; place 2 units away with mult=0.0
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {
                    "pos": [5.0, 0.0, 52.0],  # 2 units away — below floor even at mult=0
                    "team": 0,
                    "tower_type": "barrier",
                    "forced_name": "B2",
                    "spacing_mult": 0.0,
                },
            ),
        )
        assert "placement_rejected" in c1.received_types()

        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {
                    "pos": [5.0, 0.0, 50.0],
                    "team": 0,
                    "tower_type": "cannon",
                    "forced_name": "Cannon_1",
                },
            ),
        )
        c1.reset()
        c2.reset()
        server.handle(
            2,
            make_event(
                "damage_tower",
                2,
                {"name": "Cannon_1", "amount": 100.0, "source_team": 1},
            ),
        )
        assert "tower_damaged" in c1.received_types()
        assert "tower_damaged" in c2.received_types()

    def test_remove_tower_despawned_reaches_both_clients(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        server.handle(
            1,
            make_event(
                "place_tower",
                1,
                {
                    "pos": [5.0, 0.0, 50.0],
                    "team": 0,
                    "tower_type": "cannon",
                    "forced_name": "Cannon_1",
                },
            ),
        )
        c1.reset()
        c2.reset()
        server.handle(
            2,
            make_event("remove_tower", 2, {"name": "Cannon_1", "source_team": 1}),
        )
        assert "tower_despawned" in c1.received_types()
        assert "tower_despawned" in c2.received_types()

    # ── Players ───────────────────────────────────────────────────────────

    def test_damage_player_health_update_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.combat.register_player(1, team=0)
        c1.reset()
        c2.reset()
        server.handle(
            2,
            make_event(
                "damage_player",
                2,
                {"peer_id": 1, "amount": 10.0, "source_team": 1, "killer_peer_id": 2},
            ),
        )
        assert "player_health" in c1.received_types()
        assert "player_health" in c2.received_types()

    def test_player_respawned_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.combat.register_player(1, team=0)
        # Kill the player via damage so they enter dead state
        server.combat.damage_player(1, 9999.0, source_team=1, killer_peer_id=2)
        c1.reset()
        c2.reset()
        server.handle(1, make_event("player_respawned", 1, {"peer_id": 1}))
        assert "player_respawned" in c1.received_types()
        assert "player_respawned" in c2.received_types()

    # ── Minions ───────────────────────────────────────────────────────────

    def test_spawn_minion_wave_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(
            1,
            make_event(
                "spawn_minion_wave",
                1,
                {"team": 0, "lane": 0, "minion_type": "standard", "count": 3},
            ),
        )
        assert "minion_wave_spawned" in c1.received_types()
        assert "minion_wave_spawned" in c2.received_types()

    def test_damage_minion_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(
            1,
            make_event(
                "spawn_minion_wave",
                1,
                {"team": 0, "lane": 0, "minion_type": "standard", "count": 1},
            ),
        )
        c1.reset()
        c2.reset()
        minion_id = list(server.minions._minions.keys())[0]
        server.handle(
            2,
            make_event(
                "damage_minion",
                2,
                {"minion_id": minion_id, "amount": 5.0, "source_team": 1, "shooter_peer_id": 2},
            ),
        )
        assert "minion_damaged" in c1.received_types()
        assert "minion_damaged" in c2.received_types()

    def test_damage_minion_kill_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(
            1,
            make_event(
                "spawn_minion_wave",
                1,
                {"team": 0, "lane": 0, "minion_type": "standard", "count": 1},
            ),
        )
        c1.reset()
        c2.reset()
        minion_id = list(server.minions._minions.keys())[0]
        server.handle(
            2,
            make_event(
                "damage_minion",
                2,
                {"minion_id": minion_id, "amount": 9999.0, "source_team": 1, "shooter_peer_id": 2},
            ),
        )
        assert "minion_died" in c1.received_types()
        assert "minion_died" in c2.received_types()

    # ── Skills ────────────────────────────────────────────────────────────

    def test_use_skill_active_used_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.skills.register_peer(1, "Fighter")
        c1.reset()
        c2.reset()
        # Fighter starts with f_dash in slot 0; use it
        server.handle(1, make_event("use_skill", 1, {"slot": 0}))
        assert "active_used" in c1.received_types()
        assert "active_used" in c2.received_types()

    def test_unlock_skill_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.skills.register_peer(1, "Fighter")
        # Give the peer enough skill points to unlock a tier-1 node
        server.skills._states[1].skill_pts = 5
        c1.reset()
        c2.reset()
        server.handle(1, make_event("unlock_skill", 1, {"node_id": "f_field_medic"}))
        assert "skill_unlocked" in c1.received_types()
        assert "skill_unlocked" in c2.received_types()

    def test_assign_active_slot_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.skills.register_peer(1, "Fighter")
        c1.reset()
        c2.reset()
        # Fighter has f_dash in slot 0 by default; assign it to slot 1
        server.handle(1, make_event("assign_active", 1, {"slot": 1, "node_id": "f_dash"}))
        assert "active_slots_changed" in c1.received_types()
        assert "active_slots_changed" in c2.received_types()

    def test_assign_active_slot_invalid_node_no_broadcast(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.skills.register_peer(1, "Fighter")
        c1.reset()
        c2.reset()
        # f_adrenaline is not unlocked — should be rejected
        server.handle(1, make_event("assign_active", 1, {"slot": 0, "node_id": "f_adrenaline"}))
        assert "active_slots_changed" not in c1.received_types()

    # ── Game state ────────────────────────────────────────────────────────

    def test_lose_life_lives_update_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        from server.game_state import GamePhase

        server.game_state._phase = GamePhase.PLAYING
        c1.reset()
        c2.reset()
        server.handle(1, make_event("lose_life", 1, {"team": 0}))
        assert "team_lives" in c1.received_types()
        assert "team_lives" in c2.received_types()

    def test_lose_life_game_over_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        from server.game_state import GamePhase

        server.game_state._phase = GamePhase.PLAYING
        server.game_state._lives = [1, 20]
        c1.reset()
        c2.reset()
        server.handle(1, make_event("lose_life", 1, {"team": 0}))
        assert "game_over" in c1.received_types()
        assert "game_over" in c2.received_types()

    # ── Spend attribute (no broadcast but must not raise) ──────────────────

    def test_spend_attribute_no_crash(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        # Give a pending point via progression
        server.progression.register_peer(1)
        server.progression._points[1] = 1
        # Should not raise even though nothing is broadcast
        server.handle(1, make_event("spend_attribute", 1, {"attr": "hp"}))


# ---------------------------------------------------------------------------
# Helper: _get_supporter_peer
# ---------------------------------------------------------------------------


class TestGetSupporterPeer:
    def test_returns_zero_when_no_supporter(self):
        server = GameServer()
        assert server._get_supporter_peer(0) == 0

    def test_returns_peer_id_when_supporter_exists(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        server.lobby.players[1].team = 0
        server.lobby.players[1].role = Lobby.ROLE_SUPPORTER
        assert server._get_supporter_peer(0) == 1

    def test_returns_zero_for_wrong_team(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        server.lobby.players[1].team = 0
        server.lobby.players[1].role = Lobby.ROLE_SUPPORTER
        assert server._get_supporter_peer(1) == 0


class TestGameTick:
    """Slice 2: GameServer.tick advances combat, skills, territory and broadcasts results."""

    def _setup_fighter_with_dash_on_cooldown(self) -> tuple:
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        server.handle(1, make_event("set_team", 1, {"team": 0}))
        server.handle(1, make_event("set_role", 1, {"role": Lobby.ROLE_FIGHTER}))
        # Use dash to put it on cooldown
        server.handle(1, make_event("use_skill", 1, {"slot": 0}))
        c1.reset()
        return server, c1

    def test_tick_broadcasts_cooldown_tick_event(self):
        server, c1 = self._setup_fighter_with_dash_on_cooldown()
        server.tick(0.5)
        assert "cooldown_tick" in c1.received_types()

    def test_tick_no_cooldown_tick_when_no_cooldowns(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.tick(1.0)
        assert "cooldown_tick" not in c1.received_types()

    def test_tick_broadcasts_respawn_when_timer_expires(self):
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        server.handle(1, make_event("set_team", 1, {"team": 0}))
        server.handle(1, make_event("set_role", 1, {"role": Lobby.ROLE_FIGHTER}))
        # Kill the player
        server.handle(
            1, make_event("damage_player", 1, {"peer_id": 1, "amount": 9999.0, "source_team": 1})
        )
        c1.reset()
        # Tick past the respawn time (default base = 5s, min 1s)
        server.tick(20.0)
        assert "player_respawned" in c1.received_types()

    def test_tick_does_not_raise_with_no_clients(self):
        server = GameServer()
        server.tick(1.0)  # must not raise


class TestTerritorySerialise:
    """Slice 2: BuildLimitUpdate and TowerDestroyedByPushUpdate are serialisable."""

    def test_build_limit_update_serialised(self):
        from server.game_server import _serialise
        from server.territory import BuildLimitUpdate as BLU

        msg = _serialise(BLU(team=0, new_level=1, new_z=50.0))
        assert msg["type"] == "build_limit"
        assert msg["payload"]["team"] == 0
        assert msg["payload"]["new_level"] == 1
        assert msg["payload"]["new_z"] == 50.0

    def test_tower_destroyed_by_push_serialised(self):
        from server.game_server import _serialise
        from server.territory import TowerDestroyedByPushUpdate as TDPU

        msg = _serialise(TDPU(team=1, tower_name="cannon_1", tower_z=-30.0))
        assert msg["type"] == "tower_destroyed_by_push"
        assert msg["payload"]["tower_name"] == "cannon_1"


class TestPeerLifecycleWiring:
    """Slice 1: combat/progression/skills subsystems are registered at role-confirm time
    and cleaned up at unregister time."""

    def _setup_player_with_role(self, role: int) -> tuple:
        server = GameServer()
        c1 = FakeClient()
        server.register(1, c1)
        server.handle(1, make_event("register_player", 1, {"name": "Alice"}))
        server.handle(1, make_event("set_team", 1, {"team": 0}))
        server.handle(1, make_event("set_role", 1, {"role": role}))
        return server, c1

    def test_set_role_registers_combat_player(self):
        server, _ = self._setup_player_with_role(Lobby.ROLE_FIGHTER)
        assert 1 in server.combat.player_healths

    def test_set_role_registers_progression_peer(self):
        server, _ = self._setup_player_with_role(Lobby.ROLE_FIGHTER)
        assert server.progression.get_level(1) == 1

    def test_set_role_fighter_grants_free_dash_broadcast(self):
        server, c1 = self._setup_player_with_role(Lobby.ROLE_FIGHTER)
        # Fighter role-confirm must broadcast a skill_unlocked for f_dash
        types = c1.received_types()
        assert "skill_unlocked" in types

    def test_set_role_supporter_no_free_dash(self):
        server, c1 = self._setup_player_with_role(Lobby.ROLE_SUPPORTER)
        unlocked = [m for m in c1.received() if m["type"] == "skill_unlocked"]
        assert all(m["payload"]["node_id"] != "f_dash" for m in unlocked)

    def test_set_role_registers_skills_peer(self):
        server, _ = self._setup_player_with_role(Lobby.ROLE_FIGHTER)
        assert server.skills.get_role(1) == "Fighter"

    def test_unregister_clears_combat(self):
        server, _ = self._setup_player_with_role(Lobby.ROLE_FIGHTER)
        assert 1 in server.combat.player_healths
        server.unregister(1)
        assert 1 not in server.combat.player_healths

    def test_unregister_clears_progression(self):
        server, _ = self._setup_player_with_role(Lobby.ROLE_FIGHTER)
        server.unregister(1)
        # clear_peer removes internal state; get_level should return default (1)
        # but internal xp dict should be empty
        assert 1 not in server.progression._xp

    def test_unregister_clears_skills(self):
        server, _ = self._setup_player_with_role(Lobby.ROLE_FIGHTER)
        server.unregister(1)
        assert server.skills.get_role(1) == ""


# ---------------------------------------------------------------------------
# Slice 7: fire_projectile / heal_player / SpawnVisualUpdate
# ---------------------------------------------------------------------------


class TestFireProjectileAndHealPlayer:
    """
    Verify that fire_projectile and heal_player events route correctly through
    GameServer and that both connected clients receive the expected update type.
    fire_projectile is excluded from the sender to avoid double-spawning on the
    shooting peer.
    """

    def test_fire_projectile_reaches_non_sender(self):
        """The relay should reach the non-sending client."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "fire_projectile",
                1,
                {
                    "visual_type": "bullet",
                    "params": {"pos": [1.0, 0.0, 2.0], "dir": [0.0, 0.0, -1.0]},
                },
            ),
        )
        assert "spawn_visual" in c2.received_types()

    def test_fire_projectile_excluded_from_sender(self):
        """The shooting peer must NOT receive the relay back to avoid double bullets."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "fire_projectile",
                1,
                {
                    "visual_type": "bullet",
                    "params": {"pos": [1.0, 0.0, 2.0], "dir": [0.0, 0.0, -1.0]},
                },
            ),
        )
        assert "spawn_visual" not in c1.received_types()

    def test_fire_projectile_relays_visual_type(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "fire_projectile",
                1,
                {"visual_type": "rocket", "params": {}},
            ),
        )
        msgs = [m for m in c2.received() if m["type"] == "spawn_visual"]
        assert len(msgs) == 1
        assert msgs[0]["payload"]["visual_type"] == "rocket"

    def test_fire_projectile_relays_params_unchanged(self):
        server, _, c2 = _make_server_with_two_clients()
        params = {"pos": [5.0, 1.0, -3.0], "dir": [1.0, 0.0, 0.0], "damage": 25.0}
        server.handle(
            1,
            make_event("fire_projectile", 1, {"visual_type": "bullet", "params": params}),
        )
        msgs = [m for m in c2.received() if m["type"] == "spawn_visual"]
        assert msgs[0]["payload"]["params"] == params

    def test_fire_projectile_empty_params_defaults(self):
        """Missing params key should not crash; defaults to empty dict."""
        server, _, c2 = _make_server_with_two_clients()
        server.handle(1, make_event("fire_projectile", 1, {"visual_type": "mg"}))
        msgs = [m for m in c2.received() if m["type"] == "spawn_visual"]
        assert msgs[0]["payload"]["params"] == {}

    def test_fire_projectile_logs_debug_sender_and_type(self, caplog):
        """_handle_fire_projectile must emit a DEBUG log with sender_id and visual_type."""
        import logging

        server, _, _ = _make_server_with_two_clients()
        with caplog.at_level(logging.DEBUG, logger="server.game_server"):
            server.handle(
                1,
                make_event(
                    "fire_projectile",
                    1,
                    {
                        "visual_type": "bullet",
                        "params": {
                            "pos": [1.0, 0.0, 2.0],
                            "dir": [0.0, 0.0, -1.0],
                            "shooter_team": 0,
                            "shooter_peer_id": 1,
                            "damage": 15.0,
                        },
                    },
                ),
            )
        records = [r for r in caplog.records if "fire_projectile" in r.message]
        assert records, "Expected at least one DEBUG log mentioning fire_projectile"
        assert "bullet" in records[0].message
        assert "1" in records[0].message  # sender peer id

    def test_fire_projectile_logs_relay_targets(self, caplog):
        """Debug log must include the list of relay target peer IDs."""
        import logging

        server, _, _ = _make_server_with_two_clients()
        with caplog.at_level(logging.DEBUG, logger="server.game_server"):
            server.handle(
                1,
                make_event("fire_projectile", 1, {"visual_type": "bullet", "params": {}}),
            )
        # Should mention peer 2 as the relay target (not peer 1 = sender)
        relay_logs = [r for r in caplog.records if "spawn_visual" in r.message]
        assert relay_logs, "Expected DEBUG log for each relay send"
        assert "2" in relay_logs[0].message

    def test_fire_projectile_logs_flat_pos_for_cannonball(self, caplog):
        """
        Ballistic projectiles (cannonball/mortar) send pos_x/y/z flat keys, not a
        'pos' array.  The debug log must fall back to the flat keys so the log line
        shows the actual launch position instead of None.
        """
        import logging

        server, _, _ = _make_server_with_two_clients()
        params = {
            "pos_x": 10.0,
            "pos_y": 2.0,
            "pos_z": -5.0,
            "target_x": 20.0,
            "target_y": 0.0,
            "target_z": -50.0,
            "damage": 50.0,
            "team": 0,
        }
        with caplog.at_level(logging.DEBUG, logger="server.game_server"):
            server.handle(
                1,
                make_event("fire_projectile", 1, {"visual_type": "cannonball", "params": params}),
            )
        fp_records = [r for r in caplog.records if "fire_projectile" in r.message]
        assert fp_records, "Expected fire_projectile DEBUG log"
        msg = fp_records[0].message
        # The log must not say "pos=None" — it must resolve the flat keys.
        assert "None" not in msg or "shooter_peer_id=None" in msg, (
            "Log must resolve pos_x/y/z flat keys for cannonball; got: " + msg
        )
        assert "10.0" in msg, "Log must include the pos_x value (10.0)"

    def test_fire_projectile_logs_team_fallback_for_cannonball(self, caplog):
        """
        Ballistic projectiles use 'team' key, not 'shooter_team'.  The debug log
        must fall back to params['team'] when params['shooter_team'] is absent.
        """
        import logging

        server, _, _ = _make_server_with_two_clients()
        params = {
            "pos_x": 5.0,
            "pos_y": 1.0,
            "pos_z": -3.0,
            "target_x": 10.0,
            "target_y": 0.0,
            "target_z": -30.0,
            "damage": 50.0,
            "team": 1,  # ballistic key, not shooter_team
        }
        with caplog.at_level(logging.DEBUG, logger="server.game_server"):
            server.handle(
                2,
                make_event("fire_projectile", 2, {"visual_type": "cannonball", "params": params}),
            )
        fp_records = [r for r in caplog.records if "fire_projectile" in r.message]
        assert fp_records, "Expected fire_projectile DEBUG log"
        msg = fp_records[0].message
        # team=1 must appear in the log via the fallback path
        assert "1" in msg, "Log must include the team value via fallback"

    def test_fire_projectile_pos_none_when_no_keys_present(self, caplog):
        """
        When params has neither 'pos' nor 'pos_x', log_pos must be None (not crash).
        """
        import logging

        server, _, _ = _make_server_with_two_clients()
        with caplog.at_level(logging.DEBUG, logger="server.game_server"):
            server.handle(
                1,
                make_event("fire_projectile", 1, {"visual_type": "mg", "params": {}}),
            )
        fp_records = [r for r in caplog.records if "fire_projectile" in r.message]
        assert fp_records, "Expected fire_projectile DEBUG log even with empty params"

    def test_heal_player_health_update_reaches_both(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        # Damage first so a heal has room to move the value.
        server.handle(
            1,
            make_event("damage_player", 1, {"peer_id": 1, "amount": 30.0, "source_team": 1}),
        )
        c1.reset()
        c2.reset()
        server.handle(1, make_event("heal_player", 1, {"peer_id": 1, "amount": 20.0}))
        for c in (c1, c2):
            assert "player_health" in c.received_types()

    def test_heal_player_health_increases(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(
            1,
            make_event("damage_player", 1, {"peer_id": 1, "amount": 40.0, "source_team": 1}),
        )
        hp_after_damage = server.combat.player_healths[1]
        server.handle(1, make_event("heal_player", 1, {"peer_id": 1, "amount": 25.0}))
        assert server.combat.player_healths[1] > hp_after_damage

    def test_heal_player_capped_at_max_hp(self):
        server, _, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(1, make_event("heal_player", 1, {"peer_id": 1, "amount": 9999.0}))
        from server.combat import Combat

        assert server.combat.player_healths[1] <= Combat.PLAYER_MAX_HP

    def test_spawn_visual_serialise(self):
        update = SpawnVisualUpdate(visual_type="cannonball", params={"x": 1})
        wire = _serialise(update)
        assert wire["type"] == "spawn_visual"
        assert wire["payload"]["visual_type"] == "cannonball"
        assert wire["payload"]["params"] == {"x": 1}

    def test_spawn_visual_serialise_empty_params(self):
        update = SpawnVisualUpdate(visual_type="mortar")
        wire = _serialise(update)
        assert wire["payload"]["params"] == {}


# ---------------------------------------------------------------------------
# Slice 7b: spawn_visual relay (host → non-host clients)
# ---------------------------------------------------------------------------


class TestSpawnVisualRelay:
    """
    Verify _handle_spawn_visual_relay correctly relays spawn_visual messages
    from the sender (host) to all other connected clients.
    """

    def test_relay_reaches_non_sender(self):
        """spawn_visual sent by peer 1 must arrive at peer 2."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "spawn_visual",
                1,
                {
                    "visual_type": "minion_spawn",
                    "params": {"team": 0, "minion_id": 1},
                },
            ),
        )
        assert "spawn_visual" in c2.received_types()

    def test_relay_excluded_from_sender(self):
        """The sending peer must NOT receive its own spawn_visual back."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "spawn_visual",
                1,
                {"visual_type": "minion_spawn", "params": {}},
            ),
        )
        assert "spawn_visual" not in c1.received_types()

    def test_relay_preserves_visual_type(self):
        """visual_type must be forwarded unchanged."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "spawn_visual",
                1,
                {"visual_type": "minion_spawn", "params": {"minion_id": 42}},
            ),
        )
        msgs = [m for m in c2.received() if m["type"] == "spawn_visual"]
        assert len(msgs) == 1
        assert msgs[0]["payload"]["visual_type"] == "minion_spawn"

    def test_relay_preserves_params(self):
        """params dict must be forwarded unchanged."""
        server, c1, c2 = _make_server_with_two_clients()
        params = {
            "team": 1,
            "pos_x": 10.0,
            "pos_y": 1.0,
            "pos_z": -5.0,
            "lane_i": 2,
            "minion_id": 99,
            "mtype": "cannon",
            "waypoints": [[10.0, 0.0, -5.0], [20.0, 0.0, -15.0]],
        }
        server.handle(
            1,
            make_event(
                "spawn_visual",
                1,
                {"visual_type": "minion_spawn", "params": params},
            ),
        )
        msgs = [m for m in c2.received() if m["type"] == "spawn_visual"]
        assert msgs[0]["payload"]["params"] == params

    def test_relay_missing_visual_type_defaults_to_empty_string(self):
        """Missing visual_type key must not crash; defaults to empty string."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(1, make_event("spawn_visual", 1, {"params": {"x": 1}}))
        msgs = [m for m in c2.received() if m["type"] == "spawn_visual"]
        assert len(msgs) == 1
        assert msgs[0]["payload"]["visual_type"] == ""

    def test_relay_missing_params_defaults_to_empty_dict(self):
        """Missing params key must not crash; defaults to empty dict."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(1, make_event("spawn_visual", 1, {"visual_type": "minion_spawn"}))
        msgs = [m for m in c2.received() if m["type"] == "spawn_visual"]
        assert msgs[0]["payload"]["params"] == {}

    def test_relay_three_clients_sender_excluded(self):
        """With 3 clients, only the 2 non-senders receive the relay."""
        server, c1, c2 = _make_server_with_two_clients()
        c3 = FakeClient()
        server.register(3, c3)
        server.handle(
            1,
            make_event(
                "spawn_visual",
                1,
                {"visual_type": "minion_spawn", "params": {}},
            ),
        )
        assert "spawn_visual" in c2.received_types()
        assert "spawn_visual" in c3.received_types()
        assert "spawn_visual" not in c1.received_types()


# ---------------------------------------------------------------------------
# TowerVisualUpdate + DropConsumedUpdate serialisation
# ---------------------------------------------------------------------------


class TestTowerVisualAndDropSerialisers:
    def test_tower_visual_update_serialise(self):
        u = TowerVisualUpdate(vtype="tower_hit", params={"name": "T1", "health": 300.0})
        wire = _serialise(u)
        assert wire["type"] == "tower_visual"
        assert wire["payload"]["type"] == "tower_hit"
        assert wire["payload"]["name"] == "T1"
        assert wire["payload"]["health"] == 300.0

    def test_tower_visual_update_empty_params(self):
        u = TowerVisualUpdate(vtype="slow_pulse")
        wire = _serialise(u)
        assert wire["type"] == "tower_visual"
        assert wire["payload"]["type"] == "slow_pulse"

    def test_drop_consumed_update_serialise(self):
        u = DropConsumedUpdate(name="Drop_healthpack_10_20", team=0)
        wire = _serialise(u)
        assert wire["type"] == "drop_despawned"
        assert wire["payload"]["name"] == "Drop_healthpack_10_20"
        assert wire["payload"]["team"] == 0

    def test_drop_consumed_red_team(self):
        u = DropConsumedUpdate(name="Drop_weapon_5_5", team=1)
        wire = _serialise(u)
        assert wire["payload"]["team"] == 1


# ---------------------------------------------------------------------------
# Drop registration and pickup handlers
# ---------------------------------------------------------------------------


class TestDropHandlers:
    def test_register_drop_stores_in_build(self):
        server, _, _ = _make_server_with_two_clients()
        server.handle(1, make_event("register_drop", 1, {"name": "Drop_hp_5_10", "team": 0}))
        assert "Drop_hp_5_10" in server.build._live_drops

    def test_drop_picked_up_broadcasts_drop_despawned(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(1, make_event("register_drop", 1, {"name": "Drop_hp_5_10", "team": 0}))
        c1.reset()
        c2.reset()
        server.handle(1, make_event("drop_picked_up", 1, {"name": "Drop_hp_5_10"}))
        for c in (c1, c2):
            assert "drop_despawned" in c.received_types()

    def test_drop_picked_up_payload_correct(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(1, make_event("register_drop", 1, {"name": "Drop_hp_5_10", "team": 1}))
        c1.reset()
        server.handle(1, make_event("drop_picked_up", 1, {"name": "Drop_hp_5_10"}))
        msg = next(m for m in c1.received() if m["type"] == "drop_despawned")
        assert msg["payload"]["name"] == "Drop_hp_5_10"
        assert msg["payload"]["team"] == 1

    def test_drop_picked_up_unknown_no_broadcast(self):
        server, c1, c2 = _make_server_with_two_clients()
        c1.reset()
        c2.reset()
        server.handle(1, make_event("drop_picked_up", 1, {"name": "NoSuchDrop"}))
        for c in (c1, c2):
            assert "drop_despawned" not in c.received_types()

    def test_drop_picked_up_twice_no_second_broadcast(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(1, make_event("register_drop", 1, {"name": "Drop_hp_5_10", "team": 0}))
        server.handle(1, make_event("drop_picked_up", 1, {"name": "Drop_hp_5_10"}))
        c1.reset()
        server.handle(1, make_event("drop_picked_up", 1, {"name": "Drop_hp_5_10"}))
        assert "drop_despawned" not in c1.received_types()

    def test_register_drop_reenables_after_consume(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(1, make_event("register_drop", 1, {"name": "Drop_hp_5_10", "team": 0}))
        server.handle(1, make_event("drop_picked_up", 1, {"name": "Drop_hp_5_10"}))
        # Respawn: register again
        server.handle(1, make_event("register_drop", 1, {"name": "Drop_hp_5_10", "team": 0}))
        c1.reset()
        server.handle(1, make_event("drop_picked_up", 1, {"name": "Drop_hp_5_10"}))
        assert "drop_despawned" in c1.received_types()


# ---------------------------------------------------------------------------
# Tower / minion visual relay handlers
# ---------------------------------------------------------------------------


class TestTowerVisualRelayHandlers:
    def test_tower_hit_visual_reaches_both_clients(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event("tower_hit_visual", 1, {"name": "Tower_cannon_10_20", "health": 400.0}),
        )
        for c in (c1, c2):
            assert "tower_visual" in c.received_types()

    def test_tower_hit_visual_vtype_is_tower_hit(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(1, make_event("tower_hit_visual", 1, {"name": "Tower_cannon_10_20"}))
        msg = next(m for m in c1.received() if m["type"] == "tower_visual")
        assert msg["payload"]["type"] == "tower_hit"

    def test_tower_visual_handler_relays_vtype(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event("tower_visual", 1, {"vtype": "slow_pulse", "radius": 5.0, "pos": [1, 2, 3]}),
        )
        for c in (c1, c2):
            assert "tower_visual" in c.received_types()
        msg = next(m for m in c1.received() if m["type"] == "tower_visual")
        assert msg["payload"]["type"] == "slow_pulse"

    def test_tower_visual_strips_vtype_from_params(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(1, make_event("tower_visual", 1, {"vtype": "mg_rot", "angle": 0.5}))
        msg = next(m for m in c1.received() if m["type"] == "tower_visual")
        assert "vtype" not in msg["payload"]
        assert msg["payload"]["angle"] == 0.5

    def test_minion_hit_visual_reaches_both_clients(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(1, make_event("minion_hit_visual", 1, {"minion_id": 7, "health": 30.0}))
        for c in (c1, c2):
            assert "tower_visual" in c.received_types()

    def test_minion_hit_visual_vtype_is_minion_hit(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(1, make_event("minion_hit_visual", 1, {"minion_id": 7}))
        msg = next(m for m in c1.received() if m["type"] == "tower_visual")
        assert msg["payload"]["type"] == "minion_hit"


# ---------------------------------------------------------------------------
# Relay handler serialisation tests
# ---------------------------------------------------------------------------


class TestRelaySerialise:
    def test_broadcast_transform_update(self):
        u = BroadcastTransformUpdate(peer_id=5, pos=[1.0, 2.0, 3.0], rot=[0.1, 0.2, 0.3], team=1)
        d = _serialise(u)
        assert d["type"] == "broadcast_transform"
        assert d["payload"]["peer_id"] == 5
        assert d["payload"]["pos"] == [1.0, 2.0, 3.0]
        assert d["payload"]["rot"] == [0.1, 0.2, 0.3]
        assert d["payload"]["team"] == 1

    def test_seed_transform_update(self):
        u = SeedTransformUpdate(peer_id=3, pos=[0.0, 0.0, 0.0], rot=[0.0, 0.0, 0.0], team=0)
        d = _serialise(u)
        assert d["type"] == "seed_transform"
        assert d["payload"]["peer_id"] == 3

    def test_sync_minion_states_update(self):
        u = SyncMinionStatesUpdate(
            ids=[1, 2], positions=[[0, 0, 0], [1, 1, 1]], rotations=[[0], [1]], healths=[60.0, 30.0]
        )
        d = _serialise(u)
        assert d["type"] == "sync_minion_states"
        assert d["payload"]["ids"] == [1, 2]
        assert d["payload"]["healths"] == [60.0, 30.0]

    def test_spawn_missile_visuals_update(self):
        u = SpawnMissileVisualsUpdate(
            fire_pos=[0, 1, 0], target_pos=[10, 0, 10], team=1, launcher_type="launcher_missile"
        )
        d = _serialise(u)
        assert d["type"] == "spawn_missile_visuals"
        assert d["payload"]["launcher_type"] == "launcher_missile"
        assert d["payload"]["team"] == 1

    def test_sync_destroy_tree_update(self):
        u = SyncDestroyTreeUpdate(pos=[5.0, 0.0, 7.0])
        d = _serialise(u)
        assert d["type"] == "sync_destroy_tree"
        assert d["payload"]["pos"] == [5.0, 0.0, 7.0]

    def test_broadcast_recon_reveal_update(self):
        u = BroadcastReconRevealUpdate(target_pos=[1, 2, 3], radius=15.0, duration=5.0, team=0)
        d = _serialise(u)
        assert d["type"] == "broadcast_recon_reveal"
        assert d["payload"]["radius"] == 15.0
        assert d["payload"]["duration"] == 5.0

    def test_broadcast_ping_update(self):
        u = BroadcastPingUpdate(world_pos=[10.0, 0.0, 20.0], team=1, color=[1.0, 0.0, 0.0, 1.0])
        d = _serialise(u)
        assert d["type"] == "broadcast_ping"
        assert d["payload"]["team"] == 1
        assert d["payload"]["color"] == [1.0, 0.0, 0.0, 1.0]

    def test_skill_effect_update(self):
        u = SkillEffectUpdate(effect="dash", target_peer_id=7, params={"dist": 5.0})
        d = _serialise(u)
        assert d["type"] == "skill_effect"
        assert d["payload"]["effect"] == "dash"
        assert d["payload"]["target_peer_id"] == 7
        assert d["payload"]["params"]["dist"] == 5.0

    def test_sync_limit_state_update(self):
        u = SyncLimitStateUpdate(team=0, level=2, p_timer=3.5, r_timer=1.2)
        d = _serialise(u)
        assert d["type"] == "sync_limit_state"
        assert d["payload"]["level"] == 2
        assert d["payload"]["p_timer"] == 3.5
        assert d["payload"]["r_timer"] == 1.2

    def test_sync_lane_boosts_update(self):
        from server.game_server import SyncLaneBoostsUpdate

        u = SyncLaneBoostsUpdate(boosts_team0=[1, 0, 2], boosts_team1=[0, 3, 0])
        d = _serialise(u)
        assert d["type"] == "sync_lane_boosts"
        assert d["payload"]["boosts_team0"] == [1, 0, 2]
        assert d["payload"]["boosts_team1"] == [0, 3, 0]


# ---------------------------------------------------------------------------
# Relay handler dispatch tests
# ---------------------------------------------------------------------------


class TestTransformRelay:
    def test_transform_relayed_to_other_client(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1, make_event("report_transform", 1, {"pos": [1, 2, 3], "rot": [0, 0, 0], "team": 0})
        )
        assert "broadcast_transform" in c2.received_types()

    def test_transform_not_sent_back_to_sender(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1, make_event("report_transform", 1, {"pos": [1, 2, 3], "rot": [0, 0, 0], "team": 0})
        )
        assert "broadcast_transform" not in c1.received_types()

    def test_transform_peer_id_is_sender(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1, make_event("report_transform", 1, {"pos": [4, 5, 6], "rot": [0, 0, 0], "team": 1})
        )
        msg = next(m for m in c2.received() if m["type"] == "broadcast_transform")
        assert msg["payload"]["peer_id"] == 1

    def test_initial_transform_relayed_to_other_client(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "report_initial_transform", 1, {"pos": [0, 1, 0], "rot": [0, 0, 0], "team": 0}
            ),
        )
        assert "seed_transform" in c2.received_types()

    def test_initial_transform_not_sent_back_to_sender(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "report_initial_transform", 1, {"pos": [0, 1, 0], "rot": [0, 0, 0], "team": 0}
            ),
        )
        assert "seed_transform" not in c1.received_types()


class TestAvatarSync:
    def test_avatar_updates_player_char(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(1, make_event("report_avatar", 1, {"char": "c"}))
        assert server.lobby.players[1].avatar_char == "c"

    def test_avatar_broadcasts_lobby_state(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(1, make_event("report_avatar", 1, {"char": "b"}))
        assert "lobby_state" in c1.received_types()
        assert "lobby_state" in c2.received_types()

    def test_avatar_unknown_peer_no_crash(self):
        server = GameServer()
        # No clients registered — sender 99 unknown — should not raise
        server.handle(99, make_event("report_avatar", 99, {"char": "a"}))

    def test_avatar_empty_char_ignored(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.lobby.players[1].avatar_char = "x"
        server.handle(1, make_event("report_avatar", 1, {"char": ""}))
        # Empty char must not overwrite the existing value
        assert server.lobby.players[1].avatar_char == "x"


class TestMinionStateRelay:
    def test_minion_states_relayed_to_other_client(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "sync_minion_states",
                1,
                {
                    "ids": [1, 2],
                    "positions": [[0, 0, 0], [1, 1, 1]],
                    "rotations": [[0], [1]],
                    "healths": [60.0, 30.0],
                },
            ),
        )
        assert "sync_minion_states" in c2.received_types()

    def test_minion_states_not_sent_to_sender(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "sync_minion_states",
                1,
                {
                    "ids": [1],
                    "positions": [[0, 0, 0]],
                    "rotations": [[0]],
                    "healths": [60.0],
                },
            ),
        )
        assert "sync_minion_states" not in c1.received_types()

    def test_minion_states_payload_intact(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "sync_minion_states",
                1,
                {
                    "ids": [7],
                    "positions": [[3, 0, 4]],
                    "rotations": [[0.5]],
                    "healths": [45.0],
                },
            ),
        )
        msg = next(m for m in c2.received() if m["type"] == "sync_minion_states")
        assert msg["payload"]["ids"] == [7]
        assert msg["payload"]["healths"] == [45.0]


class TestMissileRelay:
    def test_missile_broadcast_to_all_clients(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "request_fire_missile",
                1,
                {
                    "fire_pos": [0, 1, 0],
                    "target_pos": [10, 0, 10],
                    "team": 0,
                    "launcher_type": "launcher_missile",
                },
            ),
        )
        assert "spawn_missile_visuals" in c1.received_types()
        assert "spawn_missile_visuals" in c2.received_types()

    def test_missile_payload_intact(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "request_fire_missile",
                1,
                {
                    "fire_pos": [1, 2, 3],
                    "target_pos": [4, 5, 6],
                    "team": 1,
                    "launcher_type": "launcher_missile",
                },
            ),
        )
        msg = next(m for m in c1.received() if m["type"] == "spawn_missile_visuals")
        assert msg["payload"]["target_pos"] == [4, 5, 6]
        assert msg["payload"]["team"] == 1


class TestTreeDestroyRelay:
    def test_tree_destroy_broadcast_to_all(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(1, make_event("destroy_tree", 1, {"pos": [5.0, 0.0, 7.0]}))
        assert "sync_destroy_tree" in c1.received_types()
        assert "sync_destroy_tree" in c2.received_types()

    def test_tree_destroy_payload(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(1, make_event("destroy_tree", 1, {"pos": [9.0, 0.0, 3.0]}))
        msg = next(m for m in c1.received() if m["type"] == "sync_destroy_tree")
        assert msg["payload"]["pos"] == [9.0, 0.0, 3.0]


class TestReconPingRelay:
    def test_recon_reveal_broadcast(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "recon_reveal",
                1,
                {
                    "target_pos": [1, 2, 3],
                    "radius": 20.0,
                    "duration": 3.0,
                    "team": 0,
                },
            ),
        )
        assert "broadcast_recon_reveal" in c1.received_types()
        assert "broadcast_recon_reveal" in c2.received_types()

    def test_recon_reveal_payload(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "recon_reveal",
                1,
                {
                    "target_pos": [5, 0, 5],
                    "radius": 15.0,
                    "duration": 6.0,
                    "team": 1,
                },
            ),
        )
        msg = next(m for m in c1.received() if m["type"] == "broadcast_recon_reveal")
        assert msg["payload"]["radius"] == 15.0
        assert msg["payload"]["team"] == 1

    def test_ping_broadcast(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "request_ping",
                1,
                {
                    "world_pos": [10.0, 0.0, 20.0],
                    "team": 1,
                    "color": [1.0, 0.0, 0.0, 1.0],
                },
            ),
        )
        assert "broadcast_ping" in c1.received_types()
        assert "broadcast_ping" in c2.received_types()

    def test_ping_payload(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "request_ping",
                1,
                {
                    "world_pos": [3.0, 0.0, 4.0],
                    "team": 0,
                    "color": [0.62, 0.0, 1.0, 1.0],
                },
            ),
        )
        msg = next(m for m in c1.received() if m["type"] == "broadcast_ping")
        assert msg["payload"]["world_pos"] == [3.0, 0.0, 4.0]


class TestSkillEffectRelay:
    def test_skill_effect_sent_only_to_target(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "apply_skill_effect",
                1,
                {
                    "effect": "dash",
                    "target_peer_id": 2,
                    "params": {"dist": 5.0},
                },
            ),
        )
        assert "skill_effect" in c2.received_types()
        assert "skill_effect" not in c1.received_types()

    def test_skill_effect_payload(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "apply_skill_effect",
                1,
                {
                    "effect": "rapid_fire",
                    "target_peer_id": 2,
                    "params": {"duration": 3.0},
                },
            ),
        )
        msg = next(m for m in c2.received() if m["type"] == "skill_effect")
        assert msg["payload"]["effect"] == "rapid_fire"
        assert msg["payload"]["params"]["duration"] == 3.0

    def test_skill_effect_defaults_target_to_sender(self):
        server, c1, c2 = _make_server_with_two_clients()
        # No target_peer_id → defaults to sender (1)
        server.handle(1, make_event("apply_skill_effect", 1, {"effect": "iron_skin", "params": {}}))
        assert "skill_effect" in c1.received_types()

    def test_skill_effect_unknown_target_no_crash(self):
        server = GameServer()
        # No clients registered — should not raise
        server.handle(
            1,
            make_event(
                "apply_skill_effect",
                1,
                {
                    "effect": "rally_cry",
                    "target_peer_id": 99,
                    "params": {},
                },
            ),
        )


class TestSyncLimitStateRelay:
    def test_limit_state_broadcast_to_all(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "sync_limit_state",
                1,
                {
                    "team": 0,
                    "level": 2,
                    "p_timer": 3.5,
                    "r_timer": 1.2,
                },
            ),
        )
        assert "sync_limit_state" in c1.received_types()
        assert "sync_limit_state" in c2.received_types()

    def test_limit_state_payload(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "sync_limit_state",
                1,
                {
                    "team": 1,
                    "level": 3,
                    "p_timer": 5.0,
                    "r_timer": 2.0,
                },
            ),
        )
        msg = next(m for m in c1.received() if m["type"] == "sync_limit_state")
        assert msg["payload"]["team"] == 1
        assert msg["payload"]["level"] == 3
        assert msg["payload"]["p_timer"] == 5.0


class TestLaneBoostsRelay:
    def test_lane_boosts_broadcast_to_all(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "report_lane_boosts",
                1,
                {
                    "boosts_team0": [1, 0, 2],
                    "boosts_team1": [0, 3, 0],
                },
            ),
        )
        assert "sync_lane_boosts" in c1.received_types()
        assert "sync_lane_boosts" in c2.received_types()

    def test_lane_boosts_payload(self):
        server, c1, _ = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "report_lane_boosts",
                1,
                {
                    "boosts_team0": [2, 1, 0],
                    "boosts_team1": [0, 0, 3],
                },
            ),
        )
        msg = next(m for m in c1.received() if m["type"] == "sync_lane_boosts")
        assert msg["payload"]["boosts_team0"] == [2, 1, 0]
        assert msg["payload"]["boosts_team1"] == [0, 0, 3]


class TestRenamedDispatchKeys:
    """Verify that the renamed event keys (request_lane_boost, request_recon_reveal,
    set_role_ingame) are accepted and produce the same outcomes as the old names."""

    def test_request_lane_boost_accepted(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        # Old key "boost_lane" used lane/amount; new key "request_lane_boost"
        # calls _handle_boost_lane which reads lane_i and passes to waves.boost_lane.
        server.handle(1, make_event("request_lane_boost", 1, {"team": 0, "lane_i": 1, "amount": 2}))
        # No crash and waves reflect boost
        assert server.waves._lane_boosts[0][1] == 2

    def test_request_lane_boost_all_lanes_via_minus_one(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        server.handle(
            1, make_event("request_lane_boost", 1, {"team": 0, "lane_i": -1, "amount": 1})
        )
        assert server.waves._lane_boosts[0][0] == 1
        assert server.waves._lane_boosts[0][1] == 1
        assert server.waves._lane_boosts[0][2] == 1

    def test_request_recon_reveal_accepted(self):
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "request_recon_reveal",
                1,
                {"target_pos": [1, 2, 3], "radius": 20.0, "duration": 3.0, "team": 0},
            ),
        )
        assert "broadcast_recon_reveal" in c1.received_types()
        assert "broadcast_recon_reveal" in c2.received_types()

    def test_set_role_ingame_accepted(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1)
        c1.reset()
        server.handle(1, make_event("set_role_ingame", 1, {"role": 0}))
        types = c1.received_types()
        assert "role_accepted" in types or "lobby_state" in types

    def test_old_recon_reveal_key_still_works(self):
        """Old key 'recon_reveal' still accepted (both keys mapped)."""
        server, c1, c2 = _make_server_with_two_clients()
        server.handle(
            1,
            make_event(
                "recon_reveal",
                1,
                {"target_pos": [0, 0, 0], "radius": 5.0, "duration": 1.0, "team": 1},
            ),
        )
        assert "broadcast_recon_reveal" in c1.received_types()


class TestRequestRamMinion:
    """_handle_request_ram_minion: spend points, broadcast points update,
    then emit SpawnWaveEvent per affected lane."""

    def test_ram_single_lane_spends_points(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        before = server.economy.get_points(0)
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": 1}))
        assert server.economy.get_points(0) == before - 20  # tier-0 cost = 20

    def test_ram_single_lane_broadcasts_team_points(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": 0}))
        assert "team_points" in c1.received_types()
        assert "team_points" in c2.received_types()

    def test_ram_single_lane_broadcasts_spawn_wave(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 1, "lane_i": 2}))
        assert "spawn_wave" in c1.received_types()
        msg = next(m for m in c1.received() if m["type"] == "spawn_wave")
        assert msg["payload"]["minion_type"] == "ram_t2"
        assert msg["payload"]["lane"] == 2

    def test_ram_all_lanes_sends_three_spawn_waves(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 200)
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": -1}))
        wave_msgs = [m for m in c1.received() if m["type"] == "spawn_wave"]
        assert len(wave_msgs) == 3
        lanes = {m["payload"]["lane"] for m in wave_msgs}
        assert lanes == {0, 1, 2}

    def test_ram_insufficient_funds_no_spawn(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy._points[0] = 0
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 2, "lane_i": 0}))
        assert "spawn_wave" not in c1.received_types()
        assert "team_points" not in c1.received_types()

    def test_ram_tier_2_cost_is_55_per_lane(self):
        server, _, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 200)
        before = server.economy.get_points(0)
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 2, "lane_i": 0}))
        assert server.economy.get_points(0) == before - 55


class TestBountyStateNotify:
    """_handle_bounty_state_notify: Godot-sent notification; Python discards it silently."""

    def test_bounty_state_no_crash(self):
        server, c1, c2 = _make_server_with_two_clients()
        # Should not raise
        server.handle(1, make_event("bounty_state", 1, {"peer_id": 1, "is_bounty": True}))
        server.handle(1, make_event("bounty_state", 1, {"peer_id": 1, "is_bounty": False}))

    def test_bounty_state_no_broadcast(self):
        server, c1, c2 = _make_server_with_two_clients()
        c1.reset()
        c2.reset()
        server.handle(1, make_event("bounty_state", 1, {"peer_id": 1, "is_bounty": True}))
        assert c1.received_types() == []
        assert c2.received_types() == []


# ---------------------------------------------------------------------------
# Passive income wiring
# ---------------------------------------------------------------------------


class TestPassiveIncomeWiring:
    """Verify that RAM, boost, and wave-tick handlers correctly wire passive income."""

    # ── _make_pts_update helper ──────────────────────────────────────────────

    def test_make_pts_update_includes_income_fields(self):
        server = GameServer()
        server.economy.sync(50, 60)
        server.economy.add_passive_income(0, 3)
        server.economy.add_passive_income(1, 7)
        u = server._make_pts_update()
        assert u.blue == 50
        assert u.red == 60
        assert u.income_blue == 3
        assert u.income_red == 7

    def test_make_pts_update_zero_income_by_default(self):
        server = GameServer()
        u = server._make_pts_update()
        assert u.income_blue == 0
        assert u.income_red == 0

    # ── TeamPointsUpdate serialisation ──────────────────────────────────────

    def test_team_points_update_serialises_income_fields(self):
        u = TeamPointsUpdate(blue=40, red=55, income_blue=2, income_red=4)
        wire = _serialise(u)
        assert wire["payload"]["income_blue"] == 2
        assert wire["payload"]["income_red"] == 4

    def test_team_points_update_income_defaults_to_zero(self):
        u = TeamPointsUpdate(blue=10, red=20)
        wire = _serialise(u)
        assert wire["payload"].get("income_blue", 0) == 0
        assert wire["payload"].get("income_red", 0) == 0

    # ── RAM minion adds passive income ───────────────────────────────────────

    def test_ram_single_lane_increments_passive_income(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        assert server.economy.get_passive_income(0) == 0
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": 1}))
        assert server.economy.get_passive_income(0) == 1

    def test_ram_all_lanes_increments_passive_income_once(self):
        """Three lanes = one RAM action = +1 income, not +3."""
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 200)
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": -1}))
        assert server.economy.get_passive_income(0) == 1

    def test_ram_insufficient_funds_does_not_increment_income(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy._points[0] = 0
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": 0}))
        assert server.economy.get_passive_income(0) == 0

    def test_ram_team_points_broadcast_includes_income_rate(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        c1.reset()
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": 0}))
        pts_msg = next(m for m in c1.received() if m["type"] == "team_points")
        assert pts_msg["payload"]["income_blue"] == 1
        assert pts_msg["payload"]["income_red"] == 0

    def test_ram_only_increments_sending_team(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_points(0, 100)
        server.handle(1, make_event("request_ram_minion", 1, {"team": 0, "tier": 0, "lane_i": 0}))
        assert server.economy.get_passive_income(1) == 0

    # ── Lane boost adds passive income ───────────────────────────────────────

    def test_boost_lane_increments_passive_income(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(1, make_event("request_lane_boost", 1, {"team": 0, "lane_i": 1, "amount": 1}))
        assert server.economy.get_passive_income(0) == 1

    def test_boost_all_lanes_increments_passive_income_once(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(
            1, make_event("request_lane_boost", 1, {"team": 1, "lane_i": -1, "amount": 1})
        )
        assert server.economy.get_passive_income(1) == 1

    def test_boost_broadcasts_team_points_with_income(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        c1.reset()
        server.handle(1, make_event("request_lane_boost", 1, {"team": 0, "lane_i": 0, "amount": 1}))
        assert "team_points" in c1.received_types()
        pts_msg = next(m for m in c1.received() if m["type"] == "team_points")
        assert pts_msg["payload"]["income_blue"] == 1

    def test_boost_only_increments_sending_team(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.handle(1, make_event("request_lane_boost", 1, {"team": 0, "lane_i": 0, "amount": 1}))
        assert server.economy.get_passive_income(1) == 0

    # ── Wave tick pays out passive income ────────────────────────────────────

    def test_tick_wave_pays_out_passive_income(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_passive_income(0, 5)
        server.economy.add_passive_income(1, 3)
        before_blue = server.economy.get_points(0)
        before_red = server.economy.get_points(1)
        server.tick(20.0)  # 20s triggers WaveAnnouncedEvent
        assert server.economy.get_points(0) == before_blue + 5
        assert server.economy.get_points(1) == before_red + 3

    def test_tick_wave_resets_passive_income_after_payout(self):
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_passive_income(0, 4)
        server.tick(20.0)
        assert server.economy.get_passive_income(0) == 0

    def test_tick_wave_broadcasts_team_points_with_zero_income_after_payout(self):
        server, c1, c2 = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_passive_income(0, 2)
        c1.reset()
        server.tick(20.0)
        pts_msgs = [m for m in c1.received() if m["type"] == "team_points"]
        assert len(pts_msgs) >= 1
        last_pts = pts_msgs[-1]
        # After payout, income resets to 0
        assert last_pts["payload"]["income_blue"] == 0
        assert last_pts["payload"]["income_red"] == 0

    def test_tick_no_wave_does_not_pay_out_income(self):
        """A short tick that doesn't trigger a wave must not payout."""
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        server.economy.add_passive_income(0, 5)
        before = server.economy.get_points(0)
        server.tick(0.1)  # far below 20s wave threshold
        assert server.economy.get_points(0) == before
        assert server.economy.get_passive_income(0) == 5

    def test_tick_wave_zero_income_no_extra_team_points_broadcast(self):
        """When income is 0, wave tick still broadcasts team_points (unconditional)."""
        server, c1, _ = _make_server_with_two_clients()
        _setup_lobby(server, 1, 2)
        c1.reset()
        server.tick(20.0)
        assert "team_points" in c1.received_types()


# ---------------------------------------------------------------------------
# _reset_all_subsystems: last client disconnect triggers full reset
# ---------------------------------------------------------------------------


class TestResetAllSubsystems:
    """When the last client disconnects, unregister() calls _reset_all_subsystems()
    so the next group of players gets a clean server without restarting the process."""

    def _setup_player_with_role(self, server: GameServer, peer_id: int) -> FakeClient:
        c = FakeClient()
        server.register(peer_id, c)
        server.handle(peer_id, make_event("register_player", peer_id, {"name": f"P{peer_id}"}))
        server.handle(peer_id, make_event("set_team", peer_id, {"team": 0}))
        server.handle(peer_id, make_event("set_role", peer_id, {"role": Lobby.ROLE_FIGHTER}))
        return c

    def test_last_client_disconnect_resets_lobby_game_started(self):
        server = GameServer()
        self._setup_player_with_role(server, 1)
        server.lobby.game_started = True
        server.unregister(1)
        assert server.lobby.game_started is False

    def test_last_client_disconnect_clears_lobby_players(self):
        server = GameServer()
        self._setup_player_with_role(server, 1)
        server.unregister(1)
        assert server.lobby.players == {}

    def test_last_client_disconnect_resets_economy(self):
        from server.economy import TeamEconomy

        server = GameServer()
        self._setup_player_with_role(server, 1)
        server.economy.add_points(0, 100)
        server.unregister(1)
        # reset() restores starting points, not zero
        assert server.economy.get_points(0) == TeamEconomy.STARTING_POINTS

    def test_last_client_disconnect_clears_combat(self):
        server = GameServer()
        self._setup_player_with_role(server, 1)
        assert 1 in server.combat.player_healths
        server.unregister(1)
        assert server.combat.player_healths == {}

    def test_last_client_disconnect_clears_progression(self):
        server = GameServer()
        self._setup_player_with_role(server, 1)
        assert 1 in server.progression._xp
        server.unregister(1)
        assert server.progression._xp == {}

    def test_last_client_disconnect_clears_skills(self):
        server = GameServer()
        self._setup_player_with_role(server, 1)
        assert server.skills.get_role(1) == "Fighter"
        server.unregister(1)
        assert server.skills.get_role(1) == ""

    def test_not_last_client_does_not_reset(self):
        """With two clients, removing one must NOT reset subsystems."""
        from server.economy import TeamEconomy

        server = GameServer()
        self._setup_player_with_role(server, 1)
        c2 = FakeClient()
        server.register(2, c2)
        server.handle(2, make_event("register_player", 2, {"name": "P2"}))
        server.economy.add_points(0, 50)
        server.unregister(1)
        # Points should be starting (75) + 50 — reset did NOT fire
        assert server.economy.get_points(0) == TeamEconomy.STARTING_POINTS + 50

    def test_second_game_after_reset_works(self):
        """Full cycle: connect, play, disconnect, reconnect, play again."""
        server = GameServer()
        self._setup_player_with_role(server, 1)
        server.lobby.game_started = True
        server.unregister(1)
        # Second player connects — lobby must be clean
        c2 = FakeClient()
        server.register(2, c2)
        server.handle(2, make_event("register_player", 2, {"name": "Fresh"}))
        assert server.lobby.game_started is False
        assert 2 in server.lobby.players
        updates = server.lobby.set_ready(2, True)
        assert isinstance(updates[0], LobbyStateUpdate)
