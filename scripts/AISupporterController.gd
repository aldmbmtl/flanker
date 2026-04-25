extends Node
# ── AI Supporter Controller ───────────────────────────────────────────────────
# Server-only node. One per team that has no human Supporter.
# Periodically evaluates the game state and places towers / drops
# using the same server-side path as request_place_item.
#
# Tower placement zones (own half only):
#   Defensive  — first 20% of lane from base end (fountatin area)
#   Mid        — 20–45% of lane from base end
#   Aggressive — 45–50% of lane (just behind map center)
#   Jungle     — off-lane |x| 20–75 clearings
#
# Player-need drops: healthpack when ally HP < 40, weapon drop when ally reserve ammo < 15.
# Per-player 30s cooldown prevents spam.

const RESERVE_POINTS: float = 5.0

const DECISION_BASE_INTERVAL: float = 6.0
const DECISION_JITTER: float = 3.0

# Offsets tried around a zone anchor when searching for a valid tile.
const SIDE_OFFSETS: Array = [0.0, 5.0, -5.0, 8.0, -8.0, 12.0, -12.0, 3.0, -3.0]
const DEPTH_OFFSETS: Array = [0.0, 4.0, 8.0, 12.0, -4.0]

# Jungle candidate columns (|x| 20–75 band)
const JUNGLE_X: Array = [25.0, -25.0, 42.0, -42.0, 58.0, -58.0, 72.0, -72.0]
# Fractions of own half depth (0 = base, 1 = center) — push toward frontline
const JUNGLE_Z_FRACS: Array = [0.3, 0.55, 0.75, 0.85, 0.92]

# Radius ring for player-need drops
const DROP_RING_RADII: Array = [7.0, 11.0, 15.0]
const DROP_RING_ANGLES: Array = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]

const PLAYER_NEED_COOLDOWN: float = 30.0
const LOW_HP_THRESHOLD: float = 40.0
const LOW_AMMO_THRESHOLD: int = 15

var team: int = 0
var build_system: Node = null

var _timer: float = 4.0
var _wave_number: int = 0
var _placed_counts: Dictionary = {}

# peer_id -> remaining cooldown seconds
var _drop_cooldowns: Dictionary = {}
# peer_id -> last known world position (populated from remote_player_updated)
var _known_positions: Dictionary = {}

func _ready() -> void:
	set_process(true)
	GameSync.remote_player_updated.connect(_on_remote_player_updated)

func _on_remote_player_updated(peer_id: int, pos: Vector3, _rot: Vector3, _t: int) -> void:
	_known_positions[peer_id] = pos

func _process(delta: float) -> void:
	# Tick per-player drop cooldowns
	for pid in _drop_cooldowns.keys():
		_drop_cooldowns[pid] -= delta
		if _drop_cooldowns[pid] <= 0.0:
			_drop_cooldowns.erase(pid)

	_timer -= delta
	if _timer > 0.0:
		return
	_timer = DECISION_BASE_INTERVAL + randf() * DECISION_JITTER

	var spawner: Node = get_tree().root.get_node_or_null("Main/MinionSpawner")
	if spawner != null:
		var wn = spawner.get("wave_number")
		if wn != null:
			_wave_number = int(wn)

	_make_decision()

func _make_decision() -> void:
	if build_system == null:
		build_system = get_tree().root.get_node_or_null("Main/BuildSystem")
		if build_system == null:
			return

	# Track local FPS player position too
	var local_player: Node = get_tree().root.get_node_or_null("Main/FPSPlayer_1")
	if local_player == null:
		# Singleplayer node name is also FPSPlayer_1 — but peer id may differ; search group
		for p in get_tree().get_nodes_in_group("player"):
			local_player = p
			break
	if local_player != null and local_player.has_method("get"):
		_known_positions[1] = local_player.global_position

	var points: float = TeamData.get_points(team)

	# Player needs take priority — if we drop something, skip tower logic this cycle
	if _check_player_needs(points):
		return

	if _wave_number < 3:
		_phase_early(points)
	elif _wave_number < 7:
		_phase_mid(points)
	else:
		_phase_late(points)

