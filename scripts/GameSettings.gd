extends Node

# Persistent game settings (non-graphics).
# Stored at user://game_settings.cfg.

const SAVE_PATH := "user://game_settings.cfg"
const DEFAULT_LIVES := 20
const DEFAULT_PLAYER_NAME := ""

var lives_per_team: int = DEFAULT_LIVES
var player_name: String = DEFAULT_PLAYER_NAME

func _ready() -> void:
	load_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "lives_per_team", lives_per_team)
	cfg.set_value("game", "player_name", player_name)
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	lives_per_team = cfg.get_value("game", "lives_per_team", DEFAULT_LIVES)
	player_name = cfg.get_value("game", "player_name", DEFAULT_PLAYER_NAME)
