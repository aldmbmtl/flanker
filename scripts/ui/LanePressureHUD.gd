extends Control
## LanePressureHUD — shows territory push/rollback warnings and advance counters.
##
## Warning mode (enemy pushing OUR limit):
##   Flashing red/orange panel at top-center:
##   "⚠ LIMIT UNDER PRESSURE  [ Xs ]"
##   Flash rate increases as timer approaches PUSH_TIME.
##
## Advance mode (WE are pushing THEIR limit):
##   Green panel with progress bar:
##   "▶ ADVANCING  [████░░░]  Xs"
##
## Banner mode (on push/rollback event):
##   Centered full-width banner that fades out over 3s.
##
## Added to $HUD for both Fighter and Supporter roles.

const PUSH_TIME:     float = 120.0
const ROLLBACK_TIME: float = 60.0

const COLOR_WARNING  := Color(1.0, 0.3, 0.1, 1.0)   # red-orange
const COLOR_ADVANCE  := Color(0.2, 0.9, 0.3, 1.0)   # green
const COLOR_LOST     := Color(1.0, 0.15, 0.1, 1.0)  # bright red
const COLOR_RESTORED := Color(1.0, 0.55, 0.1, 1.0)  # orange

const PANEL_HEIGHT:  float = 32.0
const PANEL_Y:       float = 118.0  # below the TopCenterPanel (offset_bottom=110)
const FONT_SIZE:     int   = 13
const BAR_WIDTH:     float = 80.0
const BAR_HEIGHT:    float = 10.0
const BANNER_DURATION: float = 3.0
const BANNER_FONT_SIZE: int  = 16

var _my_team: int = 0
var _prev_push_level: Array = [0, 0]

var _banner_text:  String = ""
var _banner_color: Color  = Color.WHITE
var _banner_timer: float  = 0.0

func setup(my_team: int) -> void:
	_my_team = my_team
	anchor_left   = 0.0
	anchor_top    = 0.0
	anchor_right  = 1.0
	anchor_bottom = 1.0
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_prev_push_level = [LaneControl.push_level[0], LaneControl.push_level[1]]
	LaneControl.build_limit_changed.connect(_on_limit_changed)

func _exit_tree() -> void:
	if LaneControl.build_limit_changed.is_connected(_on_limit_changed):
		LaneControl.build_limit_changed.disconnect(_on_limit_changed)

func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
	queue_redraw()

