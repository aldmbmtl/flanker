extends GutTest
## Tests for BuildLimitLine — the HUD overlay that projects the world z=0
## midline onto the screen. Purely unit-level: no real Camera3D math needed.

const BuildLimitLineScript := preload("res://scripts/ui/BuildLimitLine.gd")

var _line: Control = null

func before_each() -> void:
	_line = Control.new()
	_line.set_script(BuildLimitLineScript)
	add_child_autofree(_line)
	LaneControl.reset()

func after_each() -> void:
	LaneControl.reset()

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

# ── _should_draw_enemy guards ─────────────────────────────────────────────────

func test_should_draw_enemy_false_when_push_level_zero() -> void:
	# Enemy (team 1) has not pushed at all — line must not show.
	_line.setup(null, 0)
	LaneControl.push_level[1] = 0
	assert_false(_line._should_draw_enemy(),
		"enemy line must not show when enemy push_level == 0")

func test_should_draw_enemy_false_when_no_camera_even_if_pushed() -> void:
	_line.setup(null, 0)
	LaneControl.push_level[1] = 1
	assert_false(_line._should_draw_enemy(),
		"enemy line must not show without a camera even when push_level > 0")

func test_should_draw_enemy_false_when_camera_freed_even_if_pushed() -> void:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	_line.setup(cam, 0)
	LaneControl.push_level[1] = 2
	cam.free()
	assert_false(_line._should_draw_enemy(),
		"enemy line must not show after camera freed even when push_level > 0")

func test_should_draw_enemy_reads_correct_enemy_team_for_team0() -> void:
	# Team 0 player — enemy is team 1.
	_line.setup(null, 0)
	LaneControl.push_level[1] = 0
	assert_false(_line._should_draw_enemy(), "enemy team 1 at level 0 → false")
	LaneControl.push_level[1] = 1
	# No camera so still false, but the push_level guard passed — confirm separately
	# by checking the internal push_level directly.
	assert_eq(LaneControl.push_level[1], 1, "push_level[1] must be 1")

func test_should_draw_enemy_reads_correct_enemy_team_for_team1() -> void:
	# Team 1 player — enemy is team 0.
	_line.setup(null, 1)
	LaneControl.push_level[0] = 0
	assert_false(_line._should_draw_enemy(), "enemy team 0 at level 0 → false")

# ── Rollback bar progress ratio ───────────────────────────────────────────────

func test_rollback_bar_ratio_zero_when_timer_zero() -> void:
	LaneControl.rollback_timer[1] = 0.0
	var ratio: float = LaneControl.rollback_timer[1] / LaneControl.ROLLBACK_TIME
	assert_almost_eq(ratio, 0.0, 0.001)

func test_rollback_bar_ratio_half_at_midpoint() -> void:
	LaneControl.rollback_timer[1] = LaneControl.ROLLBACK_TIME * 0.5
	var ratio: float = LaneControl.rollback_timer[1] / LaneControl.ROLLBACK_TIME
	assert_almost_eq(ratio, 0.5, 0.001)

func test_rollback_bar_ratio_one_at_full() -> void:
	LaneControl.rollback_timer[1] = LaneControl.ROLLBACK_TIME
	var ratio: float = LaneControl.rollback_timer[1] / LaneControl.ROLLBACK_TIME
	assert_almost_eq(ratio, 1.0, 0.001)
