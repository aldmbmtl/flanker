extends Node
# ── AI Supporter Controller ───────────────────────────────────────────────────
# Server-only node. One per team that has no human Supporter.
# Periodically evaluates the game state and places towers / drops
# using the same server-side path as BuildSystem.place_item.
#
# Tower placement zones (own half only):
#   Defensive  — first 20% of lane from base end (fountatin area)
#   Mid        — 20–45% of lane from base end
#   Aggressive — 45–50% of lane (just behind map center)
#   Jungle     — off-lane |x| 20–75 clearings
#
# Player-need drops: healthpack when ally HP < 40, weapon drop when ally reserve ammo < 15.
# Per-player 30s cooldown prevents spam.
#
# The AI uses a synthetic peer_id (-100 - team) registered with LevelSystem and
# SkillTree so that all attribute bonuses (tower HP, fire rate, placement range)
# and skill tree passive bonuses apply to its placed towers exactly as they do
# for human Supporters.

const RESERVE_POINTS: float = 5.0

const DECISION_BASE_INTERVAL: float = 6.0
const DECISION_JITTER: float = 3.0

# How often (seconds) the AI considers boosting a lane.
# Uses a separate timer so boosts don't compete with tower placement decisions.
const BOOST_CHECK_INTERVAL: float = 18.0
const BOOST_COST: int = 15
# Minimum wave before AI will boost lanes (let early economy settle)
const BOOST_MIN_WAVE: int = 3
# Point reserve the AI must keep before spending on a boost
const BOOST_RESERVE: float = 40.0

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

# Minimum enemy minion cluster size to justify a missile strike
const MINION_CLUSTER_MIN: int = 3
# Radius to count minions around cluster centroid
const MINION_CLUSTER_RADIUS: float = 18.0
# How far from enemy base z (in absolute units) a target must be — prevents base strikes
const BASE_EXCLUSION_Z: float = 70.0

var team: int = 0
var build_system: Node = null

# Synthetic peer_id for LevelSystem / SkillTree registration.
# -100 - team ensures no collision with ENet peer IDs (which start at 1).
# This id is local-server-only — never sent over the network.
var peer_id: int = -100

# Skill unlock priority: follow the minion branch order tier-by-tier.
const _SKILL_UNLOCK_ORDER: Array = [
	"s_basic_t1", "s_cannon_t1", "s_healer_t1",
	"s_basic_t2", "s_cannon_t2", "s_healer_t2",
	"s_basic_t3", "s_cannon_t3", "s_healer_t3",
]

var _timer: float = 4.0
var _wave_number: int = 0
var _placed_counts: Dictionary = {}
var _boost_timer: float = BOOST_CHECK_INTERVAL

# peer_id -> remaining cooldown seconds
var _drop_cooldowns: Dictionary = {}
# peer_id -> last known world position (populated from remote_player_updated)
var _known_positions: Dictionary = {}

# launcher_node_name -> remaining fire cooldown seconds (0.0 = ready)
var _launcher_cooldowns: Dictionary = {}

func _ready() -> void:
	set_process(true)
	peer_id = -100 - team
	LevelSystem.register_peer(peer_id)
	SkillTree.register_peer(peer_id, "Supporter")
	# XP sources — same events that award XP to human players
	LobbyManager.tower_despawned.connect(_on_tower_despawned)
	GameSync.player_died.connect(_on_player_died)
	# Attribute auto-spend and skill auto-unlock
	LevelSystem.level_up.connect(_on_level_up)
	SkillTree.skill_pts_changed.connect(_on_skill_pts_changed)
	GameSync.remote_player_updated.connect(_on_remote_player_updated)

func _on_remote_player_updated(pid: int, pos: Vector3, _rot: Vector3, _t: int) -> void:
	_known_positions[pid] = pos

# ── XP hooks ──────────────────────────────────────────────────────────────────

