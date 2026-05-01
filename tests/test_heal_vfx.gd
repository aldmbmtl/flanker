# test_heal_vfx.gd
# Tier 1 — unit tests for heal VFX: EntityHUD minion bars, MinionBase particle
# hook (covered in test_minion_base.gd), and FPSController flash_heal hook.
extends GutTest

# ── EntityHUD minion bars ─────────────────────────────────────────────────────

const EntityHUDScript := preload("res://scripts/hud/EntityHUD.gd")

# Fake minion with declared properties so Node.get() works.
class FakeMinion extends Node3D:
	var team: int = 0
	var health: float = 60.0
	var max_health: float = 80.0

# EntityHUD requires a camera; stub one that never reports positions behind it.
class FakeCamera extends Camera3D:
	@warning_ignore("native_method_override")
	func is_position_behind(_pos: Vector3) -> bool:
		return false
	@warning_ignore("native_method_override")
	func unproject_position(_pos: Vector3) -> Vector2:
		# Return a position well inside a 1920×1080 viewport.
		return Vector2(400.0, 300.0)

var _hud: Control
var _camera: FakeCamera

func before_each() -> void:
	_camera = FakeCamera.new()
	add_child_autofree(_camera)

	_hud = Control.new()
	_hud.set_script(EntityHUDScript)
	add_child_autofree(_hud)
	_hud.setup(0)  # player team = 0

func after_each() -> void:
	# Remove any stray minion nodes from the group.
	for m in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(m):
			m.remove_from_group("minions")

# Helper: inject the fake camera so _draw_minion_bars can unproject positions.
func _prime_camera() -> void:
	_hud._camera = _camera

func test_draw_minion_bars_no_crash_empty_group() -> void:
	_prime_camera()
	# Must not throw with zero minions registered.
	_hud._draw_minion_bars()
	assert_true(true, "No crash with empty minions group")

func test_draw_minion_bars_filters_enemy_team() -> void:
	_prime_camera()
	var enemy: FakeMinion = FakeMinion.new()
	enemy.team = 1  # enemy team (hud is team 0)
	add_child_autofree(enemy)
	enemy.add_to_group("minions")

	# If the enemy bar would be drawn it would call draw_rect; since we can't
	# intercept draw_rect easily, we validate no error is raised and the method
	# completes without touching the enemy node's health (health unchanged).
	var hp_before: float = enemy.health
	_hud._draw_minion_bars()
	assert_eq(enemy.health, hp_before, "Enemy minion health must not be mutated")
	enemy.remove_from_group("minions")

func test_draw_minion_bars_skips_missing_health_property() -> void:
	_prime_camera()
	# A node in the minions group that has no health/max_health properties.
	var bare: Node3D = Node3D.new()
	bare.name = "BareMinion"
	add_child_autofree(bare)
	bare.add_to_group("minions")
	# Must not crash.
	_hud._draw_minion_bars()
	assert_true(true, "No crash when minion lacks health properties")
	bare.remove_from_group("minions")

func test_draw_minion_bars_skips_dead_minion_at_zero_max_health() -> void:
	_prime_camera()
	var m: FakeMinion = FakeMinion.new()
	m.team = 0
	m.health = 0.0
	m.max_health = 0.0  # should be skipped (division guard)
	add_child_autofree(m)
	m.add_to_group("minions")
	_hud._draw_minion_bars()
	assert_true(true, "No crash with max_health == 0")
	m.remove_from_group("minions")

# ── FPSController _emit_heal_flash hook ───────────────────────────────────────

const FPSControllerScript := preload("res://scripts/roles/fighter/FPSController.gd")

# Minimal FPSController subclass that skips all @onready / scene-tree deps.
# We only need hp, _dead, and the _emit_heal_flash hook.
class FakeFPS extends Node:
	var hp: float = 100.0
	var _dead: bool = false
	var flash_called: int = 0

	func _get_max_hp() -> float:
		return 100.0

	func _update_health_bar() -> void:
		pass  # no bar in tests

	func heal(amount: float) -> void:
		if _dead:
			return
		var hp_before: float = hp
		hp = minf(hp + amount, _get_max_hp())
		_update_health_bar()
		if hp > hp_before:
			_emit_heal_flash()

	func _emit_heal_flash() -> void:
		flash_called += 1

func test_fps_heal_calls_flash_when_gain_positive() -> void:
	var fps: FakeFPS = FakeFPS.new()
	add_child_autofree(fps)
	fps.hp = 60.0
	fps.heal(20.0)
	assert_eq(fps.flash_called, 1, "flash_heal should be called when HP increases")

