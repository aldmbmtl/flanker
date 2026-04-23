extends Area3D

var weapon_data: WeaponData = null

var _mesh_inst: MeshInstance3D = null
var _bob_tween: Tween = null

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	_mesh_inst = $MeshInstance3D
	# Load the weapon mesh dynamically from the WeaponData resource
	if weapon_data != null and weapon_data.mesh_path != "":
		var packed: PackedScene = load(weapon_data.mesh_path)
		if packed:
			var model: Node3D = packed.instantiate()
			model.scale = Vector3(2.0, 2.0, 2.0)
			add_child(model)
			_mesh_inst.visible = false
	# Float + spin animation
	_start_bob()

func _start_bob() -> void:
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(self, "position:y", position.y + 0.4, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(self, "position:y", position.y, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	rotate_y(delta * 1.2)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("pick_up_weapon") and weapon_data != null:
		body.pick_up_weapon(weapon_data)
		if has_node("AudioStreamPlayer3D"):
			var asp: AudioStreamPlayer3D = $AudioStreamPlayer3D
			asp.play()
			# Detach from parent deferred (cannot modify CollisionObject during physics)
			call_deferred("_detach_and_finish", asp)
		else:
			queue_free()

func _detach_and_finish(asp: AudioStreamPlayer3D) -> void:
	var root: Node = get_tree().root.get_child(0)
	get_parent().remove_child(self)
	root.add_child(self)
	await asp.finished
	queue_free()
