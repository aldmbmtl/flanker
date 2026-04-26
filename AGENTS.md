# Flankers — AGENTS.md

## Project
Godot 4 hybrid FPS/RTS game. Single-player and multiplayer (up to 10 players via ENet). No editor GUI workflow — all scene/resource edits are done by hand in `.tscn`/`.tres` files or via GDScript runtime generation.

## Commands
```bash
make           # stop + relaunch + show logs (default)
make run       # launch + wait 8s + show logs
make stop      # kill running instance
make logs      # print /tmp/flankers.log
make clean     # delete all *.uid files recursively under scripts/
```
Game binary: `/usr/bin/godot` (system install, 4.6.2). No `./godot` or `bin/godot` symlink in repo.

## Architecture

### Autoload
- `LaneData` — global singleton, all lane path data. Use `LaneData.get_lane_points(i)` / `get_lane_waypoints(i, team)`
- `TeamData` — global singleton, team points/currency tracking. Use `TeamData.get_points(team)` / `TeamData.add_points(team, amount)` / `TeamData.spend_points(team, amount)`
- `NetworkManager` — ENet multiplayer peer management. `start_host(port)` / `join_game(address, port)` / `close_connection()`. Emits `peer_connected`, `peer_disconnected`, `connected_to_server`, `connection_failed`, `server_disconnected`
- `LobbyManager` — lobby state, player registry, role claims, game start orchestration. Handles bullet/minion/tower spawn sync RPCs and player transform broadcast. `start_game(path)` broadcasts seed via `notify_game_seed.rpc` then loads scene on all peers
- `GameSync` — in-game state: player healths, teams, spawn positions, respawn countdowns. `damage_player(peer_id, amount, source_team)` handles death + escalating respawn timer

### Runtime-generated nodes
Most geometry is built at runtime in `_ready()` — no pre-baked meshes:
- `TerrainGenerator.gd` — procedural 200×200 mesh + `HeightMapShape3D` collision, new seed each launch
- `LaneVisualizer.gd` — dirt ribbon meshes along lane curves
- `LampPlacer.gd` — street lamp nodes placed along lane sample points. Each lamp is a `StaticBody3D` with a `SphereShape3D` hitbox on the bulb only. Exposes `lamp_scripts: Array` for darkness queries
- `ShootableLamp.gd` — script node attached to each lamp. Holds refs to `OmniLight3D`, bulb `MeshInstance3D`, bulb `StandardMaterial3D`. `shoot_out()` triggers flicker-then-dark; auto-restores after 15s via `_process`
- `FencePlacer.gd` — fence panels placed along both edges of each lane at regular spacing. Random gaps (20% chance). Each panel is a `StaticBody3D` on collision layer 2. Randomly spawns torches (15% chance, min 12 units apart) with `OmniLight3D` + `GPUParticles3D` flame effect
- `WallPlacer.gd` — scatter walls and crates in 20 random off-lane clearings. Avoids lane edges, secret paths, and base zones. Uses kenney_fantasy-town-kit walls + kenney_blaster-kit crates. Emits `done` signal when finished (awaited by loading screen)
- `TreePlacer.gd` — procedural trees along lane edges (11275 trees per run). Supports `menu_density` override for lighter start-menu background
- `Tower.gd` — cannon tower; thin subclass of `TowerBase`. Only overrides `_do_attack()` to fire a `Cannonball`

### TowerBase (`scripts/towers/TowerBase.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`TowerBase` is the single base class for every tower in the game. `extends StaticBody3D`. All multiplayer plumbing, collision, targeting, hit-flash, and death/despawn are handled here.

#### Lifecycle
1. `BuildSystem.spawn_item_local()` instantiates the `.tscn`, calls `add_child`, sets `node.global_position`, then calls `node.setup(team)`.
2. `setup(team)` sets `_health = max_health`, calls `_build_visuals()`, caches the turret node (if `turret_node_name != ""`), and builds the detection `Area3D` (if `attack_range > 0.0`). Adds node to group `"towers"`.
3. `_process(delta)` drives the attack timer. On expiry: finds nearest enemy via `_find_target()`, rotates turret, calls `_do_attack(target)`, resets timer.

