extends Control
## BuildLimitLine — draws a horizontal line across the RTS viewport at the
## team's current dynamic build limit z (from LaneControl).
## Added to $HUD at runtime in the Supporter branch only.
## The line is drawn in _draw() each frame; queue_redraw() is called from _process().
##
## Two lines are drawn:
##   Own limit  — orange, always shown when in viewport.
##   Enemy limit — red, shown only when enemy push_level > 0 (they have pushed
##                 into our territory). Includes a rollback progress bar showing
##                 how far the rollback timer has accumulated toward ROLLBACK_TIME.

const LINE_COLOR  := Color(1.0, 0.4, 0.1, 0.55)   # semi-transparent orange
const LINE_WIDTH  := 2.0
const LABEL_TEXT  := "— BUILD LIMIT —"
const LABEL_COLOR := Color(1.0, 0.4, 0.1, 0.75)
const LABEL_SIZE  := 12

const ENEMY_LINE_COLOR  := Color(1.0, 0.15, 0.1, 0.55)  # semi-transparent red
const ENEMY_LABEL_TEXT  := "— ENEMY LIMIT —"
const ENEMY_LABEL_COLOR := Color(1.0, 0.15, 0.1, 0.75)

const ROLLBACK_BAR_WIDTH  := 80.0
const ROLLBACK_BAR_HEIGHT := 8.0
const ROLLBACK_BAR_COLOR  := Color(1.0, 0.55, 0.1, 0.85)  # orange — filling = enemy retreating

var _rts_cam: Camera3D = null
var _team: int = 0

## Call immediately after add_child so _draw() has a valid camera reference.
func setup(rts_cam: Camera3D, team: int = 0) -> void:
	_rts_cam = rts_cam
	_team = team
	# Fill entire viewport so draw coords map 1:1 to screen pixels.
	anchor_left   = 0.0
	anchor_top    = 0.0
	anchor_right  = 1.0
	anchor_bottom = 1.0
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

## Returns true when the team's current build limit z projects into the visible viewport.
## Exposed as a standalone method so tests can call it without relying on _draw.
func _should_draw() -> bool:
	if _rts_cam == null or not is_instance_valid(_rts_cam):
		return false
	var h: float = get_viewport_rect().size.y
	if h <= 0.0:
		return false
	var limit_z: float = LaneControl.get_build_limit(_team)
	var screen_pt: Vector2 = _rts_cam.unproject_position(Vector3(0.0, 0.0, limit_z))
	return screen_pt.y >= 0.0 and screen_pt.y <= h

## Returns true when the enemy's pushed limit is active and projects into the viewport.
## Exposed so tests can verify guard logic without relying on _draw.
func _should_draw_enemy() -> bool:
	var enemy_team: int = 1 - _team
	if LaneControl.push_level[enemy_team] <= 0:
		return false
	if _rts_cam == null or not is_instance_valid(_rts_cam):
		return false
	var h: float = get_viewport_rect().size.y
	if h <= 0.0:
		return false
	var limit_z: float = LaneControl.get_build_limit(enemy_team)
	var screen_pt: Vector2 = _rts_cam.unproject_position(Vector3(0.0, 0.0, limit_z))
	return screen_pt.y >= 0.0 and screen_pt.y <= h

func _draw() -> void:
	if _rts_cam == null or not is_instance_valid(_rts_cam):
		return
	var size: Vector2 = get_viewport_rect().size
	if size.y <= 0.0:
		return
	var font: Font = ThemeDB.fallback_font

	# ── Own build limit line ────────────────────────────────────────────────
	var limit_z: float = LaneControl.get_build_limit(_team)
	var screen_pt: Vector2 = _rts_cam.unproject_position(Vector3(0.0, 0.0, limit_z))
	var y: float = screen_pt.y
	if y >= 0.0 and y <= size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), LINE_COLOR, LINE_WIDTH)
		var text_width: float = font.get_string_size(LABEL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var label_x: float = (size.x - text_width) * 0.5
		draw_string(font, Vector2(label_x, y - 4.0), LABEL_TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_COLOR)

	# ── Enemy pushed limit line (only when enemy has pushed into our territory) ──
	var enemy_team: int = 1 - _team
	if LaneControl.push_level[enemy_team] > 0:
		var enemy_limit_z: float = LaneControl.get_build_limit(enemy_team)
		var enemy_pt: Vector2 = _rts_cam.unproject_position(Vector3(0.0, 0.0, enemy_limit_z))
		var ey: float = enemy_pt.y
		if ey >= 0.0 and ey <= size.y:
			# Line
			draw_line(Vector2(0.0, ey), Vector2(size.x, ey), ENEMY_LINE_COLOR, LINE_WIDTH)
			# Label
			var etw: float = font.get_string_size(ENEMY_LABEL_TEXT,
				HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
			var elabel_x: float = (size.x - etw) * 0.5
			draw_string(font, Vector2(elabel_x, ey - 4.0), ENEMY_LABEL_TEXT,
				HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, ENEMY_LABEL_COLOR)
			# Rollback progress bar (filling = enemy limit retreating)
			var rollback_t: float = LaneControl.rollback_timer[enemy_team]
			if rollback_t > 0.0:
				var progress: float = rollback_t / LaneControl.ROLLBACK_TIME
				var bar_x: float = (size.x - ROLLBACK_BAR_WIDTH) * 0.5
				var bar_y: float = ey + 4.0
				# Trough
				draw_rect(Rect2(bar_x, bar_y, ROLLBACK_BAR_WIDTH, ROLLBACK_BAR_HEIGHT),
					Color(0.2, 0.05, 0.0, 0.7))
				# Fill
				draw_rect(Rect2(bar_x, bar_y, ROLLBACK_BAR_WIDTH * progress, ROLLBACK_BAR_HEIGHT),
					ROLLBACK_BAR_COLOR)
				# Border
				draw_rect(Rect2(bar_x, bar_y, ROLLBACK_BAR_WIDTH, ROLLBACK_BAR_HEIGHT),
					ENEMY_LABEL_COLOR, false, 1.0)
