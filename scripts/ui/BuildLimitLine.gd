extends Control
## BuildLimitLine — draws a horizontal line across the RTS viewport at the
## team's current dynamic build limit z (from LaneControl).
## Added to $HUD at runtime in the Supporter branch only.
## The line is drawn in _draw() each frame; queue_redraw() is called from _process().

const LINE_COLOR  := Color(1.0, 0.4, 0.1, 0.55)   # semi-transparent orange
const LINE_WIDTH  := 2.0
const LABEL_TEXT  := "— BUILD LIMIT —"
const LABEL_COLOR := Color(1.0, 0.4, 0.1, 0.75)
const LABEL_SIZE  := 12

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

func _draw() -> void:
	if _rts_cam == null or not is_instance_valid(_rts_cam):
		return
	var size: Vector2 = get_viewport_rect().size
	if size.y <= 0.0:
		return
	var limit_z: float = LaneControl.get_build_limit(_team)
	var screen_pt: Vector2 = _rts_cam.unproject_position(Vector3(0.0, 0.0, limit_z))
	var y: float = screen_pt.y
	if y < 0.0 or y > size.y:
		return

	# Horizontal line full-width at the projected y
	draw_line(Vector2(0.0, y), Vector2(size.x, y), LINE_COLOR, LINE_WIDTH)

	# Centered label
	var font: Font = ThemeDB.fallback_font
	var text_width: float = font.get_string_size(LABEL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	var label_x: float = (size.x - text_width) * 0.5
	draw_string(font, Vector2(label_x, y - 4.0), LABEL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_COLOR)
