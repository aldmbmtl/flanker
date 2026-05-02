extends Node

## PlayerManager — lifecycle manager for remote peer BasePlayer nodes.
##
## Mirrors MinionSpawner's authority split: spawns a BasePlayer (is_local=false)
## for every remote peer, lerps it via update_transform, and hides/shows it via
## _set_alive() on death/respawn signals.
##
## VISIBILITY-CRITICAL — keep ALL print statements. See RemotePlayerManager header
## for history of known root causes of invisible ghosts.
##
## Diagnostic prints prefix guide:
##   [PM]       — _on_remote_player_updated (every transform tick)
##   [PM-SPAWN] — ghost creation path
##   [PM-DIED]  — _on_player_died handler
##   [PM-RESP]  — _on_player_respawned handler
##   [PM-RM]    — remove_player

const BasePlayerScene := preload("res://scenes/players/BasePlayer.tscn")

## Node under which remote player puppets are spawned as children.
## Set this before _ready() in tests to inject a stub root.
## At runtime this is left null and _get_spawn_root() falls back to get_parent().
@export var spawn_root: Node = null

var _players: Dictionary = {}
var _local_peer_id: int = 1

func _ready() -> void:
	_local_peer_id = multiplayer.get_unique_id() if NetworkManager._peer != null else 1
	print("[PM] _ready local_peer_id=", _local_peer_id,
		" is_server=", multiplayer.is_server(),
		" spawn_root=", (spawn_root.name if spawn_root != null else "null (→ get_parent())"))
	GameSync.remote_player_updated.connect(_on_remote_player_updated)
	LobbyManager.player_left.connect(remove_player)
	GameSync.player_died.connect(_on_player_died)
	GameSync.player_respawned.connect(_on_player_respawned)

func _exit_tree() -> void:
	if GameSync.remote_player_updated.is_connected(_on_remote_player_updated):
		GameSync.remote_player_updated.disconnect(_on_remote_player_updated)
	if LobbyManager.player_left.is_connected(remove_player):
		LobbyManager.player_left.disconnect(remove_player)
	if GameSync.player_died.is_connected(_on_player_died):
		GameSync.player_died.disconnect(_on_player_died)
	if GameSync.player_respawned.is_connected(_on_player_respawned):
		GameSync.player_respawned.disconnect(_on_player_respawned)

## Returns the node that remote player puppets are added to.
## Defaults to get_parent() to preserve existing runtime behaviour.
func _get_spawn_root() -> Node:
	return spawn_root if spawn_root != null else get_parent()

