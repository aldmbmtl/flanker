extends Node3D

var health := 500.0
var team := 0  # 0=blue, 1=red
var _dead := false

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_label: Label3D = $Label3D

func _ready() -> void:
	add_to_group("bases")
	_update_label()

func setup(p_team: int) -> void:
	team = p_team
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.3, 1.0) if team == 0 else Color(1.0, 0.1, 0.1)
	mesh.material_override = mat

func take_damage(amount: float, _source: String) -> void:
	if _dead:
		return
	health -= amount
	_update_label()
	if health <= 0:
		_die()

func _update_label() -> void:
	if health_label:
		var team_name := "BLUE BASE" if team == 0 else "RED BASE"
		health_label.text = "%s\nHP: %d" % [team_name, max(0, int(health))]

func _die() -> void:
	if _dead:
		return
	_dead = true
	var winner := "RED" if team == 0 else "BLUE"
	print("GAME OVER — %s WINS" % winner)
	var main := get_node_or_null("/root/Main")
	if main and main.has_method("game_over_signal"):
		main.game_over_signal(winner)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	mesh.material_override = mat
