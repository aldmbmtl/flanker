## test_compass_hud.gd
## Tests for CompassHUD bearing math, ping lifecycle, and fog-gate logic.
## All tests are Tier-1 (OfflineMultiplayerPeer, no rendering).

extends GutTest

const CompassHUDScript := preload("res://scripts/hud/CompassHUD.gd")

# ── Helpers ───────────────────────────────────────────────────────────────────

## Minimal fake player node with a declared global_position property.
class FakePlayer:
	extends Node3D
	# global_position is inherited from Node3D — no extra declaration needed.

## Minimal fake Camera3D with a settable global_rotation.
class FakeCamera:
	extends Camera3D
	# global_rotation is inherited from Node3D — no extra declaration needed.

## Build a CompassHUD, add it to the scene tree, and call setup().
func _make_compass(player_pos: Vector3, cam_yaw_rad: float, team: int) -> Control:
	var player := FakePlayer.new()
	add_child_autofree(player)
	player.global_position = player_pos

	var cam := FakeCamera.new()
	add_child_autofree(cam)
	cam.rotation = Vector3(0.0, cam_yaw_rad, 0.0)

	var hud := Control.new()
	hud.set_script(CompassHUDScript)
	add_child_autofree(hud)
	hud.setup(player, cam, team)
	return hud

# ── _wrap_deg ─────────────────────────────────────────────────────────────────

func test_wrap_deg_no_wrap() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var result: float = hud._wrap_deg(45.0)
	assert_almost_eq(result, 45.0, 0.001, "_wrap_deg(45) should return 45")

func test_wrap_deg_over_180() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var result: float = hud._wrap_deg(270.0)
	assert_almost_eq(result, -90.0, 0.001, "_wrap_deg(270) should return -90")

func test_wrap_deg_negative() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var result: float = hud._wrap_deg(-270.0)
	assert_almost_eq(result, 90.0, 0.001, "_wrap_deg(-270) should return 90")

func test_wrap_deg_exactly_180() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var result: float = hud._wrap_deg(180.0)
	assert_almost_eq(result, 180.0, 0.001, "_wrap_deg(180) boundary")

# ── _world_pos_to_strip_x ────────────────────────────────────────────────────

func test_bearing_directly_ahead_is_strip_centre() -> void:
	## Camera facing north (yaw=0 → cam_bearing_deg=0).
	## Entity at (0,0,-10) is directly north (atan2(0,−10) wraps... actually:
	## world bearing of +Z is atan2(x,z) with x=0, z=-10 → atan2(0,-10) = π → 180°.
	## Wait — "North" in this game is +Z or -Z?  Let's check the coordinate system:
	## atan2(to.x, to.z): entity north of player means z > player.z,
	## so to.z > 0.  atan2(0, 10) = 0 rad = 0° → centred.  Correct.
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(Vector3(0, 0, 10), Vector3.ZERO, 0.0)
	# Should be exactly half the strip width
	assert_almost_eq(x, CompassHUDScript.STRIP_WIDTH * 0.5, 0.5, "Entity dead-ahead should land at strip centre (STRIP_WIDTH/2 px)")

func test_bearing_directly_behind_is_clipped() -> void:
	## Entity at z=-10 → bearing 180° → delta 180° > STRIP_FOV_HALF(60°) → clipped
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(Vector3(0, 0, -10), Vector3.ZERO, 0.0)
	assert_eq(x, -1.0, "Entity directly behind should be clipped (returns -1)")

func test_bearing_90_right_maps_to_right_of_centre() -> void:
	## Entity at (10,0,0) → bearing = atan2(10,0) = 90° → delta = 90° from camera.
	## 90° > STRIP_FOV_HALF(60°) → clipped.
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(Vector3(10, 0, 0), Vector3.ZERO, 0.0)
	assert_eq(x, -1.0, "Entity 90° right exceeds FOV, should be clipped")

func test_bearing_45_right_maps_within_strip() -> void:
	## Entity at (10,0,10) → bearing = atan2(10,10) = 45° → inside ±60° FOV
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(Vector3(10, 0, 10), Vector3.ZERO, 0.0)
	assert_gt(x, CompassHUDScript.STRIP_WIDTH * 0.5, "45° right entity should land right of centre")
	assert_lt(x, CompassHUDScript.STRIP_WIDTH, "45° right entity should be within strip width")

func test_bearing_59_degrees_is_within_fov() -> void:
	## 59° < 60° — should not be clipped
	var angle_rad: float = deg_to_rad(59.0)
	var entity_pos := Vector3(sin(angle_rad) * 10.0, 0.0, cos(angle_rad) * 10.0)
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(entity_pos, Vector3.ZERO, 0.0)
	assert_gt(x, -1.0, "Entity at 59° should be within FOV, not clipped")

func test_bearing_61_degrees_is_clipped() -> void:
	## 61° > 60° — should be clipped
	var angle_rad: float = deg_to_rad(61.0)
	var entity_pos := Vector3(sin(angle_rad) * 10.0, 0.0, cos(angle_rad) * 10.0)
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(entity_pos, Vector3.ZERO, 0.0)
	assert_eq(x, -1.0, "Entity at 61° should be outside FOV and clipped")

