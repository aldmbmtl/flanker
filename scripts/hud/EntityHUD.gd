## EntityHUD.gd
## Supporter-only overlay that draws:
##   - Health bars above friendly towers (always visible in Supporter role)
##   - Coloured ground circles under all players:
##       green = friendly, red = enemy, grey = team unknown
##       Enemy circles are fog-gated (only shown when within allied vision range)
##
## Attach script at runtime via set_script() from Main.gd after role selection.
## Wire via EntityHUD.setup(player_team).

extends Control

# ── Configuration ─────────────────────────────────────────────────────────────

const BAR_WIDTH     := 60.0
const BAR_HEIGHT    := 8.0
const BAR_Y_OFFSET  := -14.0   # pixels above the projected tower position

const CIRCLE_W      := 52.0    # circle diameter in pixels
const CIRCLE_H      := 52.0    # equal to CIRCLE_W for a true circle
const CIRCLE_THICK  := 2.5     # outline stroke width

const COL_BAR_BG    := Color(0.1, 0.1, 0.1, 0.75)
const COL_HP_HIGH   := Color(0.18, 0.85, 0.22, 0.90)
const COL_HP_LOW    := Color(0.90, 0.18, 0.12, 0.90)
const COL_FRIENDLY  := Color(0.15, 0.95, 0.25, 0.85)
const COL_ENEMY     := Color(0.95, 0.15, 0.15, 0.85)
const COL_UNKNOWN   := Color(0.80, 0.80, 0.80, 0.70)

const PLAYER_VISION_RADIUS := 35.0
const MINION_VISION_RADIUS := 25.0
const TOWER_VISION_RADIUS  := 30.0

# ── State ─────────────────────────────────────────────────────────────────────

var _player_team: int = 0
var _camera: Camera3D = null

# ── Public API ────────────────────────────────────────────────────────────────

func setup(player_team: int) -> void:
	_player_team = player_team
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	# Seed GameSync.player_teams from lobby state on all peers and keep it warm.
	_sync_teams_from_lobby()
	if not LobbyManager.lobby_updated.is_connected(_sync_teams_from_lobby):
		LobbyManager.lobby_updated.connect(_sync_teams_from_lobby)

func _sync_teams_from_lobby() -> void:
	for pid in LobbyManager.players:
		var info: Dictionary = LobbyManager.players[pid]
		if info.has("team"):
			var t: int = info["team"]
			GameSync.set_player_team(pid, t)

# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_camera = get_viewport().get_camera_3d()
	queue_redraw()

func _draw() -> void:
	if _camera == null:
		return
	_draw_tower_bars()
	_draw_player_circles()

# ── Tower health bars ─────────────────────────────────────────────────────────

func _draw_tower_bars() -> void:
	var towers: Array = get_tree().get_nodes_in_group("towers")
	for tower in towers:
		if not is_instance_valid(tower):
			continue
		var t_team: int = -1
		if "team" in tower:
			t_team = tower.team
		if t_team != _player_team:
			continue
		if not tower.has_method("get_health"):
			continue

		var hp: float     = tower.get_health()
		var max_hp: float = tower.get_max_health()
		if max_hp <= 0.0:
			continue

		var world_pos: Vector3 = tower.global_position + Vector3(0.0, 3.5, 0.0)
		if _camera.is_position_behind(world_pos):
			continue
		var screen_pos: Vector2 = _camera.unproject_position(world_pos)

		var vp_size: Vector2 = get_viewport_rect().size
		if screen_pos.x < 0.0 or screen_pos.x > vp_size.x or \
		   screen_pos.y < 0.0 or screen_pos.y > vp_size.y:
			continue

		var bar_origin: Vector2 = Vector2(
			screen_pos.x - BAR_WIDTH * 0.5,
			screen_pos.y + BAR_Y_OFFSET - BAR_HEIGHT * 0.5
		)

		draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), COL_BAR_BG)

		var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		var fill_col: Color = COL_HP_HIGH.lerp(COL_HP_LOW, 1.0 - ratio)
		draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH * ratio, BAR_HEIGHT)), fill_col)

# ── Player ground circles ─────────────────────────────────────────────────────