#### @export configuration (set in .tscn, never in code)
| Export | Type | Default | Purpose |
|---|---|---|---|
| `tower_type` | `String` | `""` | Must match `BuildSystem.PLACEABLE_DEFS` key. Used in `tower_despawned` signal. |
| `max_health` | `float` | `500.0` | Starting and maximum HP. |
| `attack_range` | `float` | `30.0` | Detection sphere radius. Set `0.0` for passive towers — no `Area3D` is built. |
| `attack_interval` | `float` | `3.0` | Seconds between attack attempts. |
| `projectile_scene` | `PackedScene` | `null` | Spawned by default `_do_attack()`. Set `null` and override `_do_attack()` for non-projectile attacks. |
| `turret_node_name` | `String` | `""` | Name of child node to `look_at` target each frame. Found via `find_child()` (any depth). `""` = no rotation. |
| `model_scene` | `PackedScene` | `null` | GLB or subscene to instantiate as the tower model. `null` = override `_build_visuals()`. |
| `model_scale` | `Vector3` | `ONE` | Scale applied to the instantiated model root. |
| `model_offset` | `Vector3` | `ZERO` | Local position offset of the model root. |
| `fire_point_fallback_height` | `float` | `2.0` | Y offset used as fire origin when no `"FirePoint"` child exists. |
| `xp_on_death` | `int` | `0` | XP awarded to killer on death. Falls back to `LevelSystem.XP_TOWER` when `0`. |

#### Runtime state (not exported, set internally)
- `team: int` — set by `BuildSystem` after `add_child`, before `setup()`.
- `_health`, `_dead`, `_attack_timer` — internal, do not read from outside.
- `_area: Area3D` — built by `_build_detection_area()`. `null` for passive towers.
- `_mesh_inst: MeshInstance3D` — first mesh in the model subtree; used for hit-flash.
- `_turret_node: Node3D` — cached ref found by `turret_node_name`.
- `_killer_peer_id: int` — tracks last attacker for XP award.
- `_hit_overlay_mat: StandardMaterial3D` — prepared at visual build time; applied only during `_flash_hit()` then cleared back to `null`.

#### Overridable hooks
```gdscript
# Override to build procedural geometry when model_scene is null.
# Default: instantiates model_scene, applies model_scale/model_offset,
#          caches first MeshInstance3D for hit-flash.
func _build_visuals() -> void

# Override for non-projectile attacks (raycast, pulse, slow, heal, etc.).
# Default: instantiates projectile_scene, sets shooter_team, positions at
#          get_fire_position(), adds to scene root (get_tree().root.get_child(0)).
func _do_attack(target: Node3D) -> void
```

#### Fire origin
`get_fire_position() -> Vector3` — looks for a child node named `"FirePoint"` (any depth). If found, returns its `global_position`. Otherwise returns `global_position + Vector3(0, fire_point_fallback_height, 0)`. Place a `Marker3D` named `"FirePoint"` at the barrel tip in the `.tscn` for accurate projectile spawn.

#### Targeting
- `_find_target()` — iterates `_area.get_overlapping_bodies()`, skips bodies without `take_damage`, skips same-team and team-unknown bodies, skips bodies without line-of-sight. Returns nearest valid enemy.
- `_get_body_team(body)` — duck-types team: checks `player_team` first (FPS players), then `team` (minions/towers).
- `_has_line_of_sight(target)` — raycast from `global_position + (0,2,0)` to `target.global_position + (0,0.8,0)`. Ignores tree trunks (bodies with meta `"tree_trunk_height"`). Up to 4 retries excluding each ignored collider.

#### Damage / death
- `take_damage(amount, source, source_team, shooter_peer_id)` — server-authoritative. Returns immediately if: already dead; `source_team == team` (friendly fire); client in multiplayer. Calls `_flash_hit()`, then `_die()` at 0 HP.
- `_die()` — awards XP via `LevelSystem.award_xp`. In multiplayer: calls `LobbyManager.despawn_tower.rpc(name)` (server broadcasts to all peers). In singleplayer: `queue_free()` then emits `LobbyManager.tower_despawned` signal manually with `(tower_type, team, name)`.

#### Hit flash
`_flash_hit()` — applies `_hit_overlay_mat` (red emissive, alpha 0.8) via `set_surface_override_material` on all surfaces of `_mesh_inst`, tweens `emission_energy_multiplier` from 3.0 → 0.0 over 0.3 s, then sets override back to `null` so the base GLB material is restored. **Critical**: never permanently assign a surface override material at init — this makes GLB models invisible. The overlay is only active during the flash tween.

