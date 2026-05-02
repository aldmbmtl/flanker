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
var player_shield_hp: Dictionary = {}     # {peer_id: float}  active Iron Skin shield HP
var player_shield_timer: Dictionary = {}  # {peer_id: float}  remaining shield duration

## Per-player consecutive minion kill count. Reset to 0 on player death.
## Every 5 minion kills = 1 bonus wave minion on the strongest lane. Tracked server-side.
var player_minion_kill_streak: Dictionary = {}   # {peer_id: int}
## Per-player tower kill count per life. Reset on death. Determines free ram tier:
## kill 1 = tier-0, kill 2 = tier-1, kill 3+ = tier-2 + (kill-2) rams stacked.
var player_tower_kill_streak: Dictionary = {}    # {peer_id: int}
## Per-player consecutive player kill count. Reset on death.
## ≥3 kills = bounty active: grants 2× XP + kill_streak×BOUNTY_BASE team pts on death.
var player_kill_streak: Dictionary = {}          # {peer_id: int}
## True when the player has ≥3 consecutive player kills (bounty target).
var player_is_bounty: Dictionary = {}            # {peer_id: bool}

const BOUNTY_THRESHOLD: int = 3    # player kills needed to become a bounty target
const BOUNTY_BASE: int = 10        # team points per kill count when bounty is cashed

const PLAYER_MAX_HP: float = 200.0
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
	# Drain Iron Skin shield before HP (server-authoritative, eliminates race condition
	# where apply_iron_skin RPC and apply_player_damage RPC arrive out of order).
	var actual: float = amount
	var shield: float = player_shield_hp.get(peer_id, 0.0)
	if shield > 0.0:
		var absorbed: float = minf(actual, shield)
		shield -= absorbed
		actual -= absorbed
		if shield <= 0.0:
			player_shield_hp.erase(peer_id)
			player_shield_timer.erase(peer_id)
		else:
			player_shield_hp[peer_id] = shield
	var before: float = get_player_health(peer_id)
	var hp: float = before - actual
	player_healths[peer_id] = hp
	player_health_changed.emit(peer_id, hp)
	
	if hp <= 0.0:
		player_died.emit(peer_id)
		player_dead[peer_id] = true
		var deaths: int = LobbyManager.increment_death_count(peer_id)
		var respawn_time: float = LobbyManager.get_respawn_time(peer_id)
		respawn_countdown[peer_id] = respawn_time

		# ── Bounty payout: was the dead player a bounty target? ───────────────
		var was_bounty: bool = player_is_bounty.get(peer_id, false)
		var dead_streak: int = player_kill_streak.get(peer_id, 0)

		# ── Reset all streaks for the dead player ─────────────────────────────
		player_minion_kill_streak[peer_id] = 0
		player_tower_kill_streak[peer_id] = 0
		player_kill_streak[peer_id] = 0
		player_is_bounty[peer_id] = false

		# ── Award XP to killer ────────────────────────────────────────────────
		# If no player peer fired the killing blow (e.g. a tower projectile),
		# credit the Supporter on the attacking team instead.
		var xp_amount: int = LevelSystem.XP_PLAYER
		if was_bounty:
			xp_amount *= 2  # bounty target awards double XP
		if killer_peer_id > 0:
			LevelSystem.award_xp(killer_peer_id, xp_amount)
			# Award team points (linear scale with bounty kill streak)
			if was_bounty:
				var killer_team: int = player_teams.get(killer_peer_id, -1)
				if killer_team >= 0:
					var bounty_pts: int = dead_streak * BOUNTY_BASE
					TeamData.add_points(killer_team, bounty_pts)
					if multiplayer.is_server():
						LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
			# Update killer's player kill streak and bounty flag
			player_kill_streak[killer_peer_id] = player_kill_streak.get(killer_peer_id, 0) + 1
			if player_kill_streak[killer_peer_id] >= BOUNTY_THRESHOLD:
				var was_already_bounty: bool = player_is_bounty.get(killer_peer_id, false)
				player_is_bounty[killer_peer_id] = true
				if not was_already_bounty and multiplayer.is_server():
					LobbyManager.sync_bounty_state.rpc(killer_peer_id, true)
			# Killstreak heal passive
			var heal_bonus: float = SkillTree.get_passive_bonus(killer_peer_id, "killstreak_heal")
			if heal_bonus > 0.0:
				var cur_hp: float = player_healths.get(killer_peer_id, PLAYER_MAX_HP)
				var max_hp: float = PLAYER_MAX_HP + LevelSystem.get_bonus_hp(killer_peer_id)
				player_healths[killer_peer_id] = minf(cur_hp + 30.0, max_hp)
				player_health_changed.emit(killer_peer_id, player_healths[killer_peer_id])
		elif source_team >= 0:
			var sup: int = LobbyManager.get_supporter_peer(source_team)
			if sup > 0:
				LevelSystem.award_xp(sup, xp_amount)
		# Notify clients that the bounty target died (clear indicator)
		if was_bounty and multiplayer.is_server():
			LobbyManager.sync_bounty_state.rpc(peer_id, false)
	
	return hp

func _process(delta: float) -> void:
	if NetworkManager._peer != null and not multiplayer.is_server():
		return
	# Tick Iron Skin shield timers — expire shields when duration runs out.
	for pid in player_shield_timer.keys():
		var t: float = player_shield_timer.get(pid, 0.0) - delta
		if t <= 0.0:
			player_shield_timer.erase(pid)
			player_shield_hp.erase(pid)
		else:
			player_shield_timer[pid] = t
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

func get_player_shield_hp(peer_id: int) -> float:
	return player_shield_hp.get(peer_id, 0.0)

func set_player_shield(peer_id: int, hp: float, duration: float) -> void:
	if hp > 0.0:
		player_shield_hp[peer_id] = hp
		player_shield_timer[peer_id] = duration
	else:
		player_shield_hp.erase(peer_id)
		player_shield_timer.erase(peer_id)

func reset() -> void:
	game_seed = 0
	time_seed = -1
	player_healths.clear()
	player_teams.clear()
	player_dead.clear()
	respawn_countdown.clear()
	player_reserve_ammo.clear()
	player_weapon_type.clear()
	player_shield_hp.clear()
	player_shield_timer.clear()
	player_minion_kill_streak.clear()
	player_tower_kill_streak.clear()
	player_kill_streak.clear()
	player_is_bounty.clear()
	# Restore default spawn positions
	player_spawn_positions.clear()
	player_spawn_positions[0] = Vector3(0.0, 0.0, 82.0)
	player_spawn_positions[1] = Vector3(0.0, 0.0, -82.0)