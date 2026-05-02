# Flankers — AGENTS.md

## Project
Godot 4 hybrid FPS/RTS game. Single-player and multiplayer (up to 10 players via ENet). No editor GUI workflow — all scene/resource edits are done by hand in `.tscn`/`.tres` files or via GDScript runtime generation.

---

## MANDATORY: Read the Plans Directory Before Starting Any Task

Before beginning any fix, feature, or refactor, read every `.md` file in the `plans/` directory.

- Plans marked **Status: Approved, not started** or **Status: In progress** are active. Work must align with them — do not make architectural decisions that conflict with an active plan.
- Plans marked **Status: Complete** have been fully executed and may be skipped.
- If a plan is fully implemented, update its `Status:` line at the top of the file to `Status: Complete` before finishing your work.

```bash
# Quick check — list all plans and their current status
grep -h "^\*\*Status:" plans/*.md
```

---

## MANDATORY: Tests Must Pass After Every Code Change

**Run `make test` after every single code change — no exceptions.**

```bash
make test
```

This runs the GUT headless suite. The suite must exit with no failing tests (the summary line will read `---- N pending/risky tests ----` with zero failures, or `---- All tests passed! ----`). A change that introduces any new failure is not acceptable, even if the feature works at runtime.

### Required process for every fix or feature

Every code change — bug fix or new feature — must follow this exact sequence:

1. **Apply the fix** — make the code change.
2. **Write the regression test** — write a test that passes with the fix in place.
3. **Verify the test catches the regression** — revert the fix (restore the broken code), run `make test`, and confirm the new test fails. If it does not fail, the test is not actually guarding against the regression and must be rewritten.
4. **Re-apply the fix** — restore the correct code, run `make test`, confirm all tests pass.

This sequence is mandatory. A test that was never verified to fail without the fix provides no safety guarantee.

### Rules

- **Fix the test if the code is correct** — with written justification for why the test was wrong.
- **Fix the code if the test is correct** — do not mark real regressions as `pending()`.
- **Write new tests for every new feature or bug fix** before the change is considered complete.
- **Never silence a failure** by deleting the test or converting it to `pending()` without a documented known-bug justification.

The suite currently has **608 passing** and **8 pending/risky** (all intentional — documented known bugs or no-assert smoke tests). Any run that drops below 608 passing is a regression.

