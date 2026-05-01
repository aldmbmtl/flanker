# test_terrain_async.gd
# Tier 1 — unit tests for the async loading behaviour introduced to eliminate
# the game-start freeze.
#
# Covers:
#   - TerrainGenerator: background thread fires, generation_done flag, done signal,
#     secret_paths_cache populated before thread, safe PREDELETE join
#   - TreePlacer: generation_done flag and done signal
#   - WallPlacer: generation_done flag and done signal
#
# All tests run under OfflineMultiplayerPeer (multiplayer.is_server() == true).
# Heavy visual work (mesh creation, GLB instantiation) runs as normal — GUT's
# headless renderer accepts it.  Physics raycasts in TreePlacer / WallPlacer
# simply return empty results when there is no terrain collision shape present,
# which is fine for these data-flow tests.
extends GutTest

const TerrainGeneratorScript := preload("res://scripts/TerrainGenerator.gd")
const TreePlacerScript        := preload("res://scripts/TreePlacer.gd")
const WallPlacerScript        := preload("res://scripts/WallPlacer.gd")

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Minimal TerrainGenerator subclass that skips the expensive per-vertex loops
# so the thread finishes in milliseconds.  All public API (signal, flags,
# secret_paths_cache, PREDELETE handler) is inherited unchanged.
class FastTerrain:
	extends "res://scripts/TerrainGenerator.gd"
	# Replace the full thread payload with a no-op that immediately calls
	# _apply_terrain_data with empty arrays so the done path runs.
	func _build_terrain_data(_seed_val: int, _lane_polylines: Array,
			_secret_paths: Array, _plateaus: Array) -> void:
		var verts_per_side: int = GRID_STEPS + 1
		var step: float = float(GRID_SIZE) / float(GRID_STEPS)
		# Pass empty-but-valid arrays so _apply_terrain_data doesn't crash.
		call_deferred("_apply_terrain_data",
			PackedVector3Array(), PackedVector3Array(),
			PackedColorArray(),   PackedVector2Array(),
			PackedInt32Array(),   PackedFloat32Array(),
			verts_per_side, step,
			1, 0, 0, true)

# Minimal TreePlacer subclass that skips the grid scan — just emits done.
class FastTreePlacer:
	extends "res://scripts/TreePlacer.gd"
	func _place_trees() -> void:
		generation_done = true
		done.emit()
	# Override clearing generation to avoid LaneData calls that assume game world.
	func _generate_random_clearings() -> void:
		pass

# Minimal WallPlacer subclass that skips wall placement — just emits done.
class FastWallPlacer:
	extends "res://scripts/WallPlacer.gd"
	func _place_walls() -> void:
		generation_done = true
		done.emit()
	func _generate_random_clearings() -> void:
		pass

# ─────────────────────────────────────────────────────────────────────────────
# TerrainGenerator tests
# ─────────────────────────────────────────────────────────────────────────────

func test_terrain_generation_done_flag_starts_false() -> void:
	var t := FastTerrain.new()
	# Before add_child, _ready has not run — flag must be false.
	assert_false(t.generation_done, "generation_done should be false before _ready")
	t.free()

func test_terrain_secret_paths_cache_populated_synchronously() -> void:
	# secret_paths_cache is filled in _ready() before the thread starts,
	# so it must be available on the same frame.
	GameSync.game_seed = 42
	var t := FastTerrain.new()
	add_child_autofree(t)
	# _ready() ran — cache must be non-empty (6 secret paths generated).
	assert_gt(t.secret_paths_cache.size(), 0,
		"secret_paths_cache should be populated synchronously in _ready()")

func test_terrain_done_signal_fires() -> void:
	GameSync.game_seed = 42
	var t := FastTerrain.new()
	watch_signals(t)
	add_child_autofree(t)
	# Wait enough frames for the deferred call_deferred(_apply_terrain_data) to run.
	await wait_process_frames(10)
	assert_signal_emitted(t, "done", "TerrainGenerator should emit done after build")

func test_terrain_generation_done_flag_set_after_build() -> void:
	GameSync.game_seed = 42
	var t := FastTerrain.new()
	add_child_autofree(t)
	await wait_process_frames(10)
	assert_true(t.generation_done,
		"generation_done should be true after done signal fires")

func test_terrain_thread_joined_on_predelete_no_crash() -> void:
	# This test verifies the NOTIFICATION_PREDELETE guard: free the node while
	# the thread may still be alive.  If the guard is missing, Godot crashes
	# with signal 11.  A clean exit from this test means the guard works.
	GameSync.game_seed = 99
	var t := FastTerrain.new()
	add_child(t)
	# Free immediately — thread may not have finished yet.
	t.queue_free()
	# Pump frames so the deferred free executes.
	await wait_physics_frames(5)
	# Reaching here without a crash means NOTIFICATION_PREDELETE joined the thread.
	assert_true(true, "Node freed mid-thread without crashing")

