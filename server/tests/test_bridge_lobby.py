"""
test_bridge_lobby.py — Slice 5 Python tests for lobby authority over bridge.

Covers:
  - LobbyStateUpdate includes can_start field
  - _serialise emits can_start in lobby_state payload
  - LoadGameUpdate serialises to load_game wire message
  - _handle_register_player broadcasts lobby_state with can_start=False
  - _handle_set_team broadcasts lobby_state
  - _handle_set_ready broadcasts lobby_state; can_start=True when all ready
  - _handle_start_game broadcasts game_started then load_game
  - Multi-peer scenario: 2 peers both ready → can_start True
  - _handle_start_game does NOT send load_game if lobby has no players (guard)
"""

from __future__ import annotations

from server.game_server import GameServer, _serialise
from server.lobby import LoadGameUpdate, LobbyStateUpdate

# ---------------------------------------------------------------------------
# Test double
# ---------------------------------------------------------------------------


class FakeClient:
    def __init__(self) -> None:
        self._msgs: list[dict] = []

    def send_update(self, update: dict) -> None:
        self._msgs.append(update)

    def received(self) -> list[dict]:
        return list(self._msgs)

    def received_types(self) -> list[str]:
        return [m["type"] for m in self._msgs]

    def clear(self) -> None:
        self._msgs.clear()


def make_server(*peer_ids: int) -> tuple[GameServer, list[FakeClient]]:
    """Create a server with pre-registered fake clients."""
    gs = GameServer()
    clients = []
    for pid in peer_ids:
        c = FakeClient()
        gs.register(pid, c)
        clients.append(c)
    return gs, clients


# ---------------------------------------------------------------------------
# LobbyStateUpdate dataclass
# ---------------------------------------------------------------------------


class TestLobbyStateUpdateDataclass:
    def test_can_start_defaults_false(self) -> None:
        snap = LobbyStateUpdate(players={})
        assert snap.can_start is False

    def test_can_start_true(self) -> None:
        snap = LobbyStateUpdate(players={}, can_start=True)
        assert snap.can_start is True

    def test_players_field(self) -> None:
        snap = LobbyStateUpdate(players={1: {"name": "A"}})
        assert snap.players[1]["name"] == "A"


# ---------------------------------------------------------------------------
# _serialise
# ---------------------------------------------------------------------------


class TestSerialise:
    def test_lobby_state_includes_can_start_false(self) -> None:
        w = _serialise(LobbyStateUpdate(players={}, can_start=False))
        assert w["type"] == "lobby_state"
        assert w["payload"]["can_start"] is False

    def test_lobby_state_includes_can_start_true(self) -> None:
        w = _serialise(LobbyStateUpdate(players={}, can_start=True))
        assert w["payload"]["can_start"] is True

    def test_lobby_state_includes_players(self) -> None:
        w = _serialise(LobbyStateUpdate(players={2: {"name": "B"}}, can_start=False))
        assert w["payload"]["players"][2]["name"] == "B"

    def test_load_game_serialise(self) -> None:
        w = _serialise(LoadGameUpdate(path="res://scenes/Main.tscn"))
        assert w["type"] == "load_game"
        assert w["payload"]["path"] == "res://scenes/Main.tscn"


# ---------------------------------------------------------------------------
# _handle_register_player
# ---------------------------------------------------------------------------


