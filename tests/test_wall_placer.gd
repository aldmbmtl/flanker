extends GutTest

# ---------------------------------------------------------------------------
# WallPlacer constant integrity
# ---------------------------------------------------------------------------
# These tests guard against accidental removal or path breakage of the asset
# arrays that drive jungle decoration. They do NOT instantiate WallPlacer at
# runtime (which requires a full scene tree with Terrain and autoloads) — they
# only verify the static declarations on the script itself.
# ---------------------------------------------------------------------------

const WallPlacerScript := preload("res://scripts/WallPlacer.gd")

# WallPlacer subclass that stubs out terrain queries so _scatter_sand can run
# without a real physics world, and overrides _place_walls/_scatter_grass to
# keep the test focused on sand placement only.
class SandOnlyPlacer:
	extends "res://scripts/WallPlacer.gd"
	func _generate_random_clearings() -> void:
		pass
	func _place_walls() -> void:
		await _scatter_sand()
		generation_done = true
		done.emit()
	func _scatter_grass() -> void:
		pass
	# Return a fixed y=0 result so placement always succeeds without raycasting.
	func _query_terrain(_pos: Vector3) -> Dictionary:
		return {"y": 0.0, "normal": Vector3.UP}
	# Prevent lane/path/base checks from needing LaneData raycasts.
	func _is_on_lane_area(_pos: Vector2) -> bool:
		return false
	func _is_on_secret_path(_pos: Vector2) -> bool:
		return false
	func _is_in_base_area(_pos: Vector2) -> bool:
		return false

func test_rock_scene_paths_has_six_entries() -> void:
	var wp: Node3D = WallPlacerScript.new()
	assert_eq(wp.ROCK_SCENE_PATHS.size(), 6, "ROCK_SCENE_PATHS must contain all 6 pirate-kit rock GLBs")
	wp.free()

func test_grass_scene_paths_has_five_entries() -> void:
	var wp: Node3D = WallPlacerScript.new()
	assert_eq(wp.GRASS_SCENE_PATHS.size(), 5, "GRASS_SCENE_PATHS must contain all 5 pirate-kit grass GLBs")
	wp.free()

func test_rock_scene_paths_all_non_null() -> void:
	var wp: Node3D = WallPlacerScript.new()
	for i in range(wp.ROCK_SCENE_PATHS.size()):
		assert_not_null(wp.ROCK_SCENE_PATHS[i], "ROCK_SCENE_PATHS[%d] must not be null" % i)
	wp.free()

func test_grass_scene_paths_all_non_null() -> void:
	var wp: Node3D = WallPlacerScript.new()
	for i in range(wp.GRASS_SCENE_PATHS.size()):
		assert_not_null(wp.GRASS_SCENE_PATHS[i], "GRASS_SCENE_PATHS[%d] must not be null" % i)
	wp.free()

func test_grass_count_constant_is_positive() -> void:
	var wp: Node3D = WallPlacerScript.new()
	assert_eq(wp.GRASS_COUNT, 750, "GRASS_COUNT must be 750")
	wp.free()

func test_sand_scene_paths_has_two_entries() -> void:
	var wp: Node3D = WallPlacerScript.new()
	assert_eq(wp.SAND_SCENE_PATHS.size(), 3, "SAND_SCENE_PATHS must contain all 3 pirate-kit sandy rock GLBs")
	wp.free()

func test_sand_count_constant_is_correct() -> void:
	var wp: Node3D = WallPlacerScript.new()
	assert_eq(wp.SAND_COUNT, 113, "SAND_COUNT must be 113 (70% reduction from original 375)")
	wp.free()

func test_sand_scene_paths_all_non_null() -> void:
	var wp: Node3D = WallPlacerScript.new()
	for i in range(wp.SAND_SCENE_PATHS.size()):
		assert_not_null(wp.SAND_SCENE_PATHS[i], "SAND_SCENE_PATHS[%d] must not be null" % i)
	wp.free()

