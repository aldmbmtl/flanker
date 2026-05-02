extends GutTest
# test_fighter_skills.gd — unit tests for FighterSkills active ability handlers.
# Tests are server-authoritative (Tier 1 / OfflineMultiplayerPeer).
#
# Strategy: construct a fake Main node with fake FPSPlayer_* children so
# FighterSkills._get_player() resolves correctly without a full game scene.

const FighterSkills := preload("res://scripts/skills/FighterSkills.gd")

const PEER_ID  := 10
const ALLY_ID  := 11
const ENEMY_ID := 12

# ── Fake player inner class ───────────────────────────────────────────────────

class FakePlayer extends CharacterBody3D:
	var hp: float = 100.0
	var max_hp: float = 100.0
	var team: int = 0
	var healed: float = 0.0

	func heal(amount: float) -> void:
		healed += amount
		hp = minf(hp + amount, max_hp)

	func _get_max_hp() -> float:
		return max_hp

# ── Scene setup helpers ───────────────────────────────────────────────────────

var _main: Node
var _caster: FakePlayer
var _ally: FakePlayer

func _make_player(peer_id: int, team_id: int, pos: Vector3 = Vector3.ZERO) -> FakePlayer:
	var p := FakePlayer.new()
	p.name = "FPSPlayer_%d" % peer_id
	_main.add_child(p)
	p.global_position = pos
	GameSync.set_player_team(peer_id, team_id)
	return p

func before_each() -> void:
	# Remove any existing Main node from prior tests
	var old_main: Node = get_tree().root.get_node_or_null("Main")
	if old_main != null:
		old_main.free()
	_main = Node.new()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	GameSync.reset()
	_caster = _make_player(PEER_ID, 0, Vector3.ZERO)

func after_each() -> void:
	if is_instance_valid(_main):
		_main.free()
	GameSync.reset()

# ── f_adrenaline ──────────────────────────────────────────────────────────────

func test_adrenaline_heals_caster() -> void:
	GameSync.set_player_health(PEER_ID, 50.0)
	FighterSkills.execute("f_adrenaline", PEER_ID)
	assert_almost_eq(GameSync.get_player_health(PEER_ID),
		50.0 + FighterSkills.ADRENALINE_HEAL, 0.01)

func test_adrenaline_caps_at_max_hp() -> void:
	GameSync.set_player_health(PEER_ID, GameSync.PLAYER_MAX_HP - 10.0)
	FighterSkills.execute("f_adrenaline", PEER_ID)
	assert_almost_eq(GameSync.get_player_health(PEER_ID), GameSync.PLAYER_MAX_HP, 0.01)

func test_adrenaline_no_crash_with_no_player() -> void:
	# Execute for an unregistered peer — should silently no-op.
	# Assert the known-registered caster was not touched.
	var hp_before: float = _caster.hp
	FighterSkills.execute("f_adrenaline", 999)
	assert_almost_eq(_caster.hp, hp_before, 0.01,
		"Unregistered peer must not mutate any existing player's HP")

# ── f_iron_skin ───────────────────────────────────────────────────────────────

func test_iron_skin_sets_shield_meta() -> void:
	FighterSkills.execute("f_iron_skin", PEER_ID)
	assert_true(_caster.has_meta("shield_hp"))
	assert_almost_eq(float(_caster.get_meta("shield_hp")), FighterSkills.IRON_SKIN_HP, 0.01)

func test_iron_skin_sets_shield_timer_meta() -> void:
	FighterSkills.execute("f_iron_skin", PEER_ID)
	assert_true(_caster.has_meta("shield_timer"))
	assert_almost_eq(float(_caster.get_meta("shield_timer")), FighterSkills.IRON_SKIN_DURATION, 0.01)

func test_iron_skin_absorbs_damage_before_hp() -> void:
	FighterSkills.execute("f_iron_skin", PEER_ID)
	# Simulate take_damage shield absorption (mirrors FPSController logic)
	var shield: float = float(_caster.get_meta("shield_hp"))
	var damage: float = 20.0
	var absorbed: float = minf(damage, shield)
	shield -= absorbed
	damage -= absorbed
	_caster.hp -= damage
	_caster.set_meta("shield_hp", shield)
	assert_almost_eq(_caster.hp, 100.0, 0.01)  # HP untouched
	assert_almost_eq(shield, FighterSkills.IRON_SKIN_HP - 20.0, 0.01)

# ── f_dash ────────────────────────────────────────────────────────────────────

