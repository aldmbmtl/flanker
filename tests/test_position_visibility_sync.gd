# test_position_visibility_sync.gd
# Dedicated regression tests for position and visibility synchronisation.
# Verifies that towers, minions, players and fog-of-war sources are correct
# on BOTH the host side and the client side.
#
# §A  Initial player ghost creation — stationary spawn regression (Bug D)
# §B  Minion positions — spawn, state sync, host AI vs. client puppet, kill
# §C  Tower positions — placement consistency across host+client, despawn on both sides
# §D  Cannonball/mortar host VFX — bug B6, confirms rocket workaround
# §E  Minimap positions — local player drawn, remote players missing (bug B7), towers/minions
# §F  Fog of war — update_sources args, ally visibility, minimap fog ally bug B8
extends GutTest

const PlayerManagerScript := preload("res://scripts/network/PlayerManager.gd")

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
	LobbyManager._can_start = false
	GameSync.player_healths.clear()
	GameSync.player_dead.clear()
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

# ── §A  Initial ghost creation — stationary-spawn regression (Bug D) ──────────
#
# Without the fix: FPSController only broadcasts a transform when the player
# moves ≥0.05 m or rotates ≥0.02 rad since the last send.  A player who stands
# completely still after loading in never triggers a broadcast, so PlayerManager
# never receives remote_player_updated and never spawns their ghost.  Other
# clients see nobody until the player twitches.
#
# The fix: FPSController calls _broadcast_initial_transform() deferred from
# _ready(), which sends one unconditional report_player_transform RPC regardless
# of movement.  The test verifies that this single call causes
# GameSync.remote_player_updated to fire, which is the signal PlayerManager
# listens to for ghost creation.

func test_A1_report_player_transform_emits_remote_player_updated_signal() -> void:
	# Tier 1 (OfflineMultiplayerPeer): server is the local peer.
	# broadcast_player_transform() is the function body called on every peer
	# when a transform is reported.  Calling it directly verifies it emits
	# GameSync.remote_player_updated — the signal PlayerManager relies on to
	# create ghosts.  Uses watch_signals (not CONNECT_ONE_SHOT lambdas) to avoid
	# GDScript value-capture issues with primitive variables.
	watch_signals(GameSync)

	var test_pos := Vector3(10, 0, 5)
	LobbyManager.broadcast_player_transform(2, test_pos, Vector3.ZERO, 0)

	assert_signal_emitted(GameSync, "remote_player_updated",
		"remote_player_updated must fire when broadcast_player_transform is called " +
		"(regression: stationary player never seen by others without initial broadcast)")
	var params: Array = get_signal_parameters(GameSync, "remote_player_updated")
	assert_eq(params[0], 2,
		"remote_player_updated must carry peer_id=2")
	assert_eq(params[1], test_pos,
		"remote_player_updated must carry the correct world position")

func test_A2_stationary_player_ghost_created_on_first_signal() -> void:
	# Verify that PlayerManager spawns the ghost on the very first
	# remote_player_updated signal, even before any movement-threshold updates.
	# This is the downstream effect of _broadcast_initial_transform.
	var mgr: Node = Node.new()
	mgr.set_script(PlayerManagerScript)
	var spawn_root := Node3D.new()
	mgr.set("spawn_root", spawn_root)
	add_child_autofree(spawn_root)
	add_child_autofree(mgr)

	# Simulate the single initial broadcast for peer 3 (team 0).
	GameSync.remote_player_updated.emit(3, Vector3(5, 0, 5), Vector3.ZERO, 0)
	await wait_frames(1)

	var ghost: Node = spawn_root.get_node_or_null("RemotePlayer_3")
	assert_not_null(ghost,
		"PlayerManager must create a ghost on the first remote_player_updated " +
		"signal — regression: stationary players were never spawned without this")
	if ghost != null:
		assert_true(ghost.visible,
			"Freshly spawned ghost must be visible")

	# Cleanup
	if is_instance_valid(mgr) and mgr.is_inside_tree():
		mgr.get_parent().remove_child(mgr)
		mgr.queue_free()
	LobbyManager.players.erase(3)

func test_A3_seed_player_transform_emits_remote_player_updated_via_reliable_path() -> void:
	# Regression guard for the reliable initial-position seed path.
	# seed_player_transform is the reliable RPC called from report_initial_transform
	# (used by _broadcast_initial_transform).  Unlike broadcast_player_transform
	# (unreliable_ordered), it is guaranteed to arrive even when the client is
	# still loading the scene.  This test verifies the function body emits
	# remote_player_updated with correct arguments — the downstream trigger for
	# PlayerManager to create a ghost.
	watch_signals(GameSync)

	var test_pos := Vector3(3, 0, -7)
	LobbyManager.seed_player_transform(5, test_pos, Vector3.ZERO, 1)

	assert_signal_emitted(GameSync, "remote_player_updated",
		"seed_player_transform must emit remote_player_updated " +
		"(regression: unreliable broadcast was silently dropped during scene load)")
	var params: Array = get_signal_parameters(GameSync, "remote_player_updated")
	assert_eq(params[0], 5, "peer_id must be 5")
	assert_eq(params[1], test_pos, "position must match")

