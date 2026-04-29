extends Control

@onready var card_vbox: VBoxContainer = $Card/VBox
@onready var settings_panel: Control = $SettingsPanelInstance


func _ready() -> void:
	visible = false
	settings_panel.back_pressed.connect(_on_settings_back)


func _on_resume_pressed() -> void:
	var main: Node = get_tree().root.get_node("Main")
	if main:
		main.toggle_pause(false)


func _on_settings_pressed() -> void:
	card_vbox.visible = false
	settings_panel.visible = true


func _on_settings_back() -> void:
	settings_panel.visible = false
	card_vbox.visible = true


func _on_quit_pressed() -> void:
	var main: Node = get_tree().root.get_node("Main")
	if main:
		main.leave_game()
	else:
		get_tree().quit()
