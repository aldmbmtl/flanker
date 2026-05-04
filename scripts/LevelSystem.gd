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
const HP_PER_POINT      := 15.0
const SPEED_PER_POINT   := 0.15
const DAMAGE_PER_POINT  := 0.10
const STAMINA_PER_POINT := 2.0

# Supporter stat bonus per attribute point invested
const TOWER_HP_PER_POINT           := 0.05   # +5% tower spawn HP per point
const PLACEMENT_RANGE_PER_POINT    := 0.10   # -10% spacing radius per point
const TOWER_FIRE_RATE_PER_POINT    := 0.05   # -5% attack_interval per point

# Max points that can go into any single attribute
const ATTR_CAP := 6

# Role-gated attribute sets
const FIGHTER_ATTRS   := ["hp", "speed", "damage", "stamina"]
const SUPPORTER_ATTRS := ["tower_hp", "placement_range", "tower_fire_rate"]

# ── Per-peer state ─────────────────────────────────────────────────────────────

var _xp:     Dictionary = {}  # peer_id -> int
var _level:  Dictionary = {}  # peer_id -> int (1-based, 1..12)
var _points: Dictionary = {}  # peer_id -> int (unspent attribute points)
var _attrs:  Dictionary = {}  # peer_id -> {hp:int, speed:int, damage:int, ...}

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
	_attrs[peer_id]  = {"hp": 0, "speed": 0, "damage": 0, "stamina": 0,
			"tower_hp": 0, "placement_range": 0, "tower_fire_rate": 0}

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

# Award XP to a peer. Python is authoritative; this is also used in tests.
func award_xp(peer_id: int, amount: int) -> void:
	if not _xp.has(peer_id):
		register_peer(peer_id)
	var lvl: int = _level[peer_id]
	if lvl >= MAX_LEVEL:
		return
	_xp[peer_id] = _xp[peer_id] + amount
	var xp_needed: int = _xp_for_next_level(lvl)
	xp_gained.emit(peer_id, amount, _xp[peer_id], xp_needed)

	while _level[peer_id] < MAX_LEVEL and _xp[peer_id] >= _xp_for_next_level(_level[peer_id]):
		var needed: int = _xp_for_next_level(_level[peer_id])
		_xp[peer_id] = _xp[peer_id] - needed
		_level[peer_id] = _level[peer_id] + 1
		var pts: int = POINTS_PER_LEVEL[_level[peer_id] - 2]
		_points[peer_id] = _points[peer_id] + pts
		level_up.emit(peer_id, _level[peer_id])

# Spend an attribute point for a peer.
# Bridge path: client calls BridgeClient.send("spend_attribute", ...).
# Python validates and sends back "attribute_spent" which BridgeClient handles.
func request_spend_point(attr: String) -> void:
	BridgeClient.send("spend_attribute", {"attr": attr})

func spend_point_local(peer_id: int, attr: String) -> void:
	_do_spend_point(peer_id, attr)

func _do_spend_point(peer_id: int, attr: String) -> void:
	if not _attrs.has(peer_id):
		return
	if _points.get(peer_id, 0) <= 0:
		return
	if attr not in ["hp", "speed", "damage", "stamina",
			"tower_hp", "placement_range", "tower_fire_rate"]:
		return
	# Role gate: Fighters may not spend Supporter attrs and vice versa
	var role: String = SkillTree.get_role(peer_id)
	if role == "Fighter" and attr in SUPPORTER_ATTRS:
		return
	if role == "Supporter" and attr in FIGHTER_ATTRS:
		return
	var cur: int = _attrs[peer_id].get(attr, 0)
	if cur >= ATTR_CAP:
		return
	_attrs[peer_id][attr] = cur + 1
	_points[peer_id] = _points[peer_id] - 1
	attribute_spent.emit(peer_id, attr, _attrs[peer_id].duplicate())

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

func get_bonus_stamina(peer_id: int) -> float:
	var a: Dictionary = _attrs.get(peer_id, {})
	return float(a.get("stamina", 0)) * STAMINA_PER_POINT

func get_bonus_tower_hp_mult(peer_id: int) -> float:
	var a: Dictionary = _attrs.get(peer_id, {})
	return float(a.get("tower_hp", 0)) * TOWER_HP_PER_POINT

func get_bonus_placement_range_mult(peer_id: int) -> float:
	var a: Dictionary = _attrs.get(peer_id, {})
	return float(a.get("placement_range", 0)) * PLACEMENT_RANGE_PER_POINT

func get_bonus_tower_fire_rate_mult(peer_id: int) -> float:
	var a: Dictionary = _attrs.get(peer_id, {})
	return float(a.get("tower_fire_rate", 0)) * TOWER_FIRE_RATE_PER_POINT

func get_level(peer_id: int) -> int:
	return _level.get(peer_id, 1)

func get_xp(peer_id: int) -> int:
	return _xp.get(peer_id, 0)

func get_xp_needed(peer_id: int) -> int:
	return _xp_for_next_level(_level.get(peer_id, 1))

func get_unspent_points(peer_id: int) -> int:
	return _points.get(peer_id, 0)

func get_attrs(peer_id: int) -> Dictionary:
	return _attrs.get(peer_id, {"hp": 0, "speed": 0, "damage": 0, "stamina": 0,
			"tower_hp": 0, "placement_range": 0, "tower_fire_rate": 0}).duplicate()

# ── Internal helpers ───────────────────────────────────────────────────────────

func _xp_for_next_level(lvl: int) -> int:
	if lvl < 1 or lvl > XP_PER_LEVEL.size():
		return 999999
	return XP_PER_LEVEL[lvl - 1]

# ── Inbound mirror (called by BridgeClient on level_up) ───────────────────────

# Server → owning client: you leveled up, show dialog.
# Called directly by BridgeClient._handle_server_message for the "level_up" message.
func notify_level_up(new_level: int, pts_awarded: int) -> void:
	var my_id: int = BridgeClient.get_peer_id()
	if not _xp.has(my_id):
		register_peer(my_id)
	level_up.emit(my_id, new_level)
	_pending_levelup_points += pts_awarded