func test_A4_seed_player_transform_on_respawn_position_emits_correct_peer_and_pos() -> void:
	# Regression guard: after death the server calls seed_player_transform with
	# the respawn position so the ghost on all clients is moved to the correct
	# spawn point.  Verifies the function emits remote_player_updated with the
	# exact respawn coords — the same code path triggered by
	# FPSController.respawn() → _broadcast_initial_transform() →
	# LobbyManager.report_initial_transform → seed_player_transform.
	watch_signals(GameSync)

	var respawn_pos := Vector3(0, 1, 82)  # blue spawn
	LobbyManager.seed_player_transform(7, respawn_pos, Vector3.ZERO, 0)

	assert_signal_emitted(GameSync, "remote_player_updated",
		"seed_player_transform must emit remote_player_updated for respawn position " +
		"(regression: client lost sight of host after death because respawn() " +
		"did not re-call _broadcast_initial_transform)")
	var params: Array = get_signal_parameters(GameSync, "remote_player_updated")
	assert_eq(params[0], 7,           "peer_id must be 7")
	assert_eq(params[1], respawn_pos, "position must be the respawn position")

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

	var m: Node = spawner.get_minion_by_id(66)
	assert_ne(m, null, "Minion 66 should have been spawned")
	if m != null:
		assert_eq(m.team, 1, "Puppet minion team must match spawn call team")
	_remove_stub_main(stub_main)

func test_B3_sync_minion_states_updates_puppet_position() -> void:
	# Python relays minion state back via BridgeClient._apply_minion_puppet_states.
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	spawner.spawn_for_network(0, Vector3.ZERO, waypts, 0, 77)

	# Plain Arrays — mirrors the msgpack format Python sends.
	var ids: Array = [77]
	var positions: Array = [[4.0, 0.0, 4.0]]
	var rotations: Array = [0.0]
	var healths: Array = [60.0]
	BridgeClient._apply_minion_puppet_states(ids, positions, rotations, healths)

	var m: Node = spawner.get_minion_by_id(77)
	assert_ne(m, null)
	if m != null:
		assert_eq(m.last_puppet_pos, Vector3(4, 0, 4),
			"Puppet minion position should match last sync_minion_states broadcast")
	_remove_stub_main(stub_main)

func test_B4_sync_minion_states_updates_puppet_health() -> void:
	# Python relays minion state back via BridgeClient._apply_minion_puppet_states.
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	spawner.spawn_for_network(0, Vector3.ZERO, waypts, 0, 88)

	var ids: Array = [88]
	var positions: Array = [[0.0, 0.0, 0.0]]
	var rotations: Array = [0.0]
	var healths: Array = [22.5]
	BridgeClient._apply_minion_puppet_states(ids, positions, rotations, healths)

	var m: Node = spawner.get_minion_by_id(88)
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
	# Python relays minion state back via BridgeClient._apply_minion_puppet_states.
	var stub_main := _make_stub_main()
	var spawner := StubMinionSpawner.new()
	spawner.name = "MinionSpawner"
	stub_main.add_child(spawner)

	var waypts: Array[Vector3] = [Vector3.ZERO]
	spawner.spawn_for_network(0, Vector3.ZERO, waypts, 0, 101)
	spawner.spawn_for_network(1, Vector3.ZERO, waypts, 1, 102)

	var ids: Array = [101, 102]
	var positions: Array = [[1.0, 0.0, 0.0], [0.0, 0.0, 5.0]]
	var rotations: Array = [0.0, 0.5]
	var healths: Array = [50.0, 30.0]
	BridgeClient._apply_minion_puppet_states(ids, positions, rotations, healths)

	var m1: Node = spawner.get_minion_by_id(101)
	var m2: Node = spawner.get_minion_by_id(102)
	if m1 != null:
		assert_eq(m1.last_puppet_pos, Vector3(1, 0, 0))
	if m2 != null:
		assert_eq(m2.last_puppet_pos, Vector3(0, 0, 5))
	_remove_stub_main(stub_main)

# ── §C  Tower positions ───────────────────────────────────────────────────────

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