#### Adding a new tower — checklist
1. Create `scenes/towers/MyTower.tscn` inheriting `StaticBody3D`. Attach a script extending `TowerBase`.
2. Set all `@export` vars in the `.tscn` Inspector (or `.tscn` file directly): `tower_type`, `max_health`, `attack_range`, `attack_interval`, and either `model_scene` or override `_build_visuals()`.
3. If auto-attacking with a projectile: set `projectile_scene`. The projectile must accept `shooter_team` as a property.
4. If custom attack (raycast, pulse, etc.): leave `projectile_scene = null` and override `_do_attack(target)`.
5. If passive (barrier, heal zone): set `attack_range = 0.0` — no `Area3D` is built.
6. Register in `BuildSystem.PLACEABLE_DEFS` with `"is_tower": true`.
7. Add `tower_type` key to the name-generation `elif` block in `BuildSystem.spawn_item_local()`.
8. **Do not add `Area3D` to the `.tscn`** — `TowerBase` builds it entirely in code.

- `FogOverlay.gd` — full-map `MeshInstance3D` at y=25 driven by `FogOfWar.gdshader`. `update_sources(player_pos, player_radius, minion_positions, minion_radius, tower_positions, tower_radius)` pushes up to 64 visibility sources as `vec4` array to the shader

### Scene tree (Main.tscn)
```
Main (Node, Main.gd)
  World (Node3D)
    Terrain (StaticBody3D, TerrainGenerator.gd)
    LaneVisualizer (Node3D, LaneVisualizer.gd)
    LampPlacer (Node3D, LampPlacer.gd)
    FencePlacer (Node3D, FencePlacer.gd)
    WallPlacer (Node3D, WallPlacer.gd)
    TreePlacer (Node3D, TreePlacer.gd)
    FogOverlay (MeshInstance3D, FogOverlay.gd)
    SunLight (DirectionalLight3D)
    WorldEnvironment → assets/{day,dusk,night}_environment.tres
    BlueBase / RedBase (Node3D → Base.tscn + OmniLight3D)
  FPSPlayer_<peer_id> (CharacterBody3D, FPSController.gd)  ← spawned at runtime
  RTSCamera (Camera3D, RTSController.gd)
  MinionSpawner (Node, MinionSpawner.gd)
  BuildSystem (Node, BuildSystem.gd)
  RemotePlayerManager (Node, RemotePlayerManager.gd)  ← multiplayer only
  HUD (CanvasLayer)
    Crosshair (Control) ← hidden in RTS mode / Supporter role
      ReloadBar (ProgressBar)
    PointsLabel (Label) ← team points display
    HealthBar (ProgressBar)
    StaminaBar (ProgressBar)
    AmmoLabel (Label)
    ReloadPrompt (Label)
    WeaponLabel (Label)
    RespawnLabel (Label)
    ModeLabel (Label)
    WaveInfoLabel (Label)
    WaveAnnounceLabel (Label)
    GameOverLabel (Label)
    HUDOverlay (Control)
      EntityHUD (Node, EntityHUD.gd)
    Minimap (Control, Minimap.gd)
    PauseMenu (Control, PauseMenu.gd)  ← hidden until Esc
  AudioModeSwitch (AudioStreamPlayer)
  AudioWave (AudioStreamPlayer)
  AudioRespawn (AudioStreamPlayer)
```

Additional scenes not in Main.tscn:
- `StartMenu.tscn` — host/join/local-play UI with cinematic orbiting camera (`MenuCamera.gd`) and a live menu-world terrain background. Shown before game loads.
- `Lobby.tscn` — pre-game lobby listing players by team with ready/start controls (`Lobby.gd`)
- `LoadingScreen.tscn` — progress bar overlay shown during scene setup (`LoadingScreen.gd`). Reports steps via `LoadingState.report()`
- `RoleSelectDialog.tscn` — in-game role picker (Fighter / Supporter). One Supporter slot per team; server validates and rejects duplicates (`RoleSelectDialog.gd`)
- `RemotePlayer.tscn` — ghost representation of a remote peer. Lerps to server-broadcast position/rotation, drives walk/idle animation from movement speed (`RemotePlayerGhost.gd`)
- `PauseMenu.tscn` — Resume / Leave game buttons (`PauseMenu.gd`)

