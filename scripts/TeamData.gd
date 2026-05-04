extends Node

const TEAM_COUNT := 2

var team_points: Array = []
var passive_income: Array = []

func _ready() -> void:
	team_points.resize(TEAM_COUNT)
	team_points[0] = 75
	team_points[1] = 75
	passive_income.resize(TEAM_COUNT)
	passive_income[0] = 0
	passive_income[1] = 0

func add_points(team: int, amount: int) -> void:
	if team >= 0 and team < TEAM_COUNT:
		team_points[team] += amount

func get_points(team: int) -> int:
	if team >= 0 and team < TEAM_COUNT:
		return team_points[team]
	return 0

func spend_points(team: int, amount: int) -> bool:
	if team >= 0 and team < TEAM_COUNT and team_points[team] >= amount:
		team_points[team] -= amount
		return true
	return false

func sync_from_server(blue: int, red: int) -> void:
	team_points[0] = blue
	team_points[1] = red

func reset() -> void:
	team_points[0] = 75
	team_points[1] = 75
	passive_income[0] = 0
	passive_income[1] = 0

func get_passive_income(team: int) -> int:
	if team >= 0 and team < TEAM_COUNT:
		return passive_income[team]
	return 0

func sync_income_from_server(blue_rate: int, red_rate: int) -> void:
	passive_income[0] = blue_rate
	passive_income[1] = red_rate

func add_passive_income(_team: int, _amount: int) -> void:
	# No-op: passive income is now server-authoritative.
	# The server sends income_blue/income_red in the team_points message.
	pass