func test_dash_sets_target_forward() -> void:
	_caster.global_position = Vector3.ZERO
	# Default basis: -Z is forward. Target should be ~DASH_DISTANCE units away.
	FighterSkills.execute("f_dash", PEER_ID)
	assert_true(_caster.has_meta("dash_target"), "dash_target meta should be set")
	var target: Vector3 = _caster.get_meta("dash_target") as Vector3
	assert_almost_eq(target.length(), FighterSkills.DASH_DISTANCE, 0.1)

func test_dash_stays_horizontal() -> void:
	_caster.global_position = Vector3.ZERO
	FighterSkills.execute("f_dash", PEER_ID)
	var target: Vector3 = _caster.get_meta("dash_target") as Vector3
	assert_almost_eq(target.y, 0.0, 0.01)

func test_dash_no_crash_with_no_player() -> void:
	# Unregistered peer — _resolve returns null, function returns early.
	# Assert the caster has no dash meta set (no side-effect bleed).
	FighterSkills.execute("f_dash", 9999)
	assert_false(_caster.has_meta("dash_origin"),
		"Unregistered peer must not set dash meta on any existing player")

# ── f_rapid_fire ──────────────────────────────────────────────────────────────

func test_rapid_fire_sets_timer_meta() -> void:
	FighterSkills.execute("f_rapid_fire", PEER_ID)
	assert_true(_caster.has_meta("rapid_fire_timer"))
	assert_almost_eq(float(_caster.get_meta("rapid_fire_timer")), FighterSkills.RAPID_FIRE_DURATION, 0.01)

func test_rapid_fire_sets_weapon_meta() -> void:
	FighterSkills.execute("f_rapid_fire", PEER_ID)
	# weapon meta should be present (may be "" if caster has no weapon method)
	assert_true(_caster.has_meta("rapid_fire_weapon"))

# ── f_field_medic ─────────────────────────────────────────────────────────────

func test_field_medic_heals_caster() -> void:
	GameSync.set_player_health(PEER_ID, 50.0)
	FighterSkills.execute("f_field_medic", PEER_ID)
	assert_almost_eq(GameSync.get_player_health(PEER_ID),
		50.0 + FighterSkills.FIELD_MEDIC_HEAL, 0.01)

func test_field_medic_heals_nearby_ally() -> void:
	_ally = _make_player(ALLY_ID, 0, Vector3(1.0, 0.0, 0.0))  # same team, 1 m away
	GameSync.set_player_health(ALLY_ID, 60.0)
	FighterSkills.execute("f_field_medic", PEER_ID)
	assert_almost_eq(GameSync.get_player_health(ALLY_ID),
		60.0 + FighterSkills.FIELD_MEDIC_HEAL, 0.01)

func test_field_medic_does_not_heal_distant_ally() -> void:
	_ally = _make_player(ALLY_ID, 0, Vector3(100.0, 0.0, 0.0))  # out of range
	_ally.hp = 60.0
	_ally.healed = 0.0
	FighterSkills.execute("f_field_medic", PEER_ID)
	assert_almost_eq(_ally.healed, 0.0, 0.01)

func test_field_medic_does_not_heal_enemy() -> void:
	var enemy: FakePlayer = _make_player(ENEMY_ID, 1, Vector3(1.0, 0.0, 0.0))  # enemy team
	enemy.hp = 60.0
	enemy.healed = 0.0
	FighterSkills.execute("f_field_medic", PEER_ID)
	assert_almost_eq(enemy.healed, 0.0, 0.01)

# ── f_rally_cry ───────────────────────────────────────────────────────────────

func test_rally_cry_sets_speed_bonus_on_nearby_ally() -> void:
	_ally = _make_player(ALLY_ID, 0, Vector3(2.0, 0.0, 0.0))
	FighterSkills.execute("f_rally_cry", PEER_ID)
	assert_true(_ally.has_meta("rally_speed_bonus"))
	assert_almost_eq(float(_ally.get_meta("rally_speed_bonus")), FighterSkills.RALLY_CRY_BONUS, 0.001)

func test_rally_cry_sets_timer_on_nearby_ally() -> void:
	_ally = _make_player(ALLY_ID, 0, Vector3(2.0, 0.0, 0.0))
	FighterSkills.execute("f_rally_cry", PEER_ID)
	assert_true(_ally.has_meta("rally_cry_timer"))
	assert_almost_eq(float(_ally.get_meta("rally_cry_timer")), FighterSkills.RALLY_CRY_DURATION, 0.001)

func test_rally_cry_does_not_buff_distant_ally() -> void:
	_ally = _make_player(ALLY_ID, 0, Vector3(100.0, 0.0, 0.0))
	FighterSkills.execute("f_rally_cry", PEER_ID)
	assert_false(_ally.has_meta("rally_speed_bonus"))

