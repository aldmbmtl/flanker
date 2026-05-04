extends Node

# Tracks lives for each team. Python is authoritative.
# blue = team 0, red = team 1

signal life_lost(team: int, remaining: int)
signal game_over(winner_team: int)

var blue_lives: int = 0
var red_lives: int = 0

func _ready() -> void:
	pass

func reset() -> void:
	blue_lives = ClientSettings.lives_per_team
	red_lives  = ClientSettings.lives_per_team

func get_lives(team: int) -> int:
	return blue_lives if team == 0 else red_lives

# Called on the client when the local player's minion scores.
# Forwards to Python; Python broadcasts team_lives back to all peers.
func lose_life(team: int) -> void:
	BridgeClient.send("lose_life", {"team": team})
