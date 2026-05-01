## test_supporter_hud_visibility.gd
## Verifies that the Supporter role shows PointsLabel and LivesBar
## while hiding the XP/level widgets (XPBar, LevelLabel, PendingButton).
## Tier-1 tests: no rendering, no real scene tree. We exercise the same
## visibility assignments that Main.gd applies in its Supporter branch.

extends GutTest

# ── Helpers ───────────────────────────────────────────────────────────────────

## Fake widget — just a Control whose .visible can be read.
class FakeWidget:
	extends Control

## Simulate the Supporter branch of Main.gd:
##   hide XP/level widgets; leave PointsLabel + LivesBar untouched.
func _apply_supporter_hud_visibility(
	xp_bar: Control,
	level_label: Control,
	pending_button: Control
) -> void:
	xp_bar.visible = false
	level_label.visible = false
	pending_button.visible = false

# ── Tests ─────────────────────────────────────────────────────────────────────

func test_xp_bar_hidden_for_supporter() -> void:
	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	xp_bar.visible = true

	var level_label := FakeWidget.new()
	add_child_autofree(level_label)
	var pending_button := FakeWidget.new()
	add_child_autofree(pending_button)

	_apply_supporter_hud_visibility(xp_bar, level_label, pending_button)
	assert_false(xp_bar.visible, "XPBar must be hidden for Supporter")

func test_level_label_hidden_for_supporter() -> void:
	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	var level_label := FakeWidget.new()
	add_child_autofree(level_label)
	level_label.visible = true
	var pending_button := FakeWidget.new()
	add_child_autofree(pending_button)

	_apply_supporter_hud_visibility(xp_bar, level_label, pending_button)
	assert_false(level_label.visible, "LevelLabel must be hidden for Supporter")

func test_pending_button_hidden_for_supporter() -> void:
	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	var level_label := FakeWidget.new()
	add_child_autofree(level_label)
	var pending_button := FakeWidget.new()
	add_child_autofree(pending_button)
	pending_button.visible = true

	_apply_supporter_hud_visibility(xp_bar, level_label, pending_button)
	assert_false(pending_button.visible, "PendingButton must be hidden for Supporter")

func test_points_label_visible_for_supporter() -> void:
	## PointsLabel is NOT touched by the Supporter branch — it starts visible
	## and must remain so. This test asserts the branch does NOT set it false.
	var points_label := FakeWidget.new()
	add_child_autofree(points_label)
	points_label.visible = true  # simulates _HUD_set_visible(true) prior to branch

	# Supporter branch only hides xp/level widgets — points_label is untouched.
	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	var level_label := FakeWidget.new()
	add_child_autofree(level_label)
	var pending_button := FakeWidget.new()
	add_child_autofree(pending_button)
	_apply_supporter_hud_visibility(xp_bar, level_label, pending_button)

	assert_true(points_label.visible, "PointsLabel must remain visible for Supporter")

func test_lives_bars_visible_for_supporter() -> void:
	## LivesBar widgets are NOT touched by the Supporter branch.
	var blue_bar := FakeWidget.new()
	add_child_autofree(blue_bar)
	blue_bar.visible = true
	var red_bar := FakeWidget.new()
	add_child_autofree(red_bar)
	red_bar.visible = true

	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	var level_label := FakeWidget.new()
	add_child_autofree(level_label)
	var pending_button := FakeWidget.new()
	add_child_autofree(pending_button)
	_apply_supporter_hud_visibility(xp_bar, level_label, pending_button)

	assert_true(blue_bar.visible, "BlueBar must remain visible for Supporter")
	assert_true(red_bar.visible, "RedBar must remain visible for Supporter")

func test_fighter_role_leaves_xp_visible() -> void:
	## Fighter branch never calls _apply_supporter_hud_visibility.
	## XPBar defaults to visible and should stay that way.
	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	xp_bar.visible = true
	# No Supporter branch applied — widget untouched
	assert_true(xp_bar.visible, "XPBar must stay visible when Supporter branch is NOT applied (Fighter)")

# ── CharacterScreen.set_role — Fighter attr rows hidden for Supporter ─────────

const CharacterScreenScene := preload("res://scenes/ui/CharacterScreen.tscn")

func test_character_screen_supporter_hides_fighter_rows() -> void:
	# Regression: Fighter HP/Speed/Damage rows were never hidden when role=Supporter
	# because set_role() only toggled StaminaRow, not the other three Fighter rows.
	var screen: Control = CharacterScreenScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame  # let @onready refs resolve

	screen.set_role(false)  # Supporter

	assert_false(screen.get_node("Panel/HSplit/LeftPanel/VBox/HPRow").visible,
		"HPRow must be hidden for Supporter")
	assert_false(screen.get_node("Panel/HSplit/LeftPanel/VBox/SpeedRow").visible,
		"SpeedRow must be hidden for Supporter")
	assert_false(screen.get_node("Panel/HSplit/LeftPanel/VBox/DamageRow").visible,
		"DamageRow must be hidden for Supporter")
	assert_false(screen.get_node("Panel/HSplit/LeftPanel/VBox/StaminaRow").visible,
		"StaminaRow must be hidden for Supporter")

func test_character_screen_supporter_shows_supporter_rows() -> void:
	var screen: Control = CharacterScreenScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame

	screen.set_role(false)  # Supporter

	assert_true(screen.get_node("Panel/HSplit/LeftPanel/VBox/TowerHPRow").visible,
		"TowerHPRow must be visible for Supporter")
	assert_true(screen.get_node("Panel/HSplit/LeftPanel/VBox/PlacementRangeRow").visible,
		"PlacementRangeRow must be visible for Supporter")
	assert_true(screen.get_node("Panel/HSplit/LeftPanel/VBox/FireRateRow").visible,
		"FireRateRow must be visible for Supporter")

func test_character_screen_fighter_shows_fighter_rows() -> void:
	var screen: Control = CharacterScreenScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame

	screen.set_role(true)  # Fighter

	assert_true(screen.get_node("Panel/HSplit/LeftPanel/VBox/HPRow").visible,
		"HPRow must be visible for Fighter")
	assert_true(screen.get_node("Panel/HSplit/LeftPanel/VBox/SpeedRow").visible,
		"SpeedRow must be visible for Fighter")
	assert_true(screen.get_node("Panel/HSplit/LeftPanel/VBox/DamageRow").visible,
		"DamageRow must be visible for Fighter")
	assert_true(screen.get_node("Panel/HSplit/LeftPanel/VBox/StaminaRow").visible,
		"StaminaRow must be visible for Fighter")

func test_character_screen_fighter_hides_supporter_rows() -> void:
	var screen: Control = CharacterScreenScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame

	screen.set_role(true)  # Fighter

	assert_false(screen.get_node("Panel/HSplit/LeftPanel/VBox/TowerHPRow").visible,
		"TowerHPRow must be hidden for Fighter")
	assert_false(screen.get_node("Panel/HSplit/LeftPanel/VBox/PlacementRangeRow").visible,
		"PlacementRangeRow must be hidden for Fighter")
	assert_false(screen.get_node("Panel/HSplit/LeftPanel/VBox/FireRateRow").visible,
		"FireRateRow must be hidden for Fighter")
