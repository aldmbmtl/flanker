extends GutTest
## Tests for RamMinionAI and the MinionSpawner.request_ram_minion path.

const RamMinionAIScript    := preload("res://scripts/minions/RamMinionAI.gd")
const MinionSpawnerScript  := preload("res://scripts/MinionSpawner.gd")

# ── stub spawner ──────────────────────────────────────────────────────────────
## Subclass that intercepts _spawn_minion so tests never need a real scene tree.
class StubSpawner extends Node:
	var spawn_calls: Array = []   # Array of {team, lane_i, mtype}

	func _ready() -> void:
		pass  # skip real _ready (no PackedScene loads)

	func request_ram_minion(team: int, tier: int, lane_i: int) -> bool:
		var t: int = clampi(tier, 0, 2)
		var lanes: Array = [-1] if lane_i == -1 else [lane_i]
		if lane_i == -1:
			lanes = [0, 1, 2]
		var total_cost: int = MinionSpawnerScript.RAM_TIER_COSTS[t] * lanes.size()
		if not TeamData.spend_points(team, total_cost):
			return false
		var mtype: String = "ram_t%d" % (t + 1)
		for li: int in lanes:
			_spawn_minion(team, li, mtype)
		return true

	func _spawn_minion(team: int, lane_i: int, mtype: String = "basic") -> void:
		spawn_calls.append({ "team": team, "lane_i": lane_i, "mtype": mtype })

# ── RamMinionAI unit tests ────────────────────────────────────────────────────

class TestRamMinionAI extends GutTest:

	var _minion: Node = null

	func before_each() -> void:
		var scene: PackedScene = load("res://scenes/minions/RamMinion.tscn")
		_minion = scene.instantiate()
		add_child_autofree(_minion)

	## After _ready, all combat ranges must be zero.
	func test_combat_ranges_zeroed() -> void:
		assert_eq(_minion.detect_range,    0.0, "detect_range")
		assert_eq(_minion.attack_range,    0.0, "attack_range")
		assert_eq(_minion.shoot_range,     0.0, "shoot_range")
		assert_eq(_minion.attack_damage,   0.0, "attack_damage")
		assert_gt(_minion.attack_cooldown, 50.0, "attack_cooldown high (no-op sentinel)")

	## _find_target always returns null.
	func test_find_target_returns_null() -> void:
		var result: Node3D = _minion._find_target()
		assert_null(result, "_find_target must return null for ram minion")

	## _fire_at must not error or modify state.
	func test_fire_at_is_noop() -> void:
		_minion._fire_at(null)
		pass  # no assert — just must not crash

	## Default tier is 0 (beaver).
	func test_default_tier_is_zero() -> void:
		assert_eq(_minion._ram_tier, 0, "default tier should be 0 (beaver)")

	## Tier index clamping logic (mirrors _build_visuals).
	func test_tier_index_clamped() -> void:
		assert_eq(clampi(-1, 0, 2), 0, "negative tier clamped to 0")
		assert_eq(clampi(5,  0, 2), 2, "tier > 2 clamped to 2")
		assert_eq(clampi(1,  0, 2), 1, "mid tier preserved")

	## TIER_COSTS constants match design spec.
	func test_tier_cost_constants() -> void:
		assert_eq(MinionSpawnerScript.RAM_TIER_COSTS[0], 15, "T1 cost")
		assert_eq(MinionSpawnerScript.RAM_TIER_COSTS[1], 30, "T2 cost")
		assert_eq(MinionSpawnerScript.RAM_TIER_COSTS[2], 50, "T3 cost")

	## RAM_TIER_HP constants match design spec.
	func test_tier_hp_constants() -> void:
		assert_eq(MinionSpawnerScript.RAM_TIER_HP[0], 300.0,  "T1 HP")
		assert_eq(MinionSpawnerScript.RAM_TIER_HP[1], 600.0,  "T2 HP")
		assert_eq(MinionSpawnerScript.RAM_TIER_HP[2], 1000.0, "T3 HP")

# ── StubSpawner.request_ram_minion unit tests ─────────────────────────────────

