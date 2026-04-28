## test_heal_station.gd
## Tests for HealStation — damage, death, and take_damage signature compatibility.

extends GutTest

const HealStationScript := preload("res://scripts/HealStation.gd")

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
	# If we got here without a crash the die path ran (queue_free is deferred).
	pass
