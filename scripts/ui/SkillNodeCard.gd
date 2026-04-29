extends Control
# SkillNodeCard — circular skill node for CharacterScreen.
# Left-click        → unlock (if available).
# Hover + Q         → assign to active slot 0 (Q key) if unlocked + active type.
# Hover + E         → assign to active slot 1 (E key) if unlocked + active type.
# Hover + Q/E (locked) → brief red flash on lock overlay to signal not unlocked.
# Hover             → Godot built-in tooltip shows name / description / cost.

signal unlock_requested(node_id: String)
signal assign_active_requested(node_id: String, slot: int)

var _node_id:   String = ""
var _peer_id:   int    = 1
var _is_active: bool   = false
var _hovered:   bool   = false

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
		tooltip += "\nHover + Q to assign slot 1 (Q), E to assign slot 2 (E)"
	# tooltip_text lives on the CircleBtn so hover anywhere on the circle shows it.
	_circle_btn.tooltip_text = tooltip

	_circle_btn.pressed.connect(_on_left_click)
	_circle_btn.mouse_entered.connect(_on_mouse_entered)
	_circle_btn.mouse_exited.connect(_on_mouse_exited)

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

# ── Hover tracking ─────────────────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	_hovered = true

func _on_mouse_exited() -> void:
	_hovered = false

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_left_click() -> void:
	var unlocked: bool = SkillTree.is_unlocked(_peer_id, _node_id)
	if not unlocked:
		unlock_requested.emit(_node_id)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _hovered or not _is_active:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var slot: int = -1
	if event.keycode == KEY_Q:
		slot = 0
	elif event.keycode == KEY_E:
		slot = 1

	if slot == -1:
		return

	get_viewport().set_input_as_handled()

	var unlocked: bool = SkillTree.is_unlocked(_peer_id, _node_id)
	if unlocked:
		assign_active_requested.emit(_node_id, slot)
	else:
		_flash_not_unlocked()

func _flash_not_unlocked() -> void:
	# Show lock overlay in red briefly to signal the skill is not yet unlocked.
	_lock_overlay.visible = true
	var orig_color: Color = _lock_overlay.color
	_lock_overlay.color   = Color(0.8, 0.0, 0.0, 0.75)
	var tw: Tween = create_tween()
	tw.tween_property(_lock_overlay, "color", Color(0.0, 0.0, 0.0, 0.0), 0.4)
	await tw.finished
	# Restore correct visibility state after flash.
	refresh()
	_lock_overlay.color = orig_color
