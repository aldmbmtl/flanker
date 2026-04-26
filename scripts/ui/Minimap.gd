extends Control

const MAP_RADIUS        := 100.0   # half of 200×200 world
const MAP_SCALE_FRAC    := 0.09    # 9% of viewport width
const MAP_SIZE_MIN      := 150.0
const MAP_SIZE_MAX      := 500.0
const TERRAIN_IMG_SIZE  := 256     # baked terrain texture resolution

# Colors
const COL_BG            := Color(0.0,  0.0,  0.0,  0.55)
const COL_BORDER        := Color(0.8,  0.8,  0.8,  0.6)
const COL_BLUE_BASE     := Color(0.2,  0.4,  1.0,  0.9)
const COL_RED_BASE      := Color(1.0,  0.2,  0.2,  0.9)
const COL_BLUE_MINION   := Color(0.3,  0.55, 1.0,  1.0)
const COL_RED_MINION    := Color(1.0,  0.35, 0.35, 1.0)
const COL_PLAYER        := Color(1.0,  1.0,  1.0,  1.0)
const COL_BLUE_TOWER    := Color(0.1,  0.6,  1.0,  1.0)
const COL_RED_TOWER     := Color(1.0,  0.4,  0.1,  1.0)
const COL_WEAPON_PICKUP := Color(1.0,  0.85, 0.0,  1.0)   # yellow
const COL_HEALTHPACK    := Color(0.15, 0.9,  0.15, 1.0)   # green
const COL_HEALSTATION   := Color(0.0,  0.95, 0.85, 1.0)   # cyan

const COL_FOG           := Color(0.0,  0.0,  0.0,  0.72)   # fog overlay cell

const FOG_CELL_PX       := 4   # pixel size of each fog cell
const REDRAW_INTERVAL   := 0.05  # 20 fps

# Computed at runtime
var _map_size: float = MAP_SIZE_MIN

# Pre-baked lane pixel arrays — recomputed when _map_size changes
var _lane_pixels: Array = []

var _blue_base_px: Vector2
var _red_base_px: Vector2

var _redraw_timer: float = 0.0
var _rts_cam: Camera3D = null
var _main: Node = null

var _terrain_tex: ImageTexture = null   # baked terrain image


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_recalc_size()

	var main_root = get_tree().root.get_node_or_null("Main")
	if main_root:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			pass  # resolved per-frame via group

	_rts_cam = get_node_or_null("/root/Main/RTSCamera")
	_main    = get_node_or_null("/root/Main")

	# Bake terrain texture (TerrainGenerator runs in _ready before us since it's higher in the tree)
	var terrain = get_node_or_null("/root/Main/World/Terrain")
	if terrain and terrain.has_method("bake_minimap_image"):
		var img: Image = terrain.bake_minimap_image(TERRAIN_IMG_SIZE)
		_terrain_tex = ImageTexture.create_from_image(img)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_WM_SIZE_CHANGED:
		_recalc_size()


func _recalc_size() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var new_size: float = clamp(vp_size.x * MAP_SCALE_FRAC, MAP_SIZE_MIN, MAP_SIZE_MAX)
	if abs(new_size - _map_size) < 0.5:
		return
	_map_size = new_size
	custom_minimum_size = Vector2(_map_size, _map_size)

	# Resize the parent MinimapPanel so it follows
	var panel := get_parent()
	if panel:
		panel.custom_minimum_size = Vector2(_map_size + 4.0, _map_size + 4.0)
		# Re-anchor panel: top-right corner, 8px from right edge, 48px from top
		panel.offset_left   = -(panel.custom_minimum_size.x + 8.0)
		panel.offset_right  = -8.0
		panel.offset_top    = 48.0
		panel.offset_bottom = 48.0 + panel.custom_minimum_size.y

	_bake_lane_pixels()
	_blue_base_px = _world_to_map(Vector2(0.0,  84.0))
	_red_base_px  = _world_to_map(Vector2(0.0, -84.0))


func _bake_lane_pixels() -> void:
	_lane_pixels.clear()
	for i in range(3):
		var pts: Array = LaneData.get_lane_points(i)
		var px_arr: Array[Vector2] = []
		for p in pts:
			px_arr.append(_world_to_map(Vector2(p.x, p.y)))
		_lane_pixels.append(px_arr)


func _process(delta: float) -> void:
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		queue_redraw()


