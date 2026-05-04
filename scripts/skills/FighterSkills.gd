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

## Heal a player by peer_id. Routes through Python bridge in multiplayer;
## falls back to direct GameSync update in singleplayer / test context.
static func _heal_player(peer_id: int, amount: float) -> void:
	if BridgeClient.is_connected_to_server():
		BridgeClient.send("heal_player", {"peer_id": peer_id, "amount": amount})
	else:
		var max_hp: float = GameSync.PLAYER_MAX_HP + LevelSystem.get_bonus_hp(peer_id)
		var cur_hp: float = GameSync.player_healths.get(peer_id, 0.0)
		GameSync.set_player_health(peer_id, minf(cur_hp + amount, max_hp))

# ── Guardian branch ───────────────────────────────────────────────────────────

static func _field_medic(peer_id: int) -> void:
	var caster: Node = _resolve(peer_id)
	if caster == null:
		return
	var team: int = SkillTree.get_player_team(peer_id)
	# Heal self.
	_heal_player(peer_id, FIELD_MEDIC_HEAL)
	# Heal nearby allies
	for ally in SkillTree.get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= FIELD_MEDIC_RANGE:
			var ally_pid: int = _peer_id_from_node(ally)
			if ally_pid > 0:
				_heal_player(ally_pid, FIELD_MEDIC_HEAL)

static func _rally_cry(peer_id: int) -> void:
	var caster: Node = _resolve(peer_id)
	if caster == null:
		return
	var team: int = SkillTree.get_player_team(peer_id)
	# Apply to caster first (get_ally_players excludes caster).
	caster.set_meta("rally_speed_bonus", RALLY_CRY_BONUS)
	caster.set_meta("rally_cry_timer",   RALLY_CRY_DURATION)
	if BridgeClient.is_connected_to_server():
		BridgeClient.send("apply_skill_effect", {
			"target_peer_id": peer_id,
			"effect": "rally_cry",
			"bonus": RALLY_CRY_BONUS,
			"duration": RALLY_CRY_DURATION,
		})

	for ally in SkillTree.get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= RALLY_CRY_RANGE:
			ally.set_meta("rally_speed_bonus", RALLY_CRY_BONUS)
			ally.set_meta("rally_cry_timer", RALLY_CRY_DURATION)
			# Deliver to the owning client of this ally.
			var ally_peer_id: int = _peer_id_from_node(ally)
			if ally_peer_id > 0 and BridgeClient.is_connected_to_server():
				BridgeClient.send("apply_skill_effect", {
					"target_peer_id": ally_peer_id,
					"effect": "rally_cry",
					"bonus": RALLY_CRY_BONUS,
					"duration": RALLY_CRY_DURATION,
				})

## Extract peer_id from a node named "FPSPlayer_<id>" or "RemotePlayer_<id>".
static func _peer_id_from_node(node: Node) -> int:
	var n: String = node.name
	for prefix in ["FPSPlayer_", "RemotePlayer_"]:
		if n.begins_with(prefix):
			var id_str: String = n.substr(prefix.length())
			if id_str.is_valid_int():
				return int(id_str)
	return -1

static func _revive_pulse(peer_id: int) -> void:
	var caster: Node = _resolve(peer_id)
	if caster == null:
		return
	var team: int = SkillTree.get_player_team(peer_id)
	# Full self-heal (server caps at max HP).
	_heal_player(peer_id, 999.0)
	# Heal allies within range
	for ally in SkillTree.get_ally_players(team, peer_id):
		if not (ally is Node3D):
			continue
		var dist: float = (ally as Node3D).global_position.distance_to(caster.global_position)
		if dist <= REVIVE_PULSE_RANGE:
			var ally_pid: int = _peer_id_from_node(ally)
			if ally_pid > 0:
				_heal_player(ally_pid, REVIVE_PULSE_ALLY)

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

	if BridgeClient.is_connected_to_server():
		BridgeClient.send("apply_skill_effect", {
			"target_peer_id": peer_id,
			"effect": "dash",
			"origin": [cb.global_position.x, cb.global_position.y, cb.global_position.z],
			"target": [target.x, target.y, target.z],
			"elapsed": 0.0,
			"duration": DASH_DURATION,
		})

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
	# Read weapon type from server-authoritative GameSync dict; avoids calling
	# get_current_weapon_type() on a puppet BasePlayer node (which has no such method).
	var weapon_type: String = GameSync.player_weapon_type.get(peer_id, "")
	player.set_meta("rapid_fire_timer",  RAPID_FIRE_DURATION)
	player.set_meta("rapid_fire_weapon", weapon_type)
	# Deliver to owning client.
	if BridgeClient.is_connected_to_server():
		BridgeClient.send("apply_skill_effect", {
			"target_peer_id": peer_id,
			"effect": "rapid_fire",
			"duration": RAPID_FIRE_DURATION,
			"weapon_type": weapon_type,
		})

static func _rocket_barrage(peer_id: int) -> void:
	# Python is authoritative — delegate targeting and rocket spawning to server.
	# Visual rockets are spawned via spawn_visual bridge messages on all clients.
	BridgeClient.send("use_skill_direct", {"node_id": "f_rocket_barrage", "peer_id": peer_id})

# ── Tank branch ───────────────────────────────────────────────────────────────

static func _adrenaline(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null:
		return
	_heal_player(peer_id, ADRENALINE_HEAL)

static func _iron_skin(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null:
		return
	# Set shield metas on the server-side node for any server-path reads.
	# Python is authoritative for shield state — no GameSync.set_player_shield call.
	player.set_meta("shield_hp",    IRON_SKIN_HP)
	player.set_meta("shield_timer", IRON_SKIN_DURATION)
	# Deliver to owning client so FPSController can show local shield feedback.
	if BridgeClient.is_connected_to_server():
		BridgeClient.send("apply_skill_effect", {
			"target_peer_id": peer_id,
			"effect": "iron_skin",
			"hp": IRON_SKIN_HP,
			"timer": IRON_SKIN_DURATION,
		})

static func _deploy_mg(peer_id: int) -> void:
	var player: Node = _resolve(peer_id)
	if player == null or not (player is Node3D):
		return
	var team: int = SkillTree.get_player_team(peer_id)
	var pos: Vector3 = (player as Node3D).global_position
	# Python is authoritative — tell the server to spawn the MG tower.
	BridgeClient.send("deploy_mg", {
		"peer_id": peer_id,
		"team": team,
		"pos": [pos.x, pos.y, pos.z],
		"lifetime": DEPLOY_MG_LIFETIME,
	})
