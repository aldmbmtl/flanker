extends Node

# ── Level / XP constants ──────────────────────────────────────────────────────

const MAX_LEVEL := 12

# XP required to reach level N+1 (index 0 = level 1→2, index 10 = level 11→12)
const XP_PER_LEVEL: Array[int] = [70, 140, 250, 390, 560, 770, 1020, 1300, 1610, 1960, 2350]

# Attribute points awarded on reaching each level (index 0 = level 2, index 10 = level 12)
const POINTS_PER_LEVEL: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3]

# Kill XP rewards
const XP_MINION  := 10
const XP_PLAYER  := 100
const XP_TOWER   := 200

# Stat bonus per attribute point invested
const HP_PER_POINT     := 15.0
const SPEED_PER_POINT  := 0.15
const DAMAGE_PER_POINT := 0.10

# Max points that can go into any single attribute
const ATTR_CAP := 6

# ── Per-peer state ─────────────────────────────────────────────────────────────
# All dicts keyed by peer_id (int)

var _xp:     Dictionary = {}  # peer_id -> int
var _level:  Dictionary = {}  # peer_id -> int (1-based, 1..12)
var _points: Dictionary = {}  # peer_id -> int (unspent attribute points)
var _attrs:  Dictionary = {}  # peer_id -> {hp:int, speed:int, damage:int}

# Pending queued attribute point dialogs for local player (multiple rapid level-ups)
var _pending_levelup_points: int = 0

# ── Signals ────────────────────────────────────────────────────────────────────

signal xp_gained(peer_id: int, amount: int, new_xp: int, xp_needed: int)
signal level_up(peer_id: int, new_level: int)
signal attribute_spent(peer_id: int, attr: String, new_attrs: Dictionary)

# ── Public API ─────────────────────────────────────────────────────────────────

func register_peer(peer_id: int) -> void:
	if _xp.has(peer_id):
		return
	_xp[peer_id]     = 0
	_level[peer_id]  = 1
	_points[peer_id] = 0
	_attrs[peer_id]  = {"hp": 0, "speed": 0, "damage": 0}

func clear_peer(peer_id: int) -> void:
	_xp.erase(peer_id)
	_level.erase(peer_id)
	_points.erase(peer_id)
	_attrs.erase(peer_id)

func clear_all() -> void:
	_xp.clear()
	_level.clear()
	_points.clear()
	_attrs.clear()

# Award XP to a peer (server-authoritative).
# In multiplayer this should only be called on the server.
func award_xp(peer_id: int, amount: int) -> void:
	if not _xp.has(peer_id):
		register_peer(peer_id)
	var lvl: int = _level[peer_id]
	if lvl >= MAX_LEVEL:
		return  # Already max level, no more XP needed
	_xp[peer_id] = _xp[peer_id] + amount
	var xp_needed: int = _xp_for_next_level(lvl)
	xp_gained.emit(peer_id, amount, _xp[peer_id], xp_needed)

	# Check for level-up(s)
	while _level[peer_id] < MAX_LEVEL and _xp[peer_id] >= _xp_for_next_level(_level[peer_id]):
		var needed: int = _xp_for_next_level(_level[peer_id])
		_xp[peer_id] = _xp[peer_id] - needed
		_level[peer_id] = _level[peer_id] + 1
		var pts: int = POINTS_PER_LEVEL[_level[peer_id] - 2]  # index 0 = level 2
		_points[peer_id] = _points[peer_id] + pts
		level_up.emit(peer_id, _level[peer_id])
		# In MP: send to owning client via RPC
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and peer_id != multiplayer.get_unique_id() and multiplayer.get_peers().has(peer_id):
			_sync_level_state_to_peer(peer_id)
			notify_level_up.rpc_id(peer_id, _level[peer_id], pts)
		elif multiplayer.has_multiplayer_peer() and multiplayer.is_server() and peer_id == multiplayer.get_unique_id():
			# Server is also the local player — just emit, no RPC needed
			pass
		elif not multiplayer.has_multiplayer_peer():
			# Singleplayer — signal is sufficient, Main.gd handles dialog
			pass

# Spend an attribute point for a peer.
# In MP this RPC is sent client→server; server validates + syncs back.
@rpc("any_peer", "reliable")
func request_spend_point(attr: String) -> void:
	var peer_id: int
	if multiplayer.has_multiplayer_peer():
		peer_id = multiplayer.get_remote_sender_id()
		if peer_id == 0:
			peer_id = 1
	else:
		peer_id = 1
	_do_spend_point(peer_id, attr)

