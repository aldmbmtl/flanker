extends CanvasLayer
## LaneBoostHUD — right-edge vertical toolbar for the Supporter role.
## Lets the Supporter queue extra minions on specific lanes for the next wave.
##
## Buttons:
##   LEFT  — +3 minions on lane 0 next wave (costs 15 pts)
##   MID   — +3 minions on lane 1 next wave (costs 15 pts)
##   RIGHT — +3 minions on lane 2 next wave (costs 15 pts)
##   ALL   — +1 minion on every lane next wave (costs 15 pts)
##
## Boost state is server-authoritative. LobbyManager.lane_boosts_synced drives the display.
## Wire LobbyManager.lane_boosts_synced → apply_boost_sync() from Main.gd after setup().
##
## Usage:
##   setup(team)
##   LobbyManager.lane_boosts_synced.connect(_lane_boost_hud.apply_boost_sync)

var _player_team: int = 0
var _scale: float = 1.0

## Shared style constants — matches project palette (same as LauncherHUD)
const _BG_COLOR     := Color(0.04, 0.05, 0.06, 0.92)
const _BORDER_COLOR := Color(0.85, 0.32, 0.05, 1.0)
const _TITLE_COLOR  := Color(1.0, 0.35, 0.1, 1.0)
const _DIM_COLOR    := Color(0.55, 0.45, 0.35, 1.0)
const _SLOT_BG      := Color(0.06, 0.07, 0.09, 0.92)
const _ACTIVE_BG    := Color(0.04, 0.12, 0.04, 0.92)

const BOOST_COST: int = 15

## Slot definitions: [label, lane_i]  lane_i=-1 means all lanes
const _SLOTS: Array = [
	{ "label": "LEFT",  "lane_i": 0 },
	{ "label": "MID",   "lane_i": 1 },
	{ "label": "RIGHT", "lane_i": 2 },
	{ "label": "ALL",   "lane_i": -1 },
]

## Server-synced boost counts for our team: index 0..2 = per-lane extra minions.
## Updated via apply_boost_sync() which is connected to LobbyManager.lane_boosts_synced.
var _synced_boosts: Array = [0, 0, 0]

## Button panel refs for refresh
var _panels: Array = []
var _boost_labels: Array = []
var _vbox: VBoxContainer = null

func _ready() -> void:
	_scale = float(DisplayServer.window_get_size().y) / 1080.0
	layer = 11
	_build_ui()

func setup(p_team: int) -> void:
	_player_team = p_team

## Called by Main.gd via LobbyManager.lane_boosts_synced signal.
## boosts_team0 / boosts_team1 are Array[int] of size 3 (one per lane).
func apply_boost_sync(boosts_team0: Array, boosts_team1: Array) -> void:
	if _player_team == 0:
		_synced_boosts = boosts_team0.duplicate()
	else:
		_synced_boosts = boosts_team1.duplicate()

# ── UI construction ───────────────────────────────────────────────────────────

func _make_card_style() -> StyleBoxFlat:
	var sc: float = _scale
	var s := StyleBoxFlat.new()
	s.bg_color = _BG_COLOR
	s.border_width_left   = 1
	s.border_width_right  = 3
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

func _make_slot_style(has_boost: bool, can_afford: bool) -> StyleBoxFlat:
	var sc: float = _scale
	var s := StyleBoxFlat.new()
	if has_boost:
		s.bg_color = _ACTIVE_BG
		s.border_color = Color(0.85, 0.32, 0.05, 0.8)
	elif can_afford:
		s.bg_color = _SLOT_BG
		s.border_color = Color(_BORDER_COLOR, 0.5)
	else:
		s.bg_color = Color(0.04, 0.04, 0.05, 0.92)
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

	# Full-rect transparent wrapper — CenterContainer aligns card to right-center
	var wrapper := Control.new()
	wrapper.name = "LaneBoostWrapper"
	wrapper.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	wrapper.anchor_left  = 1.0
	wrapper.offset_left  = -130.0 * sc
	wrapper.offset_right = 0.0
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(center)

	var root := PanelContainer.new()
	root.name = "LaneBoostToolbarRoot"
	root.add_theme_stylebox_override("panel", _make_card_style())

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", roundi(6.0 * sc))
	root.add_child(_vbox)

	# Header
	var header := Label.new()
	header.text = "REINFORCE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", roundi(10.0 * sc))
	header.add_theme_color_override("font_color", _TITLE_COLOR)
	_vbox.add_child(header)

	# Cost label under header
	var cost_header := Label.new()
	cost_header.text = "¤%d / click" % BOOST_COST
	cost_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_header.add_theme_font_size_override("font_size", roundi(9.0 * sc))
	cost_header.add_theme_color_override("font_color", _DIM_COLOR)
	_vbox.add_child(cost_header)

	# One button per slot
	for slot_i in _SLOTS.size():
		var slot: Dictionary = _SLOTS[slot_i]
		_add_slot_button(slot_i, slot)

	center.add_child(root)
	add_child(wrapper)