# Enemy tower destroyed — award tower kill XP (same as LevelSystem.XP_TOWER).
func _on_tower_despawned(_item_type: String, tower_team: int, _tower_name: String) -> void:
	if tower_team == team:
		return  # own tower destroyed, no XP
	LevelSystem.award_xp(peer_id, LevelSystem.XP_TOWER)

# Enemy player died — award player kill XP (same as LevelSystem.XP_PLAYER).
func _on_player_died(dead_peer_id: int, _respawn_time: float) -> void:
	if GameSync.get_player_team(dead_peer_id) == team:
		return  # ally died, no XP
	LevelSystem.award_xp(peer_id, LevelSystem.XP_PLAYER)

# ── Attribute auto-spend ──────────────────────────────────────────────────────

# Called whenever the AI levels up. Spends all available attribute points
# with wave-adaptive priority:
#   early (wave < 3)  → tower_hp first, then tower_fire_rate, then placement_range
#   mid   (3–6)       → tower_fire_rate first, then tower_hp, then placement_range
#   late  (≥ 7)       → placement_range first, then tower_fire_rate, then tower_hp
func _on_level_up(leveled_peer_id: int, _new_level: int) -> void:
	if leveled_peer_id != peer_id:
		return
	_spend_all_attribute_points()

func _spend_all_attribute_points() -> void:
	var priority: Array
	if _wave_number < 3:
		priority = ["tower_hp", "tower_fire_rate", "placement_range"]
	elif _wave_number < 7:
		priority = ["tower_fire_rate", "tower_hp", "placement_range"]
	else:
		priority = ["placement_range", "tower_fire_rate", "tower_hp"]

	while LevelSystem.get_unspent_points(peer_id) > 0:
		var spent: bool = false
		for attr in priority:
			var cur: int = LevelSystem.get_attrs(peer_id).get(attr, 0)
			if cur < LevelSystem.ATTR_CAP:
				LevelSystem.spend_point_local(peer_id, attr)
				spent = true
				break
		if not spent:
			break  # all attrs at cap

# ── Skill auto-unlock ─────────────────────────────────────────────────────────

# Called whenever skill points change for any peer. Unlocks the next available
# node in the minion branch priority order when it's our peer_id.
func _on_skill_pts_changed(changed_peer_id: int, _pts: int) -> void:
	if changed_peer_id != peer_id:
		return
	_unlock_next_skills()

func _unlock_next_skills() -> void:
	var changed: bool = true
	while changed:
		changed = false
		for nid in _SKILL_UNLOCK_ORDER:
			if SkillTree.is_unlocked(peer_id, nid):
				continue
			if SkillTree.can_unlock(peer_id, nid):
				SkillTree.unlock_node_local(peer_id, nid)
				changed = true
				break

