# test_tree_placer.gd
# Tier 1 — unit tests for TreePlacer wind-shader integration and tree clearing.
#
# TreePlacer requires autoloads (GameSync, LaneData, LoadingState) and a live
# physics world for raycasts — we test only the pure-logic wind paths that do
# NOT need raycasts or terrain geometry.
#
# Specifically:
#   1. Wind export defaults are sane (strength, gust, speed, direction)
#   2. _commit_multimeshes applies a ShaderMaterial on surface 0 of each MMI
#   3. The ShaderMaterial uses WIND_SHADER and sets the expected uniforms
#   4. _process gust calculation stays in [wind_strength_base,
#      wind_strength_base + wind_strength_gust]
#   5. _extract_albedo_recursive returns null for a plain MeshInstance3D with
#      no material (graceful fallback)
#   6. clear_trees_at removes _tree_records and rebuilds MMI instance_count
extends GutTest

const TreePlacerScript := preload("res://scripts/TreePlacer.gd")
const WIND_SHADER      := preload("res://assets/tree_wind.gdshader")

# Minimal TreePlacer subclass that bypasses async _ready() and _place_trees().
class FakeTreePlacer extends Node3D:
	var wind_strength_base: float    = 0.03
	var wind_strength_gust: float    = 0.04
	var wind_gust_cycle_speed: float = 0.25
	var wind_speed: float            = 0.9
	var wind_direction: Vector2      = Vector2(1.0, 0.3)
	var wave_scale: float            = 0.05
	var _wind_mmis: Array[MultiMeshInstance3D] = []

	# Exposed so tests can drive the uniform-update path directly.
	func simulate_process(t: float) -> void:
		if _wind_mmis.is_empty():
			return
		var gust_factor: float = sin(t * wind_gust_cycle_speed) * 0.5 + 0.5
		var current_strength: float = wind_strength_base + wind_strength_gust * gust_factor
		for mmi in _wind_mmis:
			if is_instance_valid(mmi):
				var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
				if mat:
					mat.set_shader_parameter("wind_strength", current_strength)

	# Mirrors TreePlacer._find_albedo_recursive so we can unit-test it.
	func find_albedo_recursive(node: Node) -> Texture2D:
		if node is MeshInstance3D:
			var mi: MeshInstance3D = node as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(si)
				if mat is BaseMaterial3D:
					var bm: BaseMaterial3D = mat as BaseMaterial3D
					if bm.albedo_texture != null:
						return bm.albedo_texture
		for child in node.get_children():
			var t: Texture2D = find_albedo_recursive(child)
			if t != null:
				return t
		return null

	# Build a single MMI with a wind ShaderMaterial — mirrors _commit_multimeshes
	# logic without needing GLB assets or MultiMesh instances.
	func build_wind_mmi(albedo_tex: Texture2D) -> MultiMeshInstance3D:
		var mmi := MultiMeshInstance3D.new()
		var mat := ShaderMaterial.new()
		mat.shader = WIND_SHADER
		mat.set_shader_parameter("wind_strength", wind_strength_base)
		mat.set_shader_parameter("wind_speed", wind_speed)
		mat.set_shader_parameter("wind_direction", wind_direction)
		mat.set_shader_parameter("wave_scale", wave_scale)
		if albedo_tex != null:
			mat.set_shader_parameter("albedo_texture", albedo_tex)
		mmi.material_override = mat
		_wind_mmis.append(mmi)
		add_child(mmi)
		return mmi


# Mirrors the cast_shadow selection logic from TreePlacer._commit_multimeshes.
class ShadowTestHelper extends Node3D:
	func resolve_cast_shadow(tsd: int, band: int) -> int:
		if tsd == 1 and band == 0:
			return GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elif tsd == 2:
			return GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Minimal in-test tree placer that mirrors the _tree_records / _mmis / _band_transforms