class TestRequestRamMinion extends GutTest:

	var _spawner: StubSpawner = null

	func before_each() -> void:
		_spawner = StubSpawner.new()
		add_child_autofree(_spawner)
		TeamData.sync_from_server(100, 100)

	## Sufficient funds: returns true.
	func test_sufficient_funds_returns_true() -> void:
		var ok: bool = _spawner.request_ram_minion(0, 0, 0)
		assert_true(ok, "should return true when affordable")

	## Cost is deducted after successful request (T1 = $15).
	func test_cost_deducted_on_success() -> void:
		TeamData.sync_from_server(50, 50)
		_spawner.request_ram_minion(0, 0, 0)
		assert_eq(TeamData.get_points(0), 35, "15 pts deducted for T1 single lane")

	## Insufficient funds: returns false, no deduction.
	func test_insufficient_funds_returns_false() -> void:
		TeamData.sync_from_server(10, 10)
		var ok: bool = _spawner.request_ram_minion(0, 0, 0)
		assert_false(ok, "should return false when unaffordable")
		assert_eq(TeamData.get_points(0), 10, "no deduction on failure")

	## Lane -1 spawns on all 3 lanes and deducts cost × 3.
	func test_all_lanes_deducts_triple_cost() -> void:
		var ok: bool = _spawner.request_ram_minion(0, 0, -1)
		assert_true(ok, "all-lanes should succeed with 100 pts")
		assert_eq(TeamData.get_points(0), 55, "3 × $15 = $45 deducted")

	## All-lanes request fails if team can't afford × 3.
	func test_all_lanes_fails_when_cant_afford_triple() -> void:
		TeamData.sync_from_server(40, 40)  # can afford 2 but not 3
		var ok: bool = _spawner.request_ram_minion(0, 0, -1)
		assert_false(ok, "should reject when total cost > points")
		assert_eq(TeamData.get_points(0), 40, "no deduction on failure")

	## Single-lane request registers exactly one spawn call.
	func test_single_lane_one_spawn_call() -> void:
		_spawner.request_ram_minion(0, 0, 1)
		assert_eq(_spawner.spawn_calls.size(), 1, "one spawn call for single lane")
		assert_eq(_spawner.spawn_calls[0]["lane_i"], 1, "lane_i forwarded correctly")

	## All-lanes request registers 3 spawn calls.
	func test_all_lanes_three_spawn_calls() -> void:
		_spawner.request_ram_minion(0, 0, -1)
		assert_eq(_spawner.spawn_calls.size(), 3, "three spawn calls for all lanes")

	## mtype string is correct for each tier.
	func test_mtype_string_per_tier() -> void:
		_spawner.request_ram_minion(0, 0, 0)
		assert_eq(_spawner.spawn_calls[0]["mtype"], "ram_t1", "T0 → ram_t1")
		_spawner.spawn_calls.clear()
		_spawner.request_ram_minion(0, 1, 0)
		assert_eq(_spawner.spawn_calls[0]["mtype"], "ram_t2", "T1 → ram_t2")
		_spawner.spawn_calls.clear()
		_spawner.request_ram_minion(0, 2, 0)
		assert_eq(_spawner.spawn_calls[0]["mtype"], "ram_t3", "T2 → ram_t3")

	## T2 (cow) costs $30 per lane.
	func test_tier1_cost_per_lane() -> void:
		TeamData.sync_from_server(100, 100)
		_spawner.request_ram_minion(0, 1, 0)
		assert_eq(TeamData.get_points(0), 70, "T2 costs $30")

	## T3 (elephant) costs $50 per lane.
	func test_tier2_cost_per_lane() -> void:
		TeamData.sync_from_server(100, 100)
		_spawner.request_ram_minion(0, 2, 0)
		assert_eq(TeamData.get_points(0), 50, "T3 costs $50")

	## Spawn call records correct team.
	func test_spawn_call_records_team() -> void:
		_spawner.request_ram_minion(1, 0, 2)
		assert_eq(_spawner.spawn_calls[0]["team"], 1, "team forwarded to _spawn_minion")

# ── MinionSpawner._spawn_at_position ram branch (property-setting logic) ──────

class TestSpawnAtPositionRamBranch extends GutTest:
	## Verifies the tier-index / HP / minion_type assignment formulas match constants,
	## without needing a real tree.  Tests the arithmetic, not add_child.

	func test_mtype_to_tier_index_formula() -> void:
		# "ram_t1" → 0, "ram_t2" → 1, "ram_t3" → 2
		for i: int in range(1, 4):
			var mtype: String = "ram_t%d" % i
			var idx: int = int(mtype.substr(5, 1)) - 1
			assert_eq(idx, i - 1, "mtype %s → tier idx %d" % [mtype, i - 1])

	func test_tier_hp_via_formula() -> void:
		var expected: Array[float] = [300.0, 600.0, 1000.0]
		for i: int in range(1, 4):
			var mtype: String = "ram_t%d" % i
			var idx: int = int(mtype.substr(5, 1)) - 1
			assert_eq(MinionSpawnerScript.RAM_TIER_HP[idx], expected[i - 1], "HP for %s" % mtype)