func _add_slot_button(slot_i: int, slot: Dictionary) -> void:
	var sc: float = _scale

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(100.0 * sc, 0.0)
	panel.add_theme_stylebox_override("panel", _make_slot_style(false, true))

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", roundi(2.0 * sc))
	panel.add_child(inner)

	# Lane label
	var name_lbl := Label.new()
	name_lbl.text = slot["label"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", roundi(11.0 * sc))
	name_lbl.add_theme_color_override("font_color", _TITLE_COLOR)
	inner.add_child(name_lbl)

	# What it does
	var desc_lbl := Label.new()
	if slot["lane_i"] == -1:
		desc_lbl.text = "+1 all lanes"
	else:
		desc_lbl.text = "+3 next wave"
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", roundi(9.0 * sc))
	desc_lbl.add_theme_color_override("font_color", _DIM_COLOR)
	inner.add_child(desc_lbl)

	# Boost status label — server-synced: shows queued count or affordability
	var boost_lbl := Label.new()
	boost_lbl.text = ""
	boost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boost_lbl.add_theme_font_size_override("font_size", roundi(9.0 * sc))
	boost_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	inner.add_child(boost_lbl)
	_boost_labels.append(boost_lbl)

	# Invisible button overlay
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(btn)
	btn.pressed.connect(func() -> void: _on_boost_pressed(slot_i))

	_vbox.add_child(panel)
	_panels.append(panel)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_refresh_all()

func _refresh_all() -> void:
	var pts: int = TeamData.get_points(_player_team)
	var can_afford: bool = pts >= BOOST_COST

	for slot_i in _SLOTS.size():
		var lane_i: int = _SLOTS[slot_i]["lane_i"]

		# For the ALL button, has_boost = true if any lane has a boost queued
		var has_boost: bool = false
		if lane_i == -1:
			for li in range(3):
				if _synced_boosts[li] > 0:
					has_boost = true
					break
		else:
			has_boost = _synced_boosts[lane_i] > 0

		var panel: PanelContainer = _panels[slot_i]
		if is_instance_valid(panel):
			panel.add_theme_stylebox_override("panel", _make_slot_style(has_boost, can_afford))

		var blbl: Label = _boost_labels[slot_i]
		if not is_instance_valid(blbl):
			continue

		if lane_i == -1:
			# ALL button: show total queued across all lanes
			var total: int = 0
			for li in range(3):
				total += _synced_boosts[li]
			if total > 0:
				blbl.text = "+%d total" % total
				blbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			elif not can_afford:
				blbl.text = "¤ LOW"
				blbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
			else:
				blbl.text = ""
		else:
			var queued: int = _synced_boosts[lane_i]
			if queued > 0:
				blbl.text = "+%d queued" % queued
				blbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			elif not can_afford:
				blbl.text = "¤ LOW"
				blbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
			else:
				blbl.text = ""

# ── Input handler ─────────────────────────────────────────────────────────────

func _on_boost_pressed(slot_i: int) -> void:
	if TeamData.get_points(_player_team) < BOOST_COST:
		return

	var slot: Dictionary = _SLOTS[slot_i]
	var lane_i: int = slot["lane_i"]

	# If we are the server (singleplayer or multiplayer host), call directly.
	# The server path also calls sync_lane_boosts.rpc so all clients update.
	if multiplayer.is_server():
		var spawner: Node = get_tree().root.get_node_or_null("Main/MinionSpawner")
		if spawner == null:
			return
		if not TeamData.spend_points(_player_team, BOOST_COST):
			return
		if lane_i == -1:
			spawner.boost_all_lanes(_player_team)
		else:
			spawner.boost_lane(_player_team, lane_i, LobbyManager.LANE_BOOST_AMOUNT)
		var b: Array = spawner.get("_lane_boosts") as Array
		LobbyManager.sync_lane_boosts.rpc(b[0], b[1])
		LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
	else:
		# Multiplayer client: RPC to server.
		# Server will validate, spend points, boost, then broadcast sync_lane_boosts
		# and sync_team_points back to all peers — no optimistic update needed here.
		LobbyManager.request_lane_boost.rpc_id(1, lane_i, _player_team)
