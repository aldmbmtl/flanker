extends Node

# Persistent game settings (non-graphics).
# Stored at user://game_settings.cfg.

const SAVE_PATH := "user://game_settings.cfg"
const DEFAULT_LIVES := 20

var lives_per_team: int = DEFAULT_LIVES

func _ready() -> void:
	load_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "lives_per_team", lives_per_team)
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	lives_per_team = cfg.get_value("game", "lives_per_team", DEFAULT_LIVES)
