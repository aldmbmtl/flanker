extends Node3D

var health := 500.0
var team := 0
var _dead := false

const FOUNTAIN_PATH := "res://assets/kenney_fantasy-town-kit/Models/GLB format/fountain-square.glb"

func _ready() -> void:
	add_to_group("bases")
	call_deferred("_spawn_fountain")

func _spawn_fountain() -> void:
	var glb := load(FOUNTAIN_PATH)
	if glb:
		var scene: PackedScene = glb
		var fountain_root := Node3D.new()
		fountain_root.name = "FountainRoot"
		add_child(fountain_root)
		var instance := scene.instantiate()
		fountain_root.add_child(instance)
		fountain_root.scale = Vector3(2.0, 2.0, 2.0)
		fountain_root.position = Vector3(0, 0, 5.0 if team == 0 else 15.0)
	else:
		print("Failed to load fountain")

func setup(p_team: int) -> void:
	team = p_team

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	var winner := "RED" if team == 0 else "BLUE"
	print("GAME OVER — %s WINS" % winner)
	var main := get_node_or_null("/root/Main")
	if main and main.has_method("game_over_signal"):
		main.game_over_signal(winner)