extends Node

# Single source of truth for all lane paths.
# Used by: TerrainGenerator, MinionSpawner, LaneVisualizer

# Map constants
const BLUE_BASE := Vector2(0.0, 82.0)   # z positive = south
const RED_BASE  := Vector2(0.0, -82.0)  # z negative = north
const SAMPLE_COUNT := 40  # points per lane curve
const LANE_FLATTEN := 50  # max perturbation for control points

# Cubic Bézier control points [P0, P1, P2, P3] in XZ (Vector2)
# Lane 0 = Left, Lane 1 = Mid, Lane 2 = Right
const LANE_CONTROLS := [
	# Left lane: exits blue base west, hugs left wall, arrives red base
	[Vector2(0.0, 82.0), Vector2(-85.0, 82.0), Vector2(-85.0, -82.0), Vector2(0.0, -82.0)],
	# Mid lane: straight line (P1/P2 on the line = effectively linear)
	[Vector2(0.0, 82.0), Vector2(0.0, 27.0), Vector2(0.0, -27.0), Vector2(0.0, -82.0)],
	# Right lane: mirror of left
	[Vector2(0.0, 82.0), Vector2(85.0, 82.0), Vector2(85.0, -82.0), Vector2(0.0, -82.0)],
]

# Cache
var _lane_points: Array = []  # Array of Array[Vector2]
var _secret_paths: Array = []  # Array of Array[Vector2]
var _generated: bool = false

func _ready() -> void:
	pass  # lazy generation on first access

func regenerate_for_new_game() -> void:
	_generated = false
	_lane_points.clear()
	_generate_if_needed()

func _generate_if_needed() -> void:
	if _generated:
		return
	_generated = true
	for i in range(3):
		var ctrl: Array = LANE_CONTROLS[i]
		seed(GameSync.game_seed + 100 * (i + 1))
		var p1_offset := Vector2(randf_range(-LANE_FLATTEN, LANE_FLATTEN), randf_range(-LANE_FLATTEN, LANE_FLATTEN))
		var p2_offset := Vector2(randf_range(-LANE_FLATTEN, LANE_FLATTEN), randf_range(-LANE_FLATTEN, LANE_FLATTEN))
		var perturbed: Array[Vector2] = [
			ctrl[0],  # P0 fixed
			ctrl[1] + p1_offset,
			ctrl[2] + p2_offset,
			ctrl[3],  # P3 fixed
		]
		_lane_points.append(_sample_bezier(perturbed[0], perturbed[1], perturbed[2], perturbed[3], SAMPLE_COUNT))

# Called by Main.gd after terrain generates secret paths
func set_secret_paths(paths: Array) -> void:
	_secret_paths = paths

# Returns Array[Vector2] of XZ world positions along lane (blue→red direction)
func get_lane_points(lane_i: int) -> Array:
	_generate_if_needed()
	return _lane_points[lane_i]

# Returns secret path points for path_index (0-5), or empty array if invalid
func get_secret_path_points(path_index: int) -> Array:
	if path_index < 0 or path_index >= _secret_paths.size():
		return []
	return _secret_paths[path_index]

# Returns all secret path points flattened
func get_all_secret_path_points() -> Array:
	_generate_if_needed()
	var all: Array = []
	for path in _secret_paths:
		all.append_array(path)
	return all

# Returns Array[Vector3] waypoints for a minion to follow
# team 0 = blue (south→north, index order), team 1 = red (north→south, reversed)
func get_lane_waypoints(lane_i: int, team: int) -> Array[Vector3]:
	var pts: Array = _lane_points[lane_i]
	var result: Array[Vector3] = []
	if team == 0:
		for p in pts:
			result.append(Vector3(p.x, 1.0, p.y))
	else:
		for i in range(pts.size() - 1, -1, -1):
			var p: Vector2 = pts[i]
			result.append(Vector3(p.x, 1.0, p.y))
	return result

# Returns all lane points flattened into one Array[Vector2] for terrain use
func get_all_lane_points() -> Array:
	_generate_if_needed()
	var all: Array = []
	for lane in _lane_points:
		all.append_array(lane)
	return all

# Sample cubic Bézier curve into n+1 points
func _sample_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n: int) -> Array:
	var pts: Array = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		var mt := 1.0 - t
		var pt: Vector2 = mt*mt*mt * p0 \
			+ 3.0*mt*mt*t * p1 \
			+ 3.0*mt*t*t  * p2 \
			+ t*t*t        * p3
		pts.append(pt)
	return pts

# Minimum distance from point p to a polyline defined by pts (Array[Vector2])
func dist_to_polyline(p: Vector2, pts: Array) -> float:
	var min_d := INF
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		min_d = min(min_d, _dist_point_segment(p, a, b))
	return min_d

func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t: float = clamp(ap.dot(ab) / ab.dot(ab), 0.0, 1.0) if ab.dot(ab) > 0.0001 else 0.0
	var closest: Vector2 = a + ab * t
	return p.distance_to(closest)
