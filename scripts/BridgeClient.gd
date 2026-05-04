## BridgeClient.gd
## Autoload singleton — connects Godot to the Python game server.
##
## Phase 0 responsibilities:
##   - Connect to the Python server over TCP on demand (call connect_to_server)
##   - Expose send(type, payload) to push events to Python
##   - Read incoming StateUpdate messages every frame and emit message_received
##   - Log connection state changes
##
## Connection is NOT automatic on launch.  The StartMenu drives it:
##   - Host flow: BridgeClient.connect_to_server("127.0.0.1", bridge_port)
##   - Join flow: BridgeClient.connect_to_server(host_address, bridge_port)
##
## Signals:
##   message_received(type: String, payload: Dictionary)
##   connected_to_server
##   disconnected_from_server
##
## Usage:
##   BridgeClient.connect_to_server("127.0.0.1", 7890)
##   BridgeClient.send("ping", {"timestamp": Time.get_unix_time_from_system()})
##   BridgeClient.message_received.connect(_on_bridge_message)
extends Node

signal message_received(type: String, payload: Dictionary)
signal connected_to_server
signal disconnected_from_server

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

const DEFAULT_PORT := 7890

## How many bytes to attempt to read per frame before yielding.
const MAX_READ_PER_FRAME := 65536

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _peer: StreamPeerTCP = null
var _read_buf: PackedByteArray = PackedByteArray()
var _connected: bool = false

## Local peer ID assigned by the Python server via lobby_state messages.
var _local_peer_id: int = 0

## True when this client is the session host (first to register).
var _is_host: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	pass  # Connection is driven by the UI — see connect_to_server().


func _process(_delta: float) -> void:
	if _peer == null:
		return

	_peer.poll()
	var status: int = _peer.get_status()

	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			if not _connected:
				_connected = true
				print("[BridgeClient] connected to Python server")
				connected_to_server.emit()
			_read_available()

		StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR:
			if _connected:
				_connected = false
				print("[BridgeClient] disconnected from Python server")
				disconnected_from_server.emit()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Initiate a TCP connection to the Python game server.
## Call this once from the StartMenu after the player confirms Host or Join.
func connect_to_server(host: String, port: int) -> void:
	_peer = StreamPeerTCP.new()
	var err: int = _peer.connect_to_host(host, port)
	if err != OK:
		push_error("[BridgeClient] connect_to_host failed: %d (host=%s port=%d)" % [err, host, port])
		_peer = null
		return
	print("[BridgeClient] connecting to %s:%d …" % [host, port])


## Cleanly close the TCP connection to the Python server.
## Safe to call when already disconnected (no-op in that case).
func disconnect_from_server() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _connected:
		_connected = false
		disconnected_from_server.emit()


## Send an event to the Python server.
## type:    event type string, e.g. "ping"
## payload: Dictionary of event-specific fields
func send(type: String, payload: Dictionary) -> void:
	if not _connected:
		push_warning("BridgeClient.send: not connected (type=%s)" % type)
		return

	var event := {
		"type":      type,
		"sender_id": _local_peer_id,
		"payload":   payload,
	}
	var body: PackedByteArray = MsgPack.encode(event)
	# length-prefix: 4-byte big-endian uint32
	var header := PackedByteArray()
	var length: int = body.size()
	header.append((length >> 24) & 0xff)
	header.append((length >> 16) & 0xff)
	header.append((length >>  8) & 0xff)
	header.append(length & 0xff)

	# Send header + body as a single put_data call. Two separate calls are not
	# atomic — a flush boundary between them causes the Python server to read the
	# next message's header as the body of the current one, producing
	# "ValueError: Unpack failed: incomplete input" in msgpack.unpackb.
	_peer.put_data(header + body)


func is_connected_to_server() -> bool:
	return _connected


## Returns true when this client is the session host (first to register).
func is_host() -> bool:
	return _is_host


