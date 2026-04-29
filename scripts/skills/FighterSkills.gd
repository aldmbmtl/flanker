extends Node
# FighterSkills — executes active ability effects for Fighter players.
# All functions are server-authoritative; called by SkillTree.use_active_local().

# ── Constants ─────────────────────────────────────────────────────────────────

const DASH_DISTANCE       := 5.0     # metres teleported forward
const ADRENALINE_HEAL     := 40.0
const FIELD_MEDIC_HEAL    := 25.0
const FIELD_MEDIC_RANGE   := 8.0
const RALLY_CRY_BONUS     := 0.20    # +20% speed
const RALLY_CRY_DURATION  := 5.0
const RALLY_CRY_RANGE     := 8.0
const REVIVE_PULSE_RANGE  := 10.0
const REVIVE_PULSE_ALLY   := 30.0
const RAPID_FIRE_MULT     := 3.0
const RAPID_FIRE_DURATION := 3.0
const BARRAGE_RANGE       := 50.0
const BARRAGE_MAX_TARGETS := 5
const IRON_SKIN_HP        := 60.0
const IRON_SKIN_DURATION  := 8.0
const DEPLOY_MG_LIFETIME  := 20.0

# ── Dispatch ──────────────────────────────────────────────────────────────────

static func execute(node_id: String, peer_id: int) -> void:
	match node_id:
		# Guardian branch
		"f_field_medic":    _field_medic(peer_id)
		"f_rally_cry":      _rally_cry(peer_id)
		"f_revive_pulse":   _revive_pulse(peer_id)
		# DPS branch
		"f_dash":           _dash(peer_id)
		"f_rapid_fire":     _rapid_fire(peer_id)
		"f_rocket_barrage": _rocket_barrage(peer_id)
		# Tank branch
		"f_adrenaline":     _adrenaline(peer_id)
		"f_iron_skin":      _iron_skin(peer_id)
		"f_deploy_mg":      _deploy_mg(peer_id)

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _get_main() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Main")

static func _get_player(peer_id: int) -> Node:
	var main: Node = _get_main()
	if main == null:
		return null
	return main.get_node_or_null("FPSPlayer_%d" % peer_id)

static func _get_player_team(peer_id: int) -> int:
	return GameSync.get_player_team(peer_id)

# Returns all FPSPlayer_* nodes in Main whose team matches ally_team,
# excluding the caster's own peer (handled separately when needed).
static func _get_ally_players(ally_team: int, exclude_id: int = -1) -> Array:
	var main: Node = _get_main()
	if main == null:
		return []
	var result: Array = []
	for child in main.get_children():
		if not child.name.begins_with("FPSPlayer_"):
			continue
		var id_str: String = child.name.substr("FPSPlayer_".length())
		if not id_str.is_valid_int():
			continue
		var pid: int = int(id_str)
		if pid == exclude_id:
			continue
		if GameSync.get_player_team(pid) == ally_team:
			result.append(child)
	return result

# ── Guardian branch ───────────────────────────────────────────────────────────

static func _field_medic(peer_id: int) -> void:
	var caster: Node = _get_player(peer_id)
	if caster == null:
		return
	var team: int = _get_player_team(peer_id)
	# Heal self
	if caster.has_method("heal"):
		caster.heal(FIELD_MEDIC_HEAL)
	# Heal nearby allies
	for ally in _get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= FIELD_MEDIC_RANGE and ally.has_method("heal"):
			ally.heal(FIELD_MEDIC_HEAL)

static func _rally_cry(peer_id: int) -> void:
	var caster: Node = _get_player(peer_id)
	if caster == null:
		return
	var team: int = _get_player_team(peer_id)
	for ally in _get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= RALLY_CRY_RANGE:
			ally.set_meta("rally_speed_bonus", RALLY_CRY_BONUS)
			ally.set_meta("rally_cry_timer", RALLY_CRY_DURATION)

static func _revive_pulse(peer_id: int) -> void:
	var caster: Node = _get_player(peer_id)
	if caster == null:
		return
	var team: int = _get_player_team(peer_id)
	# Full self-heal
	if caster.has_method("heal") and caster.has_method("_get_max_hp"):
		caster.heal(caster._get_max_hp())
	elif caster.has_method("heal"):
		caster.heal(999.0)
	# Heal allies within range
	for ally in _get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= REVIVE_PULSE_RANGE and ally.has_method("heal"):
			ally.heal(REVIVE_PULSE_ALLY)

# ── DPS branch ────────────────────────────────────────────────────────────────

static func _dash(peer_id: int) -> void:
	var player: Node = _get_player(peer_id)
	if player == null or not (player is CharacterBody3D):
		return
	var cb := player as CharacterBody3D
	var forward: Vector3 = -cb.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	cb.global_position += forward.normalized() * DASH_DISTANCE

