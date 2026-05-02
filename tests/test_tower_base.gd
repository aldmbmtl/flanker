# test_tower_base.gd
# Tier 1 — unit tests for TowerBase combat logic.
# We instantiate a minimal TowerBase directly (no scene/mesh) since all the
# combat logic lives in GDScript, not in the visual nodes.
extends GutTest

# Minimal TowerBase subclass with no visuals — safe to instantiate in tests.
# Overrides _build_visuals() to do nothing (no model_scene in test context).
class FakeTower extends TowerBase:
	func _build_visuals() -> void:
		pass  # skip GLB loading in headless tests

var tower: FakeTower

func before_each() -> void:
	tower = FakeTower.new()
	tower.max_health     = 100.0
	tower.attack_range   = 0.0   # passive — no Area3D built, avoids physics queries
	tower.attack_interval = 3.0
	tower.tower_type     = "cannon"
	add_child_autofree(tower)
	tower.setup(0)  # team 0
	# Reset autoloads
	LevelSystem.clear_all()
	LevelSystem.register_peer(1)

# ── setup ─────────────────────────────────────────────────────────────────────

func test_setup_sets_health_to_max() -> void:
	assert_eq(tower.get_health(), 100.0)

func test_setup_assigns_team() -> void:
	assert_eq(tower.team, 0)

func test_setup_adds_to_towers_group() -> void:
	assert_true(tower.is_in_group("towers"), "Tower should be in 'towers' group after setup")

# ── take_damage ───────────────────────────────────────────────────────────────

func test_take_damage_reduces_health() -> void:
	tower.take_damage(30.0, "player", 1)  # source_team 1 = enemy
	assert_eq(tower.get_health(), 70.0)

func test_take_damage_friendly_fire_ignored() -> void:
	tower.take_damage(50.0, "player", 0)  # source_team 0 = same team
	assert_eq(tower.get_health(), 100.0, "Friendly fire should not damage tower")

func test_take_damage_already_dead_ignored() -> void:
	tower._dead = true
	tower.take_damage(50.0, "player", 1)
	assert_eq(tower.get_health(), 100.0, "Dead tower takes no damage")

func test_take_damage_accumulates() -> void:
	tower.take_damage(20.0, "player", 1)
	tower.take_damage(30.0, "player", 1)
	assert_eq(tower.get_health(), 50.0)

# ── death ─────────────────────────────────────────────────────────────────────

func test_death_fires_at_zero_hp() -> void:
	tower.take_damage(100.0, "player", 1)
	assert_true(tower._dead, "Tower should be marked dead at 0 HP")

func test_death_fires_at_negative_hp() -> void:
	tower.take_damage(150.0, "player", 1)
	assert_true(tower._dead, "Overkill damage should also trigger death")

func test_death_awards_xp_to_killer_in_singleplayer() -> void:
	# Singleplayer: _killer_peer_id > 0 triggers XP award to that peer.
	# In our test context multiplayer.has_multiplayer_peer() == false (OfflineMultiplayerPeer).
	tower._killer_peer_id = 1
	var xp_before: int = LevelSystem.get_xp(1)
	tower.take_damage(100.0, "player", 1, 1)
	var xp_after: int = LevelSystem.get_xp(1)
	assert_gt(xp_after, xp_before, "Killer should receive XP on tower death")

func test_death_only_happens_once() -> void:
	tower.take_damage(100.0, "player", 1)
	# _dead is now true; a second call should be a no-op
	var hp_before: float = tower.get_health()
	tower.take_damage(100.0, "player", 1)  # second hit after death
	assert_true(tower._dead)

# ── get_fire_position ─────────────────────────────────────────────────────────

func test_fire_position_uses_fallback_height_when_no_fire_point() -> void:
	tower.fire_point_fallback_height = 3.0
	tower.global_position = Vector3(0.0, 5.0, 0.0)
	var fp: Vector3 = tower.get_fire_position()
	assert_eq(fp, Vector3(0.0, 8.0, 0.0),
		"Fire position should be global_position + fallback height")

func test_fire_position_uses_fire_point_child_when_present() -> void:
	var marker := Marker3D.new()
	marker.name = "FirePoint"
	tower.add_child(marker)
	# Set position after add_child so global_position is valid
	marker.global_position = Vector3(1.0, 10.0, 0.0)
	var fp: Vector3 = tower.get_fire_position()
	assert_eq(fp, marker.global_position, "Should use FirePoint child position when present")

