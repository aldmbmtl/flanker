# StubMinionSpawner.gd
# Stub for MinionSpawner — records spawn/kill calls without spawning real scenes.
extends Node
class_name StubMinionSpawner

var spawn_calls: Array = []   # each: {team, spawn_pos, waypts, lane_i, minion_id, mtype}
var kill_calls:  Array = []   # each: int minion_id
var _minions: Dictionary = {} # minion_id -> StubMinionNode

class StubMinionNode extends Node:
	var minion_id: int = 0
	var team: int = 0
	var last_puppet_pos: Vector3 = Vector3.ZERO
	var last_puppet_rot: float = 0.0
	var last_puppet_hp: float = 60.0
	var force_died: bool = false

	func apply_puppet_state(pos: Vector3, rot: float, hp: float) -> void:
		last_puppet_pos = pos
		last_puppet_rot = rot
		last_puppet_hp  = hp

	func force_die() -> void:
		force_died = true
		queue_free()

	func take_damage(_amount: float, _source: String, _src_team: int, _killer: int = -1) -> void:
		pass

func spawn_for_network(team: int, spawn_pos: Vector3, waypts: Array,
		lane_i: int, minion_id: int, mtype: String = "basic") -> void:
	spawn_calls.append({
		"team": team, "spawn_pos": spawn_pos, "waypts": waypts,
		"lane_i": lane_i, "minion_id": minion_id, "mtype": mtype
	})
	var m := StubMinionNode.new()
	m.minion_id = minion_id
	m.team = team
	m.name = "Minion_%d" % minion_id
	add_child(m)
	_minions[minion_id] = m

func kill_minion_by_id(minion_id: int) -> void:
	kill_calls.append(minion_id)
	if _minions.has(minion_id):
		_minions[minion_id].queue_free()
		_minions.erase(minion_id)

func get_minion_by_id(minion_id: int) -> Node:
	return _minions.get(minion_id, null)

func reset() -> void:
	spawn_calls.clear()
	kill_calls.clear()
