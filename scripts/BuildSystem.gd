extends Node

const TOWER_SCENE := "res://scenes/Tower.tscn"
var _tower_scene: PackedScene = null

# Player team for placed towers (always blue in single-player prototype)
var player_team := 0

func _ready() -> void:
	_tower_scene = load(TOWER_SCENE)

func place_tower(world_pos: Vector3) -> void:
	var tower = _tower_scene.instantiate()
	# Snap to grid
	world_pos.x = snappedf(world_pos.x, 2.0)
	world_pos.z = snappedf(world_pos.z, 2.0)
	world_pos.y = 1.0
	tower.global_position = world_pos
	get_tree().root.get_node("Main").add_child(tower)
	tower.setup(player_team)
	print("Tower placed at %s for team %d" % [world_pos, player_team])
