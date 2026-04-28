# StubRemotePlayerManager.gd
# Stub for RemotePlayerManager — records ghost lifecycle via remote_player_updated signal.
extends Node
class_name StubRemotePlayerManager

var ghost_updates: Array = []  # each: {peer_id, pos, rot, team}
var _ghosts: Dictionary = {}   # peer_id -> {pos, rot, team}

func _ready() -> void:
	GameSync.remote_player_updated.connect(_on_remote_player_updated)

func _on_remote_player_updated(peer_id: int, pos: Vector3, rot: Vector3, team: int) -> void:
	ghost_updates.append({"peer_id": peer_id, "pos": pos, "rot": rot, "team": team})
	_ghosts[peer_id] = {"pos": pos, "rot": rot, "team": team}

func has_ghost(peer_id: int) -> bool:
	return _ghosts.has(peer_id)

func get_ghost(peer_id: int) -> Dictionary:
	return _ghosts.get(peer_id, {})

func reset() -> void:
	ghost_updates.clear()
	_ghosts.clear()
