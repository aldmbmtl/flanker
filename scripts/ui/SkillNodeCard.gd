extends Node
# SkillNodeCard — circular skill node for CharacterScreen.
# Left-click  → unlock (if available).
# Right-click → assign to next free active slot (if unlocked + active type).
# Hover       → Godot built-in tooltip shows name / description / cost.

signal unlock_requested(node_id: String)
signal assign_active_requested(node_id: String)

var _node_id:   String = ""
var _peer_id:   int    = 1
var _is_active: bool   = false

@onready var _circle_btn:   Button    = $CircleBtn
@onready var _name_label:   Label     = $NameLabel
@onready var _cost_badge:   Label     = $CostBadge
@onready var _lock_overlay: ColorRect = $LockOverlay

var _style_locked:    StyleBoxFlat
var _style_available: StyleBoxFlat
var _style_unlocked:  StyleBoxFlat

func _make_circle_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(36)
	return s

func setup(node_id: String, peer_id: int) -> void:
	_node_id = node_id
	_peer_id = peer_id
	var def: Dictionary = SkillDefs.get_def(node_id)

	# Short display name — strip role prefix (f_ / s_) then capitalize each word.
	var raw: String = node_id.replace("f_", "").replace("s_", "").replace("_", " ")
	_name_label.text = raw.capitalize()

	var cost: int = int(def.get("cost", 1))
	_cost_badge.text = "%dSP" % cost

	_is_active = def.get("type", "") == "active"

	# Tooltip: full name + description + cost + type hint.
	var type_hint: String = " [Active]" if _is_active else " [Passive]"
	var tooltip: String   = "%s%s\n%s\nCost: %d SP" % [
		node_id.replace("_", " ").capitalize(),
		type_hint,
		def.get("description", ""),
		cost
	]
	if _is_active:
		tooltip += "\nRight-click to assign to Q / E slot"
	# tooltip_text lives on the CircleBtn so hover anywhere on the circle shows it.
	_circle_btn.tooltip_text = tooltip

	_circle_btn.pressed.connect(_on_left_click)
	_circle_btn.gui_input.connect(_on_gui_input)

	# Build the three circle styles.
	_style_locked    = _make_circle_style(Color(0.18, 0.18, 0.2,  1.0), Color(0.35, 0.35, 0.35, 1.0))
	_style_available = _make_circle_style(Color(0.85, 0.55, 0.05, 1.0), Color(1.0,  0.8,  0.2,  1.0))
	_style_unlocked  = _make_circle_style(Color(0.15, 0.6,  0.2,  1.0), Color(0.3,  1.0,  0.4,  1.0))

	refresh()

func refresh() -> void:
	if _node_id == "":
		return
	var unlocked:  bool = SkillTree.is_unlocked(_peer_id, _node_id)
	var available: bool = SkillTree.can_unlock(_peer_id, _node_id)

	_lock_overlay.visible = not unlocked and not available

	if unlocked:
		_circle_btn.add_theme_stylebox_override("normal",   _style_unlocked)
		_circle_btn.add_theme_stylebox_override("disabled", _style_unlocked)
		_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	elif available:
		_circle_btn.add_theme_stylebox_override("normal",   _style_available)
		_circle_btn.add_theme_stylebox_override("disabled", _style_available)
		_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		_circle_btn.add_theme_stylebox_override("normal",   _style_locked)
		_circle_btn.add_theme_stylebox_override("disabled", _style_locked)
		_name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_left_click() -> void:
	var unlocked: bool = SkillTree.is_unlocked(_peer_id, _node_id)
	if not unlocked:
		unlock_requested.emit(_node_id)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var unlocked: bool = SkillTree.is_unlocked(_peer_id, _node_id)
			if unlocked and _is_active:
				assign_active_requested.emit(_node_id)
