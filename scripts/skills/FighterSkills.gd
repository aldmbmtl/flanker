extends Node
# FighterSkills — executes active ability effects for Fighter players.
# All functions are server-authoritative; called by SkillTree.use_active_local().

const DASH_DISTANCE := 5.0
const ADRENALINE_HEAL := 40.0

static func execute(node_id: String, peer_id: int) -> void:
	match node_id:
		"f_dash":
			_dash(peer_id)
		"f_adrenaline":
			_adrenaline(peer_id)

static func _dash(peer_id: int) -> void:
	# Find the FPSPlayer node for this peer and apply an impulse forward.
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if main == null:
		return
	var player: Node = main.get_node_or_null("FPSPlayer_%d" % peer_id)
	if player == null or not player.has_method("_dash_impulse"):
		# Fallback: apply velocity directly if CharacterBody3D
		if player != null and player is CharacterBody3D:
			var cb := player as CharacterBody3D
			var forward: Vector3 = -cb.global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.001:
				forward = forward.normalized()
			cb.velocity += forward * (DASH_DISTANCE / 0.15)
		return
	player._dash_impulse(DASH_DISTANCE)

static func _adrenaline(peer_id: int) -> void:
	# Heal the local player by ADRENALINE_HEAL HP.
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if main == null:
		return
	var player: Node = main.get_node_or_null("FPSPlayer_%d" % peer_id)
	if player == null:
		return
	if player.has_method("heal"):
		player.heal(ADRENALINE_HEAL)
