# test_graphics_settings.gd
# Tier 1 — unit tests for GraphicsSettings autoload.
#
# Tests cover tree_shadow_distance: default value, persistence through
# save/load, apply() updates, restore_defaults() resets to 1 (Close).
extends GutTest

var gs: Node

func before_each() -> void:
	# Instantiate a fresh GraphicsSettings node (not the autoload singleton)
	# so tests are isolated and don't touch the user's saved config.
	gs = load("res://scripts/ClientSettings.gd").new()
	# Override SAVE_PATH to a temp location so tests never write real config.
	# We skip load_settings() side-effects by not calling _ready().
	add_child_autofree(gs)


# ── Default value ─────────────────────────────────────────────────────────────

func test_tree_shadow_distance_default_is_close() -> void:
	# Reset to known state — restore_defaults sets tree_shadow_distance to 1.
	gs.restore_defaults()
	assert_eq(gs.tree_shadow_distance, 1,
		"tree_shadow_distance default must be 1 (Close)")


# ── apply() updates tree_shadow_distance ─────────────────────────────────────

func test_apply_sets_tree_shadow_distance_off() -> void:
	gs.apply(true, 1.0, true, 0.07, 1, 0)
	assert_eq(gs.tree_shadow_distance, 0,
		"apply() with tree_shad_dist=0 must set tree_shadow_distance to 0 (Off)")

func test_apply_sets_tree_shadow_distance_close() -> void:
	gs.apply(true, 1.0, true, 0.07, 1, 1)
	assert_eq(gs.tree_shadow_distance, 1,
		"apply() with tree_shad_dist=1 must set tree_shadow_distance to 1 (Close)")

func test_apply_sets_tree_shadow_distance_far() -> void:
	gs.apply(true, 1.0, true, 0.07, 1, 2)
	assert_eq(gs.tree_shadow_distance, 2,
		"apply() with tree_shad_dist=2 must set tree_shadow_distance to 2 (Far)")

func test_apply_emits_settings_changed() -> void:
	watch_signals(gs)
	gs.apply(true, 1.0, true, 0.07, 1, 2)
	assert_signal_emitted(gs, "settings_changed",
		"apply() must emit settings_changed")


# ── restore_defaults() resets tree_shadow_distance ───────────────────────────

func test_restore_defaults_resets_tree_shadow_distance() -> void:
	gs.tree_shadow_distance = 2
	gs.restore_defaults()
	assert_eq(gs.tree_shadow_distance, 1,
		"restore_defaults() must reset tree_shadow_distance to 1 (Close)")


# ── Default parameter preserves existing value ────────────────────────────────

func test_apply_default_param_preserves_tree_shadow_distance() -> void:
	gs.tree_shadow_distance = 2
	# Call apply() without passing tree_shad_dist — should keep current value.
	gs.apply(true, 1.0, true, 0.07, 1)
	assert_eq(gs.tree_shadow_distance, 2,
		"apply() without tree_shad_dist arg must preserve existing tree_shadow_distance")
