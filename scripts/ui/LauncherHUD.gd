extends CanvasLayer
## LauncherHUD — left-edge vertical toolbar.
## One button per built launcher owned by this team.
## Also handles direct-cast strikes (e.g. recon_strike) that require no tower.
## Extensible: any launcher type from LauncherDefs is handled automatically.
##
## Usage:
##   setup(team)
##   Wire LobbyManager.item_spawned  → _on_item_spawned(type, team)
##   Wire LobbyManager.tower_despawned → _on_tower_despawned(type, team, tower_name)
##   RTSController calls confirm_target(world_pos) to complete a fire action.

signal fire_requested(launcher_name: String, launcher_type: String, target_pos: Vector3)
signal reveal_requested(target_pos: Vector3, reveal_radius: float, reveal_duration: float)

var _player_team: int = 0
var _scale: float = 1.0

# List of launcher entries: { name, type, cooldown_remaining, cooldown_max, button_panel, progress_bar, status_label }
var _launchers: Array = []

# Targeting state
var _targeting: bool = false
var _target_launcher_idx: int = -1

# Root container built in code
var _vbox: VBoxContainer = null
var _root: PanelContainer = null

func _ready() -> void:
	_scale = float(DisplayServer.window_get_size().y) / 1080.0
	layer = 11
	_build_ui()

func setup(p_team: int) -> void:
	_player_team = p_team
	_register_direct_cast_strikes()

# Registers all direct-cast strikes from LauncherDefs automatically.
func _register_direct_cast_strikes() -> void:
	for ltype in LauncherDefs.get_all_types():
		if LauncherDefs.is_direct_cast(ltype):
			_register_direct_strike(ltype)

# Registers a direct-cast strike (no tower node required).
func _register_direct_strike(strike_type: String) -> void:
	# Avoid duplicates
	for entry in _launchers:
		if entry["type"] == strike_type and entry["name"] == "":
			return
	var cd: float = LauncherDefs.get_cooldown(strike_type)
	var entry: Dictionary = {
		"name":               "",
		"type":               strike_type,
		"cooldown_remaining": 0.0,
		"cooldown_max":       cd,
		"button_panel":       null,
		"progress_bar":       null,
		"status_label":       null,
		"cost_label":         null,
		"direct_cast":        true,
	}
	_launchers.append(entry)
	_add_button(entry)
	_refresh_button(_launchers.size() - 1)

# ── Public API ────────────────────────────────────────────────────────────────

func is_targeting() -> bool:
	return _targeting

# Returns the launcher node for the currently active targeting action, or null.
# Returns null for direct-cast strikes (they have no tower node).
func get_active_launcher() -> Node:
	if not _targeting or _target_launcher_idx < 0:
		return null
	if _target_launcher_idx >= _launchers.size():
		return null
	var entry: Dictionary = _launchers[_target_launcher_idx]
	if entry.get("direct_cast", false) or entry["name"] == "":
		return null
	return get_tree().root.get_node_or_null("Main/" + entry["name"])

# Called by RTSController after the player clicks a target on the map.
func confirm_target(world_pos: Vector3) -> void:
	if not _targeting or _target_launcher_idx < 0:
		return
	var idx: int = _target_launcher_idx
	_cancel_targeting()

	if idx >= _launchers.size():
		return
	var entry: Dictionary = _launchers[idx]

	# Spend fire cost
	var fire_cost: int = LauncherDefs.get_fire_cost(entry["type"])
	if not TeamData.spend_points(_player_team, fire_cost):
		return

	# Start cooldown
	entry["cooldown_remaining"] = entry["cooldown_max"]

	# Direct-cast strikes emit reveal_requested instead of fire_requested
	if entry.get("direct_cast", false):
		var radius: float = LauncherDefs.get_reveal_radius(entry["type"])
		var duration: float = LauncherDefs.get_reveal_duration(entry["type"])
		reveal_requested.emit(world_pos, radius, duration)
		return

	# Emit signal so RTSController / LobbyManager can do the network call
	fire_requested.emit(entry["name"], entry["type"], world_pos)

# Cancel targeting mode (right-click / Escape)
func cancel_targeting() -> void:
	_cancel_targeting()

# ── Launcher registration ─────────────────────────────────────────────────────

# Called when a launcher is placed (item_spawned signal, type is a launcher type).
func register_launcher(launcher_name: String, launcher_type: String) -> void:
	# Avoid duplicates
	for entry in _launchers:
		if entry["name"] == launcher_name:
			return

	var cd: float = LauncherDefs.get_cooldown(launcher_type)
	var entry: Dictionary = {
		"name":               launcher_name,
		"type":               launcher_type,
		"cooldown_remaining": 0.0,
		"cooldown_max":       cd,
		"button_panel":       null,
		"progress_bar":       null,
		"status_label":       null,
		"cost_label":         null,
	}
	_launchers.append(entry)
	_add_button(entry)
	_refresh_button(_launchers.size() - 1)

