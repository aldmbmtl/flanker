# StubFogOverlay.gd
# Stub for FogOverlay — records update_sources and add_timed_reveal calls.
extends Node
class_name StubFogOverlay

var update_calls: Array = []  # each: {player_positions, player_radius, minion_positions, minion_radius, tower_positions, tower_radius}
var timed_reveals: Array = [] # each: {pos, radius, duration}

func update_sources(player_positions: Array, player_radius: float,
		minion_positions: Array, minion_radius: float,
		tower_positions: Array, tower_radius: float) -> void:
	update_calls.append({
		"player_positions": player_positions.duplicate(),
		"player_radius": player_radius,
		"minion_positions": minion_positions.duplicate(),
		"minion_radius": minion_radius,
		"tower_positions": tower_positions.duplicate(),
		"tower_radius": tower_radius
	})

func add_timed_reveal(pos: Vector3, radius: float, duration: float) -> void:
	timed_reveals.append({"pos": pos, "radius": radius, "duration": duration})

func reset() -> void:
	update_calls.clear()
	timed_reveals.clear()