### Key data flows
- `Main.gd._ready()` detects `NetworkManager._peer != null` → chooses single-player or multiplayer path
- `Main.gd._on_start_game()` awaits `$World/TreePlacer.done` and `$World/WallPlacer.done` before proceeding, driving the loading screen progress bar
- Multiplayer game start: `LobbyManager.start_game(path)` → broadcasts `notify_game_seed.rpc` (sets `GameSync.game_seed` + calls `LaneData.regenerate_for_new_game()` on all peers) → `load_game_scene.rpc` → all peers change scene
- `Main.gd._setup_hud_for_player()` passes `$HUD/Crosshair/ReloadBar`, `$HUD/HealthBar`, `$HUD/StaminaBar`, `weapon_label`, `ammo_label`, `reload_prompt` to `fps_player`
- Bullets spawned into `get_tree().root.get_child(0)` (scene root) — not parented to shooter
- Multiplayer shot path: `FPSController` → `LobbyManager.validate_shot.rpc_id(1, ...)` with `hit_info` dict → server applies damage, calls `apply_player_damage.rpc` on target, calls `spawn_bullet_visuals.rpc` on all clients
- Minions added via `add_child` — set `minion.set("team", team)` **before** `add_child` so `_ready()` sees the correct value
- `MinionAI._ready()` calls `add_to_group("minions")` and defers visuals via `call_deferred("_init_visuals")`
- Remote player positions: `FPSController` → `LobbyManager.report_player_transform.rpc_id(1, ...)` → server calls `broadcast_player_transform.rpc` → `GameSync.remote_player_updated` signal → `RemotePlayerManager` creates/updates `RemotePlayerGhost` nodes
- Avatar chars: `Main._pick_minion_characters()` → `LobbyManager.report_avatar_char.rpc_id(1, char)` → server updates `players` dict and `sync_lobby_state.rpc` → `RemotePlayerGhost._try_load_avatar()` reads on `lobby_updated`
- RPC sender ID: `get_remote_sender_id()` returns 0 when the server calls an RPC on itself. Always use `_sender_id()` helper in `LobbyManager` which maps 0 → 1 (server peer id)

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
- **RPC sender ID on server**: `multiplayer.get_remote_sender_id()` returns 0 when the server invokes an RPC locally. Use the `_sender_id()` pattern:
  ```gdscript
  func _sender_id() -> int:
      var id := multiplayer.get_remote_sender_id()
      return id if id != 0 else 1
  ```
- **Role slots**: only one Supporter per team. Server validates `set_role_ingame` and rejects with `_notify_role_rejected.rpc_id(id, ...)` if slot is taken
- **Seed guard**: `LobbyManager.start_game` never sends seed=0 (TerrainGenerator falls back to random seed, causing client/server divergence)

## Terrain
- `HeightMapShape3D` collision scale must be `col_shape.scale = Vector3(step, 1.0, step)` where `step = GRID_SIZE / GRID_STEPS`
- Triangle winding for upward normals (y-up right-handed): `tl→tr→bl` and `tr→br→bl`
- Height application order per vertex: lane flatten → secret path flatten → base zone flatten → plateau lift → peak lift → color

## ProjectileBase (`scripts/projectiles/ProjectileBase.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`ProjectileBase` is the single base class for every projectile in the game. `class_name ProjectileBase`, `extends Node3D`. All per-frame movement, gravity, raycast collision, lifetime expiry, friendly-fire guard, and splash damage are handled here.

### File layout
```
scripts/projectiles/ProjectileBase.gd   ← base class
scripts/projectiles/Bullet.gd           ← player + minion hitscan tracer
scripts/projectiles/Cannonball.gd       ← cannon tower ballistic shell
scripts/projectiles/MortarShell.gd      ← mortar tower ballistic shell
scripts/projectiles/Rocket.gd           ← player rocket launcher projectile
scripts/projectiles/Missile.gd          ← launcher tower guided missile

scenes/projectiles/Bullet.tscn
scenes/projectiles/Cannonball.tscn
scenes/projectiles/MortarShell.tscn
scenes/projectiles/Rocket.tscn
scenes/projectiles/Missile.tscn
```

### Core loop (`_process`)
Each frame, in order:
1. Increment `_age`. If `>= max_lifetime` → call `_on_expire()` then `queue_free()`.
2. If `gravity != 0.0` → subtract `gravity * delta` from `velocity.y`.
3. Raycast from `prev_pos` → `new_pos` via `PhysicsRayQueryParameters3D`. No `RigidBody`, no `CollisionShape` — avoids tunnelling at high speed.
4. Hit → call `_on_hit(pos, collider)` then `queue_free()`.
5. No hit → set `global_position = new_pos`, call `_after_move()`.

