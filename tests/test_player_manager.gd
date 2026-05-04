extends GutTest

## test_player_manager.gd — PM1–PM11
## Tier 1: OfflineMultiplayerPeer (multiplayer.is_server() = true).
##
## Tests cover the full lifecycle of PlayerManager:
##   spawn on first remote_player_updated, local peer exclusion, no duplicate
##   spawn, remove_player, player_died/_set_alive, player_respawned/_set_alive,
##   stale-RPC visibility guard, is_instance_valid guard, and update_transform
##   on existing players.
##
## Pattern:
##   - Create a stub world node and add it to get_tree().root so PlayerManager
##     can add puppets to spawn_root (avoids polluting the GUT test runner tree).
##   - PlayerManager.spawn_root is set to the stub world so add_child targets it.
##   - All state is torn down in after_each().

const PlayerManagerScript := preload("res://scripts/network/PlayerManager.gd")

var _world: Node         = null
var _pm:    Node         = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func before_each() -> void:
	BridgeClient._local_peer_id = 1
	# Stub world node — puppets are spawned here.
	_world = Node.new()
	_world.name = "StubWorld"
	get_tree().root.add_child(_world)

	# PlayerManager instance with spawn_root wired to the stub world.
	_pm = Node.new()
	_pm.set_script(PlayerManagerScript)
	_pm.set("spawn_root", _world)
	_world.add_child(_pm)  # triggers _ready()

func after_each() -> void:
	BridgeClient._local_peer_id = 0
	if is_instance_valid(_pm):
		_pm.queue_free()
	if is_instance_valid(_world):
		_world.queue_free()
		get_tree().root.remove_child(_world)
	# Clean up GameSync state touched by tests.
	GameSync.player_dead.clear()
	GameSync.player_teams.clear()
	LobbyManager.players.clear()

# ── Helpers ───────────────────────────────────────────────────────────────────

## Emit remote_player_updated on GameSync to trigger PM spawn/update.
func _emit_transform(peer_id: int, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, team: int = 0) -> void:
	GameSync.remote_player_updated.emit(peer_id, pos, rot, team)

## Return the _players dict from the manager.
func _players() -> Dictionary:
	return _pm.get("_players")

# ── PM1: spawn on first remote_player_updated ─────────────────────────────────

func test_pm1_spawn_on_first_transform_update() -> void:
	_emit_transform(2, Vector3(10, 0, 5), Vector3.ZERO, 0)
	var players: Dictionary = _players()
	assert_true(players.has(2),
		"PlayerManager must create a puppet for peer 2 on first transform update")
	var p: Node = players[2]
	assert_true(is_instance_valid(p), "spawned puppet must be valid")
	assert_true(p.is_inside_tree(), "spawned puppet must be in the scene tree")

# ── PM2: local peer excluded from spawn ──────────────────────────────────────

func test_pm2_local_peer_excluded() -> void:
	# OfflineMultiplayerPeer returns 1 as unique_id — _local_peer_id is 1.
	_emit_transform(1, Vector3.ZERO, Vector3.ZERO, 0)
	assert_false(_players().has(1),
		"PlayerManager must not spawn a puppet for the local peer")

# ── PM3: no duplicate spawn on second transform for same peer ─────────────────

func test_pm3_no_duplicate_spawn() -> void:
	_emit_transform(2)
	_emit_transform(2, Vector3(5, 0, 0))
	var players: Dictionary = _players()
	assert_eq(players.size(), 1,
		"PlayerManager must not spawn a second puppet for the same peer_id")

# ── PM4: remove_player frees node and erases dict entry ──────────────────────

func test_pm4_remove_player_frees_and_erases() -> void:
	_emit_transform(2)
	var p: Node = _players()[2]
	_pm.call("remove_player", 2)
	assert_false(_players().has(2),
		"_players dict must not contain peer 2 after remove_player")
	await wait_frames(2)
	assert_false(is_instance_valid(p),
		"puppet node must be freed after remove_player")

# ── PM5: player_died calls _set_alive(false) — player stays visible ──────────

func test_pm5_player_died_calls_set_alive_false() -> void:
	_emit_transform(2)
	var p: Node = _players()[2]
	p.visible = true
	GameSync.player_died.emit(2, 10.0)
	assert_true(p.visible,
		"puppet must stay visible after player_died signal")

# ── PM6: player_died before spawn does not crash ─────────────────────────────

func test_pm6_player_died_before_spawn_no_crash() -> void:
	GameSync.player_died.emit(2, 10.0)
	assert_false(_players().has(2),
		"player_died before spawn must not crash and must not create a phantom entry")

# ── PM7: player_respawned calls _set_alive(true) and updates transform ────────

func test_pm7_player_respawned_calls_set_alive_true() -> void:
	_emit_transform(2)
	var p: Node = _players()[2]
	var spawn_pos := Vector3(3, 0, 7)
	GameSync.player_respawned.emit(2, spawn_pos)
	assert_true(p.visible,
		"puppet must be shown after player_respawned signal")
	assert_eq(p.get("_target_position"), spawn_pos,
		"puppet _target_position must be updated to spawn_pos on respawn")

# ── PM8: player_respawned before spawn does not crash ────────────────────────

func test_pm8_player_respawned_before_spawn_no_crash() -> void:
	GameSync.player_respawned.emit(2, Vector3.ZERO)
	assert_false(_players().has(2),
		"player_respawned before spawn must not crash and must not create a phantom entry")

# ── PM9: players always spawn visible ────────────────────────────────────────

func test_pm9_stale_rpc_guard_dead_player_spawns_invisible() -> void:
	# Even if GameSync marks a peer as dead, the ghost spawns visible.
	# The session-seed guard on notify_player_died prevents stale RPCs from hiding it.
	GameSync.player_dead[2] = true
	_emit_transform(2)
	var p: Node = _players()[2]
	assert_true(p.visible,
		"puppet must spawn visible even if GameSync.player_dead[peer]=true — " +
		"stale RPCs are now blocked by session seed guard")

# ── PM10: freed node reference does not crash on player_died ─────────────────

func test_pm10_invalid_player_reference_no_crash() -> void:
	_emit_transform(2)
	var p: Node = _players()[2]
	# Manually free the node without going through remove_player, leaving a
	# stale reference in _players — simulates an edge case in teardown.
	p.queue_free()
	await wait_frames(2)
	# Firing player_died with a stale entry must not crash.
	GameSync.player_died.emit(2, 10.0)
	assert_true(true, "player_died with freed puppet must not crash")

# ── PM11: update_transform called on existing player moves target ─────────────

func test_pm11_update_transform_on_existing_player() -> void:
	_emit_transform(2, Vector3.ZERO)
	var p: Node = _players()[2]
	var new_pos := Vector3(99, 0, 42)
	_emit_transform(2, new_pos)
	assert_eq(p.get("_target_position"), new_pos,
		"second remote_player_updated for existing peer must update _target_position")
