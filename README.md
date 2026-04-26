# Flankers

A hybrid **FPS / RTS** game built in Godot 4. Play as a ground soldier in first-person while commanding waves of minions and placing towers from a top-down RTS view. Supports single-player and multiplayer (up to 10 players via ENet). Three procedurally generated lanes connect two team bases across a 200×200 unit map.

---

## About This Project

A hybrid FPS/RTS game combining ground-based combat with top-down base management. Features:

- Single-player and multiplayer (up to 10 players via ENet)
- Player roles: Fighter (FPS + RTS) or Supporter (RTS-only)
- Dual-mode gameplay: first-person combat and RTS tower placement
- Procedurally generated terrain with diverse features
- Wave-based minion spawning with escalating difficulty
- Physics-based bullet system with realistic gravity
- Ballistic cannonball tower projectiles with splash damage
- Tower defense mechanics with auto-attack AI
- Team-based currency and resource management
- Dynamic lighting with shootable street lamps
- Fog of war shader overlay
- Time-of-day system affecting lamp behavior and visibility

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Linux (X11), Windows 10, macOS 12 | Linux |
| **Godot** | 4.4+ | 4.6.2 |
| **Renderer** | Forward+ (Vulkan) | Forward+ (Vulkan) |
| **GPU** | Vulkan 1.1 capable | Vulkan 1.3+ |
| **VRAM** | 2 GB | 4 GB+ |
| **RAM** | 4 GB | 8 GB |
| **CPU** | Quad-core 2.5 GHz | Any modern multi-core |
| **Display** | 1280×720 | 1920×1080 |

> **Vulkan is required.** The project uses the Forward+ rendering backend. OpenGL / Compatibility mode is not supported.

### Installing Godot

**Arch Linux (recommended)**
```bash
sudo pacman -S godot
```

**Ubuntu / Debian**
```bash
# Godot 4.6+ is not in default apt repos — use Flatpak or download directly
flatpak install flathub org.godotengine.Godot
# or download from https://godotengine.org/download
```

**macOS**
```bash
brew install --cask godot
```

