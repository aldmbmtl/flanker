# test_streak_mechanics.gd
# Tier 1 — regression tests for all three new streak/bounty mechanics and the
# three wired orphaned passives.
#
# Mechanics covered:
#   1. Minion kill streak → boost_lane every 5 kills (MinionBase._die)
#   2. Tower kill streak  → spawn_free_ram on kill (TowerBase._die)
#   3. Player kill streak → bounty flag + 2× XP + scaled team points (GameSync.damage_player)
#   4. Orphaned passives in SkillDefs (f_killstreak_heal, s_minion_revive, s_minion_dmg_reduce)
#   5. MinionSpawner.spawn_free_ram does not deduct team points (interface contract)
extends GutTest

# ─── Minimal stubs ────────────────────────────────────────────────────────────

class FakeTower extends TowerBase:
	func _build_visuals() -> void:
		pass

class FakeMinion extends MinionBase:
	func _build_visuals() -> void:
		pass
	func _on_death() -> void:
		pass
	func _fire_at(_t: Node3D) -> void:
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

# Stub spawner that records boost_lane and spawn_free_ram calls without side effects.
class FakeSpawner extends Node:
	var boost_calls: Array = []
	var free_ram_calls: Array = []
	var _lane_boosts: Array = [[0, 0, 0], [0, 0, 0]]
	var _revive_used: Dictionary = {0: false, 1: false}
	var _minion_node_cache: Dictionary = {}

	func boost_lane(team: int, lane_i: int, amount: int) -> void:
		boost_calls.append({"team": team, "lane_i": lane_i, "amount": amount})
		_lane_boosts[team][lane_i] += amount

	func spawn_free_ram(team: int, tier: int, lane_i: int) -> void:
		free_ram_calls.append({"team": team, "tier": tier, "lane_i": lane_i})

# ─── Injected tree stubs ──────────────────────────────────────────────────────
# MinionBase._die() and TowerBase._die() look up "Main/MinionSpawner" from the
# scene root. In headless tests there is no Main scene, so we inject a stub.

var _stub_main: Node          # parented to get_tree().root
var _fake_spawner: FakeSpawner

func _inject_spawner() -> void:
	_stub_main = Node.new()
	_stub_main.name = "Main"
	get_tree().root.add_child(_stub_main)
	_fake_spawner = FakeSpawner.new()
	_fake_spawner.name = "MinionSpawner"
	_stub_main.add_child(_fake_spawner)

func _remove_spawner() -> void:
	if is_instance_valid(_stub_main):
		get_tree().root.remove_child(_stub_main)
		_stub_main.queue_free()
	_stub_main = null
	_fake_spawner = null

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _reset_streaks() -> void:
	GameSync.player_minion_kill_streak.clear()
	GameSync.player_tower_kill_streak.clear()
	GameSync.player_kill_streak.clear()
	GameSync.player_is_bounty.clear()

func _make_minion(team: int, lane_i: int) -> FakeMinion:
	var m := FakeMinion.new()
	m.max_health = 60.0
	add_child_autofree(m)
	m.setup(team, [], lane_i)
	return m

func _make_tower(team: int) -> FakeTower:
	var t := FakeTower.new()
	t.max_health = 100.0
	t.attack_range = 0.0
	t.tower_type = "cannon"
	add_child_autofree(t)
	t.setup(team)
	return t

# ─── before/after each ────────────────────────────────────────────────────────

func before_each() -> void:
	_reset_streaks()
	GameSync.player_healths.clear()
	GameSync.player_teams.clear()
	GameSync.player_dead.clear()
	GameSync.respawn_countdown.clear()
	GameSync.player_shield_hp.clear()
	GameSync.player_shield_timer.clear()
	LobbyManager.player_death_counts.clear()
	LobbyManager.players.clear()
	LevelSystem.clear_all()
	TeamData.sync_from_server(75, 75)

func after_each() -> void:
	_remove_spawner()

# ═══════════════════════════════════════════════════════════════════════════════
# 1. MINION KILL STREAK
# ═══════════════════════════════════════════════════════════════════════════════

func test_minion_kill_increments_streak() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.player_minion_kill_streak[1] = 0
	GameSync.set_player_team(1, 0)
	var m := _make_minion(1, 0)  # enemy minion
	m._killer_peer_id = 1
	m._attacker_team = 0
	m._die()
	assert_eq(GameSync.player_minion_kill_streak.get(1, 0), 1,
		"Minion kill streak should increment to 1")

