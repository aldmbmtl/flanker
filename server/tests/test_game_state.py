"""Tests for server/game_state.py — GameStateMachine, GamePhase, update objects."""

import pytest

from server.game_state import (
    GameOverUpdate,
    GamePhase,
    GameStateMachine,
    LivesUpdate,
)

# ── Helpers ───────────────────────────────────────────────────────────────────


def playing_machine(lives: int = 5) -> GameStateMachine:
    """Return a machine already in PLAYING phase."""
    m = GameStateMachine(lives_per_team=lives)
    m.transition(GamePhase.LOADING)
    m.transition(GamePhase.PLAYING)
    return m


# ── Initial state ─────────────────────────────────────────────────────────────


def test_initial_phase_is_lobby():
    assert GameStateMachine().phase == GamePhase.LOBBY


def test_initial_lives_default():
    m = GameStateMachine()
    assert m.get_lives(0) == 20
    assert m.get_lives(1) == 20


def test_initial_lives_custom():
    m = GameStateMachine(lives_per_team=3)
    assert m.get_lives(0) == 3
    assert m.get_lives(1) == 3


def test_get_lives_invalid_team_returns_zero():
    assert GameStateMachine().get_lives(-1) == 0
    assert GameStateMachine().get_lives(5) == 0


# ── Transitions ───────────────────────────────────────────────────────────────


def test_valid_transition_lobby_to_loading():
    m = GameStateMachine()
    m.transition(GamePhase.LOADING)
    assert m.phase == GamePhase.LOADING


def test_valid_transition_loading_to_playing():
    m = GameStateMachine()
    m.transition(GamePhase.LOADING)
    m.transition(GamePhase.PLAYING)
    assert m.phase == GamePhase.PLAYING


def test_valid_transition_playing_to_game_over():
    m = playing_machine(lives=1)
    m.lose_life(0)
    assert m.phase == GamePhase.GAME_OVER


def test_invalid_transition_raises():
    m = GameStateMachine()
    with pytest.raises(ValueError):
        m.transition(GamePhase.PLAYING)


def test_invalid_transition_lobby_to_game_over():
    m = GameStateMachine()
    with pytest.raises(ValueError):
        m.transition(GamePhase.GAME_OVER)


def test_no_transitions_from_game_over():
    m = playing_machine(lives=1)
    m.lose_life(0)
    with pytest.raises(ValueError):
        m.transition(GamePhase.LOBBY)


# ── lose_life ─────────────────────────────────────────────────────────────────


def test_lose_life_returns_lives_update():
    m = playing_machine(lives=3)
    result = m.lose_life(0)
    assert len(result) == 1
    assert isinstance(result[0], LivesUpdate)
    assert result[0].team == 0
    assert result[0].lives == 2


def test_lose_life_decrements_lives():
    m = playing_machine(lives=3)
    m.lose_life(1)
    assert m.get_lives(1) == 2


def test_lose_life_does_not_affect_other_team():
    m = playing_machine(lives=3)
    m.lose_life(0)
    assert m.get_lives(1) == 3


def test_lose_life_to_zero_returns_game_over():
    m = playing_machine(lives=1)
    result = m.lose_life(0)
    assert len(result) == 1
    assert isinstance(result[0], GameOverUpdate)
    assert result[0].winner == 1


def test_lose_life_red_team_to_zero_blue_wins():
    m = playing_machine(lives=1)
    result = m.lose_life(1)
    assert isinstance(result[0], GameOverUpdate)
    assert result[0].winner == 0


def test_game_over_fires_exactly_once():
    m = playing_machine(lives=1)
    r1 = m.lose_life(0)
    r2 = m.lose_life(0)  # already GAME_OVER — guard fires
    assert isinstance(r1[0], GameOverUpdate)
    assert r2 == []


def test_lose_life_outside_playing_returns_empty():
    m = GameStateMachine()  # LOBBY
    assert m.lose_life(0) == []


def test_lose_life_invalid_team_returns_empty():
    m = playing_machine()
    assert m.lose_life(-1) == []
    assert m.lose_life(2) == []


def test_lives_floor_at_zero():
    m = playing_machine(lives=1)
    m.lose_life(0)
    assert m.get_lives(0) == 0


# ── reset ─────────────────────────────────────────────────────────────────────


def test_reset_restores_lobby_phase():
    m = playing_machine(lives=1)
    m.lose_life(0)
    m.reset()
    assert m.phase == GamePhase.LOBBY


def test_reset_restores_lives():
    m = playing_machine(lives=5)
    m.lose_life(0)
    m.lose_life(0)
    m.reset()
    assert m.get_lives(0) == 5
    assert m.get_lives(1) == 5


def test_reset_with_new_lives_count():
    m = GameStateMachine(lives_per_team=10)
    m.reset(lives_per_team=3)
    assert m.get_lives(0) == 3
    assert m.get_lives(1) == 3