### Configuration vars (set before `add_child`)
| Var | Type | Default | Purpose |
|---|---|---|---|
| `damage` | `float` | `10.0` | Direct-hit damage amount. |
| `source` | `String` | `"unknown"` | Damage source tag passed to `take_damage`. |
| `shooter_team` | `int` | `-1` | `-1` = player (no friendly fire against other `-1`). Tower/minion projectiles pass their `team` int. |
| `shooter_peer_id` | `int` | `-1` | Set for player-fired projectiles. `-1` for tower/minion projectiles. |
| `max_lifetime` | `float` | `3.0` | Seconds until `_on_expire()` + `queue_free()`. |
| `gravity` | `float` | `18.0` | m/s² subtracted from `velocity.y` each frame. Set `0.0` to disable (rockets, missiles). |
| `velocity` | `Vector3` | `ZERO` | Set by caller before `add_child`, or computed in subclass `_ready()`. |

### Overridable hooks
```gdscript
# Called when raycast hits. Default: CombatUtils.should_damage + take_damage on collider.
# Override for ghost peers, splash, VFX, tree clearing, etc.
func _on_hit(pos: Vector3, collider: Object) -> void

# Called each frame after global_position is updated (no hit this frame).
# Override for: orientation toward velocity, trail timers, acceleration, light flicker.
func _after_move() -> void

# Called just before queue_free() on max_lifetime expiry.
# Override to detach persistent trails or spawn timeout VFX.
func _on_expire() -> void
```

### Splash helper
```gdscript
_apply_splash(pos, radius, splash_dmg, splash_source, exclude_body = null)
```
Sphere-overlap at `pos` with `radius`. Calls `CombatUtils.should_damage` + `take_damage` on every body in range. Pass the direct-hit collider as `exclude_body` to avoid double-damaging it.

### Concrete projectiles

| Class | Scene | Fired by | `gravity` | Movement | Splash |
|---|---|---|---|---|---|
| `Bullet` | `Bullet.tscn` | `FPSController`, `MinionAI`, `LobbyManager` (visual) | `18.0` | `velocity` set by caller | None |
| `Cannonball` | `Cannonball.tscn` | `TowerAI` (cannon tower) | `18.0` | Ballistic arc, `FLIGHT_TIME=2.5s`, `target_pos` set before `add_child` | radius 3, 50% damage |
| `MortarShell` | `MortarShell.tscn` | `MortarTowerAI` | `18.0` | Ballistic arc, `FLIGHT_TIME=3.5s`, `target_pos` set before `add_child` | radius 6, 50% damage |
| `Rocket` | `Rocket.tscn` | `FPSController`, `LobbyManager` | `0.0` | Accelerates from 0.1 → 49 m/s (`ACCELERATION=120`). `velocity` set to `dir * 0.1` by caller. | radius 8, flat 80 dmg |
| `Missile` | `Missile.tscn` | `LauncherTower` via `LauncherDefs` | `0.0` (own `_process`) | Ballistic arc, flight time from `LauncherDefs`. Uses `configure()` pattern. | radius/damage from `LauncherDefs` |

#### Bullet — special rules
- Ghost hitbox path: if collider is a `StaticBody3D` with `ghost_peer_id` meta, damage is routed via `GameSync.damage_player` + `LobbyManager.apply_player_damage.rpc` — **not** via `take_damage()`. Server-authoritative only.
- Emits `hit_something(hit_type: String)` signal on every hit (`"player"`, `"tower"`, `"minion"`, `"building"`).
- Tracer color set in `_ready()` via `CombatUtils.make_team_tracer_material(shooter_team)`.
- `shooter_team = -1` for player bullets; minions pass their `team` int.

#### Cannonball — special rules
- `target_pos` must be set **before** `add_child` — arc computed in `_ready()` from `global_position` (valid only after `add_child`).
- Tree hit: spawns wood/leaf VFX, destroys tree, no combat damage.
- Cannonball node carries an `OmniLight3D` child; `_after_move` flickers it every 0.05 s.

