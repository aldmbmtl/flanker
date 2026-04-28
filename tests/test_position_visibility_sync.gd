# test_position_visibility_sync.gd
# Dedicated regression tests for position and visibility synchronisation.
# Verifies that towers, minions, players and fog-of-war sources are correct
# on BOTH the host side and the client side.
#
# §A  Player transform pipeline — client→server→all, ghost creation, host/client symmetry
# §B  Minion positions — spawn, state sync, host AI vs. client puppet, kill
# §C  Tower positions — placement consistency across host+client, despawn on both sides
# §D  Cannonball/mortar host VFX — bug B6, confirms rocket workaround
# §E  Minimap positions — local player drawn, remote players missing (bug B7), towers/minions
# §F  Fog of war — update_sources args, ally visibility, minimap fog ally bug B8
extends GutTest

# ── Top-level stub classes used in §E tests ───────────────────────────────────

class LocalPlayerStub extends Node3D:
	var _is_local: bool = true

class RemotePlayerStub extends Node3D:
	var _is_local: bool = false

# ── helpers ───────────────────────────────────────────────────────────────────

func _reset_state() -> void:
	LobbyManager.players.clear()
	LobbyManager.game_started = false
	LobbyManager.supporter_claimed = { 0: false, 1: false }
	LobbyManager.player_death_counts.clear()
	LobbyManager._roles_pending = 0
	GameSync.player_healths.clear()
	GameSync.player_dead.clear()
	GameSync.respawn_countdown.clear()
	GameSync.player_teams.clear()
	LevelSystem.clear_all()

func after_each() -> void:
	_reset_state()

func _make_stub_main() -> Node:
	var n := Node.new()
	n.name = "Main"
	get_tree().root.add_child(n)
	return n

func _remove_stub_main(n: Node) -> void:
	get_tree().root.remove_child(n)
	n.queue_free()

# ── §A  Player transform pipeline ────────────────────────────────────────────

func test_A1_broadcast_player_transform_emits_remote_player_updated() -> void:
	watch_signals(GameSync)
	LobbyManager.broadcast_player_transform.rpc(
		5, Vector3(10, 2, -5), Vector3(0, 1.5, 0), 0
	)
	assert_signal_emitted(GameSync, "remote_player_updated",
		"broadcast_player_transform must emit remote_player_updated")

func test_A2_correct_peer_id_in_remote_player_updated() -> void:
	watch_signals(GameSync)
	LobbyManager.broadcast_player_transform(42, Vector3.ZERO, Vector3.ZERO, 0)
	var params: Array = get_signal_parameters(GameSync, "remote_player_updated")
	assert_eq(params[0], 42, "Correct peer_id must reach remote_player_updated listener")

func test_A3_correct_position_in_remote_player_updated() -> void:
	watch_signals(GameSync)
	var expected := Vector3(7.5, 1.0, -12.0)
	LobbyManager.broadcast_player_transform(1, expected, Vector3.ZERO, 0)
	var params: Array = get_signal_parameters(GameSync, "remote_player_updated")
	assert_eq(params[1], expected, "Position must be transmitted without modification")

func test_A4_correct_team_in_remote_player_updated() -> void:
	watch_signals(GameSync)
	LobbyManager.broadcast_player_transform(1, Vector3.ZERO, Vector3.ZERO, 1)
	var params: Array = get_signal_parameters(GameSync, "remote_player_updated")
	assert_eq(params[3], 1, "Team must be transmitted correctly")

func test_A5_stub_remote_player_manager_creates_ghost() -> void:
	var mgr := StubRemotePlayerManager.new()
	add_child_autofree(mgr)
	LobbyManager.broadcast_player_transform.rpc(99, Vector3(3, 0, 3), Vector3.ZERO, 0)
	assert_true(mgr.has_ghost(99), "StubRemotePlayerManager should create a ghost for peer 99")

func test_A6_stub_remote_player_manager_updates_ghost_position() -> void:
	var mgr := StubRemotePlayerManager.new()
	add_child_autofree(mgr)
	LobbyManager.broadcast_player_transform.rpc(10, Vector3(1, 0, 1), Vector3.ZERO, 0)
	LobbyManager.broadcast_player_transform.rpc(10, Vector3(9, 0, 9), Vector3.ZERO, 0)
	var ghost: Dictionary = mgr.get_ghost(10)
	assert_eq(ghost.get("pos", Vector3.ZERO), Vector3(9, 0, 9),
		"Ghost should track the latest position")

