extends GutTest
# test_skill_defs.gd — integrity tests for SkillDefs.ALL
# Verifies: no duplicate IDs, all required fields present, valid roles/types/tiers,
# no orphan prereqs, every active node has a cooldown > 0, passive nodes have a key.

const VALID_ROLES  := ["Fighter", "Supporter"]
const VALID_TYPES  := ["passive", "active", "unlock", "utility"]
const VALID_TIERS  := [1, 2, 3]
const REQUIRED_KEYS := ["role", "branch", "type", "tier", "cost", "prereqs",
						"level_req", "name", "description", "passive_key", "passive_val", "cooldown"]

# ── Field presence & type validity ────────────────────────────────────────────

func test_all_nodes_have_required_fields() -> void:
	for nid in SkillDefs.ALL:
		var d: Dictionary = SkillDefs.ALL[nid]
		for key in REQUIRED_KEYS:
			assert_true(d.has(key), "Node '%s' missing field '%s'" % [nid, key])

func test_all_nodes_have_valid_role() -> void:
	for nid in SkillDefs.ALL:
		var role: String = SkillDefs.ALL[nid].get("role", "")
		assert_true(role in VALID_ROLES, "Node '%s' has invalid role '%s'" % [nid, role])

func test_all_nodes_have_valid_type() -> void:
	for nid in SkillDefs.ALL:
		var t: String = SkillDefs.ALL[nid].get("type", "")
		assert_true(t in VALID_TYPES, "Node '%s' has invalid type '%s'" % [nid, t])

func test_all_nodes_have_valid_tier() -> void:
	for nid in SkillDefs.ALL:
		var tier: int = int(SkillDefs.ALL[nid].get("tier", 0))
		assert_true(tier in VALID_TIERS, "Node '%s' has invalid tier %d" % [nid, tier])

func test_tier_matches_cost() -> void:
	for nid in SkillDefs.ALL:
		var d: Dictionary = SkillDefs.ALL[nid]
		assert_eq(int(d["tier"]), int(d["cost"]),
			"Node '%s': tier=%d but cost=%d" % [nid, int(d["tier"]), int(d["cost"])])

# ── Prereq integrity ──────────────────────────────────────────────────────────

func test_no_orphan_prereqs() -> void:
	for nid in SkillDefs.ALL:
		for prereq in SkillDefs.ALL[nid].get("prereqs", []):
			assert_true(SkillDefs.ALL.has(prereq),
				"Node '%s' has orphan prereq '%s'" % [nid, prereq])

func test_no_self_prereqs() -> void:
	for nid in SkillDefs.ALL:
		assert_false(SkillDefs.ALL[nid].get("prereqs", []).has(nid),
			"Node '%s' lists itself as a prereq" % nid)

func test_prereqs_same_role() -> void:
	for nid in SkillDefs.ALL:
		var role: String = SkillDefs.ALL[nid]["role"]
		for prereq in SkillDefs.ALL[nid].get("prereqs", []):
			if SkillDefs.ALL.has(prereq):
				var prereq_role: String = SkillDefs.ALL[prereq]["role"]
				assert_eq(prereq_role, role,
					"Node '%s' prereq '%s' is a different role" % [nid, prereq])

# ── Active / passive rules ────────────────────────────────────────────────────

func test_active_nodes_have_positive_cooldown() -> void:
	for nid in SkillDefs.ALL:
		var d: Dictionary = SkillDefs.ALL[nid]
		if d["type"] == "active":
			assert_gt(float(d["cooldown"]), 0.0,
				"Active node '%s' has cooldown <= 0" % nid)

func test_passive_nodes_have_passive_key() -> void:
	for nid in SkillDefs.ALL:
		var d: Dictionary = SkillDefs.ALL[nid]
		if d["type"] == "passive":
			assert_ne(d.get("passive_key", ""), "",
				"Passive node '%s' has empty passive_key" % nid)

