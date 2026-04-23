# Flankers — AGENTS.md

## Project
Godot 4 hybrid FPS/RTS game. Single-player prototype. No editor GUI workflow — all scene/resource edits are done by hand in `.tscn`/`.tres` files or via GDScript runtime generation.

## Commands
```bash
make           # stop + relaunch + show logs (default)
make run       # launch + wait 8s + show logs
make stop      # kill running instance
make logs      # print /tmp/flankers.log
```
Game binary: `/usr/bin/godot` (system install, 4.6.2). No `./godot` symlink in repo.

## Architecture

### Autoload
`LaneData` is a **global singleton** (`project.godot` → `[autoload]`). All lane path data flows through it. Never hardcode lane positions in other scripts — always use `LaneData.get_lane_points(i)` / `get_lane_waypoints(i, team)`.

### Runtime-generated nodes
Most geometry is built at runtime in `_ready()` — no pre-baked meshes:
- `TerrainGenerator.gd` — procedural 200×200 mesh + `HeightMapShape3D` collision, new seed each launch
- `LaneVisualizer.gd` — dirt ribbon meshes along lane curves
- `LampPlacer.gd` — street lamp nodes placed along lane sample points

### Scene tree (Main.tscn)
```
Main (Node, Main.gd)
  World (Node3D)
    Terrain (StaticBody3D, TerrainGenerator.gd)
    LaneVisualizer (Node3D, LaneVisualizer.gd)
    LampPlacer (Node3D, LampPlacer.gd)
    SunLight (DirectionalLight3D)
    WorldEnvironment → assets/night_environment.tres
    BlueBase / RedBase (Node3D → Base.tscn + OmniLight3D)
  FPSPlayer (CharacterBody3D, FPSController.gd)
  RTSCamera (Camera3D, RTSController.gd)
  MinionSpawner (Node, MinionSpawner.gd)
  BuildSystem (Node, BuildSystem.gd)
  HUD (CanvasLayer)
    Crosshair (Control) ← hidden in RTS mode
      ReloadBar (ProgressBar)
```

### Key data flows
- `Main.gd._ready()` passes `$HUD/Crosshair/ReloadBar` to `fps_player.reload_bar`
- Bullets spawned into `get_tree().root.get_child(0)` (scene root) — not parented to shooter
- Minions added via `add_child` — set `minion.set("team", team)` **before** `add_child` so `_ready()` sees the correct value
- `MinionAI._ready()` calls `add_to_group("minions")` and defers visuals via `call_deferred("_init_visuals")`

## GDScript gotchas
- **Always use explicit types** when RHS could be Variant: array reads, ternary, `min()`/`clamp()` return values. `:=` on these causes parse errors.
  ```gdscript
  var x: float = some_array[i]   # correct
  var x := some_array[i]         # breaks if array is untyped Array
  ```
- `var outer: float = 1.0 + expr` — not `var outer := 1.0 + expr` when expr involves division of floats
- Loop variables go out of scope immediately after the loop — capture needed values before exiting
- `is_node_ready()` does not protect `@onready` vars from null — use explicit null checks
- `@onready` on dynamically spawned nodes (e.g. minions via `add_child`) must be accessed via `call_deferred`
- Autoload scripts must `extends Node`

## Terrain
- `HeightMapShape3D` collision scale must be `col_shape.scale = Vector3(step, 1.0, step)` where `step = GRID_SIZE / GRID_STEPS`
- Triangle winding for upward normals (y-up right-handed): `tl→tr→bl` and `tr→br→bl`
- Height application order per vertex: lane flatten → secret path flatten → base zone flatten → plateau lift → peak lift → color

## Bullets
- Physics done manually in `_process` (not `_physics_process`) — no `RigidBody`, no `CollisionShape`
- Collision via `PhysicsRayQueryParameters3D` raycast between prev and current position each frame — avoids tunnelling
- Friendly fire disabled in `Bullet.gd._should_damage()` — single source of truth, not in individual `take_damage()` methods
- Player `shooter_team = -1`, minions pass their `team` int

## Map layout
- Map: 200×200 units. Blue base z=+82, Red base z=-82
- Lanes: Left (`x≈-85`), Mid (straight), Right (`x≈+85`) — cubic Bézier, 40 sample points each
- Mountain/off-lane band: `|x|` 15–80
- Biome split (grass vs desert) is seeded: `seed % 2 == 0` → grass left (`x<0`), else flipped
- Peaks reach height 22 (snow line 13) — physically impassable, jump velocity is 6
- Plateaus max height ~7 — reachable, used as sniper nests

## Adding new input actions
Register in `project.godot` `[input]` section using the existing Object serialization format. Physical keycodes for common keys:
- Shift = `4194325`, Ctrl = `4194326`, Tab = `4194320`, Space = `32`
- Mouse button 1 = LMB, button 2 = RMB
