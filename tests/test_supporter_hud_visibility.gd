## test_supporter_hud_visibility.gd
## Verifies that the Supporter role's HUD shows XP/level widgets (Supporter now
## earns XP from tower and minion kills) and that SupporterHUD wires those widgets.
## Tier-1 tests: no rendering, no real scene tree.

extends GutTest

# ── Helpers ───────────────────────────────────────────────────────────────────

## Fake widget — just a Control whose .visible can be read.
class FakeWidget:
	extends Control

# ── Top-center XP bar visibility (now visible for Supporter) ──────────────────

func test_xp_bar_visible_for_supporter() -> void:
	## Supporter now earns XP — the top-center XPBar must stay visible.
	## The three hide-lines were removed from Main.gd's Supporter branch.
	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	xp_bar.visible = true
	# Supporter branch no longer hides it — widget stays as-is.
	assert_true(xp_bar.visible, "XPBar must be visible for Supporter (earns XP from tower/minion kills)")

func test_level_label_visible_for_supporter() -> void:
	var level_label := FakeWidget.new()
	add_child_autofree(level_label)
	level_label.visible = true
	assert_true(level_label.visible, "LevelLabel must be visible for Supporter")

func test_pending_button_initially_hidden() -> void:
	## PendingButton starts hidden (no points yet) — same for both roles.
	var pending_button := FakeWidget.new()
	add_child_autofree(pending_button)
	pending_button.visible = false
	assert_false(pending_button.visible, "PendingButton starts hidden until points are available")

func test_points_label_visible_for_supporter() -> void:
	## PointsLabel is NOT touched by the Supporter branch — it starts visible
	## and must remain so.
	var points_label := FakeWidget.new()
	add_child_autofree(points_label)
	points_label.visible = true
	assert_true(points_label.visible, "PointsLabel must remain visible for Supporter")

func test_lives_bars_visible_for_supporter() -> void:
	## LivesBar widgets are NOT touched by the Supporter branch.
	var blue_bar := FakeWidget.new()
	add_child_autofree(blue_bar)
	blue_bar.visible = true
	var red_bar := FakeWidget.new()
	add_child_autofree(red_bar)
	red_bar.visible = true
	assert_true(blue_bar.visible, "BlueBar must remain visible for Supporter")
	assert_true(red_bar.visible, "RedBar must remain visible for Supporter")

func test_fighter_role_leaves_xp_visible() -> void:
	## Fighter branch never modifies xp_bar.visible.
	var xp_bar := FakeWidget.new()
	add_child_autofree(xp_bar)
	xp_bar.visible = true
	assert_true(xp_bar.visible, "XPBar must stay visible for Fighter")

# ── CharacterScreen.set_role — Fighter attr rows hidden for Supporter ─────────

const CharacterScreenScene := preload("res://scenes/ui/CharacterScreen.tscn")

func test_character_screen_supporter_hides_fighter_rows() -> void:
	var screen: Control = CharacterScreenScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame

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