# ── Player-need drops ─────────────────────────────────────────────────────────

func _check_player_needs(points: float) -> bool:
	# Gather all allied peer IDs and their health/position
	for peer_id in GameSync.player_healths.keys():
		if GameSync.get_player_team(peer_id) != team:
			continue
		if GameSync.player_dead.get(peer_id, false):
			continue
		if _drop_cooldowns.has(peer_id):
			continue

		var hp: float = GameSync.get_player_health(peer_id)
		var pos: Vector3 = _known_positions.get(peer_id, Vector3.INF)
		if pos == Vector3.INF:
			continue

		# Low HP → healthpack
		if hp < LOW_HP_THRESHOLD:
			if _try_place_near_player(pos, "healthpack", "", 15.0, points):
				_drop_cooldowns[peer_id] = PLAYER_NEED_COOLDOWN
				return true

		# Low ammo → drop matching weapon type (if server has seen ammo report)
		var reserve: int = GameSync.get_player_reserve_ammo(peer_id)
		if reserve < LOW_AMMO_THRESHOLD:
			var wtype: String = GameSync.player_weapon_type.get(peer_id, "pistol")
			var cost: float = float(build_system.WEAPON_COSTS.get(wtype, 10))
			if _try_place_near_player(pos, "weapon", wtype, cost, points):
				_drop_cooldowns[peer_id] = PLAYER_NEED_COOLDOWN
				return true

	return false

func _try_place_near_player(player_pos: Vector3, item_type: String, subtype: String,
		cost: float, available_points: float) -> bool:
	if available_points - cost < RESERVE_POINTS:
		return false
	# Own-half boundary
	var own_z_sign: float = 1.0 if team == 0 else -1.0
	for radius in DROP_RING_RADII:
		for deg in DROP_RING_ANGLES:
			var rad: float = deg * PI / 180.0
			var cx: float = player_pos.x + cos(rad) * radius
			var cz: float = player_pos.z + sin(rad) * radius
			# Must stay on own half
			if team == 0 and cz < 0.0:
				continue
			if team == 1 and cz > 0.0:
				continue
			var cy: float = _terrain_y(cx, cz)
			var candidate := Vector3(cx, cy, cz)
			if build_system.can_place_item(candidate, team, item_type):
				return _do_place(candidate, item_type, subtype)
	return false

# ── Phase logic ───────────────────────────────────────────────────────────────

func _phase_early(points: float) -> void:
	var lane_order: Array = _lanes_by_enemy_pressure()
	# Immediately push into all three zones — don't wait
	for lane_i in lane_order:
		for zone_pair in [[0.0, 0.2, "def"], [0.2, 0.45, "mid"], [0.45, 0.5, "agg"]]:
			var key: String = "lane_%d_cannon_%s" % [lane_i, zone_pair[2]]
			if _placed_counts.get(key, 0) < 1:
				if _try_place_zone(lane_i, zone_pair[0], zone_pair[1], "cannon", "", 25.0, points):
					_placed_counts[key] = _placed_counts.get(key, 0) + 1
					return
	# Early jungle cannon too
	var jkey: String = "jungle_cannon_0"
	if _placed_counts.get(jkey, 0) < 1:
		if _try_place_jungle("cannon", "", 25.0, points):
			_placed_counts[jkey] = 1
			return
	_try_place_zone(lane_order[0], 0.0, 0.15, "healthpack", "", 15.0, points)

