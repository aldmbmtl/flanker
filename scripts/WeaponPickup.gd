extends Area3D

signal weapon_picked_up(pos: Vector3)

var weapon_data: WeaponData = null

var _mesh_inst: MeshInstance3D = null
var _glow_light: OmniLight3D = null

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	_mesh_inst = $MeshInstance3D
	if weapon_data != null and weapon_data.mesh_path != "":
		var packed: PackedScene = load(weapon_data.mesh_path)
		if packed:
			var model: Node3D = packed.instantiate()
			model.scale = Vector3(2.0, 2.0, 2.0)
			add_child(model)
			_mesh_inst.visible = false
	_add_glow_light()

func _add_glow_light() -> void:
	if weapon_data == null:
		return
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = weapon_data.glow_color
	_glow_light.light_energy = 0.2
	_glow_light.omni_range = 4.0
	_glow_light.position = Vector3(0.0, 0.5, 0.0)
	add_child(_glow_light)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("pick_up_weapon") and weapon_data != null:
		# Supporter-placed drops sync despawn to all peers via Python bridge.
		if get_meta("supporter_placed", false):
			body.pick_up_weapon(weapon_data)
			BridgeClient.send("drop_picked_up", {"name": str(name)})
			return
		# Natural pickup path — emit signal for Main.gd respawn timer, then free.
		# Detach audio before sending drop_picked_up so the node can queue_free
		# when drop_despawned arrives without cutting the sound short.
		weapon_picked_up.emit(global_position)
		body.pick_up_weapon(weapon_data)
		if has_node("AudioStreamPlayer3D"):
			var asp: AudioStreamPlayer3D = $AudioStreamPlayer3D
			asp.play()
			call_deferred("_detach_and_finish", asp)
		if BridgeClient.is_connected_to_server():
			BridgeClient.send("drop_picked_up", {"name": str(name)})
		else:
			queue_free()

func _detach_and_finish(asp: AudioStreamPlayer3D) -> void:
	var root: Node = VfxUtils.get_scene_root(self)
	get_parent().remove_child(self)
	root.add_child(self)
	await asp.finished
	queue_free()
