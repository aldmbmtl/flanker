# test_build_system_relay.gd
# Tier 1 — tests for BuildSystem bridge message handling and place_item relay.
#
# BuildSystem._on_bridge_message is the inbound handler for Python server
# messages.  place_item now sends to Python instead of spawning locally.
# These tests verify:
#   - "tower_spawned"    → spawn_item_local called, item_spawned signal emitted
#   - "tower_despawned"  → node freed, tower_despawned signal emitted
#   - "placement_rejected" → no spawn, warning only (no crash)
#   - "team_points"      → TeamData.sync_from_server called with correct values
#   - place_item         → always returns "" (async relay; does not spawn locally)
#
# IMPORTANT: Each test that needs a "Main" node creates and removes it within
# the test body.  We do NOT use before_each/after_each for it to prevent the
# node from persisting across test suites (which would corrupt tests in
# test_position_visibility_sync.gd and test_projectile_base.gd that also
# create stub "Main" nodes).
extends GutTest

const BuildSystemScript := preload("res://scripts/BuildSystem.gd")

var bs: Node

# ─── helpers ──────────────────────────────────────────────────────────────────

func _make_main() -> Node:
	var m := Node.new()
	m.name = "Main"
	get_tree().root.add_child(m)
	return m

func _drop_main(m: Node) -> void:
	get_tree().root.remove_child(m)
	m.queue_free()

func before_each() -> void:
	bs = Node.new()
	bs.set_script(BuildSystemScript)
	add_child_autofree(bs)
	TeamData.sync_from_server(100, 100)

# ─── place_item returns "" immediately (async relay) ─────────────────────────

func test_place_item_always_returns_empty_string() -> void:
	# place_item now relays to Python and returns "" without spawning locally.
	var m := _make_main()
	TeamData.sync_from_server(200, 200)
	var result: String = bs.place_item(Vector3(0.0, 5.0, 50.0), 0, "cannon", "")
	assert_eq(result, "", "place_item must return '' — spawn is async via Python")
	_drop_main(m)
	await get_tree().process_frame

func test_place_item_does_not_spawn_node_locally() -> void:
	var m := _make_main()
	TeamData.sync_from_server(200, 200)
	var before_count: int = m.get_child_count()
	var _r: String = bs.place_item(Vector3(0.0, 5.0, 50.0), 0, "cannon", "")
	assert_eq(m.get_child_count(), before_count,
		"place_item must not add any node to Main before Python responds")
	_drop_main(m)
	await get_tree().process_frame

# ─── tower_spawned message ────────────────────────────────────────────────────

func test_tower_spawned_spawns_node_in_main() -> void:
	var m := _make_main()
	bs._on_bridge_message("tower_spawned", {
		"tower_type": "cannon",
		"team": 0,
		"pos": [0.0, 5.0, 50.0],
		"name": "Cannon_relay_test",
	})
	await get_tree().process_frame
	var node: Node = m.get_node_or_null("Cannon_relay_test")
	assert_not_null(node, "tower_spawned must spawn a node named by the server")
	_drop_main(m)
	await get_tree().process_frame

func test_tower_spawned_emits_item_spawned_signal() -> void:
	var m := _make_main()
	watch_signals(LobbyManager)
	bs._on_bridge_message("tower_spawned", {
		"tower_type": "cannon",
		"team": 0,
		"pos": [0.0, 5.0, 50.0],
		"name": "Cannon_signal_test",
	})
	await get_tree().process_frame
	assert_signal_emitted(LobbyManager, "item_spawned")
	_drop_main(m)
	await get_tree().process_frame

func test_tower_spawned_signal_carries_correct_type_and_team() -> void:
	var m := _make_main()
	watch_signals(LobbyManager)
	bs._on_bridge_message("tower_spawned", {
		"tower_type": "mortar",
		"team": 1,
		"pos": [0.0, 5.0, -50.0],
		"name": "Mortar_signal_test",
	})
	await get_tree().process_frame
	var params: Array = get_signal_parameters(LobbyManager, "item_spawned")
	assert_eq(params[0], "mortar", "item_spawned first arg must be item_type")
	assert_eq(params[1], 1, "item_spawned second arg must be team")
	_drop_main(m)
	await get_tree().process_frame

# ─── tower_despawned message ──────────────────────────────────────────────────

func test_tower_despawned_frees_existing_node() -> void:
	var m := _make_main()
	var stub := Node.new()
	stub.name = "Cannon_despawn_test"
	m.add_child(stub)
	assert_not_null(m.get_node_or_null("Cannon_despawn_test"))

	bs._on_bridge_message("tower_despawned", {
		"name": "Cannon_despawn_test",
		"tower_type": "cannon",
		"team": 0,
	})
	await get_tree().process_frame
	assert_null(m.get_node_or_null("Cannon_despawn_test"),
		"tower_despawned must free the named node from Main")
	_drop_main(m)
	await get_tree().process_frame

func test_tower_despawned_emits_tower_despawned_signal() -> void:
	var m := _make_main()
	var stub := Node.new()
	stub.name = "Cannon_despawn_sig"
	m.add_child(stub)

	watch_signals(LobbyManager)
	bs._on_bridge_message("tower_despawned", {
		"name": "Cannon_despawn_sig",
		"tower_type": "cannon",
		"team": 0,
	})
	await get_tree().process_frame
	assert_signal_emitted(LobbyManager, "tower_despawned")
	_drop_main(m)
	await get_tree().process_frame

func test_tower_despawned_missing_node_does_not_crash() -> void:
	var m := _make_main()
	bs._on_bridge_message("tower_despawned", {
		"name": "NonExistent_node",
		"tower_type": "cannon",
		"team": 0,
	})
	assert_true(true, "no crash when despawning a non-existent tower node")
	_drop_main(m)
	await get_tree().process_frame

# ─── placement_rejected message ───────────────────────────────────────────────

func test_placement_rejected_does_not_crash() -> void:
	bs._on_bridge_message("placement_rejected", {"reason": "insufficient_funds"})
	assert_true(true, "placement_rejected must not crash")

func test_placement_rejected_does_not_spawn_node() -> void:
	var m := _make_main()
	var before_count: int = m.get_child_count()
	bs._on_bridge_message("placement_rejected", {"reason": "spacing"})
	await get_tree().process_frame
	assert_eq(m.get_child_count(), before_count,
		"placement_rejected must never spawn any node")
	_drop_main(m)
	await get_tree().process_frame

# ─── team_points message ──────────────────────────────────────────────────────

func test_team_points_updates_team_data() -> void:
	TeamData.sync_from_server(0, 0)
	bs._on_bridge_message("team_points", {"blue": 150, "red": 75})
	assert_eq(TeamData.get_points(0), 150, "team_points must sync blue to TeamData")
	assert_eq(TeamData.get_points(1), 75,  "team_points must sync red to TeamData")