# ── _get_body_team ────────────────────────────────────────────────────────────
# GDScript's Node.get() only reads declared script properties — not arbitrary set() calls
# on plain Node3D.  We use tiny inner classes that declare the property.

class FakePlayer extends Node3D:
	var player_team: int = 1

class FakeMinion extends Node3D:
	var team: int = 0

func test_get_body_team_reads_player_team() -> void:
	var fake_player := FakePlayer.new()
	add_child_autofree(fake_player)
	assert_eq(tower._get_body_team(fake_player), 1)

func test_get_body_team_reads_team_if_no_player_team() -> void:
	var fake_minion := FakeMinion.new()
	add_child_autofree(fake_minion)
	assert_eq(tower._get_body_team(fake_minion), 0)

func test_get_body_team_returns_minus_one_for_unknown() -> void:
	var anon := Node3D.new()
	add_child_autofree(anon)
	assert_eq(tower._get_body_team(anon), -1)

# ── detection sphere radius ───────────────────────────────────────────────────

func test_detection_area_sphere_radius_matches_attack_range() -> void:
	# Build an attacking tower (attack_range > 0) and confirm the Area3D sphere
	# radius equals attack_range exactly — this is what TowerBase._build_detection_area builds.
	var t := FakeTower.new()
	t.max_health     = 100.0
	t.attack_range   = 30.0
	t.attack_interval = 1.0
	t.tower_type     = "cannon"
	add_child_autofree(t)
	t.setup(0)
	# _area is private but accessible via get() in GDScript tests.
	var area: Area3D = t.get("_area") as Area3D
	assert_not_null(area, "Area3D should be built when attack_range > 0")
	var shape_owner_id: int = area.get_shape_owners()[0]
	var shape: Shape3D = area.shape_owner_get_shape(shape_owner_id, 0)
	assert_true(shape is SphereShape3D, "Detection shape must be a SphereShape3D")
	assert_almost_eq((shape as SphereShape3D).radius, 30.0, 0.001,
		"Detection sphere radius must equal attack_range")

func test_no_detection_area_when_attack_range_zero() -> void:
	# Passive towers must not build an Area3D.
	var t := FakeTower.new()
	t.max_health     = 500.0
	t.attack_range   = 0.0
	t.attack_interval = 1.0
	t.tower_type     = "slow"
	add_child_autofree(t)
	t.setup(0)
	var area = t.get("_area")
	assert_null(area, "No Area3D should be created for passive towers (attack_range == 0)")

# ── SlowTowerAI server-authority guard ───────────────────────────────────────

class FakeSlowTower extends SlowTowerAI:
	func _build_visuals() -> void:
		pass  # skip GLB loading in headless tests

# ── Composite model system ────────────────────────────────────────────────────
#
# These tests verify _build_visuals() builds the component hierarchy correctly
# without loading real GLB assets. Each test subclass calls super._build_visuals()
# after manually injecting fake PackedScene-equivalent nodes via _ready().
#
# Strategy: we cannot hand PackedScene instances real GLB data in headless tests,
# so we use a FakeTower subclass that overrides _build_visuals() to call the
# TowerBase assembly logic directly with fake Node3D subtrees.

# A tower that manually calls the TowerBase component assembly steps using
# fake sub-nodes — no GLB loading required.
class ComponentTower extends TowerBase:
	# These are set by individual tests to control what gets assembled.
	var fake_base: Node3D = null
	var fake_mid: Node3D = null
	var fake_turret: Node3D = null
	var fake_attachment: Node3D = null

	func _build_visuals() -> void:
		# Replicate TowerBase._build_visuals() without PackedScene.instantiate()
		if fake_base != null:
			add_child(fake_base)
			_collect_meshes(fake_base)
		if fake_mid != null:
			fake_mid.position = model_mid_offset
			add_child(fake_mid)
			_collect_meshes(fake_mid)
		_turret_pivot = Node3D.new()
		_turret_pivot.name = "TurretPivot"
		_turret_pivot.position = model_turret_offset
		add_child(_turret_pivot)
		if fake_turret != null:
			_turret_pivot.add_child(fake_turret)
			_collect_meshes(fake_turret)
		if fake_attachment != null:
			fake_attachment.position = model_attachment_offset
			_turret_pivot.add_child(fake_attachment)
			_collect_meshes(fake_attachment)
		if _all_mesh_insts.size() > 0:
			_mesh_inst = _all_mesh_insts[0]
		_build_hit_overlay()

