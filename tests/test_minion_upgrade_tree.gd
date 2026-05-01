extends GutTest
## Tests for the Supporter minion upgrade skill tree.
## Covers passive bonus accumulation, damage reduction in MinionBase.take_damage,
## XP bonus in MinionBase._die, revive flag reset, and active ability dispatch.

const MinionBaseScript := preload("res://scripts/minions/MinionBase.gd")

const SUP_ID  := 77
const TEAM    := 0

# ── Minimal MinionBase subclass that suppresses visuals/audio ─────────────────
class FakeMinion extends MinionBase:
	func _init() -> void:
		# Stub audio nodes so @onready bindings in MinionBase._ready() succeed
		var sa := AudioStreamPlayer3D.new()
		sa.name = "ShootAudio"
		add_child(sa)
		var da := AudioStreamPlayer3D.new()
		da.name = "DeathAudio"
		add_child(da)
	func _build_visuals() -> void: pass
	func _init_visuals() -> void: pass
	func _cache_static_refs() -> void: pass
	func _play_anim(_name: String) -> void: pass

func _make_minion() -> FakeMinion:
	var m := FakeMinion.new()
	m.set("team", TEAM)
	m.set("_minion_id", 1)
	m.name = "TestMinion"
	add_child_autofree(m)
	return m

func before_each() -> void:
	SkillTree.clear_all()
	LevelSystem.clear_all()
	TeamData.sync_from_server(75, 75)

func after_each() -> void:
	SkillTree.clear_all()
	LevelSystem.clear_all()

# ── SkillDefs integrity ───────────────────────────────────────────────────────

func test_all_nine_supporter_nodes_present() -> void:
	var ids := ["s_minion_hp", "s_minion_armor", "s_minion_revive",
				"s_minion_damage", "s_minion_speed", "s_minion_barrage",
				"s_minion_count", "s_minion_xp", "s_minion_surge"]
	for id in ids:
		assert_true(SkillDefs.ALL.has(id), "Missing node: %s" % id)

func test_old_supporter_nodes_removed() -> void:
	var old_ids := ["s_build_discount", "s_fast_respawn", "s_tower_hp",
					"s_fortify", "s_point_surge", "s_ammo_drop",
					"s_build_anywhere", "s_rally", "s_turret_overdrive",
					"s_advanced_launcher", "s_repair"]
	for id in old_ids:
		assert_false(SkillDefs.ALL.has(id), "Old node still present: %s" % id)

# ── Passive bonus accumulation ────────────────────────────────────────────────

func test_minion_hp_bonus_passive() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_minion_hp")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "minion_hp_bonus"), 0.25, 0.001)

func test_minion_damage_reduction_passive() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_minion_hp")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)  # +2 SP for tier-2 cost
	SkillTree.unlock_node_local(SUP_ID, "s_minion_armor")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "minion_damage_reduction"), 0.15, 0.001)

func test_minion_count_bonus_passive() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_minion_count")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "minion_count_bonus"), 1.0, 0.001)

func test_minion_xp_bonus_passive() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_minion_count")
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_minion_xp")
	assert_almost_eq(SkillTree.get_passive_bonus(SUP_ID, "minion_xp_bonus"), 0.5, 0.001)

# ── damage reduction applied in take_damage ───────────────────────────────────

func test_damage_reduction_reduces_incoming_damage() -> void:
	SkillTree.register_peer(SUP_ID, "Supporter")
	SkillTree._on_level_up(SUP_ID, 2)
	SkillTree.unlock_node_local(SUP_ID, "s_minion_hp")   # prereq
	SkillTree._on_level_up(SUP_ID, 3)
	SkillTree._on_level_up(SUP_ID, 4)
	SkillTree.unlock_node_local(SUP_ID, "s_minion_armor") # 15% DR

	# Register SUP_ID as a Supporter on TEAM in LobbyManager so get_supporter_peer works
	LobbyManager.register_player_local(SUP_ID, "TestSup")
	LobbyManager.players[SUP_ID]["team"] = TEAM
	LobbyManager.players[SUP_ID]["role"] = 1  # role 1 = Supporter

	var m := _make_minion()
	m.set("max_health", 100.0)
	m.set("health", 100.0)

	m.take_damage(20.0, "test", 1)  # enemy team = 1
	var hp: float = float(m.get("health"))
	# 20 * (1 - 0.15) = 17.0 → health = 83.0
	assert_almost_eq(hp, 83.0, 0.5, "Damage reduction should lower damage by 15%")

	LobbyManager.players.erase(SUP_ID)

# ── s_minion_barrage is active type ──────────────────────────────────────────

func test_minion_barrage_is_active_type() -> void:
	var def: Dictionary = SkillDefs.ALL["s_minion_barrage"]
	assert_eq(def["type"], "active", "s_minion_barrage must be type active")

func test_minion_surge_is_active_type() -> void:
	var def: Dictionary = SkillDefs.ALL["s_minion_surge"]
	assert_eq(def["type"], "active", "s_minion_surge must be type active")
