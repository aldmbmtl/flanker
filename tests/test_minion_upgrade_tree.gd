extends GutTest
## Tests for the Supporter minion upgrade skill tree (new 3-branch system).
## Covers node presence, passive bonus accumulation, and active-type verification.

const SUP_ID := 77
const TEAM   := 0

func before_each() -> void:
	SkillTree.clear_all()
	LevelSystem.clear_all()
	TeamData.sync_from_server(75, 75)

func after_each() -> void:
	SkillTree.clear_all()
	LevelSystem.clear_all()

# ── SkillDefs integrity ───────────────────────────────────────────────────────

func test_all_nine_supporter_nodes_present() -> void:
	var ids := ["s_basic_t1", "s_basic_t2", "s_basic_t3",
				"s_cannon_t1", "s_cannon_t2", "s_cannon_t3",
				"s_healer_t1", "s_healer_t2", "s_healer_t3"]
	for id in ids:
		assert_true(SkillDefs.ALL.has(id), "Missing node: %s" % id)

func test_old_supporter_nodes_removed() -> void:
	# s_minion_revive is intentionally re-added as a new Supporter passive (Logistics branch,
	# tier 2) that interacts with the minion kill streak mechanic. It is no longer in the
	# "old nodes to remove" list. All other old minion upgrade nodes remain absent.
	var old_ids := ["s_minion_hp", "s_minion_armor",
					"s_minion_damage", "s_minion_speed", "s_minion_barrage",
					"s_minion_count", "s_minion_xp", "s_minion_surge",
					"s_build_discount", "s_fast_respawn", "s_tower_hp",
					"s_fortify", "s_point_surge", "s_ammo_drop",
					"s_build_anywhere", "s_rally", "s_turret_overdrive",
					"s_advanced_launcher", "s_repair"]
	for id in old_ids:
		assert_false(SkillDefs.ALL.has(id), "Old node still present: %s" % id)

# ── Passive bonus accumulation ────────────────────────────────────────────────

func test_basic_tier_passive_t1() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "basic_tier"), 1.0, 0.001)

func test_basic_tier_passive_t2_accumulates() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t2")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "basic_tier"), 2.0, 0.001)

func test_cannon_tier_passive_t1() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "cannon_tier"), 1.0, 0.001)

func test_cannon_tier_passive_t2_accumulates() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_cannon_t2")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "cannon_tier"), 2.0, 0.001)

func test_healer_tier_passive_t1() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "healer_tier"), 1.0, 0.001)

func test_healer_tier_passive_t2_accumulates() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t1")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_healer_t2")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "healer_tier"), 2.0, 0.001)

func test_branches_are_independent() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_basic_t1")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "cannon_tier"), 0.0, 0.001,
		"cannon_tier must not be affected by basic_tier unlock")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "healer_tier"), 0.0, 0.001,
		"healer_tier must not be affected by basic_tier unlock")

# ── Active node type verification ─────────────────────────────────────────────

func test_basic_t3_is_active_type() -> void:
	var def: Dictionary = SkillDefs.ALL["s_basic_t3"]
	assert_eq(def["type"], "active", "s_basic_t3 must be type active")

func test_cannon_t3_is_active_type() -> void:
	var def: Dictionary = SkillDefs.ALL["s_cannon_t3"]
	assert_eq(def["type"], "active", "s_cannon_t3 must be type active")

func test_healer_t3_is_active_type() -> void:
	var def: Dictionary = SkillDefs.ALL["s_healer_t3"]
	assert_eq(def["type"], "active", "s_healer_t3 must be type active")

func test_t1_nodes_are_passive_type() -> void:
	for id in ["s_basic_t1", "s_cannon_t1", "s_healer_t1"]:
		var def: Dictionary = SkillDefs.ALL[id]
		assert_eq(def["type"], "passive", "%s must be type passive" % id)

func test_t2_nodes_are_passive_type() -> void:
	for id in ["s_basic_t2", "s_cannon_t2", "s_healer_t2"]:
		var def: Dictionary = SkillDefs.ALL[id]
		assert_eq(def["type"], "passive", "%s must be type passive" % id)

# ── Prereq chain ──────────────────────────────────────────────────────────────

func test_t2_requires_t1_as_prereq() -> void:
	for branch in [["s_basic_t1","s_basic_t2"], ["s_cannon_t1","s_cannon_t2"], ["s_healer_t1","s_healer_t2"]]:
		var def: Dictionary = SkillDefs.ALL[branch[1]]
		assert_true(def["prereqs"].has(branch[0]),
			"%s must require %s" % [branch[1], branch[0]])

func test_t3_requires_t2_as_prereq() -> void:
	for branch in [["s_basic_t2","s_basic_t3"], ["s_cannon_t2","s_cannon_t3"], ["s_healer_t2","s_healer_t3"]]:
		var def: Dictionary = SkillDefs.ALL[branch[1]]
		assert_true(def["prereqs"].has(branch[0]),
			"%s must require %s" % [branch[1], branch[0]])

func test_t1_nodes_have_no_prereqs() -> void:
	for id in ["s_basic_t1", "s_cannon_t1", "s_healer_t1"]:
		var def: Dictionary = SkillDefs.ALL[id]
		assert_eq(def["prereqs"].size(), 0, "%s must have no prereqs" % id)