## Returns the local peer ID assigned by the Python server.
## Returns 0 before the first lobby_state message is received.
func get_peer_id() -> int:
	return _local_peer_id

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _read_available() -> void:
	# Drain available bytes into _read_buf, then parse complete frames.
	var available: int = _peer.get_available_bytes()
	if available <= 0:
		return
	var to_read: int = min(available, MAX_READ_PER_FRAME)
	var result: Array = _peer.get_data(to_read)
	if result[0] == OK:
		_read_buf.append_array(result[1])
	_parse_frames()


func _parse_frames() -> void:
	# Messages are length-prefixed: 4-byte big-endian uint32 + msgpack body.
	while _read_buf.size() >= 4:
		var length: int = (
			(_read_buf[0] << 24) |
			(_read_buf[1] << 16) |
			(_read_buf[2] <<  8) |
			_read_buf[3]
		)
		if _read_buf.size() < 4 + length:
			break  # wait for more data

		var body: PackedByteArray = _read_buf.slice(4, 4 + length)
		_read_buf = _read_buf.slice(4 + length)

		var decoded = MsgPack.decode(body)
		if typeof(decoded) == TYPE_DICTIONARY:
			var msg_type: String = str(decoded.get("type", ""))
			var payload: Dictionary = decoded.get("payload", {})
			if msg_type != "":
				_handle_server_message(msg_type, payload)
				message_received.emit(msg_type, payload)
		else:
			push_warning("[BridgeClient] received non-dict message, ignoring")


