extends GutTest
## Tests for BuildLimitLine — the HUD overlay that projects the world z=0
## midline onto the screen. Purely unit-level: no real Camera3D math needed.

const BuildLimitLineScript := preload("res://scripts/ui/BuildLimitLine.gd")

var _line: Control = null

func before_each() -> void:
	_line = Control.new()
	_line.set_script(BuildLimitLineScript)
	add_child_autofree(_line)

# ── setup / defaults ──────────────────────────────────────────────────────────

func test_default_camera_is_null() -> void:
	assert_null(_line.get("_rts_cam"),
		"Camera ref must start null before setup() is called")

func test_setup_assigns_camera() -> void:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	_line.setup(cam)
	assert_eq(_line.get("_rts_cam"), cam,
		"setup() must store the camera reference")

# ── _should_draw guards ───────────────────────────────────────────────────────

func test_should_draw_false_when_no_camera() -> void:
	# _rts_cam is null → must return false without crashing
	assert_false(_line._should_draw(),
		"_should_draw() must return false when no camera is set")

func test_should_draw_false_when_camera_freed() -> void:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	_line.setup(cam)
	cam.free()
	# After cam.free(), is_instance_valid returns false — _should_draw must guard it
	assert_false(_line._should_draw(),
		"_should_draw() must return false after camera is freed")
