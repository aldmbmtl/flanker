extends Node
# FighterSkills — executes active ability effects for Fighter players.
# All functions are server-authoritative; called by SkillTree.use_active_local().

# ── Constants ─────────────────────────────────────────────────────────────────

const DASH_DISTANCE       := 5.0     # metres moved forward
const DASH_DURATION       := 0.5     # seconds for dash animation
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

# ── Helpers (delegated to SkillTree shared methods) ─────────────────────

## Returns the player node for peer_id, or null if not found / not in tree.
## All skill functions call this instead of repeating the null-guard inline.
static func _resolve(peer_id: int) -> Node:
	return SkillTree.get_player(peer_id)

# ── Guardian branch ───────────────────────────────────────────────────────────

static func _field_medic(peer_id: int) -> void:
	var caster: Node = _resolve(peer_id)
	if caster == null:
		return
	var team: int = SkillTree.get_player_team(peer_id)
	# Heal self
	if caster.has_method("heal"):
		caster.heal(FIELD_MEDIC_HEAL)
	# Heal nearby allies
	for ally in SkillTree.get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= FIELD_MEDIC_RANGE and ally.has_method("heal"):
			ally.heal(FIELD_MEDIC_HEAL)

static func _rally_cry(peer_id: int) -> void:
	var caster: Node = _resolve(peer_id)
	if caster == null:
		return
	var team: int = SkillTree.get_player_team(peer_id)
	var _mp: MultiplayerAPI = Engine.get_main_loop().root.multiplayer
	var is_mp_server: bool = _mp.has_multiplayer_peer() and _mp.is_server()
	for ally in SkillTree.get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= RALLY_CRY_RANGE:
			ally.set_meta("rally_speed_bonus", RALLY_CRY_BONUS)
			ally.set_meta("rally_cry_timer", RALLY_CRY_DURATION)
			# Deliver to the owning client of this ally.
			if is_mp_server:
				var ally_peer_id: int = _peer_id_from_node(ally)
				if ally_peer_id > 0 and ally_peer_id != _mp.get_unique_id() \
						and _mp.get_peers().has(ally_peer_id):
					SkillTree.apply_rally_cry.rpc_id(ally_peer_id, RALLY_CRY_BONUS, RALLY_CRY_DURATION)

## Extract peer_id from a node named "FPSPlayer_<id>".
static func _peer_id_from_node(node: Node) -> int:
	var n: String = node.name
	var prefix: String = "FPSPlayer_"
	if not n.begins_with(prefix):
		return -1
	var id_str: String = n.substr(prefix.length())
	if not id_str.is_valid_int():
		return -1
	return int(id_str)

static func _revive_pulse(peer_id: int) -> void:
	var caster: Node = _resolve(peer_id)
	if caster == null:
		return
	var team: int = SkillTree.get_player_team(peer_id)
	# Full self-heal
	if caster.has_method("heal") and caster.has_method("_get_max_hp"):
		caster.heal(caster._get_max_hp())
	elif caster.has_method("heal"):
		caster.heal(999.0)
	# Heal allies within range
	for ally in SkillTree.get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= REVIVE_PULSE_RANGE and ally.has_method("heal"):
			ally.heal(REVIVE_PULSE_ALLY)

# ── DPS branch ────────────────────────────────────────────────────────────────

