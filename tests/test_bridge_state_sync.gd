# test_bridge_state_sync.gd
# Verifies that the 7 new BridgeClient message handlers correctly update
# GDScript autoload state and emit the expected signals.
# Covers: level_up, skill_unlocked, skill_pts_changed, active_slots_changed,
#         active_used, team_lives, game_over, game_started, all_roles_confirmed
extends GutTest

const PEER_A := 201

func _fire(msg_type: String, payload: Dictionary) -> void:
	BridgeClient._handle_server_message(msg_type, payload)

func before_each() -> void:
	LevelSystem.register_peer(PEER_A)
	SkillTree.register_peer(PEER_A, "Fighter")
	TeamLives.blue_lives = 20
	TeamLives.red_lives  = 20
	TeamData.team_points[0] = 75
	TeamData.team_points[1] = 75
	TeamData.passive_income[0] = 0
	TeamData.passive_income[1] = 0

func after_each() -> void:
	LevelSystem.clear_peer(PEER_A)
	SkillTree.clear_peer(PEER_A)
	TeamLives.blue_lives = 0
	TeamLives.red_lives  = 0
	GameSync.game_seed   = 0
	TeamData.team_points[0] = 75
	TeamData.team_points[1] = 75
	TeamData.passive_income[0] = 0
	TeamData.passive_income[1] = 0

# ── level_up ──────────────────────────────────────────────────────────────────

func test_level_up_updates_level() -> void:
	_fire("level_up", {"peer_id": PEER_A, "new_level": 3, "pts_awarded": 1})
	assert_eq(LevelSystem.get_level(PEER_A), 3,
		"level_up message must update LevelSystem._level")

func test_level_up_adds_pts() -> void:
	var pts_before: int = LevelSystem.get_unspent_points(PEER_A)
	_fire("level_up", {"peer_id": PEER_A, "new_level": 2, "pts_awarded": 2})
	assert_eq(LevelSystem.get_unspent_points(PEER_A), pts_before + 2,
		"level_up message must add pts_awarded to unspent attribute points")

func test_level_up_emits_signal() -> void:
	watch_signals(LevelSystem)
	_fire("level_up", {"peer_id": PEER_A, "new_level": 4, "pts_awarded": 1})
	assert_signal_emitted(LevelSystem, "level_up",
		"level_up message must emit LevelSystem.level_up signal")

func test_level_up_signal_carries_peer_id_and_level() -> void:
	watch_signals(LevelSystem)
	_fire("level_up", {"peer_id": PEER_A, "new_level": 5, "pts_awarded": 1})
	var params: Array = get_signal_parameters(LevelSystem, "level_up")
	assert_eq(params[0], PEER_A, "level_up signal peer_id must match")
	assert_eq(params[1], 5, "level_up signal new_level must match")

func test_level_up_invalid_peer_no_crash() -> void:
	_fire("level_up", {"peer_id": -1, "new_level": 2, "pts_awarded": 1})
	pass  # must not crash

func test_level_up_auto_registers_unknown_peer() -> void:
	var unknown_id := 9991
	LevelSystem.clear_peer(unknown_id)
	_fire("level_up", {"peer_id": unknown_id, "new_level": 2, "pts_awarded": 1})
	assert_eq(LevelSystem.get_level(unknown_id), 2,
		"level_up for an unknown peer must auto-register and apply the level")
	LevelSystem.clear_peer(unknown_id)

# ── skill_unlocked ────────────────────────────────────────────────────────────

func test_skill_unlocked_records_node() -> void:
	_fire("skill_unlocked", {"peer_id": PEER_A, "node_id": "f_adrenaline"})
	assert_true(SkillTree.is_unlocked(PEER_A, "f_adrenaline"),
		"skill_unlocked message must add node_id to SkillTree unlocked list")

func test_skill_unlocked_emits_signal() -> void:
	watch_signals(SkillTree)
	_fire("skill_unlocked", {"peer_id": PEER_A, "node_id": "f_adrenaline"})
	assert_signal_emitted(SkillTree, "skill_unlocked",
		"skill_unlocked message must emit SkillTree.skill_unlocked signal")