func spend_point_local(peer_id: int, attr: String) -> void:
	_do_spend_point(peer_id, attr)

func _do_spend_point(peer_id: int, attr: String) -> void:
	if not _attrs.has(peer_id):
		return
	if _points.get(peer_id, 0) <= 0:
		return
	if attr not in ["hp", "speed", "damage"]:
		return
	var cur: int = _attrs[peer_id].get(attr, 0)
	if cur >= ATTR_CAP:
		return
	_attrs[peer_id][attr] = cur + 1
	_points[peer_id] = _points[peer_id] - 1
	attribute_spent.emit(peer_id, attr, _attrs[peer_id].duplicate())
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and peer_id != multiplayer.get_unique_id():
		_sync_level_state_to_peer(peer_id)

# ── Stat bonus queries ─────────────────────────────────────────────────────────

func get_bonus_hp(peer_id: int) -> float:
	var a: Dictionary = _attrs.get(peer_id, {})
	return float(a.get("hp", 0)) * HP_PER_POINT

func get_bonus_speed_mult(peer_id: int) -> float:
	var a: Dictionary = _attrs.get(peer_id, {})
	return float(a.get("speed", 0)) * SPEED_PER_POINT

func get_bonus_damage_mult(peer_id: int) -> float:
	var a: Dictionary = _attrs.get(peer_id, {})
	return float(a.get("damage", 0)) * DAMAGE_PER_POINT

func get_level(peer_id: int) -> int:
	return _level.get(peer_id, 1)

func get_xp(peer_id: int) -> int:
	return _xp.get(peer_id, 0)

func get_xp_needed(peer_id: int) -> int:
	return _xp_for_next_level(_level.get(peer_id, 1))

func get_unspent_points(peer_id: int) -> int:
	return _points.get(peer_id, 0)

func get_attrs(peer_id: int) -> Dictionary:
	return _attrs.get(peer_id, {"hp": 0, "speed": 0, "damage": 0}).duplicate()

# ── Internal helpers ───────────────────────────────────────────────────────────

func _xp_for_next_level(lvl: int) -> int:
	if lvl < 1 or lvl > XP_PER_LEVEL.size():
		return 999999
	return XP_PER_LEVEL[lvl - 1]

func _sync_level_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == multiplayer.get_unique_id():
		return  # Don't RPC to self
	if not multiplayer.get_peers().has(peer_id):
		return  # Peer not connected (e.g. offline/test context)
	var xp_val: int = _xp.get(peer_id, 0)
	var lvl: int    = _level.get(peer_id, 1)
	var pts: int    = _points.get(peer_id, 0)
	var a: Dictionary = _attrs.get(peer_id, {"hp": 0, "speed": 0, "damage": 0})
	sync_level_state.rpc_id(peer_id, peer_id, xp_val, lvl, pts, a)

# ── RPCs ───────────────────────────────────────────────────────────────────────

# Server → owning client: push authoritative level state
@rpc("authority", "reliable")
func sync_level_state(peer_id: int, xp_val: int, lvl: int, pts: int, attrs: Dictionary) -> void:
	if not _xp.has(peer_id):
		register_peer(peer_id)
	_xp[peer_id]     = xp_val
	_level[peer_id]  = lvl
	_points[peer_id] = pts
	_attrs[peer_id]  = attrs.duplicate()
	# Refresh local HUD
	var needed: int = _xp_for_next_level(lvl)
	xp_gained.emit(peer_id, 0, xp_val, needed)

# Server → owning client: you leveled up, show dialog
@rpc("authority", "reliable")
func notify_level_up(new_level: int, pts_awarded: int) -> void:
	# Runs on the receiving client
	var my_id: int = multiplayer.get_unique_id()
	if not _xp.has(my_id):
		register_peer(my_id)
	level_up.emit(my_id, new_level)
	_pending_levelup_points += pts_awarded
	_show_pending_levelup_dialog()

func _show_pending_levelup_dialog() -> void:
	# Signal is caught by Main.gd which shows the LevelUpDialog
	# We just queue the signal — dialog will call back spend_point_local (SP)
	# or request_spend_point.rpc (MP)
	pass
