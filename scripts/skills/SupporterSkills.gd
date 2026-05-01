extends Node
# SupporterSkills — executes active ability effects for Supporter players.
# All functions are server-authoritative; called by SkillTree.use_active_local().

static func execute(node_id: String, peer_id: int) -> void:
	match node_id:
		"s_minion_barrage":
			_minion_barrage(peer_id)
		"s_minion_surge":
			_minion_surge(peer_id)

static func _minion_barrage(peer_id: int) -> void:
	# Force all living friendly minions to fire immediately by resetting their
	# attack timer to zero. They will fire on the next physics frame.
	var team: int = SkillTree.get_player_team(peer_id)
	var minions: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("minions")
	for m in minions:
		var m_team: int = int(m.get("team") if m.get("team") != null else -1)
		if m_team != team:
			continue
		if m.get("_dead"):
			continue
		m.set("_attack_timer", 0.0)

static func _minion_surge(peer_id: int) -> void:
	# Award 1 team point per living friendly minion.
	var team: int = SkillTree.get_player_team(peer_id)
	var minions: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("minions")
	var count: int = 0
	for m in minions:
		var m_team: int = int(m.get("team") if m.get("team") != null else -1)
		if m_team != team:
			continue
		if m.get("_dead"):
			continue
		count += 1
	if count > 0:
		TeamData.add_points(team, count)