**Windows**
Download the standard (non-Mono) 64-bit installer from [godotengine.org/download](https://godotengine.org/download).

Verify your install:
```bash
godot --version
# expected: 4.x.x.stable...
```

---

## Running the Game

```bash
git clone <repo-url>
cd flanker
make        # stop any running instance, launch, show logs
```

### Makefile targets

| Command | Description |
|---------|-------------|
| `make` | Stop + relaunch + show logs after 8s (default) |
| `make run` | Launch + show logs |
| `make stop` | Kill running instance |
| `make logs` | Print `/tmp/flankers.log` |

Logs are written to `/tmp/flankers.log`. On a successful launch you will see:
```
Terrain: verts=40401 seed=XXXXXXXXX plateaus=5 peaks=5 secret_paths=6 grass_left=true
```

### Running without Make

```bash
DISPLAY=:0 godot --path /path/to/flanker > /tmp/flankers.log 2>&1 &
```

---

## Downloading Pre-built Releases

Pre-built binaries are available from the `build/` folder in the repository.

### Downloading

1. Download the appropriate zip for your OS:
   - **Linux**: [flanker-linux.zip](./build/flanker-linux.zip)
   - **Windows**: [flanker-windows.zip](./build/flanker-windows.zip)

2. Extract the zip to a folder of your choice.

### Running the Game

**Linux**

Open a terminal in the extracted folder and run:
```bash
./flanker-linux
```

Or double-click the file in your file manager. If prompted, mark as executable.

**Windows**

Double-click `flanker-windows.exe` to launch the game.

> **Note**: Vulkan 1.1+ is required. Ensure your GPU drivers are up to date.

---

## Controls

### FPS Mode (Fighter role only)

| Key / Button | Action |
|---|---|
| `W A S D` | Move |
| Mouse | Look |
| `LMB` | Shoot |
| `RMB` (hold) | Zoom / ADS |
| `Space` | Jump |
| `Shift` (hold) | Sprint |
| `Ctrl` (hold) | Crouch |
| `Tab` | Switch to RTS mode |
| `Esc` | Pause menu |

### RTS Mode

| Key / Button | Action |
|---|---|
| `W A S D` | Pan camera |
| `Scroll` | Zoom |
| `LMB` | Place tower |
| `Tab` | Switch to FPS mode (Fighter only) |

> **Supporter role** players start in RTS mode and cannot switch to FPS. `Tab` is locked for both roles — Fighters stay FPS-only unless they tab switch; Supporters are RTS-only permanently.

---

## Gameplay

### Overview

- Two teams: **Blue** (south, `z=+82`) and **Red** (north, `z=-82`)
- Three lanes connect the bases: **Left**, **Mid**, **Right**
- Minions spawn in waves every 30 seconds, escalating in count each wave (cap 6 per lane per team)
- Destroy the enemy base to win

### Player Roles

At game start, each player picks a role:

- **Fighter** — spawns as an FPS soldier. Can switch between first-person combat and RTS tower placement with `Tab`
- **Supporter** — RTS-only. No FPS body. Permanently in top-down view, placing towers and managing resources

Only **one Supporter per team** is allowed. The server enforces this — if two players try to claim Supporter on the same team, the second is rejected and must pick Fighter.

### Multiplayer

From the **Start Menu**, choose Host or Join:

- **Host** — opens a lobby on the specified port (default 8910). Other players join by IP
- **Join** — connects to a host by IP and port, enters the lobby
- **Local Play** — single-player, skips networking entirely

In the **Lobby**, players are auto-assigned to teams (balanced). Everyone hits Ready; the host starts the game. The server broadcasts a seed so all clients generate the identical map.

Up to **10 players** supported. Server is authoritative for shot damage, minion state, tower placement, and team points. Respawn timers escalate with each death (`5s base + 5s per prior death`).

### Map Features

Each run is **procedurally seeded** — the map is different every game:

- **Lanes** — flattened dirt paths along cubic Bézier curves, lit by alternating-side hanging street lamps, lined with wooden fence panels
- **Mountain bands** — rough terrain between `|x|` 15–80 on each side of the map
- **Secret paths** — 6 narrow mountain trails (3 per side) cutting through the off-lane zones, good for flanking
- **Plateaus** — 5 elevated flat areas (~6–7 units high) per run, placed in mountain bands. Good sniper nests with sightlines down onto lanes
- **Peaks** — 5 impassable snow-capped spires (~22 units high) per run. Snow appears above ~13 units. Physically unreachable — jump height is 6 units
- **Biomes** — one side of the map is grass, the other desert, randomly assigned each run based on seed
- **Cover objects** — walls and crates scattered across 20 random clearings in off-lane areas

### Bullets

- All shots are **physics-based projectiles** with realistic gravity drop (`18 m/s²`)
- Player bullets travel at **280 m/s**, minion bullets at **120 m/s**
- Tracer color: player = yellow-white, blue minions = blue, red minions = red
- **Friendly fire is disabled**
- Player has a **1.5s reload delay** — a progress bar appears under the crosshair during reload and hides when ready

### Cannonball Towers

Towers fire **ballistic cannonballs** at enemy minions:

- Computed arc: x/z constant velocity, y component overcomes gravity over **2.5 second flight time**
- **Direct hit damage** applies to the first collider struck
- **Splash damage** — 50% of direct damage, applied to all targets within **3 units** of impact
- Friendly fire disabled via the same `_should_damage()` pattern as bullets
- Impact spawns a GPU particle burst

### Minion AI

- Minions detect enemies at **12 units**, begin strafing approach
- Stop and fire at **10 units**; each has a unique strafe phase so crowds naturally spread out
- Separation steering prevents minions from stacking
- In darkness (no nearby lit lamp), detect range drops to **5 units** and shots have a **60% miss chance**
- Shoot out a lamp while being chased — minions lose track and bullets go wide

### Street Lamps and Darkness

Lanes are lined with hanging street lamps procedurally placed along each curve.

- **Time-of-day aware** — lamps are on at sunrise, dusk, and night. At noon they stay off (daylight is sufficient)
- **Shootable** — aim at the bulb and shoot to destroy the light. Only the bulb has a hitbox; shooting the pole does nothing
- **Flicker on shoot-out** — the bulb flickers rapidly before going dark, simulating the filament dying
- **Auto-respawn** — shot-out lamps flicker back on after **15 seconds**
- **Tactical darkness** — dark zones reduce minion detection range and accuracy. Use them to break pursuit or set up an ambush

### Fence and Torches

Both edges of every lane are lined with procedural wooden fence panels:

- **20% random gaps** — natural breaks in the fence line
- **15% of panels** randomly sprout a torch: `OmniLight3D` + GPU particle flame effect
- Torches are spaced at least **12 units** apart (no torch clusters)
- Fence panels are `StaticBody3D` on collision layer 2 — block movement but not bullets

### Cover Objects

`WallPlacer` scatters cover across 20 randomly placed clearings in the mountain/off-lane areas:

- Mix of **walls** (kenney_fantasy-town-kit) and **crates** (kenney_blaster-kit)
- Clearings avoid lane edges, secret paths, and base zones
- Each piece has a `StaticBody3D` collision shape on collision layer 2

### Fog of War

A full-map shader overlay at `y=25` clears visibility circles around allied units:

- Up to **64 visibility sources**: player position, allied minion positions, allied tower positions
- Each source has a configurable radius — player sees farther than minions
- Updated every frame via `FogOverlay.update_sources(...)`

### Enemy Health Bars

- Health bars appear above enemies when **zoomed in** (`RMB` hold)
- Only visible within **75 units**
- Occluded by terrain and geometry — no health bars through hills or walls

### Respawn

On death, the player switches to RTS camera and waits:

- Base respawn time: **5 seconds**
- Each subsequent death adds **5 more seconds** (escalating penalty)
- In multiplayer, death counts are tracked server-side in `LobbyManager.player_death_counts`

---

## Project Structure

```
flanker/
├── Makefile
├── project.godot          # input actions, autoload singletons, renderer config
├── assets/
│   ├── day_environment.tres
│   ├── dusk_environment.tres
│   ├── night_environment.tres
│   ├── FogOfWar.gdshader
│   ├── ui_theme.tres
│   ├── weapons/           # weapon preset .tres files
│   ├── kenney_blocky-characters/  # GLB character models
│   ├── kenney_fantasy-town-kit/   # wall, fence GLB models
│   ├── kenney_blaster-kit/        # crate GLB models
│   ├── kenney_pirate-kit/         # 3D models (optional)
│   ├── kenney_ui-audio/           # UI sound effects
│   └── tower-defense-kit/         # tower models (optional)
├── scenes/
│   ├── Main.tscn          # root game scene — all nodes wired here
│   ├── StartMenu.tscn     # host/join/local-play UI with cinematic camera
│   ├── Lobby.tscn         # pre-game lobby with team lists and ready checks
│   ├── LoadingScreen.tscn # progress bar overlay during scene setup
│   ├── RoleSelectDialog.tscn  # Fighter / Supporter role picker
│   ├── PauseMenu.tscn     # Resume / Leave game overlay
│   ├── FPSPlayer.tscn
│   ├── RemotePlayer.tscn  # ghost representation of a remote peer
│   ├── Minion.tscn
│   ├── Bullet.tscn
│   ├── Cannonball.tscn    # ballistic tower projectile
│   ├── Tower.tscn
│   ├── Base.tscn
│   └── WeaponPickup.tscn
└── scripts/
    ├── Main.gd              # game manager, mode switching, wave announcements
    ├── LaneData.gd          # autoload — Bézier curves, waypoints
    ├── TeamData.gd          # autoload — team points tracking
    ├── NetworkManager.gd    # autoload — ENet peer management
    ├── LobbyManager.gd      # autoload — lobby state, RPCs, game start orchestration
    ├── GameSync.gd          # autoload — in-game player state (health, teams, respawn)
    ├── TerrainGenerator.gd  # procedural mesh, collision, biomes, peaks, plateaus
    ├── LaneVisualizer.gd    # dirt ribbon meshes along lanes
    ├── LampPlacer.gd        # hanging street lamps along lane edges
    ├── ShootableLamp.gd     # per-lamp flicker + restore logic
    ├── FencePlacer.gd       # fence panels + torches along lane edges
    ├── WallPlacer.gd        # walls + crates in random off-lane clearings
    ├── TreePlacer.gd        # procedural trees along lane edges
    ├── FogOverlay.gd        # fog of war mesh + shader source management
    ├── MenuCamera.gd        # cinematic orbiting camera for start menu
    ├── FPSController.gd     # player movement, shoot, sprint, crouch, zoom, reload
    ├── RTSController.gd     # top-down camera, tower placement
    ├── RemotePlayerManager.gd  # creates/removes RemotePlayerGhost nodes
    ├── RemotePlayerGhost.gd    # lerp position/rotation, drive walk/idle animation
    ├── MinionAI.gd          # pathfinding, strafing, ranged shooting, separation
    ├── MinionSpawner.gd     # wave timer, escalating spawn counts
    ├── Bullet.gd            # projectile physics, raycast collision, friendly fire
    ├── Cannonball.gd        # ballistic arc, splash damage, impact particles
    ├── TowerAI.gd           # auto-attack enemy minions in range
    ├── Tower.gd             # tower setup, state machine
    ├── BuildSystem.gd       # RTS tower placement logic
    ├── Base.gd              # base HP, damage, win condition
    ├── WeaponData.gd        # weapon definitions for pickups
    ├── WeaponPickup.gd      # weapon pickup interaction
    ├── EntityHUD.gd         # per-entity health bars (zoom + LOS gated)
    ├── RoleSelectDialog.gd  # Fighter / Supporter role picker UI
    ├── Lobby.gd             # lobby screen UI and ready/start logic
    ├── LoadingScreen.gd     # progress bar overlay
    ├── LoadingState.gd      # global loading step reporter
    ├── PauseMenu.gd         # resume / leave game
    └── Minimap.gd           # RTS minimap rendering
```

## Development Notes

- All scene and resource edits are done **by hand in `.tscn` / `.tres` files** — there is no editor GUI workflow
- Geometry is generated at runtime in `_ready()` — no pre-baked meshes in the repo
- `LaneData` autoload is the **single source of truth** for all lane positions — never hardcode lane coordinates elsewhere
- **Multiplayer authority**: server is authoritative for shot damage, minion state, tower placement, and team points. Clients send requests; server validates and broadcasts results
- **RPC sender ID**: `multiplayer.get_remote_sender_id()` returns `0` when the server calls an RPC on itself. Use the `_sender_id()` helper in `LobbyManager` (maps `0` → `1`)
- **Seed sync**: `LobbyManager.start_game` broadcasts a non-zero seed to all peers before scene change. Never allow seed=0 — `TerrainGenerator` falls back to `randi()` causing client/server map divergence
- The project was developed against Godot **4.6.2** (system install). No `.NET` / Mono required
- No external dependencies beyond Godot 4.6.2 engine