func _draw() -> void:
	var sz: float = _map_size
	var r: Rect2 = Rect2(Vector2.ZERO, Vector2(sz, sz))

	# ── Cache group arrays once for the entire draw call ─────────────────────
	var all_minions: Array = get_tree().get_nodes_in_group("minions")
	var all_towers: Array  = get_tree().get_nodes_in_group("towers")
	var fps_players: Array = get_tree().get_nodes_in_group("player")
	var player_team: int   = _main.get("player_start_team") if _main != null and _main.get("player_start_team") != null else 0

	# ── Background / terrain ──────────────────────────────────────────────────
	if _terrain_tex != null:
		draw_texture_rect(_terrain_tex, r, false, Color(1.0, 1.0, 1.0, 0.85))
	else:
		draw_rect(r, COL_BG)

	# ── Lane lines (drawn on top of terrain for clarity) ──────────────────────
	for lane_px in _lane_pixels:
		if lane_px.size() >= 2:
			draw_polyline(lane_px, Color(0.65, 0.52, 0.22, 0.55), 1.5)

	# ── Base markers ──────────────────────────────────────────────────────────
	var base_half := Vector2(5.0, 5.0)
	draw_rect(Rect2(_blue_base_px - base_half, base_half * 2.0), COL_BLUE_BASE)
	draw_rect(Rect2(_red_base_px  - base_half, base_half * 2.0), COL_RED_BASE)

	# ── Fog of war overlay ────────────────────────────────────────────────────
	_draw_fog_overlay(fps_players, all_minions, all_towers, player_team)

	# ── Pickup icons ──────────────────────────────────────────────────────────
	# Weapon pickups — yellow diamond
	for wp in get_tree().get_nodes_in_group("weapon_pickups"):
		if not is_instance_valid(wp):
			continue
		var gp: Vector3 = (wp as Node3D).global_position
		var px: Vector2 = _world_to_map(Vector2(gp.x, gp.z))
		if _in_bounds(px):
			_draw_diamond(px, 4.5, COL_WEAPON_PICKUP)

	# Supporter drops — healthpack (green cross) vs heal station (cyan ring)
	for drop in get_tree().get_nodes_in_group("supporter_drops"):
		if not is_instance_valid(drop):
			continue
		var gp: Vector3 = (drop as Node3D).global_position
		var px: Vector2 = _world_to_map(Vector2(gp.x, gp.z))
		if not _in_bounds(px):
			continue
		if drop.has_method("take_damage"):
			# HealStation — cyan filled circle with dark ring
			draw_circle(px, 4.5, COL_HEALSTATION)
			draw_arc(px, 5.5, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.7), 1.2)
		else:
			# HealthPackPickup — green cross
			_draw_cross(px, 4.5, COL_HEALTHPACK)

	# ── Minion dots ───────────────────────────────────────────────────────────
	for minion in all_minions:
		if not is_instance_valid(minion):
			continue
		var gp: Vector3 = minion.global_position
		var team: int = minion.get("team") if minion.get("team") != null else 0
		if _is_fogged(gp, team, player_team, fps_players, all_minions):
			continue
		var px: Vector2 = _world_to_map(Vector2(gp.x, gp.z))
		if _in_bounds(px):
			var col: Color = COL_BLUE_MINION if team == 0 else COL_RED_MINION
			draw_circle(px, 2.5, col)

	# ── Tower dots ────────────────────────────────────────────────────────────
	for tower in all_towers:
		if not is_instance_valid(tower):
			continue
		var tower_team: int = tower.get("team") if tower.get("team") != null else 0
		var tp: Vector3 = (tower as Node3D).global_position
		if _is_fogged(tp, tower_team, player_team, fps_players, all_minions):
			continue
		var px: Vector2 = _world_to_map(Vector2(tp.x, tp.z))
		if _in_bounds(px):
			var tower_col: Color = COL_BLUE_TOWER if tower_team == 0 else COL_RED_TOWER
			draw_circle(px, 3.5, tower_col)
			draw_arc(px, 4.5, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.5), 1.0)

	# ── Player arrow ──────────────────────────────────────────────────────────
	var local_player: CharacterBody3D = null
	for p in fps_players:
		if p.get("_is_local") == true:
			local_player = p
			break
	if local_player == null and fps_players.size() > 0:
		local_player = fps_players[0]

	if is_instance_valid(local_player):
		var pp: Vector3 = local_player.global_position
		var px: Vector2 = _world_to_map(Vector2(pp.x, pp.z))
		if _in_bounds(px):
			# Forward direction: -basis.z is facing direction in Godot
			var fwd3: Vector3 = -local_player.global_transform.basis.z
			var angle: float = atan2(fwd3.x, fwd3.z)  # rotation in XZ plane
			_draw_arrow(px, angle, 10.0, COL_PLAYER)

	# ── Border ────────────────────────────────────────────────────────────────
	draw_rect(r, COL_BORDER, false, 1.5)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _draw_fog_overlay(fps_players: Array, all_minions: Array, all_towers: Array, player_team: int) -> void:
	if _main == null:
		return

	# Collect vision circle centres (world XZ) and their squared radii
	# Sources: local player (35u), friendly minions (25u), friendly towers (20u)
	var sources: Array = []   # each entry: [world_x, world_z, r_sq]

	for p in fps_players:
		if p.get("_is_local") != true:
			continue
		if is_instance_valid(p):
			var gp: Vector3 = (p as Node3D).global_position
			sources.append([gp.x, gp.z, 35.0 * 35.0])

	for minion in all_minions:
		if not is_instance_valid(minion):
			continue
		if minion.get("team") != player_team:
			continue
		var gp: Vector3 = minion.global_position
		sources.append([gp.x, gp.z, 25.0 * 25.0])

	for tower in all_towers:
		if not is_instance_valid(tower):
			continue
		if tower.get("team") != player_team:
			continue
		var tp: Vector3 = (tower as Node3D).global_position
		sources.append([tp.x, tp.z, 20.0 * 20.0])

	var cell: float = float(FOG_CELL_PX)
	var cell_sz := Vector2(cell, cell)
	var cells: int = int(ceil(_map_size / cell))

	for cy in range(cells):
		for cx in range(cells):
			# World position at cell centre
			var px: float = (float(cx) + 0.5) * cell
			var pz: float = (float(cy) + 0.5) * cell
			# pixel → normalised → world
			var wx: float = ((px / _map_size) - 0.5) * (MAP_RADIUS * 2.0)
			var wz: float = ((pz / _map_size) - 0.5) * (MAP_RADIUS * 2.0)
			var visible: bool = false
			for src in sources:
				var dx: float = wx - src[0]
				var dz: float = wz - src[1]
				if dx * dx + dz * dz <= src[2]:
					visible = true
					break
			if not visible:
				draw_rect(Rect2(Vector2(float(cx) * cell, float(cy) * cell), cell_sz), COL_FOG)


