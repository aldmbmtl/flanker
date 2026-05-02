extends Node
# SkillTree autoload — server-authoritative skill tree state, RPC surface,
# cooldown tracking, and passive bonus queries.
#
# Registration pattern mirrors LevelSystem exactly:
#   register_peer(id, role)  called from Main.gd after role is confirmed
#   clear_peer(id)           called when a peer disconnects
#   clear_all()              called at match end / during tests

# ── Inner state container ──────────────────────────────────────────────────────

class SkillTreeState:
	var role: String = ""
	var skill_pts: int = 0
	var unlocked: Array = []           # Array[String] of node IDs
	var active_slots: Array = ["", ""] # [slot_0_id, slot_1_id]
	var cooldowns: Dictionary = {}     # node_id -> float (remaining seconds)
	# second_wind: tracks whether the auto-heal has fired this life
	var second_wind_used: bool = false

# ── Autoload state ─────────────────────────────────────────────────────────────

var _states: Dictionary = {}  # peer_id -> SkillTreeState

# ── Signals ────────────────────────────────────────────────────────────────────

signal skill_unlocked(peer_id: int, node_id: String)
signal active_used(peer_id: int, node_id: String)
signal skill_pts_changed(peer_id: int, pts: int)
signal active_slots_changed(peer_id: int, slots: Array)

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	LevelSystem.level_up.connect(_on_level_up)

func _process(delta: float) -> void:
	for peer_id in _states:
		_tick_cooldowns_for(peer_id, delta)

# ── Public API ─────────────────────────────────────────────────────────────────

func register_peer(peer_id: int, role: String) -> void:
	if _states.has(peer_id):
		return
	var s := SkillTreeState.new()
	s.role = role
	_states[peer_id] = s
	# Grant dash by default for Fighters so it's immediately testable
	if role == "Fighter":
		s.skill_pts += 1
		s.unlocked.append("f_dash")
		s.active_slots[0] = "f_dash"
		skill_pts_changed.emit(peer_id, s.skill_pts)
		skill_unlocked.emit(peer_id, "f_dash")
		active_slots_changed.emit(peer_id, s.active_slots.duplicate())

func clear_peer(peer_id: int) -> void:
	_states.erase(peer_id)

func clear_all() -> void:
	_states.clear()

func get_skill_pts(peer_id: int) -> int:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return 0
	return s.skill_pts

func debug_grant_pts(peer_id: int, amount: int) -> void:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return
	s.skill_pts += amount
	skill_pts_changed.emit(peer_id, s.skill_pts)

func is_unlocked(peer_id: int, node_id: String) -> bool:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return false
	return s.unlocked.has(node_id)

func get_active_slots(peer_id: int) -> Array:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return ["", ""]
	return s.active_slots.duplicate()

func get_cooldown(peer_id: int, node_id: String) -> float:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return 0.0
	return s.cooldowns.get(node_id, 0.0)

func get_role(peer_id: int) -> String:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return ""
	return s.role

# Returns the sum of passive_val for all unlocked nodes with matching passive_key.
func get_passive_bonus(peer_id: int, passive_key: String) -> float:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return 0.0
	var total: float = 0.0
	for nid in s.unlocked:
		var def: Dictionary = SkillDefs.get_def(nid)
		if def.get("passive_key", "") == passive_key:
			total += float(def.get("passive_val", 0.0))
	return total

# ── Shared helpers (used by FighterSkills and SupporterSkills) ────────────

func get_main() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Main")

func get_player(peer_id: int) -> Node:
	var main: Node = get_main()
	if main == null:
		return null
	var n: Node = main.get_node_or_null("FPSPlayer_%d" % peer_id)
	if n != null:
		return n
	# On the server, remote peers are represented as BasePlayer puppets named
	# RemotePlayer_<id>. Fall back to that so skill execution can read position.
	return main.get_node_or_null("RemotePlayer_%d" % peer_id)

func get_player_team(peer_id: int) -> int:
	return GameSync.get_player_team(peer_id)

func get_ally_players(team: int, exclude_id: int = -1) -> Array:
	var main: Node = get_main()
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
		if GameSync.get_player_team(pid) == team:
			result.append(child)
	return result

func get_supporter_position(peer_id: int) -> Vector3:
	var main: Node = get_main()
	if main == null:
		return Vector3.ZERO
	var rts: Node = main.get_node_or_null("RTSCamera")
	if rts != null and rts is Node3D:
		return (rts as Node3D).global_position
	return Vector3.ZERO

