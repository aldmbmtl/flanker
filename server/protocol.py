"""
protocol.py — Wire format for Godot ↔ Python communication.

Every message is a msgpack-encoded dict with a 4-byte big-endian uint32 length prefix.

Event (Godot → Python):
    {"type": str, "sender_id": int, "payload": dict}

StateUpdate (Python → Godot):
    {"type": str, "payload": dict}
"""

import struct

import msgpack

# ---------------------------------------------------------------------------
# Framing
# ---------------------------------------------------------------------------

HEADER_FORMAT = ">I"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)  # 4 bytes


def encode(message: dict) -> bytes:
    """Encode a dict to a length-prefixed msgpack frame."""
    body = msgpack.packb(message, use_bin_type=True)
    return struct.pack(HEADER_FORMAT, len(body)) + body


def decode(body: bytes) -> dict:
    """Decode a msgpack body (without the length prefix) to a dict."""
    return msgpack.unpackb(body, raw=False)


# ---------------------------------------------------------------------------
# Reader helper — reads exactly one framed message from a socket
# ---------------------------------------------------------------------------


def read_message(sock) -> dict | None:
    """
    Read one length-prefixed msgpack message from a blocking socket.
    Returns None if the connection is closed cleanly (recv returns b"").
    Raises ConnectionError on partial reads.
    """
    header = _recv_exact(sock, HEADER_SIZE)
    if header is None:
        return None
    (length,) = struct.unpack(HEADER_FORMAT, header)
    body = _recv_exact(sock, length)
    if body is None:
        raise ConnectionError("Connection closed mid-message")
    return decode(body)


def _recv_exact(sock, n: int) -> bytes | None:
    """Read exactly n bytes from a blocking socket. Returns None on clean close."""
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            if len(buf) == 0:
                return None  # clean close before any bytes
            raise ConnectionError(f"Connection closed after {len(buf)} of {n} bytes")
        buf.extend(chunk)
    return bytes(buf)


# ---------------------------------------------------------------------------
# Convenience constructors
# ---------------------------------------------------------------------------


def make_event(event_type: str, sender_id: int, payload: dict) -> dict:
    return {"type": event_type, "sender_id": sender_id, "payload": payload}


def make_update(update_type: str, payload: dict) -> dict:
    return {"type": update_type, "payload": payload}
