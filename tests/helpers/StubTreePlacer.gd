# StubTreePlacer.gd
# Stub for TreePlacer — records clear_trees_at calls.
extends Node
class_name StubTreePlacer

var clear_calls: Array = []  # each: {pos, radius}

func clear_trees_at(pos: Vector3, radius: float) -> void:
	clear_calls.append({"pos": pos, "radius": radius})

func reset() -> void:
	clear_calls.clear()
