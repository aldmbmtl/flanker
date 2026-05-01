# test_lane_control.gd
# Tier 1 — unit tests for LaneControl territory push/rollback system.
# LaneControl is an autoload — we call reset() in before_each to get clean state.
# LaneData requires GameSync.game_seed; we set it to a fixed value so lanes generate.
#
# Push condition: team t's OWN minions past team t's OWN build limit into enemy territory.
#   t=0 (blue): blue minions at z < get_build_limit(0)  (into red/negative side)
#   t=1 (red):  red minions  at z > get_build_limit(1)  (into blue/positive side)
#   _place_all_lanes_pushed(own_team) places own_team minions past their own limit.
extends GutTest

# ── Fake nodes ────────────────────────────────────────────────────────────────

class FakeMinion extends Node3D:
	var team: int = 0

class FakeTower extends Node3D:
	var team: int = 0
	var _die_called: bool = false
	func _die() -> void:
		_die_called = true
		queue_free()

# ── Helpers ───────────────────────────────────────────────────────────────────

# Add a minion for the given team at world position.
func _add_minion(team: int, pos: Vector3) -> FakeMinion:
	var m := FakeMinion.new()
	m.team = team
	add_child_autofree(m)
	m.global_position = pos
	m.add_to_group("minions")
	return m

# Add a tower for the given team at world position.
func _add_tower(team: int, pos: Vector3) -> FakeTower:
	var t := FakeTower.new()
	t.team = team
	add_child_autofree(t)
	t.global_position = pos
	t.add_to_group("towers")
	return t

# Place one minion per lane for `own_team` past that team's OWN build limit
# into enemy territory. Queries actual lane sample points to guarantee lane assignment.
# t=0 (blue): minions placed at z < get_build_limit(0)  (negative = red's side)
# t=1 (red):  minions placed at z > get_build_limit(1)  (positive = blue's side)
func _place_all_lanes_pushed(own_team: int, margin: float = 5.0) -> Array:
	var own_limit_z: float = LaneControl.get_build_limit(own_team)
	var minions: Array = []
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		var best_pt: Vector2 = Vector2.ZERO
		var best_dist: float = INF
		for pt in pts:
			var pt2: Vector2 = pt as Vector2
			var past: bool
			if own_team == 0:
				past = pt2.y < own_limit_z - margin   # into red's side (negative z)
			else:
				past = pt2.y > own_limit_z + margin   # into blue's side (positive z)
			if past:
				var dist_to_limit: float = abs(pt2.y - own_limit_z)
				if dist_to_limit < best_dist:
					best_dist = dist_to_limit
					best_pt = pt2
		if best_pt == Vector2.ZERO:
			var z_val: float = (own_limit_z - 20.0) if own_team == 0 else (own_limit_z + 20.0)
			best_pt = Vector2(0.0 if lane_i == 1 else (-85.0 if lane_i == 0 else 85.0), z_val)
		minions.append(_add_minion(own_team, Vector3(best_pt.x, 1.0, best_pt.y)))
	return minions

# Tick LaneControl for team t for `seconds` in `steps` increments.
func _tick_team_for(t: int, seconds: float, steps: int = 10) -> void:
	var dt: float = seconds / float(steps)
	for _i in range(steps):
		LaneControl._tick_team(t, dt)

# ── Setup / teardown ──────────────────────────────────────────────────────────

func before_each() -> void:
	LaneControl.reset()
	# Ensure LaneData is initialized with a deterministic seed
	GameSync.game_seed = 42
	LaneData.regenerate_for_new_game()

# ── 1. Initial state ──────────────────────────────────────────────────────────

func test_initial_push_level_both_teams_zero() -> void:
	assert_eq(LaneControl.push_level[0], 0)
	assert_eq(LaneControl.push_level[1], 0)

