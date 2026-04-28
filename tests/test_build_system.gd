# test_build_system.gd
# Tier 1/2 — unit tests for BuildSystem placement validation and cost logic.
# We test the pure-logic helpers (get_item_cost, can_place_item team-half check,
# spacing computation) without needing a full physics world.
#
# NOTE: BuildSystem is NOT an autoload — it lives as a child of Main.tscn.
# We instantiate it directly here using its script path.
extends GutTest

const BuildSystemScript := preload("res://scripts/BuildSystem.gd")

var bs: Node  # local BuildSystem instance

# ─── helpers ──────────────────────────────────────────────────────────────────

# Place a fake tower node in the "towers" group at the given position so the
# spacing check in can_place_item() has something to collide against.
class FakeTower extends Node3D:
	var tower_type: String = "cannon"

func _add_fake_tower(pos: Vector3, tower_type: String = "cannon") -> Node3D:
	var n := FakeTower.new()
	n.tower_type = tower_type
	add_child_autofree(n)
	n.global_position = pos  # set AFTER add_child so the node is in the tree
	n.add_to_group("towers")
	return n

func _add_fake_drop(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child_autofree(n)
	n.global_position = pos  # set AFTER add_child
	n.add_to_group("supporter_drops")
	return n

func before_each() -> void:
	bs = Node.new()
	bs.set_script(BuildSystemScript)
	add_child_autofree(bs)
	# _ready() runs automatically; spacing is computed there.
	TeamData.sync_from_server(200, 200)

# ── get_item_cost ─────────────────────────────────────────────────────────────

func test_cost_cannon() -> void:
	assert_eq(bs.get_item_cost("cannon", ""), 25)

func test_cost_mortar() -> void:
	assert_eq(bs.get_item_cost("mortar", ""), 35)

func test_cost_barrier() -> void:
	assert_eq(bs.get_item_cost("barrier", ""), 10)

func test_cost_machinegun() -> void:
	assert_eq(bs.get_item_cost("machinegun", ""), 40)

func test_cost_launcher_missile() -> void:
	assert_eq(bs.get_item_cost("launcher_missile", ""), 50)

func test_cost_healthpack() -> void:
	assert_eq(bs.get_item_cost("healthpack", ""), 15)

func test_cost_healstation() -> void:
	assert_eq(bs.get_item_cost("healstation", ""), 25)

func test_cost_weapon_pistol() -> void:
	assert_eq(bs.get_item_cost("weapon", "pistol"), 10)

func test_cost_weapon_rifle() -> void:
	assert_eq(bs.get_item_cost("weapon", "rifle"), 20)

func test_cost_weapon_heavy() -> void:
	assert_eq(bs.get_item_cost("weapon", "heavy"), 30)

func test_cost_weapon_rocket_launcher() -> void:
	assert_eq(bs.get_item_cost("weapon", "rocket_launcher"), 60)

func test_cost_unknown_type_returns_zero() -> void:
	assert_eq(bs.get_item_cost("does_not_exist", ""), 0)

func test_cost_unknown_weapon_subtype_returns_zero() -> void:
	assert_eq(bs.get_item_cost("weapon", "flamethrower"), 0)

# ── get_tower_cost (legacy shim) ──────────────────────────────────────────────

func test_get_tower_cost_equals_cannon_cost() -> void:
	assert_eq(bs.get_tower_cost(), bs.get_item_cost("cannon", ""))

# ── spacing computation (_ready populates this) ───────────────────────────────

func test_spacing_computed_for_cannon() -> void:
	var def: Dictionary = bs.PLACEABLE_DEFS["cannon"]
	assert_true(def.has("spacing"), "cannon def should have 'spacing' key after _ready()")
	# cannon attack_range=30; spacing = 30*0.75 = 22.5
	assert_eq(def["spacing"], 22.5)

func test_spacing_computed_for_barrier_passive() -> void:
	var def: Dictionary = bs.PLACEABLE_DEFS["barrier"]
	# barrier attack_range=0 → SPACING_PASSIVE = 3.0
	assert_eq(def["spacing"], 3.0)

func test_spacing_computed_for_mortar() -> void:
	var def: Dictionary = bs.PLACEABLE_DEFS["mortar"]
	# mortar attack_range=50; spacing = 50*0.75 = 37.5
	assert_eq(def["spacing"], 37.5)

# ── can_place_item — team half guard ──────────────────────────────────────────
# z > 0 is team 0's half; z < 0 is team 1's half.

func test_team0_cannot_place_on_negative_z() -> void:
	var result: bool = bs.can_place_item(Vector3(0.0, 5.0, -10.0), 0, "barrier")
	assert_false(result, "Team 0 must not place in team 1's half (z < 0)")

func test_team1_cannot_place_on_positive_z() -> void:
	var result: bool = bs.can_place_item(Vector3(0.0, 5.0, 10.0), 1, "barrier")
	assert_false(result, "Team 1 must not place in team 0's half (z > 0)")

func test_unknown_item_type_always_returns_false() -> void:
	assert_false(bs.can_place_item(Vector3(0, 5, 10), 0, "nonexistent"))

# ── spacing check — nodes in tree ─────────────────────────────────────────────

func test_spacing_blocks_placement_too_close() -> void:
	_add_fake_tower(Vector3(0.0, 0.0, 50.0), "cannon")
	# barrier spacing=3; cannon spacing=22.5; effective=22.5; distance=5 < 22.5 → blocked
	var result: bool = bs.can_place_item(Vector3(0.0, 0.0, 55.0), 0, "barrier")
	assert_false(result, "Placement within existing tower's spacing should be rejected")

func test_spacing_allows_placement_far_enough() -> void:
	_add_fake_tower(Vector3(0.0, 0.0, 10.0), "cannon")
	# 50 units away > cannon spacing 22.5 → allowed (headless: no physics/lane checks)
	var result: bool = bs.can_place_item(Vector3(0.0, 0.0, 60.0), 0, "barrier")
	assert_true(result, "Placement outside all tower spacings should be allowed (headless)")

func test_drop_spacing_check_uses_supporter_drops_group() -> void:
	_add_fake_drop(Vector3(0.0, 0.0, 10.0))
	var result: bool = bs.can_place_item(Vector3(0.0, 0.0, 12.0), 0, "healthpack")
	assert_false(result, "Healthpack within existing drop's spacing (5 units) should be rejected")

# ── place_item — spend_points guard ──────────────────────────────────────────

func test_place_item_returns_empty_string_when_insufficient_funds() -> void:
	TeamData.sync_from_server(5, 5)  # less than cannon cost (25)
	var node_name: String = bs.place_item(Vector3(0.0, 5.0, 50.0), 0, "cannon", "")
	assert_eq(node_name, "", "place_item should fail and return '' when team has insufficient funds")

func test_place_item_returns_empty_string_on_bad_type() -> void:
	var node_name: String = bs.place_item(Vector3(0.0, 5.0, 50.0), 0, "bogus", "")
	assert_eq(node_name, "")

# ── PLACEABLE_DEFS integrity ──────────────────────────────────────────────────

func test_all_defs_have_scene_path() -> void:
	for key in bs.PLACEABLE_DEFS:
		var def: Dictionary = bs.PLACEABLE_DEFS[key]
		assert_true(def.has("scene") and def["scene"] != "",
			"PLACEABLE_DEFS[%s] missing scene path" % key)

func test_all_defs_have_is_tower_flag() -> void:
	for key in bs.PLACEABLE_DEFS:
		var def: Dictionary = bs.PLACEABLE_DEFS[key]
		assert_true(def.has("is_tower"),
			"PLACEABLE_DEFS[%s] missing is_tower flag" % key)

func test_all_tower_defs_have_spacing_after_ready() -> void:
	for key in bs.PLACEABLE_DEFS:
		var def: Dictionary = bs.PLACEABLE_DEFS[key]
		if def.get("is_tower", false):
			assert_true(def.has("spacing"),
				"Tower PLACEABLE_DEFS[%s] missing spacing (not computed in _ready?)" % key)
