extends Node

const TEAM_COUNT := 2

var game_seed: int = 0
var time_seed: int = -1  # -1 = random; 0=sunrise 1=noon 2=sunset 3=night
var player_healths: Dictionary = {}
var player_teams: Dictionary = {}
var player_spawn_positions: Dictionary = {}
var player_dead: Dictionary = {}
var player_reserve_ammo: Dictionary = {}  # {peer_id: int}  total reserve across both slots
var player_weapon_type: Dictionary = {}   # {peer_id: String}  active weapon name

## True when the player has ≥3 consecutive player kills (bounty target).
## Kept as a mirror dict — Python is authoritative; BridgeClient writes here.
var player_is_bounty: Dictionary = {}            # {peer_id: bool}

const PLAYER_MAX_HP: float = 200.0
const PLAYER_SYNC_INTERVAL := 5

signal player_health_changed(peer_id: int, health: float)
signal player_died(peer_id: int, respawn_time: float)
signal player_respawned(peer_id: int, spawn_pos: Vector3)
signal remote_player_updated(peer_id: int, pos: Vector3, rot: Vector3, team: int)


func _ready() -> void:
	player_spawn_positions[0] = Vector3(0.0, 0.0, 82.0)
	player_spawn_positions[1] = Vector3(0.0, 0.0, -82.0)

func get_player_health(peer_id: int) -> float:
	return player_healths.get(peer_id, PLAYER_MAX_HP)

func set_player_health(peer_id: int, hp: float) -> void:
	player_healths[peer_id] = hp
	player_health_changed.emit(peer_id, hp)

func get_player_team(peer_id: int) -> int:
	return player_teams.get(peer_id, -1)

func set_player_team(peer_id: int, team: int) -> void:
	player_teams[peer_id] = team

func get_spawn_position(team: int) -> Vector3:
	return player_spawn_positions.get(team, Vector3.ZERO)

func get_player_reserve_ammo(peer_id: int) -> int:
	return player_reserve_ammo.get(peer_id, 999)  # 999 = never synced, assume fine

func reset() -> void:
	game_seed = 0
	time_seed = -1
	# Emit signals with zeroed values BEFORE clearing so listeners (HUD, etc.) update.
	for pid in player_healths.keys():
		player_health_changed.emit(pid, 0.0)
	player_healths.clear()
	player_teams.clear()
	player_dead.clear()
	player_reserve_ammo.clear()
	player_weapon_type.clear()
	player_is_bounty.clear()
	# Restore default spawn positions
	player_spawn_positions.clear()
	player_spawn_positions[0] = Vector3(0.0, 0.0, 82.0)
	player_spawn_positions[1] = Vector3(0.0, 0.0, -82.0)