#### MortarShell — special rules
- `target_pos` must be set before `add_child`. Arc computed same as Cannonball.
- Builds its own sphere mesh in `_ready()` — no mesh in `.tscn`.
- Smoke puff spawned every `0.06 s` in `_after_move`. Shell orients nose toward velocity.

#### Rocket — special rules
- `velocity` set to `dir * 0.1` (near-zero) by caller; `_after_move` accelerates along current direction each frame.
- Persistent fire + smoke trails added as children in `_ready()`; detached and left to expire on `_on_hit` / `_on_expire`.
- Tree hit: explosion VFX + tree clear, returns early (no combat damage to the tree).
- Destroys trees within `TREE_DESTROY_RADIUS = 8.0` on any impact.

#### Missile — special rules
- Uses `configure(def, team, fire_pos, target_pos, launcher_type)` called **before** `add_child`. Never set vars directly.
- `fire_pos` is passed explicitly because `global_position` is not valid before `add_child`.
- Overrides `_process` entirely — terrain-only raycast (`collision_mask = 1`), overshot detection (`prev_pos.y > target_pos.y and new_pos.y <= target_pos.y`), server-only blast damage via `_apply_blast_damage`.
- All stats (`blast_radius`, `blast_damage`, `flight_time`) come from `LauncherDefs.get_def(launcher_type)`.
- Screen shake on impact: attenuates by distance, full within 20 units, none beyond 80.

### Spawning pattern (all projectiles except Missile)
```gdscript
var proj: ProjectileBase = Scene.instantiate()
proj.damage       = ...
proj.shooter_team = team
proj.velocity     = dir * speed   # or set target_pos for ballistic types
get_tree().root.get_child(0).add_child(proj)
proj.global_position = fire_origin
```
Projectiles are always parented to the scene root child (index 0), **never** to the shooter.

### Spawning pattern (Missile)
```gdscript
var missile = MissileScene.instantiate()
missile.configure(def, team, fire_pos, target_pos, launcher_type)
get_tree().root.get_child(0).add_child(missile)
# Do NOT set global_position after add_child — fire_pos was passed to configure().
```

### Adding a new projectile — checklist
1. Create `scripts/projectiles/MyProjectile.gd` extending `ProjectileBase`.
2. Set `gravity`, `max_lifetime`, `source` in `_ready()` as needed.
3. Override `_on_hit(pos, collider)` for custom hit logic. Call `_apply_splash` if needed.
4. Override `_after_move()` for orientation, trails, acceleration.
5. Override `_on_expire()` to detach any persistent trail children.
6. Create `scenes/projectiles/MyProjectile.tscn`. Script path: `res://scripts/projectiles/MyProjectile.gd`.
7. Any mesh/light added in `.tscn` is fine. Avoid collision shapes — base raycast handles it.
8. **Never** put projectile scenes in `scenes/` root or scripts in `scripts/` root.

## MinionBase (`scripts/minions/MinionBase.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`MinionBase` is the single base class for every minion unit in the game. `class_name MinionBase`, `extends CharacterBody3D`. All movement, waypoint marching, target scanning, ranged attack, slow debuff, puppet-sync, damage, and death are handled here.

### File layout
```
scripts/minions/MinionBase.gd   ← base class
scripts/minions/MinionAI.gd     ← standard rifle minion (thin subclass, holds class_name for static method access)

scenes/minions/Minion.tscn      ← standard minion scene; script: res://scripts/minions/MinionAI.gd
```

### Lifecycle
1. `MinionSpawner._spawn_at_position()` instantiates the `.tscn`, sets `team` and `_minion_id`, calls `add_child`, then calls `minion.setup(team, waypoints, lane_i)`.
2. `_ready()` sets `health = max_health`, defers `_init_visuals()` (→ `_build_visuals()`) and `_cache_static_refs()`.
3. `_physics_process` drives gravity, attack timer, throttled target rescan, movement/strafe, throttled separation, and `move_and_slide()`. Server/singleplayer only — returns immediately if `is_puppet`.
4. Puppet clients receive state via `apply_puppet_state(pos, rot, hp)` and lerp to it in `_process()`.

