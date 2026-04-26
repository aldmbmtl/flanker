extends Node

signal status_changed(text: String, progress: float)

var current_status: String = ""
var current_progress: float = 0.0

func report(text: String, progress: float) -> void:
	current_status = text
	current_progress = progress
	emit_signal("status_changed", text, progress)
