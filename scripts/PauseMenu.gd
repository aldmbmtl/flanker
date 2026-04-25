extends Control

func _ready() -> void:
	print("[PauseMenu] _ready called")
	visible = false

func _on_resume_pressed() -> void:
	var main: Node = get_tree().root.get_node("Main")
	if main:
		main.toggle_pause(false)

func _on_quit_pressed() -> void:
	var main: Node = get_tree().root.get_node("Main")
	if main:
		main.leave_game()
	else:
		get_tree().quit()