func test_rally_cry_does_not_buff_enemy() -> void:
	var enemy: FakePlayer = _make_player(ENEMY_ID, 1, Vector3(2.0, 0.0, 0.0))
	FighterSkills.execute("f_rally_cry", PEER_ID)
	assert_false(enemy.has_meta("rally_speed_bonus"))

# ── f_rocket_barrage ─────────────────────────────────────────────────────────

func test_rocket_barrage_no_towers_no_crash() -> void:
	# No towers in scene → targets list is empty → returns before spawning.
	var children_before: int = _main.get_child_count()
	FighterSkills.execute("f_rocket_barrage", PEER_ID)
	assert_eq(_main.get_child_count(), children_before,
		"No rockets should be spawned when there are no enemy towers in range")

func test_rocket_barrage_skips_friendly_towers() -> void:
	# Add a friendly tower in range — must be skipped, no rockets spawned.
	var tower := StaticBody3D.new()
	tower.name   = "FriendlyTower"
	tower.set("team", 0)  # same team as caster
	_main.add_child(tower)
	tower.add_to_group("towers")
	var children_before: int = _main.get_child_count()
	FighterSkills.execute("f_rocket_barrage", PEER_ID)
	assert_eq(_main.get_child_count(), children_before,
		"Friendly tower must be skipped — no rockets spawned")

# ── f_deploy_mg (singleplayer path) ──────────────────────────────────────────

func test_deploy_mg_singleplayer_spawns_node() -> void:
	# Force singleplayer path by temporarily clearing the multiplayer peer.
	# OfflineMultiplayerPeer makes has_multiplayer_peer() return true, which
	# would send the multiplayer RPC path instead of the singleplayer branch.
	var mg_scene: PackedScene = load("res://scenes/towers/MachineGunTower.tscn")
	if mg_scene == null:
		push_warning("MachineGunTower.tscn not loadable — skipping")
		return
	multiplayer.set_multiplayer_peer(null)
	var children_before: int = _main.get_child_count()
	FighterSkills.execute("f_deploy_mg", PEER_ID)
	# Restore OfflineMultiplayerPeer so subsequent tests run correctly.
	multiplayer.set_multiplayer_peer(OfflineMultiplayerPeer.new())
	assert_gt(_main.get_child_count(), children_before,
		"Singleplayer deploy_mg must add a MachineGun node to Main")

# ── Regression: heal delivery via LobbyManager.heal_player_broadcast ─────────
# Previously all heal calls used player.heal() directly — failed silently on
# puppet nodes (BasePlayer). Fixed: use heal_player_broadcast which updates
# GameSync.player_healths server-authoritatively.

func test_adrenaline_updates_gamesync_health() -> void:
	GameSync.set_player_health(PEER_ID, 50.0)
	FighterSkills.execute("f_adrenaline", PEER_ID)
	var new_hp: float = GameSync.get_player_health(PEER_ID)
	assert_almost_eq(new_hp, 50.0 + FighterSkills.ADRENALINE_HEAL, 0.01,
		"Adrenaline must update GameSync HP via heal_player_broadcast")

func test_field_medic_updates_gamesync_health_for_caster() -> void:
	GameSync.set_player_health(PEER_ID, 50.0)
	FighterSkills.execute("f_field_medic", PEER_ID)
	var new_hp: float = GameSync.get_player_health(PEER_ID)
	assert_almost_eq(new_hp, 50.0 + FighterSkills.FIELD_MEDIC_HEAL, 0.01,
		"Field Medic must update caster GameSync HP via heal_player_broadcast")

func test_field_medic_updates_gamesync_health_for_nearby_ally() -> void:
	_ally = _make_player(ALLY_ID, 0, Vector3(1.0, 0.0, 0.0))
	GameSync.set_player_health(ALLY_ID, 60.0)
	FighterSkills.execute("f_field_medic", PEER_ID)
	var new_hp: float = GameSync.get_player_health(ALLY_ID)
	assert_almost_eq(new_hp, 60.0 + FighterSkills.FIELD_MEDIC_HEAL, 0.01,
		"Field Medic must update ally GameSync HP via heal_player_broadcast")

func test_revive_pulse_fully_heals_caster_via_gamesync() -> void:
	GameSync.set_player_health(PEER_ID, 30.0)
	FighterSkills.execute("f_revive_pulse", PEER_ID)
	var new_hp: float = GameSync.get_player_health(PEER_ID)
	assert_almost_eq(new_hp, GameSync.PLAYER_MAX_HP, 0.01,
		"Revive Pulse must fully heal caster in GameSync")