func test_terrain_get_secret_paths_returns_cache() -> void:
	GameSync.game_seed = 7
	var t := FastTerrain.new()
	add_child_autofree(t)
	var paths: Array = t.get_secret_paths()
	assert_eq(paths, t.secret_paths_cache,
		"get_secret_paths() should return secret_paths_cache")

func test_terrain_done_not_emitted_before_apply() -> void:
	# generation_done must still be false immediately after add_child (before
	# the deferred _apply_terrain_data runs).
	GameSync.game_seed = 42
	var t := FastTerrain.new()
	watch_signals(t)
	add_child_autofree(t)
	# No frames pumped yet — done should not have fired.
	assert_signal_not_emitted(t, "done",
		"done must not fire synchronously in _ready()")
	assert_false(t.generation_done,
		"generation_done must be false before deferred apply runs")

# ─────────────────────────────────────────────────────────────────────────────
# TreePlacer tests
# ─────────────────────────────────────────────────────────────────────────────

func test_tree_placer_generation_done_starts_false() -> void:
	var tp := FastTreePlacer.new()
	assert_false(tp.generation_done,
		"TreePlacer.generation_done should be false before _ready")
	tp.free()

func test_tree_placer_done_signal_fires() -> void:
	GameSync.game_seed = 1
	var tp := FastTreePlacer.new()
	watch_signals(tp)
	add_child_autofree(tp)
	# _ready awaits 2 process frames then calls _place_trees.
	await wait_physics_frames(5)
	assert_signal_emitted(tp, "done", "TreePlacer should emit done")

func test_tree_placer_generation_done_set_after_done() -> void:
	GameSync.game_seed = 1
	var tp := FastTreePlacer.new()
	add_child_autofree(tp)
	await wait_physics_frames(5)
	assert_true(tp.generation_done,
		"TreePlacer.generation_done should be true after done fires")

func test_tree_placer_done_not_emitted_synchronously() -> void:
	GameSync.game_seed = 1
	var tp := FastTreePlacer.new()
	watch_signals(tp)
	add_child_autofree(tp)
	# 0 frames pumped — must not have fired yet (awaits 2 frames internally).
	assert_signal_not_emitted(tp, "done",
		"TreePlacer done must not fire synchronously in _ready()")

# ─────────────────────────────────────────────────────────────────────────────
# WallPlacer tests
# ─────────────────────────────────────────────────────────────────────────────

func test_wall_placer_generation_done_starts_false() -> void:
	var wp := FastWallPlacer.new()
	assert_false(wp.generation_done,
		"WallPlacer.generation_done should be false before _ready")
	wp.free()

func test_wall_placer_done_signal_fires() -> void:
	GameSync.game_seed = 1
	var wp := FastWallPlacer.new()
	watch_signals(wp)
	add_child_autofree(wp)
	await wait_physics_frames(5)
	assert_signal_emitted(wp, "done", "WallPlacer should emit done")

func test_wall_placer_generation_done_set_after_done() -> void:
	GameSync.game_seed = 1
	var wp := FastWallPlacer.new()
	add_child_autofree(wp)
	await wait_physics_frames(5)
	assert_true(wp.generation_done,
		"WallPlacer.generation_done should be true after done fires")

func test_wall_placer_done_not_emitted_synchronously() -> void:
	GameSync.game_seed = 1
	var wp := FastWallPlacer.new()
	watch_signals(wp)
	add_child_autofree(wp)
	assert_signal_not_emitted(wp, "done",
		"WallPlacer done must not fire synchronously in _ready()")

# ─────────────────────────────────────────────────────────────────────────────
# Plateau ramp tests
# ─────────────────────────────────────────────────────────────────────────────

func test_plateau_ramps_count_equals_plateau_count() -> void:
	# _gen_plateau_ramps must return exactly one ramp per plateau.
	GameSync.game_seed = 42
	var t := TerrainGeneratorScript.new()
	var lane_polylines: Array = []
	for i in range(3):
		lane_polylines.append(LaneData.get_lane_points(i))
	var plateaus: Array = t._gen_plateaus(42, lane_polylines)
	var ramps: Array = t._gen_plateau_ramps(plateaus, 42)
	assert_eq(ramps.size(), plateaus.size(),
		"one ramp per plateau expected")
	t.free()

