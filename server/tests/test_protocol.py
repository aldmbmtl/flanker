"""
test_protocol.py — Tests for server/protocol.py

These are pure unit tests with no network or Godot dependency.
"""

import struct

import pytest

from server.protocol import (
    HEADER_FORMAT,
    HEADER_SIZE,
    decode,
    encode,
    make_event,
    make_update,
    read_message,
)

# ---------------------------------------------------------------------------
# encode / decode round-trip
# ---------------------------------------------------------------------------


class TestEncode:
    def test_returns_bytes(self):
        result = encode({"type": "ping", "payload": {}})
        assert isinstance(result, bytes)

    def test_header_is_four_bytes(self):
        result = encode({"type": "ping", "payload": {}})
        assert len(result) >= HEADER_SIZE

    def test_header_length_matches_body(self):
        msg = {"type": "ping", "payload": {"timestamp": 1.0}}
        result = encode(msg)
        (length,) = struct.unpack(HEADER_FORMAT, result[:HEADER_SIZE])
        assert length == len(result) - HEADER_SIZE

    def test_round_trip_simple(self):
        original = {"type": "ping", "payload": {"timestamp": 12345.0}}
        frame = encode(original)
        body = frame[HEADER_SIZE:]
        recovered = decode(body)
        assert recovered == original

    def test_round_trip_nested_dict(self):
        original = {
            "type": "place_tower",
            "sender_id": 7,
            "payload": {"tower_type": "cannon", "team": 0, "position": [10.0, 0.0, 20.0]},
        }
        frame = encode(original)
        body = frame[HEADER_SIZE:]
        recovered = decode(body)
        assert recovered == original

    def test_round_trip_empty_payload(self):
        original = {"type": "noop", "payload": {}}
        frame = encode(original)
        body = frame[HEADER_SIZE:]
        recovered = decode(body)
        assert recovered == original

    def test_round_trip_integer_values(self):
        original = {"type": "test", "payload": {"a": 1, "b": -42, "c": 0}}
        frame = encode(original)
        body = frame[HEADER_SIZE:]
        assert decode(body) == original

    def test_round_trip_float_values(self):
        original = {"type": "test", "payload": {"x": 3.14, "y": -0.001}}
        frame = encode(original)
        body = frame[HEADER_SIZE:]
        recovered = decode(body)
        assert abs(recovered["payload"]["x"] - 3.14) < 1e-5
        assert abs(recovered["payload"]["y"] - (-0.001)) < 1e-5

    def test_round_trip_string_values(self):
        original = {"type": "register_player", "payload": {"name": "Alice"}}
        frame = encode(original)
        body = frame[HEADER_SIZE:]
        assert decode(body) == original

    def test_multiple_messages_produce_distinct_frames(self):
        m1 = encode({"type": "ping", "payload": {}})
        m2 = encode({"type": "pong", "payload": {"timestamp": 99.0}})
        assert m1 != m2


# ---------------------------------------------------------------------------
# read_message via a socket-like pipe
# ---------------------------------------------------------------------------


class _PipeSocket:
    """Minimal socket-like object backed by a bytes buffer."""

    def __init__(self, data: bytes) -> None:
        self._buf = bytearray(data)

    def recv(self, n: int) -> bytes:
        chunk = bytes(self._buf[:n])
        del self._buf[:n]
        return chunk


class TestReadMessage:
    def test_reads_one_message(self):
        original = {"type": "ping", "payload": {"timestamp": 1.0}}
        pipe = _PipeSocket(encode(original))
        recovered = read_message(pipe)
        assert recovered == original

    def test_returns_none_on_empty_socket(self):
        pipe = _PipeSocket(b"")
        assert read_message(pipe) is None

    def test_reads_two_consecutive_messages(self):
        m1 = {"type": "ping", "payload": {}}
        m2 = {"type": "register_player", "payload": {"name": "Bob"}}
        pipe = _PipeSocket(encode(m1) + encode(m2))
        assert read_message(pipe) == m1
        assert read_message(pipe) == m2

    def test_raises_on_truncated_body(self):
        original = {"type": "ping", "payload": {"a": "b" * 100}}
        frame = encode(original)
        # Truncate: keep header but only half the body
        truncated = frame[: HEADER_SIZE + len(frame) // 4]
        pipe = _PipeSocket(truncated)
        with pytest.raises(ConnectionError):
            read_message(pipe)

    def test_raises_when_body_immediately_closes(self):
        """Header arrives complete but connection closes before any body bytes."""
        import struct as _struct

        # Craft a header claiming 10 body bytes, then provide none
        fake_header = _struct.pack(HEADER_FORMAT, 10)
        pipe = _PipeSocket(fake_header)  # buffer exhausted after header
        with pytest.raises(ConnectionError):
            read_message(pipe)


# ---------------------------------------------------------------------------
# Convenience constructors
# ---------------------------------------------------------------------------


class TestMakeHelpers:
    def test_make_event_structure(self):
        ev = make_event("place_tower", sender_id=3, payload={"tower_type": "cannon"})
        assert ev["type"] == "place_tower"
        assert ev["sender_id"] == 3
        assert ev["payload"]["tower_type"] == "cannon"

    def test_make_update_structure(self):
        upd = make_update("tower_spawned", {"name": "Cannon_1", "health": 900.0})
        assert upd["type"] == "tower_spawned"
        assert upd["payload"]["name"] == "Cannon_1"

    def test_make_event_round_trip(self):
        ev = make_event("damage_player", 2, {"target_id": 5, "amount": 25.0})
        frame = encode(ev)
        body = frame[HEADER_SIZE:]
        recovered = decode(body)
        assert recovered == ev