func _draw_player_circles() -> void:
	# Local FPS player (Fighter role only)
	var local_players: Array = get_tree().get_nodes_in_group("player")
	for p in local_players:
		if not is_instance_valid(p):
			continue
		var p_team: int = _player_team
		if "player_team" in p:
			p_team = p.player_team
		if p_team != _player_team and not _is_revealed(p.global_position):
			continue
		_draw_circle_for_pos(p.global_position, p_team)

	# Remote player ghosts (multiplayer only)
	var ghosts: Array = get_tree().get_nodes_in_group("remote_players")
	for ghost in ghosts:
		if not is_instance_valid(ghost):
			continue
		var peer_id: int = 0
		if "peer_id" in ghost:
			peer_id = ghost.peer_id
		if peer_id <= 0:
			continue
		var g_team: int = GameSync.get_player_team(peer_id)
		if g_team < 0:
			var info: Dictionary = LobbyManager.players.get(peer_id, {})
			if info.has("team"):
				g_team = info["team"]
		if g_team != _player_team and not _is_revealed(ghost.global_position):
			continue
		_draw_circle_for_pos(ghost.global_position, g_team)

# ── Fog visibility check ──────────────────────────────────────────────────────

func _is_revealed(world_pos: Vector3) -> bool:
	var player_vis_sq: float = PLAYER_VISION_RADIUS * PLAYER_VISION_RADIUS

	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var t: int = _player_team
		if "player_team" in p:
			t = p.player_team
		if t == _player_team and world_pos.distance_squared_to(p.global_position) <= player_vis_sq:
			return true

	for ghost in get_tree().get_nodes_in_group("remote_players"):
		if not is_instance_valid(ghost):
			continue
		var pid: int = 0
		if "peer_id" in ghost:
			pid = ghost.peer_id
		var t: int = GameSync.get_player_team(pid)
		if t < 0:
			var info: Dictionary = LobbyManager.players.get(pid, {})
			if info.has("team"):
				t = info["team"]
		if t == _player_team and world_pos.distance_squared_to(ghost.global_position) <= player_vis_sq:
			return true

	var minion_vis_sq: float = MINION_VISION_RADIUS * MINION_VISION_RADIUS
	for minion in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(minion):
			continue
		var t: int = -1
		if "team" in minion:
			t = minion.team
		if t == _player_team and world_pos.distance_squared_to(minion.global_position) <= minion_vis_sq:
			return true

	var tower_vis_sq: float = TOWER_VISION_RADIUS * TOWER_VISION_RADIUS
	for tower in get_tree().get_nodes_in_group("towers"):
		if not is_instance_valid(tower):
			continue
		var t: int = -1
		if "team" in tower:
			t = tower.team
		if t == _player_team and world_pos.distance_squared_to(tower.global_position) <= tower_vis_sq:
			return true

	return false

# ── Draw ellipse ──────────────────────────────────────────────────────────────

func _draw_circle_for_pos(world_pos: Vector3, entity_team: int) -> void:
	var foot: Vector3 = world_pos + Vector3(0.0, 0.15, 0.0)
	if _camera.is_position_behind(foot):
		return
	var screen_pos: Vector2 = _camera.unproject_position(foot)

	var vp_size: Vector2 = get_viewport_rect().size
	if screen_pos.x < -CIRCLE_W or screen_pos.x > vp_size.x + CIRCLE_W or \
	   screen_pos.y < -CIRCLE_H or screen_pos.y > vp_size.y + CIRCLE_H:
		return

	var col: Color
	if entity_team < 0:
		col = COL_UNKNOWN
	elif entity_team == _player_team:
		col = COL_FRIENDLY
	else:
		col = COL_ENEMY

	var segments: int = 32
	var prev: Vector2 = screen_pos + Vector2(CIRCLE_W * 0.5, 0.0)
	for i in range(1, segments + 1):
		var angle: float = (float(i) / float(segments)) * TAU
		var next: Vector2 = screen_pos + Vector2(
			cos(angle) * CIRCLE_W * 0.5,
			sin(angle) * CIRCLE_H * 0.5
		)
		draw_line(prev, next, col, CIRCLE_THICK, true)
		prev = next
