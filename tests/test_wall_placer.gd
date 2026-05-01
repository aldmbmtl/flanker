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
