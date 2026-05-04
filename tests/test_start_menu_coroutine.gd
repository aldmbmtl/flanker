# test_start_menu_coroutine.gd
# Regression tests for the is_inside_tree() guards added to
# StartMenu._start_simulation_when_ready().
#
# Bug: when a player starts a game before the background terrain finishes
# generating, change_scene_to_file frees StartMenu while the coroutine is
# suspended at "await terrain.done". When terrain.done fires the coroutine
# resumes, calls get_tree().physics_frame, and crashes with:
#   ERROR: Parameter "data.tree" is null.
#
# Fix: two is_inside_tree() guards — one after each await suspension point —
# abort the coroutine before touching get_tree() if the node is gone.
#
# These tests verify the guards in isolation using a minimal stub that
# replicates the coroutine logic without requiring the full StartMenu scene.
extends GutTest

# ---------------------------------------------------------------------------
# Stub: replicates _start_simulation_when_ready logic with an observable flag
# ---------------------------------------------------------------------------

class _StubMenu extends Node:
	signal done_signal   # mimics terrain.done / trees.done
	var generation_done: bool = false
	var menu_world_ready_called: bool = false

	# Mirrors StartMenu._start_simulation_when_ready exactly (with the fix).
	func start_sim(terrain: Node, trees: Node) -> void:
		if not terrain.get("generation_done"):
			await terrain.done_signal
		if not is_inside_tree():
			return
		if not trees.get("generation_done"):
			await trees.done_signal
		if not is_inside_tree():
			return
		await get_tree().physics_frame
		menu_world_ready_called = true

class _StubTerrain extends Node:
	signal done_signal
	var generation_done: bool = false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

var _menu: _StubMenu
var _terrain: _StubTerrain
var _trees: _StubTerrain

func before_each() -> void:
	_menu    = _StubMenu.new()
	_terrain = _StubTerrain.new()
	_trees   = _StubTerrain.new()

func after_each() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	if is_instance_valid(_terrain):
		_terrain.queue_free()
	if is_instance_valid(_trees):
		_trees.queue_free()

# ---------------------------------------------------------------------------
# Tests: guard after terrain.done — node removed before terrain signal fires
# ---------------------------------------------------------------------------

func test_coroutine_aborts_if_node_removed_before_terrain_done() -> void:
	# Regression: coroutine must not call get_tree() if node is no longer in tree.
	add_child_autofree(_menu)
	_terrain.generation_done = false
	_trees.generation_done   = false

	# Start coroutine — suspends at "await terrain.done_signal".
	_menu.start_sim(_terrain, _trees)

	# Simulate scene change: remove menu from the tree before signal fires.
	_menu.get_parent().remove_child(_menu)
	assert_false(_menu.is_inside_tree(), "setup: menu must be out of tree")

	# Now emit terrain done — coroutine resumes, must hit the guard and return.
	_terrain.done_signal.emit()
	await get_tree().process_frame

	assert_false(_menu.menu_world_ready_called,
		"_on_menu_world_ready must NOT be called when node was removed before terrain.done")

func test_coroutine_aborts_if_node_removed_between_terrain_and_trees() -> void:
	# Guard 2: node removed after terrain.done fires but before trees.done fires.
	add_child_autofree(_menu)
	_terrain.generation_done = false
	_trees.generation_done   = false

	_menu.start_sim(_terrain, _trees)

	# Let terrain finish first — coroutine advances past first await.
	_terrain.done_signal.emit()
	await get_tree().process_frame

	# Now remove from tree before trees.done fires.
	_menu.get_parent().remove_child(_menu)
	assert_false(_menu.is_inside_tree(), "setup: menu must be out of tree after terrain done")

	# Emit trees done — coroutine resumes at second guard, must abort.
	_trees.done_signal.emit()
	await get_tree().process_frame

	assert_false(_menu.menu_world_ready_called,
		"_on_menu_world_ready must NOT be called when node was removed between terrain and trees done")

func test_coroutine_completes_normally_when_node_stays_in_tree() -> void:
	# Happy path: both signals fire while node is in tree — should complete.
	add_child_autofree(_menu)
	_terrain.generation_done = false
	_trees.generation_done   = false

	_menu.start_sim(_terrain, _trees)

	_terrain.done_signal.emit()
	_trees.done_signal.emit()
	# Wait for the physics_frame await plus one more frame.
	await get_tree().physics_frame
	await get_tree().process_frame

	assert_true(_menu.menu_world_ready_called,
		"_on_menu_world_ready MUST be called when node stays in tree through both awaits")

func test_coroutine_skips_terrain_await_when_already_done() -> void:
	# If generation_done is already true, the terrain await is skipped entirely.
	add_child_autofree(_menu)
	_terrain.generation_done = true   # already finished
	_trees.generation_done   = false

	_menu.start_sim(_terrain, _trees)

	# Only need to fire trees signal.
	_trees.done_signal.emit()
	await get_tree().physics_frame
	await get_tree().process_frame

	assert_true(_menu.menu_world_ready_called,
		"coroutine must complete when terrain is pre-done and trees fires normally")

func test_coroutine_no_crash_when_node_never_added_to_tree() -> void:
	# Edge case: coroutine launched on a node that was never added to the tree.
	# is_inside_tree() returns false immediately.
	_terrain.generation_done = false
	_trees.generation_done   = false

	# _menu is NOT added to tree — start_sim will suspend then guard-return.
	_menu.start_sim(_terrain, _trees)
	_terrain.done_signal.emit()
	await get_tree().process_frame

	assert_false(_menu.menu_world_ready_called,
		"coroutine must not crash or call _on_menu_world_ready for an out-of-tree node")
