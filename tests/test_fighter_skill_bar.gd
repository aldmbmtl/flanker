extends GutTest
# test_fighter_skill_bar.gd — unit tests for FighterSkillBar HUD node.
# Tier 1 (OfflineMultiplayerPeer): no network, multiplayer.is_server() == true.
#
# Strategy: instantiate the bar via set_script, call setup(), then assert on
# label text, visibility, modulate, and border colour state through the
# public _slots array and signal emissions.

const FighterSkillBarScript := preload("res://scripts/ui/FighterSkillBar.gd")

const PEER_ID := 42

var _bar: Node

func before_each() -> void:
	SkillTree.clear_all()
	SkillTree.register_peer(PEER_ID, "Fighter")
	_bar = CanvasLayer.new()
	_bar.set_script(FighterSkillBarScript)
	_bar.name = "FighterSkillBar"
	add_child_autofree(_bar)
	_bar.setup(PEER_ID)

func after_each() -> void:
	SkillTree.clear_all()

# ── Slot count ────────────────────────────────────────────────────────────────

func test_bar_creates_two_slots() -> void:
	assert_eq(_bar._slots.size(), 2)

# ── Empty slot appearance ─────────────────────────────────────────────────────

func test_empty_slot_shows_dash_placeholder() -> void:
	# Slot 0 has f_dash by default; slot 1 is empty
	assert_eq(_bar._slots[0].name_lbl.text, "Dash")
	assert_eq(_bar._slots[1].name_lbl.text, "—")

func test_empty_slot_cooldown_label_hidden() -> void:
	assert_false(_bar._slots[0].cool_lbl.visible)
	assert_false(_bar._slots[1].cool_lbl.visible)

func test_empty_slot_node_id_is_empty_string() -> void:
	# Slot 0 has f_dash by default; slot 1 is empty
	assert_eq(_bar._slots[0].node_id, "f_dash")
	assert_eq(_bar._slots[1].node_id, "")

# ── Assigning a skill updates label ──────────────────────────────────────────

func test_assign_skill_updates_name_label() -> void:
	# Unlock and assign f_dash to slot 0
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_dash")
	# active_slots_changed fires → _refresh_slot(0) runs
	assert_eq(_bar._slots[0].name_lbl.text, "Dash")

func test_assign_skill_slot1_updates_label() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 1, "f_dash")
	assert_eq(_bar._slots[1].name_lbl.text, "Dash")

func test_assign_skill_does_not_change_other_slot() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_dash")
	assert_eq(_bar._slots[1].name_lbl.text, "—")

func test_assign_skill_stores_node_id() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_dash")
	assert_eq(_bar._slots[0].node_id, "f_dash")

# ── Cooldown display ──────────────────────────────────────────────────────────

func test_cooldown_label_hidden_when_skill_ready() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_dash")
	# No use yet — cooldown is 0
	assert_false(_bar._slots[0].cool_lbl.visible)

func test_cooldown_label_visible_after_use() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_dash")
	# Use the skill — active_used fires → _on_active_used sets visible
	SkillTree.use_active_local(PEER_ID, 0)
	assert_true(_bar._slots[0].cool_lbl.visible)

func test_active_used_records_total_cd() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_dash")
	SkillTree.use_active_local(PEER_ID, 0)
	# f_dash has cooldown 6.0
	assert_almost_eq(_bar._slots[0].total_cd, 6.0, 0.01)

func test_active_used_sets_grey_border() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_dash")
	SkillTree.use_active_local(PEER_ID, 0)
	var border: Color = _bar._slots[0].style_box.border_color
	# Border should be grey (on-cooldown), not orange (ready)
	assert_almost_eq(border.r, 0.35, 0.05)

# ── Death / respawn visibility ────────────────────────────────────────────────

func test_bar_fades_out_on_death() -> void:
	GameSync.player_died.emit(PEER_ID)
	await wait_seconds(0.5)
	assert_almost_eq(_bar._root.modulate.a, 0.0, 0.05)

func _on_player_respawned(peer_id: int, _spawn_pos: Vector3) -> void:
	pass  # not used — signal arity fix only

func test_bar_fades_in_on_respawn() -> void:
	_bar._root.modulate.a = 0.0
	GameSync.player_respawned.emit(PEER_ID, Vector3.ZERO)
	await wait_seconds(0.5)
	assert_almost_eq(_bar._root.modulate.a, 1.0, 0.05)

func test_death_ignores_other_peer() -> void:
	GameSync.player_died.emit(PEER_ID + 1)
	await wait_seconds(0.1)
	assert_almost_eq(_bar._root.modulate.a, 1.0, 0.01)

# ── Name label uses SkillDefs 'name' field ────────────────────────────────────

func test_name_label_uses_skilldefs_name_field() -> void:
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_field_medic")
	SkillTree.assign_active_slot(PEER_ID, 0, "f_field_medic")
	assert_eq(_bar._slots[0].name_lbl.text, "Field Medic")

func test_name_label_uses_rapid_fire_name() -> void:
	# Unlock path: f_dash (1 SP) then f_rapid_fire (2 SP)
	SkillTree._on_level_up(PEER_ID, 2)
	SkillTree.unlock_node_local(PEER_ID, "f_dash")
	SkillTree._on_level_up(PEER_ID, 3)
	SkillTree._on_level_up(PEER_ID, 4)
	SkillTree.unlock_node_local(PEER_ID, "f_rapid_fire")
	SkillTree.assign_active_slot(PEER_ID, 1, "f_rapid_fire")
	assert_eq(_bar._slots[1].name_lbl.text, "Rapid Fire")
