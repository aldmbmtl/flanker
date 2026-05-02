extends Node
# SupporterSkills — executes active ability effects for Supporter players.
# All functions are server-authoritative; called by SkillTree.use_active_local().

static func execute(node_id: String, peer_id: int) -> void:
	match node_id:
		"s_basic_t3":
			_basic_barrage(peer_id)
		"s_cannon_t3":
			_cannon_barrage(peer_id)
		"s_healer_t3":
			_mass_heal(peer_id)

# ── s_basic_t3: force all living basic minions to fire immediately ─────────────

static func _basic_barrage(peer_id: int) -> void:
	var team: int = SkillTree.get_player_team(peer_id)
	var minions: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("minions")
	for m in minions:
		var m_team: int = int(m.get("team") if m.get("team") != null else -1)
		if m_team != team:
			continue
		if m.get("_dead"):
			continue
		# Only trigger on basic minions (MinionAI / MinionBase, not cannon/healer subclasses).
		if m is CannonMinionAI or m is HealerMinionAI:
			continue
		m.set("_attack_timer", 0.0)

# ── s_cannon_t3: force all living cannon minions to fire immediately ───────────

static func _cannon_barrage(peer_id: int) -> void:
	var team: int = SkillTree.get_player_team(peer_id)
	var minions: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("minions")
	for m in minions:
		if not (m is CannonMinionAI):
			continue
		var m_team: int = int(m.get("team") if m.get("team") != null else -1)
		if m_team != team:
			continue
		if m.get("_dead"):
			continue
		m.set("_attack_timer", 0.0)

# ── s_healer_t3: instantly heal 30 HP to all friendly minions and players ──────

static func _mass_heal(peer_id: int) -> void:
	var team: int = SkillTree.get_player_team(peer_id)
	var tree: SceneTree = Engine.get_main_loop().root.get_tree()
	# Heal friendly minions (minion.heal() is safe — server-only, no RPC needed)
	for m in tree.get_nodes_in_group("minions"):
		var m_team: int = int(m.get("team") if m.get("team") != null else -1)
		if m_team != team:
			continue
		if m.get("_dead"):
			continue
		if m.has_method("heal"):
			m.heal(30.0)
	# Heal friendly players via authoritative broadcast so remote clients receive HP.
	for pid in GameSync.player_teams:
		if GameSync.get_player_team(pid) != team:
			continue
		if GameSync.player_dead.get(pid, false):
			continue
		LobbyManager.heal_player_broadcast(pid, 30.0)