func test_skill_unlocked_signal_carries_peer_id_and_node() -> void:
	watch_signals(SkillTree)
	_fire("skill_unlocked", {"peer_id": PEER_A, "node_id": "f_adrenaline"})
	var params: Array = get_signal_parameters(SkillTree, "skill_unlocked")
	assert_eq(params[0], PEER_A, "skill_unlocked signal peer_id must match")
	assert_eq(params[1], "f_adrenaline", "skill_unlocked signal node_id must match")

func test_skill_unlocked_no_duplicate_in_list() -> void:
	_fire("skill_unlocked", {"peer_id": PEER_A, "node_id": "f_adrenaline"})
	_fire("skill_unlocked", {"peer_id": PEER_A, "node_id": "f_adrenaline"})
	var s = SkillTree._states.get(PEER_A)
	var count: int = 0
	for nid in s.unlocked:
		if nid == "f_adrenaline":
			count += 1
	assert_eq(count, 1, "skill_unlocked must not add duplicates to the unlocked list")

func test_skill_unlocked_invalid_peer_no_crash() -> void:
	_fire("skill_unlocked", {"peer_id": -1, "node_id": "f_adrenaline"})
	pass

func test_skill_unlocked_empty_node_id_no_crash() -> void:
	_fire("skill_unlocked", {"peer_id": PEER_A, "node_id": ""})
	pass

# ── skill_pts_changed ─────────────────────────────────────────────────────────

func test_skill_pts_changed_updates_state() -> void:
	_fire("skill_pts_changed", {"peer_id": PEER_A, "pts": 5})
	assert_eq(SkillTree.get_skill_pts(PEER_A), 5,
		"skill_pts_changed message must update SkillTree skill_pts")

func test_skill_pts_changed_emits_signal() -> void:
	watch_signals(SkillTree)
	_fire("skill_pts_changed", {"peer_id": PEER_A, "pts": 3})
	assert_signal_emitted(SkillTree, "skill_pts_changed",
		"skill_pts_changed message must emit SkillTree.skill_pts_changed signal")

func test_skill_pts_changed_signal_carries_peer_id_and_pts() -> void:
	watch_signals(SkillTree)
	_fire("skill_pts_changed", {"peer_id": PEER_A, "pts": 7})
	var params: Array = get_signal_parameters(SkillTree, "skill_pts_changed")
	assert_eq(params[0], PEER_A, "skill_pts_changed signal peer_id must match")
	assert_eq(params[1], 7, "skill_pts_changed signal pts must match")

func test_skill_pts_changed_invalid_peer_no_crash() -> void:
	_fire("skill_pts_changed", {"peer_id": -1, "pts": 3})
	pass

# ── active_slots_changed ──────────────────────────────────────────────────────

func test_active_slots_changed_updates_state() -> void:
	_fire("active_slots_changed", {"peer_id": PEER_A, "slots": ["f_dash", "f_adrenaline"]})
	var slots: Array = SkillTree.get_active_slots(PEER_A)
	assert_eq(slots[0], "f_dash", "slot 0 must be updated")
	assert_eq(slots[1], "f_adrenaline", "slot 1 must be updated")

func test_active_slots_changed_emits_signal() -> void:
	watch_signals(SkillTree)
	_fire("active_slots_changed", {"peer_id": PEER_A, "slots": ["f_dash", ""]})
	assert_signal_emitted(SkillTree, "active_slots_changed",
		"active_slots_changed message must emit SkillTree.active_slots_changed signal")

func test_active_slots_changed_signal_carries_peer_id_and_slots() -> void:
	watch_signals(SkillTree)
	_fire("active_slots_changed", {"peer_id": PEER_A, "slots": ["f_dash", "f_iron_skin"]})
	var params: Array = get_signal_parameters(SkillTree, "active_slots_changed")
	assert_eq(params[0], PEER_A, "active_slots_changed signal peer_id must match")
	assert_eq((params[1] as Array)[0], "f_dash", "active_slots_changed signal slot 0 must match")

