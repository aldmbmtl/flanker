## BarrierTowerAI.gd — Barrier wall (TowerBase subclass).
## Passive fortification: no attack, no Area3D, blocks movement.
## Stats configured via @export in BarrierTower.tscn.
## Overrides _build_visuals to load wall.glb and add body collision in code.

extends TowerBase

const WALL_MODEL_PATH := "res://assets/kenney_fantasy-town-kit/Models/GLB format/wall.glb"

# ── Visuals + collision — all built in code ───────────────────────────────────

func _build_visuals() -> void:
	var packed: PackedScene = load(WALL_MODEL_PATH)
	if packed == null:
		push_error("BarrierTowerAI: wall.glb not found at " + WALL_MODEL_PATH)
		return
	var root: Node3D = packed.instantiate() as Node3D
	if root == null:
		return
	root.scale = Vector3(2.0, 3.0, 2.0)
	add_child(root)

	# Cache mesh for hit-flash
	var meshes: Array = find_children("*", "MeshInstance3D", true, false)
	if meshes.size() > 0:
		_mesh_inst = meshes[0] as MeshInstance3D
		_add_hit_overlay(_mesh_inst)

	# Body collision — 2 wide × 3 tall × 0.5 deep
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 0.5)
	col.shape = box
	col.position = Vector3(0.0, 1.5, 0.0)
	add_child(col)
