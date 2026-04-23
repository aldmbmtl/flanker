extends StaticBody3D

const GRID_SIZE       := 200
const GRID_STEPS      := 200
const MAX_HEIGHT      := 8.0
const BASE_FLAT_Z     := 76.0
const BASE_BLEND_Z    := 70.0
const LANE_FLAT_DIST  := 3.0
const LANE_BLEND_DIST := 7.0

# Secret paths
const SECRET_FLAT_DIST  := 1.5
const SECRET_BLEND_DIST := 4.5
const SECRET_SAMPLE     := 30

# Plateaus
const PLATEAU_COUNT  := 5
const PLATEAU_HEIGHT := 6.0
const PLATEAU_BLEND  := 4.0

# Peaks
const PEAK_COUNT  := 5
const PEAK_HEIGHT := 22.0
const SNOW_LINE   := 13.0

# Biome
const BIOME_BLEND_X := 10.0

func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var seed_val: int = randi()
	noise.seed = seed_val
	noise.frequency = 0.018
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0

	var verts_per_side := GRID_STEPS + 1
	var half := GRID_SIZE / 2.0
	var step := float(GRID_SIZE) / float(GRID_STEPS)

	var lane_polylines: Array = []
	for i in range(3):
		lane_polylines.append(LaneData.get_lane_points(i))

	var secret_paths: Array = _gen_secret_paths(seed_val)
	var plateaus: Array     = _gen_plateaus(seed_val, lane_polylines)
	var peaks: Array        = _gen_peaks(seed_val, lane_polylines)

	# Biome orientation — flips each run
	var grass_left: bool = (seed_val % 2 == 0)

	# ── Build height map ───────────────────────────────────────────────────────
	var heights: Array = []
	heights.resize(verts_per_side * verts_per_side)
	var plateau_weights: Array = []
	plateau_weights.resize(verts_per_side * verts_per_side)
	var peak_weights: Array = []
	peak_weights.resize(verts_per_side * verts_per_side)

	for zi in range(verts_per_side):
		for xi in range(verts_per_side):
			var wx := -half + xi * step
			var wz := -half + zi * step
			var raw := (noise.get_noise_2d(wx, wz) + 1.0) * 0.5
			var h := raw * MAX_HEIGHT

			# Lane flatten
			var min_lane_dist := INF
			for poly in lane_polylines:
				var d: float = LaneData.dist_to_polyline(Vector2(wx, wz), poly)
				if d < min_lane_dist:
					min_lane_dist = d
			var lane_blend := 1.0
			if min_lane_dist < LANE_FLAT_DIST:
				lane_blend = 0.0
			elif min_lane_dist < LANE_BLEND_DIST:
				var t: float = (min_lane_dist - LANE_FLAT_DIST) / (LANE_BLEND_DIST - LANE_FLAT_DIST)
				lane_blend = smoothstep(0.0, 1.0, t)

			# Secret path flatten
			var min_secret_dist := INF
			for poly in secret_paths:
				var d: float = LaneData.dist_to_polyline(Vector2(wx, wz), poly)
				if d < min_secret_dist:
					min_secret_dist = d
			var secret_blend := 1.0
			if min_secret_dist < SECRET_FLAT_DIST:
				secret_blend = 0.0
			elif min_secret_dist < SECRET_BLEND_DIST:
				var t: float = (min_secret_dist - SECRET_FLAT_DIST) / (SECRET_BLEND_DIST - SECRET_FLAT_DIST)
				secret_blend = smoothstep(0.0, 1.0, t)

			# Base zone flatten
			var base_blend := 1.0
			var az: float = abs(wz)
			if az > BASE_FLAT_Z:
				base_blend = 0.0
			elif az > BASE_BLEND_Z:
				var t: float = (az - BASE_BLEND_Z) / (BASE_FLAT_Z - BASE_BLEND_Z)
				base_blend = 1.0 - smoothstep(0.0, 1.0, t)

			h *= lane_blend * secret_blend * base_blend

			var total_flat: float = (1.0 - lane_blend) + (1.0 - base_blend)

			# Plateau lift
			var plat_w := 0.0
			if total_flat < 0.1:
				var best_plat: Array = []
				for plat in plateaus:
					var pw: float = _plateau_weight(Vector2(wx, wz), plat)
					if pw > plat_w:
						plat_w = pw
						best_plat = plat
				if plat_w > 0.0 and best_plat.size() > 4:
					var target_h: float = best_plat[4]
					h = lerp(h, max(h, target_h), plat_w)

			# Peak lift
			var pk_w := 0.0
			if total_flat < 0.1:
				for peak in peaks:
					var pw: float = _peak_weight(Vector2(wx, wz), peak)
					if pw > pk_w:
						pk_w = pw
				if pk_w > 0.0:
					var peak_h: float = PEAK_HEIGHT * pow(pk_w, 0.6)
					h = max(h, peak_h)

			heights[zi * verts_per_side + xi] = h
			plateau_weights[zi * verts_per_side + xi] = plat_w
			peak_weights[zi * verts_per_side + xi] = pk_w

	# ── Build ArrayMesh ────────────────────────────────────────────────────────
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors  := PackedColorArray()
	var uvs     := PackedVector2Array()
	var indices := PackedInt32Array()

	for zi in range(verts_per_side):
		for xi in range(verts_per_side):
			var wx := -half + xi * step
			var wz := -half + zi * step
			var h: float  = heights[zi * verts_per_side + xi]
			var plat_w: float = plateau_weights[zi * verts_per_side + xi]
			var pk_w: float   = peak_weights[zi * verts_per_side + xi]

			verts.append(Vector3(wx, h, wz))
			uvs.append(Vector2(float(xi) / GRID_STEPS, float(zi) / GRID_STEPS))

			# Step 1 — biome base color
			var x_norm: float = clamp(wx / BIOME_BLEND_X, -1.0, 1.0)
			var biome_t: float = smoothstep(-1.0, 1.0, x_norm if grass_left else -x_norm)
			var ht: float = clamp(h / MAX_HEIGHT, 0.0, 1.0)
			var grass_col: Color = Color(0.18, 0.32, 0.10).lerp(Color(0.30, 0.42, 0.14), ht)
			var desert_col: Color = Color(0.62, 0.48, 0.22).lerp(Color(0.52, 0.36, 0.14), ht)
			var base_col: Color = grass_col.lerp(desert_col, biome_t)

			# Step 2 — rocky plateau overlay
			base_col = base_col.lerp(Color(0.52, 0.46, 0.38), plat_w)

			# Step 3 — peak rocky slope
			base_col = base_col.lerp(Color(0.46, 0.42, 0.40), pk_w)

			# Step 4 — snow cap
			var snow_t: float = smoothstep(SNOW_LINE, PEAK_HEIGHT, h)
			base_col = base_col.lerp(Color(0.92, 0.95, 1.0), snow_t)

			colors.append(base_col)
			normals.append(Vector3.UP)

	for zi in range(GRID_STEPS):
		for xi in range(GRID_STEPS):
			var tl := zi * verts_per_side + xi
			var tr := tl + 1
			var bl := tl + verts_per_side
			var br := bl + 1
			indices.append(tl); indices.append(tr); indices.append(bl)
			indices.append(tr); indices.append(br); indices.append(bl)

	# Smooth normals
	var normal_accum: Array = []
	normal_accum.resize(verts.size())
	for i in range(normal_accum.size()):
		normal_accum[i] = Vector3.ZERO
	for i in range(0, indices.size(), 3):
		var ia := indices[i]; var ib := indices[i+1]; var ic := indices[i+2]
		var edge1: Vector3 = verts[ib] - verts[ia]
		var edge2: Vector3 = verts[ic] - verts[ia]
		var fn := edge1.cross(edge2).normalized()
		normal_accum[ia] += fn
		normal_accum[ib] += fn
		normal_accum[ic] += fn
	for i in range(normals.size()):
		normals[i] = normal_accum[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR]  = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	arr_mesh.surface_set_material(0, mat)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = arr_mesh
	add_child(mesh_inst)

	# HeightMapShape3D collision
	var hmap := HeightMapShape3D.new()
	hmap.map_width = verts_per_side
	hmap.map_depth = verts_per_side
	var hmap_data := PackedFloat32Array()
	hmap_data.resize(verts_per_side * verts_per_side)
	for zi in range(verts_per_side):
		for xi in range(verts_per_side):
			hmap_data[zi * verts_per_side + xi] = heights[zi * verts_per_side + xi]
	hmap.map_data = hmap_data
	var col_shape := CollisionShape3D.new()
	col_shape.shape = hmap
	col_shape.scale = Vector3(step, 1.0, step)
	add_child(col_shape)

	print("Terrain: verts=%d seed=%d plateaus=%d peaks=%d secret_paths=%d grass_left=%s" \
		% [verts.size(), seed_val, plateaus.size(), peaks.size(), secret_paths.size(), str(grass_left)])

