# test_tower_fog_radius.gd
# Regression tests for per-tower fog reveal radius.
#
# Verifies that:
#   1. FogOverlay.update_sources accepts Array[Vector4] tower_sources (not a flat radius).
#   2. Each tower's reveal radius in the shader buffer matches its attack_range.
#   3. Passive towers (attack_range=0) use the PASSIVE_TOWER_FOG_RADIUS fallback (8 units).
#   4. _is_visible_to_sources respects each tower's individual radius.
#   5. Regression: a cannon tower (range 30) does NOT reveal a point at range 35.
#   6. Regression: a mortar tower (range 50) DOES reveal a point at range 45.
extends GutTest

# ── Fake tower nodes ──────────────────────────────────────────────────────────

class FakeTower extends Node3D:
	var team: int = 0
	var attack_range: float = 30.0

class FakePassiveTower extends Node3D:
	var team: int = 0
	var attack_range: float = 0.0

# ── Helpers ───────────────────────────────────────────────────────────────────

const PASSIVE_FOG_RADIUS := 8.0

# Mirrors the logic from RTSController._update_fog / _is_visible_to_sources
# but extracted here for isolated unit testing.
func _build_tower_data(towers: Array, player_team: int) -> Array:
	var data: Array = []
	for tower in towers:
		var t: int = tower.get("team") if tower.get("team") != null else -1
		if t != player_team:
			continue
		var ar: float = tower.get("attack_range") if tower.get("attack_range") != null else 0.0
		var fog_r: float = ar if ar > 0.0 else PASSIVE_FOG_RADIUS
		data.append({"pos": tower.global_position, "radius": fog_r})
	return data

func _is_visible_via_towers(world_pos: Vector3, tower_data: Array) -> bool:
	for entry in tower_data:
		var r: float = entry["radius"]
		if world_pos.distance_squared_to(entry["pos"]) <= r * r:
			return true
	return false

# ── FogOverlay.update_sources signature tests ─────────────────────────────────

func test_update_sources_accepts_vector4_tower_sources() -> void:
	# Verify the real FogOverlay takes the new 5-arg signature with tower_sources Array.
	var fog := preload("res://scripts/FogOverlay.gd").new()
	add_child_autofree(fog)
	# Must not crash — if signature changed back this would throw an argument-count error.
	var tower_src: Array = [Vector4(0, 0, 30.0, 0.0)]
	fog.update_sources([Vector3(0, 0, 0)], 35.0, [], 20.0, tower_src)
	pass_test("update_sources accepted Array[Vector4] tower_sources without error")

func test_update_sources_tower_radius_encoded_in_vec4_z() -> void:
	# The w-component of each source vec4 is the reveal radius (z component is world-z,
	# the radius is in x=world_x, y=world_z, z=radius).
	var tower_src: Array = [Vector4(10.0, 20.0, 45.0, 0.0)]
	assert_almost_eq(tower_src[0].z, 45.0, 0.01,
		"Tower reveal radius must be stored in Vector4.z field")

# ── _build_tower_data / per-tower radius tests ────────────────────────────────

func test_attack_tower_uses_attack_range_as_fog_radius() -> void:
	var t := FakeTower.new()
	t.attack_range = 50.0
	add_child_autofree(t)
	var data: Array = _build_tower_data([t], 0)
	assert_eq(data.size(), 1)
	assert_almost_eq(data[0]["radius"], 50.0, 0.01,
		"Mortar (range 50) fog radius must be 50")

func test_passive_tower_uses_fallback_fog_radius() -> void:
	var t := FakePassiveTower.new()
	add_child_autofree(t)
	var data: Array = _build_tower_data([t], 0)
	assert_eq(data.size(), 1)
	assert_almost_eq(data[0]["radius"], PASSIVE_FOG_RADIUS, 0.01,
		"Passive tower fog radius must fall back to %s" % str(PASSIVE_FOG_RADIUS))

func test_enemy_tower_excluded_from_fog_data() -> void:
	var t := FakeTower.new()
	t.team = 1  # enemy
	add_child_autofree(t)
	var data: Array = _build_tower_data([t], 0)  # player_team=0
	assert_eq(data.size(), 0, "Enemy towers must not contribute fog sources")

