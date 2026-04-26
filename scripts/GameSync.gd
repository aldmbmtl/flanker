extends Node

const TEAM_COUNT := 2

var game_seed: int = 0
var time_seed: int = -1  # -1 = random; 0=sunrise 1=noon 2=sunset 3=night
var player_healths: Dictionary = {}
var player_teams: Dictionary = {}
var player_spawn_positions: Dictionary = {}
var player_dead: Dictionary = {}
var respawn_timer: float = 0.0
var respawn_countdown: Dictionary = {}
var player_reserve_ammo: Dictionary = {}  # {peer_id: int}  total reserve across both slots
var player_weapon_type: Dictionary = {}   # {peer_id: String}  active weapon name

const PLAYER_MAX_HP: float = 100.0
const PLAYER_SYNC_INTERVAL := 5

signal player_health_changed(peer_id: int, health: float)
signal player_died(peer_id: int)
signal player_respawned(peer_id: int, spawn_pos: Vector3)
signal remote_player_updated(peer_id: int, pos: Vector3, rot: Vector3, team: int)
signal player_ammo_changed(peer_id: int, reserve: int)

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

func damage_player(peer_id: int, amount: float, source_team: int, killer_peer_id: int = -1) -> float:
	if player_dead.get(peer_id, false):
		return player_healths.get(peer_id, 0.0)
	var before: float = get_player_health(peer_id)
	var hp: float = before - amount
	player_healths[peer_id] = hp
	player_health_changed.emit(peer_id, hp)
	
	if hp <= 0.0:
		player_died.emit(peer_id)
		player_dead[peer_id] = true
		var deaths: int = LobbyManager.increment_death_count(peer_id)
		var respawn_time: float = min(deaths * LobbyManager.RESPAWN_INCREMENT + LobbyManager.RESPAWN_BASE, LobbyManager.RESPAWN_CAP)
		respawn_countdown[peer_id] = respawn_time
		# Award XP to killer (server-authoritative)
		if killer_peer_id > 0:
			LevelSystem.award_xp(killer_peer_id, LevelSystem.XP_PLAYER)
	
	return hp

func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	for peer_id in player_dead.keys():
		if player_dead.get(peer_id, false):
			if respawn_countdown.has(peer_id):
				respawn_countdown[peer_id] -= delta
			if respawn_countdown.get(peer_id, 0.0) <= 0.0:
				respawn_player(peer_id)

func respawn_player(peer_id: int) -> void:
	var team: int = get_player_team(peer_id)
	var spawn_pos: Vector3 = player_spawn_positions.get(team, Vector3.ZERO)
	spawn_pos.y = 1.0
	
	var max_hp: float = PLAYER_MAX_HP + LevelSystem.get_bonus_hp(peer_id)
	player_healths[peer_id] = max_hp
	player_dead[peer_id] = false
	respawn_countdown.erase(peer_id)
	player_respawned.emit(peer_id, spawn_pos)
	player_health_changed.emit(peer_id, max_hp)

func get_spawn_position(team: int) -> Vector3:
	return player_spawn_positions.get(team, Vector3.ZERO)

func get_player_reserve_ammo(peer_id: int) -> int:
	return player_reserve_ammo.get(peer_id, 999)  # 999 = never synced, assume fine

func set_player_reserve_ammo(peer_id: int, reserve: int, weapon_type: String) -> void:
	player_reserve_ammo[peer_id] = reserve
	player_weapon_type[peer_id] = weapon_type
	player_ammo_changed.emit(peer_id, reserve)