# Handles server messages that require immediate autoload side-effects before
# the generic message_received signal propagates to other listeners.
func _handle_server_message(msg_type: String, payload: Dictionary) -> void:
	match msg_type:
		"game_started":
			GameSync.game_seed = int(payload.get("map_seed", 0))
			var lane_data = payload.get("lane_points", [])
			if lane_data is Array and lane_data.size() == 3:
				LaneData.populate_from_server(lane_data)
			else:
				push_warning("[BridgeClient] game_started missing valid lane_points; LaneData will self-generate")
		"all_roles_confirmed":
			LobbyManager.all_roles_confirmed.emit()
		"role_accepted":
			# Python accepted the role claim. Update local supporter_claimed and
			# emit role_slots_updated so Main.gd's await resolves and
			# RoleSelectDialog reflects the correct slot state.
			var claimed: Dictionary = payload.get("supporter_claimed", {})
			LobbyManager.supporter_claimed[0] = bool(claimed.get(0, false))
			LobbyManager.supporter_claimed[1] = bool(claimed.get(1, false))
			LobbyManager.role_slots_updated.emit(LobbyManager.supporter_claimed)
		"role_rejected":
			# Python rejected the Supporter claim (slot already taken).
			# Update local state so the dialog grays out the correct button,
			# and emit role_slots_updated so Main.gd's await resolves.
			var claimed: Dictionary = payload.get("supporter_claimed", {})
			LobbyManager.supporter_claimed[0] = bool(claimed.get(0, false))
			LobbyManager.supporter_claimed[1] = bool(claimed.get(1, false))
			LobbyManager.role_slots_updated.emit(LobbyManager.supporter_claimed)
		"cooldown_tick":
			var peer_id: int = payload.get("peer_id", -1)
			var cooldowns: Dictionary = payload.get("cooldowns", {})
			if peer_id != -1:
				SkillTree._apply_bridge_cooldown_tick(peer_id, cooldowns)
		"player_health":
			var pid: int = payload.get("peer_id", -1)
			var hp: float = float(payload.get("health", 0.0))
			if pid != -1:
				var old_hp: float = GameSync.player_healths.get(pid, 0.0)
				GameSync.set_player_health(pid, hp)
				# If this is the local FPS player and HP increased (heal), apply
				# directly so the health bar and heal-flash update immediately.
				if pid == _local_peer_id and hp > old_hp:
					var fps: Node = get_node_or_null("/root/Main/FPSPlayer_%d" % pid)
					if fps != null and fps.has_method("heal"):
						fps.call("heal", hp - old_hp)
		"player_died":
			var pid: int = payload.get("peer_id", -1)
			var rt: float = float(payload.get("respawn_time", 10.0))
			if pid != -1:
				GameSync.player_dead[pid] = true
				GameSync.player_died.emit(pid, rt)
		"player_respawned":
			var pid: int = payload.get("peer_id", -1)
			var sp: Array = payload.get("spawn_pos", [0.0, 0.0, 0.0])
			var hp: float = float(payload.get("health", float(GameSync.PLAYER_MAX_HP)))
			if pid != -1:
				GameSync.player_dead[pid] = false
				GameSync.set_player_health(pid, hp)
				var spawn_vec := Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
				GameSync.player_respawned.emit(pid, spawn_vec)
	"level_up":
		# Python is authoritative for XP/level. Apply the new level and pts
		# into LevelSystem so all bonus-stat queries stay accurate, then emit
		# the level_up signal so Main.gd can show the LevelUpDialog.
		var pid: int = payload.get("peer_id", -1)
		var new_level: int = payload.get("new_level", 1)
		var pts_awarded: int = payload.get("pts_awarded", 0)
		if pid != -1:
			if not LevelSystem._level.has(pid):
				LevelSystem.register_peer(pid)
			LevelSystem._level[pid] = new_level
			# Only update points if Python explicitly sent the new total (not an increment).
			# Python sends the new total points, not a delta.
			var new_pts: int = payload.get("new_pts", -1)
			if new_pts >= 0:
				LevelSystem._points[pid] = new_pts
			else:
				LevelSystem._points[pid] = LevelSystem._points.get(pid, 0) + pts_awarded
			LevelSystem.level_up.emit(pid, new_level)
			# Only accumulate pending points for the local player (for LevelUpDialog).
			# Use a separate server-sent flag to avoid double-counting.
			if pid == _local_peer_id:
				LevelSystem._pending_levelup_points += pts_awarded
		"attribute_spent":
			# Python confirmed a server-authoritative attribute spend.
			# Update _attrs so all bonus-stat queries reflect the new value,
			# and emit attribute_spent so the LevelUpDialog and HUD refresh.
			var pid: int = payload.get("peer_id", -1)
			var attr: String = payload.get("attr", "")
			var new_val: int = payload.get("new_val", 0)
			if pid != -1 and attr != "":
				if not LevelSystem._attrs.has(pid):
					LevelSystem.register_peer(pid)
				LevelSystem._attrs[pid][attr] = new_val
				LevelSystem._points[pid] = max(0, LevelSystem._points.get(pid, 0) - 1)
				LevelSystem.attribute_spent.emit(pid, attr, LevelSystem._attrs[pid].duplicate())
		"skill_unlocked":
			# Python confirmed an unlock. Record it in SkillTree state and emit
			# the signal so the skill-tree UI refreshes.
			var pid: int = payload.get("peer_id", -1)
			var node_id: String = payload.get("node_id", "")
			if pid != -1 and node_id != "":
				var s = SkillTree._states.get(pid)
				if s == null:
					s = SkillTree.SkillTreeState.new()
					SkillTree._states[pid] = s
				if not s.unlocked.has(node_id):
					s.unlocked.append(node_id)
				SkillTree.skill_unlocked.emit(pid, node_id)
		"skill_pts_changed":
			# Python is authoritative for skill points. Sync the count and emit
			# so the UI label updates immediately.
			var pid: int = payload.get("peer_id", -1)
			var pts: int = payload.get("pts", 0)
			if pid != -1:
				var s = SkillTree._states.get(pid)
				if s == null:
					s = SkillTree.SkillTreeState.new()
					SkillTree._states[pid] = s
				s.skill_pts = pts
				SkillTree.skill_pts_changed.emit(pid, pts)
		"active_slots_changed":
			# Python confirmed a slot assignment. Mirror into SkillTree state
			# and emit so the hotbar UI reflects the new assignment.
			var pid: int = payload.get("peer_id", -1)
			var slots: Array = payload.get("slots", ["", ""])
			if pid != -1:
				var s = SkillTree._states.get(pid)
				if s == null:
					s = SkillTree.SkillTreeState.new()
					SkillTree._states[pid] = s
				s.active_slots = slots.duplicate()
				SkillTree.active_slots_changed.emit(pid, slots.duplicate())
		"active_used":
			# Python confirmed a skill was fired. Emit the signal so VFX /
			# audio hooks in Main.gd or FPSController can respond.
			var pid: int = payload.get("peer_id", -1)
			var node_id: String = payload.get("node_id", "")
			if pid != -1 and node_id != "":
				SkillTree.active_used.emit(pid, node_id)
		"team_lives":
			# Python is authoritative for lives. Update TeamLives state and emit
			# life_lost so the HUD LivesBar refreshes.
			var team: int = payload.get("team", 0)
			var lives: int = payload.get("lives", 0)
			if team == 0:
				TeamLives.blue_lives = lives
			else:
				TeamLives.red_lives = lives
			TeamLives.life_lost.emit(team, lives)
		"game_over":
			# Python declared a winner. Emit game_over so GameOverScreen shows.
			var winner: int = payload.get("winner", 0)
			TeamLives.game_over.emit(winner)
		"wave_announced":
			# Python fired the wave timer. Show the wave announcement banner.
			var wnum: int = payload.get("wave_number", 0)
			var main: Node = get_node_or_null("/root/Main")
			if main and main.has_method("show_wave_announcement"):
				main.show_wave_announcement(wnum)
		"spawn_wave":
			# Python authorises spawning a batch of minions for one team+lane+type.
			# Only the host runs authoritative minion physics — clients receive puppet
			# state via minion_sync.  Without this guard both peers spawn full-AI
			# minions, each firing their own bullets and sending duplicate relays,
			# which is the root cause of "bullets appearing at the middle of the map".
			if is_host():
				var ms: Node = get_node_or_null("/root/Main/MinionSpawner")
				if ms and ms.has_method("_on_bridge_spawn_wave"):
					ms._on_bridge_spawn_wave(payload)
		"minion_died":
			# Python confirmed a minion death. Godot removes the scene node.
			var mid: int = payload.get("minion_id", -1)
			if mid >= 0:
				var ms: Node = get_node_or_null("/root/Main/MinionSpawner")
				if ms and ms.has_method("kill_minion_by_id"):
					ms.kill_minion_by_id(mid)
	"lobby_state":
		# Python is authoritative for lobby state. Repopulate LobbyManager.players,
		# update _can_start, and mirror team assignments into GameSync so that all
		# server-authoritative combat / targeting code sees correct team data.
		# Also records the local peer_id and host flag for use by is_host() /
		# get_peer_id() — replacing the old ENet multiplayer.get_unique_id() calls.
		var state: Dictionary = payload.get("players", {})
		var new_peer_id: int = payload.get("your_peer_id", _local_peer_id)
		var host_id: int = payload.get("host_id", _local_peer_id)
		if new_peer_id != 0:
			_local_peer_id = new_peer_id
		_is_host = (_local_peer_id != 0 and _local_peer_id == host_id)
		LobbyManager.players.clear()
		for pid_str in state:
			var pid: int = int(str(pid_str))
			var info: Dictionary = state[pid_str]
			LobbyManager.players[pid] = info
			var team: int = int(info.get("team", 0))
			GameSync.set_player_team(pid, team)
			# Register remote peers in SkillTree on all clients so passive
			# bonus queries work for remote peers (e.g. minion damage reduction).
			var role: String = info.get("role", "")
			if role != "" and not role.begins_with("-"):
				SkillTree.register_peer(pid, role)
		LobbyManager._can_start = payload.get("can_start", false)
		LobbyManager.lobby_updated.emit()
		"load_game":
			# Python authorised the game to start. Change to the game scene.
			# The Lobby node was added directly to root (not as a child of the
			# current scene) in StartMenu._show_lobby(), so change_scene_to_file
			# does NOT free it — only the current_scene is freed. We must
			# explicitly remove the Lobby here before changing the scene.
			var lobby: Node = get_tree().root.get_node_or_null("Lobby")
			if lobby:
				lobby.queue_free()
			var path: String = payload.get("path", "")
			if path != "":
				get_tree().change_scene_to_file(path)
		"spawn_visual":
			# Python relayed a visual-only projectile or effect. Dispatch to the
			# appropriate LobbyManager local function based on visual_type.
			var vtype: String = payload.get("visual_type", "")
			var params: Dictionary = payload.get("params", {})
			_handle_spawn_visual(vtype, params)
		"tower_visual":
			# Python relayed a tower/minion visual (hit flash, slow pulse, MG rot, etc.)
			_handle_tower_visual(payload)
		"drop_despawned":
			# Python confirmed a pickup was consumed. Despawn the node on all clients.
			var drop_name: String = payload.get("name", "")
			if drop_name != "":
				LobbyManager.despawn_drop(drop_name)
		"tower_damaged":
			# Python confirmed tower took damage — update health bar visuals.
			var tname: String = payload.get("name", "")
			var hp: float = float(payload.get("health", 0.0))
			var main: Node = get_node_or_null("/root/Main")
			if main:
				var tnode: Node = main.get_node_or_null(tname)
				if tnode and tnode.has_method("_on_health_updated"):
					tnode._on_health_updated(hp)
		"tower_despawned":
			# Python confirmed tower death. Remove the node on all clients.
			var tname: String = payload.get("name", "")
			if tname != "":
				LobbyManager.despawn_tower(tname)
		"broadcast_transform":
			# Python relayed another peer's position/rotation.
			var pid: int = payload.get("peer_id", -1)
			if pid == -1 or pid == _local_peer_id:
				return
			var raw_pos: Array = payload.get("pos", [0.0, 0.0, 0.0])
			var raw_rot: Array = payload.get("rot", [0.0, 0.0, 0.0])
			var team: int = payload.get("team", 0)
			var pos := Vector3(float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2]))
			var rot := Vector3(float(raw_rot[0]), float(raw_rot[1]), float(raw_rot[2]))
			GameSync.remote_player_updated.emit(pid, pos, rot, team)
		"seed_transform":
			# Python relayed a reliable initial-position seed for a peer.
			var pid: int = payload.get("peer_id", -1)
			if pid == -1 or pid == _local_peer_id:
				return
			var raw_pos: Array = payload.get("pos", [0.0, 0.0, 0.0])
			var raw_rot: Array = payload.get("rot", [0.0, 0.0, 0.0])
			var team: int = payload.get("team", 0)
			var pos := Vector3(float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2]))
			var rot := Vector3(float(raw_rot[0]), float(raw_rot[1]), float(raw_rot[2]))
			GameSync.remote_player_updated.emit(pid, pos, rot, team)
		"sync_minion_states":
			# Python relayed batch minion puppet state.
			var ids: Array = payload.get("ids", [])
			var positions: Array = payload.get("positions", [])
			var rotations: Array = payload.get("rotations", [])
			var healths: Array = payload.get("healths", [])
			_apply_minion_puppet_states(ids, positions, rotations, healths)
		"spawn_missile_visuals":
			# Python relayed a missile launch from the host.
			var raw_fp: Array = payload.get("fire_pos", [0.0, 0.0, 0.0])
			var raw_tp: Array = payload.get("target_pos", [0.0, 0.0, 0.0])
			var mteam: int = payload.get("team", 0)
			var ltype: String = payload.get("launcher_type", "")
			var fire_pos := Vector3(float(raw_fp[0]), float(raw_fp[1]), float(raw_fp[2]))
			var target_pos := Vector3(float(raw_tp[0]), float(raw_tp[1]), float(raw_tp[2]))
			LobbyManager.spawn_missile_visuals(fire_pos, target_pos, mteam, ltype)
		"team_points":
			# Python is authoritative for team currency and passive income rate.
			var blue: int = payload.get("blue", 0)
			var red: int = payload.get("red", 0)
			TeamData.sync_from_server(blue, red)
			var income_blue: int = payload.get("income_blue", 0)
			var income_red: int = payload.get("income_red", 0)
			TeamData.sync_income_from_server(income_blue, income_red)
		"wave_info":
			# Python sent the current wave number and countdown.
			var wnum: int = payload.get("wave_number", 0)
			var next_in: float = float(payload.get("next_in_seconds", 0.0))
			LobbyManager.sync_wave_info(wnum, int(next_in))
		"sync_destroy_tree":
			# Python relayed a tree-destruction event.
			var raw: Array = payload.get("pos", [0.0, 0.0, 0.0])
			var tree_pos := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
			LobbyManager.sync_destroy_tree(tree_pos)
		"sync_lane_boosts":
			# Python relayed current lane boost state.
			var b0: Array = payload.get("boosts_team0", [])
			var b1: Array = payload.get("boosts_team1", [])
			LobbyManager.sync_lane_boosts(b0, b1)
		"broadcast_recon_reveal":
			# Python relayed a recon-reveal effect.
			var raw_tp: Array = payload.get("target_pos", [0.0, 0.0, 0.0])
			var radius: float = float(payload.get("radius", 0.0))
			var duration: float = float(payload.get("duration", 0.0))
			var rteam: int = payload.get("team", 0)
			var tgt := Vector3(float(raw_tp[0]), float(raw_tp[1]), float(raw_tp[2]))
			LobbyManager.broadcast_recon_reveal(tgt, radius, duration, rteam)
		"broadcast_ping":
			# Python relayed a map ping.
			var raw_wp: Array = payload.get("world_pos", [0.0, 0.0, 0.0])
			var pteam: int = payload.get("team", 0)
			var raw_col: Array = payload.get("color", [0.62, 0.0, 1.0, 1.0])
			var wpos := Vector3(float(raw_wp[0]), float(raw_wp[1]), float(raw_wp[2]))
			var col := Color(float(raw_col[0]), float(raw_col[1]), float(raw_col[2]), float(raw_col[3]))
			LobbyManager.broadcast_ping(wpos, pteam, col)
		"skill_effect":
			# Python forwarded a skill effect to this specific peer.
			var effect: String = payload.get("effect", "")
			var params: Dictionary = payload.get("params", {})
			_handle_skill_effect(effect, params)
		"sync_limit_state":
			# Python relayed territory push-limit state.
			var lteam: int = payload.get("team", 0)
			var level: int = payload.get("level", 0)
			var p_timer: float = float(payload.get("p_timer", 0.0))
			var r_timer: float = float(payload.get("r_timer", 0.0))
			var lc: Node = get_node_or_null("/root/Main/LaneControl")
			if lc and lc.has_method("sync_limit_state"):
				lc.sync_limit_state(lteam, level, p_timer, r_timer)
		"bounty_activated":
			var pid: int = payload.get("peer_id", -1)
			GameSync.player_is_bounty[pid] = true
		"bounty_cleared":
			var pid: int = payload.get("peer_id", -1)
			GameSync.player_is_bounty[pid] = false
		"player_left":
			# A peer disconnected mid-game. Remove from LobbyManager and clean up puppet.
			var pid: int = payload.get("peer_id", -1)
			if pid == -1:
				return
			LobbyManager.players.erase(pid)
			LobbyManager.lobby_updated.emit()
			var pm: Node = get_node_or_null("/root/Main/PlayerManager")
			if pm and pm.has_method("remove_player"):
				pm.remove_player(pid)
		"tower_destroyed_by_push":
			# Python removed a tower due to enemy territory push. Despawn the node.
			var tname: String = payload.get("name", "")
			if tname != "":
				LobbyManager.despawn_tower(tname)


