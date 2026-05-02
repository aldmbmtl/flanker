extends CanvasLayer
## RamHUD — left-edge vertical toolbar for requesting ram minions immediately.
## Always visible during play (same pattern as LaneBoostHUD).
## Top section: 3 tier buttons (Beaver / Cow / Elephant) — clicking one selects it.
## Bottom section: LEFT / MID / RIGHT / ALL lane buttons — clicking one fires that
##                 tier on that lane immediately (costs RAM_TIER_COSTS[tier] per lane).
##
## Usage:
##   setup(team)
##   — no other wiring required; HUD manages itself.

var _player_team: int = 0
var _scale: float     = 1.0
var _tier: int        = 0   # currently-selected tier (0=beaver, 1=cow, 2=elephant)

const _BG_COLOR     := Color(0.04, 0.05, 0.06, 0.92)
const _BORDER_COLOR := Color(0.85, 0.32, 0.05, 1.0)
const _TITLE_COLOR  := Color(1.0, 0.35, 0.1, 1.0)
const _DIM_COLOR    := Color(0.55, 0.45, 0.35, 1.0)
const _SLOT_BG      := Color(0.06, 0.07, 0.09, 0.92)
const _ACTIVE_BG    := Color(0.10, 0.06, 0.02, 0.92)

const TIER_COSTS:  Array[int]    = [15, 30, 50]
const TIER_NAMES:  Array[String] = ["Beaver", "Cow", "Elephant"]
const TIER_LABELS: Array[String] = ["Ram I", "Ram II", "Ram III"]

const _LANES: Array = [
	{ "label": "LEFT",  "lane_i": 0 },
	{ "label": "MID",   "lane_i": 1 },
	{ "label": "RIGHT", "lane_i": 2 },
	{ "label": "ALL",   "lane_i": -1 },
]

var _tier_panels: Array  = []   # PanelContainer per tier button
var _lane_panels: Array  = []   # PanelContainer per lane button
var _cost_lbl: Label     = null

func _ready() -> void:
	_scale = float(DisplayServer.window_get_size().y) / 1080.0
	layer  = 12
	_build_ui()
	# Always visible — no hide/show toggling needed.

func setup(p_team: int) -> void:
	_player_team = p_team

# ── UI construction ───────────────────────────────────────────────────────────

func _make_card_style() -> StyleBoxFlat:
	var sc: float = _scale
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
	s.content_margin_left   = 10.0 * sc
	s.content_margin_right  = 10.0 * sc
	s.content_margin_top    = 10.0 * sc
	s.content_margin_bottom = 10.0 * sc
	return s

func _make_tier_style(selected: bool, can_afford: bool) -> StyleBoxFlat:
	var sc: float = _scale
	var s := StyleBoxFlat.new()
	if selected:
		s.bg_color    = _ACTIVE_BG
		s.border_color = _BORDER_COLOR
	elif can_afford:
		s.bg_color    = _SLOT_BG
		s.border_color = Color(_BORDER_COLOR, 0.5)
	else:
		s.bg_color    = Color(0.04, 0.04, 0.05, 0.92)
		s.border_color = Color(_BORDER_COLOR, 0.15)
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left     = 3
	s.corner_radius_top_right    = 3
	s.corner_radius_bottom_right = 3
	s.corner_radius_bottom_left  = 3
	s.content_margin_left   = 8.0 * sc
	s.content_margin_right  = 8.0 * sc
	s.content_margin_top    = 4.0 * sc
	s.content_margin_bottom = 4.0 * sc
	return s