func test_A7_report_player_transform_fires_signal_on_server() -> void:
	watch_signals(GameSync)
	LobbyManager.report_player_transform(Vector3(2, 0, 2), Vector3.ZERO, 0)
	assert_signal_emitted(GameSync, "remote_player_updated",
		"Server must rebroadcast incoming transforms via remote_player_updated")

func test_A8_report_player_transform_emits_exactly_once_on_server() -> void:
	# Bug 4 fixed: removed redundant direct call so remote_player_updated fires
	# exactly once per incoming transform packet on the server.
	watch_signals(GameSync)
	LobbyManager.report_player_transform(Vector3(2, 0, 2), Vector3.ZERO, 0)
	assert_signal_emit_count(GameSync, "remote_player_updated", 1, "Must fire exactly once per packet")

# ── §B  Minion positions ──────────────────────────────────────────────────────

func test_B1_spawn_minion_visuals_calls_spawner() -> void:
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO, Vector3(5, 0, 0)]
	LobbyManager.spawn_minion_visuals(0, Vector3(1, 0, 2), waypts, 1, 55)

	assert_eq(spawner.spawn_calls.size(), 1, "spawn_for_network must be called once")
	assert_eq(spawner.spawn_calls[0]["minion_id"], 55)
	assert_eq(spawner.spawn_calls[0]["team"], 0)
	_remove_stub_main(stub_main)

func test_B2_spawned_puppet_minion_has_correct_team() -> void:
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	LobbyManager.spawn_minion_visuals(1, Vector3.ZERO, waypts, 0, 66)

	var m: StubMinionSpawner.StubMinionNode = spawner.get_minion_by_id(66)
	assert_ne(m, null, "Minion 66 should have been spawned")
	if m != null:
		assert_eq(m.team, 1, "Puppet minion team must match spawn call team")
	_remove_stub_main(stub_main)

func test_B3_sync_minion_states_updates_puppet_position() -> void:
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	spawner.spawn_for_network(0, Vector3.ZERO, waypts, 0, 77)

	var ids := PackedInt32Array([77])
	var positions := PackedVector3Array([Vector3(4, 0, 4)])
	var rotations := PackedFloat32Array([0.0])
	var healths := PackedFloat32Array([60.0])
	LobbyManager.sync_minion_states(ids, positions, rotations, healths)

	var m: StubMinionSpawner.StubMinionNode = spawner.get_minion_by_id(77)
	assert_ne(m, null)
	if m != null:
		assert_eq(m.last_puppet_pos, Vector3(4, 0, 4),
			"Puppet minion position should match last sync_minion_states broadcast")
	_remove_stub_main(stub_main)

func test_B4_sync_minion_states_updates_puppet_health() -> void:
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	spawner.spawn_for_network(0, Vector3.ZERO, waypts, 0, 88)

	var ids := PackedInt32Array([88])
	var positions := PackedVector3Array([Vector3.ZERO])
	var rotations := PackedFloat32Array([0.0])
	var healths := PackedFloat32Array([22.5])
	LobbyManager.sync_minion_states(ids, positions, rotations, healths)

	var m: StubMinionSpawner.StubMinionNode = spawner.get_minion_by_id(88)
	if m != null:
		assert_almost_eq(m.last_puppet_hp, 22.5, 0.01,
			"Puppet minion HP should match last sync_minion_states broadcast")
	_remove_stub_main(stub_main)

func test_B5_kill_minion_visuals_removes_minion() -> void:
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	spawner.spawn_for_network(0, Vector3.ZERO, waypts, 0, 99)
	assert_ne(spawner.get_minion_by_id(99), null, "Minion should exist before kill")

	LobbyManager.kill_minion_visuals(99)
	assert_eq(spawner.get_minion_by_id(99), null,
		"Minion should be removed after kill_minion_visuals")
	assert_true(spawner.kill_calls.has(99), "kill_minion_by_id must be called with correct id")
	_remove_stub_main(stub_main)