## Dispatch a spawn_visual message from Python to the appropriate local
## LobbyManager visual function. All Vector3 params arrive as [x,y,z] arrays.
func _handle_spawn_visual(vtype: String, params: Dictionary) -> void:
	match vtype:
		"bullet":
			var pos_arr: Array = params.get("pos", [0.0, 0.0, 0.0])
			var dir_arr: Array = params.get("dir", [0.0, 0.0, 1.0])
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			var dir := Vector3(float(dir_arr[0]), float(dir_arr[1]), float(dir_arr[2]))
			var dmg: float = float(params.get("damage", 10.0))
			var team: int = int(params.get("shooter_team", -1))
			var peer: int = int(params.get("shooter_peer_id", -1))
			var ptype: String = str(params.get("projectile_type", "bullet"))
			print("[BridgeClient] spawn_visual bullet: pos=%s dir=%s dmg=%s team=%d peer=%d" % [pos, dir, dmg, team, peer])
			LobbyManager.spawn_bullet_visuals(pos, dir, dmg, team, peer, ptype)
		"cannonball":
			var pos := Vector3(float(params.get("pos_x", 0)), float(params.get("pos_y", 0)), float(params.get("pos_z", 0)))
			var tgt := Vector3(float(params.get("target_x", 0)), float(params.get("target_y", 0)), float(params.get("target_z", 0)))
			var dmg: float = float(params.get("damage", 50.0))
			var team: int = int(params.get("team", 0))
			LobbyManager.spawn_cannonball_visuals(pos, tgt, dmg, team)
		"mortar":
			var pos := Vector3(float(params.get("pos_x", 0)), float(params.get("pos_y", 0)), float(params.get("pos_z", 0)))
			var tgt := Vector3(float(params.get("target_x", 0)), float(params.get("target_y", 0)), float(params.get("target_z", 0)))
			var dmg: float = float(params.get("damage", 60.0))
			var team: int = int(params.get("team", 0))
			LobbyManager.spawn_mortar_visuals(pos, tgt, dmg, team)
		"minion_spawn":
			var sp := Vector3(float(params.get("pos_x", 0)), float(params.get("pos_y", 0)), float(params.get("pos_z", 0)))
			var raw_wp: Array = params.get("waypoints", [])
			var waypts: Array[Vector3] = []
			for wp in raw_wp:
				if wp is Array and wp.size() >= 3:
					waypts.append(Vector3(float(wp[0]), float(wp[1]), float(wp[2])))
			var team: int = int(params.get("team", 0))
			var lane_i: int = int(params.get("lane_i", 0))
			var mid: int = int(params.get("minion_id", 0))
			var mtype: String = str(params.get("mtype", "basic"))
			LobbyManager.spawn_minion_visuals(team, sp, waypts, lane_i, mid, mtype)
		"minion_death":
			var mid: int = int(params.get("minion_id", 0))
			LobbyManager.kill_minion_visuals(mid)
		_:
			push_warning("[BridgeClient] unknown spawn_visual type: %s" % vtype)


