extends Control
# SkillTreeOverlay — full-screen skill tree UI.
# Toggled by skill_tree_toggle input action (T).
# Opened/closed by Main.gd which holds a reference and calls toggle().

var _peer_id: int = 1
var _is_mp: bool = false
var _cards: Array = []  # Array[SkillNodeCard]

const SkillNodeCardScene := preload("res://scenes/ui/SkillNodeCard.tscn")

# Portrait PNGs for each minion type branch (used for Supporter skill tree).
# Keys match the "branch" value in SkillDefs.
const BRANCH_PORTRAIT_BASE := "res://assets/kenney_blocky-characters/Previews/character-%s.png"

# For each Supporter branch: the tier-0/1/2 chars used as upgrade preview in tooltip.
const BRANCH_TIER_CHARS: Dictionary = {
	"Basic Minion":  ["j", "m", "r"],
	"Cannon Minion": ["d", "g", "h"],
	"Healer Minion": ["i", "n", "q"],
}

# Portrait char: the tier-0 (base) char for each branch (shown in the circle).
const BRANCH_PORTRAIT_CHAR: Dictionary = {
	"Basic Minion":  "j",
	"Cannon Minion": "d",
	"Healer Minion": "i",
}

@onready var _pts_label:     Label          = $Panel/VBox/Header/PtsLabel
@onready var _role_label:    Label          = $Panel/VBox/Header/RoleLabel
@onready var _branches_box:  HBoxContainer  = $Panel/VBox/BranchContainer
@onready var _slot0_label:   Label          = $Panel/VBox/ActiveSlotsRow/Slot0Box/SlotLabel
@onready var _slot1_label:   Label          = $Panel/VBox/ActiveSlotsRow/Slot1Box/SlotLabel
@onready var _slot0_cd:      ProgressBar    = $Panel/VBox/ActiveSlotsRow/Slot0Box/CooldownBar
@onready var _slot1_cd:      ProgressBar    = $Panel/VBox/ActiveSlotsRow/Slot1Box/CooldownBar

func setup(peer_id: int, is_mp: bool) -> void:
	_peer_id = peer_id
	_is_mp   = is_mp
	visible  = false
	call_deferred("_build_tree")
	SkillTree.skill_pts_changed.connect(_on_pts_changed)
	SkillTree.skill_unlocked.connect(_on_skill_unlocked)
	SkillTree.active_slots_changed.connect(_on_slots_changed)

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_all()

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_cooldown_bars()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_tree_toggle"):
		toggle()
		get_viewport().set_input_as_handled()

func _build_tree() -> void:
	# Clear old content
	for child in _branches_box.get_children():
		child.queue_free()
	_cards.clear()

	var role: String = SkillTree.get_role(_peer_id)
	_role_label.text = role.to_upper() + " SKILL TREE"

	var branches: Array = SkillDefs.get_branches_for_role(role)
	for branch in branches:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(200, 0)
		var branch_lbl := Label.new()
		branch_lbl.text = branch
		branch_lbl.add_theme_font_size_override("font_size", 13)
		col.add_child(branch_lbl)

		var nodes_in_branch: Array = SkillDefs.get_nodes_in_branch(role, branch)
		var is_first_in_branch: bool = true
		for nid in nodes_in_branch:
			var card: Control = SkillNodeCardScene.instantiate()

			# Attach portrait + tier tooltip to the first card in each Supporter branch.
			if role == "Supporter" and is_first_in_branch:
				_decorate_supporter_card(card, branch)

			col.add_child(card)
			card.setup(nid, _peer_id)
			card.unlock_requested.connect(_on_unlock_requested)
			card.assign_active_requested.connect(_on_assign_active_requested)
			_cards.append(card)
			is_first_in_branch = false
		_branches_box.add_child(col)

## Attach portrait texture and tier upgrade tooltip to the first card in a Supporter branch.
func _decorate_supporter_card(card: Control, branch: String) -> void:
	# Portrait image — load the tier-0 character preview PNG.
	if BRANCH_PORTRAIT_CHAR.has(branch):
		var char: String = BRANCH_PORTRAIT_CHAR[branch]
		var path: String = BRANCH_PORTRAIT_BASE % char
		if ResourceLoader.exists(path):
			card.set("portrait_texture", load(path))

	# Tier tooltip showing upgrade chain with character names.
	if BRANCH_TIER_CHARS.has(branch):
		var chars: Array = BRANCH_TIER_CHARS[branch]
		var lines: PackedStringArray = PackedStringArray()
		lines.append("Model upgrades:")
		lines.append("  Tier 0 (base): character-%s" % chars[0])
		lines.append("  Tier 1 (1 skill): character-%s" % chars[1])
		lines.append("  Tier 2 (2 skills): character-%s" % chars[2])
		card.set("tier_tooltip", "\n".join(lines))

func _refresh_all() -> void:
	_pts_label.text = "Skill Points: %d" % SkillTree.get_skill_pts(_peer_id)
	for card in _cards:
		if card.has_method("refresh"):
			card.refresh()
	_refresh_slot_labels()
	_refresh_cooldown_bars()

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
		var rem: float = SkillTree.get_cooldown(_peer_id, nid)
		cd_bar.max_value = max_cd
		cd_bar.value = rem

func _on_pts_changed(peer_id: int, pts: int) -> void:
	if peer_id != _peer_id:
		return
	_pts_label.text = "Skill Points: %d" % pts

func _on_skill_unlocked(peer_id: int, _node_id: String) -> void:
	if peer_id != _peer_id:
		return
	for card in _cards:
		if card.has_method("refresh"):
			card.refresh()

func _on_slots_changed(peer_id: int, _slots: Array) -> void:
	if peer_id != _peer_id:
		return
	_refresh_slot_labels()

func _on_unlock_requested(node_id: String) -> void:
	SkillTree.request_unlock(node_id)

func _on_assign_active_requested(node_id: String, slot: int) -> void:
	SkillTree.request_assign_active(slot, node_id)
