# StubBuildSystem.gd
# Stub for BuildSystem — records spawn_item_local / place_item calls.
extends Node
class_name StubBuildSystem

var spawn_calls: Array = []  # each: {world_pos, team, item_type, subtype, node_name}
var place_calls: Array = []  # each: {world_pos, team, item_type, subtype}
var _next_name: String = "Tower_cannon_0_0"
var _should_fail: bool = false

func set_next_name(n: String) -> void:
	_next_name = n

func set_fail(fail: bool) -> void:
	_should_fail = fail

func spawn_item_local(world_pos: Vector3, team: int, item_type: String,
		subtype: String, node_name: String = "") -> String:
	var used_name: String = node_name if node_name != "" else _next_name
	spawn_calls.append({
		"world_pos": world_pos, "team": team,
		"item_type": item_type, "subtype": subtype,
		"node_name": used_name
	})
	return used_name

func place_item(world_pos: Vector3, team: int, item_type: String,
		subtype: String) -> String:
	place_calls.append({
		"world_pos": world_pos, "team": team,
		"item_type": item_type, "subtype": subtype
	})
	if _should_fail:
		return ""
	return _next_name

func reset() -> void:
	spawn_calls.clear()
	place_calls.clear()