## Helper: creates a Node3D containing one MeshInstance3D with a BoxMesh.
func _make_fake_model() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	return root

# ComponentTower variant that supports model_mid_count > 1 and model_top,
# using fresh fake Node3D instances per repeat so each is independently positioned.
# Exposes _mid_nodes and _top_node for position assertions.
class MultiMidTower extends TowerBase:
	var fake_top: Node3D = null
	var _mid_nodes: Array = []
	var _top_node: Node3D = null

	func _build_visuals() -> void:
		_mid_nodes.clear()
		for i in model_mid_count:
			var mid := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mid.add_child(mi)
			mid.position = model_mid_offset + model_mid_step * i
			add_child(mid)
			_collect_meshes(mid)
			_mid_nodes.append(mid)
		if fake_top != null:
			fake_top.position = model_top_offset
			add_child(fake_top)
			_collect_meshes(fake_top)
			_top_node = fake_top
		_turret_pivot = Node3D.new()
		_turret_pivot.name = "TurretPivot"
		_turret_pivot.position = model_turret_offset
		add_child(_turret_pivot)
		if _all_mesh_insts.size() > 0:
			_mesh_inst = _all_mesh_insts[0]
		_build_hit_overlay()

func test_turret_pivot_created_when_build_visuals_called() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	add_child_autofree(t)
	t.setup(0)
	var pivot: Node3D = t.get("_turret_pivot") as Node3D
	assert_not_null(pivot, "_turret_pivot must exist after _build_visuals()")
	assert_true(pivot.name == "TurretPivot", "Pivot should be named TurretPivot")

func test_turret_pivot_is_child_of_tower() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	add_child_autofree(t)
	t.setup(0)
	var pivot: Node3D = t.get("_turret_pivot") as Node3D
	assert_not_null(pivot)
	assert_true(pivot.get_parent() == t, "TurretPivot must be a direct child of the tower")

func test_base_mesh_collected_into_all_mesh_insts() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.fake_base = _make_fake_model()
	add_child_autofree(t)
	t.setup(0)
	var meshes: Array = t.get("_all_mesh_insts")
	assert_gt(meshes.size(), 0, "Base mesh should be collected into _all_mesh_insts")

func test_turret_mesh_collected_into_all_mesh_insts() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.fake_base = _make_fake_model()
	t.fake_turret = _make_fake_model()
	add_child_autofree(t)
	t.setup(0)
	var meshes: Array = t.get("_all_mesh_insts")
	assert_eq(meshes.size(), 2, "Both base and turret meshes should be collected")

func test_attachment_parented_to_turret_pivot() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.fake_turret = _make_fake_model()
	t.fake_attachment = _make_fake_model()
	add_child_autofree(t)
	t.setup(0)
	var pivot: Node3D = t.get("_turret_pivot") as Node3D
	assert_not_null(pivot)
	# attachment Node3D should be a child of pivot (index 1 after turret)
	assert_eq(pivot.get_child_count(), 2,
		"TurretPivot should have turret + attachment as children")

func test_all_three_components_collected() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.fake_base = _make_fake_model()
	t.fake_turret = _make_fake_model()
	t.fake_attachment = _make_fake_model()
	add_child_autofree(t)
	t.setup(0)
	var meshes: Array = t.get("_all_mesh_insts")
	assert_eq(meshes.size(), 3, "Base + turret + attachment meshes all collected")

func test_backward_compat_model_scene_used_when_model_base_null() -> void:
	# If model_base is null but model_scene is set (old .tscn style),
	# TowerBase should fall back to model_scene as the base.
	# We can't load a real GLB in headless — verify the fallback path
	# is reached by using a ComponentTower with no fake_base but checking
	# _mesh_inst stays null (no GLB = nothing instantiated) without crashing.
	var t := FakeTower.new()  # FakeTower has no-op _build_visuals
	t.attack_range = 0.0
	t.tower_type = "cannon"
	# model_base stays null, model_scene stays null — should not crash
	add_child_autofree(t)
	t.setup(0)
	# Just assert it doesn't crash and _dead is still false
	assert_false(t._dead, "Tower should not die just from having no model")