func test_plateau_ramp_starts_at_plateau_centre() -> void:
	# The first point of each ramp must equal the plateau centre (cx, cz).
	GameSync.game_seed = 123
	var t := TerrainGeneratorScript.new()
	var lane_polylines: Array = []
	for i in range(3):
		lane_polylines.append(LaneData.get_lane_points(i))
	var plateaus: Array = t._gen_plateaus(123, lane_polylines)
	var ramps: Array = t._gen_plateau_ramps(plateaus, 123)
	for idx in range(plateaus.size()):
		var plat: Array = plateaus[idx]
		var ramp: Array = ramps[idx]
		assert_gt(ramp.size(), 0, "ramp must have at least one point")
		var start: Vector2 = ramp[0]
		assert_almost_eq(start.x, plat[0], 0.001,
			"ramp start x must equal plateau cx")
		assert_almost_eq(start.y, plat[1], 0.001,
			"ramp start y must equal plateau cz")
	t.free()

func test_plateau_ramp_has_correct_sample_count() -> void:
	# Each ramp must contain RAMP_SAMPLES+1 = 21 points.
	GameSync.game_seed = 7
	var t := TerrainGeneratorScript.new()
	var lane_polylines: Array = []
	for i in range(3):
		lane_polylines.append(LaneData.get_lane_points(i))
	var plateaus: Array = t._gen_plateaus(7, lane_polylines)
	var ramps: Array = t._gen_plateau_ramps(plateaus, 7)
	for ramp in ramps:
		assert_eq(ramp.size(), 21, "each ramp must have 21 sample points")
	t.free()

func test_plateau_ramps_appended_to_secret_paths() -> void:
	# After _ready(), secret_paths_cache should contain the original secret
	# paths PLUS one ramp per plateau.
	GameSync.game_seed = 55
	# Use real TerrainGenerator (non-fast) to call real _ready() but we only
	# need _ready to run synchronously for the cache — use FastTerrain which
	# still runs the full _ready() preamble, just skips mesh build.
	var t := FastTerrain.new()
	add_child_autofree(t)
	# secret_paths_cache is set synchronously — no need to await.
	var lane_polylines: Array = []
	for i in range(3):
		lane_polylines.append(LaneData.get_lane_points(i))
	var plateaus: Array = t._gen_plateaus(55, lane_polylines)
	# 6 secret paths (2 sides × 3 each) + one per plateau
	var expected_min: int = 6 + plateaus.size()
	assert_gte(t.secret_paths_cache.size(), expected_min,
		"secret_paths_cache must contain secret paths + plateau ramps")

func test_plateau_ramp_endpoint_outside_plateau_blend() -> void:
	# The last ramp point must be farther from plateau centre than
	# (max(rx,rz) + PLATEAU_BLEND), ensuring it exits the plateau blend zone.
	GameSync.game_seed = 99
	var t := TerrainGeneratorScript.new()
	var lane_polylines: Array = []
	for i in range(3):
		lane_polylines.append(LaneData.get_lane_points(i))
	var plateaus: Array = t._gen_plateaus(99, lane_polylines)
	var ramps: Array = t._gen_plateau_ramps(plateaus, 99)
	var plateau_blend: float = t.PLATEAU_BLEND
	for idx in range(plateaus.size()):
		var plat: Array = plateaus[idx]
		var ramp: Array = ramps[idx]
		var end_pt: Vector2 = ramp[ramp.size() - 1]
		var centre := Vector2(plat[0], plat[1])
		var dist: float = centre.distance_to(end_pt)
		var min_dist: float = max(plat[2], plat[3]) + plateau_blend
		assert_gt(dist, min_dist,
			"ramp endpoint must exit the plateau blend zone")
	t.free()

func test_plateau_weight_callable_regression() -> void:
	# Regression: a bad edit once concatenated the _plateau_weight func signature
	# with the first line of its body, causing a parse error that prevented
	# TerrainGenerator.gd (and anything preloading it, e.g. StartMenu.gd) from
	# loading at all.  This test verifies _plateau_weight is callable and returns
	# a sensible value so a recurrence would be caught immediately.
	var t := TerrainGeneratorScript.new()
	# Inside the plateau centre — weight must be 1.0
	var plat: Array = [0.0, 0.0, 10.0, 8.0, 6.0]
	var w_inside: float = t._plateau_weight(Vector2(0.0, 0.0), plat)
	assert_almost_eq(w_inside, 1.0, 0.001,
		"_plateau_weight must return 1.0 at plateau centre")
	# Far outside — weight must be 0.0
	var w_outside: float = t._plateau_weight(Vector2(100.0, 100.0), plat)
	assert_almost_eq(w_outside, 0.0, 0.001,
		"_plateau_weight must return 0.0 far outside plateau")
	t.free()
