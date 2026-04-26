extends CanvasLayer
## Supporter HUD — horizontal toolbar for selecting what to place.
## Hotkeys 1-9 or click to select. Slot 6 = weapon sub-row.

signal slot_changed(item_type: String, subtype: String)

const SLOT_DEFS := [
	{ "key": "1", "type": "cannon",           "subtype": "",       "label": "Cannon",    "cost_key": "cannon"           },
	{ "key": "2", "type": "mortar",           "subtype": "",       "label": "Mortar",    "cost_key": "mortar"           },
	{ "key": "3", "type": "slow",             "subtype": "",       "label": "Slow",      "cost_key": "slow"             },
	{ "key": "4", "type": "barrier",          "subtype": "",       "label": "Barrier",   "cost_key": "barrier"          },
	{ "key": "5", "type": "weapon",           "subtype": "rifle",  "label": "Weapon▾",  "cost_key": "weapon"           },
	{ "key": "6", "type": "healthpack",       "subtype": "",       "label": "HealthPack","cost_key": "healthpack"       },
	{ "key": "7", "type": "healstation",      "subtype": "",       "label": "HealStation","cost_key": "healstation"     },
	{ "key": "8", "type": "launcher_missile", "subtype": "",       "label": "Launcher",  "cost_key": "launcher_missile" },
	{ "key": "9", "type": "recon_strike",    "subtype": "",       "label": "Recon",     "cost_key": "recon_strike"     },
]

const WEAPON_SUBTYPES := ["pistol", "rifle", "heavy", "rocket_launcher"]
const WEAPON_COSTS    := { "pistol": 10, "rifle": 20, "heavy": 30, "rocket_launcher": 60 }
const WEAPON_LABELS   := { "pistol": "Pistol", "rifle": "Rifle", "heavy": "Heavy", "rocket_launcher": "Rocket" }
const PLACEABLE_COSTS := {
	"cannon": 25, "mortar": 35,
	"slow": 30, "barrier": 10, "healthpack": 15, "healstation": 25,
	"launcher_missile": 50, "recon_strike": 100,
}

var selected_type:    String = ""
var selected_subtype: String = ""
var _player_team: int = 0
var _selected_slot:   int = -1
var _scale: float = 1.0

var _slot_buttons:  Array = []
var _cost_labels:   Array = []
var _weapon_subrow: Control = null
var _weapon_sub_btns: Array = []
var _selected_sub: int = 1  # default rifle

func _ready() -> void:
	_scale = float(DisplayServer.window_get_size().y) / 1080.0
	layer = 10
	_build_ui()

func setup(team: int) -> void:
	_player_team = team

## Shared style constants — matches project palette
const _BG_COLOR     := Color(0.04, 0.05, 0.06, 0.92)
const _BORDER_COLOR := Color(0.85, 0.32, 0.05, 1.0)
const _TITLE_COLOR  := Color(1.0, 0.35, 0.1, 1.0)
const _DIM_COLOR    := Color(0.55, 0.45, 0.35, 1.0)
const _SEL_BG       := Color(0.14, 0.08, 0.04, 1.0)
const _SEL_BORDER   := Color(0.85, 0.32, 0.05, 1.0)
const _HOV_BG       := Color(0.28, 0.14, 0.04, 1.0)
const _HOV_BORDER   := Color(1.0, 0.55, 0.1, 1.0)
const _SLOT_BG      := Color(0.06, 0.07, 0.09, 0.92)