### @export configuration (set in .tscn, never in code)
| Export | Type | Default | Purpose |
|---|---|---|---|
| `max_health` | `float` | `60.0` | Starting and maximum HP. |
| `speed` | `float` | `4.0` | Move speed (m/s). |
| `attack_range` | `float` | `2.5` | Distance to attack a base directly. |
| `shoot_range` | `float` | `10.0` | Distance at which ranged fire opens. |
| `attack_damage` | `float` | `8.0` | Per-shot damage. |
| `attack_cooldown` | `float` | `1.5` | Seconds between attack attempts. |
| `bullet_speed` | `float` | `58.8` | Projectile velocity used by default `_fire_at()`. |
| `detect_range` | `float` | `12.0` | Target scan radius. |

### Runtime state (not exported, set internally)
- `team: int` — set by `MinionSpawner` before `add_child`, then confirmed via `setup()`.
- `health: float` — initialised to `max_health` in `_ready()`.
- `_dead`, `_attack_timer`, `_slow_timer`, `_slow_mult` — internal, do not read from outside.
- `is_puppet: bool` — set by `MinionSpawner.spawn_for_network()` on client peers; disables physics.
- `_minion_id: int` — unique ID assigned by spawner; used for network sync lookup.
- `_cached_towers`, `_cached_bases`, `_enemy_base` — populated once in `_cache_static_refs()`.

### Overridable hooks
```gdscript
# Override for custom attack: melee, AoE, ability, etc.
# Default: instantiates Bullet.tscn, fires toward target, plays shoot_audio,
#          calls LobbyManager.spawn_bullet_visuals.rpc on server.
func _fire_at(target: Node3D) -> void

# Override to use a custom model instead of kenney blocky-character GLBs.
# Default: loads cached GLB for team, sets up CharacterBlue/CharacterRed,
#          disables shadows, caches AnimationPlayer, loads audio streams,
#          plays idle, adds shadow proxy capsule.
func _build_visuals() -> void

# Called just before the death tween and queue_free().
# Override to spawn death VFX, drop items, award bonus points, etc.
func _on_death() -> void
```

### Static model character methods
```gdscript
MinionBase.set_model_characters(blue_char, red_char)   # clears cache; called by Main.gd via MinionAI
MinionBase.get_blue_model_path() -> String
MinionBase.get_red_model_path()  -> String
```
`MinionAI` is a thin subclass with `class_name MinionAI` so callers can write `MinionAI.set_model_characters(...)` without knowing the base class name.

### Targeting priority
`_find_target()` scans in this order: enemy minions → local FPS players → remote player ghosts → enemy towers → enemy base. Returns nearest within `detect_range`.

### Darkness / detect-range interaction
Dark positions reduce effective detect range from 12 → 5 and add 60% shot miss chance. This logic lives in `MinionAI` consumers (`AISupporterController`) not in `MinionBase` itself — `MinionBase` exposes `_is_in_darkness(pos) -> bool` as a helper.

### Spawning pattern
```gdscript
var minion: CharacterBody3D = minion_scene.instantiate()
minion.set("team", team)
minion.set("_minion_id", minion_id)
minion.name = "Minion_%d" % minion_id
minion.position = spawn_pos
get_tree().root.get_node("Main").add_child(minion)
minion.setup(team, waypoints, lane_i)
# For puppet clients, also set is_puppet=true and disable physics process.
```
**Critical**: set `team` **before** `add_child` so `_ready()` sees the correct value.

### Adding a new minion type — checklist
1. Create `scripts/minions/MyMinion.gd` extending `MinionBase`.
2. Set `@export` overrides in the `.tscn`: `max_health`, `speed`, `attack_damage`, etc.
3. Override `_fire_at(target)` for custom attack. Call `shoot_audio.play()` manually if desired.
4. Override `_build_visuals()` if not using kenney GLBs.
5. Override `_on_death()` for death VFX or drops.
6. Create `scenes/minions/MyMinion.tscn`. Script path: `res://scripts/minions/MyMinion.gd`.
7. Add `CapsuleShape3D` `CollisionShape3D`, `ShootAudio` (`AudioStreamPlayer3D`), `DeathAudio` (`AudioStreamPlayer3D`) nodes to the `.tscn`.
8. Update `MinionSpawner` or whichever system spawns the new type.
9. **Never** put minion scenes in `scenes/` root or scripts in `scripts/` root.

## Map layout
- Map: 200×200 units. Blue base z=+82, Red base z=-82
- Lanes: Left (`x≈-85`), Mid (straight), Right (`x≈+85`) — cubic Bézier, 40 sample points each
- Mountain/off-lane band: `|x|` 15–80
- Biome split (grass vs desert) is seeded: `seed % 2 == 0` → grass left (`x<0`), else flipped
- Peaks reach height 22 (snow line 13) — physically impassable, jump velocity is 6
- Plateaus max height ~7 — reachable, used as sniper nests

