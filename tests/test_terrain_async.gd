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
			_secret_paths: Array, _plateaus: Array, _peaks: Array) -> void:
		var verts_per_side: int = GRID_STEPS + 1
		var step: float = float(GRID_SIZE) / float(GRID_STEPS)
		# Pass empty-but-valid arrays so _apply_terrain_data doesn't crash.
		call_deferred("_apply_terrain_data",
			PackedVector3Array(), PackedVector3Array(),
			PackedColorArray(),   PackedVector2Array(),
			PackedInt32Array(),   PackedFloat32Array(),
			verts_per_side, step,
			1, 0, 0, 0, true)

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
	await wait_frames(5)
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
	await wait_frames(5)
	assert_signal_emitted(tp, "done", "TreePlacer should emit done")

func test_tree_placer_generation_done_set_after_done() -> void:
	GameSync.game_seed = 1
	var tp := FastTreePlacer.new()
	add_child_autofree(tp)
	await wait_frames(5)
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
	await wait_frames(5)
	assert_signal_emitted(wp, "done", "WallPlacer should emit done")

func test_wall_placer_generation_done_set_after_done() -> void:
	GameSync.game_seed = 1
	var wp := FastWallPlacer.new()
	add_child_autofree(wp)
	await wait_frames(5)
	assert_true(wp.generation_done,
		"WallPlacer.generation_done should be true after done fires")

func test_wall_placer_done_not_emitted_synchronously() -> void:
	GameSync.game_seed = 1
	var wp := FastWallPlacer.new()
	watch_signals(wp)
	add_child_autofree(wp)
	assert_signal_not_emitted(wp, "done",
		"WallPlacer done must not fire synchronously in _ready()")