# Called when a launcher is destroyed (tower_despawned signal).
func unregister_launcher(launcher_name: String) -> void:
	for i in range(_launchers.size()):
		if _launchers[i]["name"] == launcher_name:
			var entry: Dictionary = _launchers[i]
			if entry["button_panel"] != null and is_instance_valid(entry["button_panel"]):
				entry["button_panel"].queue_free()
			_launchers.remove_at(i)
			# If we were targeting this one, cancel
			if _targeting and _target_launcher_idx == i:
				_cancel_targeting()
			elif _targeting and _target_launcher_idx > i:
				_target_launcher_idx -= 1
			return

# ── UI construction ───────────────────────────────────────────────────────────

## Shared style constants — matches project palette
const _BG_COLOR     := Color(0.04, 0.05, 0.06, 0.92)
const _BORDER_COLOR := Color(0.85, 0.32, 0.05, 1.0)
const _TITLE_COLOR  := Color(1.0, 0.35, 0.1, 1.0)
const _DIM_COLOR    := Color(0.55, 0.45, 0.35, 1.0)
const _SLOT_BG      := Color(0.06, 0.07, 0.09, 0.92)
const _SEL_BG       := Color(0.14, 0.08, 0.04, 1.0)

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
	s.content_margin_left   = 10.0 * sc
	s.content_margin_right  = 10.0 * sc
	s.content_margin_top    = 10.0 * sc
	s.content_margin_bottom = 10.0 * sc
	return s