func _process(delta: float) -> void:
	# Tick per-player drop cooldowns
	for pid in _drop_cooldowns.keys():
		_drop_cooldowns[pid] -= delta
		if _drop_cooldowns[pid] <= 0.0:
			_drop_cooldowns.erase(pid)

	# Tick launcher fire cooldowns
	for lname in _launcher_cooldowns.keys():
		_launcher_cooldowns[lname] -= delta
		if _launcher_cooldowns[lname] <= 0.0:
			_launcher_cooldowns[lname] = 0.0

	# Tick boost check timer
	_boost_timer -= delta
	if _boost_timer <= 0.0:
		_boost_timer = BOOST_CHECK_INTERVAL + randf() * 8.0
		_maybe_boost_lane()

	# Check missile strike opportunities every process frame (server-only)
	_check_strike_opportunities()

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
			if build_system.can_place_item(candidate, team, item_type, peer_id):
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
	# One machinegun per pressure lane at aggressive zone mid-phase
	for lane_i in lane_order:
		var key: String = "lane_%d_machinegun_agg" % lane_i
		if _placed_counts.get(key, 0) < 1:
			if _try_place_zone(lane_i, 0.45, 0.5, "machinegun", "", 40.0, points):
				_placed_counts[key] = 1
				return
	# One missile launcher mid-phase
	var lkey: String = "launcher_missile_0"
	if _placed_counts.get(lkey, 0) < 1:
		if _try_place_jungle("launcher_missile", "", float(LauncherDefs.get_build_cost("launcher_missile")), points):
			_placed_counts[lkey] = 1
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
	# Up to 2 machineguns per pressure lane at aggressive/mid late-phase
	for lane_i in lane_order:
		for zone_pair in [[0.45, 0.5, "agg"], [0.2, 0.45, "mid"]]:
			var key: String = "lane_%d_machinegun_%s" % [lane_i, zone_pair[2]]
			if _placed_counts.get(key, 0) < 2:
				if _try_place_zone(lane_i, zone_pair[0], zone_pair[1], "machinegun", "", 40.0, points):
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
	# Up to 3 missile launchers late-phase
	for li in range(3):
		var lkey: String = "launcher_missile_%d" % li
		if _placed_counts.get(lkey, 0) < 1:
			if _try_place_jungle("launcher_missile", "", float(LauncherDefs.get_build_cost("launcher_missile")), points):
				_placed_counts[lkey] = 1
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
			if build_system.can_place_item(candidate, team, item_type, peer_id):
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
			if build_system.can_place_item(candidate, team, item_type, peer_id):
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
	var assigned_name: String = build_system.place_item(world_pos, team, item_type, subtype, peer_id)
	if assigned_name == "":
		return false
	LobbyManager.item_spawned.emit(item_type, team)
	# Register launcher so AI can fire from it
	if LauncherDefs.is_launcher_type(item_type):
		_launcher_cooldowns[assigned_name] = 0.0
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

# ── Lane boost logic ──────────────────────────────────────────────────────────

# Called periodically. If mid/late game and team has spare points, boost the
# lane with the most enemy pressure (or all lanes if points are plentiful).
func _maybe_boost_lane() -> void:
	if _wave_number < BOOST_MIN_WAVE:
		return
	var points: float = TeamData.get_points(team)
	if points - BOOST_COST < BOOST_RESERVE:
		return

	var spawner: Node = get_tree().root.get_node_or_null("Main/MinionSpawner")
	if spawner == null:
		return

	# If we have lots of spare points, boost all lanes; otherwise pick the busiest
	if points - (BOOST_COST * 3) >= BOOST_RESERVE and randf() < 0.3:
		if TeamData.spend_points(team, BOOST_COST):
			spawner.boost_all_lanes(team)
	else:
		var lane_order: Array = _lanes_by_enemy_pressure()
		var target_lane: int = lane_order[0]
		if TeamData.spend_points(team, BOOST_COST):
			spawner.boost_lane(team, target_lane, LobbyManager.LANE_BOOST_AMOUNT)

# ── Missile strike logic ──────────────────────────────────────────────────────

# Called every _process frame. Iterates ready launchers and fires at best target.
func _check_strike_opportunities() -> void:
	if _launcher_cooldowns.is_empty():
		return
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return

	for lname in _launcher_cooldowns.keys():
		if _launcher_cooldowns[lname] > 0.0:
			continue
		# Resolve the launcher node
		var launcher: Node = main.get_node_or_null(lname)
		if launcher == null:
			# Tower was destroyed — remove tracking
			_launcher_cooldowns.erase(lname)
			continue
		# Determine launcher type from node name  e.g. "Launcher_missile_10_30"
		var launcher_type: String = _launcher_type_from_node(launcher)
		if launcher_type == "":
			continue
		var fire_cost: int = LauncherDefs.get_fire_cost(launcher_type)
		if TeamData.get_points(team) < fire_cost:
			continue

		var target: Vector3 = _best_strike_target()
		if target == Vector3.INF:
			continue

		# Confirm target is not in enemy base exclusion zone
		if _is_in_base_zone(target):
			continue

		var fire_pos: Vector3 = launcher.get_fire_position() if launcher.has_method("get_fire_position") \
				else launcher.global_position + Vector3(0.0, 6.0, 0.0)

		if not TeamData.spend_points(team, fire_cost):
			continue

		LobbyManager.spawn_missile_server(fire_pos, target, team, launcher_type)
		BridgeClient.send("request_fire_missile", {
			"fire_pos": [fire_pos.x, fire_pos.y, fire_pos.z],
			"target_pos": [target.x, target.y, target.z],
			"team": team,
			"launcher_type": launcher_type,
		})

		_launcher_cooldowns[lname] = LauncherDefs.get_cooldown(launcher_type)
		# Fire one launcher per frame maximum
		return

