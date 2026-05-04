extends CanvasLayer
# FighterSkillBar — 2-slot active skill bar for the Fighter HUD.
# Displayed bottom-centre, above the crosshair area.
# Built entirely in code — no .tscn required.
#
# Usage:
#   var bar := Node.new()
#   bar.set_script(FighterSkillBarScript)
#   add_child(bar)
#   bar.setup(peer_id)

# ── Constants ─────────────────────────────────────────────────────────────────

const SLOT_SIZE    := 80
const SLOT_GAP     := 8
const CARD_RADIUS  := 4
const FONT_SIZE_KEY  := 9
const FONT_SIZE_NAME := 11
const FONT_SIZE_COOL := 10
const FADE_DURATION  := 0.4

const _BG_COLOR       := Color(0.06, 0.07, 0.09, 0.92)
const _BORDER_READY   := Color(0.85, 0.32, 0.05, 1.0)   # orange
const _BORDER_CD      := Color(0.35, 0.35, 0.35, 1.0)   # grey
const _KEY_COLOR      := Color(0.55, 0.45, 0.35, 1.0)   # dim brown
const _NAME_COLOR     := Color(1.0,  0.35, 0.1,  1.0)   # bright orange
const _EMPTY_COLOR    := Color(0.4,  0.4,  0.4,  1.0)   # muted
const _COOL_COLOR     := Color(0.9,  0.9,  0.9,  1.0)   # white
const _SWEEP_COLOR    := Color(0.0,  0.0,  0.0,  0.55)  # dark overlay

# ── Inner class: per-slot data ────────────────────────────────────────────────

class SlotData:
	var card:      PanelContainer
	var key_lbl:   Label
	var name_lbl:  Label
	var cool_lbl:  Label
	var sweep:     Control      # redraws each frame when on cooldown
	var node_id:   String = ""
	var total_cd:  float  = 0.0
	# Cached style refs for border colour swaps
	var style_box: StyleBoxFlat

# ── State ─────────────────────────────────────────────────────────────────────

var _peer_id: int    = -1
var _slots: Array    = []    # Array[SlotData], size 2
var _root:  Control  = null

# ── Public API ────────────────────────────────────────────────────────────────

func setup(peer_id: int) -> void:
	_peer_id = peer_id
	layer    = 9
	_build_ui()
	SkillTree.active_slots_changed.connect(_on_slots_changed)
	SkillTree.active_used.connect(_on_active_used)
	GameSync.player_died.connect(_on_player_died)
	GameSync.player_respawned.connect(_on_player_respawned)
	_refresh_all()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Wrapper anchored bottom-wide
	_root = Control.new()
	_root.name                = "SkillBarRoot"
	_root.anchor_left         = 0.0
	_root.anchor_top          = 1.0
	_root.anchor_right        = 1.0
	_root.anchor_bottom       = 1.0
	_root.offset_top          = -(SLOT_SIZE + 16)
	_root.offset_bottom       = -8
	_root.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var centre := CenterContainer.new()
	centre.name               = "Centre"
	centre.anchor_left        = 0.0
	centre.anchor_top         = 0.0
	centre.anchor_right       = 1.0
	centre.anchor_bottom      = 1.0
	centre.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)

	var row := HBoxContainer.new()
	row.name                  = "SlotsRow"
	row.alignment             = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", SLOT_GAP)
	row.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	centre.add_child(row)

	var key_labels := ["[Q]", "[E]"]
	for i in 2:
		var sd := SlotData.new()
		sd.card = _build_slot_card(key_labels[i], sd)
		row.add_child(sd.card)
		_slots.append(sd)

func _build_slot_card(key_text: String, sd: SlotData) -> PanelContainer:
	# StyleBox
	var sb := StyleBoxFlat.new()
	sb.bg_color               = _BG_COLOR
	sb.border_color           = _BORDER_READY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(CARD_RADIUS)
	sd.style_box              = sb

	var card := PanelContainer.new()
	card.custom_minimum_size  = Vector2(SLOT_SIZE, SLOT_SIZE)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter         = Control.MOUSE_FILTER_IGNORE

	# Stack (Control fills card)
	var stack := Control.new()
	stack.anchor_right        = 1.0
	stack.anchor_bottom       = 1.0
	stack.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)

	# VBox centred inside stack
	var vbox := VBoxContainer.new()
	vbox.anchor_left          = 0.0
	vbox.anchor_top           = 0.0
	vbox.anchor_right         = 1.0
	vbox.anchor_bottom        = 1.0
	vbox.alignment            = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	stack.add_child(vbox)

	# Key label  [Q] / [E]
	var key_lbl := Label.new()
	key_lbl.text              = key_text
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.add_theme_font_size_override("font_size", FONT_SIZE_KEY)
	key_lbl.add_theme_color_override("font_color", _KEY_COLOR)
	vbox.add_child(key_lbl)
	sd.key_lbl = key_lbl

	# Skill name label
	var name_lbl := Label.new()
	name_lbl.text             = "—"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", FONT_SIZE_NAME)
	name_lbl.add_theme_color_override("font_color", _EMPTY_COLOR)
	name_lbl.autowrap_mode    = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)
	sd.name_lbl = name_lbl

	# Cooldown countdown label (hidden when ready)
	var cool_lbl := Label.new()
	cool_lbl.text             = ""
	cool_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cool_lbl.add_theme_font_size_override("font_size", FONT_SIZE_COOL)
	cool_lbl.add_theme_color_override("font_color", _COOL_COLOR)
	cool_lbl.visible          = false
	vbox.add_child(cool_lbl)
	sd.cool_lbl = cool_lbl

	# Sweep overlay (drawn via _draw, sits on top of vbox)
	var sweep := _SweepControl.new()
	sweep.anchor_left         = 0.0
	sweep.anchor_top          = 0.0
	sweep.anchor_right        = 1.0
	sweep.anchor_bottom       = 1.0
	sweep.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sweep._slot_data          = sd
	sweep._peer_id            = _peer_id
	stack.add_child(sweep)
	sd.sweep = sweep

	return card

