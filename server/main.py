"""
main.py — Entry point for the Python game server (Phase 0).

Starts a synchronous blocking TCP server on 127.0.0.1:7890.
Each connected Godot client is handled on its own thread (one thread per
connection — acceptable at ≤10 players; asyncio is introduced in Phase 3).

Usage:
    python -m server.main
    python server/main.py

Environment variables:
    SERVER_HOST  — bind address (default: 127.0.0.1)
    SERVER_PORT  — bind port    (default: 7890)
    LOG_FILE     — path for the rotating log file (default: logs/server.log)
"""

from __future__ import annotations

import logging
import os
import socket
import threading
import time
from logging.handlers import RotatingFileHandler

from server.game_server import GameServer
from server.protocol import encode, read_message

# ---------------------------------------------------------------------------
# Logging — stderr (INFO) + rotating file (DEBUG)
# ---------------------------------------------------------------------------

_LOG_FMT = "%(asctime)s [flanker-server] %(levelname)s %(name)s %(message)s"
_LOG_FMT_BRIEF = "[flanker-server] %(levelname)s %(message)s"

logging.basicConfig(
    level=logging.DEBUG,
    format=_LOG_FMT_BRIEF,
)

# Elevate the stderr handler to INFO so the console stays readable.
_stderr_handler = logging.root.handlers[0]
_stderr_handler.setLevel(logging.INFO)
_stderr_handler.setFormatter(logging.Formatter(_LOG_FMT_BRIEF))

# File handler — DEBUG level with timestamps, rotating at 10 MB, 3 backups.
_log_file = os.environ.get("LOG_FILE", os.path.join("logs", "server.log"))
os.makedirs(os.path.dirname(os.path.abspath(_log_file)), exist_ok=True)
_file_handler = RotatingFileHandler(
    _log_file, maxBytes=10 * 1024 * 1024, backupCount=3, encoding="utf-8"
)
_file_handler.setLevel(logging.DEBUG)
_file_handler.setFormatter(logging.Formatter(_LOG_FMT))
logging.root.addHandler(_file_handler)

log = logging.getLogger(__name__)

HOST = os.environ.get("SERVER_HOST", "127.0.0.1")
PORT = int(os.environ.get("SERVER_PORT", "7890"))

TICK_RATE: float = 1.0 / 20.0  # 20 Hz game loop tick


# ---------------------------------------------------------------------------
# Per-connection client handle
# ---------------------------------------------------------------------------


class SocketClient:
    """Wraps a connected socket. Thread-safe send via a lock."""

    def __init__(self, sock: socket.socket, addr) -> None:
        self._sock = sock
        self._addr = addr
        self._lock = threading.Lock()

    def send_update(self, update: dict) -> None:
        data = encode(update)
        with self._lock:
            try:
                self._sock.sendall(data)
            except OSError:
                pass  # connection gone; server will clean up on recv side

    def close(self) -> None:
        try:
            self._sock.close()
        except OSError:
            pass

    def __repr__(self) -> str:
        return f"SocketClient({self._addr})"


# ---------------------------------------------------------------------------
# Connection handler (runs in its own thread)
# ---------------------------------------------------------------------------


def _handle_connection(
    peer_id: int,
    sock: socket.socket,
    addr,
    server: GameServer,
) -> None:
    client = SocketClient(sock, addr)
    server.register(peer_id, client)
    log.info("peer %d connected from %s", peer_id, addr)

    try:
        while True:
            try:
                msg = read_message(sock)
            except (ConnectionError, OSError) as exc:
                log.debug("peer %d read error: %s", peer_id, exc)
                break  # socket gone — exit loop cleanly
            if msg is None:
                break  # clean close
            # Ensure sender_id is set (Godot sends it, but be defensive)
            msg.setdefault("sender_id", peer_id)
            try:
                server.handle(peer_id, msg)
            except Exception:  # noqa: BLE001
                # Log the full traceback so bugs in handlers are visible, but
                # do NOT kill the connection — keep serving the peer.
                log.exception(
                    "peer %d: unhandled exception in handle() for msg type=%r",
                    peer_id,
                    msg.get("type", "?"),
                )
    finally:
        server.unregister(peer_id)
        client.close()
        log.info("peer %d disconnected", peer_id)


# ---------------------------------------------------------------------------
# Tick loop (runs in its own daemon thread)
# ---------------------------------------------------------------------------


def _run_tick_loop(server: GameServer, stop_event: threading.Event) -> None:
    """Advance time-based subsystems at TICK_RATE Hz until stop_event is set."""
    last = time.monotonic()
    while not stop_event.is_set():
        now = time.monotonic()
        delta = now - last
        last = now
        server.tick(delta)
        elapsed = time.monotonic() - now
        sleep_for = TICK_RATE - elapsed
        if sleep_for > 0.0:
            time.sleep(sleep_for)


# ---------------------------------------------------------------------------
# Main server loop
# ---------------------------------------------------------------------------


def run(host: str = HOST, port: int = PORT) -> None:  # pragma: no cover
    game_server = GameServer()
    next_peer_id = 1

    stop_tick = threading.Event()
    tick_thread = threading.Thread(
        target=_run_tick_loop,
        args=(game_server, stop_tick),
        daemon=True,
    )
    tick_thread.start()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((host, port))
        srv.listen(10)
        log.info("listening on %s:%d", host, port)

        while True:
            try:
                conn, addr = srv.accept()
            except KeyboardInterrupt:
                log.info("shutting down")
                break

            peer_id = next_peer_id
            next_peer_id += 1

            t = threading.Thread(
                target=_handle_connection,
                args=(peer_id, conn, addr, game_server),
                daemon=True,
            )
            t.start()

    stop_tick.set()


if __name__ == "__main__":  # pragma: no cover
    run()
