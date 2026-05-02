# Flanker — Python Authority Layer Migration Plan

**Created:** 2026-05-02  
**Status:** Approved, not started  
**Author:** Conversation with OpenCode  

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Root Cause Analysis](#2-root-cause-analysis)
3. [Decision: Why Not a Full Rewrite](#3-decision-why-not-a-full-rewrite)
4. [Target Architecture](#4-target-architecture)
5. [What Gets Replaced vs What Stays](#5-what-gets-replaced-vs-what-stays)
6. [How Each Pain Point Is Solved](#6-how-each-pain-point-is-solved)
7. [Python Stack](#7-python-stack)
8. [Phase-by-Phase Execution Plan](#8-phase-by-phase-execution-plan)
9. [Entity Registry Pattern](#9-entity-registry-pattern)
10. [Sync Contract Pattern](#10-sync-contract-pattern)
11. [Game State Machine](#11-game-state-machine)
12. [Protocol Design](#12-protocol-design)
13. [Testing Strategy](#13-testing-strategy)
14. [Docker / Headless Server Path](#14-docker--headless-server-path)
15. [Effort Estimate](#15-effort-estimate)
16. [Known Bugs Fixed By This Migration](#16-known-bugs-fixed-by-this-migration)
17. [Risks and Mitigations](#17-risks-and-mitigations)

---

## 1. Problem Statement

The project has actual users and is actively maintained, but four recurring pain points are making progress unsustainable:

### Pain Point 1 — Multiplayer desync ("X on host, not on client")
A feature works correctly on the host machine but is missing or wrong on connected clients. Debugging requires understanding the GDScript RPC system, Godot's multiplayer authority model, and the specific sync pattern chosen for that entity type.

### Pain Point 2 — Adding entities breaks multiplayer
Adding a new tower, minion, or skill requires touching 4–6 files in disconnected parts of the codebase. If any single file is missed, the entity silently fails to sync to clients. There is no registry or contract that enforces completeness.

### Pain Point 3 — Win conditions and build limits are fragile
The win condition currently has a double-broadcast bug (game_over fires twice on clients). The build limit logic is correct but opaque — spread across `LaneControl`, `BuildSystem`, and `LobbyManager`. These systems are hard to read, modify, and test.

### Pain Point 4 — Large codebase, weak DRY discipline, tests don't block real bugs
The 608-test GUT suite tests implementation details, not distributed behavior contracts. A test can pass while the feature it covers is broken in a real multiplayer session. The developer cannot read GDScript errors, write fixes independently, or add meaningful tests without AI assistance.

---

## 2. Root Cause Analysis

The root cause is **not the language** — it is the architecture of the multiplayer layer.

### Finding 1: Three incompatible sync patterns

The codebase uses three completely different patterns for syncing state to clients, with no consistency:

| Entity type | Sync pattern | How it works |
|---|---|---|
| Towers | Event-driven RPC | `spawn_item_visuals.rpc()` — `call_remote`, fires once on place/despawn |
| Minions | Continuous batch push | `sync_minion_states.rpc()` — unreliable_ordered, fires every frame |
| Skills | Per-effect directed RPC | `apply_dash.rpc_id(peer)`, `apply_rapid_fire.rpc_id(peer)` — per ability |

When adding a new entity, the developer must know which pattern to use. If the wrong one is chosen, or the RPC wiring in `LobbyManager.gd` is missed, the entity only works on the host.

### Finding 2: No central entity registry

Adding a tower requires changes in 5 places:
1. `BuildSystem.PLACEABLE_DEFS` — cost, attack_range, spacing
2. `BuildSystem.spawn_item_local()` — a new `elif` branch for naming
3. A new `.tscn` scene file
4. A new `.gd` script extending `TowerBase`
5. A new bespoke `spawn_X_visuals.rpc()` in `LobbyManager.gd`

There is no automatic discovery. Missing step 5 produces a host-only entity with no error.

### Finding 3: Win condition double-broadcast bug (active)

`TeamLives.lose_life()` calls `_broadcast_game_over.rpc()` which emits `game_over` on all clients. Then `LobbyManager._on_team_lives_game_over()` calls `_rpc_game_over.rpc()` which emits `game_over` again. The signal fires twice on every client.

Relevant lines:
- `TeamLives.gd:36-40` — first broadcast
- `LobbyManager.gd:985-993` — second broadcast

### Finding 4: 75-80% of game logic lives in 9 autoloads

The game architecture is already a service layer. The autoloads own all state; scene-attached scripts are thin consumers. This is the key insight that makes the hybrid approach viable — those 9 autoloads can be replaced with Python without touching any rendering, physics, or UI code.

---

## 3. Decision: Why Not a Full Rewrite

A full rewrite onto Python/Panda3D was evaluated and rejected for this project at this time.

**Why rejected:**
- `godot-python` (the only viable Godot 4 + Python bridge) is not production-ready for Godot 4 as of 2026. The Godot 4 branch is unreleased.
- A Panda3D rewrite is estimated at 4–5 months of side-project work with no shippable game until completion.
- Godot is good at what it does: 3D rendering, physics, audio, shaders. Replacing it produces no user-visible benefit.
- The pain points are all in the *logic layer*, not the rendering layer.

**Why the hybrid approach is better:**
- The 9 autoloads that cause pain are already written as a service layer with no rendering or physics coupling.
- Replacing those 9 autoloads with Python eliminates all four pain points without touching any Godot rendering code.
- Estimated effort: 8–13 weeks vs 4–5 months.
- The game is shippable at every phase boundary.
- The Python server is Docker-ready from day one, enabling future headless multiplayer hosting.

---

## 4. Target Architecture

### Current architecture
```
Godot (everything)
├── Autoloads (game logic + network authority)
│   ├── GameSync         — all combat state
│   ├── LobbyManager     — all multiplayer RPCs (1,029 lines)
│   ├── TeamData         — economy
│   ├── LevelSystem      — progression
│   ├── TeamLives        — win condition
│   ├── SkillTree        — skill state
│   ├── LaneControl      — territory / build limits
│   ├── FighterSkills    — ability execution
│   └── SupporterSkills  — ability execution
└── Scene scripts (rendering + physics)
    ├── FPSController    — player input + visuals
    ├── TowerBase        — tower logic + visuals
    ├── MinionBase       — minion AI + visuals
    └── ... (all other scene scripts)
```

### Target architecture (single-player / listen server)
```
┌──────────────────────────────────────────────────┐
│              Godot (renderer + input)             │
│                                                   │
│  Scene scripts (unchanged):                       │
│  FPSController, TowerBase, MinionBase, all UI     │
│                                                   │
│  Autoload relay stubs (thin):                     │
│  GameSync.gd → forwards events, receives state   │
│  LobbyManager.gd → forwards events, receives state│
│  (all 9 autoloads become thin relay stubs)        │
└────────────────────┬─────────────────────────────┘
                     │ localhost TCP socket (msgpack)
                     │ Python launched as subprocess
┌────────────────────▼─────────────────────────────┐
│              Python Game Server                   │
│                                                   │
│  server/                                          │
│  ├── game_server.py   — main event loop           │
│  ├── combat.py        — replaces GameSync         │
│  ├── lobby.py         — replaces LobbyManager     │
│  ├── economy.py       — replaces TeamData         │
│  ├── progression.py   — replaces LevelSystem      │
│  ├── game_state.py    — replaces TeamLives        │
│  ├── skills.py        — replaces SkillTree        │
│  ├── territory.py     — replaces LaneControl      │
│  ├── skills/          
│  │   ├── fighter.py   — replaces FighterSkills    │
│  │   └── supporter.py — replaces SupporterSkills  │
│  ├── registry.py      — unified entity registry   │
│  └── protocol.py      — msgpack event/state defs  │
│                                                   │
│  tests/                                           │
│  └── test_*.py        — pytest suite              │
└──────────────────────────────────────────────────┘
```

### Target architecture (future: dedicated server / Docker)
```
┌───────────────┐     TCP      ┌─────────────────────────────┐
│ Godot Client A│ ────────────►│                             │
├───────────────┤              │   Python Game Server        │
│ Godot Client B│ ────────────►│   (Docker container)        │
├───────────────┤              │                             │
│ Godot Client C│ ────────────►│   Same Python code.         │
└───────────────┘              │   Zero code changes.        │
                               └─────────────────────────────┘
```

The local subprocess model and the Docker model use the same Python server code. The only difference is the address Godot connects to (`127.0.0.1` vs `SERVER_HOST` env var).

---

## 5. What Gets Replaced vs What Stays

### Replaced (Python)

| GDScript file | Lines | Python replacement |
|---|---|---|
| `scripts/GameSync.gd` | 206 | `server/combat.py` |
| `scripts/LobbyManager.gd` | 1,029 | `server/lobby.py` + `server/network.py` |
| `scripts/TeamData.gd` | 52 | `server/economy.py` |
| `scripts/LevelSystem.gd` | 238 | `server/progression.py` |
| `scripts/TeamLives.gd` | 53 | `server/game_state.py` |
| `scripts/SkillTree.gd` | 410 | `server/skills.py` |
| `scripts/LaneControl.gd` | 178 | `server/territory.py` |
| `scripts/skills/FighterSkills.gd` | 331 | `server/skills/fighter.py` |
| `scripts/skills/SupporterSkills.gd` | 65 | `server/skills/supporter.py` |
| `scripts/SkillDefs.gd` | 249 | `server/registry.py` (skills section) |
| `scripts/BuildSystem.gd` | 286 | `server/registry.py` (towers section) + `server/build.py` |
| **Total** | **~3,097 lines** | |

### Stays in GDScript (untouched)

Everything that renders, handles physics, plays audio, or manages UI:

| Category | Scripts |
|---|---|
| Rendering / world | `TerrainGenerator`, `LaneVisualizer`, `FogOverlay`, `TreePlacer`, `WallPlacer`, `FencePlacer`, `LampPlacer`, `WindParticles` |
| Physics / movement | `FPSController` (input + camera), `BasePlayer`, `MinionBase` (puppet), `TowerBase` (visual), `ProjectileBase` + all projectiles |
| Audio | `SoundManager` |
| UI / HUD | All 24 UI scripts |
| Shaders | All 5 `.gdshader` files |
| Network transport | `NetworkManager.gd` — ENet peer setup stays in Godot for now |
| Minor autoloads | `LoadingState`, `GraphicsSettings`, `GameSettings`, `SoundManager`, `LaneData` |

**The Godot autoloads that are replaced become thin relay stubs.** They maintain the same public API (signals, method names) so that all existing scene scripts continue to work without modification. Internally, instead of owning state, they forward events to Python and receive state updates back.

---

## 6. How Each Pain Point Is Solved

### Pain Point 1 — "X on host, not on client"

**Root cause:** Three inconsistent sync patterns. `call_remote` RPCs skip the host. Manual wiring in `LobbyManager.gd` is easily missed.

**Solution:** Python server pushes `StateUpdate` objects to every registered Godot client, including the host-side Godot instance. There is no `call_remote` asymmetry. The host Godot instance is registered as a client like any other. Every state change goes through one path.

```python
# server/game_server.py
def apply_event(self, sender_id: int, event: Event) -> None:
    updates = self._process(event)
    for client in self._clients.values():  # includes host
        client.send(updates)
```

Structurally impossible to have host-only state after Phase 4.

### Pain Point 2 — "Adding entities breaks multiplayer"

**Root cause:** No central registry. Entity sync requires manual wiring in 5 places.

**Solution:** Central Python registry. A new tower is one `TowerDef` dataclass entry. The sync behavior is inherited from the base class. Missing fields raise `TypeError` at import time — not silently at runtime.

```python
# server/registry.py
@dataclass
class TowerDef:
    tower_type: str      # required
    cost: int            # required
    max_health: float    # required
    attack_range: float  # required
    # TypeError at startup if any field is missing

TOWER_REGISTRY: dict[str, TowerDef] = {
    "cannon": TowerDef(tower_type="cannon", cost=25, max_health=900, attack_range=30.0),
    # adding a new tower = one line here
}
```

No bespoke RPCs to add in `LobbyManager`. No `elif` branches in `spawn_item_local`. The sync contract is in the base class.

### Pain Point 3 — "Win conditions and build limits are fragile"

**Root cause:** Win condition has a double-broadcast bug. No explicit state machine.

**Solution:** `GameStateMachine` in Python with explicit phases and a single `game_over` transition point. The double-broadcast bug disappears by construction.

```python
# server/game_state.py
class GamePhase(Enum):
    LOBBY    = "lobby"
    LOADING  = "loading"
    PLAYING  = "playing"
    GAME_OVER = "game_over"

class GameStateMachine:
    def lose_life(self, team: int) -> list[StateUpdate]:
        self._lives[team] -= 1
        if self._lives[team] <= 0 and self._phase == GamePhase.PLAYING:
            self._phase = GamePhase.GAME_OVER
            return [GameOverUpdate(winner=1 - team)]  # fires exactly once
        return [LivesUpdate(team=team, lives=self._lives[team])]
```

Build limits are a plain Python method with no GDScript required to read or modify.

### Pain Point 4 — "Tests don't block real bugs"

**Root cause:** GUT tests verify function implementations, not distributed behavior contracts. Tests require Godot runtime.

**Solution:** pytest tests that verify contracts. The most important class of missing test — "when event X is sent, all clients receive update Y" — becomes trivial.

```python
# tests/test_sync_contracts.py
def test_tower_placement_broadcasts_to_all_clients():
    server = GameServer()
    client_a, client_b = FakeClient(), FakeClient()
    server.register(1, client_a)
    server.register(2, client_b)

    server.handle(1, PlaceTowerEvent(tower_type="cannon", team=0, pos=(10, 0, 10)))

    assert client_a.last_message()["type"] == "tower_spawned"
    assert client_b.last_message()["type"] == "tower_spawned"
    # No Godot runtime. Runs in 2ms.
```

All tests run with `pytest` — no Godot, no GUT, no `make test`. VS Code shows red/green inline.

---

## 7. Python Stack

| Purpose | Library | Install |
|---|---|---|
| Server runtime | stdlib `asyncio` | built-in |
| Serialization | `msgpack` | `pip install msgpack` |
| Event types | `dataclasses` | built-in |
| Signals/events | `blinker` | `pip install blinker` |
| Tests | `pytest` | `pip install pytest` |
| Type checking | `mypy` | `pip install mypy` (optional but recommended) |
| Docker | `python:3.12-slim` base image | — |

No heavy dependencies. The Python server is a small asyncio application. It has no Godot dependency and no Panda3D dependency.

---

## 8. Phase-by-Phase Execution Plan

### Phase 0 — Foundation
**Duration:** 1–2 weeks  
**Goal:** Python server starts, Godot connects, ping/pong works.

Tasks:
- Create `server/` Python package at the project root
- Implement `GameServer` class with asyncio event loop and client registry
- Define the base `Event` and `StateUpdate` protocol types in `server/protocol.py`
- Implement msgpack framing over a TCP localhost socket
- Write `BridgeClient.gd` Godot autoload: connects to Python subprocess on game start, sends events, receives state updates, emits Godot signals
- Write Godot subprocess launcher: `Main.gd` spawns `python server/main.py` as a child process
- Write smoke test: `test_server_starts_and_accepts_connection`

**Exit criteria:** `pytest tests/` passes. Godot connects to Python. Ping round-trip works. The game still runs normally (no logic moved yet).

---

### Phase 1 — Pure logic + pytest
**Duration:** 1 week  
**Goal:** All pure game logic lives in Python with full test coverage.

Tasks:
- `server/economy.py` — `TeamData` (points, add/spend, sync)
- `server/progression.py` — `LevelSystem` (XP, leveling, attribute points, stat bonuses)
- `server/game_state.py` — `TeamLives` + `GamePhase` state machine
- `server/registry.py` — unified registry for towers, minions, skills (replaces `PLACEABLE_DEFS`, `SkillDefs.ALL`)
- Write pytest suite for all of the above: target 100+ tests
- All tests must pass with zero Godot runtime dependency

**Exit criteria:** `pytest tests/` ≥100 tests passing. No Godot process needed to run them. Developer can open any file in these modules and read/modify it independently.

---

### Phase 2 — Game state authority
**Duration:** 2–3 weeks  
**Goal:** Python server can process all game events and produce correct state updates.

Tasks:
- `server/combat.py` — `GameSync` (health, damage, death, respawn, shield, ammo)
- `server/territory.py` — `LaneControl` (build limits, push/rollback, limit enforcement)
- `server/skills.py` — `SkillTree` (unlock validation, cooldown tracking, passive bonuses)
- `server/skills/fighter.py` — `FighterSkills` (all 9 active abilities)
- `server/skills/supporter.py` — `SupporterSkills` (all active abilities)
- Wire all systems into `GameServer.apply_event()` — single event processing path
- Extend pytest suite: test every game event type end-to-end through the server
- Fix the double-broadcast game_over bug (disappears by construction in `GameStateMachine`)

**Exit criteria:** `pytest tests/` covers all game events. `GameStateMachine` has no double-broadcast. Build limit logic is readable Python.

---

### Phase 3 — Networking layer
**Duration:** 2–3 weeks  
**Goal:** A real multiplayer session works with Python as the authority.

Tasks:
- `server/lobby.py` — `LobbyManager` (player registration, team assignment, role validation, game start orchestration)
- `server/network.py` — asyncio TCP server, client lifecycle, reconnect handling
- Replace all 9 Godot autoloads with relay stubs:
  - Each stub connects to `BridgeClient.gd`
  - Each stub emits the same Godot signals as before
  - Each stub forwards method calls as events to Python
  - All existing scene scripts (`TowerBase`, `MinionBase`, etc.) see no change
- Write integration test: two `FakeGodotClient` instances complete a full lobby flow (connect → register → role → game start)

**Exit criteria:** Full lobby flow works in a real game session. Developer can `print()` every event in `server/lobby.py` and see what is happening. No GDScript reading required for networking bugs.

---

### Phase 4 — Entity sync contracts
**Duration:** 1–2 weeks  
**Goal:** The three inconsistent sync patterns are replaced with one. Host-only bugs are structurally eliminated.

Tasks:
- Audit all entity sync points: towers, minions, skills, projectiles, pickups
- Replace the three sync patterns (event-driven / batch push / directed RPC) with a single `GameServer.broadcast(StateUpdate)` call
- The host-side Godot instance is a registered client — it receives all state updates the same way any other client does
- The `call_remote` asymmetry bug class is eliminated
- Write contract tests: for every entity type, assert that a server-side event produces identical state updates on all registered clients

**Exit criteria:** No entity exists that works on host but not on clients. Contract tests enforce this for every registered entity type.

---

### Phase 5 — Harden and Docker
**Duration:** 1–2 weeks  
**Goal:** Full test coverage. Docker packaging. Clean developer experience.

Tasks:
- Mirror GUT test coverage in pytest for all ported systems
- Write the class of tests that was previously missing: sync contract tests, state machine transition tests, build limit enforcement tests
- `Dockerfile` for the Python server: `python:3.12-slim`, installs `msgpack blinker`, exposes TCP port
- Godot reads `SERVER_HOST` and `SERVER_PORT` env vars — if set, connects to remote; otherwise spawns local subprocess
- `docker-compose.yml` for local multiplayer testing (one Python server container, two Godot instances)
- Documentation: `server/README.md` explaining how to add a tower, minion, or skill

**Exit criteria:** `pytest` suite covers all previous GUT logic coverage plus new contract tests. `docker run flanker-server` starts the server. Two Godot instances can connect to it and play a complete game.

---

## 9. Entity Registry Pattern

The current system requires 5 manual steps to add a tower. The new system requires 1.

### Current (GDScript) — 5 places to touch

```gdscript
# 1. BuildSystem.gd:11-21 — add to PLACEABLE_DEFS
const PLACEABLE_DEFS = {
    "mytower": {"scene": "res://scenes/towers/MyTower.tscn", "cost": 30, ...},
}

# 2. BuildSystem.gd:174-185 — add naming branch
elif item_type == "mytower":
    node.name = "MyTower_%d" % randi()

# 3. Create scenes/towers/MyTower.tscn

# 4. Create scripts/towers/MyTowerAI.gd extends TowerBase

# 5. LobbyManager.gd — add bespoke VFX RPC
@rpc("authority", "call_remote", "reliable")
func spawn_mytower_visuals(pos, team, name): ...
```

Missing step 5 → tower works on host, invisible to clients. No error.

### New (Python) — 1 place to touch

```python
# server/registry.py — add one entry
TOWER_REGISTRY: dict[str, TowerDef] = {
    "cannon":   TowerDef(tower_type="cannon",   cost=25, max_health=900,  attack_range=30.0),
    "mytower":  TowerDef(tower_type="mytower",  cost=30, max_health=500,  attack_range=25.0),
    # done. Sync is handled by the base TowerDef sync contract.
}
```

The `TowerDef` dataclass enforces required fields at import time. The server's `apply_event()` broadcasts `TowerSpawnedUpdate` to all clients automatically — no bespoke RPC needed.

The `.tscn` scene and GDScript rendering script still need to be created, but the sync contract is automatic.

### Same pattern for minions and skills

```python
MINION_REGISTRY: dict[str, MinionDef] = {
    "standard":  MinionDef(...),
    "healer":    MinionDef(...),
    "myminion":  MinionDef(...),  # one line
}

SKILL_REGISTRY: dict[str, SkillDef] = {
    "f_field_medic": SkillDef(role="Fighter", branch="Guardian", ...),
    "my_new_skill":  SkillDef(role="Fighter", branch="DPS", ...),  # one line
}
```

---

## 10. Sync Contract Pattern

The current system has three sync patterns and no enforcement. The new system has one.

### Current — three patterns, no contract

```
Tower placed  → spawn_item_visuals.rpc() [call_remote, skips host]
Minion moved  → sync_minion_states.rpc() [unreliable_ordered, batch]
Skill used    → apply_dash.rpc_id(peer)  [directed, per-ability]
```

### New — one pattern, enforced by the server

```python
# All state changes are Events:
@dataclass
class PlaceTowerEvent:
    tower_type: str
    team: int
    position: tuple[float, float, float]
    placer_peer_id: int

# All state changes produce StateUpdates:
@dataclass
class TowerSpawnedUpdate:
    tower_type: str
    team: int
    position: tuple[float, float, float]
    name: str
    health: float

# Server processes the event and broadcasts to ALL clients:
class GameServer:
    def apply_event(self, sender_id: int, event: Event) -> None:
        match event:
            case PlaceTowerEvent():
                update = self._build.place_tower(event)
                self._broadcast(update)  # all clients, including host
```

Every Godot client (including the host Godot instance) receives the same `TowerSpawnedUpdate`. The relay stub in Godot receives it and emits `LobbyManager.item_spawned` signal as before. All downstream Godot code is unchanged.

---

## 11. Game State Machine

The current win condition is not a state machine. It has a double-broadcast bug.

### Current — two independent broadcast paths

```
TeamLives.lose_life()
  └── _broadcast_game_over.rpc()       ← fires game_over on clients [1st time]
        └── game_over.emit()

LobbyManager._on_team_lives_game_over()
  └── _rpc_game_over.rpc()             ← fires game_over on clients [2nd time]
        └── TeamLives.game_over.emit() ← same signal, again
```

### New — one state machine, one transition point

```python
# server/game_state.py

class GamePhase(Enum):
    LOBBY     = "lobby"
    LOADING   = "loading"
    PLAYING   = "playing"
    GAME_OVER = "game_over"

@dataclass
class GameStateMachine:
    _phase: GamePhase = GamePhase.LOBBY
    _lives: dict[int, int] = field(default_factory=lambda: {0: 20, 1: 20})

    def lose_life(self, team: int) -> list[StateUpdate]:
        if self._phase != GamePhase.PLAYING:
            return []  # guard: can't lose lives outside active game

        self._lives[team] -= 1

        if self._lives[team] <= 0:
            self._phase = GamePhase.GAME_OVER
            # game_over fires exactly once, from exactly one place
            return [GameOverUpdate(winner=1 - team)]

        return [LivesUpdate(team=team, lives=self._lives[team])]

    def transition(self, new_phase: GamePhase) -> None:
        valid_transitions = {
            GamePhase.LOBBY:     [GamePhase.LOADING],
            GamePhase.LOADING:   [GamePhase.PLAYING],
            GamePhase.PLAYING:   [GamePhase.GAME_OVER],
            GamePhase.GAME_OVER: [],
        }
        if new_phase not in valid_transitions[self._phase]:
            raise ValueError(f"Invalid transition: {self._phase} -> {new_phase}")
        self._phase = new_phase
```

Tests:
```python
def test_game_over_fires_exactly_once():
    sm = GameStateMachine()
    sm.transition(GamePhase.LOADING)
    sm.transition(GamePhase.PLAYING)

    updates = sm.lose_life(team=0)  # reduce to 0 lives

    game_over_updates = [u for u in updates if isinstance(u, GameOverUpdate)]
    assert len(game_over_updates) == 1
    assert game_over_updates[0].winner == 1
```

---

## 12. Protocol Design

Communication between Godot and Python uses msgpack over a TCP localhost socket.

### Message format

Every message is a msgpack-encoded dict:

```python
# Event (Godot → Python)
{
    "type":      str,   # event type name, e.g. "place_tower"
    "sender_id": int,   # Godot peer ID of the sender
    "payload":   dict,  # event-specific fields
}

# StateUpdate (Python → Godot)
{
    "type":    str,   # update type name, e.g. "tower_spawned"
    "payload": dict,  # update-specific fields
}
```

### Framing

Messages are length-prefixed: a 4-byte big-endian uint32 header followed by the msgpack body.

```python
# server/protocol.py
import struct
import msgpack

def encode(message: dict) -> bytes:
    body = msgpack.packb(message, use_bin_type=True)
    return struct.pack(">I", len(body)) + body

def decode(data: bytes) -> dict:
    return msgpack.unpackb(data, raw=False)
```

### Event catalog

| Event type | Direction | Payload fields |
|---|---|---|
| `ping` | G→P | `timestamp` |
| `pong` | P→G | `timestamp` |
| `register_player` | G→P | `peer_id`, `name` |
| `set_role` | G→P | `peer_id`, `role`, `team` |
| `start_game` | G→P | `seed` |
| `place_tower` | G→P | `tower_type`, `team`, `position`, `placer_peer_id` |
| `remove_tower` | G→P | `tower_name`, `source_team` |
| `spawn_minion_wave` | G→P | `team`, `lane`, `mtype` |
| `player_died` | G→P | `peer_id`, `killer_peer_id` |
| `player_respawned` | G→P | `peer_id` |
| `use_skill` | G→P | `peer_id`, `slot` |
| `unlock_skill` | G→P | `peer_id`, `node_id` |
| `spend_attribute` | G→P | `peer_id`, `attr` |
| `damage_player` | G→P | `target_id`, `amount`, `source`, `source_team`, `shooter_id` |
| `damage_tower` | G→P | `tower_name`, `amount`, `source_team`, `shooter_id` |

### StateUpdate catalog

| Update type | Direction | Payload fields |
|---|---|---|
| `pong` | P→G | `timestamp` |
| `lobby_state` | P→G | `players` dict |
| `game_started` | P→G | `seed` |
| `tower_spawned` | P→G | `tower_type`, `team`, `position`, `name`, `health` |
| `tower_despawned` | P→G | `name` |
| `tower_damaged` | P→G | `name`, `health` |
| `player_health` | P→G | `peer_id`, `health` |
| `player_died` | P→G | `peer_id`, `respawn_at` |
| `player_respawned` | P→G | `peer_id`, `position`, `health` |
| `team_points` | P→G | `blue`, `red` |
| `team_lives` | P→G | `blue`, `red` |
| `game_over` | P→G | `winner` |
| `skill_state` | P→G | `peer_id`, `unlocked`, `slots`, `cooldowns` |
| `level_state` | P→G | `peer_id`, `level`, `xp`, `unspent` |
| `build_limit` | P→G | `team`, `blue_limit`, `red_limit` |

---

## 13. Testing Strategy

### Philosophy

Tests must guard *contracts*, not *implementations*.

The most important contract in this codebase is: **when a state-changing event occurs on the server, all registered clients receive the correct state update.**

The previous GUT suite did not test this contract. The new pytest suite does.

### Test categories

**Category 1 — Unit tests (pure logic)**  
No network, no Godot, no asyncio. Tests for `economy.py`, `progression.py`, `game_state.py`, `registry.py`, `territory.py`.

```python
def test_team_spend_points_insufficient_funds():
    economy = TeamEconomy()
    economy.add_points(team=0, amount=10)
    result = economy.spend_points(team=0, amount=20)
    assert result is False
    assert economy.get_points(team=0) == 10
```

**Category 2 — Server integration tests (event processing)**  
Uses `GameServer` with `FakeClient` objects. Tests that events produce correct state updates.

```python
def test_tower_placement_broadcasts_to_all_clients():
    server = GameServer()
    client_a, client_b = FakeClient(), FakeClient()
    server.register(peer_id=1, client=client_a, team=0)
    server.register(peer_id=2, client=client_b, team=1)

    server.handle(1, PlaceTowerEvent("cannon", team=0, position=(10, 0, 10)))

    assert client_a.received_type("tower_spawned")
    assert client_b.received_type("tower_spawned")
```

**Category 3 — State machine tests**  
Tests for valid/invalid transitions, guard conditions, single-fire guarantees.

```python
def test_game_over_cannot_fire_twice():
    sm = GameStateMachine(lives_per_team=1)
    sm.transition(GamePhase.PLAYING)
    updates_1 = sm.lose_life(team=0)
    updates_2 = sm.lose_life(team=0)  # already game over
    assert sum(1 for u in updates_1 if isinstance(u, GameOverUpdate)) == 1
    assert sum(1 for u in updates_2 if isinstance(u, GameOverUpdate)) == 0
```

**Category 4 — Registry tests**  
Tests that every registered entity has all required fields and valid values.

```python
def test_all_tower_defs_have_required_fields():
    for name, defn in TOWER_REGISTRY.items():
        assert defn.cost > 0,          f"{name}: cost must be positive"
        assert defn.max_health > 0,    f"{name}: max_health must be positive"
        assert defn.attack_range >= 0, f"{name}: attack_range must be non-negative"
```

### Running tests

```bash
# All tests, no Godot required
pytest server/tests/ -v

# Specific category
pytest server/tests/test_contracts.py -v
pytest server/tests/test_game_state.py -v

# With coverage
pytest server/tests/ --cov=server --cov-report=term-missing
```

---

## 14. Docker / Headless Server Path

The Python server is designed to run standalone from day one. The subprocess model and the Docker model use identical server code.

### Local subprocess (Phase 0 onward)

```gdscript
# BridgeClient.gd
func _ready():
    var server_host = OS.get_environment("SERVER_HOST")
    if server_host == "":
        # launch subprocess
        _process = OS.create_process("python3", ["server/main.py"])
        server_host = "127.0.0.1"
    _connect(server_host, int(OS.get_environment("SERVER_PORT", "7890")))
```

### Dockerfile (Phase 5)

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY server/ ./server/
RUN pip install --no-cache-dir msgpack blinker
EXPOSE 7890
CMD ["python3", "-m", "server.main"]
```

### docker-compose for local multiplayer testing

```yaml
version: "3.9"
services:
  game-server:
    build: .
    ports:
      - "7890:7890"
    environment:
      - LIVES_PER_TEAM=20
      - MAX_PLAYERS=10
```

```bash
# Start the server
docker-compose up

# Connect two Godot clients
SERVER_HOST=127.0.0.1 SERVER_PORT=7890 godot --main-pack flanker.pck
```

---

## 15. Effort Estimate

| Phase | Description | Estimated effort |
|---|---|---|
| Phase 0 | Foundation: server skeleton, protocol, BridgeClient.gd | 1–2 weeks |
| Phase 1 | Pure logic ports + 100+ pytest tests | 1 week |
| Phase 2 | Game state authority (combat, territory, skills) | 2–3 weeks |
| Phase 3 | Networking layer (lobby, relay stubs) | 2–3 weeks |
| Phase 4 | Entity sync contracts (single pattern, host bug fix) | 1–2 weeks |
| Phase 5 | Harden: full pytest suite, Docker packaging | 1–2 weeks |
| **Total** | | **8–13 weeks at side-project pace** |

At each phase boundary the game is fully playable. No phase is a "big bang" — partial migration is safe.

Comparison: a full Panda3D rewrite was estimated at 4–5 months (16–20 weeks) with no playable game until completion. This plan is roughly half the elapsed time with continuous shippability.

---

## 16. Known Bugs Fixed By This Migration

The following bugs documented in `AGENTS.md` are fixed by construction during this migration:

| Bug | Fix mechanism |
|---|---|
| **Double game_over broadcast** (`TeamLives` + `LobbyManager` both broadcast) | `GameStateMachine.lose_life()` is the single authority. Fires `GameOverUpdate` exactly once. |
| **`notify_player_respawned` ignores bonus HP** | `server/combat.py` always computes `PLAYER_MAX_HP + progression.get_bonus_hp(peer_id)` in one place. |
| **`request_destroy_tree` uses `call_remote`** (host bullets never destroy trees on host) | Server pushes `TreeDestroyedUpdate` to all clients including host. `call_remote` asymmetry is eliminated. |
| **`broadcast_player_transform` double-emits on server** | Transform reporting is an event to the Python server, which broadcasts once to all clients. No double-emit possible. |

---

## 17. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Godot relay stubs introduce latency | Low | localhost socket round-trip is <1ms. Imperceptible. |
| asyncio complexity in the Python server | Medium | Start with synchronous (no asyncio) in Phase 0-2; add asyncio only in Phase 3 when needed for multiple concurrent clients. |
| Protocol versioning between Godot and Python | Low initially, grows over time | Include a `protocol_version` field in the handshake. Server rejects mismatched clients with a clear error. |
| Physics/visual scripts depend on autoload state that gets moved | Medium | Relay stubs emit the same signals as the original autoloads. Existing scene scripts are unchanged. Verify with `make test` after each phase. |
| Docker networking for listen-server model | Low | The host player runs Godot + Python server locally. Other players connect to the host's IP. Same as current ENet model — only the port and protocol change. |
| Scope creep during relay stub implementation | Medium | Relay stubs must be thin. If a stub exceeds ~50 lines it is doing too much. Logic belongs in Python. |
