extends Control

@onready var winner_label:   Label  = $Card/VBox/WinnerLabel
@onready var subtitle_label: Label  = $Card/VBox/SubtitleLabel
@onready var menu_button:    Button = $Card/VBox/MenuButton

func _ready() -> void:
	visible = false

func show_winner(winner_team: int) -> void:
	if winner_team == 0:
		winner_label.text = "BLUE WINS"
		winner_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
	else:
		winner_label.text = "RED WINS"
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true

func _on_menu_pressed() -> void:
	var main: Node = get_tree().root.get_node("Main")
	if main:
		main.leave_game()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/StartMenu.tscn")