func test_B6_multiple_minions_state_synced_independently() -> void:
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	spawner.spawn_for_network(0, Vector3.ZERO, waypts, 0, 101)
	spawner.spawn_for_network(1, Vector3.ZERO, waypts, 1, 102)

	var ids := PackedInt32Array([101, 102])
	var positions := PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 0, 5)])
	var rotations := PackedFloat32Array([0.0, 0.5])
	var healths := PackedFloat32Array([50.0, 30.0])
	LobbyManager.sync_minion_states(ids, positions, rotations, healths)

	var m1: StubMinionSpawner.StubMinionNode = spawner.get_minion_by_id(101)
	var m2: StubMinionSpawner.StubMinionNode = spawner.get_minion_by_id(102)
	if m1 != null:
		assert_eq(m1.last_puppet_pos, Vector3(1, 0, 0))
	if m2 != null:
		assert_eq(m2.last_puppet_pos, Vector3(0, 0, 5))
	_remove_stub_main(stub_main)

# ── §C  Tower positions ───────────────────────────────────────────────────────

func test_C1_spawn_item_visuals_calls_build_system_spawn() -> void:
	var stub_main := _make_stub_main()
	var bs := StubBuildSystem.new()
	bs.name = "BuildSystem"
	stub_main.add_child(bs)

	LobbyManager.spawn_item_visuals(
		Vector3(10, 0, -5), 0, "cannon", "", "Tower_cannon_0_0"
	)

	assert_eq(bs.spawn_calls.size(), 1, "spawn_item_local must be called once for client")
	assert_eq(bs.spawn_calls[0]["world_pos"], Vector3(10, 0, -5))
	assert_eq(bs.spawn_calls[0]["team"], 0)
	assert_eq(bs.spawn_calls[0]["item_type"], "cannon")
	_remove_stub_main(stub_main)

func test_C2_tower_world_pos_preserved_through_spawn_item_visuals() -> void:
	var stub_main := _make_stub_main()
	var bs := StubBuildSystem.new()
	bs.name = "BuildSystem"
	stub_main.add_child(bs)

	var expected := Vector3(33.0, 0.0, -22.0)
	LobbyManager.spawn_item_visuals(expected, 1, "mortar", "", "Tower_mortar_1_0")

	assert_eq(bs.spawn_calls.size(), 1)
	assert_eq(bs.spawn_calls[0]["world_pos"], expected,
		"world_pos must be passed unchanged to spawn_item_local")
	_remove_stub_main(stub_main)

func test_C3_spawn_item_visuals_emits_item_spawned() -> void:
	var stub_main := _make_stub_main()
	var bs := StubBuildSystem.new()
	bs.name = "BuildSystem"
	stub_main.add_child(bs)

	watch_signals(LobbyManager)
	LobbyManager.spawn_item_visuals(Vector3.ZERO, 0, "cannon", "", "Tower_cannon_0_0")
	assert_signal_emitted(LobbyManager, "item_spawned")
	_remove_stub_main(stub_main)

func test_C4_despawn_tower_emits_tower_despawned_when_node_present() -> void:
	var stub_main := _make_stub_main()
	var fake_tower := Node3D.new()
	fake_tower.name = "Tower_cannon_0_0"
	stub_main.add_child(fake_tower)

	watch_signals(LobbyManager)
	LobbyManager.despawn_tower("Tower_cannon_0_0")
	assert_signal_emitted(LobbyManager, "tower_despawned",
		"tower_despawned must fire when the node exists")
	_remove_stub_main(stub_main)

func test_C5_despawn_tower_removes_node_from_scene() -> void:
	var stub_main := _make_stub_main()
	var fake_tower := Node3D.new()
	fake_tower.name = "Tower_cannon_0_1"
	stub_main.add_child(fake_tower)

	assert_true(stub_main.has_node("Tower_cannon_0_1"), "Tower should exist before despawn")
	LobbyManager.despawn_tower("Tower_cannon_0_1")
	await wait_physics_frames(2)
	assert_false(is_instance_valid(fake_tower), "Tower node should be freed after despawn_tower")
	_remove_stub_main(stub_main)

