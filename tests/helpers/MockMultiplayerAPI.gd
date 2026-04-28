# MockMultiplayerAPI.gd
# Injectable MultiplayerAPIExtension for Tier 2 (RPC dispatch) tests.
# Intercepts all RPC calls and records them in rpc_log without any real networking.
#
# Usage:
#   var mock := MockMultiplayerAPI.new()
#   get_tree().set_multiplayer(mock, node_under_test.get_path())
#   # ... call methods that trigger RPCs ...
#   assert_eq(mock.rpc_log.size(), 1)
#   assert_eq(mock.rpc_log[0]["method"], "apply_player_damage")
extends MultiplayerAPIExtension
class_name MockMultiplayerAPI

## Every intercepted RPC appended as { peer, object, method, args }
var rpc_log: Array = []

## Configurable identity
var _my_id: int = 1
var _is_server_flag: bool = true

func set_as_client(peer_id: int) -> void:
	_my_id = peer_id
	_is_server_flag = false

func set_as_server() -> void:
	_my_id = 1
	_is_server_flag = true

# ── MultiplayerAPIExtension overrides ────────────────────────────────────────

func _get_unique_id() -> int:
	return _my_id

func _get_peer_ids() -> PackedInt32Array:
	return PackedInt32Array()

func _get_remote_sender_id() -> int:
	return 0

func _is_server() -> bool:
	return _is_server_flag

func _has_multiplayer_peer() -> bool:
	return true

func _poll() -> Error:
	return OK

func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	rpc_log.append({
		"peer": peer,
		"object": object,
		"method": str(method),
		"args": args.duplicate()
	})
	return OK

func _object_configuration_add(_object: Object, _config: Variant) -> Error:
	return OK

func _object_configuration_remove(_object: Object, _config: Variant) -> Error:
	return OK

func _set_multiplayer_peer(_p: MultiplayerPeer) -> void:
	pass

func _get_multiplayer_peer() -> MultiplayerPeer:
	return OfflineMultiplayerPeer.new()

# ── Query helpers ─────────────────────────────────────────────────────────────

## Returns all log entries whose "method" field matches the given name.
func calls_to(method_name: String) -> Array:
	var result: Array = []
	for entry in rpc_log:
		if entry["method"] == method_name:
			result.append(entry)
	return result

## Returns true if the named method was called at least once.
func was_called(method_name: String) -> bool:
	return calls_to(method_name).size() > 0

## Clears the log between assertions.
func reset() -> void:
	rpc_log.clear()