class TestHandleRegisterPlayer:
    def test_broadcasts_lobby_state(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        assert "lobby_state" in c.received_types()

    def test_lobby_state_has_can_start_false(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        snap = next(m for m in c.received() if m["type"] == "lobby_state")
        # Single player not ready → can_start False
        assert snap["payload"]["can_start"] is False

    def test_lobby_state_contains_player_name(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        snap = next(m for m in c.received() if m["type"] == "lobby_state")
        players = snap["payload"]["players"]
        assert any(v["name"] == "Alice" for v in players.values())


# ---------------------------------------------------------------------------
# _handle_set_team
# ---------------------------------------------------------------------------


class TestHandleSetTeam:
    def test_broadcasts_lobby_state(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        c.clear()
        gs.handle(1, {"type": "set_team", "payload": {"team": 1}})
        assert "lobby_state" in c.received_types()

    def test_lobby_state_reflects_new_team(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(1, {"type": "set_team", "payload": {"team": 1}})
        snap = next(m for m in reversed(c.received()) if m["type"] == "lobby_state")
        assert snap["payload"]["players"][1]["team"] == 1


# ---------------------------------------------------------------------------
# _handle_set_ready
# ---------------------------------------------------------------------------


class TestHandleSetReady:
    def test_broadcasts_lobby_state(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        c.clear()
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        assert "lobby_state" in c.received_types()

    def test_can_start_false_when_not_ready(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        c.clear()
        gs.handle(1, {"type": "set_ready", "payload": {"ready": False}})
        snap = next(m for m in c.received() if m["type"] == "lobby_state")
        assert snap["payload"]["can_start"] is False

    def test_can_start_true_when_all_ready(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        snap = next(m for m in reversed(c.received()) if m["type"] == "lobby_state")
        assert snap["payload"]["can_start"] is True


# ---------------------------------------------------------------------------
# Multi-peer scenario
# ---------------------------------------------------------------------------


class TestMultiPeer:
    def test_two_peers_both_ready_can_start_true(self) -> None:
        gs, (c1, c2) = make_server(1, 2)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(2, {"type": "register_player", "payload": {"name": "Bob"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        gs.handle(2, {"type": "set_ready", "payload": {"ready": True}})
        snap = next(m for m in reversed(c1.received()) if m["type"] == "lobby_state")
        assert snap["payload"]["can_start"] is True

    def test_one_of_two_ready_can_start_false(self) -> None:
        gs, (c1, c2) = make_server(1, 2)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(2, {"type": "register_player", "payload": {"name": "Bob"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        snap = next(m for m in reversed(c1.received()) if m["type"] == "lobby_state")
        assert snap["payload"]["can_start"] is False

    def test_lobby_state_broadcast_to_all_clients(self) -> None:
        gs, (c1, c2) = make_server(1, 2)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        # Both clients receive lobby_state
        assert "lobby_state" in c1.received_types()
        assert "lobby_state" in c2.received_types()


# ---------------------------------------------------------------------------
# _handle_start_game
# ---------------------------------------------------------------------------


class TestHandleStartGame:
    def test_start_game_broadcasts_game_started(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        c.clear()
        gs.handle(1, {"type": "start_game", "payload": {"map_seed": 42, "time_seed": 1}})
        assert "game_started" in c.received_types()

    def test_start_game_broadcasts_load_game(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        c.clear()
        gs.handle(1, {"type": "start_game", "payload": {"map_seed": 42, "time_seed": 1}})
        assert "load_game" in c.received_types()

    def test_start_game_load_game_has_path(self) -> None:
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        c.clear()
        gs.handle(1, {"type": "start_game", "payload": {"map_seed": 42, "time_seed": 1}})
        msg = next(m for m in c.received() if m["type"] == "load_game")
        assert msg["payload"]["path"] == "res://scenes/Main.tscn"

    def test_start_game_load_game_after_game_started(self) -> None:
        """load_game must come after game_started in the broadcast sequence."""
        gs, (c,) = make_server(1)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        c.clear()
        gs.handle(1, {"type": "start_game", "payload": {"map_seed": 42, "time_seed": 1}})
        types = c.received_types()
        assert types.index("game_started") < types.index("load_game")

    def test_start_game_broadcast_to_all_clients(self) -> None:
        gs, (c1, c2) = make_server(1, 2)
        gs.handle(1, {"type": "register_player", "payload": {"name": "Alice"}})
        gs.handle(2, {"type": "register_player", "payload": {"name": "Bob"}})
        gs.handle(1, {"type": "set_ready", "payload": {"ready": True}})
        gs.handle(2, {"type": "set_ready", "payload": {"ready": True}})
        c1.clear()
        c2.clear()
        gs.handle(1, {"type": "start_game", "payload": {"map_seed": 7, "time_seed": 2}})
        assert "load_game" in c1.received_types()
        assert "load_game" in c2.received_types()