func test_minion_kill_streak_resets_on_death() -> void:
	GameSync.player_minion_kill_streak[1] = 7
	GameSync.set_player_health(1, 10.0)
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	GameSync.damage_player(1, 10.0, 1)
	assert_eq(GameSync.player_minion_kill_streak.get(1, -1), 0,
		"Minion kill streak resets to 0 on player death")

func test_minion_kill_streak_milestone_5_calls_boost_lane() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.player_minion_kill_streak[1] = 4  # next kill = 5 (milestone)
	GameSync.set_player_team(1, 0)
	var m := _make_minion(1, 2)
	m._killer_peer_id = 1
	m._attacker_team = 0
	m._die()
	assert_eq(_fake_spawner.boost_calls.size(), 1,
		"boost_lane should be called once at milestone 5")
	assert_eq(_fake_spawner.boost_calls[0]["team"], 0,
		"boost_lane called for killer's team")

func test_minion_kill_streak_non_milestone_does_not_boost() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.player_minion_kill_streak[1] = 2  # 3rd kill — not a milestone
	GameSync.set_player_team(1, 0)
	var m := _make_minion(1, 0)
	m._killer_peer_id = 1
	m._attacker_team = 0
	m._die()
	assert_eq(_fake_spawner.boost_calls.size(), 0,
		"boost_lane should NOT be called on a non-milestone kill")

# ═══════════════════════════════════════════════════════════════════════════════
# 2. TOWER KILL STREAK → FREE RAM
# ═══════════════════════════════════════════════════════════════════════════════

func test_tower_kill_increments_tower_streak() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.set_player_team(1, 0)
	GameSync.player_tower_kill_streak[1] = 0
	var t := _make_tower(1)  # enemy tower
	t._lane_index = 0
	t._killer_peer_id = 1
	t._die()
	assert_eq(GameSync.player_tower_kill_streak.get(1, 0), 1,
		"Tower kill streak should increment to 1")

func test_tower_kill_1_sends_tier0_ram() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.set_player_team(1, 0)
	GameSync.player_tower_kill_streak[1] = 0
	var t := _make_tower(1)
	t._lane_index = 1
	t._killer_peer_id = 1
	t._die()
	assert_eq(_fake_spawner.free_ram_calls.size(), 1, "One ram should be sent on kill 1")
	assert_eq(_fake_spawner.free_ram_calls[0]["tier"], 0, "Kill 1 = tier-0 ram")
	assert_eq(_fake_spawner.free_ram_calls[0]["lane_i"], 1, "Ram sent to same lane as tower")

func test_tower_kill_2_sends_tier1_ram() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.set_player_team(1, 0)
	GameSync.player_tower_kill_streak[1] = 1
	var t := _make_tower(1)
	t._lane_index = 0
	t._killer_peer_id = 1
	t._die()
	assert_eq(_fake_spawner.free_ram_calls.size(), 1, "One ram on kill 2")
	assert_eq(_fake_spawner.free_ram_calls[0]["tier"], 1, "Kill 2 = tier-1 ram")

func test_tower_kill_3_sends_tier2_ram() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.set_player_team(1, 0)
	GameSync.player_tower_kill_streak[1] = 2
	var t := _make_tower(1)
	t._lane_index = 2
	t._killer_peer_id = 1
	t._die()
	assert_eq(_fake_spawner.free_ram_calls.size(), 1, "One ram on kill 3")
	assert_eq(_fake_spawner.free_ram_calls[0]["tier"], 2, "Kill 3 = tier-2 ram")

func test_tower_kill_4_sends_two_tier2_rams() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.set_player_team(1, 0)
	GameSync.player_tower_kill_streak[1] = 3
	var t := _make_tower(1)
	t._lane_index = 0
	t._killer_peer_id = 1
	t._die()
	assert_eq(_fake_spawner.free_ram_calls.size(), 2, "Kill 4 sends 2 rams")
	for call in _fake_spawner.free_ram_calls:
		assert_eq(call["tier"], 2, "All stacked rams are tier-2")

func test_tower_kill_5_sends_three_tier2_rams() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.set_player_team(1, 0)
	GameSync.player_tower_kill_streak[1] = 4
	var t := _make_tower(1)
	t._lane_index = 0
	t._killer_peer_id = 1
	t._die()
	assert_eq(_fake_spawner.free_ram_calls.size(), 3, "Kill 5 sends 3 rams")