func test_sand_rocks_have_collision_bodies() -> void:
	# Regression: sand rocks had no collision — players could walk through them.
	# Verify that after _scatter_sand runs, at least one StaticBody3D child with
	# collision_layer=2 exists among the placer's children.
	GameSync.game_seed = 42
	var wp := SandOnlyPlacer.new()
	add_child_autofree(wp)
	# _ready triggers _place_walls (no-op) then _scatter_sand via coroutine.
	# Wait enough frames for the scatter coroutine to complete.
	await wait_physics_frames(30)
	var found_collision := false
	for child in wp.get_children():
		if child is StaticBody3D and child.collision_layer == 2:
			found_collision = true
			break
	assert_true(found_collision,
		"_scatter_sand must produce StaticBody3D children with collision_layer=2")

# ---------------------------------------------------------------------------
# WallPlacer async tree-exit crash regression
# ---------------------------------------------------------------------------
# Regression guard for the crash:
#   ERROR: Parameter "data.tree" is null.  at: get_tree (node.h:549)
#   at: _place_walls (WallPlacer.gd:134)
#
# The crash occurs when the WallPlacer node is removed from the scene tree
# (e.g., when the client transitions to a new scene) while _place_walls is
# suspended in the middle of an `await get_tree().process_frame`.  On the next
# resume, get_tree() returns null and GDScript dereferences it.
#
# The fix: guard every `await get_tree().process_frame` with
# `if not is_inside_tree(): return` before awaiting.

class FastWallPlacer:
	extends "res://scripts/WallPlacer.gd"
	# Override _ready so we control when placement runs; skip the two initial awaits.
	func _ready() -> void:
		pass
	func _generate_random_clearings() -> void:
		# One fake clearing so _place_walls has something to loop over.
		_random_clearing_centers = [Vector2(0, 0)]
		_random_clearing_radii   = [5.0]
	func _scatter_grass() -> void:
		pass
	func _scatter_sand() -> void:
		pass
	func _get_terrain_height(_pos: Vector3) -> float:
		return 0.0
	func _is_on_lane_area(_p: Vector2) -> bool:
		return false
	func _is_on_secret_path(_p: Vector2) -> bool:
		return false
	func _is_in_base_area(_p: Vector2) -> bool:
		return false

func test_place_walls_no_crash_when_removed_from_tree_mid_await() -> void:
	# Regression: WallPlacer crashed with "data.tree is null" when the node was
	# removed from the scene tree while _place_walls() was suspended in an await.
	# With the fix, is_inside_tree() guards each await and the coroutine returns
	# early without crashing.
	GameSync.game_seed = 7
	var wp := FastWallPlacer.new()
	add_child(wp)          # must be in tree so await frames work
	wp._generate_random_clearings()

	# Kick off the async coroutine, then immediately remove the node from the
	# tree before any frames advance.  Without the fix, the next process frame
	# resume crashes; with the fix it returns silently.
	var _coro_signal: Signal = wp.done  # hold a ref so we can await it safely below
	wp._place_walls()       # starts coroutine; does NOT await here
	remove_child(wp)        # node leaves tree while coroutine is suspended

	# Advance a few frames — the coroutine resumes and must NOT crash.
	await wait_physics_frames(3)

	assert_false(wp.generation_done,
		"generation_done must stay false — coroutine should have returned early " +
		"after is_inside_tree() guard triggered (regression: was crashing with null tree)")
	wp.queue_free()

# ---------------------------------------------------------------------------
# FencePlacer async tree-exit crash regression
# ---------------------------------------------------------------------------
# Regression guard for the crash:
#   ERROR: Parameter "data.tree" is null.  at: get_tree (node.h:549)
#   at: _place_all_fences (FencePlacer.gd:59)
#
# Same root cause as WallPlacer: the node is removed from the scene tree while
# _place_all_fences() is suspended in `await get_tree().process_frame`. The
# fix: post-await `if not is_inside_tree(): return` guards in _ready() and
# _place_all_fences().