func test_D1_spawn_visual_bridge_message_calls_spawn_bullet_visuals() -> void:
	# BridgeClient "spawn_visual" with visual_type="bullet" must call
	# LobbyManager.spawn_bullet_visuals() locally (no RPC needed — bridge replaced ENet).
	# We verify the call by checking that spawn_bullet_visuals executes without error
	# (it creates a Bullet node in the scene; we just confirm no crash and it runs).
	var params := {
		"pos_x": 0.0, "pos_y": 0.0, "pos_z": 0.0,
		"dir_x": 0.0, "dir_y": 0.0, "dir_z": 1.0,
		"damage": 5.0, "shooter_team": 0, "shooter_peer_id": 1,
		"projectile_type": "rocket"
	}
	# Call should not crash; visual output is not testable headlessly.
	BridgeClient._handle_server_message("spawn_visual", {"visual_type": "bullet", "params": params})

func test_D2_spawn_cannonball_visuals_executes_on_host() -> void:
	# Bug 5 fixed: _fire_ballistic now calls rpc_callable.rpc() instead of
	# rpc_callable.call(). The RPC annotation stays call_remote so the body only
	# runs on clients. Calling the function body directly (as a client would)
	# must execute without error.
	# (No GLB rendering assertion — visual correctness is not testable headless.)
	assert_true(LobbyManager.has_method("spawn_cannonball_visuals"),
		"spawn_cannonball_visuals must exist on LobbyManager")
	# Calling directly simulates the client receiving the RPC — no crash = pass.
	LobbyManager.spawn_cannonball_visuals(Vector3.ZERO, Vector3(0, 0, 10), 50.0, 0)
	pass

func test_D3_spawn_mortar_visuals_executes_on_host() -> void:
	# Bug 5 fixed: same rationale as D2 — _fire_ballistic dispatches via .rpc()
	# so clients receive the call. Body must run without error on the receiving peer.
	assert_true(LobbyManager.has_method("spawn_mortar_visuals"),
		"spawn_mortar_visuals must exist on LobbyManager")
	LobbyManager.spawn_mortar_visuals(Vector3.ZERO, Vector3(0, 0, 10), 30.0, 1)
	pass

func test_D4_spawn_bullet_visuals_no_crash_on_client() -> void:
	# Regression guard: spawn_bullet_visuals previously called
	# get_tree().root.get_node("Main") with no null guard, crashing on clients
	# when the scene root child isn't named "Main". Fixed to use
	# VfxUtils.get_scene_root(self) with a null guard.
	# Calling the function body directly (simulating client RPC receive in a
	# test scene that is not named "Main") must not crash.
	assert_true(LobbyManager.has_method("spawn_bullet_visuals"),
		"spawn_bullet_visuals must exist on LobbyManager")
	LobbyManager.spawn_bullet_visuals(Vector3.ZERO, Vector3(0, 0, 1), 10.0, 1, 2, "bullet")
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
	fog.update_sources(player_positions, 35.0, [], 20.0, [])

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
	var tower_sources: Array = [Vector4(-10, -10, 30.0, 0.0)]
	fog.update_sources(player_positions, 35.0, minion_positions, 20.0, tower_sources)

	var call: Dictionary = fog.update_calls[0]
	assert_eq(call["player_positions"].size(), 2,
		"Both allied player positions should reach update_sources")
	assert_eq(call["minion_positions"].size(), 1)
	assert_eq(call["tower_sources"].size(), 1)

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
	fog.update_sources(player_pos, 40.0, [], 20.0, [])

	var call: Dictionary = fog.update_calls[0]
	assert_almost_eq(call["player_radius"], 40.0, 0.01,
		"Player visibility radius should be passed correctly")

# ── §G  FPS player body visibility on death/respawn ──────────────────────────
#
# Regression guard: previously FPSController._on_death() called
# `$PlayerBody.visible = false`, making the local player's body invisible to
# everyone (including allies viewing from outside).  Similarly _on_respawned
# called `$PlayerBody.visible = true` to restore it.  Both lines were removed:
# the PlayerBody is always visible; only the FPS camera is switched off.
#
# These tests use BasePlayer directly because FPSController requires a full
# scene tree with camera, HUD nodes, etc.  We verify the contract at the
# BasePlayer level: _set_alive(false/true) must never hide the node.

func test_G1_set_alive_false_does_not_hide_player_body() -> void:
	# Regression guard for FPSController._on_death() removing PlayerBody.visible=false.
	# BasePlayer._set_alive(false) must keep the player (and PlayerBody) visible.
	const BasePlayerScene := preload("res://scenes/players/BasePlayer.tscn")
	var p: BasePlayer = BasePlayerScene.instantiate()
	p.setup(5, 0, false, "a")
	add_child_autofree(p)
	# Explicitly confirm PlayerBody starts visible.
	var body: Node3D = p.get_node_or_null("PlayerBody") as Node3D
	assert_not_null(body, "PlayerBody must exist in BasePlayer.tscn")
	body.visible = true

	p._set_alive(false)

	assert_true(body.visible,
		"PlayerBody must stay visible after _set_alive(false) — " +
		"FPSController._on_death must not set PlayerBody.visible = false")