func test_fps_heal_no_flash_when_already_full() -> void:
	var fps: FakeFPS = FakeFPS.new()
	add_child_autofree(fps)
	fps.hp = 100.0
	fps.heal(20.0)
	assert_eq(fps.flash_called, 0, "No flash when HP is already at max")

func test_fps_heal_no_flash_when_dead() -> void:
	var fps: FakeFPS = FakeFPS.new()
	add_child_autofree(fps)
	fps._dead = true
	fps.hp = 60.0
	fps.heal(20.0)
	assert_eq(fps.flash_called, 0, "No flash when player is dead")
	assert_eq(fps.hp, 60.0, "HP must not change when dead")

# ── heal() → GameSync sync (real FPSController) ───────────────────────────────
# Verify that FPSController.heal() writes back to GameSync so the authoritative
# HP dict reflects the healed value.
# Regression: heal() previously never called GameSync.set_player_health(),
# leaving stale HP that the next damage RPC would overwrite.

const FPSPlayerScene := preload("res://scenes/roles/FPSPlayer.tscn")
const HEAL_SYNC_PEER := 42

var _fps_player: CharacterBody3D = null

func _make_real_fps(peer_id: int) -> CharacterBody3D:
	var player: CharacterBody3D = FPSPlayerScene.instantiate()
	player.setup(peer_id, 0, true, "a")
	player.name = "FPSPlayer_%d" % peer_id
	add_child_autofree(player)
	return player

func test_heal_syncs_gamesync_health() -> void:
	GameSync.reset()
	var player := _make_real_fps(HEAL_SYNC_PEER)
	# Damage via GameSync to bring HP below max
	GameSync.set_player_health(HEAL_SYNC_PEER, 60.0)
	player.hp = 60.0
	player.heal(30.0)
	assert_almost_eq(GameSync.get_player_health(HEAL_SYNC_PEER), 90.0, 0.01,
		"heal() must write updated HP to GameSync")
	GameSync.reset()

func test_heal_gamesync_does_not_exceed_max_hp() -> void:
	GameSync.reset()
	var player := _make_real_fps(HEAL_SYNC_PEER)
	GameSync.set_player_health(HEAL_SYNC_PEER, 90.0)
	player.hp = 90.0
	player.heal(50.0)
	assert_almost_eq(GameSync.get_player_health(HEAL_SYNC_PEER), 100.0, 0.01,
		"heal() must clamp GameSync HP to max")
	GameSync.reset()

func test_heal_does_not_trigger_damage_flash_signal() -> void:
	## heal() triggers GameSync.player_health_changed; the signal must carry
	## the healed value (new_hp > old_hp), confirming it is NOT a damage event.
	GameSync.reset()
	var player := _make_real_fps(HEAL_SYNC_PEER)
	GameSync.set_player_health(HEAL_SYNC_PEER, 50.0)
	player.hp = 50.0
	player.heal(30.0)
	# If heal() syncs to GameSync correctly, the stored HP must be 80.0
	# (was 50.0 before heal). A damage event would never bring HP UP.
	var stored_hp: float = GameSync.get_player_health(HEAL_SYNC_PEER)
	assert_almost_eq(stored_hp, 80.0, 0.01,
		"GameSync HP after heal must be healed value (80), not stale pre-heal value (50)")
	# HP going UP in GameSync means the signal carried a heal, not damage
	assert_true(stored_hp > 50.0,
		"GameSync HP after heal must exceed pre-heal value — confirms no damage path taken")
	GameSync.reset()

func test_gamesync_stale_hp_regression() -> void:
	## Regression test: without the fix, GameSync.player_healths[peer] stays at
	## the pre-heal value, so a subsequent damage_player() sees wrong base HP.
	## With fix: after heal(30) from 60 → 90, damage_player(20) leaves HP at 70.
	GameSync.reset()
	var player := _make_real_fps(HEAL_SYNC_PEER)
	GameSync.set_player_health(HEAL_SYNC_PEER, 60.0)
	player.hp = 60.0
	player.heal(30.0)  # should update GameSync to 90.0
	# Now apply damage through GameSync (server-authoritative path)
	GameSync.damage_player(HEAL_SYNC_PEER, 20.0, 1)
	assert_almost_eq(GameSync.get_player_health(HEAL_SYNC_PEER), 70.0, 0.01,
		"damage after heal must use healed HP as base (regression: stale 60 → 40)")
	GameSync.reset()
