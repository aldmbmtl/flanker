"""
test_main.py — Tests for server/main.py (SocketClient and _handle_connection).

The blocking run() function and __main__ guard are excluded via # pragma: no cover.
Everything else — SocketClient and _handle_connection — is covered here using
mock sockets and a real GameServer instance.
"""

from __future__ import annotations

import logging
import socket
import threading
from logging.handlers import RotatingFileHandler
from unittest.mock import MagicMock

from server.game_server import GameServer
from server.main import SocketClient, _handle_connection, _run_tick_loop
from server.protocol import encode, make_event

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_mock_sock(recv_data: bytes = b"") -> MagicMock:
    """
    Return a mock socket that delivers recv_data in exact requested chunk sizes,
    then returns b'' to signal a clean close — exactly how a real blocking socket
    behaves with _recv_exact's incremental recv(n - len(buf)) calls.
    """
    sock = MagicMock(spec=socket.socket)
    buf = bytearray(recv_data)

    def _recv(n):
        if not buf:
            return b""
        chunk = bytes(buf[:n])
        del buf[:n]
        return chunk

    sock.recv.side_effect = _recv
    return sock


def _framed(msg: dict) -> bytes:
    """Encode a dict as a length-prefixed msgpack frame."""
    return encode(msg)


# ---------------------------------------------------------------------------
# SocketClient
# ---------------------------------------------------------------------------