func _make_slot_style(selected: bool, ready_green: bool, sc: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if selected:
		s.bg_color = Color(0.22, 0.14, 0.02, 0.95)
		s.border_color = Color(1.0, 0.55, 0.1, 1.0)
	elif ready_green:
		s.bg_color = Color(0.04, 0.12, 0.04, 0.92)
		s.border_color = Color(0.85, 0.32, 0.05, 0.5)
	else:
		s.bg_color = _SLOT_BG
		s.border_color = Color(_BORDER_COLOR, 0.25)
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
	# Full-rect transparent wrapper — CenterContainer aligns card to left-center
	var wrapper := Control.new()
	wrapper.name = "LauncherWrapper"
	wrapper.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	wrapper.anchor_right  = 0.0
	wrapper.offset_left   = 0.0
	wrapper.offset_right  = 130.0 * sc
	wrapper.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(center)

	_root = PanelContainer.new()
	_root.name = "LauncherToolbarRoot"
	_root.add_theme_stylebox_override("panel", _make_card_style(sc))

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", roundi(6.0 * sc))
	_root.add_child(_vbox)

	# Header label
	var header := Label.new()
	header.text = "STRIKES"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", roundi(10.0 * sc))
	header.add_theme_color_override("font_color", _TITLE_COLOR)
	_vbox.add_child(header)

	center.add_child(_root)
	add_child(wrapper)

func _add_button(entry: Dictionary) -> void:
	var launcher_idx: int = _launchers.size() - 1

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(100.0 * _scale, 0.0)
	panel.add_theme_stylebox_override("panel", _make_slot_style(false, false, _scale))

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", roundi(2.0 * _scale))
	panel.add_child(inner)

	# Launcher label (type + index, or just label for direct-cast strikes)
	var name_lbl := Label.new()
	if entry.get("direct_cast", false):
		name_lbl.text = LauncherDefs.get_label(entry["type"])
	else:
		name_lbl.text = LauncherDefs.get_label(entry["type"]) + " #%d" % (_launchers.size())
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", roundi(10.0 * _scale))
	name_lbl.add_theme_color_override("font_color", _TITLE_COLOR)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(name_lbl)

	# Fire cost label
	var cost_lbl := Label.new()
	cost_lbl.text = "¤%d" % LauncherDefs.get_fire_cost(entry["type"])
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", roundi(10.0 * _scale))
	cost_lbl.add_theme_color_override("font_color", _DIM_COLOR)
	inner.add_child(cost_lbl)
	entry["cost_label"] = cost_lbl

	# Cooldown progress bar
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = entry["cooldown_max"]
	bar.value = entry["cooldown_max"]  # full = ready
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(84.0 * _scale, 8.0 * _scale)
	inner.add_child(bar)
	entry["progress_bar"] = bar

	# Status label
	var status := Label.new()
	status.text = "READY"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", roundi(10.0 * _scale))
	inner.add_child(status)
	entry["status_label"] = status

	# Invisible button overlay
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(btn)
	btn.pressed.connect(func() -> void: _on_launcher_button_pressed(launcher_idx))
	_vbox.add_child(panel)

	entry["button_panel"] = panel

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_cost_colors()

func _tick_cooldowns(delta: float) -> void:
	for i in _launchers.size():
		var entry: Dictionary = _launchers[i]
		if entry["cooldown_remaining"] > 0.0:
			entry["cooldown_remaining"] = maxf(0.0, entry["cooldown_remaining"] - delta)
		_refresh_button(i)

func _tick_cost_colors() -> void:
	var pts: int = TeamData.get_points(_player_team)
	for entry in _launchers:
		var cost: int = LauncherDefs.get_fire_cost(entry["type"])
		var lbl: Label = entry.get("cost_label")
		if lbl == null or not is_instance_valid(lbl):
			continue
		if pts < cost:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			lbl.remove_theme_color_override("font_color")

func _refresh_button(idx: int) -> void:
	if idx >= _launchers.size():
		return
	var entry: Dictionary = _launchers[idx]

	var bar: ProgressBar = entry.get("progress_bar")
	var status: Label    = entry.get("status_label")
	var panel: PanelContainer = entry.get("button_panel")

	if bar == null or not is_instance_valid(bar):
		return

	var remaining: float = entry["cooldown_remaining"]
	var cd_max: float    = entry["cooldown_max"]
	var fire_cost: int   = LauncherDefs.get_fire_cost(entry["type"])
	var pts: int         = TeamData.get_points(_player_team)

	# Bar: 0 = reloading, max = ready
	bar.max_value = cd_max
	bar.value     = cd_max - remaining

	var is_ready: bool = remaining <= 0.0
	var can_afford: bool = pts >= fire_cost
	var is_selected: bool = _targeting and _target_launcher_idx == idx

	if is_selected:
		status.text = "TARGET..."
		status.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
	elif not is_ready:
		var secs: int = int(remaining) + 1
		status.text = "~%ds" % secs
		status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	elif not can_afford:
		status.text = "¤ LOW"
		status.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	else:
		status.text = "READY"
		status.remove_theme_color_override("font_color")

	# Panel background
	if panel == null or not is_instance_valid(panel):
		return
	panel.add_theme_stylebox_override("panel", _make_slot_style(is_selected, is_ready and can_afford, _scale))

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _targeting:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_targeting()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_ESCAPE:
			_cancel_targeting()
			get_viewport().set_input_as_handled()

# ── Internal ──────────────────────────────────────────────────────────────────

func _on_launcher_button_pressed(idx: int) -> void:
	if idx >= _launchers.size():
		return
	var entry: Dictionary = _launchers[idx]

	# Must be ready
	if entry["cooldown_remaining"] > 0.0:
		return
	# Must be able to afford
	var fire_cost: int = LauncherDefs.get_fire_cost(entry["type"])
	if TeamData.get_points(_player_team) < fire_cost:
		return

	# Toggle: clicking the already-selected launcher cancels targeting
	if _targeting and _target_launcher_idx == idx:
		_cancel_targeting()
		return

	_targeting = true
	_target_launcher_idx = idx
	# Refresh all buttons to show selection state
	for i in _launchers.size():
		_refresh_button(i)

func _cancel_targeting() -> void:
	_targeting = false
	_target_launcher_idx = -1
	for i in _launchers.size():
		_refresh_button(i)

# ── Signal handlers (wire from Main.gd) ──────────────────────────────────────

func _on_item_spawned(item_type: String, team: int) -> void:
	if team != _player_team:
		return
	if not LauncherDefs.is_launcher_type(item_type):
		return
	# Direct-cast strikes are pre-registered at setup — no tower node to scan for
	if LauncherDefs.is_direct_cast(item_type):
		return
	# Find the newly added launcher node by scanning the launchers group
	# (it was just added so it won't be in _launchers yet)
	for node in get_tree().get_nodes_in_group("launchers"):
		if not is_instance_valid(node):
			continue
		var nt: int = node.get("team") if node.get("team") != null else -1
		if nt != _player_team:
			continue
		var lt: String = node.get("launcher_type") if node.get("launcher_type") != null else ""
		if lt != item_type:
			continue
		# Check not already registered
		var already: bool = false
		for entry in _launchers:
			if entry["name"] == node.name:
				already = true
				break
		if not already:
			register_launcher(node.name, item_type)

func _on_tower_despawned(item_type: String, team: int, tower_name: String) -> void:
	if team != _player_team:
		return
	if not LauncherDefs.is_launcher_type(item_type):
		return
	# Direct-cast strikes have no tower to despawn
	if LauncherDefs.is_direct_cast(item_type):
		return
	# Match by node name — avoids the deferred-free race where the node is still
	# alive in the tree when this signal fires.
	for i in range(_launchers.size()):
		var entry: Dictionary = _launchers[i]
		if entry["name"] != tower_name:
			continue
		if entry["button_panel"] != null and is_instance_valid(entry["button_panel"]):
			entry["button_panel"].queue_free()
		if _targeting and _target_launcher_idx == i:
			_cancel_targeting()
		elif _targeting and _target_launcher_idx > i:
			_target_launcher_idx -= 1
		_launchers.remove_at(i)
		return
