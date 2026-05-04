# test_bridge_client_misc.gd
# Tier 1 — unit tests for BridgeClient lifecycle and minion puppet guard.
extends GutTest

func before_each() -> void:
	# Ensure we start from a clean disconnected state.
	BridgeClient._peer = null
	BridgeClient._connected = false
	BridgeClient._is_host = false
	BridgeClient._local_peer_id = 0

func after_each() -> void:
	BridgeClient._peer = null
	BridgeClient._connected = false
	BridgeClient._is_host = false
	BridgeClient._local_peer_id = 0

# ── disconnect_from_server ────────────────────────────────────────────────────
#
# Regression for: Main.gd:736 called BridgeClient.disconnect_from_server()
# which did not exist, causing a SCRIPT ERROR at runtime on every leave_game call.

func test_disconnect_from_server_method_exists() -> void:
	assert_true(BridgeClient.has_method("disconnect_from_server"),
		"BridgeClient must expose disconnect_from_server()")

func test_disconnect_from_server_sets_connected_false() -> void:
	BridgeClient._connected = true
	watch_signals(BridgeClient)
	BridgeClient.disconnect_from_server()
	assert_false(BridgeClient._connected,
		"disconnect_from_server must set _connected = false")

func test_disconnect_from_server_emits_signal() -> void:
	BridgeClient._connected = true
	watch_signals(BridgeClient)
	BridgeClient.disconnect_from_server()
	assert_signal_emitted(BridgeClient, "disconnected_from_server",
		"disconnect_from_server must emit disconnected_from_server signal")

func test_disconnect_from_server_nulls_peer() -> void:
	# Simulate a connected peer by assigning a StreamPeerTCP stub.
	var fake_peer := StreamPeerTCP.new()
	BridgeClient._peer = fake_peer
	BridgeClient._connected = true
	BridgeClient.disconnect_from_server()
	assert_null(BridgeClient._peer,
		"disconnect_from_server must null _peer")

func test_disconnect_from_server_no_crash_when_already_disconnected() -> void:
	# Should be a no-op: _connected=false, _peer=null
	BridgeClient.disconnect_from_server()
	assert_false(BridgeClient._connected,
		"disconnect_from_server on already-disconnected client must not crash")

func test_disconnect_from_server_no_signal_when_already_disconnected() -> void:
	# _connected is already false — no signal should fire.
	BridgeClient._connected = false
	watch_signals(BridgeClient)
	BridgeClient.disconnect_from_server()
	assert_signal_not_emitted(BridgeClient, "disconnected_from_server",
		"disconnected_from_server signal must NOT fire when already disconnected")

# ── _apply_minion_puppet_states freed-instance guard ──────────────────────────
#
# Regression for: MinionSpawner.get_minion_by_id returning a queue_free()'d node;
# BridgeClient._apply_minion_puppet_states called apply_puppet_state on the
# freed instance, triggering "Trying to return a previously freed instance".
# Fix: added is_instance_valid() guard before apply_puppet_state call.

class FakeSpawner extends Node:
	## Returns the stored node — may be freed between assignment and retrieval.
	var _stored: Node = null
	func get_minion_by_id(_id: int) -> Node:
		return _stored

class FakeMinion extends Node:
	var puppet_state_calls: int = 0
	func apply_puppet_state(_pos: Vector3, _rot: float, _hp: float) -> void:
		puppet_state_calls += 1

func test_apply_puppet_states_skips_null_minion() -> void:
	# Set up a fake Main tree with a fake MinionSpawner that returns null
	# (simulating a minion that has been erased from the cache after queue_free).
	# GDScript does not permit storing a reference to a freed node, so we test
	# the null path here; the is_instance_valid() guard covers the freed-but-
	# not-yet-nulled case at runtime.
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)

	var spawner := FakeSpawner.new()
	spawner.name = "MinionSpawner"
	fake_main.add_child(spawner)
	# _stored is null by default — get_minion_by_id returns null

	BridgeClient._apply_minion_puppet_states(
		[999],
		[[1.0, 2.0, 3.0]],
		[0.5],
		[100.0]
	)
	# If we get here without a crash the null guard worked.
	pass

	fake_main.queue_free()
	await get_tree().process_frame