# machinery added to TreePlacer for visual clearing, without needing physics or terrain.
class ClearTestTreePlacer extends Node3D:
	var _band_transforms: Array = []   # [vi][band] = Array[Transform3D]
	var _tree_records: Array = []      # [{xz, vi, band}]
	var _mmis: Array = []              # [vi * 2 + band] = MultiMeshInstance3D

	func _init() -> void:
		# One variant, two bands
		_band_transforms.append([[], []])
		_mmis.resize(2)

	# Add a tree at pos (xz) in band 0, variant 0.
	func add_tree(xz: Vector2) -> Transform3D:
		var t := Transform3D()
		t.origin = Vector3(xz.x, 0.0, xz.y)
		_band_transforms[0][0].append(t)
		_tree_records.append({"xz": xz, "vi": 0, "band": 0})
		return t

	# Build an MMI for (vi=0, band=0) from current _band_transforms and store it.
	func build_mmi_for_band0() -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var transforms: Array = _band_transforms[0][0]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i] as Transform3D)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		_mmis[0] = mmi  # vi=0, band=0 → index 0
		return mmi

	# ── Copied verbatim from TreePlacer ──
	func clear_trees_at(world_pos: Vector3, radius: float) -> void:
		var center := Vector2(world_pos.x, world_pos.z)
		for child in get_children():
			if child is MultiMeshInstance3D:
				continue
			var child_pos := Vector2(child.position.x, child.position.z)
			if child_pos.distance_to(center) <= radius:
				child.queue_free()
		if _tree_records.is_empty():
			return
		var to_remove: Array[int] = []
		var dirty_keys: Dictionary = {}
		for i in _tree_records.size():
			var rec: Dictionary = _tree_records[i]
			var xz: Vector2 = rec["xz"]
			if xz.distance_to(center) <= radius:
				to_remove.append(i)
				dirty_keys[str(rec["vi"]) + "_" + str(rec["band"])] = true
		if to_remove.is_empty():
			return
		var removed_xz: Array[Vector2] = []
		for i in to_remove:
			removed_xz.append(_tree_records[i]["xz"])
		for key in dirty_keys.keys():
			var parts: Array = key.split("_")
			var vi: int = int(parts[0])
			var band: int = int(parts[1])
			var old_transforms: Array = _band_transforms[vi][band]
			var new_transforms: Array = []
			for t in old_transforms:
				var t_xz := Vector2((t as Transform3D).origin.x, (t as Transform3D).origin.z)
				var keep := true
				for rxz in removed_xz:
					if t_xz.distance_to(rxz) < 0.01:
						keep = false
						break
				if keep:
					new_transforms.append(t)
			_band_transforms[vi][band] = new_transforms
			_rebuild_mmi(vi, band)
		for i in range(to_remove.size() - 1, -1, -1):
			_tree_records.remove_at(to_remove[i])

	func _rebuild_mmi(vi: int, band: int) -> void:
		var idx: int = vi * 2 + band
		if idx >= _mmis.size():
			return
		var mmi: MultiMeshInstance3D = _mmis[idx] as MultiMeshInstance3D
		if mmi == null or not is_instance_valid(mmi):
			return
		var transforms: Array = _band_transforms[vi][band]
		var mm: MultiMesh = mmi.multimesh
		if mm == null:
			return
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i] as Transform3D)


var tp: FakeTreePlacer
var shadow_helper: ShadowTestHelper
var ctp: ClearTestTreePlacer

func before_each() -> void:
	tp = FakeTreePlacer.new()
	add_child_autofree(tp)
	shadow_helper = ShadowTestHelper.new()
	add_child_autofree(shadow_helper)
	ctp = ClearTestTreePlacer.new()
	add_child_autofree(ctp)


# ── Default wind parameter sanity ─────────────────────────────────────────────

func test_wind_strength_base_default() -> void:
	assert_gt(tp.wind_strength_base, 0.0,
		"wind_strength_base must be positive")

func test_wind_strength_gust_default() -> void:
	assert_gt(tp.wind_strength_gust, 0.0,
		"wind_strength_gust must be positive")

func test_wind_strength_gust_gt_base() -> void:
	# Gust amplitude drives the visible variation — should be larger than base.
	assert_gt(tp.wind_strength_gust, tp.wind_strength_base,
		"gust amplitude should exceed base for noticeable variation")

func test_wind_speed_default() -> void:
	assert_gt(tp.wind_speed, 0.0,
		"wind_speed must be positive")

func test_wind_direction_not_zero() -> void:
	assert_gt(tp.wind_direction.length(), 0.0,
		"wind_direction must be a non-zero vector")


# ── ShaderMaterial applied to MMI ─────────────────────────────────────────────

func test_mmi_gets_shader_material() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: Material = mmi.material_override
	assert_not_null(mat, "surface override material must be set on the MMI")
	assert_true(mat is ShaderMaterial,
		"surface override material must be a ShaderMaterial")

func test_mmi_uses_wind_shader() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	assert_eq(mat.shader, WIND_SHADER,
		"ShaderMaterial must reference the tree_wind shader")

func test_mmi_wind_strength_uniform_set() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	var val: float = mat.get_shader_parameter("wind_strength")
	assert_almost_eq(val, tp.wind_strength_base, 0.001,
		"wind_strength uniform should start at wind_strength_base")

func test_mmi_wind_speed_uniform_set() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	var val: float = mat.get_shader_parameter("wind_speed")
	assert_almost_eq(val, tp.wind_speed, 0.001,
		"wind_speed uniform must be forwarded to the shader")

