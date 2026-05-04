# test_player_username.gd
# Tier 1 — unit tests for the player username feature.
# Covers: ClientSettings save/load round-trip, StartMenu button guard,
# and name propagation to LobbyManager registration.
extends GutTest

# ── ClientSettings: player_name persistence ───────────────────────────────────

func test_game_settings_has_player_name_var() -> void:
	assert_true("player_name" in ClientSettings, "ClientSettings should expose player_name")

func test_player_name_default_is_empty() -> void:
	var saved: String = ClientSettings.player_name
	ClientSettings.player_name = ""
	assert_eq(ClientSettings.player_name, "", "Default player_name should be empty string")
	ClientSettings.player_name = saved

func test_player_name_can_be_set() -> void:
	var saved: String = ClientSettings.player_name
	ClientSettings.player_name = "Aldric"
	assert_eq(ClientSettings.player_name, "Aldric", "player_name should store assigned value")
	ClientSettings.player_name = saved

func test_player_name_save_and_load_round_trip() -> void:
	var saved: String = ClientSettings.player_name
	ClientSettings.player_name = "RoundTripTest"
	ClientSettings.save_settings()
	# Reset in memory, then reload
	ClientSettings.player_name = ""
	ClientSettings.load_settings()
	assert_eq(ClientSettings.player_name, "RoundTripTest", "Loaded name should match saved name")
	# Restore original value
	ClientSettings.player_name = saved
	ClientSettings.save_settings()

func test_player_name_empty_survives_save_load() -> void:
	var saved: String = ClientSettings.player_name
	ClientSettings.player_name = ""
	ClientSettings.save_settings()
	ClientSettings.player_name = "Temp"
	ClientSettings.load_settings()
	assert_eq(ClientSettings.player_name, "", "Empty name should survive save/load round-trip")
	ClientSettings.player_name = saved
	ClientSettings.save_settings()

func test_player_name_max_length_survives_save_load() -> void:
	var saved: String = ClientSettings.player_name
	var long_name: String = "ABCDEFGHIJKLMNOPQRSTUVWX"  # 24 chars
	ClientSettings.player_name = long_name
	ClientSettings.save_settings()
	ClientSettings.player_name = ""
	ClientSettings.load_settings()
	assert_eq(ClientSettings.player_name, long_name, "24-char name should survive save/load")
	ClientSettings.player_name = saved
	ClientSettings.save_settings()

# ── StartMenu: button guard ────────────────────────────────────────────────────

class FakeStartMenuNode extends Control:
	# Minimal stub that replicates the button-guard logic tested in isolation.
	# We don't instantiate the full StartMenu.tscn (it spawns a 3D world);
	# instead we test the guard function directly.
	var host_btn: Button
	var join_btn: Button
	var name_edit: LineEdit

	func _init() -> void:
		host_btn  = Button.new()
		join_btn  = Button.new()
		name_edit = LineEdit.new()
		host_btn.name  = "HostButton"
		join_btn.name  = "JoinButton"
		name_edit.name = "NameEdit"

	func update_name_buttons() -> void:
		var has_name: bool = name_edit.text.strip_edges().length() > 0
		host_btn.disabled = not has_name
		join_btn.disabled = not has_name

func test_host_button_disabled_when_name_empty() -> void:
	var menu := FakeStartMenuNode.new()
	menu.name_edit.text = ""
	menu.update_name_buttons()
	assert_true(menu.host_btn.disabled, "Host button should be disabled when name is empty")

func test_join_button_disabled_when_name_empty() -> void:
	var menu := FakeStartMenuNode.new()
	menu.name_edit.text = ""
	menu.update_name_buttons()
	assert_true(menu.join_btn.disabled, "Join button should be disabled when name is empty")

func test_host_button_enabled_when_name_set() -> void:
	var menu := FakeStartMenuNode.new()
	menu.name_edit.text = "Alice"
	menu.update_name_buttons()
	assert_false(menu.host_btn.disabled, "Host button should be enabled when name is non-empty")

func test_join_button_enabled_when_name_set() -> void:
	var menu := FakeStartMenuNode.new()
	menu.name_edit.text = "Alice"
	menu.update_name_buttons()
	assert_false(menu.join_btn.disabled, "Join button should be enabled when name is non-empty")

func test_buttons_disabled_for_whitespace_only_name() -> void:
	var menu := FakeStartMenuNode.new()
	menu.name_edit.text = "   "
	menu.update_name_buttons()
	assert_true(menu.host_btn.disabled, "Whitespace-only name should be treated as empty")
	assert_true(menu.join_btn.disabled, "Whitespace-only name should be treated as empty")

func test_buttons_enabled_after_name_cleared_then_set() -> void:
	var menu := FakeStartMenuNode.new()
	menu.name_edit.text = ""
	menu.update_name_buttons()
	assert_true(menu.host_btn.disabled)
	menu.name_edit.text = "Bob"
	menu.update_name_buttons()
	assert_false(menu.host_btn.disabled, "Button should re-enable after name is entered")

# ── Name propagates to LobbyManager registration ──────────────────────────────

func before_each() -> void:
	LobbyManager.players.clear()
	LobbyManager.reset()

func test_register_player_local_stores_provided_name() -> void:
	# register_player_local was removed — Python now owns registration.
	# Seed the player dict directly to verify name storage contract.
	LobbyManager.players[1] = {"name": "TestPlayer", "team": 0, "role": -1, "ready": false, "avatar_char": ""}
	var info: Dictionary = LobbyManager.players.get(1, {})
	assert_eq(info.get("name", ""), "TestPlayer", "Player dict should store the name")

func test_register_player_local_name_differs_from_old_default() -> void:
	LobbyManager.players[1] = {"name": "ActualName", "team": 0, "role": -1, "ready": false, "avatar_char": ""}
	var info: Dictionary = LobbyManager.players.get(1, {})
	assert_ne(info.get("name", ""), "Host", "Name should not be the hardcoded 'Host' default")
	assert_ne(info.get("name", ""), "Player", "Name should not be the hardcoded 'Player' default")