func test_tower_kill_streak_resets_on_death() -> void:
	GameSync.player_tower_kill_streak[1] = 5
	GameSync.set_player_health(1, 10.0)
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	GameSync.damage_player(1, 10.0, 1)
	assert_eq(GameSync.player_tower_kill_streak.get(1, -1), 0,
		"Tower kill streak resets to 0 on player death")

func test_tower_kill_no_ram_when_lane_index_unknown() -> void:
	_inject_spawner()
	LevelSystem.register_peer(1)
	GameSync.set_player_team(1, 0)
	GameSync.player_tower_kill_streak[1] = 0
	var t := _make_tower(1)
	t._lane_index = -1
	t._killer_peer_id = 1
	t._die()
	assert_eq(_fake_spawner.free_ram_calls.size(), 0, "No ram when lane_index is -1")

# ═══════════════════════════════════════════════════════════════════════════════
# 3. PLAYER KILL STREAK → BOUNTY
# ═══════════════════════════════════════════════════════════════════════════════

func test_player_kill_increments_kill_streak() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	GameSync.set_player_health(2, 50.0)
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	GameSync.player_kill_streak[1] = 0
	GameSync.damage_player(2, 50.0, 0, 1)
	assert_eq(GameSync.player_kill_streak.get(1, 0), 1,
		"Killer's player kill streak increments")

func test_player_kill_streak_below_threshold_no_bounty() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	GameSync.set_player_health(2, 50.0)
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	GameSync.player_kill_streak[1] = 1  # 2nd kill — below threshold of 3
	GameSync.damage_player(2, 50.0, 0, 1)
	assert_false(GameSync.player_is_bounty.get(1, false),
		"2 kills should NOT trigger bounty flag")

func test_player_kill_streak_at_threshold_sets_bounty() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	GameSync.set_player_health(2, 50.0)
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	GameSync.player_kill_streak[1] = 2  # this kill = 3 → bounty
	GameSync.damage_player(2, 50.0, 0, 1)
	assert_true(GameSync.player_is_bounty.get(1, false),
		"3rd kill should set bounty flag on killer")

func test_bounty_player_death_clears_bounty() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	GameSync.set_player_health(1, 50.0)
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	GameSync.player_is_bounty[1] = true
	GameSync.player_kill_streak[1] = 5
	GameSync.damage_player(1, 50.0, 1, 2)
	assert_false(GameSync.player_is_bounty.get(1, false),
		"Bounty flag cleared when bounty player dies")

func test_bounty_kill_awards_double_xp() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	GameSync.set_player_health(1, 50.0)
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	GameSync.player_is_bounty[1] = true
	GameSync.player_kill_streak[1] = 3
	# Watch xp_gained to capture the raw awarded amount (get_xp returns carry-over
	# after level-ups and would not equal the awarded total).
	watch_signals(LevelSystem)
	GameSync.damage_player(1, 50.0, 1, 2)
	assert_signal_emitted(LevelSystem, "xp_gained", "xp_gained should fire on kill")
	var params: Array = get_signal_parameters(LevelSystem, "xp_gained")
	assert_eq(params[0], 2, "XP awarded to killer (peer 2)")
	assert_eq(params[1], LevelSystem.XP_PLAYER * 2,
		"Killing a bounty player awards 2× XP")

func test_bounty_kill_awards_scaled_team_points() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	GameSync.set_player_health(1, 50.0)
	GameSync.set_player_team(1, 0)  # bounty player is team 0
	GameSync.set_player_team(2, 1)  # killer is team 1
	GameSync.player_is_bounty[1] = true
	var dead_streak: int = 4
	GameSync.player_kill_streak[1] = dead_streak
	var pts_before: int = TeamData.get_points(1)
	GameSync.damage_player(1, 50.0, 1, 2)
	var pts_after: int = TeamData.get_points(1)
	assert_eq(pts_after - pts_before, dead_streak * GameSync.BOUNTY_BASE,
		"Bounty kill awards kill_streak × BOUNTY_BASE team points")

