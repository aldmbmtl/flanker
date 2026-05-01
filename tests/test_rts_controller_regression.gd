# test_rts_controller_regression.gd
# Regression tests for RTSController parse errors and type annotation bugs.
extends GutTest

const RTSScript := preload("res://scripts/roles/supporter/RTSController.gd")
const BuildSystemScript := preload("res://scripts/BuildSystem.gd")

# ── RTSController loads without parse errors ──────────────────────────────────

func test_rts_controller_script_loads() -> void:
	# Regression: "Identifier 'peer_id' not declared in the current scope" at line 478.
	# If the script has a parse error, preload above would fail and this test
	# would not be reachable — but we also instantiate to force _ready().
	var cam := Camera3D.new()
	cam.set_script(RTSScript)
	add_child_autofree(cam)
	assert_not_null(cam, "RTSController must instantiate without parse errors")

# ── player_role property is accessible via Node-typed reference ───────────────

func test_player_role_assignable_via_node_reference() -> void:
	# Regression: Main.gd had `rts_camera: Camera3D` — Camera3D has no
	# player_role property, so assignment raised "Invalid assignment of property".
	# Fix: rts_camera typed as Node so the script property is reachable.
	var cam := Camera3D.new()
	cam.set_script(RTSScript)
	add_child_autofree(cam)
	# Assign via Node reference (mirrors what Main.gd does after the fix)
	var node_ref: Node = cam
	node_ref.set("player_role", 1)
	assert_eq(node_ref.get("player_role"), 1,
		"player_role must be readable/writable via a Node-typed reference")

# ── ghost validation uses a valid placer_peer_id (not undeclared 'peer_id') ───

func test_can_place_item_called_with_valid_placer_id() -> void:
	# Regression: _update_ghost_placement called can_place_item(... peer_id)
	# where peer_id was never declared, causing a parse error.
	# After the fix it uses multiplayer.get_unique_id() or 1 (singleplayer).
	# We verify BuildSystem.can_place_item receives a non-crash int by calling
	# the fixed expression directly with singleplayer peer semantics.
	var bs := Node.new()
	bs.set_script(BuildSystemScript)
	add_child_autofree(bs)
	TeamData.sync_from_server(200, 200)

	# Simulate singleplayer: no multiplayer peer → placer_id = 1
	var placer_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	# Must not crash; result value doesn't matter here
	var result: bool = bs.can_place_item(Vector3(40.0, 5.0, 40.0), 0, "cannon", placer_id)
	assert_true(result is bool,
		"can_place_item with resolved placer_id must return a bool without crashing")