# ── Sweep control inner class ─────────────────────────────────────────────────

class _SweepControl extends Control:
	var _slot_data: SlotData = null
	var _peer_id:   int      = -1
	const SWEEP_COLOR := Color(0.0, 0.0, 0.0, 0.55)

	func _draw() -> void:
		if _slot_data == null or _slot_data.node_id == "" or _peer_id < 0:
			return
		var cd: float = SkillTree.get_cooldown(_peer_id, _slot_data.node_id)
		if cd <= 0.0 or _slot_data.total_cd <= 0.0:
			return
		var frac: float = cd / _slot_data.total_cd
		var centre: Vector2 = size * 0.5
		var radius: float   = minf(size.x, size.y) * 0.5
		var start_angle: float = -PI * 0.5
		var end_angle: float   = start_angle + frac * TAU
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(centre)
		var steps: int = max(32, int(frac * 64))
		for s in (steps + 1):
			var a: float = start_angle + (float(s) / float(steps)) * (end_angle - start_angle)
			pts.append(centre + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(pts, SWEEP_COLOR)

# ── Process: tick cooldown display ───────────────────────────────────────────

func _process(_delta: float) -> void:
	if _peer_id < 0:
		return
	for i in 2:
		var sd: SlotData = _slots[i]
		if sd.node_id == "":
			continue
		var cd: float = SkillTree.get_cooldown(_peer_id, sd.node_id)
		if cd > 0.0:
			sd.cool_lbl.text    = "%.1fs" % cd
			sd.cool_lbl.visible = true
			sd.style_box.border_color = _BORDER_CD
			sd.sweep.queue_redraw()
		else:
			if sd.cool_lbl.visible:
				# Just came off cooldown — reset to ready state
				sd.cool_lbl.visible = false
				sd.style_box.border_color = _BORDER_READY
				sd.sweep.queue_redraw()

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_slots_changed(peer_id: int, _slots_arr: Array) -> void:
	if peer_id != _peer_id:
		return
	_refresh_all()

func _on_active_used(peer_id: int, node_id: String) -> void:
	if peer_id != _peer_id:
		return
	# Find which slot(s) have this node and record total_cd
	for i in 2:
		var sd: SlotData = _slots[i]
		if sd.node_id == node_id:
			var def: Dictionary = SkillDefs.get_def(node_id)
			sd.total_cd = float(def.get("cooldown", 0.0))
			sd.style_box.border_color = _BORDER_CD
			sd.cool_lbl.visible = true
			sd.sweep.queue_redraw()

func _on_player_died(peer_id: int, _respawn_time: float) -> void:
	if peer_id != _peer_id:
		return
	if _root == null:
		return
	var tw: Tween = create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)

func _on_player_respawned(peer_id: int, _spawn_pos: Vector3) -> void:
	if peer_id != _peer_id:
		return
	if _root == null:
		return
	var tw: Tween = create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

# ── Refresh helpers ───────────────────────────────────────────────────────────

func _refresh_all() -> void:
	for i in 2:
		_refresh_slot(i)

func _refresh_slot(idx: int) -> void:
	if _peer_id < 0:
		return
	var sd: SlotData = _slots[idx]
	var slots: Array = SkillTree.get_active_slots(_peer_id)
	var node_id: String = slots[idx] if idx < slots.size() else ""
	sd.node_id = node_id

	if node_id == "":
		sd.name_lbl.text = "—"
		sd.name_lbl.add_theme_color_override("font_color", _EMPTY_COLOR)
		sd.cool_lbl.visible = false
		sd.style_box.border_color = _BORDER_READY
		sd.sweep.queue_redraw()
		sd.total_cd = 0.0
	else:
		var def: Dictionary = SkillDefs.get_def(node_id)
		sd.name_lbl.text = str(def.get("name", node_id))
		sd.name_lbl.add_theme_color_override("font_color", _NAME_COLOR)
		var cd: float = SkillTree.get_cooldown(_peer_id, node_id)
		if cd > 0.0:
			sd.total_cd = maxf(sd.total_cd, cd)
			sd.cool_lbl.text    = "%.1fs" % cd
			sd.cool_lbl.visible = true
			sd.style_box.border_color = _BORDER_CD
		else:
			sd.total_cd = float(def.get("cooldown", 0.0))
			sd.cool_lbl.visible = false
			sd.style_box.border_color = _BORDER_READY
		sd.sweep.queue_redraw()