static func _rapid_fire(peer_id: int) -> void:
	var player: Node = _get_player(peer_id)
	if player == null:
		return
	# Store current weapon type so FPSController can scope the boost
	var weapon_type: String = ""
	if player.has_method("get_current_weapon_type"):
		weapon_type = player.get_current_weapon_type()
	player.set_meta("rapid_fire_timer",  RAPID_FIRE_DURATION)
	player.set_meta("rapid_fire_weapon", weapon_type)

static func _rocket_barrage(peer_id: int) -> void:
	var player: Node = _get_player(peer_id)
	if player == null or not (player is Node3D):
		return
	var caster_pos: Vector3 = (player as Node3D).global_position
	var team: int = _get_player_team(peer_id)

	# Collect enemy towers within range
	var targets: Array = []
	for tower in Engine.get_main_loop().get_nodes_in_group("towers"):
		if not (tower is Node3D):
			continue
		var tower_team: int = tower.get("team") if tower.get("team") != null else -1
		if tower_team == team or tower_team == -1:
			continue  # skip friendly and unknown
		var dist: float = (tower as Node3D).global_position.distance_to(caster_pos)
		if dist <= BARRAGE_RANGE:
			targets.append(tower)

	if targets.is_empty():
		return  # no valid targets — no effect

	# Sort by distance, cap at max targets
	targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(caster_pos) < b.global_position.distance_to(caster_pos))
	if targets.size() > BARRAGE_MAX_TARGETS:
		targets = targets.slice(0, BARRAGE_MAX_TARGETS)

	var rocket_scene: PackedScene = load("res://scenes/projectiles/Rocket.tscn")
	if rocket_scene == null:
		return
	var scene_root: Node = Engine.get_main_loop().root.get_child(0)
	var fire_pos: Vector3 = caster_pos + Vector3(0.0, 1.2, 0.0)

	for target in targets:
		var rocket: Node3D = rocket_scene.instantiate()
		var dir: Vector3 = ((target as Node3D).global_position - fire_pos).normalized()
		rocket.set("damage",          80.0)
		rocket.set("source",          "f_rocket_barrage")
		rocket.set("shooter_team",    -1)   # player-fired, same as FPSController rockets
		rocket.set("shooter_peer_id", peer_id)
		rocket.set("velocity",        dir * 49.0)
		scene_root.add_child(rocket)
		rocket.global_position = fire_pos

# ── Tank branch ───────────────────────────────────────────────────────────────

static func _adrenaline(peer_id: int) -> void:
	var player: Node = _get_player(peer_id)
	if player == null:
		return
	if player.has_method("heal"):
		player.heal(ADRENALINE_HEAL)

static func _iron_skin(peer_id: int) -> void:
	var player: Node = _get_player(peer_id)
	if player == null:
		return
	player.set_meta("shield_hp",    IRON_SKIN_HP)
	player.set_meta("shield_timer", IRON_SKIN_DURATION)

static func _deploy_mg(peer_id: int) -> void:
	var player: Node = _get_player(peer_id)
	if player == null or not (player is Node3D):
		return
	var team: int = _get_player_team(peer_id)
	var pos: Vector3 = (player as Node3D).global_position

	var mp: MultiplayerAPI = Engine.get_main_loop().root.multiplayer
	if mp.has_multiplayer_peer() and mp.is_server():
		# Multiplayer: use spawn_item_visuals RPC so all clients see the turret
		var forced_name: String = "DeployMG_%d_%d" % [peer_id, Time.get_ticks_msec()]
		var build_sys: Node = Engine.get_main_loop().root.get_node_or_null("Main/BuildSystem")
		if build_sys != null and build_sys.has_method("spawn_item_local"):
			build_sys.spawn_item_local(pos, team, "machinegun", "", forced_name)
		LobbyManager.spawn_item_visuals.rpc(pos, team, "machinegun", "", forced_name)
		# Schedule despawn on all peers after lifetime
		var despawn_timer: SceneTreeTimer = Engine.get_main_loop().create_timer(DEPLOY_MG_LIFETIME)
		despawn_timer.timeout.connect(func() -> void:
			LobbyManager.despawn_tower.rpc(forced_name))
	else:
		# Singleplayer
		var mg_scene: PackedScene = load("res://scenes/towers/MachineGunTower.tscn")
		if mg_scene == null:
			return
		var mg: Node = mg_scene.instantiate()
		var main: Node = _get_main()
		if main == null:
			return
		main.add_child(mg)
		mg.global_position = pos
		if mg.has_method("setup"):
			mg.setup(team)
		# Schedule despawn
		var despawn_timer: SceneTreeTimer = Engine.get_main_loop().create_timer(DEPLOY_MG_LIFETIME)
		despawn_timer.timeout.connect(func() -> void:
			if is_instance_valid(mg):
				mg.queue_free())