## Game Features
- **Dual Mode**: Fighter role switches between FPS shooting and RTS tower placement (Tab). Supporter role is RTS-only; no Tab switching
- **Player Roles**: Fighter (FPS combat + optional RTS) or Supporter (RTS-only tower placement). One Supporter slot per team, server-enforced. Role selected at game start via `RoleSelectDialog`
- **Multiplayer**: ENet-based, up to 10 players. Host/join from `StartMenu`. Lobby screen with team display and ready checks. Seed broadcast ensures identical procedural map on all clients. Server is authoritative for shot damage, minion state, tower placement, and team points
- **Remote Player Ghosts**: Other players shown as `RemotePlayerGhost` nodes with lerped position/rotation (speed 15). Animation driven by actual movement speed (walk/idle). Hitbox is a `StaticBody3D` with `ghost_peer_id` meta for server-side raycast identification
- **Character Avatars**: Kenney blocky-characters GLB models. Three random characters picked per game: blue minions, red minions, local player. Avatar char reported to server and synced to all peers via `LobbyManager`
- **Respawn System**: On death, player switches to RTS camera and waits. Respawn time = `RESPAWN_BASE (5s) + death_count × RESPAWN_INCREMENT (5s)`. In multiplayer, death count tracked in `LobbyManager.player_death_counts`
- **Wave System**: Minion waves spawn every 30 seconds with escalating numbers (max 6 per lane)
- **Procedural Generation**: Each game has unique map layout with peaks, plateaus, secret paths
- **Physics-based Bullets**: Realistic gravity with different speeds for player (280 m/s) vs minions (120 m/s)
- **Cannonball Towers**: Tower projectiles use ballistic arcs with splash damage (radius 3 units)
- **Team Resource System**: Currency based on team points for tower placement. Synced to all clients via `LobbyManager.sync_team_points.rpc`
- **Minion AI**: Pathfinding, strafing, separation steering, and ranged combat
- **Time-of-Day**: `Main.time_seed` (0=sunrise, 1=noon, 2=sunset, 3=night) set once at game start. Lamps off at noon, on otherwise
- **Shootable Street Lamps**: Bulb-only `SphereShape3D` hitbox. `Bullet.gd` checks `is_lamp` meta on hit `StaticBody3D` → calls `ShootableLamp.shoot_out()`. Flicker on shoot-out and on restore (15s timer)
- **Fence + Torch**: Procedural wooden fence panels line both edges of each lane. Random 20% gaps. 15% of panels have a torch (OmniLight3D + GPU particle flame) spaced at least 12 units apart
- **Cover Objects**: `WallPlacer` scatters walls and crates across 20 randomly placed clearings in off-lane areas. Clearings avoid lanes, secret paths, and bases
- **Darkness Mechanics**: `MinionAI._is_in_darkness(pos)` walks `LampPlacer.lamp_scripts` — if no lit lamp within 22 units, pos is dark. Dark targets: detect range 12→5, shot miss chance 60%
- **Fog of War**: `FogOverlay.gd` + `FogOfWar.gdshader` — full-map mesh at y=25. Up to 64 visibility sources (player, allied minions, towers) clear circles in the fog. Updated each frame via `update_sources()`
- **Entity Health Bars**: Visible only when zoomed (`camera.fov < 55`), within 75 units, and with clear line-of-sight (occlusion raycast in `EntityHUD.process_entity_hud`)
- **Loading Screen**: `LoadingScreen.tscn` shown during world setup. Progress driven by `LoadingState.report()` and awaited signals from `TreePlacer.done` / `WallPlacer.done`
- **Pause Menu**: `Esc` toggles pause. Pauses player input, shows Resume/Leave buttons. Leave exits to `StartMenu.tscn` and closes network connection if multiplayer
- **Weapon Pickups**: 3 lane-midpoint pickups + up to 17 random mountain-area pickups. Respawn after 90 seconds at same position (or nearby if occupied)

## Adding new input actions
Register in `project.godot` `[input]` section using the existing Object serialization format. Physical keycodes for common keys:
- Shift = `4194325`, Ctrl = `4194326`, Tab = `4194320`, Space = `32`
- Mouse button 1 = LMB, button 2 = RMB
