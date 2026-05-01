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
	assert_eq(wp.SAND_COUNT, 375, "SAND_COUNT must be 375")
	wp.free()

func test_sand_scene_paths_all_non_null() -> void:
	var wp: Node3D = WallPlacerScript.new()
	for i in range(wp.SAND_SCENE_PATHS.size()):
		assert_not_null(wp.SAND_SCENE_PATHS[i], "SAND_SCENE_PATHS[%d] must not be null" % i)
	wp.free()