See the [Test Suite](#test-suite) section for the full inventory of test files and what each covers.

---

## Commands
```bash
make           # stop + relaunch + show logs (default)
make run       # launch + show logs
make stop      # kill running instance
make logs      # print /tmp/flankers.log
make clean     # delete all *.uid files recursively under scripts/
make test      # run GUT headless test suite, output to /tmp/flankers_tests.log
```
Game binary: `/usr/bin/godot` (system install, 4.6.2). No `./godot` or `bin/godot` symlink in repo.

---

## Architecture

## Skill System

### Overview
The skill system provides Fighter players with three distinct branches of abilities: Guardian, DPS, and Tank. Supporter players have their own branch system with Arsenal, Logistics, and Defense skills.

Skills are earned through leveling up (1 skill point per level) and can be unlocked in the skill tree UI. Active abilities have cooldowns and can be assigned to hotbar slots.

### Skill Tree Structure
- Each player has a unique skill tree with three branches per role
- Skill nodes are organized by tier (1-3, corresponding to cost in skill points)
- Nodes have prerequisites, must be at required level, 
- Active abilities have cooldowns that reset after use
- Passive abilities modify player stats

### Skill Definitions

Skills are defined in the static `SkillDefs.gd` autoload. Each node includes fields:
- role: "Fighter" or "Supporter"
- branch: visual grouping (e.g., "Guardian", "DPS", "Tank", "Arsenal", "Logistics", "Defense")
- type: "passive", "active", "unlock", or "utility"
- tier: 1, 2, or 3 (also cost in skill points)
- cost: int skill points to unlock
- prereqs: Array[String] of node IDs that must be unlocked first
- level_req: minimum player level required (0 = no gate)
- name: short display name
- description: short display string
- passive_key: String used by `SkillTree.get_passive_bonus()` (passive/utility only)
- passive_val: float value contributed by this node to its passive_key
- cooldown: float seconds (active nodes only; 0.0 for non-actives)

### Skill Effects

Fighter Skills:
- Guardian branch:
  - Field Medic: Heal yourself and nearby allies for 25 HP within 8m. 15s cooldown.
  - Rally Cry: Grant nearby allies +20% move speed for 5s. 30s cooldown.
  - Revive Pulse: Fully heal yourself and restore 30 HP to all allies within 10m. 60s cooldown.
- DPS branch:
  - Dash: Dash 5m forward. 6s cooldown.
  - Rapid Fire: Current weapon fires 3× faster for 3s. 20s cooldown.
  - Rocket Barrage: Fire one rocket at each enemy tower within 50m (up to 5). No targets = no effect. 45s cooldown.
- Tank branch:
  - Adrenaline: Instantly heal 40 HP. 20s cooldown.
  - Iron Skin: Absorb the next 60 incoming damage as a shield for 8s. 30s cooldown.
  - Deploy MG: Deploy a MachineGun turret at your feet for 20s (no team point cost). 60s cooldown.

Supporter Skills:
- Arsenal branch:
  - Build Discount: All your placements cost -2 team points.
  - Turret Overdrive: Targeted friendly tower fires 2× speed for 6s. 25s cooldown.
  - Advanced Launcher: Unlocks Advanced Launcher missile type in the build shop.
- Logistics branch:
  - Fast Respawn: Your personal respawn timer is -2s.
  - Ammo Drop: Place an ammo crate at your feet. Allies within 3m reload instantly. 30s cooldown.
  - Build Anywhere: Removes lane-setback restriction from your placements.
  - Rally: Rally beacon: all teammates gain +10% move speed for 8s. 45s cooldown.
- Defense branch:
  - Tower HP: Friendly towers you place spawn with +20% HP.
  - Repair: Restore 30% HP to the nearest friendly tower within 15m. 20s cooldown.
  - Fortify: Barrier towers you place have ×2 HP.
  - Point Surge: On kill: your team gains +3 points.

### Architecture

The skill system is entirely server-authoritative:
- `SkillTree` autoload manages state, RPC surface, and cooldown tracking
- `SkillDefs` contains static skill definitions
- `FighterSkills` handles Fighter-specific active ability effects
- `SupporterSkills` handles Supporter-specific active ability effects

### Lifecycle
1. `SkillTree.register_peer(id, role)` is called after role confirmation
2. Level-ups grant 1 skill point
3. Players can unlock skills via UI that sends `SkillTree.request_unlock(node_id)`
4. Active abilities are assigned via `SkillTree.request_assign_active(slot, node_id)`
5. Active abilities are used via `SkillTree.request_use_active(slot)`

### Usage Flow
When a player uses an active ability:
- `SkillTree.request_use_active(slot)` is called by client
- This calls `SkillTree.use_active_local()` on the server
- This dispatches to either `FighterSkills.execute()` or `SupporterSkills.execute()` based on role
- Skill effects are applied directly to player or game state

### GameSync Integration
Skill tree state affects:
- Passive bonus calculations (via `get_passive_bonus`)
- Level-up point distribution
- Skill point management

### Skill Tree State Management
- `SkillTree` manages each peer's skill point total, unlocked nodes, and active slot assignments
- Cooldowns are tracked per peer and cleared when abilities are used
- `SkillTree.get_passive_bonus()` computes cumulative bonuses from unlocked nodes
- State is server-authoritative and syncs to clients via `sync_skill_state.rpc`

### Architecture

The skill system is entirely server-authoritative:
- `SkillTree` autoload manages state, RPC surface, and cooldown tracking
- `SkillDefs` contains static skill definitions
- `FighterSkills` handles Fighter-specific active ability effects
- `SupporterSkills` handles Supporter-specific active ability effects

### Lifecycle
1. `SkillTree.register_peer(id, role)` is called after role confirmation
2. Level-ups grant 1 skill point
3. Players can unlock skills via UI that sends `SkillTree.request_unlock(node_id)`
4. Active abilities are assigned via `SkillTree.request_assign_active(slot, node_id)`
5. Active abilities are used via `SkillTree.request_use_active(slot)`

### GameSync Integration
Skill tree state affects:
- Passive bonus calculations (via `get_passive_bonus`)
- Level-up point distribution
- Skill point management


### Autoloads (11 singletons, registered in `project.godot`)

| Name | Script | Purpose |
|---|---|---|
| `GameSync` | `scripts/GameSync.gd` | In-game player state: healths, teams, spawn positions, ammo, weapon type, respawn countdowns. `PLAYER_MAX_HP = 100`. Signals: `player_health_changed`, `player_died`, `player_respawned`, `remote_player_updated`, `player_ammo_changed` |
| `LaneData` | `scripts/LaneData.gd` | All lane Bézier path data. `get_lane_points(i)`, `get_lane_waypoints(i, team)`, `regenerate_for_new_game()` |
| `TeamData` | `scripts/TeamData.gd` | Team currency. Starting points: 75 each. `add_points(team, amount)`, `spend_points(team, amount) -> bool`, `get_points(team)`, `sync_from_server(blue, red)` |
| `NetworkManager` | `scripts/NetworkManager.gd` | ENet peer management. Port: 8910, max peers: 10. `start_host(port)`, `join_game(address, port)`, `close_connection()`. Signals: `peer_connected`, `peer_disconnected`, `connected_to_server`, `connection_failed`, `server_disconnected` |
| `LobbyManager` | `scripts/LobbyManager.gd` | Player registry, role claiming, game start orchestration, bullet/minion/tower sync RPCs, ping broadcast, death counts. `register_player_local(id, name)`, `can_start_game()`, `start_game(path, seed, time_seed)`, `get_players_by_team(team)`, `increment_death_count(id)`, `get_respawn_time(id)`, `_sender_id()`. `RESPAWN_BASE = 5.0`. Signals: `lobby_updated`, `game_start_requested`, `all_roles_confirmed`, `ping_received`, `tower_despawned`, `item_spawned` |
| `LevelSystem` | `scripts/LevelSystem.gd` | XP, leveling (12 levels), attribute points (hp/speed/damage, cap 6 each). `award_xp(id, amount)`, `spend_point_local(id, attr)`, `request_spend_point.rpc_id(1, attr)`, `get_xp(id)`, `get_level(id)`, `get_unspent_points(id)`, `get_bonus_hp(id)`, `get_bonus_speed_mult(id)`, `get_bonus_damage_mult(id)`, `register_peer(id)`, `clear_peer(id)`, `clear_all()`. Signals: `xp_gained`, `level_up`, `attribute_spent` |
| `TeamLives` | `scripts/TeamLives.gd` | Lives per team (default from `GameSettings.lives_per_team`). Server-authoritative, RPC synced. Signal: `game_over` |
| `LoadingState` | `scripts/ui/LoadingState.gd` | Relay for loading progress. `report(text, progress)`. Signal: `status_changed` |
| `GraphicsSettings` | `scripts/ui/GraphicsSettings.gd` | Persistent graphics settings saved to `user://graphics.cfg`. Fog (enabled, density), DoF (enabled, blur), shadow quality (0=off/1=low/2=high). `apply(...)`, `restore_defaults()`, `get_fog_density(time_seed)`. Signal: `settings_changed` |
| `GameSettings` | `scripts/GameSettings.gd` | Persistent game settings saved to `user://game_settings.cfg`. `lives_per_team` (default 20) |
| `SoundManager` | `scripts/SoundManager.gd` | Global audio pool: 8× `AudioStreamPlayer3D` + 3× `AudioStreamPlayer` |
| `SkillTree` | `scripts/SkillTree.gd` | Skill tree state, RPC surface, cooldown tracking, and passive bonus queries. Server-authoritative. Signals: `skill_unlocked`, `active_used`, `skill_pts_changed`, `active_slots_changed` |

### Runtime-generated nodes
Most geometry is built at runtime in `_ready()` — no pre-baked meshes:
- `TerrainGenerator.gd` — procedural 200×200 mesh + `HeightMapShape3D` collision, seeded per game
- `LaneVisualizer.gd` — dirt ribbon meshes along lane curves
- `LampPlacer.gd` — street lamp nodes placed along lane sample points. Each lamp is a `StaticBody3D` with a `SphereShape3D` hitbox on the bulb only. Exposes `lamp_scripts: Array` for darkness queries
- `ShootableLamp.gd` — script attached to each lamp. Holds refs to `OmniLight3D`, bulb `MeshInstance3D`, bulb `StandardMaterial3D`. `shoot_out()` triggers flicker-then-dark; auto-restores after 15s
- `FencePlacer.gd` — fence panels along both edges of each lane. Random gaps (20% chance). Each panel is a `StaticBody3D` on collision layer 2. Randomly spawns torches (15% chance, min 12 units apart) with `OmniLight3D` + `GPUParticles3D` flame effect
- `WallPlacer.gd` — walls and crates in 20 random off-lane clearings. Avoids lane edges, secret paths, base zones. Uses kenney_fantasy-town-kit walls + kenney_blaster-kit crates. Emits `done` signal (awaited by loading screen)
- `TreePlacer.gd` — procedural trees along lane edges. Supports `menu_density` override for lighter start-menu background
- `FogOverlay.gd` — full-map `MeshInstance3D` at y=25 driven by `FogOfWar.gdshader`. `update_sources(player_pos, player_radius, minion_positions, minion_radius, tower_positions, tower_radius)` pushes up to 64 visibility sources as `vec4` array to shader

### Scene tree (Main.tscn)
```
Main (Node, Main.gd)
  World (Node3D)
    Terrain (StaticBody3D, TerrainGenerator.gd)
    LaneVisualizer (Node3D, LaneVisualizer.gd)
    TreePlacer (Node3D, TreePlacer.gd)
    WallPlacer (Node3D, WallPlacer.gd)
    FencePlacer (Node3D, FencePlacer.gd)
    SunLight (DirectionalLight3D) — orange-tinted, shadows enabled
    WorldEnvironment → assets/night_environment.tres (swapped at runtime by time_seed)
    ← LampPlacer, BlueBase, RedBase spawned here at runtime by Main.gd
  RTSCamera (Camera3D, RTSController.gd) — orthographic, size=80
  MinionSpawner (Node, MinionSpawner.gd)
  BuildSystem (Node, BuildSystem.gd)
  HUD (CanvasLayer, ui_theme.tres)
    VignetteRect (ColorRect, vignette.gdshader)
    DamageFlashRect (ColorRect, damage_flash.gdshader)
    HUDOverlay (Control) ← EntityHUD added here at runtime
    XPPanel: LevelLabel + XPBar + PendingButton (hidden until level-up available)
    LivesBar: BlueBar + RedBar (max=GameSettings.lives_per_team)
    WaveInfoPanel / WaveInfoLabel
    WaveAnnouncePanel / WaveAnnounceLabel (hidden)
    GameOverScreen (GameOverScreen.tscn instanced)
    Crosshair: 4 orange bars + HitIndicatorRing (4 gold rects, fade on hit) + ReloadBar
    VitalsPanel: WeaponSlots (Slot1+Slot2) + StaminaBar + HealthBar
    RespawnLabel (hidden)
    MinimapPanel → Minimap (Control, Minimap.gd)
    AmmoPanel → AmmoLabel
    PointsPanel → PointsLabel
    EventFeed (Control, EventFeed.gd) — scrolling kill/event log
    ReloadPrompt (Label, hidden)
  AudioModeSwitch (AudioStreamPlayer)
  AudioWave (AudioStreamPlayer)
  AudioRespawn (AudioStreamPlayer)
  ← FPSPlayer_<peer_id>, PlayerManager, FogOverlay, LampPlacer added at runtime
```

Additional scenes (not in Main.tscn static tree):
- `scenes/ui/StartMenu.tscn` — host/join/local-play UI with cinematic orbiting `MenuCamera.gd` and live menu-world terrain background
- `scenes/ui/Lobby.tscn` — pre-game lobby with team lists and ready/start controls (`Lobby.gd`)
- `scenes/ui/LoadingScreen.tscn` — progress bar overlay, layer=10. Progress via `LoadingState.report()`, awaits `TreePlacer.done` + `WallPlacer.done`
- `scenes/ui/RoleSelectDialog.tscn` — Fighter/Supporter role picker. One Supporter slot per team, server-enforced
- `scenes/ui/PauseMenu.tscn` — Resume/Settings/Leave game (`PauseMenu.gd`)
- `scenes/ui/SupporterHUD.tscn` — 9-slot placement toolbar for Supporter/RTS mode (`SupporterHUD.gd`)
- `scenes/ui/LevelUpDialog.tscn` — HP/Speed/Damage attribute point spend dialog (`LevelUpDialog.gd`)
- `scenes/ui/SettingsPanel.tscn` — Fog/DoF/shadow/lives settings (`SettingsPanel.gd`)
- `scenes/ui/GameOverScreen.tscn` — Win/loss screen (`GameOverScreen.gd`)
- `scenes/players/BasePlayer.tscn` — base scene for all player representations. `CharacterBody3D` root with `CollisionShape3D`, `HitBody (StaticBody3D + HitShape CollisionShape3D)`, `PlayerBody/CharacterMesh (Node3D)`. Script: `BasePlayer.gd`. `FPSPlayer.tscn` inherits this scene and attaches `FPSController.gd`.

### Key data flows
- `Main.gd._ready()` detects `NetworkManager._peer != null` → chooses single-player or multiplayer path
- `Main.gd._on_start_game()` awaits `$World/TreePlacer.done` and `$World/WallPlacer.done` before proceeding, driving the loading screen progress bar
- Multiplayer game start: `LobbyManager.start_game(path)` → broadcasts `notify_game_seed.rpc` (call_local; sets `GameSync.game_seed` + `LaneData.regenerate_for_new_game()` on all peers) → `load_game_scene.rpc` → all peers change scene
- Bullets spawned into `get_tree().root.get_child(0)` (scene root child 0) — never parented to shooter
- Multiplayer shot path: `FPSController` → `LobbyManager.validate_shot.rpc_id(1, ...)` → server applies damage via `GameSync.damage_player`, calls `apply_player_damage.rpc` on target peer, calls `spawn_bullet_visuals.rpc` on all clients
- Minions: set `team` **before** `add_child` so `_ready()` sees the correct value. Then call `setup(team, waypoints, lane_i)`
- Remote player positions: `FPSController` → `LobbyManager.report_player_transform.rpc_id(1, ...)` → server calls `broadcast_player_transform.rpc` → `GameSync.remote_player_updated` signal → `PlayerManager` creates/updates `BasePlayer` puppet nodes
- Avatar chars: `Main._pick_minion_characters()` → `LobbyManager.report_avatar_char.rpc_id(1, char)` → server updates `players` dict → `sync_lobby_state.rpc` → `BasePlayer._try_load_avatar()` reads on `lobby_updated`
- Pings: `RTSController` → `LobbyManager.send_ping.rpc_id(1, pos, team)` → server → `LobbyManager.ping_received` signal → `PingHUD` draws 3D beam + screen indicator
- RPC sender ID: `multiplayer.get_remote_sender_id()` returns 0 when the server calls an RPC on itself. Always use `_sender_id()` helper in `LobbyManager` which maps 0 → 1

---

## BasePlayer (`scripts/players/BasePlayer.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`BasePlayer` is the single base class for all player representations. `class_name BasePlayer`, `extends CharacterBody3D`. Both the local FPS player and remote puppet nodes use this class — differentiated by `is_local`.

### File layout
```
scripts/players/BasePlayer.gd
scripts/roles/fighter/FPSController.gd   ← extends BasePlayer; local player input + combat
scripts/network/PlayerManager.gd         ← lifecycle manager for remote peer puppets

scenes/players/BasePlayer.tscn           ← CharacterBody3D root, no baked GLB
scenes/roles/FPSPlayer.tscn             ← inherits BasePlayer.tscn, attaches FPSController.gd
```

### Lifecycle (CRITICAL — order matters)
1. `instantiate()` the scene.
2. Call `setup(peer_id, team, is_local, avatar_char)` **before** `add_child`. `_ready()` reads `is_local` to decide whether to disable `HitShape`. If setup is called after `add_child`, the `HitShape` is not disabled on the first frame, causing the `CharacterBody3D` capsule to collide with the sibling `StaticBody3D` and launch the player upward.
3. Set `node.name`.
4. Call `add_child(node)`.
5. Set `node.global_position` (must be after `add_child` — engine requirement).

### @export / var
| Field | Type | Default | Purpose |
|---|---|---|---|
| `peer_id` | `int` | `0` | Multiplayer peer this node represents |
| `player_team` | `int` | `0` | Team index (0=blue, 1=red) |
| `is_local` | `bool` | `false` | True when owned by local peer |
| `avatar_char` | `String` | `""` | Character letter a–f; drives `_load_model` |

### Overridable hooks
```gdscript
func _build_visuals() -> void          # called deferred from _ready(); default no-op
func _on_died() -> void                # called by _set_alive(false)
func _on_respawned(spawn_pos: Vector3) # called by _set_alive(true)
func take_damage(amount, source, source_team, shooter_peer_id) -> void  # no-op in base
```

### HitBody / HitShape contract
- `HitBody` (`StaticBody3D`) stays on **collision layer 1** when alive so bullet raycasts (`collision_mask=1`) detect it.
- `_set_alive(false)` sets layer to 0 (invisible to raycasts).
- `is_local=true` → `HitShape.disabled = true` always — local player must not collide with own hitbox.
- Never add a second `Area3D` or collision shape to `BasePlayer.tscn` — `TowerBase` pattern.

### Avatar model loading
- `_init_visuals()` (deferred from `_ready()`) calls `_try_load_avatar()`.
- If avatar char is not yet known, loads fallback `"a"` and connects `LobbyManager.lobby_updated`.
- On `_on_lobby_updated`: if char found, calls `_load_model(char)` and **disconnects** the signal — prevents double-load.
- `_load_model` adds new model BEFORE freeing old children to avoid same-frame `queue_free` that silently sets `visible=false` on the root node.
- `ResourceLoader.exists()` is checked before `load()` to suppress engine-level file-not-found errors.

---

## PlayerManager (`scripts/network/PlayerManager.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`PlayerManager` owns the lifecycle of remote peer `BasePlayer` puppets. Mirrors `MinionSpawner`. Added to `Main.tscn` at runtime alongside `FogOverlay` and `LampPlacer`.

### Key methods
- `remove_player(peer_id)` — frees the puppet node and erases from `_players` dict.
- `_on_remote_player_updated(peer_id, pos, rot, team)` — spawns puppet on first call, calls `update_transform` on subsequent calls.
- `_on_player_died(peer_id)` — calls `puppet._set_alive(false)`.
- `_on_player_respawned(peer_id, spawn_pos)` — calls `puppet._set_alive(true)` + `update_transform`.

### @export
- `spawn_root: Node` — node under which puppets are spawned. Defaults to `get_parent()` at runtime. **Set this in tests** to inject a stub root instead of polluting the GUT tree.

### Signal cleanup
`_exit_tree()` disconnects all four signal connections. This is required for test isolation — `queue_free` alone does not disconnect signals, causing ghost firings on the next test's `GameSync` signals.

### Stale-RPC guard
When a puppet is spawned, `player.visible` is pre-set from `GameSync.player_dead[peer_id]` **before** `add_child`. Stale reliable-queue `notify_player_died` RPCs from a previous session arrive after the node exists; since the node is already in the correct dead state, the RPC is a no-op.

### Diagnostic prints
All print calls are intentional and must be preserved — they exist to diagnose the invisible-remote-player bug class. Prefix guide: `[PM]`, `[PM-SPAWN]`, `[PM-DIED]`, `[PM-RESP]`, `[PM-RM]`, `[PM-VIS-CHG]`, `[PM-DIAG]`.

---

## TowerBase (`scripts/towers/TowerBase.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`TowerBase` is the single base class for every tower in the game. `extends StaticBody3D`. All multiplayer plumbing, collision, targeting, hit-flash, and death/despawn are handled here.

### Lifecycle
1. `BuildSystem.spawn_item_local()` instantiates the `.tscn`, calls `add_child`, sets `node.global_position`, then calls `node.setup(team)`.
2. `setup(team)` sets `_health = max_health`, calls `_build_visuals()`, caches the turret node (if `turret_node_name != ""`), and builds the detection `Area3D` (if `attack_range > 0.0`). Adds node to group `"towers"`.
3. `_process(delta)` drives the attack timer. On expiry: finds nearest enemy via `_find_target()`, rotates turret, calls `_do_attack(target)`, resets timer.

### @export configuration (set in .tscn, never in code)
| Export | Type | Default | Purpose |
|---|---|---|---|
| `tower_type` | `String` | `""` | Must match `BuildSystem.PLACEABLE_DEFS` key |
| `max_health` | `float` | `500.0` | Starting and maximum HP |
| `attack_range` | `float` | `30.0` | Detection sphere radius. Set `0.0` for passive towers — no `Area3D` is built |
| `attack_interval` | `float` | `3.0` | Seconds between attack attempts |
| `projectile_scene` | `PackedScene` | `null` | Spawned by default `_do_attack()`. Set `null` and override `_do_attack()` for non-projectile attacks |
| `turret_node_name` | `String` | `""` | Child node to `look_at` target each frame. `""` = no rotation |
| `model_scene` | `PackedScene` | `null` | GLB or subscene for the tower model. `null` = override `_build_visuals()` |
| `model_scale` | `Vector3` | `ONE` | Scale applied to the instantiated model root |
| `model_offset` | `Vector3` | `ZERO` | Local position offset of the model root |
| `fire_point_fallback_height` | `float` | `2.0` | Y offset when no `"FirePoint"` child exists |
| `xp_on_death` | `int` | `0` | XP awarded to killer. Falls back to `LevelSystem.XP_TOWER` when `0` |

### Overridable hooks
```gdscript
func _build_visuals() -> void    # override when model_scene is null
func _do_attack(target: Node3D) -> void  # override for non-projectile attacks
```

### Fire origin
`get_fire_position() -> Vector3` — looks for a child node named `"FirePoint"` (any depth). If found, returns its `global_position`. Otherwise returns `global_position + Vector3(0, fire_point_fallback_height, 0)`.

### Targeting
- `_find_target()` — iterates `_area.get_overlapping_bodies()`, skips bodies without `take_damage`, skips same-team and team-unknown bodies, skips bodies without line-of-sight. Returns nearest valid enemy.
- `_get_body_team(body)` — duck-types team: checks `player_team` first (FPS players), then `team` (minions/towers).
- `_has_line_of_sight(target)` — raycast from `global_position + (0,2,0)` to `target.global_position + (0,0.8,0)`. Ignores tree trunks (meta `"tree_trunk_height"`). Up to 4 retries.

### Damage / death
- `take_damage(amount, source, source_team, shooter_peer_id)` — server-authoritative. Ignored if: already dead; `source_team == team` (friendly fire); client in multiplayer. Calls `_flash_hit()`, then `_die()` at 0 HP.
- `_die()` — awards XP via `LevelSystem.award_xp`. In multiplayer: `LobbyManager.despawn_tower.rpc(name)`. In singleplayer: `queue_free()` then emits `LobbyManager.tower_despawned` signal.

### Hit flash
`_flash_hit()` — applies a red emissive overlay (`_hit_overlay_mat`) via `set_surface_override_material`, tweens `emission_energy_multiplier` 3.0 → 0.0 over 0.3s, then clears back to `null`. **Critical**: never permanently assign a surface override material at init — this makes GLB models invisible.

### Tower stats (verified from .tscn files)
| Tower | max_health | attack_range | attack_interval | Spacing |
|---|---|---|---|---|
| Cannon | 900 | 30 | 1.0s | 42.0 |
| Mortar | 700 | 50 | 3.5s | 70.0 |
| MachineGun | 600 | 22 | 0.15s | 40.8 |
| Slow | 500 | 18 | 1.0s | 35.2 |
| Barrier | 1200 | 0 (passive) | — | 3.0 |
| Launcher | 600 | 0 (passive) | — | 3.0 |

### Adding a new tower — checklist
1. Create `scenes/towers/MyTower.tscn` extending `StaticBody3D`. Attach a script extending `TowerBase`.
2. Set all `@export` vars in the `.tscn`: `tower_type`, `max_health`, `attack_range`, `attack_interval`.
3. If auto-attacking with a projectile: set `projectile_scene`. The projectile must accept `shooter_team` as a property.
4. If custom attack (raycast, pulse, etc.): leave `projectile_scene = null` and override `_do_attack(target)`.
5. If passive (barrier, heal zone): set `attack_range = 0.0` — no `Area3D` is built.
6. Register in `BuildSystem.PLACEABLE_DEFS` with `"is_tower": true`.
7. Add `tower_type` key to the name-generation `elif` block in `BuildSystem.spawn_item_local()`.
8. **Do not add `Area3D` to the `.tscn`** — `TowerBase` builds it entirely in code.
9. **Write tests** for any new logic in your subclass.

---

## ProjectileBase (`scripts/projectiles/ProjectileBase.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`ProjectileBase` is the single base class for every projectile. `class_name ProjectileBase`, `extends Node3D`. All per-frame movement, gravity, raycast collision, lifetime expiry, friendly-fire guard, and splash damage are handled here.

### File layout
```
scripts/projectiles/ProjectileBase.gd
scripts/projectiles/Bullet.gd        ← player + minion hitscan tracer
scripts/projectiles/Cannonball.gd    ← cannon tower ballistic shell
scripts/projectiles/MortarShell.gd   ← mortar tower ballistic shell
scripts/projectiles/Rocket.gd        ← player rocket launcher
scripts/projectiles/Missile.gd       ← launcher tower guided missile

scenes/projectiles/Bullet.tscn
scenes/projectiles/Cannonball.tscn
scenes/projectiles/MortarShell.tscn
scenes/projectiles/Rocket.tscn
scenes/projectiles/Missile.tscn
```

### Core loop (`_process`)
1. Increment `_age`. If `>= max_lifetime` → `_on_expire()` then `queue_free()`.
2. If `gravity != 0.0` → subtract `gravity * delta` from `velocity.y`.
3. Raycast from `prev_pos` → `new_pos`. Hit → `_on_hit(pos, collider)` then `queue_free()`.
4. No hit → set `global_position = new_pos`, call `_after_move()`.

### Configuration vars (set before `add_child`)
| Var | Default | Purpose |
|---|---|---|
| `damage` | `10.0` | Direct-hit damage |
| `source` | `"unknown"` | Damage source tag |
| `shooter_team` | `-1` | `-1` = player. Tower/minion projectiles pass their `team` int |
| `shooter_peer_id` | `-1` | Set for player-fired projectiles |
| `max_lifetime` | `3.0` | Seconds until expiry |
| `gravity` | `18.0` | m/s². Set `0.0` to disable |
| `velocity` | `ZERO` | Set by caller before `add_child` |

### Overridable hooks
```gdscript
func _on_hit(pos: Vector3, collider: Object) -> void
func _after_move() -> void
func _on_expire() -> void
```

### Splash helper
```gdscript
_apply_splash(pos, radius, splash_dmg, splash_source, exclude_body = null)
```

### Concrete projectiles
| Class | Fired by | gravity | Splash |
|---|---|---|---|
| `Bullet` | `FPSController`, `MinionAI`, `LobbyManager` (visual) | 18.0 | None |
| `Cannonball` | Cannon tower | 18.0 | radius 3, 50% dmg |
| `MortarShell` | Mortar tower | 18.0 | radius 6, 50% dmg |
| `Rocket` | `FPSController` | 0.0 | radius 8, flat 80 dmg |
| `Missile` | `LauncherTower` | 0.0 (own `_process`) | from `LauncherDefs` |

#### Bullet special rules
- Ghost hitbox: `StaticBody3D` with `ghost_peer_id` meta → damage via `GameSync.damage_player` + `apply_player_damage.rpc`. Server-authoritative only.
- Emits `hit_something(hit_type: String)` on hit (`"player"`, `"tower"`, `"minion"`, `"building"`).
- `shooter_team = -1` for player bullets; minions pass their `team` int.

#### Cannonball special rules
- `target_pos` must be set **before** `add_child`. Arc computed in `_ready()` from `global_position`.
- Tree hit: spawns VFX, destroys tree, no combat damage.

#### MortarShell special rules
- `target_pos` must be set before `add_child`.
- Builds its own sphere mesh in `_ready()`.
- Smoke puff spawned every 0.06s in `_after_move`.

#### Rocket special rules
- Accelerates from 0.1 → 49 m/s (`ACCELERATION=120`).
- Persistent fire + smoke trails detached on `_on_hit` / `_on_expire`.
- Destroys trees within `TREE_DESTROY_RADIUS = 8.0`.

#### Missile special rules
- Use `configure(def, team, fire_pos, target_pos, launcher_type)` **before** `add_child`. Never set vars directly.
- All stats from `LauncherDefs.get_def(launcher_type)`.
- Screen shake on impact (attenuates 20–80 units).

### Spawning pattern (all except Missile)
```gdscript
var proj: ProjectileBase = Scene.instantiate()
proj.damage       = ...
proj.shooter_team = team
proj.velocity     = dir * speed
get_tree().root.get_child(0).add_child(proj)
proj.global_position = fire_origin
```

### Spawning pattern (Missile)
```gdscript
var missile = MissileScene.instantiate()
missile.configure(def, team, fire_pos, target_pos, launcher_type)
get_tree().root.get_child(0).add_child(missile)
# Do NOT set global_position — fire_pos was passed to configure().
```

### Adding a new projectile — checklist
1. Create `scripts/projectiles/MyProjectile.gd` extending `ProjectileBase`.
2. Set `gravity`, `max_lifetime`, `source` in `_ready()`.
3. Override `_on_hit`, `_after_move`, `_on_expire` as needed. Call `_apply_splash` if needed.
4. Create `scenes/projectiles/MyProjectile.tscn`. Avoid collision shapes — base raycast handles it.
5. **Never** put projectile scenes in `scenes/` root or scripts in `scripts/` root.
6. **Write tests** for custom hit/expire logic.

---

## MinionBase (`scripts/minions/MinionBase.gd`) — DO NOT MODIFY WITHOUT EXPLICIT INSTRUCTION

`MinionBase` is the single base class for every minion unit. `class_name MinionBase`, `extends CharacterBody3D`. All movement, waypoint marching, target scanning, ranged attack, slow debuff, puppet-sync, damage, and death are handled here.

### File layout
```
scripts/minions/MinionBase.gd
scripts/minions/MinionAI.gd    ← standard rifle minion (thin subclass with class_name)

scenes/minions/Minion.tscn     ← script: res://scripts/minions/MinionAI.gd
```

### Lifecycle
1. `MinionSpawner` instantiates `.tscn`, sets `team` + `_minion_id`, calls `add_child`, then `minion.setup(team, waypoints, lane_i)`.
2. `_ready()` sets `health = max_health`, defers `_init_visuals()` and `_cache_static_refs()`.
3. `_physics_process` drives gravity, attack timer, target rescan, movement/strafe, separation. Server/singleplayer only — returns if `is_puppet`.
4. Puppet clients receive state via `apply_puppet_state(pos, rot, hp)` and lerp in `_process()`.

### @export configuration
| Export | Default | Purpose |
|---|---|---|
| `max_health` | `60.0` | Starting and maximum HP |
| `speed` | `4.0` | Move speed (m/s) |
| `attack_range` | `2.5` | Distance to attack a base directly |
| `shoot_range` | `10.0` | Distance at which ranged fire opens |
| `attack_damage` | `8.0` | Per-shot damage |
| `attack_cooldown` | `1.5` | Seconds between attacks |
| `bullet_speed` | `58.8` | Projectile velocity |
| `detect_range` | `12.0` | Target scan radius |

### Overridable hooks
```gdscript
func _fire_at(target: Node3D) -> void  # default: instantiates Bullet.tscn
func _build_visuals() -> void          # default: kenney blocky-character GLBs
func _on_death() -> void               # default: no-op
```

### Static model character methods
```gdscript
MinionBase.set_model_characters(blue_char, red_char)  # called by Main.gd via MinionAI
MinionBase.get_blue_model_path() -> String
MinionBase.get_red_model_path()  -> String
```

### Targeting priority
`_find_target()` scans: enemy minions → local FPS players → remote player ghosts → enemy towers. Returns nearest within `detect_range`.

### Darkness helper
`_is_in_darkness(pos) -> bool` — walks `LampPlacer.lamp_scripts`. No lit lamp within 22 units → dark. Dark targets: detect range 12 → 5, shot miss chance 60%.

### Spawning pattern
```gdscript
var minion: CharacterBody3D = minion_scene.instantiate()
minion.set("team", team)          # BEFORE add_child
minion.set("_minion_id", id)
minion.name = "Minion_%d" % id
minion.position = spawn_pos
get_tree().root.get_node("Main").add_child(minion)
minion.setup(team, waypoints, lane_i)
```

### Adding a new minion type — checklist
1. Create `scripts/minions/MyMinion.gd` extending `MinionBase`.
2. Override `@export` vars in the `.tscn`.
3. Override `_fire_at`, `_build_visuals`, `_on_death` as needed.
4. Create `scenes/minions/MyMinion.tscn` with `CapsuleShape3D`, `ShootAudio`, `DeathAudio` nodes.
5. **Never** put minion scenes in `scenes/` root or scripts in `scripts/` root.
6. **Write tests** for any new combat or targeting logic.

---

## BuildSystem (`scripts/BuildSystem.gd`)

Not an autoload — exists as a child `Node` of `Main.tscn`. Access via `get_node("BuildSystem")` or the `BuildSystem` variable in `Main.gd`. **Not accessible by name from test files** — tests must instantiate it directly:
```gdscript
const BuildSystemScript := preload("res://scripts/BuildSystem.gd")
var bs := Node.new()
bs.set_script(BuildSystemScript)
add_child(bs)  # triggers _ready() which computes spacing
```

### Placeable definitions (`PLACEABLE_DEFS`)
| Key | Cost | is_tower | attack_range | Spacing |
|---|---|---|---|---|
| `cannon` | 25 | true | 30 | 42.0 |
| `mortar` | 35 | true | 50 | 70.0 |
| `slow` | 30 | true | 18 | 35.2 |
| `barrier` | 10 | true | 0 | 3.0 |
| `machinegun` | 40 | true | 22 | 40.8 |
| `launcher_missile` | 50 | true | 0 | 3.0 |
| `weapon` | varies | false | — | 5.0 |
| `healthpack` | 15 | false | — | 5.0 |
| `healstation` | 25 | false | — | 5.0 |

Weapon costs: pistol=10, rifle=20, heavy=30, rocket_launcher=60.
Spacing formula: `max(SPACING_FLOOR=10, attack_range * SPACING_FACTOR=1.4)`. Passive towers: `SPACING_PASSIVE=3.0`.

### Key methods
- `get_item_cost(item_type, subtype) -> int`
- `can_place_item(world_pos, team, item_type) -> bool` — team-half check → lane setback → slope check → spacing check
- `place_item(world_pos, team, item_type, subtype) -> String` — validates, spends points, spawns. Returns node name or `""` on failure.
- `spawn_item_local(world_pos, team, item_type, subtype, forced_name) -> String`

---

## Map Layout
- Map: 200×200 units. Blue base z=+82, Red base z=-82
- Lanes: Left (`x≈-85`), Mid (straight), Right (`x≈+85`) — cubic Bézier, 40 sample points each
- Mountain/off-lane band: `|x|` 15–80
- Biome split: `seed % 2 == 0` → grass left (`x<0`), else flipped
- Peaks: height 22 (snow line 13) — physically impassable, jump velocity is 6
- Plateaus: max height ~7 — reachable sniper nests

---

## GDScript Gotchas
- **Always use explicit types** when RHS could be Variant: array reads, ternary, `min()`/`clamp()` return values. `:=` on these causes parse errors.
  ```gdscript
  var x: float = some_array[i]   # correct
  var x := some_array[i]         # breaks if array is untyped Array
  ```
- Loop variables go out of scope after the loop — capture needed values before exiting
- `is_node_ready()` does not protect `@onready` vars from null — use explicit null checks
- `@onready` on dynamically spawned nodes must be accessed via `call_deferred`
- `Node.get("prop")` only reads declared GDScript properties. It does NOT read values set via `set()` on a plain `Node3D` with no script. Use inner classes with declared vars for test fakes.
- Autoload scripts must `extends Node`
- **`@onready` in subclass tests**: if `_ready()` is overridden in a test subclass, `@onready` bindings resolve BEFORE `_ready()` is called. Add stub child nodes in `_init()` (not `_ready()`) so bindings can find them by name.
- **RPC sender ID on server**: `multiplayer.get_remote_sender_id()` returns 0 when the server invokes an RPC locally. Use `_sender_id()`:
  ```gdscript
  func _sender_id() -> int:
      var id := multiplayer.get_remote_sender_id()
      return id if id != 0 else 1
  ```
- **Role slots**: one Supporter per team max. Server validates `set_role_ingame` and rejects with `_notify_role_rejected.rpc_id(id, ...)` if slot is taken
- **Seed guard**: `LobbyManager.start_game` never sends seed=0 — `TerrainGenerator` falls back to `randi()` on seed=0, causing client/server map divergence
- **`global_position` before tree**: always call `add_child` before setting `global_position`. Setting it before add_child silently fails and logs `!is_inside_tree()`.
- **`TeamData` has no `set_points`** — use `sync_from_server(blue, red)` to set both teams at once in tests

---

## Terrain
- `HeightMapShape3D` collision scale: `col_shape.scale = Vector3(step, 1.0, step)` where `step = GRID_SIZE / GRID_STEPS`
- Triangle winding for upward normals (y-up right-handed): `tl→tr→bl` and `tr→br→bl`
- Height application order per vertex: lane flatten → secret path flatten → base zone flatten → plateau lift → peak lift → color

---

## Test Suite

Tests live in `res://tests/`. Run with `make test`. All tests extend `GutTest`. **All tests must pass before any code change is considered complete.**

### Test files

| File | Tier | Tests | What is covered |
|---|---|---|---|
| `tests/test_team_data.gd` | 1 | 13 | `TeamData`: add/spend/get points, sync, guards |
| `tests/test_level_system.gd` | 1 | 27 | `LevelSystem`: XP, level-up, carry-over, MAX_LEVEL cap, attribute spend, bonus stats |
| `tests/test_game_sync.gd` | 1 | 22 | `GameSync`: health get/set/damage/death/respawn, teams, ammo, spawn positions |
| `tests/test_lobby_manager.gd` | 1+2 | 23 | `LobbyManager`: registration, team balance, can_start, role slots, death count, respawn time. 2 known bugs as `pending()` |
| `tests/test_tower_base.gd` | 1 | 33 | `TowerBase`: setup, take_damage, friendly fire, death, XP, `get_fire_position`, `_get_body_team`, composite model assembly, hit-flash, LOS puppet regression |
| `tests/test_minion_base.gd` | 1 | 35 | `MinionBase`: setup, take_damage, death, slow, puppet state, model helpers, waypoints, force_die, target spread, separation, lane offset |
| `tests/test_projectile_base.gd` | 1 | 14 | `ProjectileBase`: initial state, lifetime/expire, gravity, `_on_hit`, friendly fire guard |
| `tests/test_build_system.gd` | 1+2 | 28 | `BuildSystem`: item costs, spacing formula, team-half guard, spacing block/allow, drop spacing, insufficient funds, `PLACEABLE_DEFS` integrity |
| `tests/test_base_player.gd` | 1 | 30 | `BasePlayer`: setup, _ready HitShape contract, _set_alive, update_transform, puppet lerp, avatar loading, hook dispatch, lobby_updated guard |
| `tests/test_player_manager.gd` | 1 | 11 | `PlayerManager`: spawn on first transform, local peer exclusion, no duplicate spawn, remove_player, died/respawned signals, died-before-spawn, respawned-before-spawn, stale-RPC visibility guard, invalid ref no crash |
| `tests/test_multiplayer_integration.gd` | 3 | 19 | ENet loopback (ports 7510–7519): connection, peer detection, seed broadcast, `damage_player`, death signal, respawn, role accept/reject, `sync_lobby_state`, death counts. 3 known bugs as `pending()` |
| `tests/test_multiplayer_rpcs.gd` | 1+2+3 | 71 | Full RPC surface of `LobbyManager`: player registration, role flow, game seed, shot validation, damage, respawn, transform broadcast, minion sync, tower spawn/despawn, team points, ping, lane boosts, recon reveal, level/XP RPCs, ammo reporting. 3 known bugs as `pending()`, 10 smoke tests as `[Risky]` |
| `tests/test_position_visibility_sync.gd` | 1+3 | 30 | Player position broadcast, remote player ghost creation/update, minion puppet sync, tower spawn/despawn visuals, projectile visual RPCs, minimap fog sources, fog overlay source management. 6 known bugs as `pending()`, 2 smoke tests as `[Risky]` |
| `tests/test_machine_gun_tower.gd` | 1 | 20 | `MachineGunTowerAI`: setup, attack_damage, friendly-fire guard, enemy hit, detection sphere, SupporterHUD slot wiring, raycast self-exclude regression, particle lifetime regression, muzzle flash unconditional regression |
| `tests/helpers/MockMultiplayerAPI.gd` | helper | — | `MultiplayerAPIExtension` that logs all RPC calls to `rpc_log`. Helpers: `calls_to()`, `was_called()`, `reset()` |

**Total: 608 passing, 8 pending/risky (all intentional — documented known bugs or no-assert smoke tests)**

### Test tiers
- **Tier 1** — `OfflineMultiplayerPeer`. `multiplayer.is_server()` returns `true`. Server-authoritative code paths run without network guards blocking them.
- **Tier 2** — `MockMultiplayerAPI` RPC dispatch interception for verifying RPC calls without a real network.
- **Tier 3** — Real `ENetMultiplayerPeer` loopback on `127.0.0.1`. Ports 7510–7519. Use `await wait_for_signal(...)` or `await wait_frames(N)` — GUT `simulate()` does NOT pump ENet sockets.

### What the tests DO and DO NOT cover

The tests verify **data plumbing** — signals fire with correct values, state dictionaries update correctly, RPC function bodies execute the right logic. They do **not** verify:
- Visual rendering on a real second Godot client
- That GLB assets, animations, or particle effects display correctly
- Smooth lerp/interpolation of remote player ghosts on screen
- Any audio playback

### Known bugs (documented as `pending()`)
1. **`_roles_pending` never decrements on early disconnect** — `_on_peer_disconnected` checks `role == ""` but initial role is `-1` (int). `all_roles_confirmed` never fires when a player disconnects before picking a role. (`LobbyManager.gd:236-244`)
2. **`notify_player_respawned` ignores bonus HP** — broadcasts flat `PLAYER_MAX_HP` instead of `PLAYER_MAX_HP + LevelSystem.get_bonus_hp(peer_id)`. Clients see wrong HP after respawn for leveled-up players. (`LobbyManager.gd:452-455`)
3. **`request_destroy_tree` uses `call_remote`** — host-fired bullet hits never destroy trees on the host side. (`LobbyManager.gd:694-705`)
4. **`broadcast_player_transform` double-emits on server** — `report_player_transform` calls `broadcast_player_transform` both directly (line 370) and via `.rpc()` (line 371), firing `remote_player_updated` twice on the host. (`LobbyManager.gd:370-371`)
5. **Remote players invisible on minimap** — `BasePlayer` puppet nodes are in group `"players"` but `Minimap` only queries group `"player"`. Remote allies/enemies never appear on the minimap. (`Minimap.gd`)
6. **Minimap fog ignores allied remote player positions** — `_draw_fog_overlay` / `_is_fogged` only clears fog for the local player. Allied positions passed to fog overlay are not used. (`Minimap.gd`)

### Writing new tests
- Place files in `res://tests/`. GUT auto-discovers all `test_*.gd` files in that directory.
- Tier 1: instantiate the class directly, override visuals/audio hooks to no-ops, use `add_child_autofree`.
- Fake nodes that need `Node.get("prop")` to return a value **must** use inner classes with declared properties — not plain `Node3D` with `set()`.
- `@onready` stubs: add stub child nodes in `_init()` so they exist before `@onready` resolves.
- `global_position`: always call `add_child` before setting it.
- `TeamData`: use `sync_from_server(blue, red)` to seed team points, not `set_points` (doesn't exist).
- Use GUT's `watch_signals(obj)` + `get_signal_parameters(obj, "signal_name")` to assert signal arguments — do **not** use `CONNECT_ONE_SHOT` lambdas (causes cross-test signal contamination).
- `call_remote` RPC functions skip local execution entirely under `OfflineMultiplayerPeer` and `MockMultiplayerAPI`. Call the function body directly to test what the receiving peer executes.
- `MockMultiplayerAPI._rpc()` only logs calls, never executes function bodies — always call the function directly alongside `.rpc()` when state assertions are needed.
- After `ENetMultiplayerPeer.close()`, poll both client and server a few frames before nulling the client reference — ENet needs one flush cycle to deliver the disconnect packet.
- Run `make test` and confirm zero failing tests before committing.

---

## Adding New Input Actions
Register in `project.godot` `[input]` section using the existing Object serialization format. Physical keycodes:
- Shift = `4194325`, Ctrl = `4194326`, Tab = `4194320`, Space = `32`
- Mouse button 1 = LMB, button 2 = RMB