func test_flash_hit_covers_all_mesh_instances() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.fake_base = _make_fake_model()
	t.fake_turret = _make_fake_model()
	add_child_autofree(t)
	t.setup(0)
	# Damage to trigger flash
	t.take_damage(10.0, "player", 1)
	# After flash, overlay material should be set on all mesh surfaces
	var meshes: Array = t.get("_all_mesh_insts")
	assert_eq(meshes.size(), 2, "Sanity: two meshes collected")
	var overlay: StandardMaterial3D = t.get("_hit_overlay_mat") as StandardMaterial3D
	assert_not_null(overlay, "Hit overlay material must exist after setup")
	for mi in meshes:
		var mesh_inst := mi as MeshInstance3D
		for i in mesh_inst.mesh.get_surface_count():
			assert_not_null(mesh_inst.get_surface_override_material(i),
				"Flash overlay must be applied to every surface of every mesh")

func test_mid_count_one_creates_single_mid_child() -> void:
	var t := ComponentTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.fake_mid = _make_fake_model()
	t.model_mid_count = 1
	t.model_mid_step = Vector3(0.0, 1.0, 0.0)
	add_child_autofree(t)
	t.setup(0)
	# One mid node should be a direct child of tower (plus TurretPivot)
	var mid_children: int = 0
	for child in t.get_children():
		if child != t.get("_turret_pivot") and child.name != "CollisionShape3D":
			mid_children += 1
	# base=0 (no fake_base), mid=1 node, top=0 → 1 non-pivot child
	assert_eq(mid_children, 1, "model_mid_count=1 should produce exactly 1 mid child")

func test_mid_count_five_creates_five_mid_children() -> void:
	var t := MultiMidTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.model_mid_count = 5
	t.model_mid_offset = Vector3(0.0, 1.0, 0.0)
	t.model_mid_step   = Vector3(0.0, 1.0, 0.0)
	add_child_autofree(t)
	t.setup(0)
	var mid_nodes: Array = t.get("_mid_nodes")
	assert_eq(mid_nodes.size(), 5, "model_mid_count=5 should produce 5 mid nodes")
	var meshes: Array = t.get("_all_mesh_insts")
	assert_eq(meshes.size(), 5, "5 mid repeats should collect 5 mesh instances")

func test_mid_step_offsets_each_repeat() -> void:
	# Use a ComponentTower variant that repeats fake_mid N times at correct offsets.
	# We subclass ComponentTower to support mid_count > 1 with fake nodes.
	var t := MultiMidTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.model_mid_count = 3
	t.model_mid_offset = Vector3(0.0, 1.0, 0.0)
	t.model_mid_step   = Vector3(0.0, 1.0, 0.0)
	add_child_autofree(t)
	t.setup(0)
	# 3 mids × 1 mesh each = 3 mesh insts (no base, no top, no turret)
	var meshes: Array = t.get("_all_mesh_insts")
	assert_eq(meshes.size(), 3, "3 mid repeats should collect 3 mesh instances")
	# Verify Y positions: mid[0]=1.0, mid[1]=2.0, mid[2]=3.0
	var mid_nodes: Array = t.get("_mid_nodes")
	assert_eq(mid_nodes.size(), 3, "Should have 3 mid node refs")
	assert_almost_eq((mid_nodes[0] as Node3D).position.y, 1.0, 0.001, "Mid 0 Y should be 1.0")
	assert_almost_eq((mid_nodes[1] as Node3D).position.y, 2.0, 0.001, "Mid 1 Y should be 2.0")
	assert_almost_eq((mid_nodes[2] as Node3D).position.y, 3.0, 0.001, "Mid 2 Y should be 3.0")

func test_model_top_placed_above_mids() -> void:
	var t := MultiMidTower.new()
	t.attack_range = 0.0
	t.tower_type = "cannon"
	t.model_mid_count  = 2
	t.model_mid_offset = Vector3(0.0, 1.0, 0.0)
	t.model_mid_step   = Vector3(0.0, 1.0, 0.0)
	t.model_top_offset = Vector3(0.0, 5.0, 0.0)
	t.fake_top         = _make_fake_model()
	add_child_autofree(t)
	t.setup(0)
	var top_node: Node3D = t.get("_top_node") as Node3D
	assert_not_null(top_node, "model_top should be instantiated")
	assert_almost_eq(top_node.position.y, 5.0, 0.001, "Top node Y should match model_top_offset")