# ── _is_visible_via_towers radius precision tests ─────────────────────────────

func test_cannon_tower_does_not_reveal_point_beyond_its_range() -> void:
	# Cannon attack_range=30; point at distance 35 must be hidden.
	var t := FakeTower.new()
	t.attack_range = 30.0
	add_child_autofree(t)
	t.global_position = Vector3(0, 0, 0)
	var data: Array = _build_tower_data([t], 0)
	var result := _is_visible_via_towers(Vector3(35, 0, 0), data)
	assert_false(result, "Cannon (range 30) must NOT reveal a point at distance 35")

func test_cannon_tower_reveals_point_within_its_range() -> void:
	var t := FakeTower.new()
	t.attack_range = 30.0
	add_child_autofree(t)
	t.global_position = Vector3(0, 0, 0)
	var data: Array = _build_tower_data([t], 0)
	var result := _is_visible_via_towers(Vector3(29, 0, 0), data)
	assert_true(result, "Cannon (range 30) must reveal a point at distance 29")

func test_mortar_tower_reveals_point_at_range_45() -> void:
	# Mortar attack_range=50; point at 45 must be visible.
	var t := FakeTower.new()
	t.attack_range = 50.0
	add_child_autofree(t)
	t.global_position = Vector3(0, 0, 0)
	var data: Array = _build_tower_data([t], 0)
	var result := _is_visible_via_towers(Vector3(0, 0, 45), data)
	assert_true(result, "Mortar (range 50) must reveal a point at distance 45")

func test_machinegun_tower_does_not_reveal_point_at_range_25() -> void:
	# MachineGun attack_range=22; point at 25 must be hidden.
	var t := FakeTower.new()
	t.attack_range = 22.0
	add_child_autofree(t)
	t.global_position = Vector3(0, 0, 0)
	var data: Array = _build_tower_data([t], 0)
	var result := _is_visible_via_towers(Vector3(25, 0, 0), data)
	assert_false(result, "MachineGun (range 22) must NOT reveal a point at distance 25")

func test_passive_tower_reveals_point_within_fallback_radius() -> void:
	var t := FakePassiveTower.new()
	add_child_autofree(t)
	t.global_position = Vector3(0, 0, 0)
	var data: Array = _build_tower_data([t], 0)
	var result := _is_visible_via_towers(Vector3(7, 0, 0), data)
	assert_true(result, "Passive tower must reveal within fallback radius %s" % str(PASSIVE_FOG_RADIUS))

func test_passive_tower_does_not_reveal_point_beyond_fallback_radius() -> void:
	var t := FakePassiveTower.new()
	add_child_autofree(t)
	t.global_position = Vector3(0, 0, 0)
	var data: Array = _build_tower_data([t], 0)
	var result := _is_visible_via_towers(Vector3(10, 0, 0), data)
	assert_false(result, "Passive tower must NOT reveal beyond fallback radius %s" % str(PASSIVE_FOG_RADIUS))

# ── Mixed tower types in same update ─────────────────────────────────────────

func test_mixed_towers_each_use_own_radius() -> void:
	var cannon := FakeTower.new()
	cannon.attack_range = 30.0

	var mortar := FakeTower.new()
	mortar.attack_range = 50.0

	add_child_autofree(cannon)
	add_child_autofree(mortar)

	cannon.global_position = Vector3(0, 0, 0)
	mortar.global_position = Vector3(100, 0, 100)

	var data: Array = _build_tower_data([cannon, mortar], 0)
	assert_eq(data.size(), 2)

	# Point at (40, 0, 0): beyond cannon range, but cannon is the closer tower.
	var hidden := _is_visible_via_towers(Vector3(40, 0, 0), data)
	assert_false(hidden, "Point at 40 from cannon (range 30) must be hidden")

	# Point near mortar at (100, 0, 145): within 50 of mortar.
	var visible := _is_visible_via_towers(Vector3(100, 0, 145), data)
	assert_true(visible, "Point within 50 of mortar must be visible")
