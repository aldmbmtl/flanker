extends Node

const MINION_SCENE        := "res://scenes/minions/Minion.tscn"
const CANNON_MINION_SCENE := "res://scenes/minions/CannonMinion.tscn"
const HEALER_MINION_SCENE := "res://scenes/minions/HealerMinion.tscn"

const WAVE_INTERVAL := 20.0
const MAX_WAVE_SIZE := 6
const MINION_STAGGER := 0.0  # seconds between each minion in a wave
const SYNC_INTERVAL := 3     # physics frames between position broadcasts

# ── Model chars per minion type, indexed by tier (0, 1, 2) ───────────────────
# basic:  j → m → r
# cannon: d → g → h
# healer: i → n → q
const BASIC_CHARS:  Array[String] = ["j", "m", "r"]
const CANNON_CHARS: Array[String] = ["d", "g", "h"]
const HEALER_CHARS: Array[String] = ["i", "n", "q"]

var wave_number := 0
var wave_timer := 0.0
var _minion_counter: int = 0
var _minion_node_cache: Dictionary = {}  # minion_id -> Node

# Per-team lane boosts: _lane_boosts[team][lane_i] = extra minions to spawn next wave.
# Set via boost_lane() / boost_all_lanes(). Consumed (reset to 0) after each wave fires.
var _lane_boosts: Array = [[0, 0, 0], [0, 0, 0]]
var _sync_frame: int = 0
var _last_synced_next_in: int = -1

# s_minion_revive: once-per-wave flag per team. True = revive already used this wave.
var _revive_used: Dictionary = {0: false, 1: false}

var _minion_scene: PackedScene = null
var _cannon_scene: PackedScene = null
var _healer_scene: PackedScene = null
var _main: Node = null

func _ready() -> void:
	_minion_scene = load(MINION_SCENE)
	_cannon_scene = load(CANNON_MINION_SCENE)
	_healer_scene = load(HEALER_MINION_SCENE)
	_main = get_node_or_null("/root/Main")
	_minion_node_cache.clear()
	_minion_counter = 0

func _physics_process(_delta: float) -> void:
	if NetworkManager._peer != null and not multiplayer.is_server():
		return
	_sync_frame += 1
	if _sync_frame >= SYNC_INTERVAL:
		_sync_frame = 0
		_broadcast_minion_states()

const SYNC_CHUNK_SIZE := 50  # max minions per RPC packet (stays under MTU)

func _broadcast_minion_states() -> void:
	if _minion_node_cache.is_empty():
		return
	var ids:       PackedInt32Array   = PackedInt32Array()
	var positions: PackedVector3Array = PackedVector3Array()
	var rotations: PackedFloat32Array = PackedFloat32Array()
	var healths:   PackedFloat32Array = PackedFloat32Array()
	var stale: Array = []
	for mid in _minion_node_cache.keys():
		var m = _minion_node_cache.get(mid)
		if not is_instance_valid(m):
			stale.append(mid)
			continue
		var mn: Node = m as Node
		ids.append(mid as int)
		positions.append(mn.global_position)
		rotations.append(mn.rotation.y)
		healths.append(mn.get("health") as float)
	for mid in stale:
		_minion_node_cache.erase(mid)
	if ids.is_empty():
		return
	var total: int = ids.size()
	var offset: int = 0
	while offset < total:
		var end: int = min(offset + SYNC_CHUNK_SIZE, total)
		LobbyManager.sync_minion_states.rpc(
			ids.slice(offset, end),
			positions.slice(offset, end),
			rotations.slice(offset, end),
			healths.slice(offset, end)
		)
		offset = end

func _process(delta: float) -> void:
	if NetworkManager._peer != null and not multiplayer.is_server():
		return
	wave_timer += delta
	# Update countdown label
	if _main and _main.has_method("update_wave_info"):
		var next_in := int(WAVE_INTERVAL - wave_timer) + 1
		_main.update_wave_info(wave_number, next_in)
		if next_in != _last_synced_next_in:
			_last_synced_next_in = next_in
			LobbyManager.sync_wave_info.rpc(wave_number, next_in)

	if wave_timer >= WAVE_INTERVAL:
		wave_timer = 0.0
		wave_number += 1
		_last_synced_next_in = -1
		# Reset once-per-wave revive flag for both teams
		_revive_used[0] = false
		_revive_used[1] = false
		_launch_wave()

