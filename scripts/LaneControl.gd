extends Node
## LaneControl — server-authoritative territory system.
## Tracks per-team push levels and timers. When a team holds all 3 lane
## frontmost enemy minions past the current build limit for PUSH_TIME seconds,
## the build limit advances one step into enemy territory (up to MAX_PUSH steps).
## When the losing team holds all lanes back for ROLLBACK_TIME seconds, the
## limit retreats one step and any towers past the new limit are destroyed.
##
## Symmetrical: both teams can push the other's build limit.

# Push limit z-values indexed by push_level [0..3].
# Blue (team 0): limits move in -z direction (toward red base at z=-82).
# Red  (team 1): limits move in +z direction (toward blue base at z=+82).
const PUSH_LIMITS_BLUE: Array = [0.0, -13.7, -27.4, -41.0]
const PUSH_LIMITS_RED:  Array = [0.0, +13.7, +27.4, +41.0]

const MAX_PUSH:       int   = 3
const PUSH_TIME:      float = 120.0
const ROLLBACK_TIME:  float = 60.0

# Lane assignment proximity threshold — minion must be within this many units
# of a lane polyline to be counted for that lane's push condition.
const LANE_ASSIGN_DIST: float = 15.0

# Per-team state arrays  [team_0_val, team_1_val]
var push_level:      Array = [0, 0]
var push_timer:      Array = [0.0, 0.0]
var rollback_timer:  Array = [0.0, 0.0]

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

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _is_authority():
		return
	_tick_team(0, delta)
	_tick_team(1, delta)

func _is_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true  # singleplayer
	return multiplayer.is_server()

func _tick_team(t: int, delta: float) -> void:
	# Push condition: minions from team t have crossed team t's OWN build limit
	# into enemy territory.
	# t=0 (blue): blue's limit starts at z=0 and moves negative. Blue minions are
	#   "in enemy territory" when z < get_build_limit(0).
	# t=1 (red):  red's limit starts at z=0 and moves positive. Red minions are
	#   "in enemy territory" when z > get_build_limit(1).
	var own_limit_z: float = get_build_limit(t)

	# --- Find deepest own minion per lane (furthest into enemy territory) ---
	# t=0: deepest = most negative z (min z)
	# t=1: deepest = most positive z (max z)
	var frontmost_z: Array = [INF if t == 0 else -INF,
	                          INF if t == 0 else -INF,
	                          INF if t == 0 else -INF]
	var lane_has_minion: Array = [false, false, false]

	for minion in get_tree().get_nodes_in_group("minions"):
		if minion.get("team") != t:
			continue
		var mpos: Vector3 = minion.global_position
		var mp := Vector2(mpos.x, mpos.z)
		var best_lane: int = -1
		var best_dist: float = LANE_ASSIGN_DIST
		for lane_i in range(3):
			var pts: Array = LaneData.get_lane_points(lane_i)
			var d: float = LaneData.dist_to_polyline(mp, pts)
			if d < best_dist:
				best_dist = d
				best_lane = lane_i
		if best_lane == -1:
			continue
		# Track deepest (most into enemy territory) minion per lane
		if t == 0:
			if mpos.z < frontmost_z[best_lane]:
				frontmost_z[best_lane] = mpos.z
				lane_has_minion[best_lane] = true
		else:
			if mpos.z > frontmost_z[best_lane]:
				frontmost_z[best_lane] = mpos.z
				lane_has_minion[best_lane] = true

	# --- Push condition: all 3 lanes have own minions past own build limit ---
	# t=0: minion z < own_limit_z  (into negative/red side)
	# t=1: minion z > own_limit_z  (into positive/blue side)
	var all_pushed: bool = true
	for lane_i in range(3):
		if not lane_has_minion[lane_i]:
			all_pushed = false
			break
		var past: bool = (t == 0 and frontmost_z[lane_i] < own_limit_z) or \
		                 (t == 1 and frontmost_z[lane_i] > own_limit_z)
		if not past:
			all_pushed = false
			break

	# --- Push timer ---
	if all_pushed:
		push_timer[t] = minf(push_timer[t] + delta, PUSH_TIME)
	else:
		push_timer[t] = 0.0

	if push_timer[t] >= PUSH_TIME and push_level[t] < MAX_PUSH:
		push_level[t] += 1
		push_timer[t] = 0.0
		rollback_timer[t] = 0.0
		_broadcast(t)

	# --- Rollback condition: no own minions past own limit in any lane ---
	var all_clear: bool = true
	if push_level[t] == 0:
		all_clear = false  # nothing to roll back
	else:
		var cur_limit: float = get_build_limit(t)
		for lane_i in range(3):
			if not lane_has_minion[lane_i]:
				continue
			var still_past: bool = (t == 0 and frontmost_z[lane_i] < cur_limit) or \
			                       (t == 1 and frontmost_z[lane_i] > cur_limit)
			if still_past:
				all_clear = false
				break

	if all_clear and push_level[t] > 0:
		rollback_timer[t] = minf(rollback_timer[t] + delta, ROLLBACK_TIME)
	else:
		rollback_timer[t] = 0.0

	if rollback_timer[t] >= ROLLBACK_TIME and push_level[t] > 0:
		push_level[t] -= 1
		rollback_timer[t] = 0.0
		push_timer[t] = 0.0
		_broadcast(t)
		_destroy_towers_outside_limit(t)

# ── Internal helpers ──────────────────────────────────────────────────────────

func _destroy_towers_outside_limit(team: int) -> void:
	var limit_z: float = get_build_limit(team)
	for tower in get_tree().get_nodes_in_group("towers"):
		if tower.get("team") != team:
			continue
		var tz: float = tower.global_position.z
		var outside: bool = (team == 0 and tz < limit_z) or \
		                    (team == 1 and tz > limit_z)
		if outside:
			tower.call("_die")

func _broadcast(team: int) -> void:
	if multiplayer.has_multiplayer_peer():
		sync_limit_state.rpc(team, push_level[team], push_timer[team], rollback_timer[team])
	build_limit_changed.emit(team, get_build_limit(team), push_level[team])

# ── RPC sync ──────────────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func sync_limit_state(team: int, level: int, p_timer: float, r_timer: float) -> void:
	push_level[team]     = level
	push_timer[team]     = p_timer
	rollback_timer[team] = r_timer
	build_limit_changed.emit(team, get_build_limit(team), level)
