extends TowerBase
## LauncherTower — manual-fire only, no auto-attack.
## Supports all launcher types defined in LauncherDefs.
## Extends TowerBase; health/death/hit-flash/damage all inherited.
## setup(team, launcher_type) overrides base to set tower_type from LauncherDefs.
## max_health and attack_range (0.0) are set via @export in the .tscn.

var launcher_type: String = "launcher_missile"

# Launcher-specific light ref (not in TowerBase)
var _light: OmniLight3D = null

# ── Entry point — called by BuildSystem.spawn_item_local() ───────────────────

func setup(p_team: int, p_launcher_type: String = "launcher_missile") -> void:
	launcher_type = p_launcher_type
	tower_type = p_launcher_type   # used by tower_despawned signal
	super.setup(p_team)            # sets _health = max_health, builds visuals, adds to group
	add_to_group("launchers")

# ── Visual construction ───────────────────────────────────────────────────────

func _build_visuals() -> void:
	# ── Collision body ────────────────────────────────────────────────────────
	var col_shape := CylinderShape3D.new()
	col_shape.radius = 1.2
	col_shape.height = 6.0
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0.0, 3.0, 0.0)
	add_child(col)

	# ── Launch tube mesh (programmatic cylinder) ──────────────────────────────
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.55
	cyl.bottom_radius = 0.8
	cyl.height        = 5.5
	cyl.radial_segments = 12

	var mat := StandardMaterial3D.new()
	var team_color: Color = Color(0.18, 0.45, 1.0) if team == 0 else Color(0.9, 0.15, 0.15)
	mat.albedo_color = team_color
	mat.roughness    = 0.6
	mat.metallic     = 0.6
	cyl.material = mat

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = cyl
	_mesh_inst.position = Vector3(0.0, 2.75, 0.0)
	add_child(_mesh_inst)

	# ── Base platform (box) ───────────────────────────────────────────────────
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(2.4, 0.5, 2.4)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.22, 0.22, 0.22)
	base_mat.roughness = 0.8
	base_mesh.material = base_mat
	var base_inst := MeshInstance3D.new()
	base_inst.mesh = base_mesh
	base_inst.position = Vector3(0.0, 0.25, 0.0)
	add_child(base_inst)

	# ── Ambient glow (dim until fired) ───────────────────────────────────────
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.1)
	_light.light_energy = 0.4
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 5.8, 0.0)
	add_child(_light)

	# Prepare hit-flash overlay (does NOT apply it — TowerBase._flash_hit handles that)
	_add_hit_overlay(_mesh_inst)

# ── Fire origin ───────────────────────────────────────────────────────────────

func get_fire_position() -> Vector3:
	return global_position + Vector3(0.0, 6.2, 0.0)