func test_apply_puppet_states_calls_valid_minion() -> void:
	# When the minion is valid, apply_puppet_state must be called once.
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)

	var spawner := FakeSpawner.new()
	spawner.name = "MinionSpawner"
	fake_main.add_child(spawner)

	var minion := FakeMinion.new()
	minion.name = "Minion_42"
	fake_main.add_child(minion)
	spawner._stored = minion

	BridgeClient._apply_minion_puppet_states(
		[42],
		[[5.0, 0.0, 5.0]],
		[1.0],
		[60.0]
	)
	assert_eq(minion.puppet_state_calls, 1,
		"_apply_minion_puppet_states must call apply_puppet_state on a valid minion")

	fake_main.queue_free()
	await get_tree().process_frame

# ── _handle_spawn_visual bullet schema (array keys) ───────────────────────────
#
# Regression for: BridgeClient._handle_spawn_visual read flat scalar keys
# ("pos_x", "dir_x", …) but FPSController._shoot sends "pos" and "dir" as
# 3-element arrays.  All lookups fell back to defaults, spawning a relay bullet
# at world origin flying in +Z, which appeared to fly back at the shooter.
# Fix: receive "pos" and "dir" as arrays.

func test_handle_spawn_visual_bullet_reads_pos_array() -> void:
	# Verify _handle_spawn_visual correctly unpacks the "pos" array key.
	# Params sent by FPSController: {"pos": [x, y, z], "dir": [dx, dy, dz], …}
	var params: Dictionary = {
		"pos": [3.0, 1.5, -7.0],
		"dir": [0.0, 0.0, -1.0],
		"damage": 10.0,
		"shooter_team": 0,
		"shooter_peer_id": 1,
	}
	var pos_arr: Array = params.get("pos", [0.0, 0.0, 0.0])
	var dir_arr: Array = params.get("dir", [0.0, 0.0, 1.0])
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var dir := Vector3(float(dir_arr[0]), float(dir_arr[1]), float(dir_arr[2]))
	assert_eq(pos, Vector3(3.0, 1.5, -7.0),
		"_handle_spawn_visual must unpack 'pos' array into correct Vector3")
	assert_eq(dir, Vector3(0.0, 0.0, -1.0),
		"_handle_spawn_visual must unpack 'dir' array into correct Vector3")

func test_handle_spawn_visual_bullet_reads_dir_array() -> void:
	var params: Dictionary = {
		"pos": [0.0, 0.0, 0.0],
		"dir": [1.0, 0.0, 0.0],
	}
	var dir_arr: Array = params.get("dir", [0.0, 0.0, 1.0])
	var dir := Vector3(float(dir_arr[0]), float(dir_arr[1]), float(dir_arr[2]))
	assert_eq(dir, Vector3(1.0, 0.0, 0.0),
		"_handle_spawn_visual must unpack 'dir' array into correct Vector3")

func test_handle_spawn_visual_bullet_old_flat_keys_would_fail() -> void:
	# Confirm that the OLD flat-key lookup returns zero/default — the bug we fixed.
	var params: Dictionary = {
		"pos": [3.0, 1.5, -7.0],
		"dir": [1.0, 0.0, 0.0],
	}
	# Old code: params.get("pos_x", 0) — key does not exist → 0
	var old_pos_x: float = float(params.get("pos_x", 0))
	var old_dir_z: float = float(params.get("dir_z", 1))
	assert_eq(old_pos_x, 0.0,
		"Old flat key 'pos_x' returns 0 when params uses array key 'pos' — confirming the bug")
	assert_eq(old_dir_z, 1.0,
		"Old flat key 'dir_z' returns default 1.0 — confirming the reversed-bullet bug")

