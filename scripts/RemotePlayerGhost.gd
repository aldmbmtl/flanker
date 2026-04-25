extends Node3D

var peer_id: int = 0
var target_position: Vector3 = Vector3.ZERO
var target_rotation: Vector3 = Vector3.ZERO
const LERP_SPEED := 15.0

var _anim: AnimationPlayer = null
var _prev_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("remote_players")
	# Wire the hitbox meta so raycasts can identify this ghost's peer
	var hit_body: StaticBody3D = get_node_or_null("HitBody")
	if hit_body != null:
		hit_body.set_meta("ghost_peer_id", peer_id)

	# Try to load avatar char from LobbyManager — may not be populated yet
	var char_loaded: bool = _try_load_avatar()
	if not char_loaded:
		# Wait for lobby_updated signal in case players dict isn't synced yet
		LobbyManager.lobby_updated.connect(_on_lobby_updated)

func _on_lobby_updated() -> void:
	if _try_load_avatar():
		LobbyManager.lobby_updated.disconnect(_on_lobby_updated)

func _try_load_avatar() -> bool:
	if peer_id <= 0:
		return false
	var info: Dictionary = LobbyManager.players.get(peer_id, {})
	var char: String = info.get("avatar_char", "") as String
	if char.is_empty():
		return false
	_load_model(char)
	return true

func _load_model(char: String) -> void:
	var glb_path: String = "res://assets/kenney_blocky-characters/Models/GLB format/character-%s.glb" % char
	var packed: PackedScene = load(glb_path)
	if packed == null:
		push_warning("[RemotePlayerGhost] could not load %s" % glb_path)
		return

	# Replace CharacterMesh contents with the correct model
	var char_mesh_node: Node3D = get_node_or_null("PlayerBody/CharacterMesh")
	if char_mesh_node == null:
		return
	for c in char_mesh_node.get_children():
		c.queue_free()

	var model: Node3D = packed.instantiate()
	model.scale = Vector3(0.667, 0.667, 0.667)
	model.rotate_y(PI)
	char_mesh_node.add_child(model)
	char_mesh_node.visible = true

	# Find AnimationPlayer
	_anim = _find_anim_player(model)
	if _anim != null:
		_anim.play("idle")

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null

func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position, LERP_SPEED * delta)
	rotation.y = lerp_angle(rotation.y, target_rotation.y, LERP_SPEED * delta)

	# Drive walk/idle from how much the ghost is actually moving
	if _anim != null and _anim.is_inside_tree():
		var moved: float = global_position.distance_to(_prev_pos)
		var horiz_speed: float = moved / max(delta, 0.001)
		var want_anim: String = "walk" if horiz_speed > 0.3 else "idle"
		if _anim.current_animation != want_anim:
			_anim.play(want_anim)
	_prev_pos = global_position

func update_transform(pos: Vector3, rot: Vector3) -> void:
	target_position = pos
	target_rotation = rot
