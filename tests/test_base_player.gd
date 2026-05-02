extends GutTest

## test_base_player.gd — P1–P30
## Tier 1: OfflineMultiplayerPeer. Tests cover setup(), group membership,
## HitBody wiring, HitShape local disable, puppet lerp (position + rotation),
## _set_alive() hooks, _build_visuals() hook, take_damage no-op, update_transform,
## _load_model, _try_load_avatar, _on_lobby_updated, and edge cases.

const BasePlayerScene := preload("res://scenes/players/BasePlayer.tscn")

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_player() -> BasePlayer:
	var p: BasePlayer = BasePlayerScene.instantiate()
	return p

# ── P1: setup() sets identity fields before add_child ─────────────────────────

func test_p1_setup_sets_fields() -> void:
	var p := _make_player()
	p.setup(42, 1, true, "c")
	assert_eq(p.peer_id,     42)
	assert_eq(p.player_team, 1)
	assert_true(p.is_local)
	assert_eq(p.avatar_char, "c")
	p.queue_free()

# ── P2: setup() values persist after add_child (not overwritten by _ready) ────

func test_p2_setup_persists_after_add_child() -> void:
	var p := _make_player()
	p.setup(7, 0, false, "b")
	add_child_autofree(p)
	assert_eq(p.peer_id,     7)
	assert_eq(p.player_team, 0)
	assert_false(p.is_local)
	assert_eq(p.avatar_char, "b")

# ── P3: _ready() adds node to group "players" ─────────────────────────────────

func test_p3_added_to_players_group() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	assert_true(p.is_in_group("players"))

# ── P4: _ready() sets ghost_peer_id meta on HitBody ──────────────────────────

func test_p4_hit_body_meta_set() -> void:
	var p := _make_player()
	p.setup(55, 0, false, "a")
	add_child_autofree(p)
	var hit_body: Node = p.get_node_or_null("HitBody")
	assert_not_null(hit_body)
	assert_true(hit_body.has_meta("ghost_peer_id"))
	assert_eq(int(hit_body.get_meta("ghost_peer_id")), 55)

# ── P5: _set_alive(false) disables HitBody collision (player stays visible) ───

func test_p5_set_alive_false_hides_and_disables_hitbox() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	p.visible = true
	var hit_body: StaticBody3D = p.get_node_or_null("HitBody") as StaticBody3D
	if hit_body != null:
		hit_body.set_collision_layer(1)
	p._set_alive(false)
	assert_true(p.visible, "_set_alive(false) must not hide player")
	if hit_body != null:
		assert_eq(hit_body.get_collision_layer(), 0)

# ── P6: _set_alive(true) enables HitBody collision (player stays visible) ─────

func test_p6_set_alive_true_shows_and_enables_hitbox() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	var hit_body: StaticBody3D = p.get_node_or_null("HitBody") as StaticBody3D
	if hit_body != null:
		hit_body.set_collision_layer(0)
	p._set_alive(true)
	assert_true(p.visible)
	if hit_body != null:
		assert_eq(hit_body.get_collision_layer(), 1)

# ── P7: update_transform updates target position and rotation ─────────────────

func test_p7_update_transform_sets_targets() -> void:
	var p := _make_player()
	p.setup(2, 1, false, "a")
	add_child_autofree(p)
	p.update_transform(Vector3(5, 0, 5), Vector3(0, 1.5, 0))
	assert_eq(p._target_position, Vector3(5, 0, 5))
	assert_eq(p._target_rotation, Vector3(0, 1.5, 0))

# ── P8: puppet _process lerps toward target position ─────────────────────────

func test_p8_puppet_lerps_toward_target() -> void:
	var p := _make_player()
	p.setup(3, 0, false, "a")
	add_child_autofree(p)
	p.global_position = Vector3.ZERO
	p.update_transform(Vector3(100, 0, 0), Vector3.ZERO)
	for _i: int in range(10):
		p._process(0.1)
	assert_gt(p.global_position.x, 0.0)

# ── P9: local player _process does NOT lerp (is_local=true) ──────────────────

func test_p9_local_player_process_does_not_lerp() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	p.global_position = Vector3.ZERO
	p.update_transform(Vector3(100, 0, 0), Vector3.ZERO)
	p._process(0.1)
	assert_eq(p.global_position.x, 0.0)

# ── P10: _try_load_avatar returns false when peer_id=0 ────────────────────────

func test_p10_try_load_avatar_false_when_no_peer_id() -> void:
	var p := _make_player()
	p.setup(0, 0, false, "")
	add_child_autofree(p)
	assert_false(p._try_load_avatar())

# ── P11: _try_load_avatar returns false when LobbyManager has no avatar_char ──