# Priority: deepest enemy tower → largest enemy minion cluster centroid.
# Returns Vector3.INF if no valid target found.
func _best_strike_target() -> Vector3:
	var enemy_team: int = 1 - team
	var enemy_base_z: float = -82.0 if enemy_team == 0 else 82.0

	# 1) Deepest enemy tower (closest to enemy base — most forward on their half)
	var best_tower: Node = null
	var best_tower_depth: float = INF  # distance to enemy base z
	for node in get_tree().get_nodes_in_group("towers"):
		var t: int = node.get("team") if node.get("team") != null else -1
		if t != enemy_team:
			continue
		var dist_to_base: float = abs(node.global_position.z - enemy_base_z)
		if dist_to_base < best_tower_depth:
			best_tower_depth = dist_to_base
			best_tower = node
	if best_tower != null:
		var tp: Vector3 = best_tower.global_position
		if not _is_in_base_zone(tp):
			return tp

	# 2) Largest enemy minion cluster centroid
	return _enemy_minion_cluster_centroid(enemy_team)

# Returns centroid of the densest enemy minion cluster, or Vector3.INF if none.
func _enemy_minion_cluster_centroid(enemy_team: int) -> Vector3:
	var minions: Array = []
	for m in get_tree().get_nodes_in_group("minions"):
		if m.get("team") == enemy_team:
			minions.append(m)
	if minions.is_empty():
		return Vector3.INF

	var best_centroid: Vector3 = Vector3.INF
	var best_count: int = 0

	for seed_m in minions:
		var sp: Vector3 = seed_m.global_position
		var cluster_sum: Vector3 = Vector3.ZERO
		var cluster_count: int = 0
		for other in minions:
			if sp.distance_to(other.global_position) <= MINION_CLUSTER_RADIUS:
				cluster_sum += other.global_position
				cluster_count += 1
		if cluster_count > best_count:
			best_count = cluster_count
			best_centroid = cluster_sum / float(cluster_count)

	if best_count < MINION_CLUSTER_MIN:
		return Vector3.INF
	if _is_in_base_zone(best_centroid):
		return Vector3.INF
	return best_centroid

# Returns true if pos is within the base exclusion zone of either base.
func _is_in_base_zone(pos: Vector3) -> bool:
	# Blue base z≈+82, Red base z≈-82.  Exclude anything beyond BASE_EXCLUSION_Z.
	return abs(pos.z) >= BASE_EXCLUSION_Z

# Derives launcher_type from the node's script or name.
# Node name format: "Launcher_missile_x_z"
func _launcher_type_from_node(launcher: Node) -> String:
	var n: String = launcher.name
	# Strip "Launcher_" prefix, then extract type segment before the coords
	if not n.begins_with("Launcher_"):
		return ""
	var rest: String = n.substr(9)  # e.g. "missile_10_30"
	# Find the last two underscore-separated ints (coords) and remove them
	var parts: Array = rest.split("_")
	if parts.size() < 3:
		return ""
	# type may itself contain underscores — everything except last two parts
	var type_parts: Array = parts.slice(0, parts.size() - 2)
	var ltype: String = "launcher_" + "_".join(type_parts)
	if LauncherDefs.is_launcher_type(ltype):
		return ltype
	return ""