# ── Secret path generation ─────────────────────────────────────────────────────
func _gen_secret_paths(seed_val: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var paths: Array = []
	for side in range(2):
		var x_sign := -1.0 if side == 0 else 1.0
		for _p in range(3):
			var x_start := x_sign * rng.randf_range(20.0, 72.0)
			var z_start := rng.randf_range(-70.0, 70.0)
			var x_end   := x_sign * rng.randf_range(20.0, 72.0)
			var z_end   := rng.randf_range(-70.0, 70.0)
			var x_c1 := x_sign * rng.randf_range(18.0, 78.0)
			var z_c1 := z_start + (z_end - z_start) * rng.randf_range(0.2, 0.45)
			var x_c2 := x_sign * rng.randf_range(18.0, 78.0)
			var z_c2 := z_start + (z_end - z_start) * rng.randf_range(0.55, 0.8)
			paths.append(_sample_bezier_2d(
				Vector2(x_start, z_start), Vector2(x_c1, z_c1),
				Vector2(x_c2, z_c2), Vector2(x_end, z_end), SECRET_SAMPLE))
	return paths

# ── Plateau generation ─────────────────────────────────────────────────────────
func _gen_plateaus(seed_val: int, lane_polylines: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 9999
	var plateaus: Array = []
	var attempts := 0
	while plateaus.size() < PLATEAU_COUNT and attempts < 200:
		attempts += 1
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var cx := side * rng.randf_range(16.0, 76.0)
		var cz := rng.randf_range(-68.0, 68.0)
		var too_close := false
		for poly in lane_polylines:
			if LaneData.dist_to_polyline(Vector2(cx, cz), poly) < 14.0:
				too_close = true; break
		if too_close: continue
		var overlap := false
		for p in plateaus:
			var dx: float = cx - p[0]; var dz: float = cz - p[1]
			if sqrt(dx*dx + dz*dz) < 28.0:
				overlap = true; break
		if overlap: continue
		plateaus.append([cx, cz, rng.randf_range(10.0, 18.0), rng.randf_range(8.0, 14.0), rng.randf_range(5.0, 7.0)])
	return plateaus

# ── Peak generation ────────────────────────────────────────────────────────────
func _gen_peaks(seed_val: int, lane_polylines: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 77777
	var peaks: Array = []
	var attempts := 0
	while peaks.size() < PEAK_COUNT and attempts < 200:
		attempts += 1
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var cx := side * rng.randf_range(20.0, 78.0)
		var cz := rng.randf_range(-68.0, 68.0)
		var too_close := false
		for poly in lane_polylines:
			if LaneData.dist_to_polyline(Vector2(cx, cz), poly) < 14.0:
				too_close = true; break
		if too_close: continue
		var overlap := false
		for p in peaks:
			var dx: float = cx - p[0]; var dz: float = cz - p[1]
			if sqrt(dx*dx + dz*dz) < 25.0:
				overlap = true; break
		if overlap: continue
		# Also keep peaks away from plateaus — checked later via height logic
		peaks.append([cx, cz, rng.randf_range(8.0, 14.0), rng.randf_range(7.0, 12.0)])
	return peaks

# Returns 0..1 weight for peak influence; steep falloff for sharp spires
func _peak_weight(pos: Vector2, peak: Array) -> float:
	var cx: float = peak[0]; var cz: float = peak[1]
	var rx: float = peak[2]; var rz: float = peak[3]
	var dx := (pos.x - cx) / rx
	var dz := (pos.y - cz) / rz
	var dist: float = sqrt(dx*dx + dz*dz)
	if dist >= 1.0:
		return 0.0
	# Exponential-ish falloff: steep sides, sharp peak
	return pow(1.0 - dist, 1.8)

func _plateau_weight(pos: Vector2, plat: Array) -> float:
	var cx: float = plat[0]; var cz: float = plat[1]
	var rx: float = plat[2]; var rz: float = plat[3]
	var dx := (pos.x - cx) / rx
	var dz := (pos.y - cz) / rz
	var dist: float = sqrt(dx*dx + dz*dz)
	if dist >= 1.0 + PLATEAU_BLEND / min(rx, rz):
		return 0.0
	var inner: float = 1.0
	var outer: float = 1.0 + PLATEAU_BLEND / min(rx, rz)
	if dist > inner:
		var t: float = (dist - inner) / (outer - inner)
		return 1.0 - smoothstep(0.0, 1.0, t)
	return 1.0

func _sample_bezier_2d(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n: int) -> Array:
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