func _launch_wave() -> void:
	if _main and _main.has_method("show_wave_announcement"):
		_main.show_wave_announcement(wave_number)
		LobbyManager.sync_wave_announcement.rpc(wave_number)

	var base_count: int = min(wave_number, MAX_WAVE_SIZE)
	for lane_i in range(3):
		for team in range(2):
			var extra: int = _lane_boosts[team][lane_i]
			var count: int = base_count + extra
			# Determine wave composition.
			# Slots 0-3 = basic, slot 4 = cannon (wave ≥ 5), slot 5 = healer (wave = 6+).
			# Smaller waves fill from the start of the slot list.
			var i: int = 0
			while i < count:
				var mtype: String
				if i <= 3:
					mtype = "basic"
				elif i == 4:
					mtype = "cannon"
				else:
					mtype = "healer"
				var delay: float = i * MINION_STAGGER
				_spawn_minion_delayed(team, lane_i, delay, mtype)
				i += 1

	# Reset all boosts after the wave launches and broadcast zeroes to all peers
	_lane_boosts = [[0, 0, 0], [0, 0, 0]]
	LobbyManager.sync_lane_boosts.rpc([0, 0, 0], [0, 0, 0])

# ── Lane boost API ────────────────────────────────────────────────────────────

## Adds `amount` extra minions for `team` on `lane_i` for the next wave.
## Called server-side only.
func boost_lane(team: int, lane_i: int, amount: int) -> void:
	if lane_i < 0 or lane_i > 2:
		return
	if team < 0 or team > 1:
		return
	_lane_boosts[team][lane_i] += amount

## Adds 1 extra minion per lane for `team` on the next wave.
## Called server-side only.
func boost_all_lanes(team: int) -> void:
	if team < 0 or team > 1:
		return
	for lane_i in range(3):
		_lane_boosts[team][lane_i] += 1

func _spawn_minion_delayed(team: int, lane_i: int, delay: float, mtype: String = "basic") -> void:
	if delay <= 0.0:
		_spawn_minion(team, lane_i, mtype)
	else:
		await get_tree().create_timer(delay).timeout
		_spawn_minion(team, lane_i, mtype)

func _spawn_minion(team: int, lane_i: int, mtype: String = "basic") -> void:
	var waypts: Array[Vector3] = LaneData.get_lane_waypoints(lane_i, team)
	var spawn_pos := Vector3(waypts[0].x, 0.0, waypts[0].z)
	spawn_pos.y = _get_terrain_height(spawn_pos) + 1.0
	_minion_counter += 1
	var minion_id: int = _minion_counter
	_spawn_at_position(team, spawn_pos, waypts, lane_i, minion_id, mtype)

	if multiplayer.is_server():
		LobbyManager.spawn_minion_visuals.rpc(team, spawn_pos, waypts, lane_i, minion_id)

func _spawn_at_position(team: int, pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int, mtype: String = "basic") -> void:
	# Pick scene based on minion type.
	var scene: PackedScene
	match mtype:
		"cannon":
			if _cannon_scene == null:
				_cannon_scene = load(CANNON_MINION_SCENE)
			scene = _cannon_scene
		"healer":
			if _healer_scene == null:
				_healer_scene = load(HEALER_MINION_SCENE)
			scene = _healer_scene
		_:
			if _minion_scene == null:
				_minion_scene = load(MINION_SCENE)
			scene = _minion_scene

	var minion: CharacterBody3D = scene.instantiate()
	minion.set("team", team)
	minion.set("_minion_id", minion_id)
	minion.name = "Minion_%d" % minion_id
	minion.position = pos

	# Apply Supporter passive bonuses and model tier before add_child.
	var sup: int = LobbyManager.get_supporter_peer(team)
	_apply_type_bonuses(minion, mtype, sup)
	_apply_tier_model(minion, mtype, sup)

	get_tree().root.get_node("Main").add_child(minion)
	minion.setup(team, waypts, lane_i)
	_minion_node_cache[minion_id] = minion

