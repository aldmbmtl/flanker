extends Control
# CharacterScreen — unified Tab-key character screen.
# Left 25%: attribute point spending (HP / Speed / Damage).
# Right 75%: skill tree, vertical per-branch columns (tier 1 top → tier 3 bottom).
# Replaces both SkillTreeOverlay and the LevelUpDialog popup.

signal opened
signal closed

var _peer_id: int  = 1
var _is_mp:   bool = false
var _cards:   Array = []   # Array of SkillNodeCard controls

const SkillNodeCardScene := preload("res://scenes/ui/SkillNodeCard.tscn")

# ── Left panel @onready ───────────────────────────────────────────────────────
@onready var _level_label:   Label       = $Panel/HSplit/LeftPanel/VBox/LevelRow/LevelLabel
@onready var _xp_bar:        ProgressBar = $Panel/HSplit/LeftPanel/VBox/XPBar
@onready var _attr_pts_label: Label      = $Panel/HSplit/LeftPanel/VBox/AttrPtsLabel

@onready var _hp_bar:    ProgressBar = $Panel/HSplit/LeftPanel/VBox/HPRow/HPBar
@onready var _hp_frac:   Label       = $Panel/HSplit/LeftPanel/VBox/HPRow/HPFrac
@onready var _hp_btn:    Button      = $Panel/HSplit/LeftPanel/VBox/HPRow/HPBtn

@onready var _spd_bar:   ProgressBar = $Panel/HSplit/LeftPanel/VBox/SpeedRow/SpeedBar
@onready var _spd_frac:  Label       = $Panel/HSplit/LeftPanel/VBox/SpeedRow/SpeedFrac
@onready var _spd_btn:   Button      = $Panel/HSplit/LeftPanel/VBox/SpeedRow/SpeedBtn

@onready var _dmg_bar:   ProgressBar = $Panel/HSplit/LeftPanel/VBox/DamageRow/DamageBar
@onready var _dmg_frac:  Label       = $Panel/HSplit/LeftPanel/VBox/DamageRow/DamageFrac
@onready var _dmg_btn:   Button      = $Panel/HSplit/LeftPanel/VBox/DamageRow/DamageBtn

# ── Right panel @onready ──────────────────────────────────────────────────────
@onready var _role_label:    Label         = $Panel/HSplit/RightPanel/VBox/Header/RoleLabel
@onready var _sp_label:      Label         = $Panel/HSplit/RightPanel/VBox/Header/SPLabel
@onready var _branches_box:  HBoxContainer = $Panel/HSplit/RightPanel/VBox/BranchScroll/BranchContainer
@onready var _slot0_label:   Label         = $Panel/HSplit/RightPanel/VBox/SlotsRow/Slot0Box/SlotLabel
@onready var _slot1_label:   Label         = $Panel/HSplit/RightPanel/VBox/SlotsRow/Slot1Box/SlotLabel
@onready var _slot0_cd:      ProgressBar   = $Panel/HSplit/RightPanel/VBox/SlotsRow/Slot0Box/CooldownBar
@onready var _slot1_cd:      ProgressBar   = $Panel/HSplit/RightPanel/VBox/SlotsRow/Slot1Box/CooldownBar

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(peer_id: int, is_mp: bool) -> void:
	_peer_id = peer_id
	_is_mp   = is_mp
	visible  = false
	call_deferred("_init_ui")

func _init_ui() -> void:
	# Attribute buttons
	_hp_btn.pressed.connect(_on_hp_pressed)
	_spd_btn.pressed.connect(_on_spd_pressed)
	_dmg_btn.pressed.connect(_on_dmg_pressed)
	# Signals
	LevelSystem.attribute_spent.connect(_on_attribute_spent)
	LevelSystem.xp_gained.connect(_on_xp_gained)
	LevelSystem.level_up.connect(_on_level_up)
	SkillTree.skill_pts_changed.connect(_on_sp_changed)
	SkillTree.skill_unlocked.connect(_on_skill_unlocked)
	SkillTree.active_slots_changed.connect(_on_slots_changed)
	_build_skill_tree()

# ── Toggle ────────────────────────────────────────────────────────────────────

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_all()
		emit_signal("opened")
	else:
		emit_signal("closed")

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(_event: InputEvent) -> void:
	pass  # Toggle is dispatched by Main._input to avoid double-fire.

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_cooldown_bars()

# ── Build skill tree columns ──────────────────────────────────────────────────

func _build_skill_tree() -> void:
	for child in _branches_box.get_children():
		child.queue_free()
	_cards.clear()

	var role: String = SkillTree.get_role(_peer_id)
	_role_label.text = role.to_upper() + " SKILLS"

	var branches: Array = SkillDefs.get_branches_for_role(role)
	for branch in branches:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_theme_constant_override("separation", 6)

		# Branch header
		var branch_lbl := Label.new()
		branch_lbl.text = branch.to_upper()
		branch_lbl.add_theme_font_size_override("font_size", 12)
		branch_lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 0.05, 1.0))
		branch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(branch_lbl)

		_branches_box.add_child(col)

		# Cards — tier 1 at top, tier 3 at bottom
		var nodes_in_branch: Array = SkillDefs.get_nodes_in_branch(role, branch)
		for nid in nodes_in_branch:
			# Connector line between cards
			if col.get_child_count() > 1:
				var sep := ColorRect.new()
				sep.custom_minimum_size = Vector2(2, 14)
				sep.color = Color(0.85, 0.55, 0.05, 0.5)
				sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				col.add_child(sep)

			var card: Control = SkillNodeCardScene.instantiate()
			col.add_child(card)
			card.setup(nid, _peer_id)
			card.unlock_requested.connect(_on_unlock_requested)
			card.assign_active_requested.connect(_on_assign_active_requested)
			_cards.append(card)