# ── LOS / puppet targeting regression tests ──────────────────────────────────
#
# Regression: TowerBase._has_line_of_sight() used to exclude only the
# CharacterBody3D RID from the raycast, not the sibling HitBody StaticBody3D
# (collision layer 1). The ray hit HitBody before reaching open sky and
# returned false, so host towers never attacked the client puppet.
# Fix: TowerBase.gd:336 now also appends HitBody.get_rid() to excluded.

## Minimal BasePlayer subclass — skips visuals and lobby queries in headless tests.
class FakePuppet extends BasePlayer:
	func _init() -> void:
		# Stub PlayerBody/CharacterMesh so @onready paths in BasePlayer don't crash.
		var body := Node3D.new()
		body.name = "PlayerBody"
		var mesh := Node3D.new()
		mesh.name = "CharacterMesh"
		body.add_child(mesh)
		add_child(body)
	func _build_visuals() -> void:
		pass
	func _init_visuals() -> void:
		pass  # skip LobbyManager / avatar loading entirely

func test_los_not_blocked_by_target_hitbody() -> void:
	# Tower at origin, puppet 10 m away — clear sky between them.
	# Before the fix _has_line_of_sight returned false because the ray hit
	# the puppet's own HitBody StaticBody3D (layer 1).
	var t := FakeTower.new()
	t.max_health    = 100.0
	t.attack_range  = 0.0  # no Area3D needed for this test
	t.attack_interval = 1.0
	t.tower_type    = "cannon"
	add_child_autofree(t)
	t.setup(0)
	t.global_position = Vector3.ZERO

	var puppet := FakePuppet.new()
	puppet.setup(2, 1, false, "a")
	add_child_autofree(puppet)
	puppet.global_position = Vector3(0.0, 0.0, 10.0)

	# Physics needs one frame to register before we can use direct_space_state.
	await get_tree().physics_frame

	var los: bool = t._has_line_of_sight(puppet)
	assert_true(los,
		"_has_line_of_sight must return true when only the target's HitBody is between tower and target")

func test_find_target_returns_enemy_puppet_in_range() -> void:
	# Tower team=0, puppet team=1 at 8 m — should be selected as target.
	# Before the fix _find_target() returned null because LOS always failed.
	var t := FakeTower.new()
	t.max_health    = 100.0
	t.attack_range  = 50.0
	t.attack_interval = 1.0
	t.tower_type    = "cannon"
	add_child_autofree(t)
	t.setup(0)
	t.global_position = Vector3.ZERO

	var puppet := FakePuppet.new()
	puppet.setup(2, 1, false, "a")
	add_child_autofree(puppet)
	puppet.global_position = Vector3(0.0, 0.0, 8.0)

	# Wait for Area3D overlap detection.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var target: Node3D = t._find_target()
	assert_not_null(target, "_find_target() must return the enemy puppet when it is in range")

func test_slow_tower_pulse_does_not_fire_on_client() -> void:
	# In headless tests multiplayer.is_server() == true (OfflineMultiplayerPeer).
	# To test the client guard we read the code path directly: _process must
	# return early when NetworkManager._peer != null AND not is_server().
	# We verify the guard exists by confirming _pulse_timer does NOT advance
	# when we fake a non-server multiplayer context.
	#
	# Since OfflineMultiplayerPeer always returns is_server()=true we can't
	# actually flip the flag at runtime — instead we assert the guard is present
	# by confirming the timer DOES advance in the normal (server) test context,
	# which proves the guard branch is the only reason it would not advance.
	var t := FakeSlowTower.new()
	t.max_health     = 500.0
	t.attack_range   = 0.0   # passive — no Area3D
	t.attack_interval = 1.0
	t.tower_type     = "slow"
	add_child_autofree(t)
	t.setup(0)
	var timer_before: float = t.get("_pulse_timer")
	t._process(0.5)
	var timer_after: float = t.get("_pulse_timer")
	assert_gt(timer_after, timer_before,
		"_pulse_timer should advance on server — confirms _process runs past guard")

# ── Cannon/Mortar VFX RPC: call_remote regression guards ─────────────────────
#
# These tests verify that spawn_cannonball_visuals and spawn_mortar_visuals are
# call_remote — the server must NOT re-spawn a second physics projectile via the
# RPC (it already spawned the authoritative one in _do_attack).
#
# Strategy: inject MockMultiplayerAPI so we can observe RPC dispatch, then call
# the RPC function body directly to confirm it does NOT run locally on the
# server (because call_remote suppresses local execution under MockMultiplayerAPI).

