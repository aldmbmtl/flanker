extends Area3D
## Health Pack — one-time pickup that restores 50 HP to the first friendly player who touches it.

const HEAL_AMOUNT := 50.0
const CRATE_MODEL_PATH := "res://assets/kenney_blaster-kit/Models/GLB format/crate-small.glb"

var team: int = -1  # -1 = any team can pick up

func _ready() -> void:
	connect("body_entered", _on_body_entered)
	add_to_group("supporter_drops")
	_build_visuals()

func setup(p_team: int) -> void:
	team = p_team

func _build_visuals() -> void:
	# Crate model base
	var packed: PackedScene = load(CRATE_MODEL_PATH)
	if packed:
		var crate: Node3D = packed.instantiate()
		crate.scale = Vector3(1.5, 1.5, 1.5)
		add_child(crate)

	# Green cross marker on top so it reads as a health pickup
	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(0.1, 0.9, 0.2)
	cross_mat.emission_enabled = true
	cross_mat.emission = Color(0.0, 1.0, 0.1)
	cross_mat.emission_energy_multiplier = 2.5

	var h := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(0.55, 0.08, 0.18)
	h.mesh = hbox
	h.material_override = cross_mat
	h.position = Vector3(0.0, 0.82, 0.0)
	add_child(h)

	var v := MeshInstance3D.new()
	var vbox := BoxMesh.new()
	vbox.size = Vector3(0.18, 0.08, 0.55)
	v.mesh = vbox
	v.material_override = cross_mat
	v.position = Vector3(0.0, 0.82, 0.0)
	add_child(v)

	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 1.0, 0.3)
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position = Vector3(0.0, 0.5, 0.0)
	add_child(light)

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("heal"):
		return
	# Only the local player's controller triggers pickup — prevents double-fire
	# on server (which has CharacterBody3D for all players) and ignores ghosts.
	var is_local: bool = body.get("_is_local") == true
	if not is_local:
		return
	if team != -1:
		var body_team: int = -1
		var pt = body.get("player_team")
		if pt != null:
			body_team = pt as int
		else:
			var t = body.get("team")
			if t != null:
				body_team = t as int
		if body_team != team:
			return
	body.heal(HEAL_AMOUNT)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			# rpc_id(1,...) from the server to itself is a no-op — call directly
			LobbyManager.despawn_drop.rpc(name)
		else:
			LobbyManager.notify_drop_picked_up.rpc_id(1, name)
	else:
		queue_free()