func test_initial_timers_all_zero() -> void:
	assert_eq(LaneControl.push_timer[0], 0.0)
	assert_eq(LaneControl.push_timer[1], 0.0)
	assert_eq(LaneControl.rollback_timer[0], 0.0)
	assert_eq(LaneControl.rollback_timer[1], 0.0)

func test_initial_build_limit_returns_zero_both_teams() -> void:
	assert_eq(LaneControl.get_build_limit(0), 0.0)
	assert_eq(LaneControl.get_build_limit(1), 0.0)

# ── 2. Push timer accumulates ─────────────────────────────────────────────────

func test_push_timer_accumulates_while_condition_true() -> void:
	# Blue minions past blue's own limit (z=0) into red's territory (z < 0)
	_place_all_lanes_pushed(0)
	_tick_team_for(0, 30.0)
	assert_almost_eq(LaneControl.push_timer[0], 30.0, 0.01)

# ── 3. Push timer resets when condition breaks ─────────────────────────────────

func test_push_timer_resets_when_condition_breaks() -> void:
	_place_all_lanes_pushed(0)
	_tick_team_for(0, 30.0)
	# Remove all minions and tick again — timer should reset
	for m in get_tree().get_nodes_in_group("minions"):
		m.queue_free()
	# Wait one frame for queue_free to process
	await get_tree().process_frame
	_tick_team_for(0, 5.0)
	assert_eq(LaneControl.push_timer[0], 0.0)

# ── 4. Push level advances at PUSH_TIME ───────────────────────────────────────

func test_push_level_advances_to_1_after_push_time() -> void:
	_place_all_lanes_pushed(0)
	_tick_team_for(0, LaneControl.PUSH_TIME + 1.0, 200)
	assert_eq(LaneControl.push_level[0], 1)

# ── 5. get_build_limit returns correct z at push level 1 ──────────────────────

func test_get_build_limit_team0_push1_returns_minus_13_7() -> void:
	LaneControl.push_level[0] = 1
	assert_almost_eq(LaneControl.get_build_limit(0), -13.7, 0.01)

func test_get_build_limit_team1_push1_returns_plus_13_7() -> void:
	LaneControl.push_level[1] = 1
	assert_almost_eq(LaneControl.get_build_limit(1), 13.7, 0.01)

func test_get_build_limit_team0_push3_returns_minus_41() -> void:
	LaneControl.push_level[0] = 3
	assert_almost_eq(LaneControl.get_build_limit(0), -41.0, 0.01)

# ── 6. Push level caps at MAX_PUSH ────────────────────────────────────────────

func test_push_level_caps_at_max_push() -> void:
	LaneControl.push_level[0] = LaneControl.MAX_PUSH
	_place_all_lanes_pushed(0)
	_tick_team_for(0, LaneControl.PUSH_TIME + 1.0, 200)
	assert_eq(LaneControl.push_level[0], LaneControl.MAX_PUSH,
		"Push level must not exceed MAX_PUSH")

# ── 7. build_limit_changed signal fires on push ───────────────────────────────

func test_build_limit_changed_signal_fires_on_push() -> void:
	watch_signals(LaneControl)
	_place_all_lanes_pushed(0)
	_tick_team_for(0, LaneControl.PUSH_TIME + 1.0, 200)
	assert_signal_emitted(LaneControl, "build_limit_changed")
	var params: Array = get_signal_parameters(LaneControl, "build_limit_changed")
	assert_eq(params[0], 0)                      # team
	assert_almost_eq(params[1], -13.7, 0.01)    # new_z
	assert_eq(params[2], 1)                      # new_level

# ── 8. Rollback timer accumulates when lanes clear ────────────────────────────

func test_rollback_timer_accumulates_when_lanes_clear() -> void:
	LaneControl.push_level[0] = 1
	# No enemy minions past limit — lanes are clear
	_tick_team_for(0, 30.0)
	assert_almost_eq(LaneControl.rollback_timer[0], 30.0, 0.01)