func _draw() -> void:
	var size: Vector2 = get_viewport_rect().size
	if size.x <= 0.0:
		return

	var enemy_team: int = 1 - _my_team
	var panel_cx: float = size.x * 0.5
	var font: Font = ThemeDB.fallback_font

	# ── Warning panel (enemy minions past our limit) ────────────────────────
	var enemy_push_t: float = LaneControl.push_timer[enemy_team]
	if enemy_push_t > 0.0:
		var time_left: float = PUSH_TIME - enemy_push_t
		var pulse_speed: float = 2.0 + (enemy_push_t / PUSH_TIME) * 8.0
		var pulse: float = (sin(Time.get_ticks_msec() * 0.001 * pulse_speed) * 0.5 + 0.5)
		var col: Color = COLOR_WARNING
		col.a = 0.55 + pulse * 0.45

		var warn_text: String = "  ⚠ LIMIT UNDER PRESSURE  [ %ds ]  " % int(ceil(time_left))
		var text_w: float = font.get_string_size(warn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var panel_w: float = text_w + 16.0
		var px: float = panel_cx - panel_w * 0.5
		var py: float = PANEL_Y

		# Background
		draw_rect(Rect2(px, py, panel_w, PANEL_HEIGHT),
			Color(col.r * 0.2, col.g * 0.1, 0.0, col.a * 0.7))
		# Border
		draw_rect(Rect2(px, py, panel_w, PANEL_HEIGHT), col, false, 1.5)
		# Text
		draw_string(font,
			Vector2(px + 8.0, py + PANEL_HEIGHT * 0.5 + FONT_SIZE * 0.35),
			warn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)

	# ── Advance panel (our minions past enemy limit) ────────────────────────
	var our_push_t: float = LaneControl.push_timer[_my_team]
	if our_push_t > 0.0:
		var progress: float = our_push_t / PUSH_TIME
		var adv_col: Color = COLOR_ADVANCE
		var elapsed_s: int = int(our_push_t)

		var prefix: String = "▶ ADVANCING  "
		var suffix: String = "  %ds" % elapsed_s
		var prefix_w: float = font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var suffix_w: float = font.get_string_size(suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var total_w: float = prefix_w + BAR_WIDTH + suffix_w + 16.0
		var px: float = panel_cx - total_w * 0.5
		# Offset below warning panel if both showing
		var py: float = PANEL_Y + (PANEL_HEIGHT + 4.0) if enemy_push_t > 0.0 else PANEL_Y

		# Background
		draw_rect(Rect2(px, py, total_w, PANEL_HEIGHT),
			Color(0.0, 0.15, 0.05, 0.7))
		# Border
		draw_rect(Rect2(px, py, total_w, PANEL_HEIGHT), adv_col, false, 1.5)

		var text_y: float = py + PANEL_HEIGHT * 0.5 + FONT_SIZE * 0.35
		# Prefix
		draw_string(font, Vector2(px + 8.0, text_y),
			prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, adv_col)

		# Progress bar
		var bar_x: float = px + 8.0 + prefix_w
		var bar_y: float = py + (PANEL_HEIGHT - BAR_HEIGHT) * 0.5
		draw_rect(Rect2(bar_x, bar_y, BAR_WIDTH, BAR_HEIGHT),
			Color(0.1, 0.3, 0.1, 0.8))
		draw_rect(Rect2(bar_x, bar_y, BAR_WIDTH * progress, BAR_HEIGHT),
			Color(0.2, 0.9, 0.3, 0.9))
		draw_rect(Rect2(bar_x, bar_y, BAR_WIDTH, BAR_HEIGHT),
			adv_col, false, 1.0)

		# Suffix
		draw_string(font, Vector2(bar_x + BAR_WIDTH + 4.0, text_y),
			suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, adv_col)

	# ── Banner (push/rollback event) ────────────────────────────────────────
	if _banner_timer > 0.0 and _banner_text != "":
		var alpha: float = _banner_timer / BANNER_DURATION
		var bcol: Color = _banner_color
		bcol.a = alpha

		var btext_w: float = font.get_string_size(_banner_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FONT_SIZE).x
		var bpanel_w: float = btext_w + 24.0
		var bpanel_h: float = PANEL_HEIGHT + 8.0
		var bpx: float = panel_cx - bpanel_w * 0.5
		var bpy: float = PANEL_Y + PANEL_HEIGHT * 2.0 + 12.0

		draw_rect(Rect2(bpx, bpy, bpanel_w, bpanel_h),
			Color(bcol.r * 0.15, bcol.g * 0.15, bcol.b * 0.15, alpha * 0.75))
		draw_rect(Rect2(bpx, bpy, bpanel_w, bpanel_h), bcol, false, 2.0)
		draw_string(font,
			Vector2(bpx + 12.0, bpy + bpanel_h * 0.5 + BANNER_FONT_SIZE * 0.35),
			_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FONT_SIZE, bcol)

func _show_banner(text: String, color: Color, duration: float = BANNER_DURATION) -> void:
	_banner_text  = text
	_banner_color = color
	_banner_timer = duration

func _on_limit_changed(team: int, _new_z: float, new_level: int) -> void:
	var old_level: int = _prev_push_level[team]
	_prev_push_level[team] = new_level

	if team == _my_team:
		if new_level < old_level:
			# Our limit was rolled back — bad
			_show_banner("⚠ BUILD LIMIT LOST  (%d/3)" % new_level, COLOR_LOST)
		else:
			# Our limit advanced — good (enemy pushed back further into their territory)
			_show_banner("▶ BUILD LIMIT ADVANCED  (%d/3)" % new_level, COLOR_ADVANCE)
	else:
		if new_level > old_level:
			# We pushed enemy limit forward — good
			_show_banner("▶ ENEMY LIMIT PUSHED  (%d/3)" % new_level, COLOR_ADVANCE)
		else:
			# Enemy regained their limit — bad
			_show_banner("⚠ ENEMY LIMIT RESTORED  (%d/3)" % new_level, COLOR_RESTORED)