func _make_card_style(sc: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _BG_COLOR
	s.border_width_left   = 3
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color = _BORDER_COLOR
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left  = 4
	s.content_margin_left   = 12.0 * sc
	s.content_margin_right  = 12.0 * sc
	s.content_margin_top    = 10.0 * sc
	s.content_margin_bottom = 10.0 * sc
	return s

func _make_slot_style(selected: bool, sc: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _SEL_BG if selected else _SLOT_BG
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.border_color = _SEL_BORDER if selected else Color(_BORDER_COLOR, 0.35)
	s.corner_radius_top_left     = 3
	s.corner_radius_top_right    = 3
	s.corner_radius_bottom_right = 3
	s.corner_radius_bottom_left  = 3
	s.content_margin_left   = 8.0 * sc
	s.content_margin_right  = 8.0 * sc
	s.content_margin_top    = 6.0 * sc
	s.content_margin_bottom = 6.0 * sc
	return s

func _build_ui() -> void:
	var sc: float = _scale
	# Full-rect transparent wrapper so CenterContainer can anchor to bottom
	var wrapper := Control.new()
	wrapper.name = "ToolbarWrapper"
	wrapper.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrapper.anchor_top    = 1.0
	wrapper.anchor_bottom = 1.0
	wrapper.offset_top    = -100.0 * sc
	wrapper.offset_bottom = 0.0
	wrapper.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	# CenterContainer horizontally centers the card
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(center)

	# Outer card
	var root := PanelContainer.new()
	root.name = "ToolbarRoot"
	root.add_theme_stylebox_override("panel", _make_card_style(sc))
	center.add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(6.0 * sc))
	root.add_child(vbox)

	# Weapon sub-row (hidden until weapon slot selected)
	_weapon_subrow = HBoxContainer.new()
	_weapon_subrow.visible = false
	_weapon_subrow.alignment = BoxContainer.ALIGNMENT_CENTER
	_weapon_subrow.add_theme_constant_override("separation", roundi(6.0 * sc))
	vbox.add_child(_weapon_subrow)

	for i in WEAPON_SUBTYPES.size():
		var sub := i
		var wtype: String = WEAPON_SUBTYPES[i]
		var wcost: int = WEAPON_COSTS[wtype]
		var sub_panel := PanelContainer.new()
		sub_panel.add_theme_stylebox_override("panel", _make_slot_style(false, sc))
		var sub_inner := VBoxContainer.new()
		sub_panel.add_child(sub_inner)
		var sub_name := Label.new()
		sub_name.text = WEAPON_LABELS.get(wtype, wtype.capitalize())
		sub_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_name.add_theme_font_size_override("font_size", roundi(11.0 * sc))
		sub_name.add_theme_color_override("font_color", _DIM_COLOR)
		sub_inner.add_child(sub_name)
		var sub_cost := Label.new()
		sub_cost.text = "¤%d" % wcost
		sub_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_cost.add_theme_font_size_override("font_size", roundi(10.0 * sc))
		sub_inner.add_child(sub_cost)
		var sub_btn := Button.new()
		sub_btn.flat = true
		sub_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		sub_panel.add_child(sub_btn)
		sub_btn.pressed.connect(func(): _select_weapon_sub(sub))
		_weapon_subrow.add_child(sub_panel)
		_weapon_sub_btns.append(sub_panel)

	# Main toolbar row — one HBox of slot cards
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", roundi(6.0 * sc))
	vbox.add_child(hbox)

	for i in SLOT_DEFS.size():
		var def: Dictionary = SLOT_DEFS[i]
		var slot_idx: int = i

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(80.0 * sc, 0.0)
		panel.add_theme_stylebox_override("panel", _make_slot_style(false, sc))

		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", roundi(2.0 * sc))
		panel.add_child(inner)

		var key_lbl := Label.new()
		key_lbl.text = "[%s]" % def["key"]
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", roundi(9.0 * sc))
		key_lbl.add_theme_color_override("font_color", _DIM_COLOR)
		inner.add_child(key_lbl)

		var name_lbl := Label.new()
		name_lbl.text = def["label"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", roundi(11.0 * sc))
		name_lbl.add_theme_color_override("font_color", _TITLE_COLOR)
		inner.add_child(name_lbl)

		var cost_lbl := Label.new()
		var cost: int = _get_slot_cost(i)
		cost_lbl.text = "¤%d" % cost
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.add_theme_font_size_override("font_size", roundi(11.0 * sc))
		inner.add_child(cost_lbl)
		_cost_labels.append(cost_lbl)

		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(btn)
		btn.pressed.connect(func(): _select_slot(slot_idx))

		hbox.add_child(panel)
		_slot_buttons.append(panel)

	add_child(wrapper)
	_refresh_selection()

func _get_slot_cost(slot_idx: int) -> int:
	var def: Dictionary = SLOT_DEFS[slot_idx]
	if def["type"] == "weapon":
		return WEAPON_COSTS.get(WEAPON_SUBTYPES[_selected_sub], 20)
	return PLACEABLE_COSTS.get(def["cost_key"], 0)

func deselect() -> void:
	_selected_slot   = -1
	selected_type    = ""
	selected_subtype = ""
	_weapon_subrow.visible = false
	_refresh_selection()

func _select_slot(slot_idx: int) -> void:
	_selected_slot = slot_idx
	var def: Dictionary = SLOT_DEFS[slot_idx]
	selected_type    = def["type"]
	selected_subtype = def["subtype"]
	if selected_type == "weapon":
		selected_subtype = WEAPON_SUBTYPES[_selected_sub]
		_weapon_subrow.visible = true
	else:
		_weapon_subrow.visible = false
	_refresh_selection()
	slot_changed.emit(selected_type, selected_subtype)

func _select_weapon_sub(sub_idx: int) -> void:
	_selected_sub    = sub_idx
	selected_subtype = WEAPON_SUBTYPES[sub_idx]
	_refresh_weapon_sub()
	slot_changed.emit(selected_type, selected_subtype)

func _refresh_selection() -> void:
	for i in _slot_buttons.size():
		var panel: PanelContainer = _slot_buttons[i]
		panel.add_theme_stylebox_override("panel", _make_slot_style(i == _selected_slot, _scale))
	_refresh_weapon_sub()

func _refresh_weapon_sub() -> void:
	for i in _weapon_sub_btns.size():
		var panel: PanelContainer = _weapon_sub_btns[i]
		panel.add_theme_stylebox_override("panel", _make_slot_style(i == _selected_sub and selected_type == "weapon", _scale))

func _process(_delta: float) -> void:
	_tick_hotkeys()
	_tick_cost_colors()

func _tick_hotkeys() -> void:
	for i in SLOT_DEFS.size():
		var action: String = "supporter_slot_%d" % (i + 1)
		if Input.is_action_just_pressed(action):
			_select_slot(i)

func _tick_cost_colors() -> void:
	var pts: int = TeamData.get_points(_player_team)
	for i in _cost_labels.size():
		var lbl: Label = _cost_labels[i]
		var cost: int = _get_slot_cost(i)
		if pts < cost:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			lbl.remove_theme_color_override("font_color")