# Reset per-life state (second_wind). Called by Main/GameSync on respawn.
func get_all_peers() -> Array:
	return _states.keys()

func reset_per_life(peer_id: int) -> void:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return
	s.second_wind_used = false

func is_second_wind_used(peer_id: int) -> bool:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return true
	return s.second_wind_used

func consume_second_wind(peer_id: int) -> void:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return
	s.second_wind_used = true

# ── Validation ─────────────────────────────────────────────────────────────────

func can_unlock(peer_id: int, node_id: String) -> bool:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return false
	if s.unlocked.has(node_id):
		return false  # already unlocked
	var def: Dictionary = SkillDefs.get_def(node_id)
	if def.is_empty():
		return false  # unknown node
	if def.get("role", "") != s.role:
		return false  # wrong role
	var cost: int = int(def.get("cost", 999))
	if s.skill_pts < cost:
		return false  # insufficient points
	var lvl_req: int = int(def.get("level_req", 0))
	if lvl_req > 0 and LevelSystem.get_level(peer_id) < lvl_req:
		return false
	for prereq in def.get("prereqs", []):
		if not s.unlocked.has(prereq):
			return false
	return true

# ── Unlock (server-authoritative) ─────────────────────────────────────────────

func unlock_node_local(peer_id: int, node_id: String) -> void:
	if not can_unlock(peer_id, node_id):
		return
	var s: SkillTreeState = _states[peer_id]
	var cost: int = int(SkillDefs.get_def(node_id).get("cost", 0))
	s.skill_pts -= cost
	s.unlocked.append(node_id)
	skill_unlocked.emit(peer_id, node_id)
	skill_pts_changed.emit(peer_id, s.skill_pts)
	_push_state_to_peer(peer_id)

# ── Active slot assignment ─────────────────────────────────────────────────────

# slot: 0 or 1.  node_id: "" to clear the slot.
func assign_active_slot(peer_id: int, slot: int, node_id: String) -> void:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null or slot < 0 or slot > 1:
		return
	if node_id != "" and not s.unlocked.has(node_id):
		return
	if node_id != "":
		var def: Dictionary = SkillDefs.get_def(node_id)
		if def.get("type", "") != "active":
			return
	s.active_slots[slot] = node_id
	active_slots_changed.emit(peer_id, s.active_slots.duplicate())
	_push_state_to_peer(peer_id)

# ── Cooldown management ────────────────────────────────────────────────────────

func _tick_cooldowns_for(peer_id: int, delta: float) -> void:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return
	for key in s.cooldowns.keys():
		s.cooldowns[key] = maxf(0.0, s.cooldowns[key] - delta)

func _set_cooldown(peer_id: int, node_id: String) -> void:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return
	var cd: float = float(SkillDefs.get_def(node_id).get("cooldown", 0.0))
	if cd > 0.0:
		s.cooldowns[node_id] = cd

# ── Use active ability (server-authoritative) ──────────────────────────────────

func use_active_local(peer_id: int, slot: int) -> void:
	var s: SkillTreeState = _states.get(peer_id)
	if s == null or slot < 0 or slot > 1:
		return
	var node_id: String = s.active_slots[slot]
	if node_id == "":
		return
	if not s.unlocked.has(node_id):
		return
	var remaining: float = s.cooldowns.get(node_id, 0.0)
	if remaining > 0.0:
		return  # on cooldown
	_set_cooldown(peer_id, node_id)
	active_used.emit(peer_id, node_id)
	_push_state_to_peer(peer_id)
	# Dispatch to skill implementation
	var def: Dictionary = SkillDefs.get_def(node_id)
	var role: String = def.get("role", "")
	if role == "Fighter":
		FighterSkills.execute(node_id, peer_id)
	elif role == "Supporter":
		SupporterSkills.execute(node_id, peer_id)

# ── Level-up hook ──────────────────────────────────────────────────────────────

func _on_level_up(peer_id: int, _new_level: int) -> void:
	# Award 1 skill point per level-up regardless of which level it is.
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return
	s.skill_pts += 1
	skill_pts_changed.emit(peer_id, s.skill_pts)
	_push_state_to_peer(peer_id)

# ── Multiplayer sync ───────────────────────────────────────────────────────────

