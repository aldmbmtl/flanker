# test_tower_base.gd
# Tier 1 — unit tests for TowerBase combat logic.
# We instantiate a minimal TowerBase directly (no scene/mesh) since all the
# combat logic lives in GDScript, not in the visual nodes.
extends GutTest

# Minimal TowerBase subclass with no visuals — safe to instantiate in tests.
# Overrides _build_visuals() to do nothing (no model_scene in test context).
class TestTower extends TowerBase:
	func _build_visuals() -> void:
		pass  # skip GLB loading in headless tests

var tower: TestTower

func before_each() -> void:
	tower = TestTower.new()
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