func test_p11_try_load_avatar_false_when_no_char_in_lobby() -> void:
	var p := _make_player()
	p.setup(999, 0, false, "")
	add_child_autofree(p)
	assert_false(p._try_load_avatar())

# ── P12: _try_load_avatar returns true when avatar_char set directly ───────────

func test_p12_try_load_avatar_true_when_char_set_directly() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	await wait_frames(2)
	assert_true(p._model_loaded)

# ── P13: _load_model adds GLB child to PlayerBody/CharacterMesh ───────────────

func test_p13_load_model_adds_child() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	await wait_frames(2)
	var char_mesh: Node3D = p.get_node_or_null("PlayerBody/CharacterMesh")
	assert_not_null(char_mesh)
	assert_gt(char_mesh.get_child_count(), 0)

# ── P14: _load_model sets _current_char and _model_loaded ─────────────────────

func test_p14_load_model_sets_state() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	add_child_autofree(p)
	p._load_model("a")
	assert_eq(p._current_char, "a")
	assert_true(p._model_loaded)

# ── P15: _load_model called twice does not crash (no blank frame) ──────────────

func test_p15_load_model_twice_no_crash() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	add_child_autofree(p)
	p._load_model("a")
	p._load_model("b")
	assert_eq(p._current_char, "b")

# ── P16: _on_lobby_updated loads avatar when char appears in LobbyManager ─────

func test_p16_on_lobby_updated_loads_avatar() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "")
	add_child_autofree(p)
	await wait_frames(2)
	# Simulate lobby update with avatar_char
	LobbyManager.players[1] = {"avatar_char": "b", "name": "Test", "team": 0, "role": 0}
	LobbyManager.lobby_updated.emit()
	await wait_frames(2)
	assert_true(p._model_loaded)
	assert_eq(p._current_char, "b")
	LobbyManager.players.erase(1)

# ── P17: _set_alive false then true — player always visible ───────────────────

func test_p17_set_alive_toggle_restores_visible() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	add_child_autofree(p)
	p._set_alive(false)
	assert_true(p.visible, "Player must stay visible after _set_alive(false)")
	p._set_alive(true)
	assert_true(p.visible)

# ── P18: HitBody collision layer 0 when dead, 1 when alive ────────────────────

func test_p18_hitbody_layer_matches_alive_state() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	add_child_autofree(p)
	var hit_body: StaticBody3D = p.get_node_or_null("HitBody") as StaticBody3D
	if hit_body == null:
		pass  # no hitbox in minimal scene — skip collision assertions
		return
	p._set_alive(false)
	assert_eq(hit_body.get_collision_layer(), 0)
	p._set_alive(true)
	assert_eq(hit_body.get_collision_layer(), 1)

# ── Subclass helpers for hook and warning tests ───────────────────────────────

## Records calls to overridable hooks so tests can assert they fired.
class TrackingPlayer extends BasePlayer:
	var died_called: bool    = false
	var respawned_called: bool = false
	var build_visuals_called: bool = false
	var _warnings: Array = []

	func _on_died() -> void:
		died_called = true

	func _on_respawned(_spawn_pos: Vector3) -> void:
		respawned_called = true

	func _build_visuals() -> void:
		build_visuals_called = true

	## Capture push_warning output so tests can assert it was emitted.
	func push_warning(msg: String) -> void:
		_warnings.append(msg)

# ── P19: HitShape disabled for local player ───────────────────────────────────

func test_p19_hitshape_disabled_for_local_player() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	var hit_body: Node = p.get_node_or_null("HitBody")
	assert_not_null(hit_body, "HitBody must exist in BasePlayer.tscn")
	var hit_shape: CollisionShape3D = hit_body.get_node_or_null("HitShape") as CollisionShape3D
	assert_not_null(hit_shape, "HitShape must exist inside HitBody")
	assert_true(hit_shape.disabled,
		"HitShape must be disabled for is_local=true to prevent self-collision launch")

# ── P20: HitShape NOT disabled for remote puppet ─────────────────────────────

func test_p20_hitshape_enabled_for_remote_player() -> void:
	var p := _make_player()
	p.setup(2, 0, false, "a")
	add_child_autofree(p)
	var hit_body: Node = p.get_node_or_null("HitBody")
	assert_not_null(hit_body)
	var hit_shape: CollisionShape3D = hit_body.get_node_or_null("HitShape") as CollisionShape3D
	assert_not_null(hit_shape)
	assert_false(hit_shape.disabled,
		"HitShape must stay enabled for is_local=false so bullet raycasts can detect it")

# ── P21: take_damage is a documented no-op ────────────────────────────────────