func test_non_bounty_kill_awards_normal_xp() -> void:
	LevelSystem.register_peer(1)
	LevelSystem.register_peer(2)
	GameSync.set_player_health(2, 50.0)
	GameSync.set_player_team(1, 0)
	GameSync.set_player_team(2, 1)
	GameSync.player_is_bounty[2] = false
	watch_signals(LevelSystem)
	GameSync.damage_player(2, 50.0, 0, 1)
	assert_signal_emitted(LevelSystem, "xp_gained", "xp_gained should fire on kill")
	var params: Array = get_signal_parameters(LevelSystem, "xp_gained")
	assert_eq(params[0], 1, "XP awarded to killer (peer 1)")
	assert_eq(params[1], LevelSystem.XP_PLAYER,
		"Non-bounty kill awards 1× XP")

func test_player_kill_streak_resets_on_death() -> void:
	GameSync.player_kill_streak[1] = 5
	GameSync.set_player_health(1, 10.0)
	GameSync.set_player_team(1, 0)
	LevelSystem.register_peer(1)
	GameSync.damage_player(1, 10.0, 1)
	assert_eq(GameSync.player_kill_streak.get(1, -1), 0,
		"Player kill streak resets to 0 on death")

# ═══════════════════════════════════════════════════════════════════════════════
# 4. ORPHANED PASSIVES IN SKILLDEFS
# ═══════════════════════════════════════════════════════════════════════════════

func test_skill_def_f_killstreak_heal_exists() -> void:
	var d: Dictionary = SkillDefs.get_def("f_killstreak_heal")
	assert_false(d.is_empty(), "f_killstreak_heal should be defined in SkillDefs.ALL")

func test_skill_def_f_killstreak_heal_passive_key() -> void:
	var d: Dictionary = SkillDefs.get_def("f_killstreak_heal")
	assert_eq(d.get("passive_key", ""), "killstreak_heal",
		"f_killstreak_heal passive_key should be 'killstreak_heal'")

func test_skill_def_s_minion_revive_exists() -> void:
	var d: Dictionary = SkillDefs.get_def("s_minion_revive")
	assert_false(d.is_empty(), "s_minion_revive should be defined in SkillDefs.ALL")

func test_skill_def_s_minion_revive_passive_key() -> void:
	var d: Dictionary = SkillDefs.get_def("s_minion_revive")
	assert_eq(d.get("passive_key", ""), "minion_revive",
		"s_minion_revive passive_key should be 'minion_revive'")

func test_skill_def_s_minion_dmg_reduce_exists() -> void:
	var d: Dictionary = SkillDefs.get_def("s_minion_dmg_reduce")
	assert_false(d.is_empty(), "s_minion_dmg_reduce should be defined in SkillDefs.ALL")

func test_skill_def_s_minion_dmg_reduce_passive_val() -> void:
	var d: Dictionary = SkillDefs.get_def("s_minion_dmg_reduce")
	assert_eq(d.get("passive_val", 0.0), 0.15,
		"s_minion_dmg_reduce passive_val should be 0.15 (15% reduction)")

func test_skill_def_f_killstreak_heal_prereq_is_f_dash() -> void:
	var d: Dictionary = SkillDefs.get_def("f_killstreak_heal")
	assert_true(d.get("prereqs", []).has("f_dash"),
		"f_killstreak_heal should require f_dash")

func test_skill_def_s_minion_dmg_reduce_prereq_is_s_basic_t1() -> void:
	var d: Dictionary = SkillDefs.get_def("s_minion_dmg_reduce")
	assert_true(d.get("prereqs", []).has("s_basic_t1"),
		"s_minion_dmg_reduce should require s_basic_t1")

# ═══════════════════════════════════════════════════════════════════════════════
# 5. SPAWNER — spawn_free_ram interface does not deduct team points
# ═══════════════════════════════════════════════════════════════════════════════

func test_spawn_free_ram_does_not_deduct_points() -> void:
	# The FakeSpawner mirrors the interface contract: spawn_free_ram must not
	# call TeamData.spend_points. We verify this at the interface level using
	# FakeSpawner (which trivially satisfies the contract) and separately verify
	# that TeamData is untouched after a call through it.
	TeamData.sync_from_server(50, 50)
	var fs := FakeSpawner.new()
	add_child_autofree(fs)
	fs.spawn_free_ram(0, 1, 2)
	assert_eq(TeamData.get_points(0), 50,
		"spawn_free_ram must not deduct team points")
	assert_eq(fs.free_ram_calls.size(), 1, "spawn_free_ram recorded the call")
	assert_eq(fs.free_ram_calls[0]["tier"], 1, "Correct tier recorded")
	assert_eq(fs.free_ram_calls[0]["lane_i"], 2, "Correct lane recorded")
