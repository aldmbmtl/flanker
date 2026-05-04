"""
test_lobby.py — Full coverage of server/lobby.py.

Tests are grouped by method. Each group covers:
  - happy path
  - guard / rejection paths
  - edge cases matching GDScript behaviour
"""

from __future__ import annotations

import pytest

from server.lobby import (
    AllRolesConfirmedUpdate,
    DeathCountUpdate,
    GameStartUpdate,
    Lobby,
    LobbyStateUpdate,
    PlayerInfo,
    PlayerLeftUpdate,
    RoleAcceptedUpdate,
    RoleRejectedUpdate,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_lobby() -> Lobby:
    return Lobby()


def register(lobby: Lobby, peer_id: int, name: str = "p") -> None:
    lobby.register_player(peer_id, name)


# ---------------------------------------------------------------------------
# PlayerInfo.to_dict
# ---------------------------------------------------------------------------


def test_player_info_to_dict_defaults():
    p = PlayerInfo(name="Alice", team=0)
    d = p.to_dict()
    assert d["name"] == "Alice"
    assert d["team"] == 0
    assert d["role"] == -1
    assert d["ready"] is False
    assert d["avatar_char"] == ""


def test_player_info_to_dict_set_fields():
    p = PlayerInfo(name="Bob", team=1, role=0, ready=True, avatar_char="c")
    d = p.to_dict()
    assert d["role"] == 0
    assert d["ready"] is True
    assert d["avatar_char"] == "c"


# ---------------------------------------------------------------------------
# register_player
# ---------------------------------------------------------------------------


def test_register_first_player_assigned_blue():
    lobby = make_lobby()
    updates = lobby.register_player(1, "Alice")
    assert lobby.players[1].team == 0
    assert any(isinstance(u, LobbyStateUpdate) for u in updates)


def test_register_second_player_assigned_red():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.register_player(2, "Bob")
    assert lobby.players[2].team == 1


def test_register_third_player_balances_blue():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.register_player(3, "Carol")
    assert lobby.players[3].team == 0


def test_register_returns_lobby_state_update():
    lobby = make_lobby()
    updates = lobby.register_player(1, "Alice")
    assert len(updates) == 1
    assert isinstance(updates[0], LobbyStateUpdate)
    assert 1 in updates[0].players


def test_register_multiple_players_snapshot_contains_all():
    lobby = make_lobby()
    register(lobby, 1, "Alice")
    register(lobby, 2, "Bob")
    updates = lobby.register_player(3, "Carol")
    snap = updates[0]
    assert isinstance(snap, LobbyStateUpdate)
    assert set(snap.players.keys()) == {1, 2, 3}


def test_player_count_increments():
    lobby = make_lobby()
    assert lobby.player_count() == 0
    register(lobby, 1)
    assert lobby.player_count() == 1
    register(lobby, 2)
    assert lobby.player_count() == 2


# ---------------------------------------------------------------------------
# set_team
# ---------------------------------------------------------------------------


def test_set_team_changes_team():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.players[1].team = 0
    updates = lobby.set_team(1, 1)
    assert lobby.players[1].team == 1
    assert isinstance(updates[0], LobbyStateUpdate)


def test_set_team_unknown_peer_returns_empty():
    lobby = make_lobby()
    assert lobby.set_team(99, 0) == []


def test_set_team_after_game_started_ignored():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.game_started = True
    assert lobby.set_team(1, 1) == []
    assert lobby.players[1].team == 0  # unchanged


# ---------------------------------------------------------------------------
# set_role
# ---------------------------------------------------------------------------


def test_set_role_fighter_accepted():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.set_role(1, Lobby.ROLE_FIGHTER)
    accepted = [u for u in updates if isinstance(u, RoleAcceptedUpdate)]
    assert len(accepted) == 1
    assert accepted[0].peer_id == 1
    assert accepted[0].role == Lobby.ROLE_FIGHTER


def test_set_role_supporter_first_claim_accepted():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.set_role(1, Lobby.ROLE_SUPPORTER)
    accepted = [u for u in updates if isinstance(u, RoleAcceptedUpdate)]
    assert len(accepted) == 1
    assert lobby.supporter_claimed[0] is True


def test_set_role_supporter_duplicate_rejected():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    # both on blue (team 0)
    lobby.players[2].team = 0
    lobby.set_role(1, Lobby.ROLE_SUPPORTER)
    updates = lobby.set_role(2, Lobby.ROLE_SUPPORTER)
    rejected = [u for u in updates if isinstance(u, RoleRejectedUpdate)]
    assert len(rejected) == 1
    assert rejected[0].peer_id == 2


def test_set_role_supporter_different_teams_both_accepted():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.players[1].team = 0
    lobby.players[2].team = 1
    r1 = lobby.set_role(1, Lobby.ROLE_SUPPORTER)
    r2 = lobby.set_role(2, Lobby.ROLE_SUPPORTER)
    assert all(isinstance(u, RoleAcceptedUpdate) for u in r1 if isinstance(u, RoleAcceptedUpdate))
    assert all(isinstance(u, RoleAcceptedUpdate) for u in r2 if isinstance(u, RoleAcceptedUpdate))
    assert lobby.supporter_claimed == {0: True, 1: True}


def test_set_role_unknown_peer_returns_empty():
    lobby = make_lobby()
    assert lobby.set_role(99, Lobby.ROLE_FIGHTER) == []


def test_set_role_lobby_state_included_on_accept():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.set_role(1, Lobby.ROLE_FIGHTER)
    assert any(isinstance(u, LobbyStateUpdate) for u in updates)


def test_set_role_no_lobby_state_on_reject():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.players[2].team = 0
    lobby.set_role(1, Lobby.ROLE_SUPPORTER)
    updates = lobby.set_role(2, Lobby.ROLE_SUPPORTER)
    assert not any(isinstance(u, LobbyStateUpdate) for u in updates)


def test_set_role_all_roles_confirmed_fires_when_last():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby._roles_pending = 2
    lobby.set_role(1, Lobby.ROLE_FIGHTER)
    updates = lobby.set_role(2, Lobby.ROLE_FIGHTER)
    confirmed = [u for u in updates if isinstance(u, AllRolesConfirmedUpdate)]
    assert len(confirmed) == 1


def test_set_role_roles_pending_does_not_go_negative():
    lobby = make_lobby()
    register(lobby, 1)
    # _roles_pending starts at 0
    lobby.set_role(1, Lobby.ROLE_FIGHTER)
    assert lobby._roles_pending == 0


def test_set_role_records_role_on_player():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.set_role(1, Lobby.ROLE_FIGHTER)
    assert lobby.players[1].role == Lobby.ROLE_FIGHTER


# ---------------------------------------------------------------------------
# set_ready
# ---------------------------------------------------------------------------


def test_set_ready_marks_player_ready():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.set_ready(1, True)
    assert lobby.players[1].ready is True
    assert isinstance(updates[0], LobbyStateUpdate)


def test_set_ready_unready():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.players[1].ready = True
    lobby.set_ready(1, False)
    assert lobby.players[1].ready is False


def test_set_ready_unknown_peer_returns_empty():
    lobby = make_lobby()
    assert lobby.set_ready(99, True) == []


def test_set_ready_after_game_started_ignored():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.game_started = True
    assert lobby.set_ready(1, True) == []
    assert lobby.players[1].ready is False


# ---------------------------------------------------------------------------
# can_start_game
# ---------------------------------------------------------------------------


def test_can_start_game_false_when_empty():
    assert not make_lobby().can_start_game()


def test_can_start_game_false_when_not_all_ready():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.players[1].ready = True
    assert not lobby.can_start_game()


def test_can_start_game_true_when_all_ready():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.players[1].ready = True
    lobby.players[2].ready = True
    assert lobby.can_start_game()


def test_can_start_game_single_player_ready():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.players[1].ready = True
    assert lobby.can_start_game()


# ---------------------------------------------------------------------------
# start_game
# ---------------------------------------------------------------------------


def test_start_game_returns_game_start_update():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.start_game(map_seed=42, time_seed=7)
    assert len(updates) == 1
    assert isinstance(updates[0], GameStartUpdate)
    assert updates[0].map_seed == 42
    assert updates[0].time_seed == 7


def test_start_game_lane_points_default_empty():
    """Without lane_points argument, GameStartUpdate.lane_points is []."""
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.start_game(map_seed=1)
    assert updates[0].lane_points == []


def test_start_game_lane_points_propagated():
    """lane_points passed to start_game appear in the returned update."""
    lobby = make_lobby()
    register(lobby, 1)
    fake_lanes: list[list[tuple[float, float]]] = [[(0.0, 1.0), (2.0, 3.0)]]
    updates = lobby.start_game(map_seed=1, lane_points=fake_lanes)
    assert updates[0].lane_points == fake_lanes


def test_start_game_generates_seed_when_zero():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.start_game(map_seed=0)
    assert updates[0].map_seed > 0


def test_start_game_generates_seed_when_default():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.start_game()
    assert updates[0].map_seed > 0


def test_start_game_sets_game_started():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.start_game()
    assert lobby.game_started is True


def test_start_game_sets_roles_pending_to_player_count():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.start_game()
    assert lobby._roles_pending == 2


def test_start_game_resets_supporter_claimed():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.supporter_claimed = {0: True, 1: True}
    lobby.start_game()
    assert lobby.supporter_claimed == {0: False, 1: False}


def test_start_game_clears_death_counts():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.player_death_counts[1] = 5
    lobby.start_game()
    assert lobby.player_death_counts == {}


def test_start_game_seed_zero_from_randint_becomes_one(monkeypatch):
    """Defensive guard: if randint somehow returns 0, seed is set to 1."""
    import server.lobby as lobby_mod

    monkeypatch.setattr(lobby_mod.random, "randint", lambda a, b: 0)
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.start_game(map_seed=0)
    assert updates[0].map_seed == 1


# ---------------------------------------------------------------------------
# increment_death_count / get_respawn_time
# ---------------------------------------------------------------------------


def test_increment_death_count_first_death():
    lobby = make_lobby()
    updates = lobby.increment_death_count(1)
    assert isinstance(updates[0], DeathCountUpdate)
    assert updates[0].peer_id == 1
    assert updates[0].count == 1


def test_increment_death_count_accumulates():
    lobby = make_lobby()
    lobby.increment_death_count(1)
    updates = lobby.increment_death_count(1)
    assert updates[0].count == 2


def test_get_respawn_time_default():
    lobby = make_lobby()
    t = lobby.get_respawn_time(99)  # unknown peer → 0 deaths
    assert t == max(1.0, Lobby.RESPAWN_BASE)


def test_get_respawn_time_minimum_one_second():
    lobby = make_lobby()
    # With RESPAWN_BASE=10 and RESPAWN_INCREMENT=0 the value is always >= 10
    # but we verify the max(1.0, ...) floor still holds
    assert lobby.get_respawn_time(1) >= 1.0


def test_get_respawn_time_capped_at_respawn_cap():
    lobby = make_lobby()
    # Force a death count so high the formula would exceed the cap
    lobby.player_death_counts[1] = 10_000
    t = lobby.get_respawn_time(1)
    assert t <= Lobby.RESPAWN_CAP


def test_get_respawn_time_increments_with_deaths():
    # Only meaningful if RESPAWN_INCREMENT > 0; test that the formula is used
    original_increment = Lobby.RESPAWN_INCREMENT
    Lobby.RESPAWN_INCREMENT = 5.0
    try:
        lobby = make_lobby()
        lobby.player_death_counts[1] = 3
        t = lobby.get_respawn_time(1)
        expected = min(Lobby.RESPAWN_BASE + 3 * 5.0, Lobby.RESPAWN_CAP)
        assert t == pytest.approx(expected)
    finally:
        Lobby.RESPAWN_INCREMENT = original_increment


# ---------------------------------------------------------------------------
# peer_disconnected
# ---------------------------------------------------------------------------


def test_peer_disconnected_removes_player():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.peer_disconnected(1)
    assert 1 not in lobby.players


def test_peer_disconnected_returns_player_left_and_snapshot():
    lobby = make_lobby()
    register(lobby, 1)
    updates = lobby.peer_disconnected(1)
    assert any(isinstance(u, PlayerLeftUpdate) for u in updates)
    assert any(isinstance(u, LobbyStateUpdate) for u in updates)


def test_peer_disconnected_player_left_has_correct_id():
    lobby = make_lobby()
    register(lobby, 5)
    updates = lobby.peer_disconnected(5)
    left = next(u for u in updates if isinstance(u, PlayerLeftUpdate))
    assert left.peer_id == 5


def test_peer_disconnected_unknown_peer_still_returns_updates():
    lobby = make_lobby()
    updates = lobby.peer_disconnected(99)
    assert any(isinstance(u, PlayerLeftUpdate) for u in updates)
    assert any(isinstance(u, LobbyStateUpdate) for u in updates)


def test_peer_disconnected_in_game_with_unset_role_decrements_pending():
    """Known-bug parity: when game_started=True and role==-1, decrement fires."""
    lobby = make_lobby()
    register(lobby, 1)
    lobby.game_started = True
    lobby._roles_pending = 1
    lobby.players[1].role = -1
    updates = lobby.peer_disconnected(1)
    assert lobby._roles_pending == 0
    assert any(isinstance(u, AllRolesConfirmedUpdate) for u in updates)


def test_peer_disconnected_pregame_with_unset_role_does_not_decrement():
    """Known-bug parity: pre-game disconnect with role==-1 does NOT decrement."""
    lobby = make_lobby()
    register(lobby, 1)
    lobby.game_started = False
    lobby._roles_pending = 1
    lobby.players[1].role = -1
    lobby.peer_disconnected(1)
    assert lobby._roles_pending == 1  # unchanged — known bug


def test_peer_disconnected_in_game_with_set_role_does_not_decrement():
    """Peer with confirmed role disconnecting mid-game: no decrement."""
    lobby = make_lobby()
    register(lobby, 1)
    lobby.game_started = True
    lobby._roles_pending = 1
    lobby.players[1].role = Lobby.ROLE_FIGHTER
    lobby.peer_disconnected(1)
    assert lobby._roles_pending == 1  # unchanged


def test_peer_disconnected_roles_pending_clamps_to_zero():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.game_started = True
    lobby._roles_pending = 1
    lobby.players[1].role = -1
    lobby.players[2].role = -1
    # Disconnect both — second decrement should not go negative
    lobby.peer_disconnected(1)
    lobby.peer_disconnected(2)
    assert lobby._roles_pending == 0


# ---------------------------------------------------------------------------
# get_players_by_team / get_supporter_peer
# ---------------------------------------------------------------------------


def test_get_players_by_team_empty():
    lobby = make_lobby()
    assert lobby.get_players_by_team(0) == []


def test_get_players_by_team_returns_correct_peers():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    register(lobby, 3)
    lobby.players[1].team = 0
    lobby.players[2].team = 1
    lobby.players[3].team = 0
    assert set(lobby.get_players_by_team(0)) == {1, 3}
    assert lobby.get_players_by_team(1) == [2]


def test_get_supporter_peer_none_returns_minus_one():
    lobby = make_lobby()
    register(lobby, 1)
    assert lobby.get_supporter_peer(0) == -1


def test_get_supporter_peer_returns_correct_peer():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.players[1].team = 0
    lobby.players[1].role = Lobby.ROLE_SUPPORTER
    lobby.players[2].team = 0
    lobby.players[2].role = Lobby.ROLE_FIGHTER
    assert lobby.get_supporter_peer(0) == 1


def test_get_supporter_peer_respects_team():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.players[1].team = 0
    lobby.players[1].role = Lobby.ROLE_SUPPORTER
    lobby.players[2].team = 1
    lobby.players[2].role = Lobby.ROLE_SUPPORTER
    assert lobby.get_supporter_peer(0) == 1
    assert lobby.get_supporter_peer(1) == 2


# ---------------------------------------------------------------------------
# _lobby_snapshot integrity
# ---------------------------------------------------------------------------


def test_lobby_snapshot_contains_serialised_player_dicts():
    lobby = make_lobby()
    register(lobby, 1, "Alice")
    snap = lobby._lobby_snapshot()
    assert isinstance(snap.players[1], dict)
    assert snap.players[1]["name"] == "Alice"


# ---------------------------------------------------------------------------
# reset
# ---------------------------------------------------------------------------


def test_reset_clears_players():
    lobby = make_lobby()
    register(lobby, 1)
    register(lobby, 2)
    lobby.reset()
    assert lobby.players == {}


def test_reset_clears_game_started():
    lobby = make_lobby()
    lobby.game_started = True
    lobby.reset()
    assert lobby.game_started is False


def test_reset_clears_supporter_claimed():
    lobby = make_lobby()
    lobby.supporter_claimed = {0: True, 1: True}
    lobby.reset()
    assert lobby.supporter_claimed == {0: False, 1: False}


def test_reset_clears_death_counts():
    lobby = make_lobby()
    lobby.player_death_counts = {1: 5, 2: 3}
    lobby.reset()
    assert lobby.player_death_counts == {}


def test_reset_clears_roles_pending():
    lobby = make_lobby()
    lobby._roles_pending = 3
    lobby.reset()
    assert lobby._roles_pending == 0


def test_reset_clears_host_id():
    lobby = make_lobby()
    register(lobby, 7)
    assert lobby.host_id == 7
    lobby.reset()
    assert lobby.host_id == 0


def test_set_ready_works_after_reset():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.game_started = True
    assert lobby.set_ready(1, True) == []
    lobby.reset()
    register(lobby, 1)
    updates = lobby.set_ready(1, True)
    assert lobby.players[1].ready is True
    assert len(updates) == 1
    assert isinstance(updates[0], LobbyStateUpdate)


def test_set_team_works_after_reset():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.game_started = True
    assert lobby.set_team(1, 1) == []
    lobby.reset()
    register(lobby, 1)
    assert lobby.set_team(1, 1) != []


def test_can_start_game_false_after_reset():
    lobby = make_lobby()
    register(lobby, 1)
    lobby.players[1].ready = True
    assert lobby.can_start_game() is True
    lobby.reset()
    assert lobby.can_start_game() is False


def test_reset_host_reassigned_on_next_register():
    lobby = make_lobby()
    register(lobby, 5)
    lobby.reset()
    register(lobby, 9)
    assert lobby.host_id == 9