## Apply stat bonuses from skill tier passives per minion type.
func _apply_type_bonuses(minion: CharacterBody3D, mtype: String, sup: int) -> void:
	if sup <= 0:
		return
	match mtype:
		"basic":
			# s_basic_t1: +20% HP per tier point (basic_tier sums to 1 or 2 when unlocked)
			var tier: float = SkillTree.get_passive_bonus(sup, "basic_tier")
			if tier >= 1.0:
				var base_hp: float = float(minion.get("max_health") if minion.get("max_health") != null else 60.0)
				minion.set("max_health", base_hp * 1.20)
			if tier >= 2.0:
				var base_dmg: float = float(minion.get("attack_damage") if minion.get("attack_damage") != null else 8.0)
				minion.set("attack_damage", base_dmg * 1.20)
		"cannon":
			var tier: float = SkillTree.get_passive_bonus(sup, "cannon_tier")
			if tier >= 1.0:
				var base_dmg: float = float(minion.get("attack_damage") if minion.get("attack_damage") != null else 40.0)
				minion.set("attack_damage", base_dmg * 1.25)
			if tier >= 2.0:
				var base_range: float = float(minion.get("shoot_range") if minion.get("shoot_range") != null else 25.0)
				minion.set("shoot_range", base_range * 1.30)
				# detect_range must exceed shoot_range
				minion.set("detect_range", minion.get("shoot_range") * 1.12)
		"healer":
			var tier: float = SkillTree.get_passive_bonus(sup, "healer_tier")
			if tier >= 1.0:
				var base_amt: float = float(minion.get("heal_amount") if minion.get("heal_amount") != null else 10.0)
				minion.set("heal_amount", base_amt + 5.0)
			if tier >= 2.0:
				var base_rad: float = float(minion.get("heal_radius") if minion.get("heal_radius") != null else 8.0)
				minion.set("heal_radius", base_rad + 4.0)

## Pick the model chars for this minion's team and type based on skill tier.
## Sets MinionBase static chars so _build_visuals() loads the right GLB.
## NOTE: This overwrites the global static chars; they are set immediately before
## add_child so the next _build_visuals() call sees the right char.
func _apply_tier_model(minion: CharacterBody3D, mtype: String, sup: int) -> void:
	var tier_sum: float = 0.0
	if sup > 0:
		match mtype:
			"basic":
				tier_sum = SkillTree.get_passive_bonus(sup, "basic_tier")
			"cannon":
				tier_sum = SkillTree.get_passive_bonus(sup, "cannon_tier")
			"healer":
				tier_sum = SkillTree.get_passive_bonus(sup, "healer_tier")

	# tier_sum: 0.0 = base, 1.0 = mid, ≥2.0 = max
	var tier_idx: int = clampi(int(tier_sum), 0, 2)

	var chars: Array[String]
	match mtype:
		"basic":
			chars = BASIC_CHARS
		"cannon":
			chars = CANNON_CHARS
		"healer":
			chars = HEALER_CHARS
		_:
			chars = BASIC_CHARS

	# Each team gets the same tier char for this type.
	# Blue = team 0, Red = team 1 — both use the same aesthetic family.
	var ch: String = chars[tier_idx]
	# We store the chars on the minion itself via a helper so other minions
	# spawning in parallel don't clobber each other's global static.
	minion.set("_spawn_blue_char", ch)
	minion.set("_spawn_red_char", ch)

func spawn_for_network(team: int, pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int) -> void:
	_spawn_at_position(team, pos, waypts, lane_i, minion_id, "basic")
	# Mark as puppet — server drives position
	var minion: Node = _minion_node_cache.get(minion_id)
	if minion == null:
		minion = get_tree().root.get_node_or_null("Main/Minion_%d" % minion_id)
	if minion != null:
		minion.set("is_puppet", true)
		minion.set("velocity", Vector3.ZERO)
		minion.set("_puppet_target_pos", pos)
	else:
		push_warning("MinionSpawner: spawn_for_network id=%d node not found" % minion_id)

func get_minion_by_id(minion_id: int) -> Node:
	return _minion_node_cache.get(minion_id, null)

func kill_minion_by_id(minion_id: int) -> void:
	var minion: Node = _minion_node_cache.get(minion_id)
	_minion_node_cache.erase(minion_id)
	if minion != null and is_instance_valid(minion) and minion.has_method("force_die"):
		minion.force_die()

func get_terrain_height(pos: Vector3) -> float:
	return _get_terrain_height(pos)

func _get_terrain_height(pos: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var from: Vector3 = Vector3(pos.x, 50.0, pos.z)
	var to: Vector3 = Vector3(pos.x, -10.0, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result.position.y