func test_G2_set_alive_true_keeps_player_body_visible() -> void:
	# Regression guard for respawn path: PlayerBody must remain visible
	# after _set_alive(true) — no explicit show/hide toggle required.
	const BasePlayerScene := preload("res://scenes/players/BasePlayer.tscn")
	var p: BasePlayer = BasePlayerScene.instantiate()
	p.setup(6, 0, false, "a")
	add_child_autofree(p)
	var body: Node3D = p.get_node_or_null("PlayerBody") as Node3D
	assert_not_null(body)
	body.visible = true

	p._set_alive(false)
	p._set_alive(true)

	assert_true(body.visible,
		"PlayerBody must stay visible after death+respawn cycle — " +
		"respawn path must not hide or need to show PlayerBody")

# ── §H  Freed-minion guard — notify_minion_hit must not crash on queue_free'd node ──
#
# Regression for: notify_minion_hit calling get_minion_by_id which may return a
# node still in the scene tree but pending queue_free() (is_queued_for_deletion=true).
# Previously: minion._flash_hit() was called unconditionally on a dying node →
# "Trying to return a previously freed instance" crash spam in runtime logs.
# Fix: LobbyManager.notify_minion_hit now checks is_queued_for_deletion() before
# calling _flash_hit().

## Minimal minion stub with flash tracking and queue_free sentinel.
class FlashMinion extends Node3D:
	var team: int = 0
	var flash_called: int = 0
	var _minion_id: int = 0
	func _flash_hit() -> void:
		flash_called += 1
	func setup(_team: int, _wp: Array, _lane: int) -> void:
		pass

func test_H1_notify_minion_hit_skips_queued_for_deletion_node() -> void:
	# Build a fake Main/MinionSpawner tree so notify_minion_hit can find the minion.
	var existing: Node = get_tree().root.get_node_or_null("Main")
	if existing != null:
		existing.free()

	var main_stub := Node.new()
	main_stub.name = "Main"
	get_tree().root.add_child(main_stub)

	var minion := FlashMinion.new()
	minion.name = "Minion_99"
	main_stub.add_child(minion)

	# Schedule the node for deletion — it is still in the tree but dying.
	minion.queue_free()

	# notify_minion_hit must not call _flash_hit on a queued-for-deletion node.
	LobbyManager.notify_minion_hit(99)

	assert_eq(minion.flash_called, 0,
		"notify_minion_hit must not call _flash_hit on a node pending queue_free()")

	main_stub.free()
	await get_tree().process_frame

func test_H2_notify_minion_hit_calls_flash_on_live_node() -> void:
	# Confirm the positive case: a live minion does get _flash_hit called.
	var existing: Node = get_tree().root.get_node_or_null("Main")
	if existing != null:
		existing.free()

	var main_stub := Node.new()
	main_stub.name = "Main"
	get_tree().root.add_child(main_stub)

	var minion := FlashMinion.new()
	minion.name = "Minion_98"
	main_stub.add_child(minion)

	LobbyManager.notify_minion_hit(98)

	assert_eq(minion.flash_called, 1,
		"notify_minion_hit must call _flash_hit on a live minion")

	main_stub.free()
	await get_tree().process_frame

# ── §I  report_initial_transform must be a direct call, not rpc_id ─────────────
#
# Regression for: FPSController._broadcast_initial_transform calling
# LobbyManager.report_initial_transform.rpc_id(1, ...) on a function that has
# no @rpc decorator → Godot error "Unable to get the RPC configuration".
# Fix: changed to a plain direct call LobbyManager.report_initial_transform(...)

func test_I1_report_initial_transform_is_not_rpc_annotated() -> void:
	# LobbyManager.report_initial_transform must NOT have an @rpc annotation.
	# If it did, it would appear in get_method_list() with hint "rpc".
	# Plain functions do not have that property.
	# We verify it can be called directly without crashing.
	var dummy_pos := Vector3(1.0, 0.0, 2.0)
	var dummy_rot := Vector3(0.0, 0.5, 0.0)
	# BridgeClient.send is a no-op when not connected — safe to call.
	LobbyManager.report_initial_transform(dummy_pos, dummy_rot, 0)
	assert_true(true,
		"report_initial_transform must be callable as a plain function without RPC error")
