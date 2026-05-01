## BasePlayer — base class for all player representations.
##
## Mirrors MinionBase's authority split:
##   is_local = true  → this peer owns this player (local FPS controller path)
##   is_local = false → puppet: lerp toward broadcast transform, drive animation
##
## Lifecycle:
##   1. PlayerManager (or Main.gd for the local player) instantiates the scene.
##   2. Call setup(peer_id, team, is_local, avatar_char) after instantiate(),
##      BEFORE add_child. PlayerManager sets is_local=false; Main.gd sets true.
##   3. _ready() wires HitBody.ghost_peer_id, adds to "players" group,
##      defers _init_visuals().
##   4. For is_local=false: _process() lerps position/rotation and drives
##      walk/idle animation. For is_local=true: FPSController._physics_process
##      drives input and broadcasts transform.
##   5. PlayerManager calls _set_alive(bool) on visibility changes.
##      FPSController overrides _on_died() / _on_respawned() for HUD/camera effects.
##
## Adding a new player type — checklist:
##   1. Create scripts/players/MyPlayer.gd extending BasePlayer.
##   2. Override _build_visuals() for custom mesh setup.
##   3. Override _on_died() / _on_respawned() for custom death/respawn effects.
##   4. Create scenes/players/MyPlayer.tscn inheriting BasePlayer.tscn.
##   5. Write tests for any new combat or sync logic.

class_name BasePlayer
extends CharacterBody3D

# ── Identity ──────────────────────────────────────────────────────────────────

## Multiplayer peer ID this node represents.
@export var peer_id: int = 0
## Team index (0 = blue, 1 = red).
@export var player_team: int = 0
## True when this instance is owned by the local peer.
## Set by setup() before add_child — never change after that.
var is_local: bool = false
## Avatar character letter (a–f). Drives _load_model.
var avatar_char: String = ""

# ── Puppet lerp ───────────────────────────────────────────────────────────────

var _target_position: Vector3 = Vector3.ZERO
var _target_rotation: Vector3 = Vector3.ZERO
var _prev_pos: Vector3        = Vector3.ZERO
const LERP_SPEED := 15.0

# ── Visuals ───────────────────────────────────────────────────────────────────

var _anim: AnimationPlayer = null
var _model_loaded: bool    = false
var _current_char: String  = ""

const FALLBACK_CHAR  := "a"
const GLB_BASE_PATH  := "res://assets/kenney_blocky-characters/Models/GLB format/character-%s.glb"

# ── Setup ─────────────────────────────────────────────────────────────────────

## Call this BEFORE add_child so _ready() sees the correct values.
func setup(p_peer_id: int, p_team: int, p_is_local: bool, p_avatar_char: String) -> void:
	peer_id     = p_peer_id
	player_team = p_team
	is_local    = p_is_local
	avatar_char = p_avatar_char
	print("[BP] setup peer_id=", peer_id,
		" team=", player_team,
		" is_local=", is_local,
		" avatar_char='", avatar_char, "'")

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	print("[BP] _ready peer_id=", peer_id,
		" is_local=", is_local,
		" team=", player_team,
		" avatar_char='", avatar_char, "'")
	add_to_group("players")
	if not is_local:
		add_to_group("remote_players")

	# Wire HitBody so raycasts can identify which peer this node represents.
	var hit_body: StaticBody3D = get_node_or_null("HitBody")
	if hit_body != null:
		hit_body.set_meta("ghost_peer_id", peer_id)
		# Local player: disable the HitShape so the CharacterBody3D capsule does
		# not collide with the sibling StaticBody3D hitbox and launch the player
		# upward on spawn. Remote puppets keep the hitbox active for raycasts.
		if is_local:
			var hit_shape: CollisionShape3D = hit_body.get_node_or_null("HitShape")
			if hit_shape != null:
				hit_shape.disabled = true
				print("[BP] _ready peer_id=", peer_id, " HitShape disabled (is_local=true)")
			else:
				push_warning("[BasePlayer] peer_id=%d HitShape not found inside HitBody" % peer_id)
		else:
			print("[BP] _ready peer_id=", peer_id, " HitShape kept active (is_local=false, puppet)")
	else:
		push_warning("[BasePlayer] peer_id=%d HitBody not found — hitbox will not work" % peer_id)

	# Seed puppet lerp target so the node doesn't jump from origin on first frame.
	_target_position = global_position
	_target_rotation = rotation

	call_deferred("_init_visuals")

## Override to build custom visual elements after the node enters the tree.
## Called deferred from _ready(). Default: loads avatar model.
func _build_visuals() -> void:
	pass

func _init_visuals() -> void:
	_build_visuals()

	# Load correct avatar immediately if known; otherwise load fallback and wait
	# for lobby_updated. Call _load_model exactly ONCE — loading fallback then
	# immediately overwriting causes a same-frame queue_free which triggers
	# Godot's internal visibility_changed, silently setting visible=false on the root.
	if not _try_load_avatar():
		print("[BP] _init_visuals peer_id=", peer_id,
			" avatar not yet known — loading fallback char='", FALLBACK_CHAR, "'")
		_load_model(FALLBACK_CHAR)
		LobbyManager.lobby_updated.connect(_on_lobby_updated)
	else:
		print("[BP] _init_visuals peer_id=", peer_id,
			" avatar loaded immediately char='", _current_char, "'")