func _push_state_to_peer(peer_id: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if peer_id == multiplayer.get_unique_id():
		return  # server is also local — state is already live
	if not multiplayer.get_peers().has(peer_id):
		return
	var s: SkillTreeState = _states.get(peer_id)
	if s == null:
		return
	sync_skill_state.rpc_id(peer_id, s.skill_pts, s.unlocked.duplicate(),
			s.active_slots.duplicate(), s.cooldowns.duplicate())

# Server → owning client: push full authoritative state.
@rpc("authority", "reliable")
func sync_skill_state(pts: int, unlocked: Array, slots: Array, cooldowns: Dictionary) -> void:
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var s: SkillTreeState = _states.get(my_id)
	if s == null:
		# Client has no local state yet — create it so queries work.
		s = SkillTreeState.new()
		_states[my_id] = s
	# Diff unlocked arrays before overwriting so we can emit skill_unlocked for each new node.
	var old_unlocked: Array = s.unlocked.duplicate()
	var old_cooldowns: Dictionary = s.cooldowns.duplicate()
	var old_slots: Array = s.active_slots.duplicate()
	s.skill_pts = pts
	s.unlocked = unlocked.duplicate()
	s.active_slots = slots.duplicate()
	s.cooldowns = cooldowns.duplicate()
	# Emit skill_unlocked for every node that is new in this sync.
	for nid in unlocked:
		if not old_unlocked.has(nid):
			skill_unlocked.emit(my_id, nid)
	# Emit active_slots_changed if slots changed.
	if s.active_slots != old_slots:
		active_slots_changed.emit(my_id, s.active_slots.duplicate())
	# Emit active_used for any slot whose cooldown just became > 0 (ability was fired).
	for slot_idx in range(s.active_slots.size()):
		var nid: String = s.active_slots[slot_idx]
		if nid == "":
			continue
		var new_cd: float = s.cooldowns.get(nid, 0.0)
		var old_cd: float = old_cooldowns.get(nid, 0.0)
		if new_cd > 0.0 and old_cd == 0.0:
			active_used.emit(my_id, nid)
	skill_pts_changed.emit(my_id, pts)

func _sender_id() -> int:
	var id: int = multiplayer.get_remote_sender_id()
	return id if id != 0 else 1

# Client → server: request to unlock a node.
@rpc("any_peer", "reliable")
func request_unlock(node_id: String) -> void:
	if not multiplayer.is_server(): return
	unlock_node_local(_sender_id(), node_id)

# Client → server: assign active slot.
@rpc("any_peer", "reliable")
func request_assign_active(slot: int, node_id: String) -> void:
	if not multiplayer.is_server(): return
	assign_active_slot(_sender_id(), slot, node_id)

# Client → server: use active ability.
@rpc("any_peer", "reliable")
func request_use_active(slot: int) -> void:
	if not multiplayer.is_server(): return
	use_active_local(_sender_id(), slot)

# ── Effect delivery RPCs (server → owning client) ─────────────────────────────
# These replicate meta-based ability state to the client's own player node so
# FPSController can read them locally. Called by FighterSkills after setting
# the same metas on the server-side node.

@rpc("authority", "reliable")
func apply_dash(origin: Vector3, target: Vector3, elapsed: float, duration: float) -> void:
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var player: Node = get_player(my_id)
	if player == null:
		return
	player.set_meta("dash_origin",   origin)
	player.set_meta("dash_target",   target)
	player.set_meta("dash_elapsed",  elapsed)
	player.set_meta("dash_duration", duration)

@rpc("authority", "reliable")
func apply_rapid_fire(duration: float, weapon_type: String) -> void:
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var player: Node = get_player(my_id)
	if player == null:
		return
	player.set_meta("rapid_fire_timer",  duration)
	player.set_meta("rapid_fire_weapon", weapon_type)

@rpc("authority", "reliable")
func apply_iron_skin(hp: float, timer: float) -> void:
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var player: Node = get_player(my_id)
	if player == null:
		return
	player.set_meta("shield_hp",    hp)
	player.set_meta("shield_timer", timer)

@rpc("authority", "reliable")
func apply_rally_cry(bonus: float, duration: float) -> void:
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var player: Node = get_player(my_id)
	if player == null:
		return
	player.set_meta("rally_speed_bonus", bonus)
	player.set_meta("rally_cry_timer",   duration)
