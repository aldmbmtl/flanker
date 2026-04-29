extends MeshInstance3D

const MAP_SIZE := 200.0
const FOG_Y   := 25.0  # above all terrain (peaks reach 22)
const MAX_SOURCES := 64

var _mat: ShaderMaterial = null
var _sources_buf: Array[Vector4] = []

# Timed reveal entries: { pos: Vector3, radius: float, time_left: float }
var _timed_reveals: Array = []

func _ready() -> void:
	_build_mesh()
	visible = false

func _build_mesh() -> void:
	var half := MAP_SIZE / 2.0

	# Two triangles covering the full map, UV2 = world XZ so shader can compute distances
	var verts := PackedVector3Array()
	var uv2   := PackedVector2Array()
	var indices := PackedInt32Array()

	# Quad corners: TL, TR, BL, BR
	var corners := [
		Vector3(-half, FOG_Y, -half),
		Vector3( half, FOG_Y, -half),
		Vector3(-half, FOG_Y,  half),
		Vector3( half, FOG_Y,  half),
	]
	for c in corners:
		verts.append(c)
		uv2.append(Vector2(c.x, c.z))

	# Two triangles (CCW from above)
	indices.append_array([0, 1, 2, 1, 3, 2])

	var arr := Array()
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = indices

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = am

	var shader := load("res://assets/FogOfWar.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material_override = _mat

	# Pre-fill sources array with zeroed vec4s
	_sources_buf.resize(MAX_SOURCES)
	for i in range(MAX_SOURCES):
		_sources_buf[i] = Vector4(0, 0, 0, 0)
	_mat.set_shader_parameter("sources", _sources_buf)
	_mat.set_shader_parameter("source_count", 0)

func update_sources(player_positions: Array, player_radius: float,
		minion_positions: Array, minion_radius: float,
		tower_positions: Array, tower_radius: float) -> void:
	if _mat == null:
		return

	var count := 0

	# Players (allied — array of Vector3)
	for ppos in player_positions:
		if count >= MAX_SOURCES:
			break
		_sources_buf[count] = Vector4(ppos.x, ppos.z, player_radius, 0.0)
		count += 1

	# Minions
	for pos in minion_positions:
		if count >= MAX_SOURCES:
			break
		_sources_buf[count] = Vector4(pos.x, pos.z, minion_radius, 0.0)
		count += 1

	# Towers
	for pos in tower_positions:
		if count >= MAX_SOURCES:
			break
		_sources_buf[count] = Vector4(pos.x, pos.z, tower_radius, 0.0)
		count += 1

	# Timed reveals (recon strike, etc.)
	for reveal in _timed_reveals:
		if count >= MAX_SOURCES:
			break
		var rpos: Vector3 = reveal["pos"]
		_sources_buf[count] = Vector4(rpos.x, rpos.z, reveal["radius"], 0.0)
		count += 1

	# Zero out remaining slots
	for i in range(count, MAX_SOURCES):
		_sources_buf[i] = Vector4(0, 0, 0, 0)

	_mat.set_shader_parameter("sources", _sources_buf)
	_mat.set_shader_parameter("source_count", count)

# Add a temporary fog-of-war reveal at the given world position.
func add_timed_reveal(pos: Vector3, radius: float, duration: float) -> void:
	_timed_reveals.append({ "pos": pos, "radius": radius, "time_left": duration })

func _process(delta: float) -> void:
	_tick_timed_reveals(delta)

func _tick_timed_reveals(delta: float) -> void:
	var i := _timed_reveals.size() - 1
	while i >= 0:
		_timed_reveals[i]["time_left"] -= delta
		if _timed_reveals[i]["time_left"] <= 0.0:
			_timed_reveals.remove_at(i)
		i -= 1