## Dispatch a tower_visual message from Python to the appropriate local function.
func _handle_tower_visual(payload: Dictionary) -> void:
	var vtype: String = payload.get("type", "")
	match vtype:
	"tower_hit":
		var tname: String = payload.get("name", "")
		# Only apply on non-host clients (host already flashed in take_damage).
		if not is_host():
			LobbyManager.notify_tower_hit(tname)
		"minion_hit":
			var mid: int = int(payload.get("minion_id", -1))
			LobbyManager.notify_minion_hit(mid)
		"slow_pulse":
			var tname: String = payload.get("tower_name", "")
			var raw: Array = payload.get("origin", [0.0, 0.0, 0.0])
			var origin := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
			LobbyManager.spawn_slow_pulse_visuals(tname, origin)
		"mg":
			var tname: String = payload.get("tower_name", "")
			var from_raw: Array = payload.get("from", [0.0, 0.0, 0.0])
			var hp_raw: Array = payload.get("hit_pos", [0.0, 0.0, 0.0])
			var hn_raw: Array = payload.get("hit_normal", [0.0, 0.0, 0.0])
			var hit_unit: bool = bool(payload.get("hit_unit", false))
			var muzzle := Vector3(float(from_raw[0]), float(from_raw[1]), float(from_raw[2]))
			var hit_pos := Vector3(float(hp_raw[0]), float(hp_raw[1]), float(hp_raw[2]))
			var hit_normal := Vector3(float(hn_raw[0]), float(hn_raw[1]), float(hn_raw[2]))
			LobbyManager.spawn_mg_visuals(tname, muzzle, hit_pos, hit_normal, hit_unit)
		"mg_turret_rot":
			var tname: String = payload.get("tower_name", "")
			var yaw: float = float(payload.get("yaw_rad", 0.0))
			LobbyManager.sync_mg_turret_rot(tname, yaw)
		_:
			push_warning("[BridgeClient] unknown tower_visual type: %s" % vtype)


