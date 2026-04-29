extends CanvasLayer

# Call set_status() + set_progress() to update the loading screen.
# Call finish() to animate out and queue_free.

@onready var _bar:    ProgressBar = $Panel/VBox/Bar
@onready var _status: Label       = $Panel/VBox/StatusLabel
@onready var _title:  Label       = $TitleLabel

func _ready() -> void:
	layer = 10  # above everything

func set_progress(value: float) -> void:
	_bar.value = value

func set_status(text: String) -> void:
	_status.text = text

func finish() -> void:
	var tween := create_tween()
	tween.tween_property($BG, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property($Panel, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property($TitleLabel, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()