# ── Full refresh ──────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	_refresh_attrs()
	_refresh_xp()
	_refresh_skills()
	_refresh_slot_labels()
	_refresh_cooldown_bars()

func _refresh_attrs() -> void:
	var attrs: Dictionary = LevelSystem.get_attrs(_peer_id)
	var pts: int          = LevelSystem.get_unspent_points(_peer_id)
	var cap: int          = LevelSystem.ATTR_CAP

	_attr_pts_label.text = "%d attr pt%s" % [pts, "s" if pts != 1 else ""]

	var hp_pts: int  = attrs.get("hp", 0)
	var spd_pts: int = attrs.get("speed", 0)
	var dmg_pts: int = attrs.get("damage", 0)

	_hp_bar.value    = hp_pts
	_hp_frac.text    = "%d/%d" % [hp_pts, cap]
	_hp_btn.disabled = (hp_pts >= cap) or (pts <= 0)

	_spd_bar.value    = spd_pts
	_spd_frac.text    = "%d/%d" % [spd_pts, cap]
	_spd_btn.disabled = (spd_pts >= cap) or (pts <= 0)

	_dmg_bar.value    = dmg_pts
	_dmg_frac.text    = "%d/%d" % [dmg_pts, cap]
	_dmg_btn.disabled = (dmg_pts >= cap) or (pts <= 0)

func _refresh_xp() -> void:
	var lvl: int    = LevelSystem.get_level(_peer_id)
	var xp: int     = LevelSystem.get_xp(_peer_id)
	var needed: int = LevelSystem.get_xp_needed(_peer_id)
	_level_label.text = "Level %d" % lvl
	_xp_bar.max_value = float(needed)
	_xp_bar.value     = float(xp)

func _refresh_skills() -> void:
	_sp_label.text = "Skill Points: %d" % SkillTree.get_skill_pts(_peer_id)
	for card in _cards:
		if card.has_method("refresh"):
			card.refresh()

func _refresh_slot_labels() -> void:
	var slots: Array = SkillTree.get_active_slots(_peer_id)
	_slot0_label.text = "Q: " + (slots[0] if slots[0] != "" else "(empty)")
	_slot1_label.text = "E: " + (slots[1] if slots[1] != "" else "(empty)")

func _refresh_cooldown_bars() -> void:
	var slots: Array = SkillTree.get_active_slots(_peer_id)
	for i in range(2):
		var cd_bar: ProgressBar = _slot0_cd if i == 0 else _slot1_cd
		var nid: String = slots[i]
		if nid == "":
			cd_bar.value = 0.0
			continue
		var max_cd: float = float(SkillDefs.get_def(nid).get("cooldown", 1.0))
		var rem: float    = SkillTree.get_cooldown(_peer_id, nid)
		cd_bar.max_value  = max_cd
		cd_bar.value      = rem

# ── Attribute spending ────────────────────────────────────────────────────────

func _on_hp_pressed() -> void:
	_spend_attr("hp")

func _on_spd_pressed() -> void:
	_spend_attr("speed")

func _on_dmg_pressed() -> void:
	_spend_attr("damage")

func _spend_attr(attr: String) -> void:
	if _is_mp and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		LevelSystem.request_spend_point.rpc_id(1, attr)
	else:
		LevelSystem.spend_point_local(_peer_id, attr)
	_refresh_attrs()

# ── Skill unlock / assign ─────────────────────────────────────────────────────

func _on_unlock_requested(node_id: String) -> void:
	if _is_mp and not multiplayer.is_server():
		SkillTree.request_unlock.rpc_id(1, node_id)
	else:
		SkillTree.unlock_node_local(_peer_id, node_id)

func _on_assign_active_requested(node_id: String, slot: int) -> void:
	if _is_mp and not multiplayer.is_server():
		SkillTree.request_assign_active.rpc_id(1, slot, node_id)
	else:
		SkillTree.assign_active_slot(_peer_id, slot, node_id)

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_attribute_spent(_peer_id_sig: int, _attr: String, _new_attrs: Dictionary) -> void:
	if _peer_id_sig != _peer_id:
		return
	_refresh_attrs()

func _on_xp_gained(peer_id_sig: int, _amount: int, new_xp: int, xp_needed: int) -> void:
	if peer_id_sig != _peer_id:
		return
	_xp_bar.max_value = float(xp_needed)
	_xp_bar.value     = float(new_xp)
	_level_label.text = "Level %d" % LevelSystem.get_level(_peer_id)

func _on_level_up(peer_id_sig: int, _new_level: int) -> void:
	if peer_id_sig != _peer_id:
		return
	_refresh_xp()
	_refresh_attrs()

func _on_sp_changed(peer_id_sig: int, pts: int) -> void:
	if peer_id_sig != _peer_id:
		return
	_sp_label.text = "Skill Points: %d" % pts

func _on_skill_unlocked(peer_id_sig: int, _node_id: String) -> void:
	if peer_id_sig != _peer_id:
		return
	for card in _cards:
		if card.has_method("refresh"):
			card.refresh()

func _on_slots_changed(peer_id_sig: int, _slots: Array) -> void:
	if peer_id_sig != _peer_id:
		return
	_refresh_slot_labels()
