extends GutTest
# test_weapon_pickup.gd — unit tests for WeaponPickup pickup paths.
#
# After Slice 8 the pickup path routes through BridgeClient.send("drop_picked_up")
# when connected; falls back to direct LobbyManager.notify_drop_picked_up / queue_free
# when the bridge is not connected. All tests run with the bridge disconnected so
# BridgeClient.is_connected_to_server() == false.
#
# Tier 1 (OfflineMultiplayerPeer → is_server=true).

const WeaponPickupScript := preload("res://scripts/WeaponPickup.gd")

# ── Fake body that satisfies pick_up_weapon check ─────────────────────────────

class FakeBody extends CharacterBody3D:
	var picked_up: bool = false
	func pick_up_weapon(_data) -> void:
		picked_up = true

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_pickup(supporter_placed: bool = true) -> Area3D:
	var pickup: Area3D = Area3D.new()
	pickup.set_script(WeaponPickupScript)
	var data: WeaponData = WeaponData.new()
	pickup.weapon_data = data
	pickup.set_meta("supporter_placed", supporter_placed)
	# Add a dummy CollisionShape3D so Area3D is valid
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	pickup.add_child(col)
	# Add a dummy MeshInstance3D so _ready() doesn't error on $MeshInstance3D
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	pickup.add_child(mesh)
	return pickup

# ── Tests ─────────────────────────────────────────────────────────────────────

func test_supporter_pickup_calls_pick_up_weapon() -> void:
	# pick_up_weapon must always be called regardless of bridge/multiplayer state.
	var pickup: Area3D = _make_pickup(true)
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_true(body.picked_up, "pick_up_weapon must be called for a supporter-placed pickup")

func test_natural_pickup_calls_pick_up_weapon() -> void:
	# Natural (non-supporter-placed) pickup also calls pick_up_weapon.
	var pickup: Area3D = _make_pickup(false)
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_true(body.picked_up, "pick_up_weapon must be called for a natural pickup")

func test_supporter_pickup_no_rpc_when_bridge_disconnected() -> void:
	# With bridge disconnected and OfflineMultiplayerPeer (is_server=true),
	# the fallback path is notify_drop_picked_up() → despawn_drop() locally.
	# No ENet RPC should be issued.
	var mock := preload("res://tests/helpers/MockMultiplayerAPI.gd").new()
	mock.set_as_server()
	get_tree().set_multiplayer(mock, ^"/root")

	var pickup: Area3D = _make_pickup(true)
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_true(body.picked_up, "pick_up_weapon must be called")
	# Bridge disconnected + server → notify_drop_picked_up called directly (no rpc_id)
	assert_false(mock.was_called("notify_drop_picked_up"),
		"server path must NOT send notify_drop_picked_up via RPC when bridge is disconnected")

	get_tree().set_multiplayer(null, ^"/root")

func test_non_supporter_placed_no_rpc() -> void:
	# Natural pickups never call notify_drop_picked_up by RPC.
	var mock := preload("res://tests/helpers/MockMultiplayerAPI.gd").new()
	mock.set_as_client(42)
	get_tree().set_multiplayer(mock, ^"/root")

	var pickup: Area3D = _make_pickup(false)
	add_child_autofree(pickup)

	var body: FakeBody = FakeBody.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_false(mock.was_called("notify_drop_picked_up"),
		"natural pickups must not call notify_drop_picked_up by RPC")

	get_tree().set_multiplayer(null, ^"/root")
