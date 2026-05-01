extends Node
# SupporterSkills — executes active ability effects for Supporter players.
# All functions are server-authoritative; called by SkillTree.use_active_local().

const OVERDRIVE_DURATION  := 6.0    # seconds towers fire at 2× speed
const REPAIR_FRACTION     := 0.30   # 30% of max HP restored
const REPAIR_RANGE        := 15.0   # metres to nearest tower
const AMMO_DROP_RANGE     := 3.0    # metres allies must be within to get ammo
const RALLY_DURATION      := 8.0    # seconds teammates get +10% speed
const RALLY_SPEED_BONUS   := 0.10   # additive speed bonus

static func execute(node_id: String, peer_id: int) -> void:
	match node_id:
		"s_turret_overdrive":
			_turret_overdrive(peer_id)
		"s_ammo_drop":
			_ammo_drop(peer_id)
		"s_repair":
			_repair(peer_id)
		"s_rally":
			_rally(peer_id)

static func _find_nearest_friendly_tower(team: int, origin: Vector3, max_range: float) -> Node:
	var towers: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("towers")
	var best: Node = null
	var best_dist: float = max_range
	for t in towers:
		if t.get("team") != team:
			continue
		var d: float = (t as Node3D).global_position.distance_to(origin)
		if d < best_dist:
			best_dist = d
			best = t
	return best

static func _turret_overdrive(peer_id: int) -> void:
	# Find the nearest friendly tower to the Supporter's current cursor/position
	# and halve its attack_interval for OVERDRIVE_DURATION seconds.
	var team: int = SkillTree.get_player_team(peer_id)
	var origin: Vector3 = SkillTree.get_supporter_position(peer_id)
	var best: Node = _find_nearest_friendly_tower(team, origin, 9999.0)
	if best == null:
		return
	# Apply overdrive via a tween on the node's attack_interval
	var original_interval: float = float(best.get("attack_interval") if best.get("attack_interval") != null else 3.0)
	best.set("attack_interval", original_interval * 0.5)
	var tw: Tween = best.create_tween()
	tw.tween_interval(OVERDRIVE_DURATION)
	tw.tween_callback(func():
		if is_instance_valid(best):
			best.set("attack_interval", original_interval)
	)

static func _ammo_drop(peer_id: int) -> void:
	# Grant instant full reload to allies within AMMO_DROP_RANGE of the Supporter.
	var origin: Vector3 = SkillTree.get_supporter_position(peer_id)
	var players: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("players")
	for p in players:
		if not p.has_method("_finish_reload"):
			continue
		var ppos: Vector3 = (p as Node3D).global_position
		if ppos.distance_to(origin) <= AMMO_DROP_RANGE:
			# Force a full reload on all weapon slots
			if p.get("_slot_ammo") != null and p.get("weapons") != null:
				var slot_ammo: Array = p.get("_slot_ammo")
				var weapons_arr: Array = p.get("weapons")
				for i in range(weapons_arr.size()):
					if weapons_arr[i] != null:
						slot_ammo[i][0] = int(weapons_arr[i].magazine_size)
				p._update_ammo_hud()

static func _repair(peer_id: int) -> void:
	# Restore REPAIR_FRACTION of max HP to the nearest friendly tower within REPAIR_RANGE.
	var team: int = SkillTree.get_player_team(peer_id)
	var origin: Vector3 = SkillTree.get_supporter_position(peer_id)
	var best: Node = _find_nearest_friendly_tower(team, origin, REPAIR_RANGE)
	if best == null:
		return
	var max_hp: float = float(best.get("max_health") if best.get("max_health") != null else 500.0)
	var cur_hp: float = float(best.get("_health") if best.get("_health") != null else max_hp)
	var healed: float = min(cur_hp + max_hp * REPAIR_FRACTION, max_hp)
	best.set("_health", healed)

static func _rally(peer_id: int) -> void:
	# Apply a temporary speed bonus to all teammates.
	# Implemented by setting a timed modifier via GameSync rally tracking.
	# For now: iterate all FPSPlayer nodes on the same team and bump their
	# speed for RALLY_DURATION via a meta flag + timer, consumed in FPSController.
	var team: int = SkillTree.get_player_team(peer_id)
	var players: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("players")
	for p in players:
		var pt: int = int(p.get("player_team") if p.get("player_team") != null else -1)
		if pt != team:
			continue
		p.set_meta("rally_speed_bonus", RALLY_SPEED_BONUS)
		p.set_meta("rally_timer", RALLY_DURATION)

# ── Helpers (delegated to SkillTree shared methods) ─────────────────────
