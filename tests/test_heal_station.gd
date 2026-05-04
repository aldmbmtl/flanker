## test_heal_station.gd
## Tests for HealStation — damage, death, take_damage signature compatibility,
## minion healing, _process heal loop, and lifetime expiry.

extends GutTest

const HealStationScript := preload("res://scripts/HealStation.gd")

func before_each() -> void:
	BridgeClient._is_host = true

func after_each() -> void:
	BridgeClient._is_host = false

func _make_station(team: int = 0) -> StaticBody3D:
	var hs := StaticBody3D.new()
	hs.set_script(HealStationScript)
	add_child_autofree(hs)
	# setup() loads a GLB and adds an Area3D — skip it; set properties directly.
	hs.set("team", team)
	hs.set("health", HealStationScript.MAX_HEALTH)
	return hs

# ── take_damage signature ─────────────────────────────────────────────────────

func test_take_damage_accepts_3_args() -> void:
	## Baseline: original 3-arg call must not error.
	var hs: StaticBody3D = _make_station()
	# is_server() returns true under OfflineMultiplayerPeer
	hs.take_damage(10.0, "bullet", 1)
	assert_almost_eq(hs.get("health") as float, HealStationScript.MAX_HEALTH - 10.0, 0.001)

func test_take_damage_accepts_4_args() -> void:
	## Regression test: 4-arg call (projectile callers) must not error.
	var hs: StaticBody3D = _make_station()
	hs.take_damage(20.0, "splash", 1, 42)
	assert_almost_eq(hs.get("health") as float, HealStationScript.MAX_HEALTH - 20.0, 0.001)

func test_take_damage_reduces_health() -> void:
	var hs: StaticBody3D = _make_station()
	hs.take_damage(50.0, "cannon", 1, -1)
	assert_almost_eq(hs.get("health") as float, HealStationScript.MAX_HEALTH - 50.0, 0.001)

func test_take_damage_ignored_when_dead() -> void:
	var hs: StaticBody3D = _make_station()
	hs.set("_dead", true)
	hs.take_damage(100.0, "bullet", 1, -1)
	assert_almost_eq(hs.get("health") as float, HealStationScript.MAX_HEALTH, 0.001,
		"Dead HealStation should ignore damage")

func test_take_damage_kills_at_zero() -> void:
	var hs: StaticBody3D = _make_station()
	# Singleplayer path calls queue_free — just confirm _dead is set before free.
	hs.take_damage(HealStationScript.MAX_HEALTH + 1.0, "rocket", 1, -1)
	# _die() sets _dead = true synchronously before queue_free (which is deferred).
	assert_true(hs.get("_dead"), "HealStation should be marked dead after lethal damage")

# ── MinionBase.heal() ─────────────────────────────────────────────────────────

class FakeMinion extends MinionBase:
	func _build_visuals() -> void:
		pass
	func _init() -> void:
		var sa := AudioStreamPlayer3D.new()
		sa.name = "ShootAudio"
		add_child(sa)
		var da := AudioStreamPlayer3D.new()
		da.name = "DeathAudio"
		add_child(da)
	func _ready() -> void:
		health = max_health
		add_to_group("minions")
		add_to_group("minion_units")

func test_minion_has_heal_method() -> void:
	var m := FakeMinion.new()
	add_child_autofree(m)
	assert_true(m.has_method("heal"), "MinionBase must have a heal() method")

func test_minion_heal_increases_health() -> void:
	var m := FakeMinion.new()
	m.max_health = 100.0
	add_child_autofree(m)
	m.health = 50.0
	m.heal(20.0)
	assert_almost_eq(m.health, 70.0, 0.001, "heal() must increase minion health")

func test_minion_heal_capped_at_max_health() -> void:
	var m := FakeMinion.new()
	m.max_health = 100.0
	add_child_autofree(m)
	m.health = 90.0
	m.heal(9999.0)
	assert_almost_eq(m.health, 100.0, 0.001, "heal() must not exceed max_health")

# ── _process heal loop ────────────────────────────────────────────────────────

# Fake body with heal() that records calls — must declare properties so
# Node.get("player_team") duck-typing works correctly.
class FakeHealTarget extends Node3D:
	var player_team: int = 0
	var heal_called: bool = false
	var heal_amount: float = 0.0
	func heal(amount: float) -> void:
		heal_called = true
		heal_amount += amount

func test_process_heals_friendly_body_in_range() -> void:
	var hs: StaticBody3D = _make_station(0)
	var target := FakeHealTarget.new()
	target.player_team = 0
	add_child_autofree(target)
	var bodies: Array = hs.get("_bodies_in_range")
	bodies.append(target)
	hs.set("_bodies_in_range", bodies)
	hs.call("_process", 1.0)
	assert_true(target.heal_called, "_process must call heal() on a friendly body in range")
	assert_almost_eq(target.heal_amount, HealStationScript.HEAL_RATE * 1.0, 0.001,
		"_process must heal at HEAL_RATE per second")

func test_process_skips_enemy_body_in_range() -> void:
	var hs: StaticBody3D = _make_station(0)
	var target := FakeHealTarget.new()
	target.player_team = 1  # enemy team
	add_child_autofree(target)
	var bodies: Array = hs.get("_bodies_in_range")
	bodies.append(target)
	hs.set("_bodies_in_range", bodies)
	hs.call("_process", 1.0)
	assert_false(target.heal_called, "_process must not heal an enemy body")

# ── Lifetime expiry ───────────────────────────────────────────────────────────

func test_expires_after_lifetime() -> void:
	var hs: StaticBody3D = _make_station()
	# Wind _age to just before LIFETIME, then tick past it.
	hs.set("_age", HealStationScript.LIFETIME - 0.01)
	hs.call("_process", 0.02)
	assert_true(hs.get("_dead"),
		"HealStation must die when _age reaches LIFETIME")