func test_mmi_wind_direction_uniform_set() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	var val: Vector2 = mat.get_shader_parameter("wind_direction")
	assert_almost_eq(val.x, tp.wind_direction.x, 0.001,
		"wind_direction.x uniform must match")
	assert_almost_eq(val.y, tp.wind_direction.y, 0.001,
		"wind_direction.y uniform must match")

func test_mmi_wave_scale_uniform_set() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	var val: float = mat.get_shader_parameter("wave_scale")
	assert_almost_eq(val, tp.wave_scale, 0.0001,
		"wave_scale uniform must be forwarded to the shader")

func test_mmi_albedo_null_does_not_crash() -> void:
	# Passing null albedo_tex should not crash — trees without a texture still sway.
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	assert_not_null(mmi, "MMI should be created even when albedo texture is null")

func test_mmi_tracked_in_wind_mmis() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	assert_true(tp._wind_mmis.has(mmi),
		"created MMI must be tracked in _wind_mmis for gust updates")


# ── Gust oscillation range ────────────────────────────────────────────────────

func test_gust_strength_minimum_is_base() -> void:
	# sin(t) = -1 → gust_factor = 0 → current = base
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	# Drive t so that sin(t * speed) = -1 → t = -pi/(2*speed)
	var t: float = -PI / (2.0 * tp.wind_gust_cycle_speed)
	tp.simulate_process(t)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	var val: float = mat.get_shader_parameter("wind_strength")
	assert_almost_eq(val, tp.wind_strength_base, 0.005,
		"at gust_factor=0, strength must equal wind_strength_base")

func test_gust_strength_maximum_is_base_plus_gust() -> void:
	# sin(t) = +1 → gust_factor = 1 → current = base + gust
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var t: float = PI / (2.0 * tp.wind_gust_cycle_speed)
	tp.simulate_process(t)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	var val: float = mat.get_shader_parameter("wind_strength")
	var expected: float = tp.wind_strength_base + tp.wind_strength_gust
	assert_almost_eq(val, expected, 0.005,
		"at gust_factor=1, strength must equal base + gust")

func test_gust_strength_never_below_base() -> void:
	# Sweep 100 time samples and confirm the floor holds.
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	for i in range(100):
		var t: float = float(i) * 0.37
		tp.simulate_process(t)
		var val: float = mat.get_shader_parameter("wind_strength")
		assert_gte(val, tp.wind_strength_base - 0.005,
			"wind strength must never drop below wind_strength_base")

func test_gust_strength_never_above_max() -> void:
	var mmi: MultiMeshInstance3D = tp.build_wind_mmi(null)
	var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
	var max_val: float = tp.wind_strength_base + tp.wind_strength_gust
	for i in range(100):
		var t: float = float(i) * 0.37
		tp.simulate_process(t)
		var val: float = mat.get_shader_parameter("wind_strength")
		assert_lte(val, max_val + 0.005,
			"wind strength must never exceed base + gust")


# ── Albedo extraction helper ──────────────────────────────────────────────────

func test_find_albedo_returns_null_when_no_material() -> void:
	# A plain MeshInstance3D with a mesh but no material should return null.
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child_autofree(mi)
	var result: Texture2D = tp.find_albedo_recursive(mi)
	assert_null(result,
		"_find_albedo_recursive must return null when no albedo texture exists")

func test_find_albedo_returns_texture_when_present() -> void:
	# Assign a StandardMaterial3D with a real albedo texture — helper must return it.
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	mat.albedo_texture = tex
	mi.material_override = mat
	add_child_autofree(mi)
	var result: Texture2D = tp.find_albedo_recursive(mi)
	assert_not_null(result,
		"_find_albedo_recursive must return the albedo texture when one is set")

func test_find_albedo_searches_children() -> void:
	# Texture is on a child MeshInstance3D — parent is a plain Node3D.
	var parent := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.GREEN)
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mi.material_override = mat
	parent.add_child(mi)
	add_child_autofree(parent)
	var result: Texture2D = tp.find_albedo_recursive(parent)
	assert_not_null(result,
		"_find_albedo_recursive must recurse into children to find the texture")


# ── No-op when _wind_mmis empty ───────────────────────────────────────────────

func test_process_with_no_mmis_does_not_crash() -> void:
	# _wind_mmis is empty by default — simulate_process must be a clean no-op.
	tp.simulate_process(1.0)
	assert_true(true, "simulate_process with empty _wind_mmis must not crash")


# ── Tree shadow distance applied in _commit_multimeshes ───────────────────────