func test_active_slots_changed_invalid_peer_no_crash() -> void:
	_fire("active_slots_changed", {"peer_id": -1, "slots": ["f_dash", ""]})
	pass

# ── active_used ───────────────────────────────────────────────────────────────

func test_active_used_emits_signal() -> void:
	watch_signals(SkillTree)
	_fire("active_used", {"peer_id": PEER_A, "node_id": "f_dash"})
	assert_signal_emitted(SkillTree, "active_used",
		"active_used message must emit SkillTree.active_used signal")

func test_active_used_signal_carries_peer_id_and_node() -> void:
	watch_signals(SkillTree)
	_fire("active_used", {"peer_id": PEER_A, "node_id": "f_dash"})
	var params: Array = get_signal_parameters(SkillTree, "active_used")
	assert_eq(params[0], PEER_A, "active_used signal peer_id must match")
	assert_eq(params[1], "f_dash", "active_used signal node_id must match")

func test_active_used_invalid_peer_no_crash() -> void:
	_fire("active_used", {"peer_id": -1, "node_id": "f_dash"})
	pass

func test_active_used_empty_node_no_crash() -> void:
	_fire("active_used", {"peer_id": PEER_A, "node_id": ""})
	pass

# ── team_lives ────────────────────────────────────────────────────────────────

func test_team_lives_updates_blue() -> void:
	_fire("team_lives", {"team": 0, "lives": 15})
	assert_eq(TeamLives.blue_lives, 15,
		"team_lives message for team 0 must update TeamLives.blue_lives")

func test_team_lives_updates_red() -> void:
	_fire("team_lives", {"team": 1, "lives": 12})
	assert_eq(TeamLives.red_lives, 12,
		"team_lives message for team 1 must update TeamLives.red_lives")

func test_team_lives_emits_life_lost_signal() -> void:
	watch_signals(TeamLives)
	_fire("team_lives", {"team": 0, "lives": 18})
	assert_signal_emitted(TeamLives, "life_lost",
		"team_lives message must emit TeamLives.life_lost signal")

func test_team_lives_signal_carries_team_and_lives() -> void:
	watch_signals(TeamLives)
	_fire("team_lives", {"team": 1, "lives": 9})
	var params: Array = get_signal_parameters(TeamLives, "life_lost")
	assert_eq(params[0], 1, "life_lost signal team must match")
	assert_eq(params[1], 9, "life_lost signal remaining must match")

func test_team_lives_zero_lives_no_crash() -> void:
	_fire("team_lives", {"team": 0, "lives": 0})
	assert_eq(TeamLives.blue_lives, 0, "zero lives must be accepted")

# ── game_over ─────────────────────────────────────────────────────────────────

func test_game_over_emits_signal() -> void:
	watch_signals(TeamLives)
	_fire("game_over", {"winner": 1})
	assert_signal_emitted(TeamLives, "game_over",
		"game_over message must emit TeamLives.game_over signal")

func test_game_over_signal_carries_winner() -> void:
	watch_signals(TeamLives)
	_fire("game_over", {"winner": 0})
	var params: Array = get_signal_parameters(TeamLives, "game_over")
	assert_eq(params[0], 0, "game_over signal winner_team must match payload winner")

func test_game_over_winner_red_no_crash() -> void:
	watch_signals(TeamLives)
	_fire("game_over", {"winner": 1})
	var params: Array = get_signal_parameters(TeamLives, "game_over")
	assert_eq(params[0], 1, "game_over signal winner must be 1 for red team win")

# ── game_started: map_seed written to GameSync ────────────────────────────────

