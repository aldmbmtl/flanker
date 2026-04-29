extends Node

# Tracks lives for each team. Server-authoritative in multiplayer.
# blue = team 0, red = team 1

signal life_lost(team: int, remaining: int)
signal game_over(winner_team: int)

var blue_lives: int = 0
var red_lives: int = 0

func _ready() -> void:
	pass

func reset() -> void:
	blue_lives = GameSettings.lives_per_team
	red_lives  = GameSettings.lives_per_team

func get_lives(team: int) -> int:
	return blue_lives if team == 0 else red_lives

# Called on server (or singleplayer) when a minion scores.
# team = the team that lost the life (the defending team).
func lose_life(team: int) -> void:
	if team == 0:
		blue_lives = max(0, blue_lives - 1)
	else:
		red_lives = max(0, red_lives - 1)
	var remaining: int = get_lives(team)
	life_lost.emit(team, remaining)

	# Sync to all clients in multiplayer
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_lives.rpc(blue_lives, red_lives)

	if remaining <= 0:
		var winner: int = 1 if team == 0 else 0
		game_over.emit(winner)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_broadcast_game_over.rpc(winner)

# ── Multiplayer sync ─────────────────────────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func _sync_lives(blue: int, red: int) -> void:
	blue_lives = blue
	red_lives  = red
	life_lost.emit(0, blue)  # trigger HUD update for both teams
	life_lost.emit(1, red)

@rpc("authority", "call_remote", "reliable")
func _broadcast_game_over(winner: int) -> void:
	game_over.emit(winner)