func _phase_mid(points: float) -> void:
	var lane_order: Array = _lanes_by_enemy_pressure()
	# 3 cannons per zone per lane
	for lane_i in lane_order:
		for zone_pair in [[0.45, 0.5, "agg"], [0.2, 0.45, "mid"], [0.0, 0.2, "def"]]:
			var key: String = "lane_%d_cannon_%s" % [lane_i, zone_pair[2]]
			if _placed_counts.get(key, 0) < 2:
				if _try_place_zone(lane_i, zone_pair[0], zone_pair[1], "cannon", "", 25.0, points):
					_placed_counts[key] = _placed_counts.get(key, 0) + 1
					return
	# Slow + mortar at aggressive on all lanes
	for lane_i in lane_order:
		for tower_type in ["slow", "mortar"]:
			var cost: float = 30.0 if tower_type == "slow" else 35.0
			var key: String = "lane_%d_%s_agg" % [lane_i, tower_type]
			if _placed_counts.get(key, 0) < 1:
				if _try_place_zone(lane_i, 0.45, 0.5, tower_type, "", cost, points):
					_placed_counts[key] = 1
					return
	# Multiple jungle cannons
	for ji in range(3):
		var jkey: String = "jungle_cannon_%d" % ji
		if _placed_counts.get(jkey, 0) < 1:
			if _try_place_jungle("cannon", "", 25.0, points):
				_placed_counts[jkey] = 1
				return
	_try_place_zone(lane_order[0], 0.0, 0.15, "healthpack", "", 15.0, points)

func _phase_late(points: float) -> void:
	var lane_order: Array = _lanes_by_enemy_pressure()
	# Healstation
	if _placed_counts.get("healstation", 0) < 1:
		if _try_place_zone(lane_order[0], 0.0, 0.15, "healstation", "", 25.0, points):
			_placed_counts["healstation"] = 1
			return
	# 3 cannons per zone per lane — aggressive first
	for lane_i in lane_order:
		for zone_pair in [[0.45, 0.5, "agg"], [0.2, 0.45, "mid"], [0.0, 0.2, "def"]]:
			var key: String = "lane_%d_cannon_%s" % [lane_i, zone_pair[2]]
			if _placed_counts.get(key, 0) < 3:
				if _try_place_zone(lane_i, zone_pair[0], zone_pair[1], "cannon", "", 25.0, points):
					_placed_counts[key] = _placed_counts.get(key, 0) + 1
					return
	# 2 mortars + 2 slows per lane at aggressive/mid
	for lane_i in lane_order:
		for zone_pair in [[0.45, 0.5, "agg"], [0.2, 0.45, "mid"]]:
			for tower_type in ["mortar", "slow"]:
				var cost: float = 35.0 if tower_type == "mortar" else 30.0
				var key: String = "lane_%d_%s_%s" % [lane_i, tower_type, zone_pair[2]]
				if _placed_counts.get(key, 0) < 2:
					if _try_place_zone(lane_i, zone_pair[0], zone_pair[1], tower_type, "", cost, points):
						_placed_counts[key] = _placed_counts.get(key, 0) + 1
						return
	# Dense jungle fill — cannons + mortars
	for ji in range(8):
		var jkey: String = "jungle_cannon_%d" % ji
		if _placed_counts.get(jkey, 0) < 1:
			if _try_place_jungle("cannon", "", 25.0, points):
				_placed_counts[jkey] = 1
				return
	for ji in range(4):
		var jkey: String = "jungle_mortar_%d" % ji
		if _placed_counts.get(jkey, 0) < 1:
			if _try_place_jungle("mortar", "", 35.0, points):
				_placed_counts[jkey] = 1
				return

# ── Zone placement ────────────────────────────────────────────────────────────

# Places item near a lane zone defined by [start_frac, end_frac] of own half.
# start_frac=0 is own base end, end_frac=0.5 is map center.
func _try_place_zone(lane_i: int, start_frac: float, end_frac: float,
		item_type: String, subtype: String, cost: float, available_points: float) -> bool:
	if available_points - cost < RESERVE_POINTS:
		return false

	var anchor: Vector3 = _lane_zone_anchor(lane_i, start_frac, end_frac)
	# Direction along the lane from base toward center — used for depth offsets
	var lane_dir_z: float = -1.0 if team == 0 else 1.0  # toward center

	for depth in DEPTH_OFFSETS:
		for side in SIDE_OFFSETS:
			var cx: float = anchor.x + side
			var cz: float = anchor.z + depth * lane_dir_z
			# Stay on own half
			if team == 0 and cz < 0.0:
				continue
			if team == 1 and cz > 0.0:
				continue
			var cy: float = _terrain_y(cx, cz)
			var candidate := Vector3(cx, cy, cz)
			if build_system.can_place_item(candidate, team, item_type):
				return _do_place(candidate, item_type, subtype)
	return false

