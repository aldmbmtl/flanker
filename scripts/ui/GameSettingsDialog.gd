extends Control

# Emitted when the player confirms settings.
# time_seed: -1 = random, 0=sunrise, 1=noon, 2=sunset, 3=night
# map_seed:  1..2147483647
signal settings_confirmed(time_seed: int, map_seed: int)
const BG_COLOR     := Color(0.04, 0.05, 0.06, 0.92)
const BORDER_COLOR := Color(0.85, 0.32, 0.05, 0.6)
const TITLE_COLOR  := Color(1.0, 0.35, 0.1, 1.0)
const LABEL_COLOR  := Color(0.55, 0.45, 0.35, 1.0)
const DIM_COLOR    := Color(0.35, 0.30, 0.25, 1.0)

const TIME_OPTIONS := ["RANDOM", "SUNRISE", "NOON", "SUNSET", "NIGHT"]
# Maps button index → time_seed value (-1 = random)
const TIME_VALUES  := [-1, 0, 1, 2, 3]

var _selected_time_idx: int = 0  # default: RANDOM
var _time_buttons: Array[Button] = []
var _seed_edit: LineEdit
var _lives_spin: SpinBox

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_build_ui()

func _build_ui() -> void:
	var ui_theme: Theme = load("res://assets/ui_theme.tres")

	# Dark backdrop — click outside = cancel
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			queue_free()
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 2
	style.border_color = BORDER_COLOR
	style.content_margin_left   = 32
	style.content_margin_right  = 32
	style.content_margin_top    = 32
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	# ── Title ──────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "GAME SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# ── Time of day ────────────────────────────────────────────────────────────
	var time_lbl := Label.new()
	time_lbl.text = "TIME OF DAY"
	time_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	time_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(time_lbl)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	vbox.add_child(time_row)

	for i in TIME_OPTIONS.size():
		var btn := Button.new()
		btn.text = TIME_OPTIONS[i]
		btn.custom_minimum_size = Vector2(74, 38)
		btn.theme = ui_theme
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i  # capture
		btn.pressed.connect(func() -> void: _select_time(idx))
		time_row.add_child(btn)
		_time_buttons.append(btn)

	_select_time(0)  # default highlight

	vbox.add_child(HSeparator.new())

	# ── Map seed ───────────────────────────────────────────────────────────────
	var seed_lbl := Label.new()
	seed_lbl.text = "MAP SEED"
	seed_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	seed_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(seed_lbl)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	vbox.add_child(seed_row)

	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi_range(1, 2147483647))
	_seed_edit.placeholder_text = "Enter seed..."
	_seed_edit.custom_minimum_size = Vector2(0, 38)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.theme = ui_theme
	seed_row.add_child(_seed_edit)

	var rand_btn := Button.new()
	rand_btn.text = "RANDOMIZE"
	rand_btn.custom_minimum_size = Vector2(120, 38)
	rand_btn.theme = ui_theme
	rand_btn.pressed.connect(_on_randomize_seed)
	seed_row.add_child(rand_btn)

	vbox.add_child(HSeparator.new())

	# ── Lives per team ─────────────────────────────────────────────────────────
	var lives_lbl := Label.new()
	lives_lbl.text = "LIVES PER TEAM"
	lives_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	lives_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(lives_lbl)

	_lives_spin = SpinBox.new()
	_lives_spin.min_value = 1
	_lives_spin.max_value = 99
	_lives_spin.step = 1
	_lives_spin.value = GameSettings.lives_per_team
	_lives_spin.custom_minimum_size = Vector2(120, 38)
	_lives_spin.theme = ui_theme
	vbox.add_child(_lives_spin)

	vbox.add_child(HSeparator.new())

	# ── Confirm / Cancel ───────────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var start_btn := Button.new()
	start_btn.text = "START"
	start_btn.custom_minimum_size = Vector2(150, 48)
	start_btn.theme = ui_theme
	start_btn.pressed.connect(_on_start_pressed)
	btn_row.add_child(start_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(120, 48)
	cancel_btn.theme = ui_theme
	cancel_btn.pressed.connect(func() -> void: queue_free())
	btn_row.add_child(cancel_btn)

func _select_time(idx: int) -> void:
	_selected_time_idx = idx
	for i in _time_buttons.size():
		var btn: Button = _time_buttons[i]
		if i == idx:
			btn.add_theme_color_override("font_color", Color(1.0, 0.65, 0.2, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 0.65, 0.2, 1.0))
			# Highlight with orange border via modulate
			btn.modulate = Color(1.0, 0.75, 0.3, 1.0)
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_hover_color")
			btn.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_randomize_seed() -> void:
	_seed_edit.text = str(randi_range(1, 2147483647))

func _on_start_pressed() -> void:
	var raw: String = _seed_edit.text.strip_edges()
	var map_seed: int
	if raw.is_valid_int():
		map_seed = raw.to_int()
		if map_seed <= 0:
			map_seed = randi_range(1, 2147483647)
	else:
		map_seed = randi_range(1, 2147483647)
	var chosen_time: int = TIME_VALUES[_selected_time_idx]
	GameSettings.lives_per_team = int(_lives_spin.value)
	GameSettings.save_settings()
	settings_confirmed.emit(chosen_time, map_seed)
	queue_free()