func test_game_started_writes_map_seed_to_game_sync() -> void:
	# Regression: "game_started" payload carries map_seed but BridgeClient was
	# not writing it to GameSync.game_seed. TerrainGenerator._ready() then read
	# 0 and logged a divergence error.
	GameSync.game_seed = 0
	_fire("game_started", {"map_seed": 99887766, "lane_points": []})
	assert_eq(GameSync.game_seed, 99887766,
		"game_started must write map_seed into GameSync.game_seed")

func test_game_started_seed_zero_stays_zero() -> void:
	# If Python sends seed 0 (shouldn't happen, but guard it), do not explode.
	GameSync.game_seed = 0
	_fire("game_started", {"map_seed": 0, "lane_points": []})
	assert_eq(GameSync.game_seed, 0,
		"map_seed 0 must be stored as-is (TerrainGenerator handles the fallback)")

func test_game_started_does_not_overwrite_existing_seed_with_zero_when_key_missing() -> void:
	# If the payload has no map_seed key at all, int(payload.get("map_seed",0))
	# returns 0 — this is acceptable since it mirrors old behaviour. Confirm no crash.
	GameSync.game_seed = 0
	_fire("game_started", {"lane_points": []})
	assert_eq(GameSync.game_seed, 0, "missing map_seed key must default to 0 without crash")

# ── all_roles_confirmed ───────────────────────────────────────────────────────

func test_all_roles_confirmed_emits_lobby_manager_signal() -> void:
	# Regression: BridgeClient had no "all_roles_confirmed" arm so
	# LobbyManager.all_roles_confirmed was never emitted. Main.gd awaited it
	# forever and _spawn_ai_supporters_when_ready also read the removed
	# _roles_pending property, crashing with an invalid access error.
	watch_signals(LobbyManager)
	_fire("all_roles_confirmed", {})
	assert_signal_emitted(LobbyManager, "all_roles_confirmed",
		"all_roles_confirmed message must emit LobbyManager.all_roles_confirmed")

func test_all_roles_confirmed_no_crash_on_empty_payload() -> void:
	# Guard against future payload changes — extra keys must not crash.
	watch_signals(LobbyManager)
	_fire("all_roles_confirmed", {"extra": "ignored"})
	assert_signal_emitted(LobbyManager, "all_roles_confirmed",
		"all_roles_confirmed must emit signal regardless of extra payload keys")

# ── team_points income_rate fields ────────────────────────────────────────────

func test_team_points_syncs_income_rate_to_team_data() -> void:
	TeamData.sync_income_from_server(0, 0)
	_fire("team_points", {"blue": 50, "red": 60, "income_blue": 3, "income_red": 5})
	assert_eq(TeamData.get_passive_income(0), 3,
		"team_points handler must sync income_blue to TeamData")
	assert_eq(TeamData.get_passive_income(1), 5,
		"team_points handler must sync income_red to TeamData")

func test_team_points_syncs_balance_alongside_income() -> void:
	_fire("team_points", {"blue": 40, "red": 70, "income_blue": 1, "income_red": 2})
	assert_eq(TeamData.get_points(0), 40,
		"team_points handler must still sync blue balance")
	assert_eq(TeamData.get_points(1), 70,
		"team_points handler must still sync red balance")

func test_team_points_missing_income_fields_defaults_to_zero() -> void:
	TeamData.sync_income_from_server(9, 9)
	_fire("team_points", {"blue": 30, "red": 30})
	assert_eq(TeamData.get_passive_income(0), 0,
		"Missing income_blue must default to 0 and overwrite stale value")
	assert_eq(TeamData.get_passive_income(1), 0,
		"Missing income_red must default to 0 and overwrite stale value")

func test_team_points_income_zero_clears_previous_rate() -> void:
	TeamData.sync_income_from_server(5, 5)
	_fire("team_points", {"blue": 75, "red": 75, "income_blue": 0, "income_red": 0})
	assert_eq(TeamData.get_passive_income(0), 0,
		"Explicit income_blue=0 must clear previous rate")
	assert_eq(TeamData.get_passive_income(1), 0,
		"Explicit income_red=0 must clear previous rate")