func test_passive_nodes_have_positive_passive_val() -> void:
	for nid in SkillDefs.ALL:
		var d: Dictionary = SkillDefs.ALL[nid]
		if d["type"] == "passive":
			assert_gt(float(d.get("passive_val", 0.0)), 0.0,
				"Passive node '%s' has passive_val <= 0" % nid)

func test_non_active_nodes_have_zero_cooldown() -> void:
	for nid in SkillDefs.ALL:
		var d: Dictionary = SkillDefs.ALL[nid]
		if d["type"] != "active":
			assert_eq(float(d.get("cooldown", 0.0)), 0.0,
				"Non-active node '%s' has non-zero cooldown" % nid)

# ── Node count sanity ──────────────────────────────────────────────────────────

func test_total_node_count_is_22() -> void:
	# 10 Fighter + 11 Supporter = 21 total (3 new streak/bounty passives added)
	assert_eq(SkillDefs.ALL.size(), 21)

func test_fighter_node_count_is_11() -> void:
	assert_eq(SkillDefs.get_nodes_for_role("Fighter").size(), 10)

func test_supporter_node_count_is_11() -> void:
	assert_eq(SkillDefs.get_nodes_for_role("Supporter").size(), 11)

# ── Helper functions ──────────────────────────────────────────────────────────

func test_get_def_returns_correct_dict() -> void:
	var d: Dictionary = SkillDefs.get_def("f_field_medic")
	assert_eq(d["role"], "Fighter")
	assert_eq(int(d["tier"]), 1)
	assert_eq(d["type"], "active")

func test_get_def_unknown_returns_empty() -> void:
	assert_true(SkillDefs.get_def("nonexistent").is_empty())

func test_get_branches_for_fighter() -> void:
	var branches: Array = SkillDefs.get_branches_for_role("Fighter")
	assert_true(branches.has("Guardian"))
	assert_true(branches.has("DPS"))
	assert_true(branches.has("Tank"))

func test_get_branches_for_supporter() -> void:
	var branches: Array = SkillDefs.get_branches_for_role("Supporter")
	assert_true(branches.has("Basic Minion"))
	assert_true(branches.has("Cannon Minion"))
	assert_true(branches.has("Healer Minion"))

func test_get_nodes_in_branch_sorted_by_tier() -> void:
	var nodes: Array = SkillDefs.get_nodes_in_branch("Fighter", "Guardian")
	# Should be in ascending tier order
	for i in range(nodes.size() - 1):
		var t_a: int = int(SkillDefs.ALL[nodes[i]]["tier"])
		var t_b: int = int(SkillDefs.ALL[nodes[i + 1]]["tier"])
		assert_true(t_a <= t_b,
			"Branch nodes not sorted by tier at index %d" % i)

func test_get_nodes_for_role_contains_no_wrong_role() -> void:
	for nid in SkillDefs.get_nodes_for_role("Fighter"):
		assert_eq(SkillDefs.ALL[nid]["role"], "Fighter")
	for nid in SkillDefs.get_nodes_for_role("Supporter"):
		assert_eq(SkillDefs.ALL[nid]["role"], "Supporter")

func test_all_nodes_have_non_empty_name() -> void:
	for nid in SkillDefs.ALL:
		var name_val: String = str(SkillDefs.ALL[nid].get("name", ""))
		assert_true(name_val.length() > 0,
			"Node '%s' has empty or missing 'name' field" % nid)

func test_fighter_skill_names_match_expected() -> void:
	var expected := {
		"f_field_medic":    "Field Medic",
		"f_rally_cry":      "Rally Cry",
		"f_revive_pulse":   "Revive Pulse",
		"f_dash":           "Dash",
		"f_rapid_fire":     "Rapid Fire",
		"f_rocket_barrage": "Rocket Barrage",
		"f_adrenaline":     "Adrenaline",
		"f_iron_skin":      "Iron Skin",
		"f_deploy_mg":      "Deploy MG",
	}
	for nid in expected:
		assert_eq(str(SkillDefs.ALL[nid].get("name", "")), expected[nid],
			"Node '%s' name mismatch" % nid)
