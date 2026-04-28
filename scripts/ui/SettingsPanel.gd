extends Control

signal back_pressed

@onready var fog_toggle: CheckBox = $Card/VBox/FogSection/FogVBox/FogToggle
@onready var fog_slider: HSlider = $Card/VBox/FogSection/FogVBox/FogDensityRow/FogSlider
@onready var fog_value_label: Label = $Card/VBox/FogSection/FogVBox/FogDensityRow/FogValueLabel
@onready var dof_toggle: CheckBox = $Card/VBox/DoFSection/DoFVBox/DoFToggle
@onready var dof_slider: HSlider = $Card/VBox/DoFSection/DoFVBox/DoFStrengthRow/DoFSlider
@onready var dof_value_label: Label = $Card/VBox/DoFSection/DoFVBox/DoFStrengthRow/DoFValueLabel
@onready var shadow_option: OptionButton = $Card/VBox/ShadowSection/ShadowVBox/ShadowRow/ShadowOption
@onready var tree_shadow_option: OptionButton = $Card/VBox/ShadowSection/ShadowVBox/TreeShadowRow/TreeShadowOption
@onready var lives_spin: SpinBox = $Card/VBox/GameSection/GameVBox/LivesRow/LivesSpin

var _loading: bool = false


func _ready() -> void:
	shadow_option.add_item("Off",  0)
	shadow_option.add_item("Low",  1)
	shadow_option.add_item("High", 2)
	tree_shadow_option.add_item("Off",   0)
	tree_shadow_option.add_item("Close", 1)
	tree_shadow_option.add_item("Far",   2)
	_load_from_settings()


func _load_from_settings() -> void:
	_loading = true
	fog_toggle.button_pressed = GraphicsSettings.fog_enabled
	fog_slider.value = GraphicsSettings.fog_density_multiplier
	fog_slider.editable = GraphicsSettings.fog_enabled
	fog_value_label.text = "%.2f×" % GraphicsSettings.fog_density_multiplier

	dof_toggle.button_pressed = GraphicsSettings.dof_enabled
	dof_slider.value = GraphicsSettings.dof_blur_amount
	dof_slider.editable = GraphicsSettings.dof_enabled
	dof_value_label.text = "%.3f" % GraphicsSettings.dof_blur_amount

	shadow_option.selected = GraphicsSettings.shadow_quality
	tree_shadow_option.selected = GraphicsSettings.tree_shadow_distance

	lives_spin.value = GameSettings.lives_per_team
	_loading = false


func _on_fog_toggle_toggled(pressed: bool) -> void:
	if _loading:
		return
	fog_slider.editable = pressed
	_apply()


func _on_fog_slider_value_changed(value: float) -> void:
	if _loading:
		return
	fog_value_label.text = "%.2f×" % value
	_apply()


func _on_dof_toggle_toggled(pressed: bool) -> void:
	if _loading:
		return
	dof_slider.editable = pressed
	_apply()


func _on_dof_slider_value_changed(value: float) -> void:
	if _loading:
		return
	dof_value_label.text = "%.3f" % value
	_apply()


func _apply() -> void:
	GraphicsSettings.apply(
		fog_toggle.button_pressed,
		fog_slider.value,
		dof_toggle.button_pressed,
		dof_slider.value,
		shadow_option.selected,
		tree_shadow_option.selected
	)


func _on_shadow_option_item_selected(_index: int) -> void:
	if _loading:
		return
	_apply()


func _on_tree_shadow_option_item_selected(_index: int) -> void:
	if _loading:
		return
	_apply()


func _on_restore_defaults_pressed() -> void:
	GraphicsSettings.restore_defaults()
	_load_from_settings()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_lives_spin_value_changed(value: float) -> void:
	if _loading:
		return
	GameSettings.lives_per_team = int(value)
	GameSettings.save_settings()