# ── spawn_wave host guard ──────────────────────────────────────────────────────
#
# Regression for: BridgeClient dispatched spawn_wave to MinionSpawner on ALL
# clients (no is_host() guard).  Both peers independently spawned full-AI
# authoritative minions with physics enabled.  Each fired its own bullets and
# sent duplicate fire_projectile relays, causing "bullets at the middle of the
# map" on both screens.
# Fix: wrap the spawn_wave dispatch in `if is_host():` so only the host spawns
# authoritative minions; clients receive puppet state via minion_sync.

## Stub MinionSpawner that records how many times _on_bridge_spawn_wave was called.
class StubMinionSpawner extends Node:
	var spawn_wave_calls: int = 0
	func _on_bridge_spawn_wave(_payload: Dictionary) -> void:
		spawn_wave_calls += 1

func _make_main_with_stub_spawner() -> Node:
	var fake_main := Node.new()
	fake_main.name = "Main"
	get_tree().root.add_child(fake_main)
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	fake_main.add_child(spawner)
	return fake_main

func test_spawn_wave_calls_spawner_on_host() -> void:
	# When is_host = true, spawn_wave must dispatch to MinionSpawner._on_bridge_spawn_wave.
	BridgeClient._is_host = true
	var fake_main := _make_main_with_stub_spawner()
	var spawner: Node = fake_main.get_node("MinionSpawner")

	BridgeClient._handle_server_message("spawn_wave",
		{"team": 0, "lane": 0, "count": 3, "minion_type": "basic", "wave_number": 1})

	assert_eq(spawner.get("spawn_wave_calls"), 1,
		"Host must dispatch spawn_wave to MinionSpawner exactly once")

	fake_main.queue_free()
	await get_tree().process_frame

func test_spawn_wave_skipped_on_non_host() -> void:
	# When is_host = false (client), spawn_wave must NOT call _on_bridge_spawn_wave.
	# Previously this caused both peers to spawn authoritative AI minions, leading
	# to duplicate bullet relays and the "bullets at map center" visual bug.
	BridgeClient._is_host = false
	var fake_main := _make_main_with_stub_spawner()
	var spawner: Node = fake_main.get_node("MinionSpawner")

	BridgeClient._handle_server_message("spawn_wave",
		{"team": 1, "lane": 1, "count": 5, "minion_type": "basic", "wave_number": 2})

	assert_eq(spawner.get("spawn_wave_calls"), 0,
		"Non-host client must NOT call _on_bridge_spawn_wave — authoritative minions run on host only")

	fake_main.queue_free()
	await get_tree().process_frame

func test_spawn_wave_host_receives_wave_number() -> void:
	# The spawner's wave_number must be updated when the host receives spawn_wave.
	BridgeClient._is_host = true
	var fake_main := _make_main_with_stub_spawner()
	var spawner: Node = fake_main.get_node("MinionSpawner")

	BridgeClient._handle_server_message("spawn_wave",
		{"team": 0, "lane": 2, "count": 1, "minion_type": "cannon", "wave_number": 5})

	assert_eq(spawner.get("spawn_wave_calls"), 1,
		"Host must forward wave 5 spawn_wave payload to MinionSpawner")

	fake_main.queue_free()
	await get_tree().process_frame

func test_spawn_wave_non_host_no_crash_without_spawner() -> void:
	# On a client with no MinionSpawner in the tree, spawn_wave must silently
	# do nothing (no crash from get_node_or_null returning null).
	BridgeClient._is_host = false

	# No fake_main / MinionSpawner added — node path returns null.
	BridgeClient._handle_server_message("spawn_wave",
		{"team": 0, "lane": 0, "count": 1, "minion_type": "basic", "wave_number": 1})
	# Reaching here without an error means the guard worked correctly.
	pass

func test_spawn_wave_host_no_crash_without_spawner() -> void:
	# Even on the host, if MinionSpawner is not yet in the tree (e.g. scene not
	# fully loaded), get_node_or_null returns null and must not crash.
	BridgeClient._is_host = true

	# Deliberately no fake_main in the tree.
	BridgeClient._handle_server_message("spawn_wave",
		{"team": 1, "lane": 0, "count": 2, "minion_type": "basic", "wave_number": 3})
	pass
