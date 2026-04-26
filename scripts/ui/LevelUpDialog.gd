extends Control

signal point_spent(attr: String)
signal closed  # emitted when dismissed without spending (Escape)

var _peer_id: int  = 1
var _is_mp: bool   = false

@onready var pts_label:   Label       = $Panel/VBox/TitleRow/PtsLabel

@onready var hp_bar:      ProgressBar = $Panel/VBox/HPRow/HPBar
@onready var hp_frac:     Label       = $Panel/VBox/HPRow/HPFrac
@onready var hp_btn:      Button      = $Panel/VBox/HPRow/HPBtn

@onready var speed_bar:   ProgressBar = $Panel/VBox/SpeedRow/SpeedBar
@onready var speed_frac:  Label       = $Panel/VBox/SpeedRow/SpeedFrac
@onready var speed_btn:   Button      = $Panel/VBox/SpeedRow/SpeedBtn

@onready var damage_bar:  ProgressBar = $Panel/VBox/DamageRow/DamageBar
@onready var damage_frac: Label       = $Panel/VBox/DamageRow/DamageFrac
@onready var damage_btn:  Button      = $Panel/VBox/DamageRow/DamageBtn

func _ready() -> void:
	hp_btn.pressed.connect(_on_hp_pressed)
	speed_btn.pressed.connect(_on_speed_pressed)
	damage_btn.pressed.connect(_on_damage_pressed)
	visible = false

func setup(peer_id: int, is_mp: bool) -> void:
	_peer_id = peer_id
	_is_mp   = is_mp
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	var attrs: Dictionary = LevelSystem.get_attrs(_peer_id)
	var pts: int          = LevelSystem.get_unspent_points(_peer_id)
	var cap: int          = LevelSystem.ATTR_CAP

	var hp_pts: int    = attrs.get("hp", 0)
	var spd_pts: int   = attrs.get("speed", 0)
	var dmg_pts: int   = attrs.get("damage", 0)

	pts_label.text = "%d pt%s" % [pts, "s" if pts != 1 else ""]

	hp_bar.value    = hp_pts
	hp_frac.text    = "%d/%d" % [hp_pts, cap]
	hp_btn.disabled = (hp_pts >= cap) or (pts <= 0)

	speed_bar.value    = spd_pts
	speed_frac.text    = "%d/%d" % [spd_pts, cap]
	speed_btn.disabled = (spd_pts >= cap) or (pts <= 0)

	damage_bar.value    = dmg_pts
	damage_frac.text    = "%d/%d" % [dmg_pts, cap]
	damage_btn.disabled = (dmg_pts >= cap) or (pts <= 0)

	# Auto-close once all points are spent
	if pts <= 0:
		visible = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
			visible = false
			closed.emit()
			get_viewport().set_input_as_handled()

func _on_hp_pressed() -> void:
	_spend("hp")

func _on_speed_pressed() -> void:
	_spend("speed")

func _on_damage_pressed() -> void:
	_spend("damage")

func _spend(attr: String) -> void:
	if _is_mp and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		LevelSystem.request_spend_point.rpc_id(1, attr)
	else:
		LevelSystem.spend_point_local(_peer_id, attr)
	point_spent.emit(attr)
	_refresh()
