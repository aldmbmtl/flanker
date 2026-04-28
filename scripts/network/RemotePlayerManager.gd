extends Node

const RemotePlayerScene := preload("res://scenes/network/RemotePlayer.tscn")

var _ghosts: Dictionary = {}
var _local_peer_id: int = 1

func _ready() -> void:
	_local_peer_id = multiplayer.get_unique_id() if NetworkManager._peer != null else 1
	GameSync.remote_player_updated.connect(_on_remote_player_updated)
	LobbyManager.player_left.connect(remove_ghost)
	GameSync.player_died.connect(_on_player_died)
	GameSync.player_respawned.connect(_on_player_respawned)

func _on_remote_player_updated(peer_id: int, pos: Vector3, rot: Vector3, _team: int) -> void:
	print("[RPM] peer_id=", peer_id, " _local_peer_id=", _local_peer_id, " has_ghost=", _ghosts.has(peer_id), " pos=", pos)
	# Don't create ghost for local player
	if peer_id == _local_peer_id:
		return
	
	if not _ghosts.has(peer_id):
		var ghost: Node3D = RemotePlayerScene.instantiate()
		ghost.name = "RemotePlayer_%d" % peer_id
		ghost.peer_id = peer_id
		get_parent().add_child(ghost)
		_ghosts[peer_id] = ghost
	
	var g: Node3D = _ghosts[peer_id]
	if is_instance_valid(g):
		g.update_transform(pos, rot)

func remove_ghost(peer_id: int) -> void:
	if _ghosts.has(peer_id):
		var g: Node3D = _ghosts[peer_id]
		if is_instance_valid(g):
			g.queue_free()
		_ghosts.erase(peer_id)

func _on_player_died(peer_id: int) -> void:
	if _ghosts.has(peer_id):
		var g: Node3D = _ghosts[peer_id]
		if is_instance_valid(g):
			g.visible = false
			var hit_body: StaticBody3D = g.get_node_or_null("HitBody")
			if hit_body != null:
				hit_body.set_collision_layer(0)
				hit_body.set_collision_mask(0)

func _on_player_respawned(peer_id: int, _spawn_pos: Vector3) -> void:
	if _ghosts.has(peer_id):
		var g: Node3D = _ghosts[peer_id]
		if is_instance_valid(g):
			g.visible = true
			var hit_body: StaticBody3D = g.get_node_or_null("HitBody")
			if hit_body != null:
				hit_body.set_collision_layer(1)
				hit_body.set_collision_mask(0)