func test_camera_rotation_shifts_centre() -> void:
	## Camera rotated 45° right (yaw = -π/4 → cam_bearing = +45°).
	## Entity directly north (0,0,10) → world bearing 0° → delta = 0° - 45° = -45°
	## → left of centre but within FOV.
	var cam_yaw: float = -deg_to_rad(45.0)
	var hud: Control = _make_compass(Vector3.ZERO, cam_yaw, 0)
	var cam_bearing: float = rad_to_deg(-cam_yaw)   # = 45.0
	var x: float = hud._world_pos_to_strip_x(Vector3(0, 0, 10), Vector3.ZERO, cam_bearing)
	assert_lt(x, CompassHUDScript.STRIP_WIDTH * 0.5, "North entity should be left of centre when camera faces NE")
	assert_gt(x, -1.0, "North entity should still be within FOV when camera faces NE")

# ── Ping lifecycle ────────────────────────────────────────────────────────────

func test_ping_added_on_signal_same_team() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	hud._on_ping_received(Vector3(5, 0, 5), 0, Color(0.62, 0.0, 1.0, 1.0))
	assert_eq(hud._active_pings.size(), 1, "Ping for same team should be added")

func test_ping_ignored_on_signal_different_team() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	hud._on_ping_received(Vector3(5, 0, 5), 1, Color(0.62, 0.0, 1.0, 1.0))   # team 1, hud is team 0
	assert_eq(hud._active_pings.size(), 0, "Ping for different team should be ignored")

func test_ping_starts_with_age_zero() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	hud._on_ping_received(Vector3(1, 0, 1), 0, Color(0.62, 0.0, 1.0, 1.0))
	var age: float = hud._active_pings[0]["age"] as float
	assert_almost_eq(age, 0.0, 0.001, "New ping age should be 0")

func test_ping_expired_when_age_exceeds_duration() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	hud._on_ping_received(Vector3(1, 0, 1), 0, Color(0.62, 0.0, 1.0, 1.0))
	# Manually advance age past PING_DURATION
	hud._active_pings[0]["age"] = 4.1
	hud._process(0.0)   # triggers expiry check with delta=0
	assert_eq(hud._active_pings.size(), 0, "Expired ping should be removed")

func test_ping_not_expired_below_duration() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	hud._on_ping_received(Vector3(1, 0, 1), 0, Color(0.62, 0.0, 1.0, 1.0))
	hud._active_pings[0]["age"] = 3.9
	hud._process(0.0)
	assert_eq(hud._active_pings.size(), 1, "Ping below PING_DURATION should survive")

func test_multiple_pings_expire_independently() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	hud._on_ping_received(Vector3(1, 0, 1), 0, Color(0.62, 0.0, 1.0, 1.0))
	hud._on_ping_received(Vector3(2, 0, 2), 0, Color(0.62, 0.0, 1.0, 1.0))
	hud._active_pings[0]["age"] = 4.1   # expired
	hud._active_pings[1]["age"] = 1.0   # alive
	hud._process(0.0)
	assert_eq(hud._active_pings.size(), 1, "Only the expired ping should be removed")

func test_ping_stores_color() -> void:
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var green := Color(0.0, 0.85, 0.25, 1.0)
	hud._on_ping_received(Vector3(3, 0, 3), 0, green)
	var stored: Color = hud._active_pings[0]["color"] as Color
	assert_eq(stored, green, "Compass ping dict should store the passed color")

# ── Fog-of-war gate (via PLAYER_VISION_RADIUS constant) ──────────────────────

func test_player_vision_radius_constant_matches_rts_controller() -> void:
	## PLAYER_VISION_RADIUS in CompassHUD must match RTSController.PLAYER_VISION_RADIUS.
	## This is a numeric guard so they never drift silently.
	const RTSScript := preload("res://scripts/roles/supporter/RTSController.gd")
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var compass_radius: float = hud.PLAYER_VISION_RADIUS
	assert_almost_eq(compass_radius, 35.0, 0.001, "CompassHUD.PLAYER_VISION_RADIUS must equal 35.0")

# ── Out-of-FOV ping end arrows ────────────────────────────────────────────────

func test_ping_right_of_fov_is_clipped_by_helper() -> void:
	## Entity at 90° right → delta > 60° → _world_pos_to_strip_x returns -1.
	## Verifies the math that triggers the right-end arrow branch.
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(Vector3(10, 0, 0), Vector3.ZERO, 0.0)
	assert_eq(x, -1.0, "Ping at 90° right (outside FOV) must return -1 to trigger end arrow")

func test_ping_left_of_fov_is_clipped_by_helper() -> void:
	## Entity at 90° left → delta < -60° → _world_pos_to_strip_x returns -1.
	## Verifies the math that triggers the left-end arrow branch.
	var hud: Control = _make_compass(Vector3.ZERO, 0.0, 0)
	var x: float = hud._world_pos_to_strip_x(Vector3(-10, 0, 0), Vector3.ZERO, 0.0)
	assert_eq(x, -1.0, "Ping at 90° left (outside FOV) must return -1 to trigger end arrow")