class TestSocketClient:
    def test_send_update_calls_sendall(self):
        sock = MagicMock(spec=socket.socket)
        client = SocketClient(sock, ("127.0.0.1", 9999))
        update = {"type": "pong", "payload": {"timestamp": 1.0}}
        client.send_update(update)
        sock.sendall.assert_called_once_with(encode(update))

    def test_send_update_oserror_is_swallowed(self):
        """A broken connection must not propagate an exception."""
        sock = MagicMock(spec=socket.socket)
        sock.sendall.side_effect = OSError("connection reset")
        client = SocketClient(sock, ("127.0.0.1", 9999))
        # Must not raise
        client.send_update({"type": "test", "payload": {}})

    def test_close_calls_sock_close(self):
        sock = MagicMock(spec=socket.socket)
        client = SocketClient(sock, ("127.0.0.1", 9999))
        client.close()
        sock.close.assert_called_once()

    def test_close_oserror_is_swallowed(self):
        sock = MagicMock(spec=socket.socket)
        sock.close.side_effect = OSError("already closed")
        client = SocketClient(sock, ("127.0.0.1", 9999))
        # Must not raise
        client.close()

    def test_repr_contains_addr(self):
        sock = MagicMock(spec=socket.socket)
        client = SocketClient(sock, ("10.0.0.1", 1234))
        assert "10.0.0.1" in repr(client)
        assert "1234" in repr(client)

    def test_send_update_is_thread_safe(self):
        """Multiple threads sending simultaneously must not raise."""
        sock = MagicMock(spec=socket.socket)
        client = SocketClient(sock, ("127.0.0.1", 9999))
        errors = []

        def send():
            try:
                for _ in range(50):
                    client.send_update({"type": "t", "payload": {}})
            except Exception as exc:
                errors.append(exc)

        threads = [threading.Thread(target=send) for _ in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert errors == []


# ---------------------------------------------------------------------------
# _handle_connection
# ---------------------------------------------------------------------------


class TestHandleConnection:
    def test_registers_and_unregisters_peer(self):
        """Peer is registered on entry and unregistered on clean close."""
        server = GameServer()
        sock = _make_mock_sock(b"")  # immediate clean close
        addr = ("127.0.0.1", 5000)

        _handle_connection(1, sock, addr, server)

        assert server.client_count() == 0  # unregistered after exit

    def test_peer_is_registered_during_connection(self):
        """While the connection is alive the peer is registered."""
        server = GameServer()
        registered_during = []

        original_handle = server.handle

        def spy_handle(peer_id, msg):
            registered_during.append(server.client_count())
            return original_handle(peer_id, msg)

        server.handle = spy_handle

        # Send one ping message then EOF
        ping = _framed(make_event("ping", 1, {"timestamp": 0.0}))
        sock = _make_mock_sock(ping)
        _handle_connection(1, sock, ("127.0.0.1", 5000), server)

        assert registered_during == [1]  # was registered when handle() ran

    def test_sends_pong_in_response_to_ping(self):
        """Integration: a framed ping message produces a pong via sendall."""
        ping = _framed(make_event("ping", 1, {"timestamp": 42.0}))
        sock = _make_mock_sock(ping)

        server = GameServer()
        _handle_connection(1, sock, ("127.0.0.1", 5000), server)

        # sendall must have been called at least once (with the pong)
        assert sock.sendall.call_count >= 1
        sent_bytes = sock.sendall.call_args_list[0][0][0]
        # Decode and verify it's a pong
        import msgpack

        length = int.from_bytes(sent_bytes[:4], "big")
        decoded = msgpack.unpackb(sent_bytes[4 : 4 + length], raw=False)
        assert decoded["type"] == "pong"
        assert decoded["payload"]["timestamp"] == 42.0

    def test_connection_error_does_not_propagate(self):
        """A ConnectionError mid-stream must be caught and handled cleanly."""
        sock = MagicMock(spec=socket.socket)
        sock.recv.side_effect = ConnectionError("reset by peer")

        server = GameServer()
        # Must not raise
        _handle_connection(1, sock, ("127.0.0.1", 5000), server)

        assert server.client_count() == 0

    def test_oserror_does_not_propagate(self):
        """An OSError mid-stream must be caught and handled cleanly."""
        sock = MagicMock(spec=socket.socket)
        sock.recv.side_effect = OSError("broken pipe")

        server = GameServer()
        _handle_connection(1, sock, ("127.0.0.1", 5000), server)

        assert server.client_count() == 0

    def test_sender_id_defaulted_from_peer_id(self):
        """If a message arrives without sender_id, it is set to peer_id."""
        received = []
        server = GameServer()
        original_handle = server.handle

        def capturing_handle(peer_id, msg):
            received.append(msg)
            return original_handle(peer_id, msg)

        server.handle = capturing_handle

        # Build a message without sender_id
        import msgpack

        raw_msg = {"type": "ping", "payload": {"timestamp": 0.0}}
        # Deliberately omit sender_id
        packed = msgpack.packb(raw_msg, use_bin_type=True)
        frame = len(packed).to_bytes(4, "big") + packed
        sock = _make_mock_sock(frame)

        _handle_connection(7, sock, ("127.0.0.1", 5000), server)

        assert len(received) == 1
        assert received[0]["sender_id"] == 7

    def test_existing_sender_id_not_overwritten(self):
        """If a message already has sender_id, it must not be replaced."""
        received = []
        server = GameServer()
        original_handle = server.handle

        def capturing_handle(peer_id, msg):
            received.append(msg)
            return original_handle(peer_id, msg)

        server.handle = capturing_handle

        # Include sender_id explicitly in the message
        msg_with_id = make_event("ping", 99, {"timestamp": 0.0})
        frame = _framed(msg_with_id)
        sock = _make_mock_sock(frame)

        _handle_connection(7, sock, ("127.0.0.1", 5000), server)

        assert received[0]["sender_id"] == 99  # original preserved

    def test_handle_exception_does_not_kill_connection(self):
        """
        Regression: an unhandled exception inside server.handle() must NOT
        close the connection. Subsequent messages from the same peer must still
        be processed.

        Before the fix, any exception propagated out of the while-True loop and
        hit the outer finally block, which called server.unregister() and
        closed the socket — silently dropping all future messages (including
        role_accepted replies) and hanging any awaiting Godot coroutine.
        """
        call_count = []
        server = GameServer()

        call_number = [0]

        def flaky_handle(peer_id, msg):
            call_number[0] += 1
            call_count.append(call_number[0])
            if call_number[0] == 1:
                raise RuntimeError("simulated handler crash")
            # Second call: process normally via real handle
            return GameServer.handle(server, peer_id, msg)

        server.handle = flaky_handle

        # Two pings back-to-back; first triggers crash, second must still land.
        ping = _framed(make_event("ping", 1, {"timestamp": 1.0}))
        sock = _make_mock_sock(ping + ping)

        _handle_connection(1, sock, ("127.0.0.1", 5000), server)

        # Both messages were processed — connection survived the first crash.
        assert len(call_count) == 2, (
            "second message was never processed — exception killed the connection"
        )

    def test_handle_exception_peer_unregistered_on_disconnect(self):
        """
        Even when handler exceptions occur, the peer must still be unregistered
        cleanly when the socket eventually closes.
        """
        server = GameServer()

        def always_raise(peer_id, msg):
            raise ValueError("bad message")

        server.handle = always_raise

        ping = _framed(make_event("ping", 1, {"timestamp": 0.0}))
        sock = _make_mock_sock(ping)

        _handle_connection(1, sock, ("127.0.0.1", 5000), server)

        assert server.client_count() == 0  # unregistered despite exception


# ---------------------------------------------------------------------------
# _run_tick_loop
# ---------------------------------------------------------------------------


class TestRunTickLoop:
    def test_tick_loop_calls_tick_and_stops(self):
        """_run_tick_loop calls server.tick at least once before stop_event fires."""
        import threading

        tick_counts = []
        server = GameServer()
        original_tick = server.tick

        def counting_tick(delta):
            tick_counts.append(delta)
            return original_tick(delta)

        server.tick = counting_tick
        stop = threading.Event()

        t = threading.Thread(target=_run_tick_loop, args=(server, stop), daemon=True)
        t.start()
        import time

        time.sleep(0.12)  # let 2+ ticks fire at 20 Hz
        stop.set()
        t.join(timeout=1.0)

        assert len(tick_counts) >= 2
        assert not t.is_alive()

    def test_tick_loop_stops_immediately_when_event_pre_set(self):
        """If stop_event is already set, the loop exits without calling tick."""
        import threading

        tick_counts = []
        server = GameServer()
        server.tick = lambda delta: tick_counts.append(delta)

        stop = threading.Event()
        stop.set()

        t = threading.Thread(target=_run_tick_loop, args=(server, stop), daemon=True)
        t.start()
        t.join(timeout=1.0)

        assert tick_counts == []


# ---------------------------------------------------------------------------
# Logging setup — RotatingFileHandler and LOG_FILE env var
# ---------------------------------------------------------------------------


class TestLoggingSetup:
    def test_root_logger_has_rotating_file_handler(self):
        """main.py module setup must attach a RotatingFileHandler to the root logger."""
        root = logging.getLogger()
        file_handlers = [h for h in root.handlers if isinstance(h, RotatingFileHandler)]
        assert file_handlers, (
            "Root logger must have at least one RotatingFileHandler after importing server.main"
        )

    def test_file_handler_level_is_debug(self):
        """The RotatingFileHandler must be set to DEBUG so all diagnostic messages are written."""
        root = logging.getLogger()
        file_handlers = [h for h in root.handlers if isinstance(h, RotatingFileHandler)]
        assert file_handlers, "No RotatingFileHandler found on root logger"
        assert file_handlers[0].level == logging.DEBUG, (
            "RotatingFileHandler level must be DEBUG to capture verbose diagnostic logs"
        )

    def test_file_handler_formatter_includes_asctime(self):
        """Log file format must include timestamps (%(asctime)s) for debugging."""
        root = logging.getLogger()
        file_handlers = [h for h in root.handlers if isinstance(h, RotatingFileHandler)]
        assert file_handlers, "No RotatingFileHandler found on root logger"
        fmt = file_handlers[0].formatter._fmt  # type: ignore[union-attr]
        assert "asctime" in fmt, (
            "RotatingFileHandler formatter must include %(asctime)s for timestamped logs"
        )

    def test_file_handler_max_bytes(self):
        """RotatingFileHandler must rotate at 10 MB to prevent unbounded log growth."""
        root = logging.getLogger()
        file_handlers = [h for h in root.handlers if isinstance(h, RotatingFileHandler)]
        assert file_handlers, "No RotatingFileHandler found on root logger"
        assert file_handlers[0].maxBytes == 10 * 1024 * 1024, (
            "RotatingFileHandler maxBytes must be 10 MB"
        )

    def test_file_handler_backup_count(self):
        """RotatingFileHandler must keep 3 backup files."""
        root = logging.getLogger()
        file_handlers = [h for h in root.handlers if isinstance(h, RotatingFileHandler)]
        assert file_handlers, "No RotatingFileHandler found on root logger"
        assert file_handlers[0].backupCount == 3, "RotatingFileHandler backupCount must be 3"

    def test_stderr_handler_level_is_info(self):
        """The stderr (stream) handler must be set to INFO to avoid console spam."""
        import server.main as main_module

        assert main_module._stderr_handler.level == logging.INFO, (
            "stderr handler level must be INFO so DEBUG messages do not flood the console"
        )

    def test_log_file_path_comes_from_env_var(self):
        """_log_file must equal the LOG_FILE env var when it is set."""
        import os

        import server.main as main_module

        expected = os.environ.get("LOG_FILE", os.path.join("logs", "server.log"))
        assert main_module._log_file == expected, (
            "_log_file must be set from LOG_FILE env var (or default logs/server.log)"
        )