static func _dash(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null or not (player is CharacterBody3D):
		return
	var cb := player as CharacterBody3D
	# Use movement direction if moving, else fall back to facing direction
	var forward: Vector3
	var horiz_vel: Vector3 = Vector3(cb.velocity.x, 0.0, cb.velocity.z)
	if horiz_vel.length_squared() > 0.01:
		forward = horiz_vel.normalized()
	else:
		forward = -cb.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.001:
			return
		forward = forward.normalized()

	# Play dash sound
	if SoundManager != null:
		SoundManager.play_3d(
			"res://assets/kenney_impact-sounds/Audio/impactMetal_light_002.ogg",
			cb.global_position, 0.0, randf_range(0.9, 1.1))

	# VFX — particle trail attached to player so it follows during the slide
	var effect: GPUParticles3D = GPUParticles3D.new()
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 60.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0.0, -4.0, 0.0)
	pm.scale_min = 0.08
	pm.scale_max = 0.25
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.2, 0.2)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.5, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	effect.draw_pass_1 = mesh
	effect.process_material = pm
	effect.amount = 40
	effect.lifetime = 0.4
	effect.one_shot = true
	effect.emitting = true
	effect.position = Vector3(0.0, 0.5, 0.0)
	cb.add_child(effect)

	# Store dash state on the player — FPSController reads these each physics frame
	# dash_origin / dash_target drive lerp-based movement in _physics_process
	var target: Vector3 = cb.global_position + forward.normalized() * DASH_DISTANCE
	cb.set_meta("dash_origin",    cb.global_position)
	cb.set_meta("dash_target",    target)
	cb.set_meta("dash_elapsed",   0.0)
	cb.set_meta("dash_duration",  DASH_DURATION)
	cb.set_meta("dash_effect",    effect)

	# Deliver dash metas to the owning client so FPSController can read them locally.
	var _mp: MultiplayerAPI = Engine.get_main_loop().root.multiplayer
	if _mp.has_multiplayer_peer() and _mp.is_server() and peer_id != _mp.get_unique_id() \
			and _mp.get_peers().has(peer_id):
		SkillTree.apply_dash.rpc_id(peer_id, cb.global_position, target, 0.0, DASH_DURATION)

	# Auto-cleanup timer (failsafe if the player dies mid-dash)
	# Captures only peer_id (int) — no Node references — to avoid freed-capture errors.
	var cleanup_timer: SceneTreeTimer = Engine.get_main_loop().create_timer(DASH_DURATION + 0.1)
	cleanup_timer.timeout.connect(func() -> void:
		var p: Node = SkillTree.get_player(peer_id)
		if p != null and is_instance_valid(p):
			if p.has_meta("dash_effect"):
				var eff: Node = p.get_meta("dash_effect") as Node
				if is_instance_valid(eff):
					eff.queue_free()
			for key in ["dash_origin", "dash_target", "dash_elapsed", "dash_duration", "dash_effect"]:
				if p.has_meta(key):
					p.remove_meta(key))

static func _rapid_fire(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null:
		return
	# Store current weapon type so FPSController can scope the boost
	var weapon_type: String = ""
	if player.has_method("get_current_weapon_type"):
		weapon_type = player.get_current_weapon_type()
	player.set_meta("rapid_fire_timer",  RAPID_FIRE_DURATION)
	player.set_meta("rapid_fire_weapon", weapon_type)
	# Deliver to owning client.
	var _mp: MultiplayerAPI = Engine.get_main_loop().root.multiplayer
	if _mp.has_multiplayer_peer() and _mp.is_server() and peer_id != _mp.get_unique_id() \
			and _mp.get_peers().has(peer_id):
		SkillTree.apply_rapid_fire.rpc_id(peer_id, RAPID_FIRE_DURATION, weapon_type)

static func _rocket_barrage(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null or not (player is Node3D):
		return
	var caster_pos: Vector3 = (player as Node3D).global_position
	var team: int = SkillTree.get_player_team(peer_id)

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
	var player: Node = _resolve(peer_id)
	if player == null:
		return
	if player.has_method("heal"):
		player.heal(ADRENALINE_HEAL)

static func _iron_skin(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null:
		return
	player.set_meta("shield_hp",    IRON_SKIN_HP)
	player.set_meta("shield_timer", IRON_SKIN_DURATION)
	# Deliver to owning client.
	var _mp: MultiplayerAPI = Engine.get_main_loop().root.multiplayer
	if _mp.has_multiplayer_peer() and _mp.is_server() and peer_id != _mp.get_unique_id() \
			and _mp.get_peers().has(peer_id):
		SkillTree.apply_iron_skin.rpc_id(peer_id, IRON_SKIN_HP, IRON_SKIN_DURATION)

static func _deploy_mg(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null or not (player is Node3D):
		return
	var team: int = SkillTree.get_player_team(peer_id)
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
		var main: Node = SkillTree.get_main()
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