func test_revive_pulse_heals_nearby_ally_via_gamesync() -> void:
	_ally = _make_player(ALLY_ID, 0, Vector3(1.0, 0.0, 0.0))
	GameSync.set_player_health(ALLY_ID, 40.0)
	FighterSkills.execute("f_revive_pulse", PEER_ID)
	var new_hp: float = GameSync.get_player_health(ALLY_ID)
	assert_almost_eq(new_hp, 40.0 + FighterSkills.REVIVE_PULSE_ALLY, 0.01,
		"Revive Pulse must heal nearby ally in GameSync")

# ── Regression: Rapid Fire reads weapon type from GameSync ────────────────────
# Previously called get_current_weapon_type() on the server-side node — puppet
# nodes don't have this method. Fixed: read GameSync.player_weapon_type[peer_id].

func test_rapid_fire_weapon_meta_matches_gamesync_weapon_type() -> void:
	GameSync.player_weapon_type[PEER_ID] = "rifle"
	FighterSkills.execute("f_rapid_fire", PEER_ID)
	assert_eq(str(_caster.get_meta("rapid_fire_weapon")), "rifle",
		"rapid_fire_weapon meta must come from GameSync.player_weapon_type")

func test_rapid_fire_weapon_meta_empty_when_no_gamesync_entry() -> void:
	GameSync.player_weapon_type.erase(PEER_ID)
	FighterSkills.execute("f_rapid_fire", PEER_ID)
	assert_eq(str(_caster.get_meta("rapid_fire_weapon")), "",
		"rapid_fire_weapon meta must be empty string when no GameSync entry")

# ── Regression: Iron Skin sets GameSync shield state ─────────────────────────
# Previously only set metas on the local node. damage_player() never saw the
# shield, so incoming damage was not absorbed. Fixed: GameSync.set_player_shield
# is called; damage_player drains shield before HP.

func test_iron_skin_sets_gamesync_shield_hp() -> void:
	FighterSkills.execute("f_iron_skin", PEER_ID)
	assert_almost_eq(GameSync.get_player_shield_hp(PEER_ID), FighterSkills.IRON_SKIN_HP, 0.01,
		"Iron Skin must store shield HP in GameSync")

func test_damage_player_drains_shield_before_hp() -> void:
	GameSync.set_player_health(PEER_ID, 100.0)
	GameSync.set_player_shield(PEER_ID, 60.0, 8.0)
	GameSync.damage_player(PEER_ID, 30.0, 1)  # enemy team
	assert_almost_eq(GameSync.get_player_health(PEER_ID), 100.0, 0.01,
		"HP must be untouched when damage is fully absorbed by shield")
	assert_almost_eq(GameSync.get_player_shield_hp(PEER_ID), 30.0, 0.01,
		"Shield must be reduced by the absorbed amount")

func test_damage_player_bleeds_through_shield_to_hp() -> void:
	GameSync.set_player_health(PEER_ID, 100.0)
	GameSync.set_player_shield(PEER_ID, 20.0, 8.0)
	GameSync.damage_player(PEER_ID, 50.0, 1)
	assert_almost_eq(GameSync.get_player_health(PEER_ID), 70.0, 0.01,
		"Damage exceeding shield must bleed through to HP")
	assert_almost_eq(GameSync.get_player_shield_hp(PEER_ID), 0.0, 0.01,
		"Shield must be exhausted after bleed-through")

func test_damage_player_clears_shield_when_exhausted() -> void:
	GameSync.set_player_health(PEER_ID, 100.0)
	GameSync.set_player_shield(PEER_ID, 20.0, 8.0)
	GameSync.damage_player(PEER_ID, 20.0, 1)
	assert_false(GameSync.player_shield_hp.has(PEER_ID),
		"Shield entry must be cleared from dict when fully depleted")

# ── Regression: Rally Cry applies buff to caster ─────────────────────────────
# Previously get_ally_players() excluded the caster and caster was never given
# the speed bonus. Fixed: explicit self-apply before iterating allies.

func test_rally_cry_sets_speed_bonus_on_caster() -> void:
	FighterSkills.execute("f_rally_cry", PEER_ID)
	assert_true(_caster.has_meta("rally_speed_bonus"),
		"Rally Cry must apply speed bonus to the caster (self)")
	assert_almost_eq(float(_caster.get_meta("rally_speed_bonus")),
		FighterSkills.RALLY_CRY_BONUS, 0.001)

func test_rally_cry_sets_timer_on_caster() -> void:
	FighterSkills.execute("f_rally_cry", PEER_ID)
	assert_true(_caster.has_meta("rally_cry_timer"),
		"Rally Cry must set timer on the caster")
	assert_almost_eq(float(_caster.get_meta("rally_cry_timer")),
		FighterSkills.RALLY_CRY_DURATION, 0.001)