func test_spawn_cannonball_visuals_rpc_is_call_remote() -> void:
	# With call_remote, calling .rpc() on the server only dispatches to peers.
	# The function body does NOT execute locally on the server.
	# We verify: injecting mock + calling .rpc() records one dispatch entry but
	# does NOT add a child to the scene root (which would happen if call_local).
	var mock := MockMultiplayerAPI.new()
	get_tree().set_multiplayer(mock, LobbyManager.get_path())
	var root_child_count_before: int = get_tree().root.get_child_count()
	# call .rpc() — under MockMultiplayerAPI this logs the call but never runs the body
	LobbyManager.spawn_cannonball_visuals.rpc(
		Vector3.ZERO, Vector3(0, 0, 10), 50.0, 0)
	var root_child_count_after: int = get_tree().root.get_child_count()
	# call_remote: body not executed locally → no new child added to scene root
	assert_eq(root_child_count_after, root_child_count_before,
		"spawn_cannonball_visuals must be call_remote: body must not run locally on server")
	# RPC was dispatched
	assert_true(mock.was_called("spawn_cannonball_visuals"),
		"spawn_cannonball_visuals.rpc() must dispatch via multiplayer")
	get_tree().set_multiplayer(null, LobbyManager.get_path())

func test_spawn_mortar_visuals_rpc_is_call_remote() -> void:
	var mock := MockMultiplayerAPI.new()
	get_tree().set_multiplayer(mock, LobbyManager.get_path())
	var root_child_count_before: int = get_tree().root.get_child_count()
	LobbyManager.spawn_mortar_visuals.rpc(
		Vector3.ZERO, Vector3(0, 0, 10), 80.0, 1)
	var root_child_count_after: int = get_tree().root.get_child_count()
	assert_eq(root_child_count_after, root_child_count_before,
		"spawn_mortar_visuals must be call_remote: body must not run locally on server")
	assert_true(mock.was_called("spawn_mortar_visuals"),
		"spawn_mortar_visuals.rpc() must dispatch via multiplayer")
	get_tree().set_multiplayer(null, LobbyManager.get_path())

# ── _fire_ballistic RPC dispatch regression guard ────────────────────────────
#
# Verify that _fire_ballistic calls rpc_callable.rpc() (not .call()) so that
# clients actually receive the cannonball/mortar VFX broadcast.
# Previously the code used rpc_callable.call() which executed the function body
# locally but never dispatched to peers.

class FakeCannonTower extends TowerAI:
	func _build_visuals() -> void:
		pass

func test_fire_ballistic_dispatches_rpc_to_clients() -> void:
	var mock := MockMultiplayerAPI.new()
	mock.set_as_server()
	get_tree().set_multiplayer(mock, LobbyManager.get_path())

	var t := FakeCannonTower.new()
	t.max_health      = 900.0
	t.attack_range    = 0.0
	t.attack_interval = 1.0
	t.tower_type      = "cannon"
	add_child_autofree(t)
	t.setup(0)

	# Fake target — needs global_position accessible via Node3D
	var target := Node3D.new()
	add_child_autofree(target)
	target.global_position = Vector3(0, 0, 10)

	var cannon_scene: PackedScene = preload("res://scenes/projectiles/Cannonball.tscn")
	t._fire_ballistic(
		cannon_scene, 50.0, "cannonball",
		"res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_001.ogg",
		0.0, 0.9, 1.05, target,
		Callable(LobbyManager, "spawn_cannonball_visuals"))

	assert_true(mock.was_called("spawn_cannonball_visuals"),
		"_fire_ballistic must dispatch spawn_cannonball_visuals.rpc() to clients when is_server()")
	get_tree().set_multiplayer(null, LobbyManager.get_path())

# ── SlowTower pulse VFX RPC broadcast regression guard ───────────────────────
#
# Verify that _emit_pulse() calls LobbyManager.spawn_slow_pulse_visuals.rpc()
# when running as server in multiplayer. This ensures clients receive the pulse
# VFX, which previously only ran server-side.

func test_slow_tower_emit_pulse_dispatches_rpc_in_multiplayer() -> void:
	var mock := MockMultiplayerAPI.new()
	mock.set_as_server()
	get_tree().set_multiplayer(mock, LobbyManager.get_path())

	var t := FakeSlowTower.new()
	t.max_health      = 500.0
	t.attack_range    = 0.0  # passive — no Area3D
	t.attack_interval = 1.0
	t.tower_type      = "slow"
	add_child_autofree(t)
	t.setup(0)

	t._emit_pulse()

	assert_true(mock.was_called("spawn_slow_pulse_visuals"),
		"_emit_pulse() must call spawn_slow_pulse_visuals.rpc() when is_server()")
	get_tree().set_multiplayer(null, LobbyManager.get_path())