func _on_remote_player_updated(peer_id: int, pos: Vector3, rot: Vector3, team: int) -> void:
	print("[PM] peer_id=", peer_id,
		" _local_peer_id=", _local_peer_id,
		" has_player=", _players.has(peer_id),
		" pos=", pos)
	if peer_id == _local_peer_id:
		return

	if not _players.has(peer_id):
		var is_dead: bool = GameSync.player_dead.get(peer_id, false)
		var info: Dictionary = LobbyManager.players.get(peer_id, {})
		var avatar_char: String = info.get("avatar_char", "") as String

		print("[PM-SPAWN] creating player peer_id=", peer_id,
			" team=", team,
			" is_dead=", is_dead,
			" avatar_char=", avatar_char,
			" initial_visible=true (always)")

		var player: BasePlayer = BasePlayerScene.instantiate()
		# setup() BEFORE add_child — mirrors MinionBase pattern
		player.setup(peer_id, team, false, avatar_char)
		player.name = "RemotePlayer_%d" % peer_id

		# Players are always visible regardless of death state.
		player.visible = true

		_get_spawn_root().add_child(player)
		_players[peer_id] = player

		print("[PM-SPAWN] player added to tree peer_id=", peer_id,
			" player.visible=", player.visible,
			" player.name=", player.name,
			" parent=", player.get_parent().name)

		# Connect visibility_changed to catch ANY code path that hides the node,
		# including engine internals and deferred calls with no print coverage.
		var vis_capture_id: int = peer_id
		player.visibility_changed.connect(func() -> void:
			if not _players.has(vis_capture_id):
				return
			var vp: Node3D = _players[vis_capture_id]
			if not is_instance_valid(vp):
				return
			print("[PM-VIS-CHG] peer_id=", vis_capture_id,
				" player.visible=", vp.visible,
				" is_visible_in_tree=", vp.is_visible_in_tree(),
				" frame=", Engine.get_process_frames())
		)

		# One-shot diagnostic 0.1s after creation to catch deferred visibility changes.
		# Guard: get_tree() can be null in headless test contexts where the node is
		# not yet fully inside the scene tree when this code runs.
		if not is_inside_tree():
			return
		var capture_id: int = peer_id
		get_tree().create_timer(0.1).timeout.connect(func() -> void:
			if not _players.has(capture_id):
				print("[PM-DIAG] peer_id=", capture_id, " player already removed — skipping")
				return
			var dp: Node3D = _players[capture_id]
			if not is_instance_valid(dp):
				print("[PM-DIAG] peer_id=", capture_id, " player invalid — skipping")
				return
			var cm: Node3D = dp.get_node_or_null("PlayerBody/CharacterMesh")
			print("[PM-DIAG] peer_id=", capture_id,
				" player.visible=", dp.visible,
				" player.global_pos=", dp.global_position,
				" CharacterMesh.node=", ("found" if cm != null else "NULL"),
				" CharacterMesh.visible=", (cm.visible if cm != null else "N/A"),
				" CharacterMesh.children=", (cm.get_child_count() if cm != null else -1),
				" player.parent=", (dp.get_parent().name if dp.get_parent() != null else "NULL"),
				" GameSync.player_dead[peer]=", GameSync.player_dead.get(capture_id, false),
				" _players.has=", _players.has(capture_id))
			if not dp.visible:
				print("[PM-DIAG] WARNING: player.visible=false at 0.1s — " +
					"unexpected: players should always be visible.")
		)

	var p: BasePlayer = _players[peer_id]
	if is_instance_valid(p):
		p.update_transform(pos, rot)

func remove_player(peer_id: int) -> void:
	print("[PM-RM] remove_player peer_id=", peer_id,
		" had_player=", _players.has(peer_id))
	if _players.has(peer_id):
		var p: BasePlayer = _players[peer_id]
		if is_instance_valid(p):
			p.queue_free()
		_players.erase(peer_id)

func _on_player_died(peer_id: int) -> void:
	var had_player: bool = _players.has(peer_id)
	print("[PM-DIED] peer_id=", peer_id,
		" had_player=", had_player,
		" is_server=", (multiplayer.is_server() if multiplayer != null else "n/a"),
		" GameSync.player_dead=", GameSync.player_dead)
	if had_player:
		var p: Variant = _players[peer_id]
		if is_instance_valid(p):
			var bp: BasePlayer = p
			var was_visible: bool = bp.visible
			bp._set_alive(false)
			print("[PM-DIED] player hidden peer_id=", peer_id,
				" was_visible=", was_visible)
		else:
			print("[PM-DIED] player invalid peer_id=", peer_id, " — skipping")
	else:
		print("[PM-DIED] no player for peer_id=", peer_id,
			" — will be hidden at spawn time via GameSync.player_dead")

func _on_player_respawned(peer_id: int, spawn_pos: Vector3) -> void:
	var had_player: bool = _players.has(peer_id)
	print("[PM-RESP] peer_id=", peer_id,
		" had_player=", had_player,
		" spawn_pos=", spawn_pos,
		" is_server=", (multiplayer.is_server() if multiplayer != null else "n/a"),
		" GameSync.player_dead=", GameSync.player_dead)
	if had_player:
		var p: Variant = _players[peer_id]
		if is_instance_valid(p):
			var bp: BasePlayer = p
			var was_visible: bool = bp.visible
			bp._set_alive(true)
			bp.update_transform(spawn_pos, bp.rotation)
			print("[PM-RESP] player shown peer_id=", peer_id,
				" was_visible=", was_visible)
		else:
			print("[PM-RESP] player invalid peer_id=", peer_id, " — skipping")
	else:
		print("[PM-RESP] no player for peer_id=", peer_id,
			" — player will be created visible when first transform arrives " +
			"(GameSync.player_dead should now be false)")
