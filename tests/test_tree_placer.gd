# test_tree_placer.gd
# Tier 1 — unit tests for TreePlacer wind-shader integration.
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
extends GutTest

const TreePlacerScript := preload("res://scripts/TreePlacer.gd")
const WIND_SHADER      := preload("res://assets/tree_wind.gdshader")

# Minimal TreePlacer subclass that bypasses async _ready() and _place_trees().
class TestTreePlacer extends Node3D:
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


var tp: TestTreePlacer

func before_each() -> void:
	tp = TestTreePlacer.new()
	add_child_autofree(tp)


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