func _make_lane_style(can_afford: bool) -> StyleBoxFlat:
	var sc: float = _scale
	var s := StyleBoxFlat.new()
	if can_afford:
		s.bg_color    = _SLOT_BG
		s.border_color = Color(_BORDER_COLOR, 0.5)
	else:
		s.bg_color    = Color(0.04, 0.04, 0.05, 0.92)
		s.border_color = Color(_BORDER_COLOR, 0.15)
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
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

	var wrapper := Control.new()
	wrapper.name = "RamWrapper"
	wrapper.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	wrapper.anchor_right  = 0.0
	wrapper.offset_left   = 130.0 * sc
	wrapper.offset_right  = 260.0 * sc
	wrapper.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(center)

	var root := PanelContainer.new()
	root.name = "RamToolbarRoot"
	root.add_theme_stylebox_override("panel", _make_card_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(6.0 * sc))
	root.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "SEND RAM"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", roundi(10.0 * sc))
	header.add_theme_color_override("font_color", _TITLE_COLOR)
	vbox.add_child(header)

	# Tier select buttons
	for ti in TIER_NAMES.size():
		_add_tier_button(ti, vbox)

	# Divider label
	_cost_lbl = Label.new()
	_cost_lbl.text = "¤%d / lane" % TIER_COSTS[_tier]
	_cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_lbl.add_theme_font_size_override("font_size", roundi(9.0 * sc))
	_cost_lbl.add_theme_color_override("font_color", _DIM_COLOR)
	vbox.add_child(_cost_lbl)

	# Lane buttons
	for li in _LANES.size():
		_add_lane_button(li, vbox)

	center.add_child(root)
	add_child(wrapper)

func _add_tier_button(ti: int, vbox: VBoxContainer) -> void:
	var sc: float = _scale

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(100.0 * sc, 0.0)
	panel.add_theme_stylebox_override("panel", _make_tier_style(ti == _tier, true))

	var lbl := Label.new()
	lbl.text = TIER_NAMES[ti]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", roundi(10.0 * sc))
	lbl.add_theme_color_override("font_color", _TITLE_COLOR)
	panel.add_child(lbl)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(btn)
	btn.pressed.connect(func() -> void: _on_tier_pressed(ti))

	vbox.add_child(panel)
	_tier_panels.append(panel)

func _add_lane_button(li: int, vbox: VBoxContainer) -> void:
	var sc: float = _scale
	var slot: Dictionary = _LANES[li]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(100.0 * sc, 0.0)
	panel.add_theme_stylebox_override("panel", _make_lane_style(true))

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", roundi(2.0 * sc))
	panel.add_child(inner)

	var name_lbl := Label.new()
	name_lbl.text = slot["label"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", roundi(11.0 * sc))
	name_lbl.add_theme_color_override("font_color", _TITLE_COLOR)
	inner.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "send now" if slot["lane_i"] >= 0 else "all 3 lanes"
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", roundi(9.0 * sc))
	desc_lbl.add_theme_color_override("font_color", _DIM_COLOR)
	inner.add_child(desc_lbl)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(btn)
	btn.pressed.connect(func() -> void: _on_lane_pressed(li))

	vbox.add_child(panel)
	_lane_panels.append(panel)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var pts: int        = TeamData.get_points(_player_team)
	var cost: int       = TIER_COSTS[_tier]
	var afford_one: bool = pts >= cost
	var afford_all: bool = pts >= cost * 3

	# Refresh tier button styles
	for ti in _tier_panels.size():
		var p: PanelContainer = _tier_panels[ti]
		if is_instance_valid(p):
			p.add_theme_stylebox_override("panel", _make_tier_style(ti == _tier, pts >= TIER_COSTS[ti]))

	# Refresh lane button styles
	for li in _lane_panels.size():
		var p: PanelContainer = _lane_panels[li]
		if is_instance_valid(p):
			var is_all: bool = _LANES[li]["lane_i"] == -1
			p.add_theme_stylebox_override("panel", _make_lane_style(afford_all if is_all else afford_one))

# ── Input handlers ────────────────────────────────────────────────────────────

func _on_tier_pressed(ti: int) -> void:
	_tier = ti
	if _cost_lbl and is_instance_valid(_cost_lbl):
		_cost_lbl.text = "¤%d / lane" % TIER_COSTS[_tier]

func _on_lane_pressed(li: int) -> void:
	var lane_i: int   = _LANES[li]["lane_i"]
	var cost: int     = TIER_COSTS[_tier]
	var lanes_n: int  = 3 if lane_i == -1 else 1
	if TeamData.get_points(_player_team) < cost * lanes_n:
		return

	if multiplayer.is_server():
		var spawner: Node = get_tree().root.get_node_or_null("Main/MinionSpawner")
		if spawner == null:
			return
		if spawner.request_ram_minion(_player_team, _tier, lane_i):
			LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
	else:
		LobbyManager.request_ram_minion.rpc_id(1, _tier, _player_team, lane_i)