# ── Puppet process ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if is_local:
		return  # FPSController drives the local player

	# Lerp puppet toward broadcast target.
	global_position = global_position.lerp(_target_position, LERP_SPEED * delta)
	rotation.y      = lerp_angle(rotation.y, _target_rotation.y, LERP_SPEED * delta)

	# Drive walk/idle animation from actual movement speed.
	if _anim != null and _anim.is_inside_tree():
		var moved: float       = global_position.distance_to(_prev_pos)
		var horiz_speed: float = moved / maxf(delta, 0.001)
		var want_anim: String  = "walk" if horiz_speed > 0.3 else "idle"
		if _anim.current_animation != want_anim:
			_anim.play(want_anim)

	_prev_pos = global_position

## Called by PlayerManager each time a broadcast transform arrives.
## Logs only the first call and any jump larger than 5 m to avoid per-frame noise.
func update_transform(pos: Vector3, rot: Vector3) -> void:
	var jump: float = _target_position.distance_to(pos)
	if not _model_loaded or jump > 5.0:
		print("[BP] update_transform peer_id=", peer_id,
			" pos=", pos, " rot_y=", rot.y,
			" jump=", snappedf(jump, 0.01),
			" first_call=", not _model_loaded)
	_target_position = pos
	_target_rotation = rot

# ── Visibility / hitbox ───────────────────────────────────────────────────────

## Toggle visibility and hitbox collision layers.
## Called by PlayerManager on player_died / player_respawned signals.
## Override _on_died() / _on_respawned() for additional effects.
func _set_alive(alive: bool) -> void:
	print("[BP] _set_alive peer_id=", peer_id, " alive=", alive,
		" prev_visible=", visible)
	visible = alive
	var hit_body: StaticBody3D = get_node_or_null("HitBody")
	if hit_body != null:
		hit_body.set_collision_layer(1 if alive else 0)
		hit_body.set_collision_mask(0)
		print("[BP] _set_alive peer_id=", peer_id,
			" HitBody.collision_layer=", hit_body.get_collision_layer())
	if alive:
		_on_respawned(global_position if is_inside_tree() else Vector3.ZERO)
	else:
		_on_died()

## Overridable hook — fired when this player is marked dead.
## FPSController overrides this for camera shake, HUD updates, etc.
func _on_died() -> void:
	pass

## Overridable hook — fired when this player respawns.
func _on_respawned(_spawn_pos: Vector3) -> void:
	pass

# ── Damage interface ──────────────────────────────────────────────────────────

## Direct damage entry point used by singleplayer path and tests.
## Multiplayer: server calls GameSync.damage_player → GameSync.player_died signal
## → PlayerManager._on_player_died → _set_alive(false).
## Override in FPSController for skill passives, camera shake, etc.
func take_damage(amount: float, source: String, source_team: int, shooter_peer_id: int) -> void:
	pass

# ── Avatar model loading ──────────────────────────────────────────────────────

func _on_lobby_updated() -> void:
	if _try_load_avatar():
		print("[BP] _on_lobby_updated peer_id=", peer_id,
			" avatar loaded char='", _current_char, "' — disconnecting lobby_updated")
		LobbyManager.lobby_updated.disconnect(_on_lobby_updated)
	else:
		print("[BP] _on_lobby_updated peer_id=", peer_id,
			" avatar still not available — waiting for next lobby_updated")

func _try_load_avatar() -> bool:
	if peer_id <= 0:
		print("[BP] _try_load_avatar peer_id=", peer_id, " → false (no peer_id)")
		return false
	var info: Dictionary = LobbyManager.players.get(peer_id, {})
	var char: String     = info.get("avatar_char", "") as String
	if char.is_empty():
		# Fallback: use the avatar_char set directly on this node (local player path).
		char = avatar_char
	if char.is_empty():
		print("[BP] _try_load_avatar peer_id=", peer_id,
			" → false (no char in lobby or avatar_char)")
		return false
	if char == _current_char and _model_loaded:
		return true
	print("[BP] _try_load_avatar peer_id=", peer_id,
		" char='", char, "' _current_char='", _current_char, "' → loading")
	_load_model(char)
	return true

func _load_model(char: String) -> void:
	var glb_path: String = GLB_BASE_PATH % char
	print("[BP] _load_model peer_id=", peer_id,
		" char='", char, "' path='", glb_path, "'")
	if not ResourceLoader.exists(glb_path):
		push_warning("[BasePlayer] peer_id=%d could not load '%s'" % [peer_id, glb_path])
		return
	var packed: PackedScene = load(glb_path) as PackedScene
	if packed == null:
		push_warning("[BasePlayer] peer_id=%d could not load '%s'" % [peer_id, glb_path])
		return

	var char_mesh_node: Node3D = get_node_or_null("PlayerBody/CharacterMesh")
	if char_mesh_node == null:
		push_warning("[BasePlayer] peer_id=%d PlayerBody/CharacterMesh not found" % peer_id)
		return

	# Add new model BEFORE freeing old children — no blank frame.
	var old_children: Array = char_mesh_node.get_children()
	print("[BP] _load_model peer_id=", peer_id,
		" replacing ", old_children.size(), " old child(ren) is_local=", is_local)

	var model: Node3D = packed.instantiate()
	model.scale = Vector3(0.667, 0.667, 0.667)
	model.rotate_y(PI)

	# Local player: render avatar on layer 2 only so the FPS camera (cull_mask
	# excludes layer 2) never sees its own body, but all other cameras do.
	if is_local:
		_set_layers_recursive(model, 2)

	char_mesh_node.add_child(model)
	char_mesh_node.visible = true

	for c in old_children:
		c.queue_free()

	_anim = _find_anim_player(model)
	if _anim != null:
		_anim.play("idle")

	_current_char  = char
	_model_loaded  = true
	print("[BP] _load_model peer_id=", peer_id,
		" done char='", _current_char, "' anim=", (_anim != null))

func _set_layers_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for child in node.get_children():
		_set_layers_recursive(child, layer)

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim_player(child)
		if found != null:
			return found
	return null
