extends Node
## LaneControl — territory state mirror.
## Python is authoritative for push/rollback simulation.
## Godot receives sync_limit_state messages via BridgeClient and stores them here
## so BuildSystem and HUD can query get_build_limit() locally without bridging.

const PUSH_LIMITS_BLUE: Array = [0.0, -13.7, -27.4, -41.0]
const PUSH_LIMITS_RED:  Array = [0.0, +13.7, +27.4, +41.0]
const MAX_PUSH: int = 3

var push_level: Array = [0, 0]
## push_timer[team] — seconds the enemy (team) has been past our limit.
## Populated by sync_limit_state from the Python server.
## 0.0 when no push is active.
var push_timer: Array = [0.0, 0.0]
## rollback_timer[team] — seconds until an active rollback completes.
var rollback_timer: Array = [0.0, 0.0]

signal build_limit_changed(team: int, new_z: float, new_level: int)

# ── Public API ────────────────────────────────────────────────────────────────

func get_build_limit(team: int) -> float:
	if team == 0:
		return PUSH_LIMITS_BLUE[push_level[0]]
	else:
		return PUSH_LIMITS_RED[push_level[1]]

func reset() -> void:
	push_level    = [0, 0]
	push_timer    = [0.0, 0.0]
	rollback_timer = [0.0, 0.0]

# ── Inbound mirror (called by BridgeClient on sync_limit_state) ───────────────

func sync_limit_state(team: int, level: int, p_timer: float, r_timer: float) -> void:
	push_level[team]    = level
	push_timer[team]    = p_timer
	rollback_timer[team] = r_timer
	build_limit_changed.emit(team, get_build_limit(team), level)