func _draw_arrow(center: Vector2, angle: float, size: float, col: Color) -> void:
	# tip forward, two back corners
	var tip:  Vector2 = center + Vector2(sin(angle),        cos(angle))        * size
	var bl:   Vector2 = center + Vector2(sin(angle + 2.4),  cos(angle + 2.4))  * size * 0.7
	var br:   Vector2 = center + Vector2(sin(angle - 2.4),  cos(angle - 2.4))  * size * 0.7
	var pts := PackedVector2Array([tip, bl, br])
	# dark outline
	draw_polygon(pts, PackedColorArray([Color(0,0,0,0.7), Color(0,0,0,0.7), Color(0,0,0,0.7)]))
	var inset: float = 1.8
	var tip2: Vector2  = center + Vector2(sin(angle),        cos(angle))        * (size - inset)
	var bl2:  Vector2  = center + Vector2(sin(angle + 2.4),  cos(angle + 2.4))  * (size - inset) * 0.7
	var br2:  Vector2  = center + Vector2(sin(angle - 2.4),  cos(angle - 2.4))  * (size - inset) * 0.7
	var pts2 := PackedVector2Array([tip2, bl2, br2])
	draw_polygon(pts2, PackedColorArray([col, col, col]))


func _draw_diamond(center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0.0,  -r),
		center + Vector2(r,    0.0),
		center + Vector2(0.0,   r),
		center + Vector2(-r,   0.0),
	])
	draw_polygon(pts, PackedColorArray([col, col, col, col]))


func _draw_cross(center: Vector2, r: float, col: Color) -> void:
	var h: float = r
	var w: float = r * 0.45
	# horizontal bar
	draw_rect(Rect2(center - Vector2(h, w), Vector2(h * 2.0, w * 2.0)), col)
	# vertical bar
	draw_rect(Rect2(center - Vector2(w, h), Vector2(w * 2.0, h * 2.0)), col)


# Convert world XZ (as Vector2(x, z)) to minimap pixel coords.
func _world_to_map(xz: Vector2) -> Vector2:
	var nx: float = (xz.x / MAP_RADIUS) * 0.5 + 0.5
	var nz: float = (xz.y / MAP_RADIUS) * 0.5 + 0.5
	return Vector2(nx * _map_size, nz * _map_size)


func _in_bounds(px: Vector2) -> bool:
	return px.x >= 0.0 and px.x <= _map_size and px.y >= 0.0 and px.y <= _map_size


# Returns true if the position should be hidden (enemy outside vision range).
# Applied in BOTH FPS and RTS modes.
func _is_fogged(world_pos: Vector3, node_team: int, player_team: int, fps_players: Array, all_minions: Array) -> bool:
	if _main == null:
		return false
	if node_team == player_team:
		return false  # always show friendlies

	# Check local player vision
	for p in fps_players:
		if p.get("_is_local") != true:
			continue
		if is_instance_valid(p):
			if world_pos.distance_squared_to((p as Node3D).global_position) <= 35.0 * 35.0:
				return false

	# Check friendly minion vision
	for minion in all_minions:
		if not is_instance_valid(minion):
			continue
		if minion.get("team") != player_team:
			continue
		if world_pos.distance_squared_to(minion.global_position) <= 25.0 * 25.0:
			return false

	return true
