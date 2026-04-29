## CompassHUD.gd
## CoD-style horizontal compass strip fixed at top-center of the Fighter's HUD.
##
## Shows:
##   - Cardinal / intercardinal bearing labels (N, NE, E, SE, S, SW, W, NW)
##   - Allied remote player positions — always visible (green circle)
##   - Enemy remote player positions  — only when within PLAYER_VISION_RADIUS (red circle)
##   - Active pings (same team only)  — purple diamond, same duration as PingHUD
##
## Wired from Main.gd via _setup_compass_hud() after FPS player spawn.
## Fighter role only.

extends Control

# ── Configuration ─────────────────────────────────────────────────────────────

## Total horizontal field-of-view the strip represents, in degrees.
const STRIP_FOV_DEG   := 120.0
## Half of STRIP_FOV_DEG — entities outside this delta are clipped.
const STRIP_FOV_HALF  := STRIP_FOV_DEG * 0.5

const STRIP_WIDTH     := 464.0   # px — matches TopCenterPanel inner width (480 - 2*8 padding)
const STRIP_HEIGHT    := 36.0    # px
const STRIP_Y         := 12.0    # px from top of screen — inside TopCenterPanel card

const TICK_MINOR_H    := 6.0     # px — minor tick (every 5°)
const TICK_MAJOR_H    := 14.0    # px — major tick (every 45°)
const TICK_THICK      := 1.0     # px

const BLIP_RADIUS     := 5.0     # px — player/ping blip circle radius
const PING_DIAMOND_S  := 5.0     # px — ping diamond half-size
const PING_END_ARROW_S := 8.0    # px — half-size of the end-of-strip arrow
const PING_END_ARROW_MARGIN := 10.0  # px inset from strip left/right edge for end arrows
const PING_DURATION   := 4.0     # seconds (match PingHUD)
const BLINK_FREQ      := 2.0     # pings per second

## Fog-of-war reveal radius — matches RTSController.PLAYER_VISION_RADIUS.
## Enemies beyond this distance are hidden on the compass.
const PLAYER_VISION_RADIUS := 35.0

# ── Colours ───────────────────────────────────────────────────────────────────

const COL_BG         := Color(0.0, 0.0, 0.0, 0.55)
const COL_TICK       := Color(0.8, 0.8, 0.8, 0.7)
const COL_LABEL      := Color(1.0, 1.0, 1.0, 0.9)
const COL_NORTH      := Color(1.0, 0.3, 0.3, 1.0)   # N label tinted red
const COL_ALLY       := Color(0.2, 1.0, 0.4, 0.9)   # green
const COL_ENEMY      := Color(1.0, 0.2, 0.2, 0.9)   # red
const COL_PING       := Color(0.62, 0.0, 1.0, 1.0)  # vivid purple

# Cardinal / intercardinal labels keyed by bearing (degrees, 0=North)
const LABELS := {
	0:   "N",
	45:  "NE",
	90:  "E",
	135: "SE",
	180: "S",
	225: "SW",
	270: "W",
	315: "NW",
}

# ── State ─────────────────────────────────────────────────────────────────────

var _player: Node3D      = null
var _camera: Camera3D    = null
var _player_team: int    = 0
var _active_pings: Array = []   # { world_pos: Vector3, age: float }

# ── Public API ────────────────────────────────────────────────────────────────

## Call once after instantiation.  player must have a Camera3D child.
func setup(player: Node3D, camera: Camera3D, player_team: int) -> void:
	_player      = player
	_camera      = camera
	_player_team = player_team

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	LobbyManager.ping_received.connect(_on_ping_received)
	set_process(true)

# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Age and expire pings
	var i: int = _active_pings.size() - 1
	while i >= 0:
		_active_pings[i]["age"] += delta
		if _active_pings[i]["age"] >= PING_DURATION:
			_active_pings.remove_at(i)
		i -= 1
	queue_redraw()

