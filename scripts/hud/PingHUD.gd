## PingHUD.gd
## Full-screen transparent Control overlay that draws a blinking purple diamond
## (or edge arrow when off-screen) above each active ping position.
## Also spawns a tall white-core/purple-glow 3D beam at each ping location.
##
## Wired from Main.gd via _setup_ping_hud() after role selection.
## Receives pings via LobbyManager.ping_received signal and filters to
## the local player's team only.

extends Control

# ── Configuration ─────────────────────────────────────────────────────────────

const PING_DURATION   := 4.0    # seconds until a ping expires
const BLINK_FREQ      := 2.0    # blinks per second
const DIAMOND_SIZE    := 14.0   # half-width of the on-screen diamond in pixels
const RING_RADIUS_MIN := 20.0   # inner ring radius at ping birth
const RING_RADIUS_MAX := 34.0   # outer ring radius at ping death
const RING_THICKNESS  := 1.5    # ring stroke width in pixels
const HOVER_HEIGHT    := 0.8    # world units above terrain the icon floats
const EDGE_MARGIN     := 30.0   # px from screen edge for the off-screen arrow
const ARROW_SIZE      := 22.0   # half-size of edge arrow triangle in pixels

const BEAM_HEIGHT     := 80.0   # world units tall
const BEAM_RADIUS_CORE := 0.08  # inner white cylinder radius
const BEAM_RADIUS_GLOW := 0.45  # outer purple glow cylinder radius

const COL_PING  := Color(0.62, 0.0, 1.0, 1.0)   # vivid purple
const COL_WHITE := Color(1.0,  1.0, 1.0, 1.0)   # beam core

# ── State ─────────────────────────────────────────────────────────────────────

var _player_team: int = 0
var _active_pings: Array = []   # each entry: {world_pos: Vector3, age: float}

# ── Public API ────────────────────────────────────────────────────────────────

func setup(player_team: int) -> void:
	_player_team = player_team
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	LobbyManager.ping_received.connect(_on_ping_received)
	set_process(true)

# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var i: int = _active_pings.size() - 1
	while i >= 0:
		_active_pings[i]["age"] += delta
		if _active_pings[i]["age"] >= PING_DURATION:
			_active_pings.remove_at(i)
		i -= 1
	if _active_pings.size() > 0:
		queue_redraw()

func _draw() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var vp_size: Vector2 = get_viewport_rect().size
	var center: Vector2  = vp_size * 0.5

	for ping in _active_pings:
		var world_pos: Vector3 = (ping["world_pos"] as Vector3) + Vector3(0.0, HOVER_HEIGHT, 0.0)

		var age: float  = ping["age"]
		var t: float    = age / PING_DURATION
		var fade: float = 1.0 - t

		var blink: float = (sin(age * TAU * BLINK_FREQ) + 1.0) * 0.5
		var alpha: float = fade * lerp(0.35, 1.0, blink)
		var col: Color   = Color(COL_PING.r, COL_PING.g, COL_PING.b, alpha)

		var is_behind: bool   = camera.is_position_behind(world_pos)
		var screen_pos: Vector2 = camera.unproject_position(world_pos)

		# When behind camera, unproject mirrors around center — flip to get the
		# correct edge direction.
		if is_behind:
			screen_pos = center + (center - screen_pos)

		var on_screen: bool = (
			not is_behind and
			screen_pos.x >= EDGE_MARGIN and screen_pos.x <= vp_size.x - EDGE_MARGIN and
			screen_pos.y >= EDGE_MARGIN and screen_pos.y <= vp_size.y - EDGE_MARGIN
		)

		if on_screen:
			# ── Filled diamond ────────────────────────────────────────────
			var diamond: PackedVector2Array = PackedVector2Array([
				screen_pos + Vector2(0.0,           -DIAMOND_SIZE),
				screen_pos + Vector2(DIAMOND_SIZE,   0.0),
				screen_pos + Vector2(0.0,            DIAMOND_SIZE),
				screen_pos + Vector2(-DIAMOND_SIZE,  0.0),
			])
			draw_colored_polygon(diamond, col)

			# ── Expanding pulse ring ──────────────────────────────────────
			var ring_r: float   = lerp(RING_RADIUS_MIN, RING_RADIUS_MAX, t)
			var ring_col: Color = Color(COL_PING.r, COL_PING.g, COL_PING.b, fade * 0.55)
			draw_arc(screen_pos, ring_r, 0.0, TAU, 48, ring_col, RING_THICKNESS)
		else:
			# ── Edge arrow ────────────────────────────────────────────────
			var dir: Vector2  = (screen_pos - center).normalized()
			var edge: Vector2 = _clamp_to_screen_edge(center, dir, vp_size, EDGE_MARGIN)

			# Tip points toward the off-screen ping; base is two perpendicular points.
			var perp: Vector2  = Vector2(-dir.y, dir.x)
			var tip: Vector2   = edge + dir * ARROW_SIZE
			var base_l: Vector2 = edge - perp * ARROW_SIZE * 0.6
			var base_r: Vector2 = edge + perp * ARROW_SIZE * 0.6

			var arrow: PackedVector2Array = PackedVector2Array([tip, base_l, base_r])
			draw_colored_polygon(arrow, col)

# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns the point along `center + dir * t` that first reaches a screen edge,
## inset by `margin` pixels on all sides.
func _clamp_to_screen_edge(center: Vector2, dir: Vector2, vp_size: Vector2, margin: float) -> Vector2:
	var min_x: float = margin
	var max_x: float = vp_size.x - margin
	var min_y: float = margin
	var max_y: float = vp_size.y - margin

	var t_vals: Array = []
	if dir.x > 0.0001:
		t_vals.append((max_x - center.x) / dir.x)
	elif dir.x < -0.0001:
		t_vals.append((min_x - center.x) / dir.x)
	if dir.y > 0.0001:
		t_vals.append((max_y - center.y) / dir.y)
	elif dir.y < -0.0001:
		t_vals.append((min_y - center.y) / dir.y)

	var best_t: float = 1e9
	for tv in t_vals:
		var fv: float = tv as float
		if fv > 0.0 and fv < best_t:
			best_t = fv

	return center + dir * best_t

# ── Signal handler ────────────────────────────────────────────────────────────

func _on_ping_received(world_pos: Vector3, team: int) -> void:
	if team != _player_team:
		return
	_active_pings.append({"world_pos": world_pos, "age": 0.0})
	_spawn_ping_beam(world_pos)

# ── 3D beam ───────────────────────────────────────────────────────────────────

func _spawn_ping_beam(world_pos: Vector3) -> void:
	var scene_root: Node = get_tree().root.get_child(0)

	# Root node for the whole beam — add to tree first, then set position
	var beam_node: Node3D = Node3D.new()
	scene_root.add_child(beam_node)
	beam_node.global_position = world_pos + Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)

	# ── Inner white core ──────────────────────────────────────────────────────
	var core_mesh: CylinderMesh = CylinderMesh.new()
	core_mesh.top_radius    = BEAM_RADIUS_CORE
	core_mesh.bottom_radius = BEAM_RADIUS_CORE
	core_mesh.height        = BEAM_HEIGHT

	var core_mat: StandardMaterial3D = StandardMaterial3D.new()
	core_mat.albedo_color        = COL_WHITE
	core_mat.emission_enabled    = true
	core_mat.emission            = COL_WHITE
	core_mat.emission_energy_multiplier = 4.0
	core_mat.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency        = BaseMaterial3D.TRANSPARENCY_DISABLED
	core_mat.no_depth_test       = false

	var core_inst: MeshInstance3D = MeshInstance3D.new()
	core_inst.mesh = core_mesh
	core_inst.material_override = core_mat
	core_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_node.add_child(core_inst)

	# ── Outer purple glow ─────────────────────────────────────────────────────
	var glow_mesh: CylinderMesh = CylinderMesh.new()
	glow_mesh.top_radius    = BEAM_RADIUS_GLOW
	glow_mesh.bottom_radius = BEAM_RADIUS_GLOW
	glow_mesh.height        = BEAM_HEIGHT

	var glow_mat: StandardMaterial3D = StandardMaterial3D.new()
	glow_mat.albedo_color        = Color(COL_PING.r, COL_PING.g, COL_PING.b, 0.35)
	glow_mat.emission_enabled    = true
	glow_mat.emission            = COL_PING
	glow_mat.emission_energy_multiplier = 2.0
	glow_mat.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.cull_mode           = BaseMaterial3D.CULL_DISABLED
	glow_mat.no_depth_test       = false

	var glow_inst: MeshInstance3D = MeshInstance3D.new()
	glow_inst.mesh = glow_mesh
	glow_inst.material_override = glow_mat
	glow_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_node.add_child(glow_inst)

	# ── OmniLight at base ─────────────────────────────────────────────────────
	var light: OmniLight3D = OmniLight3D.new()
	light.position       = Vector3(0.0, -BEAM_HEIGHT * 0.5 + 1.0, 0.0)
	light.light_color    = COL_PING
	light.light_energy   = 3.0
	light.omni_range     = 14.0
	light.shadow_enabled = false
	beam_node.add_child(light)

	# ── Tween: fade everything out over PING_DURATION, then free ─────────────
	var tw: Tween = beam_node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(core_mat, "emission_energy_multiplier", 0.0, PING_DURATION)
	tw.tween_property(glow_mat, "emission_energy_multiplier", 0.0, PING_DURATION)
	tw.tween_property(light,    "light_energy",               0.0, PING_DURATION)
	# Alpha fade on the glow layer
	tw.tween_method(
		func(a: float) -> void:
			glow_mat.albedo_color = Color(COL_PING.r, COL_PING.g, COL_PING.b, a),
		0.35, 0.0, PING_DURATION
	)
	tw.set_parallel(false)
	tw.tween_callback(beam_node.queue_free)