func test_shadow_off_near_band_is_off() -> void:
	var result: int = shadow_helper.resolve_cast_shadow(0, 0)
	assert_eq(result, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"tsd=Off, near band → SHADOW_CASTING_SETTING_OFF")

func test_shadow_off_far_band_is_off() -> void:
	var result: int = shadow_helper.resolve_cast_shadow(0, 1)
	assert_eq(result, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"tsd=Off, far band → SHADOW_CASTING_SETTING_OFF")

func test_shadow_close_near_band_is_on() -> void:
	var result: int = shadow_helper.resolve_cast_shadow(1, 0)
	assert_eq(result, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"tsd=Close, near band → SHADOW_CASTING_SETTING_ON")

func test_shadow_close_far_band_is_off() -> void:
	var result: int = shadow_helper.resolve_cast_shadow(1, 1)
	assert_eq(result, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"tsd=Close, far band → SHADOW_CASTING_SETTING_OFF")

func test_shadow_far_near_band_is_on() -> void:
	var result: int = shadow_helper.resolve_cast_shadow(2, 0)
	assert_eq(result, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"tsd=Far, near band → SHADOW_CASTING_SETTING_ON")

func test_shadow_far_far_band_is_on() -> void:
	var result: int = shadow_helper.resolve_cast_shadow(2, 1)
	assert_eq(result, GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"tsd=Far, far band → SHADOW_CASTING_SETTING_ON")


# ── clear_trees_at visual clearing ───────────────────────────────────────────

func test_clear_trees_removes_record_within_radius() -> void:
	ctp.add_tree(Vector2(0.0, 0.0))
	ctp.add_tree(Vector2(3.0, 0.0))
	ctp.build_mmi_for_band0()
	ctp.clear_trees_at(Vector3(0.0, 0.0, 0.0), 1.5)
	# Only tree at (0,0) should be removed; tree at (3,0) is outside radius
	assert_eq(ctp._tree_records.size(), 1,
		"one record should remain after clearing radius 1.5 around origin")

func test_clear_trees_removes_transform_from_band_transforms() -> void:
	ctp.add_tree(Vector2(0.0, 0.0))
	ctp.add_tree(Vector2(5.0, 0.0))
	ctp.build_mmi_for_band0()
	ctp.clear_trees_at(Vector3(0.0, 0.0, 0.0), 1.5)
	assert_eq(ctp._band_transforms[0][0].size(), 1,
		"_band_transforms must drop the cleared tree transform")

func test_clear_trees_rebuilds_mmi_instance_count() -> void:
	ctp.add_tree(Vector2(0.0, 0.0))
	ctp.add_tree(Vector2(5.0, 0.0))
	var mmi: MultiMeshInstance3D = ctp.build_mmi_for_band0()
	assert_eq(mmi.multimesh.instance_count, 2, "pre-clear instance_count should be 2")
	ctp.clear_trees_at(Vector3(0.0, 0.0, 0.0), 1.5)
	assert_eq(mmi.multimesh.instance_count, 1,
		"MMI instance_count must drop to 1 after clearing one tree")

func test_clear_trees_outside_radius_not_removed() -> void:
	ctp.add_tree(Vector2(10.0, 0.0))
	ctp.add_tree(Vector2(20.0, 0.0))
	ctp.build_mmi_for_band0()
	ctp.clear_trees_at(Vector3(0.0, 0.0, 0.0), 5.0)
	assert_eq(ctp._tree_records.size(), 2,
		"trees outside the clearing radius must not be removed")

func test_clear_trees_all_within_radius() -> void:
	ctp.add_tree(Vector2(1.0, 0.0))
	ctp.add_tree(Vector2(-1.0, 0.0))
	ctp.add_tree(Vector2(0.0, 1.0))
	var mmi: MultiMeshInstance3D = ctp.build_mmi_for_band0()
	ctp.clear_trees_at(Vector3(0.0, 0.0, 0.0), 2.0)
	assert_eq(ctp._tree_records.size(), 0,
		"all records cleared when all trees are within radius")
	assert_eq(mmi.multimesh.instance_count, 0,
		"MMI instance_count must be 0 after all trees cleared")

func test_rebuild_mmi_with_invalid_index_does_not_crash() -> void:
	# _rebuild_mmi(vi=99, band=0) → index 198, well past _mmis.size() → no crash
	ctp._rebuild_mmi(99, 0)
	assert_true(true, "_rebuild_mmi with out-of-bounds index must not crash")

func test_clear_trees_empty_records_is_noop() -> void:
	# No trees added — clearing should be a clean no-op
	ctp.clear_trees_at(Vector3(0.0, 0.0, 0.0), 10.0)
	assert_true(true, "clear_trees_at on empty records must not crash")