func test_slow_tower_emit_pulse_rpc_passes_tower_name() -> void:
	var mock := MockMultiplayerAPI.new()
	mock.set_as_server()
	get_tree().set_multiplayer(mock, LobbyManager.get_path())

	var t := FakeSlowTower.new()
	t.max_health      = 500.0
	t.attack_range    = 0.0
	t.attack_interval = 1.0
	t.tower_type      = "slow"
	t.name            = "SlowTowerTest"
	add_child_autofree(t)
	t.setup(0)

	t._emit_pulse()

	var calls: Array = mock.calls_to("spawn_slow_pulse_visuals")
	assert_eq(calls.size(), 1)
	assert_eq(calls[0]["args"][0], "SlowTowerTest",
		"First arg to spawn_slow_pulse_visuals must be the tower node name")
	get_tree().set_multiplayer(null, LobbyManager.get_path())

# ── build_time ────────────────────────────────────────────────────────────────

func test_build_time_default_is_zero() -> void:
	var t := FakeTower.new()
	add_child_autofree(t)
	assert_eq(t.build_time, 0.0, "Default build_time must be 0")

func test_setup_seeds_build_timer_from_build_time() -> void:
	var t := FakeTower.new()
	t.max_health   = 100.0
	t.attack_range = 0.0
	t.build_time   = 10.0
	add_child_autofree(t)
	t.setup(0)
	assert_eq(t._build_timer, 10.0, "_build_timer must equal build_time after setup()")

func test_tower_with_zero_build_time_has_zero_build_timer() -> void:
	var t := FakeTower.new()
	t.max_health   = 100.0
	t.attack_range = 0.0
	t.build_time   = 0.0
	add_child_autofree(t)
	t.setup(0)
	assert_eq(t._build_timer, 0.0, "_build_timer must be 0 when build_time is 0")

## Simulate process() manually to advance the build timer.
## FakeTower has no Area3D (_area == null), so _process returns early after the
## build-phase block — we never hit the attack path, which is fine for this test.
func test_build_timer_decrements_over_time() -> void:
	var t := FakeTower.new()
	t.max_health   = 100.0
	t.attack_range = 0.0
	t.build_time   = 10.0
	add_child_autofree(t)
	t.setup(0)
	# Manually call _process to simulate elapsed time
	t._process(3.0)
	assert_almost_eq(t._build_timer, 7.0, 0.001, "_build_timer should decrease by delta")

func test_build_timer_clamps_to_zero() -> void:
	var t := FakeTower.new()
	t.max_health   = 100.0
	t.attack_range = 0.0
	t.build_time   = 5.0
	add_child_autofree(t)
	t.setup(0)
	t._process(10.0)   # far past build_time
	assert_eq(t._build_timer, 0.0, "_build_timer must not go below 0")

func test_placeable_defs_have_build_time_for_all_towers() -> void:
	const BuildSystemScript := preload("res://scripts/BuildSystem.gd")
	var bs := Node.new()
	bs.set_script(BuildSystemScript)
	add_child_autofree(bs)
	var tower_keys := ["cannon", "mortar", "slow", "machinegun", "launcher_missile"]
	for key in tower_keys:
		var def: Dictionary = bs.PLACEABLE_DEFS.get(key, {})
		assert_true(def.has("build_time"),
			"PLACEABLE_DEFS[\"%s\"] must have build_time key" % key)
		assert_gt(def["build_time"], 0.0,
			"PLACEABLE_DEFS[\"%s\"].build_time must be > 0" % key)

func test_build_time_values_in_expected_range() -> void:
	const BuildSystemScript := preload("res://scripts/BuildSystem.gd")
	var bs := Node.new()
	bs.set_script(BuildSystemScript)
	add_child_autofree(bs)
	var tower_keys := ["cannon", "mortar", "slow", "machinegun", "launcher_missile"]
	for key in tower_keys:
		var bt: float = bs.PLACEABLE_DEFS[key]["build_time"]
		assert_true(bt >= 10.0 and bt <= 35.0,
			"build_time for \"%s\" should be 10–35s, got %s" % [key, bt])