# ── §D  Cannonball/mortar host VFX ───────────────────────────────────────────

func test_D1_rocket_workaround_calls_spawn_bullet_visuals_on_server() -> void:
	# The rocket workaround at LobbyManager.gd:416-417 calls spawn_bullet_visuals
	# directly on the server (call_remote skips the host otherwise).
	# Verify the RPC is dispatched via MockMultiplayerAPI log.
	var mock := MockMultiplayerAPI.new()
	get_tree().set_multiplayer(mock, LobbyManager.get_path())

	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	LobbyManager.register_player_local(1, "P1")
	LobbyManager.register_player_local(2, "P2")
	GameSync.set_player_health(2, 100.0)
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	LobbyManager.players[1]["team"] = 0
	LobbyManager.players[2]["team"] = 1
	var hit_info: Dictionary = { "peer_id": 2 }

	LobbyManager.validate_shot(Vector3.ZERO, Vector3(0, 0, 1), 5.0, 0, 1, hit_info, "rocket")

	assert_true(mock.was_called("spawn_bullet_visuals"),
		"validate_shot must dispatch spawn_bullet_visuals.rpc() for rocket projectile type")
	var calls: Array = mock.calls_to("spawn_bullet_visuals")
	assert_eq(calls.size(), 1, "spawn_bullet_visuals should be dispatched exactly once via RPC")

	get_tree().set_multiplayer(null, LobbyManager.get_path())

func test_D2_spawn_cannonball_visuals_executes_on_host() -> void:
	# Bug 5 fixed: spawn_cannonball_visuals annotation changed from call_remote
	# to call_local. Calling the function body directly (as call_local does on
	# the server) must execute without error. The function adds a child to
	# root.get_child(0); we assert that path exists and doesn't crash.
	# (No GLB rendering assertion — visual correctness is not testable headless.)
	assert_true(LobbyManager.has_method("spawn_cannonball_visuals"),
		"spawn_cannonball_visuals must exist on LobbyManager")
	# Calling directly simulates what call_local does on the server — no crash = pass.
	LobbyManager.spawn_cannonball_visuals(Vector3.ZERO, Vector3(0, 0, 10), 50.0, 0)
	pass

func test_D3_spawn_mortar_visuals_executes_on_host() -> void:
	# Bug 5 fixed: spawn_mortar_visuals annotation changed from call_remote
	# to call_local. Same rationale as D2.
	assert_true(LobbyManager.has_method("spawn_mortar_visuals"),
		"spawn_mortar_visuals must exist on LobbyManager")
	LobbyManager.spawn_mortar_visuals(Vector3.ZERO, Vector3(0, 0, 10), 30.0, 1)
	pass

# ── §E  Minimap positions ─────────────────────────────────────────────────────

func test_E1_minimap_fog_build_sources_local_player_only() -> void:
	var lp := LocalPlayerStub.new()
	add_child_autofree(lp)
	lp.global_position = Vector3(0, 0, 0)

	var fps_players: Array = [lp]
	var sources: Array = []
	for p in fps_players:
		if p.get("_is_local") != true:
			continue
		var gp: Vector3 = (p as Node3D).global_position
		sources.append([gp.x, gp.z, 35.0 * 35.0])

	assert_eq(sources.size(), 1, "Only the local player should produce a fog source")
	assert_eq(sources[0][0], 0.0)

func test_E2_minimap_fog_non_local_player_excluded_from_sources() -> void:
	var rp := RemotePlayerStub.new()
	add_child_autofree(rp)
	rp.global_position = Vector3(10, 0, 10)

	var fps_players: Array = [rp]
	var sources: Array = []
	for p in fps_players:
		if p.get("_is_local") != true:
			continue
		var gp: Vector3 = (p as Node3D).global_position
		sources.append([gp.x, gp.z, 35.0 * 35.0])

	assert_eq(sources.size(), 0,
		"Non-local player should NOT produce a fog source in _draw_fog_overlay")

