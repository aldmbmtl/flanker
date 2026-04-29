extends Node
# Script attached to each SkillNodeCard instance.
# Populated by SkillTreeOverlay via setup().

signal unlock_requested(node_id: String)
signal assign_active_requested(node_id: String)

var _node_id: String = ""
var _peer_id: int = 1

@onready var _title_label:  Label       = $Panel/VBox/TitleLabel
@onready var _desc_label:   Label       = $Panel/VBox/DescLabel
@onready var _cost_label:   Label       = $Panel/VBox/CostLabel
@onready var _unlock_btn:   Button      = $Panel/VBox/UnlockBtn
@onready var _assign_btn:   Button      = $Panel/VBox/AssignBtn
@onready var _lock_overlay: ColorRect   = $LockOverlay
@onready var _panel:        PanelContainer = $Panel

func setup(node_id: String, peer_id: int) -> void:
	_node_id = node_id
	_peer_id = peer_id
	var def: Dictionary = SkillDefs.get_def(node_id)
	_title_label.text = node_id.replace("_", " ").capitalize()
	_desc_label.text  = def.get("description", "")
	_cost_label.text  = "%d SP" % int(def.get("cost", 1))
	var is_active: bool = def.get("type", "") == "active"
	_assign_btn.visible = is_active
	_unlock_btn.pressed.connect(_on_unlock_pressed)
	_assign_btn.pressed.connect(_on_assign_pressed)
	refresh()

func refresh() -> void:
	if _node_id == "":
		return
	var unlocked: bool = SkillTree.is_unlocked(_peer_id, _node_id)
	var available: bool = SkillTree.can_unlock(_peer_id, _node_id)
	_lock_overlay.visible = not unlocked and not available
	_unlock_btn.visible   = not unlocked
	_unlock_btn.disabled  = not available
	_assign_btn.disabled  = not unlocked
	# Visual state
	if unlocked:
		_panel.modulate = Color(0.6, 1.0, 0.6, 1.0)
	elif available:
		_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		_panel.modulate = Color(0.5, 0.5, 0.5, 1.0)

func _on_unlock_pressed() -> void:
	unlock_requested.emit(_node_id)

func _on_assign_pressed() -> void:
	assign_active_requested.emit(_node_id)