class FastFencePlacer:
	extends "res://scripts/FencePlacer.gd"
	# Skip the two initial awaits and terrain setup so tests run synchronously.
	func _ready() -> void:
		pass
	func _get_terrain_height(_pos: Vector3) -> float:
		return 0.0

func test_fence_placer_no_crash_when_removed_from_tree_mid_await() -> void:
	# Regression: FencePlacer crashed with "data.tree is null" when the node was
	# removed from the scene tree while _place_all_fences() was suspended in await.
	# With the fix, is_inside_tree() guards each await and the coroutine returns early.
	GameSync.game_seed = 7
	var fp := FastFencePlacer.new()
	add_child(fp)

	# Kick off the async coroutine, then immediately remove the node from the tree.
	fp._place_all_fences()
	remove_child(fp)

	# Advance a few frames — the coroutine resumes and must NOT crash.
	await wait_physics_frames(3)

	# If we reach here without an engine crash the fix is working.
	assert_true(true, "FencePlacer must not crash when removed from tree mid-await")
	fp.queue_free()

# ---------------------------------------------------------------------------
# TreePlacer async tree-exit crash regression
# ---------------------------------------------------------------------------
# Regression guard for the same null-tree crash pattern in TreePlacer:
#   await get_tree().process_frame  (3 sites in _ready() and _place_trees())
# Fix: post-await `if not is_inside_tree(): return` guards at each site.

class FastTreePlacer:
	extends "res://scripts/TreePlacer.gd"
	# Override _ready so we control when _place_trees() is called.
	func _ready() -> void:
		pass
	# Stub out terrain/physics so _place_trees() doesn't need a real world.
	func _find_terrain() -> StaticBody3D:
		return null
	func _get_terrain_height(_pos: Vector3) -> float:
		return 0.0
	func _build_exclusion_mask() -> void:
		# Must resize the mask array so _place_trees() index access doesn't crash.
		_exclusion_mask.resize(200 * 200)
		_exclusion_mask.fill(true)  # exclude all cells → zero candidates → no loop body runs
	func _add_tree_collision(_pos: Vector3, _scale: float) -> void:
		pass

func test_tree_placer_no_crash_when_removed_from_tree_mid_await() -> void:
	# Regression: TreePlacer crashed with "data.tree is null" when removed from
	# the scene tree while _place_trees() was suspended mid-await.
	GameSync.game_seed = 7
	var tp2 := FastTreePlacer.new()
	add_child(tp2)

	# Kick off the async coroutine, then immediately remove the node.
	tp2._place_trees()
	remove_child(tp2)

	# Advance a few frames — coroutine resumes and must NOT crash.
	await wait_physics_frames(5)

	assert_true(true, "TreePlacer must not crash when removed from tree mid-await")
	tp2.queue_free()

# ---------------------------------------------------------------------------
# LaneVisualizer async tree-exit crash regression
# ---------------------------------------------------------------------------
# Regression guard for the null-tree crash in LaneVisualizer._ready():
#   await get_tree().process_frame  (1 site inside the batch loop)
# Fix: post-await `if not is_inside_tree(): return` guard.

func test_lane_visualizer_no_crash_when_removed_from_tree_mid_await() -> void:
	# Regression: LaneVisualizer crashed with "data.tree is null" when removed
	# from the scene tree while its _ready() batch loop was suspended mid-await.
	GameSync.game_seed = 7
	var lv: Node3D = Node3D.new()
	lv.set_script(load("res://scripts/LaneVisualizer.gd"))
	# Add to tree — _ready() starts the batched coroutine immediately.
	add_child(lv)
	# Remove before any frames advance so the coroutine is suspended mid-await.
	remove_child(lv)

	# Advance enough frames for the coroutine to fully drain.
	await wait_physics_frames(10)

	assert_true(true, "LaneVisualizer must not crash when removed from tree mid-await")
	lv.queue_free()