func _try_place_jungle(item_type: String, subtype: String,
		cost: float, available_points: float) -> bool:
	if available_points - cost < RESERVE_POINTS:
		return false

	var base_z: float = 80.0 if team == 0 else -80.0  # own base z magnitude
	# Shuffle so we don't always fill the same column first
	var xs: Array = JUNGLE_X.duplicate()
	xs.shuffle()
	var zfracs: Array = JUNGLE_Z_FRACS.duplicate()
	zfracs.shuffle()

	for frac in zfracs:
		for x in xs:
			# frac=0 → near base, frac=1 → near center
			var cz: float = base_z * (1.0 - frac)
			var cy: float = _terrain_y(x, cz)
			var candidate := Vector3(x, cy, cz)
			if build_system.can_place_item(candidate, team, item_type):
				return _do_place(candidate, item_type, subtype)
	return false

# ── Core helpers ──────────────────────────────────────────────────────────────

func _terrain_y(x: float, z: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 200.0, z),
		Vector3(x, -200.0, z)
	)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result.position.y

func _do_place(world_pos: Vector3, item_type: String, subtype: String) -> bool:
	if not build_system.place_item(world_pos, team, item_type, subtype):
		return false
	LobbyManager.spawn_item_visuals.rpc(world_pos, team, item_type, subtype)
	LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
	LobbyManager.item_spawned.emit(item_type, team)
	return true

# ── Lane analysis ─────────────────────────────────────────────────────────────

func _lanes_by_enemy_pressure() -> Array:
	var enemy_team: int = 1 - team
	var counts: Array = [0, 0, 0]
	for minion in get_tree().get_nodes_in_group("minions"):
		if minion.get("team") != enemy_team:
			continue
		var pos: Vector3 = minion.global_position
		var best_lane: int = 0
		var best_dist: float = INF
		for lane_i in range(3):
			var pts: Array = LaneData.get_lane_points(lane_i)
			var d: float = LaneData.dist_to_polyline(Vector2(pos.x, pos.z), pts)
			if d < best_dist:
				best_dist = d
				best_lane = lane_i
		counts[best_lane] += 1
	var order: Array = [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return counts[a] > counts[b])
	return order

# Returns an anchor Vector3 for the lane zone between start_frac and end_frac
# of own half of the lane. frac=0 → own base end, frac=0.5 → map center.
func _lane_zone_anchor(lane_i: int, start_frac: float, end_frac: float) -> Vector3:
	var pts: Array = LaneData.get_lane_points(lane_i)
	if pts.is_empty():
		return Vector3.ZERO

	var n: int = pts.size()
	# Own half: team 0 → indices 0..n/2-1 (z>0 end), team 1 → n/2..n-1 (z<0 end)
	var half_start: int = 0 if team == 0 else n / 2
	var half_end: int = n / 2 if team == 0 else n
	var half_n: int = half_end - half_start

	var idx_start: int = half_start + int(start_frac * 2.0 * half_n)
	var idx_end: int   = half_start + int(end_frac   * 2.0 * half_n)
	idx_start = clampi(idx_start, half_start, half_end - 1)
	idx_end   = clampi(idx_end,   idx_start + 1, half_end)

	var sum := Vector2.ZERO
	var count: int = 0
	for i in range(idx_start, idx_end):
		sum += pts[i]
		count += 1

	var avg: Vector2 = sum / float(count) if count > 0 else Vector2.ZERO
	return Vector3(avg.x, 5.0, avg.y)
