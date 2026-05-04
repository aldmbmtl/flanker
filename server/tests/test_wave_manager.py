"""
test_wave_manager.py — 100% coverage for server/wave_manager.py.
"""

from __future__ import annotations

import pytest

from server.wave_manager import (
    MAX_WAVE_SIZE,
    RAM_SPAWN_CHANCE,
    WAVE_INTERVAL,
    SpawnWaveEvent,
    WaveAnnouncedEvent,
    WaveInfoUpdate,
    WaveManager,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_wm(rng_val: float = 0.5, rng_int_seq: list[int] | None = None) -> WaveManager:
    """Return a WaveManager with deterministic RNG."""
    int_seq = list(rng_int_seq) if rng_int_seq else []

    def _rng_int(n: int) -> int:
        return int_seq.pop(0) if int_seq else 0

    return WaveManager(rng_fn=lambda: rng_val, rng_int_fn=_rng_int)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------


class TestConstants:
    def test_wave_interval(self):
        assert WAVE_INTERVAL == 20.0

    def test_max_wave_size(self):
        assert MAX_WAVE_SIZE == 6

    def test_ram_spawn_chance(self):
        assert RAM_SPAWN_CHANCE == 0.25


# ---------------------------------------------------------------------------
# Initial state
# ---------------------------------------------------------------------------


class TestInitialState:
    def test_wave_number_starts_zero(self):
        wm = WaveManager()
        assert wm.wave_number == 0

    def test_timer_starts_zero(self):
        wm = WaveManager()
        assert wm._timer == 0.0

    def test_boosts_start_zeroed(self):
        wm = WaveManager()
        assert wm._lane_boosts == [[0, 0, 0], [0, 0, 0]]

    def test_time_until_next_wave_full(self):
        wm = WaveManager()
        assert wm.get_time_until_next_wave() == pytest.approx(WAVE_INTERVAL)

    def test_tick_before_interval_returns_wave_info(self):
        """tick() before wave fires returns a WaveInfoUpdate (countdown changed)."""
        wm = WaveManager()
        result = wm.tick(5.0)
        assert len(result) == 1
        assert isinstance(result[0], WaveInfoUpdate)
        assert result[0].wave_number == 0
        assert result[0].next_in_seconds == pytest.approx(15.0)

    def test_timer_accumulates(self):
        wm = WaveManager()
        wm.tick(7.0)
        wm.tick(3.0)
        assert wm._timer == pytest.approx(10.0)


# ---------------------------------------------------------------------------
# Wave firing
# ---------------------------------------------------------------------------


class TestWaveFiring:
    def test_wave_fires_at_interval(self):
        wm = _make_wm(rng_val=0.9)  # no ram
        events = wm.tick(WAVE_INTERVAL)
        assert wm.wave_number == 1
        assert any(isinstance(e, WaveAnnouncedEvent) for e in events)

    def test_wave_announced_event_has_correct_number(self):
        wm = _make_wm(rng_val=0.9)
        events = wm.tick(WAVE_INTERVAL)
        announced = [e for e in events if isinstance(e, WaveAnnouncedEvent)]
        assert len(announced) == 1
        assert announced[0].wave_number == 1

    def test_timer_resets_after_wave(self):
        wm = _make_wm(rng_val=0.9)
        wm.tick(WAVE_INTERVAL)
        # Timer should have wrapped: remainder is 0
        assert wm._timer == pytest.approx(0.0)

    def test_timer_remainder_carries_over(self):
        wm = _make_wm(rng_val=0.9)
        wm.tick(WAVE_INTERVAL + 3.0)
        assert wm._timer == pytest.approx(3.0)

    def test_time_until_next_wave_decreases(self):
        wm = WaveManager()
        wm.tick(5.0)
        assert wm.get_time_until_next_wave() == pytest.approx(15.0)

    def test_time_until_next_wave_never_negative(self):
        wm = _make_wm(rng_val=0.9)
        wm.tick(WAVE_INTERVAL + 5.0)
        assert wm.get_time_until_next_wave() >= 0.0

    def test_wave_one_spawns_correct_lanes_teams(self):
        wm = _make_wm(rng_val=0.9)  # no ram
        events = wm.tick(WAVE_INTERVAL)
        spawn = [e for e in events if isinstance(e, SpawnWaveEvent)]
        # Wave 1: base_count=1 → 1 basic per lane per team → 3 lanes × 2 teams = 6 events
        teams = {e.team for e in spawn}
        lanes = {e.lane for e in spawn}
        assert teams == {0, 1}
        assert lanes == {0, 1, 2}
        for e in spawn:
            assert e.minion_type == "basic"
            assert e.count == 1

    def test_wave_four_has_four_basics(self):
        wm = _make_wm(rng_val=0.9)
        for _ in range(3):
            wm.tick(WAVE_INTERVAL)  # advance to wave 3 without events mattering
        events = wm.tick(WAVE_INTERVAL)
        spawn = [e for e in events if isinstance(e, SpawnWaveEvent) and e.team == 0 and e.lane == 0]
        total = sum(e.count for e in spawn)
        assert total == 4
        assert all(e.minion_type == "basic" for e in spawn)

    def test_wave_five_adds_cannon(self):
        wm = _make_wm(rng_val=0.9)
        for _ in range(4):
            wm.tick(WAVE_INTERVAL)
        events = wm.tick(WAVE_INTERVAL)
        spawn = [e for e in events if isinstance(e, SpawnWaveEvent) and e.team == 0 and e.lane == 0]
        types = {e.minion_type for e in spawn}
        assert "cannon" in types
        assert "basic" in types

    def test_wave_six_adds_healer(self):
        wm = _make_wm(rng_val=0.9)
        for _ in range(5):
            wm.tick(WAVE_INTERVAL)
        events = wm.tick(WAVE_INTERVAL)
        spawn = [e for e in events if isinstance(e, SpawnWaveEvent) and e.team == 0 and e.lane == 0]
        types = {e.minion_type for e in spawn}
        assert "healer" in types

    def test_wave_capped_at_max_size(self):
        wm = _make_wm(rng_val=0.9)
        for _ in range(MAX_WAVE_SIZE + 3):
            wm.tick(WAVE_INTERVAL)
        events = wm.tick(WAVE_INTERVAL)
        spawn = [e for e in events if isinstance(e, SpawnWaveEvent) and e.team == 0 and e.lane == 0]
        total = sum(e.count for e in spawn)
        assert total == MAX_WAVE_SIZE


# ---------------------------------------------------------------------------
# Ram injection
# ---------------------------------------------------------------------------


class TestRamInjection:
    def test_ram_spawns_when_rng_below_threshold(self):
        wm = _make_wm(rng_val=RAM_SPAWN_CHANCE - 0.01, rng_int_seq=[1, 2])
        events = wm.tick(WAVE_INTERVAL)
        ram = [e for e in events if isinstance(e, SpawnWaveEvent) and e.minion_type == "ram_t1"]
        assert len(ram) == 1
        assert ram[0].team == 1
        assert ram[0].lane == 2

    def test_ram_does_not_spawn_when_rng_at_threshold(self):
        wm = _make_wm(rng_val=RAM_SPAWN_CHANCE)
        events = wm.tick(WAVE_INTERVAL)
        ram = [e for e in events if isinstance(e, SpawnWaveEvent) and e.minion_type == "ram_t1"]
        assert len(ram) == 0

    def test_ram_does_not_spawn_when_rng_above_threshold(self):
        wm = _make_wm(rng_val=0.9)
        events = wm.tick(WAVE_INTERVAL)
        ram = [e for e in events if isinstance(e, SpawnWaveEvent) and e.minion_type == "ram_t1"]
        assert len(ram) == 0


# ---------------------------------------------------------------------------
# Lane boosts
# ---------------------------------------------------------------------------


class TestLaneBoosts:
    def test_boost_lane_increases_count(self):
        wm = _make_wm(rng_val=0.9)
        wm.boost_lane(0, 1, 2)
        events = wm.tick(WAVE_INTERVAL)
        # Wave 1 base_count=1, boost=2 → 3 minions on team 0 lane 1
        spawn = [e for e in events if isinstance(e, SpawnWaveEvent) and e.team == 0 and e.lane == 1]
        total = sum(e.count for e in spawn)
        assert total == 3

    def test_boost_all_lanes_adds_one_per_lane(self):
        wm = _make_wm(rng_val=0.9)
        wm.boost_all_lanes(1)
        events = wm.tick(WAVE_INTERVAL)
        for lane in range(3):
            spawn = [
                e
                for e in events
                if isinstance(e, SpawnWaveEvent) and e.team == 1 and e.lane == lane
            ]
            total = sum(e.count for e in spawn)
            assert total == 2  # 1 base + 1 boost

    def test_boosts_reset_after_wave(self):
        wm = _make_wm(rng_val=0.9)
        wm.boost_lane(0, 0, 5)
        wm.tick(WAVE_INTERVAL)
        # Second wave: no boosts — base_count for wave 2 is 2 on lane 0 team 0
        events = wm.tick(WAVE_INTERVAL)
        spawn = [e for e in events if isinstance(e, SpawnWaveEvent) and e.team == 0 and e.lane == 0]
        total = sum(e.count for e in spawn)
        assert total == 2  # wave 2 base, no boost

    def test_boost_lane_ignores_invalid_team(self):
        wm = WaveManager()
        wm.boost_lane(-1, 0, 5)
        wm.boost_lane(2, 0, 5)
        assert wm._lane_boosts == [[0, 0, 0], [0, 0, 0]]

    def test_boost_lane_ignores_invalid_lane(self):
        wm = WaveManager()
        wm.boost_lane(0, -1, 5)
        wm.boost_lane(0, 3, 5)
        assert wm._lane_boosts == [[0, 0, 0], [0, 0, 0]]

    def test_boost_all_lanes_ignores_invalid_team(self):
        wm = WaveManager()
        wm.boost_all_lanes(-1)
        wm.boost_all_lanes(2)
        assert wm._lane_boosts == [[0, 0, 0], [0, 0, 0]]


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------


class TestReset:
    def test_reset_clears_wave_number(self):
        wm = _make_wm(rng_val=0.9)
        wm.tick(WAVE_INTERVAL * 3)
        wm.reset()
        assert wm.wave_number == 0

    def test_reset_clears_timer(self):
        wm = WaveManager()
        wm.tick(12.0)
        wm.reset()
        assert wm._timer == 0.0

    def test_reset_clears_boosts(self):
        wm = WaveManager()
        wm.boost_lane(0, 0, 3)
        wm.reset()
        assert wm._lane_boosts == [[0, 0, 0], [0, 0, 0]]


# ---------------------------------------------------------------------------
# GameServer integration — _serialise + tick wiring
# ---------------------------------------------------------------------------


class TestGameServerWaveSerialise:
    """Verify _serialise handles SpawnWaveEvent and WaveAnnouncedEvent."""

    def test_serialise_spawn_wave_event(self):
        from server.game_server import _serialise

        evt = SpawnWaveEvent(wave_number=2, team=0, lane=1, minion_type="cannon", count=3)
        d = _serialise(evt)
        assert d["type"] == "spawn_wave"
        assert d["payload"]["wave_number"] == 2
        assert d["payload"]["team"] == 0
        assert d["payload"]["lane"] == 1
        assert d["payload"]["minion_type"] == "cannon"
        assert d["payload"]["count"] == 3

    def test_serialise_wave_announced_event(self):
        from server.game_server import _serialise

        evt = WaveAnnouncedEvent(wave_number=5)
        d = _serialise(evt)
        assert d["type"] == "wave_announced"
        assert d["payload"]["wave_number"] == 5

    def test_game_server_tick_emits_wave_events(self):
        from unittest.mock import MagicMock

        from server.game_server import GameServer

        gs = GameServer()
        # Inject deterministic waves (no ram)
        gs.waves = _make_wm(rng_val=0.9)

        client = MagicMock()
        gs.register(1, client)
        gs.tick(WAVE_INTERVAL)
        sent_types = [call.args[0]["type"] for call in client.send_update.call_args_list]
        assert "wave_announced" in sent_types
        assert "spawn_wave" in sent_types

    def test_start_game_resets_wave_manager(self):
        from server.game_server import GameServer

        gs = GameServer()
        # Manually advance the wave counter
        gs.waves.wave_number = 5
        gs.waves._timer = 15.0
        # Trigger start_game
        gs.handle(1, {"type": "start_game", "payload": {"map_seed": 42, "time_seed": 0}})
        assert gs.waves.wave_number == 0
        assert gs.waves._timer == 0.0

    def test_boost_lane_handler(self):
        from server.game_server import GameServer

        gs = GameServer()
        gs.handle(
            1, {"type": "request_lane_boost", "payload": {"team": 0, "lane_i": 2, "amount": 3}}
        )
        assert gs.waves._lane_boosts[0][2] == 3

    def test_boost_all_lanes_handler(self):
        from server.game_server import GameServer

        gs = GameServer()
        gs.handle(
            1, {"type": "request_lane_boost", "payload": {"team": 1, "lane_i": -1, "amount": 1}}
        )
        assert gs.waves._lane_boosts[1] == [1, 1, 1]


# ---------------------------------------------------------------------------
# WaveInfoUpdate emission
# ---------------------------------------------------------------------------


class TestWaveInfoUpdate:
    def test_wave_info_emitted_on_first_tick(self):
        """A fresh WaveManager emits WaveInfoUpdate on the first sub-interval tick."""
        wm = WaveManager()
        result = wm.tick(1.0)
        assert any(isinstance(e, WaveInfoUpdate) for e in result)

    def test_wave_info_has_correct_countdown(self):
        wm = WaveManager()
        result = wm.tick(3.0)
        info = next(e for e in result if isinstance(e, WaveInfoUpdate))
        assert info.next_in_seconds == pytest.approx(17.0)

    def test_wave_info_wave_number_is_zero_before_first_wave(self):
        wm = WaveManager()
        result = wm.tick(1.0)
        info = next(e for e in result if isinstance(e, WaveInfoUpdate))
        assert info.wave_number == 0

    def test_wave_info_not_emitted_twice_for_same_second(self):
        """Two ticks that land on the same integer countdown should only emit once."""
        wm = WaveManager()
        # First tick: timer=0.4 → countdown=int(19.6)=19 → emits WaveInfoUpdate
        result1 = wm.tick(0.4)
        assert any(isinstance(e, WaveInfoUpdate) for e in result1)
        # Second tick: timer=0.7 → countdown=int(19.3)=19 → same int, no re-emit
        result2 = wm.tick(0.3)
        assert not any(isinstance(e, WaveInfoUpdate) for e in result2)

    def test_wave_info_emitted_each_new_second(self):
        wm = WaveManager()
        seen = set()
        for _ in range(20):
            for e in wm.tick(1.0):
                if isinstance(e, WaveInfoUpdate):
                    seen.add(e.next_in_seconds)
        # Should have seen countdown values from 0 to 19
        assert len(seen) >= 19

    def test_wave_info_reset_clears_last_broadcast(self):
        """After reset(), the next tick emits a fresh WaveInfoUpdate."""
        wm = WaveManager()
        wm.tick(5.0)  # primes _last_info_broadcast
        wm.reset()
        result = wm.tick(1.0)
        assert any(isinstance(e, WaveInfoUpdate) for e in result)

    def test_wave_info_after_wave_fires(self):
        """After a wave fires, the next sub-interval tick emits WaveInfoUpdate again."""
        wm = _make_wm(rng_val=0.9)
        wm.tick(WAVE_INTERVAL)  # fires wave 1, resets _last_info_broadcast
        result = wm.tick(1.0)
        info = [e for e in result if isinstance(e, WaveInfoUpdate)]
        assert len(info) == 1
        assert info[0].wave_number == 1

    def test_serialise_wave_info_update(self):
        from server.game_server import _serialise

        u = WaveInfoUpdate(wave_number=3, next_in_seconds=12.0)
        d = _serialise(u)
        assert d["type"] == "wave_info"
        assert d["payload"]["wave_number"] == 3
        assert d["payload"]["next_in_seconds"] == pytest.approx(12.0)

    def test_game_server_tick_emits_wave_info(self):
        """GameServer.tick() relays WaveInfoUpdate to connected clients."""
        from unittest.mock import MagicMock

        from server.game_server import GameServer

        gs = GameServer()
        client = MagicMock()
        gs.register(1, client)
        gs.tick(3.0)  # sub-interval → triggers WaveInfoUpdate
        types = [call.args[0]["type"] for call in client.send_update.call_args_list]
        assert "wave_info" in types