## Apply batch minion puppet state received from Python relay.
## ids/positions/rotations/healths are plain Arrays from msgpack.
func _apply_minion_puppet_states(ids: Array, positions: Array, rotations: Array, healths: Array) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var spawner: Node = main.get_node_or_null("MinionSpawner")
	for i in ids.size():
		var minion: Node = null
		if spawner != null and spawner.has_method("get_minion_by_id"):
			minion = spawner.get_minion_by_id(ids[i])
		if minion == null:
			minion = main.get_node_or_null("Minion_%d" % ids[i])
		if minion != null and is_instance_valid(minion) and not minion.is_queued_for_deletion() and minion.has_method("apply_puppet_state"):
			var raw_p: Array = positions[i] if i < positions.size() else [0.0, 0.0, 0.0]
			var pos := Vector3(float(raw_p[0]), float(raw_p[1]), float(raw_p[2]))
			var rot: float = float(rotations[i]) if i < rotations.size() else 0.0
			var hp: float = float(healths[i]) if i < healths.size() else 0.0
			minion.apply_puppet_state(pos, rot, hp)


## Apply a skill effect delivered by Python directly to this peer.
func _handle_skill_effect(effect: String, params: Dictionary) -> void:
	var local_pid: int = _local_peer_id
	var fps: Node = get_node_or_null("/root/Main/FPSPlayer_%d" % local_pid)
	match effect:
		"dash":
			if fps == null:
				return
			var raw_o: Array = params.get("origin", [0.0, 0.0, 0.0])
			var raw_t: Array = params.get("target", [0.0, 0.0, 0.0])
			var elapsed: float = float(params.get("elapsed", 0.0))
			var duration: float = float(params.get("duration", 0.2))
			var origin := Vector3(float(raw_o[0]), float(raw_o[1]), float(raw_o[2]))
			var target := Vector3(float(raw_t[0]), float(raw_t[1]), float(raw_t[2]))
			SkillTree.apply_dash(origin, target, elapsed, duration)
		"rapid_fire":
			var duration: float = float(params.get("duration", 3.0))
			var weapon_type: String = params.get("weapon_type", "rifle")
			SkillTree.apply_rapid_fire(duration, weapon_type)
		"iron_skin":
			var hp: float = float(params.get("hp", 60.0))
			var timer: float = float(params.get("timer", 8.0))
			SkillTree.apply_iron_skin(hp, timer)
		"rally_cry":
			var bonus: float = float(params.get("bonus", 0.2))
			var duration: float = float(params.get("duration", 5.0))
			SkillTree.apply_rally_cry(bonus, duration)
		_:
			push_warning("[BridgeClient] unknown skill_effect: %s" % effect)