func _draw() -> void:
	if _player == null or _camera == null:
		return

	var vp_size: Vector2 = get_viewport_rect().size

	# Centre the strip horizontally at the top
	var strip_x: float = (vp_size.x - STRIP_WIDTH) * 0.5
	var strip_rect := Rect2(strip_x, STRIP_Y, STRIP_WIDTH, STRIP_HEIGHT)

	# ── Background ────────────────────────────────────────────────────────────
	draw_rect(strip_rect, COL_BG)

	# Derive bearing from camera's actual world-space forward vector.
	# This matches PingHUD's projection exactly and avoids Euler angle issues.
	var fwd: Vector3 = -_camera.global_transform.basis.z
	var cam_bearing_deg: float = rad_to_deg(atan2(-fwd.x, fwd.z))

	# ── Tick marks and labels ─────────────────────────────────────────────────
	var degrees_per_px: float = STRIP_FOV_DEG / STRIP_WIDTH

	# Snap to nearest 5° and iterate across the visible window
	var first_deg: float = cam_bearing_deg - STRIP_FOV_HALF
	var start_snap: int  = int(floor(first_deg / 5.0)) * 5

	var d: int = start_snap
	while float(d) <= cam_bearing_deg + STRIP_FOV_HALF:
		var delta_deg: float = float(d) - cam_bearing_deg
		var px: float = strip_x + STRIP_WIDTH * 0.5 + delta_deg / degrees_per_px

		if px >= strip_x and px <= strip_x + STRIP_WIDTH:
			# Normalise to [0, 360)
			var norm: int = ((d % 360) + 360) % 360
			var is_major: bool = (norm % 45) == 0
			var tick_h: float = TICK_MAJOR_H if is_major else TICK_MINOR_H
			var tick_top: float = strip_rect.position.y + STRIP_HEIGHT - tick_h
			draw_line(
				Vector2(px, tick_top),
				Vector2(px, strip_rect.position.y + STRIP_HEIGHT),
				COL_TICK,
				TICK_THICK
			)

			if is_major and LABELS.has(norm):
				var lbl: String = LABELS[norm]
				var col: Color   = COL_NORTH if norm == 0 else COL_LABEL
				var lbl_pos := Vector2(px - lbl.length() * 3.5, strip_rect.position.y + 3.0)
				draw_string(ThemeDB.fallback_font, lbl_pos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		d += 5

	# ── Player blips ──────────────────────────────────────────────────────────
	var local_pos: Vector3 = _player.global_position

	for ghost in get_tree().get_nodes_in_group("remote_players"):
		if not ghost.has_method("get") :
			continue
		var ghost_team_var = ghost.get("team")
		if ghost_team_var == null:
			continue
		var ghost_team: int = ghost_team_var as int
		var ghost_pos: Vector3 = ghost.global_position

		var is_ally: bool = ghost_team == _player_team
		if not is_ally:
			# Fog-of-war gate: only show if within vision radius
			if local_pos.distance_to(ghost_pos) > PLAYER_VISION_RADIUS:
				continue

		var blip_px: float = _world_pos_to_strip_x(ghost_pos, local_pos, cam_bearing_deg)
		if blip_px < 0.0:
			continue   # outside FOV

		var bx: float  = strip_x + blip_px
		var by: float  = strip_rect.position.y + STRIP_HEIGHT * 0.5
		var col: Color = COL_ALLY if is_ally else COL_ENEMY
		draw_circle(Vector2(bx, by), BLIP_RADIUS, col)

	# ── Ping blips ────────────────────────────────────────────────────────────
	for ping in _active_pings:
		var world_pos: Vector3 = ping["world_pos"]
		var age: float         = ping["age"]
		var t: float           = age / PING_DURATION
		var fade: float        = 1.0 - t
		var blink: float       = (sin(age * TAU * BLINK_FREQ) + 1.0) * 0.5
		var alpha: float       = fade * lerp(0.35, 1.0, blink)
		var pc: Color          = ping["color"] as Color
		var col: Color         = Color(pc.r, pc.g, pc.b, alpha)

		var blip_px: float = _world_pos_to_strip_x(world_pos, local_pos, cam_bearing_deg)

		if blip_px >= 0.0:
			# ── In-FOV: draw diamond on strip ─────────────────────────────
			var bx: float = strip_x + blip_px
			var by: float = strip_rect.position.y + STRIP_HEIGHT * 0.5
			var diamond: PackedVector2Array = PackedVector2Array([
				Vector2(bx,               by - PING_DIAMOND_S),
				Vector2(bx + PING_DIAMOND_S, by),
				Vector2(bx,               by + PING_DIAMOND_S),
				Vector2(bx - PING_DIAMOND_S, by),
			])
			draw_colored_polygon(diamond, col)
		else:
			# ── Out-of-FOV: draw end arrow pointing off-strip ─────────────
			var to: Vector3        = world_pos - local_pos
			var bearing_deg: float = rad_to_deg(atan2(to.x, to.z))
			var delta_deg: float   = _wrap_deg(bearing_deg - cam_bearing_deg)
			var by: float          = strip_rect.position.y + STRIP_HEIGHT * 0.5
			var s: float           = PING_END_ARROW_S
			var m: float           = PING_END_ARROW_MARGIN
			var arrow: PackedVector2Array
			if delta_deg < 0.0:
				# Ping is left of FOV — left-pointing arrow at strip left end
				var tip_x: float = strip_x + m
				arrow = PackedVector2Array([
					Vector2(tip_x,       by),
					Vector2(tip_x + s,   by - s * 0.6),
					Vector2(tip_x + s,   by + s * 0.6),
				])
			else:
				# Ping is right of FOV — right-pointing arrow at strip right end
				var tip_x: float = strip_x + STRIP_WIDTH - m
				arrow = PackedVector2Array([
					Vector2(tip_x,       by),
					Vector2(tip_x - s,   by - s * 0.6),
					Vector2(tip_x - s,   by + s * 0.6),
				])
			draw_colored_polygon(arrow, col)

# ── Helpers ───────────────────────────────────────────────────────────────────

## Convert a world position to a pixel X offset (0 = strip left edge).
## Returns -1.0 if outside the ±STRIP_FOV_HALF window.
func _world_pos_to_strip_x(world_pos: Vector3, from_pos: Vector3, cam_bearing_deg: float) -> float:
	var to: Vector3         = world_pos - from_pos
	var bearing_rad: float  = atan2(to.x, to.z)
	var bearing_deg: float  = rad_to_deg(bearing_rad)
	var delta: float        = _wrap_deg(bearing_deg - cam_bearing_deg)

	if delta < -STRIP_FOV_HALF or delta > STRIP_FOV_HALF:
		return -1.0

	return STRIP_WIDTH * 0.5 + delta * (STRIP_WIDTH / STRIP_FOV_DEG)

## Wrap angle in degrees to [-180, 180].
func _wrap_deg(d: float) -> float:
	d = fmod(d, 360.0)
	if d > 180.0:
		d -= 360.0
	elif d < -180.0:
		d += 360.0
	return d

# ── Signal handler ────────────────────────────────────────────────────────────

func _on_ping_received(world_pos: Vector3, team: int, color: Color = COL_PING) -> void:
	if team != _player_team:
		return
	_active_pings.append({"world_pos": world_pos, "age": 0.0, "color": color})
