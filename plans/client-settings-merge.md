# Flanker — ClientSettings Merge Plan

**Created:** 2026-05-03  
**Status:** Complete  
**Author:** Conversation with OpenCode  

---

## Goal

Consolidate the two client-side settings autoloads (`GameSettings` and `GraphicsSettings`)
into a single `ClientSettings` autoload. Remove the dead `GameSettingsDialog.gd`.

Old save files (`user://game_settings.cfg`, `user://graphics.cfg`) are abandoned —
users receive fresh defaults on first run after this change.

---

## Changes Made

### New file
- `scripts/ClientSettings.gd` — merged autoload. Single save path: `user://client_settings.cfg`.
  Exposes all fields from both old autoloads plus the `settings_changed` signal.

### Deleted files
| File | Reason |
|---|---|
| `scripts/GameSettings.gd` | Merged into `ClientSettings` |
| `scripts/ui/GraphicsSettings.gd` | Merged into `ClientSettings` |
| `scripts/ui/GameSettingsDialog.gd` | Already dead — no scene or script referenced it |
| `tests/test_graphics_settings.gd` | Replaced by `tests/test_client_settings.gd` |

### Updated call sites (8 scripts)
- `scripts/ui/StartMenu.gd`
- `scripts/ui/SettingsPanel.gd`
- `scripts/roles/fighter/FPSController.gd`
- `scripts/Main.gd`
- `scripts/TreePlacer.gd`
- `scripts/TeamLives.gd`

All `GameSettings.*` and `GraphicsSettings.*` references replaced with `ClientSettings.*`.

### Updated tests (3 files)
- `tests/test_client_settings.gd` (renamed from `test_graphics_settings.gd`) — updated load path
- `tests/test_player_username.gd` — `GameSettings.*` → `ClientSettings.*`
- `tests/test_autoload_reset.gd` — `GameSettings.lives_per_team` → `ClientSettings.lives_per_team`

### `project.godot`
- Removed `GraphicsSettings` and `GameSettings` autoload entries
- Added `ClientSettings="*res://scripts/ClientSettings.gd"`

---

## API surface (unchanged externally)

All public fields, methods, and signals are identical to the union of the two old autoloads:

```
ClientSettings.lives_per_team           (was GameSettings.lives_per_team)
ClientSettings.player_name              (was GameSettings.player_name)
ClientSettings.fog_enabled              (was GraphicsSettings.fog_enabled)
ClientSettings.fog_density_multiplier   (was GraphicsSettings.fog_density_multiplier)
ClientSettings.dof_enabled              (was GraphicsSettings.dof_enabled)
ClientSettings.dof_blur_amount          (was GraphicsSettings.dof_blur_amount)
ClientSettings.shadow_quality           (was GraphicsSettings.shadow_quality)
ClientSettings.tree_shadow_distance     (was GraphicsSettings.tree_shadow_distance)
ClientSettings.apply(...)               (was GraphicsSettings.apply(...))
ClientSettings.restore_defaults()       (was GraphicsSettings.restore_defaults())
ClientSettings.get_fog_density(ts)      (was GraphicsSettings.get_fog_density(ts))
ClientSettings.get_vol_fog_density(ts)  (was GraphicsSettings.get_vol_fog_density(ts))
ClientSettings.save_settings()          (was GameSettings.save_settings() or GraphicsSettings implied)
ClientSettings.load_settings()          (was GameSettings.load_settings())
ClientSettings.settings_changed         (was GraphicsSettings.settings_changed)
```