# ── 9. Rollback timer resets when condition breaks ────────────────────────────

func test_rollback_timer_resets_when_enemy_returns() -> void:
	LaneControl.push_level[0] = 1
	_tick_team_for(0, 20.0)
	# Blue minions push past limit again — rollback timer should reset
	_place_all_lanes_pushed(0)
	_tick_team_for(0, 10.0)
	assert_eq(LaneControl.rollback_timer[0], 0.0)

# ── 10. Rollback decrements by exactly 1 ─────────────────────────────────────

func test_rollback_decrements_push_level_by_one_only() -> void:
	LaneControl.push_level[0] = 2
	_tick_team_for(0, LaneControl.ROLLBACK_TIME + 1.0, 200)
	assert_eq(LaneControl.push_level[0], 1,
		"Rollback must decrement by exactly 1, not more")

# ── 11. Rollback does not go below 0 ─────────────────────────────────────────

func test_rollback_does_not_go_below_zero() -> void:
	LaneControl.push_level[0] = 0
	# Attempt rollback — rollback condition requires push_level > 0 so timer won't run
	_tick_team_for(0, LaneControl.ROLLBACK_TIME + 1.0, 200)
	assert_eq(LaneControl.push_level[0], 0,
		"Push level must not go below 0")

# ── 12. _destroy_towers_outside_limit destroys towers past limit (team 0) ─────

func test_destroy_towers_outside_limit_team0() -> void:
	LaneControl.push_level[0] = 1   # limit = z=-13.7
	# Tower at z=-20 is past limit (outside for team 0)
	var t_outside: FakeTower = _add_tower(0, Vector3(0.0, 0.0, -20.0))
	# Tower at z=-5 is inside limit (safe)
	var t_inside: FakeTower = _add_tower(0, Vector3(0.0, 0.0, -5.0))
	LaneControl._destroy_towers_outside_limit(0)
	assert_true(t_outside._die_called,
		"Tower at z=-20 (past limit z=-13.7) should be destroyed on rollback")

# ── 13. _destroy_towers_outside_limit spares towers inside limit ──────────────

func test_destroy_towers_spares_inside_limit_team0() -> void:
	LaneControl.push_level[0] = 1   # limit = z=-13.7
	var t_inside: FakeTower = _add_tower(0, Vector3(0.0, 0.0, -5.0))
	LaneControl._destroy_towers_outside_limit(0)
	assert_false(t_inside._die_called,
		"Tower at z=-5 (inside limit z=-13.7) must NOT be destroyed")

# ── 14. Red team (team 1) symmetry ───────────────────────────────────────────

func test_red_team_push_level_advances_symmetrically() -> void:
	# Red minions past red's own limit (z=0) into blue's territory (z > 0)
	_place_all_lanes_pushed(1)
	_tick_team_for(1, LaneControl.PUSH_TIME + 1.0, 200)
	assert_eq(LaneControl.push_level[1], 1,
		"Red team push level should advance to 1 symmetrically")
	assert_almost_eq(LaneControl.get_build_limit(1), 13.7, 0.01,
		"Red team limit at push 1 should be z=+13.7")

func test_red_team_rollback_destroys_towers_past_limit() -> void:
	LaneControl.push_level[1] = 1   # red limit = z=+13.7
	# Red tower at z=+20 is past limit for red (outside = z > 13.7)
	var t_outside: FakeTower = _add_tower(1, Vector3(0.0, 0.0, 20.0))
	# Red tower at z=+5 is inside limit (safe)
	var t_inside: FakeTower = _add_tower(1, Vector3(0.0, 0.0, 5.0))
	LaneControl._destroy_towers_outside_limit(1)
	assert_true(t_outside._die_called,
		"Red tower at z=+20 (past limit z=+13.7) should be destroyed on rollback")
	assert_false(t_inside._die_called,
		"Red tower at z=+5 (inside limit z=+13.7) must NOT be destroyed")