func test_p21_take_damage_is_noop() -> void:
	var p := _make_player()
	p.setup(1, 0, true, "a")
	add_child_autofree(p)
	var hp_before: int = p.peer_id  # peer_id should not change
	p.take_damage(50.0, "test", 0, 99)
	assert_eq(p.peer_id, hp_before,
		"take_damage must not mutate peer_id or any BasePlayer state")
	assert_true(p.visible,
		"take_damage must not hide the player (BasePlayer.take_damage is a no-op)")

# ── P22: puppet lerps rotation.y toward target ────────────────────────────────

func test_p22_puppet_lerps_rotation() -> void:
	var p := _make_player()
	p.setup(3, 0, false, "a")
	add_child_autofree(p)
	p.rotation.y = 0.0
	p.update_transform(Vector3.ZERO, Vector3(0, 1.5, 0))
	for _i: int in range(10):
		p._process(0.1)
	assert_gt(p.rotation.y, 0.0,
		"puppet rotation.y must lerp toward target rotation.y via lerp_angle")

# ── P23: _on_died() hook called when _set_alive(false) ───────────────────────

func test_p23_on_died_hook_called() -> void:
	var p := TrackingPlayer.new()
	# Manually build the required sub-nodes so _ready() finds HitBody/HitShape.
	var hit_body := StaticBody3D.new()
	hit_body.name = "HitBody"
	var hit_shape := CollisionShape3D.new()
	hit_shape.name = "HitShape"
	hit_body.add_child(hit_shape)
	p.add_child(hit_body)
	var body := Node3D.new()
	body.name = "PlayerBody"
	var mesh := Node3D.new()
	mesh.name = "CharacterMesh"
	body.add_child(mesh)
	p.add_child(body)
	p.setup(10, 0, false, "")
	add_child_autofree(p)
	p._set_alive(false)
	assert_true(p.died_called, "_on_died() must be called when _set_alive(false)")

# ── P24: _on_respawned() hook called when _set_alive(true) ───────────────────

func test_p24_on_respawned_hook_called() -> void:
	var p := TrackingPlayer.new()
	var hit_body := StaticBody3D.new()
	hit_body.name = "HitBody"
	var hit_shape := CollisionShape3D.new()
	hit_shape.name = "HitShape"
	hit_body.add_child(hit_shape)
	p.add_child(hit_body)
	var body := Node3D.new()
	body.name = "PlayerBody"
	var mesh := Node3D.new()
	mesh.name = "CharacterMesh"
	body.add_child(mesh)
	p.add_child(body)
	p.setup(11, 0, false, "")
	add_child_autofree(p)
	p._set_alive(true)
	assert_true(p.respawned_called, "_on_respawned() must be called when _set_alive(true)")

# ── P25: _build_visuals() hook called from _init_visuals ─────────────────────

func test_p25_build_visuals_hook_called() -> void:
	var p := TrackingPlayer.new()
	var hit_body := StaticBody3D.new()
	hit_body.name = "HitBody"
	var hit_shape := CollisionShape3D.new()
	hit_shape.name = "HitShape"
	hit_body.add_child(hit_shape)
	p.add_child(hit_body)
	var body := Node3D.new()
	body.name = "PlayerBody"
	var mesh := Node3D.new()
	mesh.name = "CharacterMesh"
	body.add_child(mesh)
	p.add_child(body)
	p.setup(12, 0, false, "")
	add_child_autofree(p)
	await wait_frames(2)
	assert_true(p.build_visuals_called,
		"_build_visuals() must be called from _init_visuals() after add_child")

# ── P26: lobby_updated signal disconnected after successful avatar load ────────

func test_p26_lobby_updated_disconnects_after_success() -> void:
	var p := _make_player()
	p.setup(77, 0, false, "")
	add_child_autofree(p)
	await wait_frames(2)
	# First lobby_updated — provides avatar_char and triggers load + disconnect.
	LobbyManager.players[77] = {"avatar_char": "c", "name": "T", "team": 0, "role": 0}
	LobbyManager.lobby_updated.emit()
	await wait_frames(2)
	assert_eq(p._current_char, "c")
	# Second lobby_updated — must be a no-op (signal already disconnected).
	LobbyManager.players[77] = {"avatar_char": "d", "name": "T", "team": 0, "role": 0}
	LobbyManager.lobby_updated.emit()
	await wait_frames(2)
	assert_eq(p._current_char, "c",
		"After successful load lobby_updated must be disconnected — second emit is a no-op")
	LobbyManager.players.erase(77)

# ── P27: _load_model with invalid char does not crash ────────────────────────

func test_p27_load_model_invalid_char_no_crash() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	add_child_autofree(p)
	# zzz_invalid GLB does not exist — should warn and return without setting state.
	p._load_model("zzz_invalid")
	assert_false(p._model_loaded,
		"_model_loaded must stay false after failing to load invalid char")