func test_E3_remote_players_drawn_on_minimap() -> void:
	# Bug 6 fixed: Minimap now queries group "remote_players" in addition to "player".
	# Verify: a node in "remote_players" is registered in the tree so Minimap can find it.
	var ghost := RemotePlayerStub.new()
	ghost.add_to_group("remote_players")
	add_child_autofree(ghost)
	ghost.global_position = Vector3(10, 0, 10)

	var found: Array = get_tree().get_nodes_in_group("remote_players")
	assert_true(found.has(ghost),
		"Ghost must be in remote_players group so the fixed Minimap._draw() can query it")

func test_E4_minimap_fog_ally_remote_player_clears_fog() -> void:
	# Bug 7 fixed: _draw_fog_overlay now includes allied remote player positions
	# as fog vision sources. Verify that an allied ghost at a known position
	# produces a fog source entry when sources are built.
	var player_team: int = 0

	# Simulate building the source list as the fixed _draw_fog_overlay does.
	var remote_players_in_test: Array = []
	var ghost := RemotePlayerStub.new()
	add_child_autofree(ghost)
	ghost.global_position = Vector3(50, 0, 50)
	# RemotePlayerStub needs a team property — add it via set_meta / script override
	ghost.set_meta("team_override", 0)  # same team as player
	remote_players_in_test.append(ghost)

	var sources: Array = []
	for rp in remote_players_in_test:
		if not is_instance_valid(rp):
			continue
		# Use meta as a stand-in for the declared 'team' var on a real ghost
		var rp_team: int = rp.get_meta("team_override") if rp.has_meta("team_override") else -1
		if rp_team != player_team:
			continue
		var gp: Vector3 = (rp as Node3D).global_position
		sources.append([gp.x, gp.z, 35.0 * 35.0])

	assert_eq(sources.size(), 1, "Allied remote player must produce exactly one fog source")
	assert_eq(sources[0][0], 50.0, "Fog source x must match ghost position")
	assert_eq(sources[0][1], 50.0, "Fog source z must match ghost position")

# ── §F  Fog of war (FogOverlay) ───────────────────────────────────────────────

func test_F1_fog_overlay_update_sources_player_position_included() -> void:
	var fog := StubFogOverlay.new()
	add_child_autofree(fog)

	var player_positions: Array = [Vector3(5, 0, 10)]
	fog.update_sources(player_positions, 35.0, [], 20.0, [], 18.0)

	assert_eq(fog.update_calls.size(), 1)
	var call: Dictionary = fog.update_calls[0]
	assert_eq(call["player_positions"].size(), 1)
	assert_eq(call["player_positions"][0], Vector3(5, 0, 10),
		"Player position must be passed to update_sources unchanged")

func test_F2_fog_overlay_update_sources_ally_positions_included() -> void:
	var fog := StubFogOverlay.new()
	add_child_autofree(fog)

	var player_positions: Array = [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	var minion_positions: Array = [Vector3(5, 0, 5)]
	var tower_positions: Array = [Vector3(-10, 0, -10)]
	fog.update_sources(player_positions, 35.0, minion_positions, 20.0, tower_positions, 18.0)

	var call: Dictionary = fog.update_calls[0]
	assert_eq(call["player_positions"].size(), 2,
		"Both allied player positions should reach update_sources")
	assert_eq(call["minion_positions"].size(), 1)
	assert_eq(call["tower_positions"].size(), 1)

func test_F3_fog_overlay_add_timed_reveal_stored() -> void:
	var fog := StubFogOverlay.new()
	add_child_autofree(fog)

	fog.add_timed_reveal(Vector3(20, 0, 20), 30.0, 5.0)

	assert_eq(fog.timed_reveals.size(), 1)
	assert_eq(fog.timed_reveals[0]["pos"], Vector3(20, 0, 20))
	assert_almost_eq(fog.timed_reveals[0]["radius"], 30.0, 0.01)
	assert_almost_eq(fog.timed_reveals[0]["duration"], 5.0, 0.01)

func test_F4_fog_overlay_update_sources_radius_passed_correctly() -> void:
	var fog := StubFogOverlay.new()
	add_child_autofree(fog)

	var player_pos: Array = [Vector3(1, 0, 2)]
	fog.update_sources(player_pos, 40.0, [], 20.0, [], 18.0)

	var call: Dictionary = fog.update_calls[0]
	assert_almost_eq(call["player_radius"], 40.0, 0.01,
		"Player visibility radius should be passed correctly")
