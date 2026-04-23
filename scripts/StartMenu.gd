extends Control

signal start_game
signal quit_game

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_start_pressed() -> void:
	start_game.emit()

func _on_quit_pressed() -> void:
	quit_game.emit()