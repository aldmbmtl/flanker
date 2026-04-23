# Flankers

A single-player hybrid **FPS / RTS** prototype built in Godot 4. You fight on the ground as an FPS soldier while simultaneously commanding waves of minions from a top-down RTS view. Three procedurally generated lanes connect two team bases across a 200×200 unit map.

---

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

## Controls

### FPS Mode (default)

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
| `Esc` | Quit |

### RTS Mode

| Key / Button | Action |
|---|---|
| `W A S D` | Pan camera |
| `Scroll` | Zoom |
| `LMB` | Place tower |
| `Tab` | Switch to FPS mode |

---

## Gameplay

### Overview

- Two teams: **Blue** (south, `z=+82`) and **Red** (north, `z=-82`)
- Three lanes connect the bases: **Left**, **Mid**, **Right**
- Minions spawn in waves every 30 seconds, escalating in count each wave (cap 6 per lane per team)
- Destroy the enemy base to win

### Map Features

Each run is **procedurally seeded** — the map is different every game:

- **Lanes** — flattened dirt paths along cubic Bézier curves, lit by alternating-side hanging street lamps
- **Mountain bands** — rough terrain between `|x|` 15–80 on each side of the map
- **Secret paths** — 6 narrow mountain trails (3 per side) cutting through the off-lane zones, good for flanking
- **Plateaus** — 5 elevated flat areas (~6–7 units high) per run, placed in mountain bands. Good sniper nests with sightlines down onto lanes
- **Peaks** — 5 impassable snow-capped spires (~22 units high) per run. Snow appears above ~13 units. Physically unreachable — jump height is 6 units
- **Biomes** — one side of the map is grass, the other desert, randomly assigned each run based on seed

### Bullets

- All shots are **physics-based projectiles** with realistic gravity drop (`18 m/s²`)
- Player bullets travel at **280 m/s**, minion bullets at **120 m/s**
- Tracer color: player = yellow-white, blue minions = blue, red minions = red
- **Friendly fire is disabled**
- Player has a **1.5s reload delay** — a progress bar appears under the crosshair during reload and hides when ready

### Minion AI

- Minions detect enemies at **12 units**, begin strafing approach
- Stop and fire at **10 units**; each has a unique strafe phase so crowds naturally spread out
- Separation steering prevents minions from stacking

---

## Project Structure

```
flanker/
├── Makefile
├── project.godot          # input actions, autoload, renderer config
├── assets/
│   └── night_environment.tres   # dusk sky, fog, glow settings
├── scenes/
│   ├── Main.tscn          # root scene — all nodes wired here
│   ├── FPSPlayer.tscn
│   ├── Minion.tscn
│   ├── Bullet.tscn
│   ├── Tower.tscn
│   └── Base.tscn
└── scripts/
    ├── Main.gd            # game manager, mode switching, wave announcements
    ├── LaneData.gd        # autoload singleton — Bézier curves, waypoints
    ├── TerrainGenerator.gd  # procedural mesh, collision, biomes, peaks, plateaus
    ├── LaneVisualizer.gd  # dirt ribbon meshes along lanes
    ├── LampPlacer.gd      # hanging street lamps along lane edges
    ├── FPSController.gd   # player movement, shoot, sprint, crouch, zoom, reload
    ├── RTSController.gd   # top-down camera, tower placement
    ├── MinionAI.gd        # pathfinding, strafing, ranged shooting, separation
    ├── MinionSpawner.gd   # wave timer, escalating spawn counts
    ├── Bullet.gd          # projectile physics, raycast collision, friendly fire
    ├── TowerAI.gd         # auto-attack enemy minions in range
    ├── BuildSystem.gd     # RTS tower placement logic
    └── Base.gd            # base HP, damage, win condition
```

---

## Development Notes

- All scene and resource edits are done **by hand in `.tscn` / `.tres` files** — there is no editor GUI workflow
- Geometry is generated at runtime in `_ready()` — no pre-baked meshes in the repo
- `LaneData` autoload is the **single source of truth** for all lane positions — never hardcode lane coordinates elsewhere
- The project was developed against Godot **4.6.2** (system install). No `.NET` / Mono required
