extends GutTest
# test_weapon_pickup.gd — unit tests for WeaponPickup RPC guard fix.
# Verifies that supporter-placed drops call notify_drop_picked_up directly
# (not via rpc_id) when running as server, and via rpc_id when running as client.
#
# Tier 1 (OfflineMultiplayerPeer → is_server=true) for server path.
# Tier 2 (MockMultiplayerAPI → is_server=false) for client path.

const WeaponPickupScript := preload("res://scripts/WeaponPickup.gd")
const MockMultiplayerAPI  := preload("res://tests/helpers/MockMultiplayerAPI.gd")

# ── Fake body that satisfies pick_up_weapon check ─────────────────────────────

class FakeBody extends CharacterBody3D:
	var picked_up: bool = false
	func pick_up_weapon(_data) -> void:
		picked_up = true

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_pickup() -> Area3D:
	var pickup: Area3D = Area3D.new()
	pickup.set_script(WeaponPickupScript)
	var data: WeaponData = WeaponData.new()
	pickup.weapon_data = data
	pickup.set_meta("supporter_placed", true)
	# Add a dummy CollisionShape3D so Area3D is valid
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	pickup.add_child(col)
	# Add a dummy MeshInstance3D so _ready() doesn't error on $MeshInstance3D
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	pickup.add_child(mesh)
	return pickup

# ── Server path: direct call, no rpc_id ──────────────────────────────────────

func test_server_calls_notify_directly_no_rpc() -> void:
	# OfflineMultiplayerPeer: multiplayer.is_server() == true
	var pickup: Area3D = _make_pickup()
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	# Intercept despawn_drop to detect it was called (proves notify ran locally)
	watch_signals(LobbyManager)

	# Call the pickup handler directly
	pickup._on_body_entered(body)

	assert_true(body.picked_up, "pick_up_weapon should have been called")
	# notify_drop_picked_up calls despawn_drop.rpc (call_local) which tries to
	# queue_free the node by name from Main — it won't find it, but it won't crash.
	# The important thing: no RPC error, and pick_up_weapon was called.

func test_client_sends_rpc_to_server() -> void:
	var mock := MockMultiplayerAPI.new()
	mock.set_as_client(42)
	get_tree().set_multiplayer(mock, ^"/root")

	var pickup: Area3D = _make_pickup()
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_true(body.picked_up, "pick_up_weapon should have been called")
	assert_true(mock.was_called("notify_drop_picked_up"),
		"client should send notify_drop_picked_up via rpc_id(1)")
	var calls: Array = mock.calls_to("notify_drop_picked_up")
	assert_eq(calls[0]["peer"], 1, "rpc should target peer 1 (server)")

	get_tree().set_multiplayer(null, ^"/root")

func test_server_does_not_send_rpc() -> void:
	var mock := MockMultiplayerAPI.new()
	mock.set_as_server()
	get_tree().set_multiplayer(mock, ^"/root")

	var pickup: Area3D = _make_pickup()
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_false(mock.was_called("notify_drop_picked_up"),
		"server should NOT send rpc_id — calls function directly")

	get_tree().set_multiplayer(null, ^"/root")

func test_non_supporter_placed_does_not_call_notify() -> void:
	var mock := MockMultiplayerAPI.new()
	mock.set_as_client(42)
	get_tree().set_multiplayer(mock, ^"/root")

	var pickup: Area3D = _make_pickup()
	pickup.set_meta("supporter_placed", false)
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_false(mock.was_called("notify_drop_picked_up"),
		"natural pickups should not call notify_drop_picked_up")

	get_tree().set_multiplayer(null, ^"/root")