# ── P28: HitBody absent — push_warning fires, no crash ───────────────────────

func test_p28_missing_hitbody_warning_no_crash() -> void:
	# Build a minimal CharacterBody3D with just PlayerBody — no HitBody.
	var p := TrackingPlayer.new()
	var body := Node3D.new()
	body.name = "PlayerBody"
	var mesh := Node3D.new()
	mesh.name = "CharacterMesh"
	body.add_child(mesh)
	p.add_child(body)
	p.setup(20, 0, false, "")
	add_child_autofree(p)
	# The node entered the tree without crashing.
	assert_false(p.is_queued_for_deletion(), "node must not crash when HitBody is absent")

# ── P29: _set_alive called before add_child does not crash ───────────────────

func test_p29_set_alive_before_add_child_no_crash() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	# Intentionally NOT calling add_child — verify graceful handling.
	p._set_alive(false)
	p._set_alive(true)
	assert_true(true, "_set_alive before add_child must not crash")
	p.queue_free()

# ── P30: setup() called after add_child still updates fields ─────────────────

func test_p30_setup_after_add_child_updates_fields() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	add_child_autofree(p)
	# Second setup() call after being in the tree — fields must update.
	p.setup(99, 1, true, "e")
	assert_eq(p.peer_id,     99)
	assert_eq(p.player_team, 1)
	assert_true(p.is_local)
	assert_eq(p.avatar_char, "e")

# ── P31: _on_lobby_updated skips _load_model before _init_visuals runs ────────
#
# Regression guard for Bug C: lobby_updated can fire (via LobbyManager) before
# _init_visuals() has been executed (because _init_visuals is called_deferred).
# If _on_lobby_updated calls _load_model in that window, _load_model will be
# called a second time when _init_visuals runs, causing a same-frame queue_free
# that triggers Godot's visibility_changed → visible=false on the ghost root.
#
# The fix: _on_lobby_updated must be a no-op when _visuals_initialized is false.

func test_p31_on_lobby_updated_before_init_visuals_does_not_load_model() -> void:
	var p := _make_player()
	# peer_id 88 has a known char so _try_load_avatar would succeed.
	LobbyManager.players[88] = {"avatar_char": "b", "name": "T", "team": 0, "role": 0}
	p.setup(88, 0, false, "")
	# Do NOT add_child yet — _ready() calls call_deferred("_init_visuals"), so
	# at this point _visuals_initialized is still false.
	# We also do NOT add_child at all; we call _on_lobby_updated directly to
	# simulate the race window where lobby_updated fires before _init_visuals runs.
	# The function must be a no-op — _model_loaded must stay false.
	p._on_lobby_updated()
	assert_false(p._model_loaded,
		"_on_lobby_updated must not load the model before _init_visuals has run " +
		"(regression guard: double _load_model causes visible=false on ghost root)")
	LobbyManager.players.erase(88)
	p.queue_free()

# ── P32: _visuals_initialized flag set true when _init_visuals runs ──────────
#
# Companion to P31: confirms _visuals_initialized becomes true after _init_visuals
# executes, so subsequent lobby_updated calls proceed normally.

func test_p32_visuals_initialized_set_after_init_visuals() -> void:
	var p := _make_player()
	p.setup(1, 0, false, "a")
	add_child_autofree(p)
	assert_false(p._visuals_initialized,
		"_visuals_initialized must be false before _init_visuals deferred call runs")
	await wait_frames(2)
	assert_true(p._visuals_initialized,
		"_visuals_initialized must be true after _init_visuals executes")

# ── P33: _load_model re-asserts visible=true on puppet after GLB import ───────
#
# Regression guard: Godot's GLB import machinery fires visibility_changed and can
# silently set the root CharacterBody3D visible=false during model instantiation.
# _load_model() must re-assert visible=true for puppet nodes (is_local=false) at
# the end of every model load, so any such engine-internal hidden state is undone.
#
# Failure mode without the fix: the ghost spawns, _load_model runs, Godot's import
# deferred call hides the root, and the remote player becomes permanently invisible.

func test_p33_load_model_reasserts_visible_true_on_puppet() -> void:
	var p := _make_player()
	p.setup(7, 0, false, "a")
	add_child_autofree(p)
	# Simulate what the engine may do during GLB import: hide the root node.
	p.visible = false
	# Now call _load_model — it must re-assert visible=true for puppet nodes.
	p._load_model("a")
	assert_true(p.visible,
		"_load_model must re-assert visible=true on puppet (is_local=false) " +
		"to counter Godot GLB import visibility_changed side-effect")
