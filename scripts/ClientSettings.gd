extends Node

# Merged client-side settings autoload.
# Replaces GameSettings (user://game_settings.cfg) and
# GraphicsSettings (user://graphics.cfg).
# Saved to user://client_settings.cfg — old files are abandoned.

signal settings_changed

const SAVE_PATH := "user://client_settings.cfg"

# ── Game settings ─────────────────────────────────────────────────────────────

const DEFAULT_LIVES       := 20
const DEFAULT_PLAYER_NAME := ""

var lives_per_team: int = DEFAULT_LIVES
var player_name: String = DEFAULT_PLAYER_NAME

# ── Fog settings ─────────────────────────────────────────────────────────────

# Per-time-of-day base densities (index matches GameSync.time_seed
# 0=sunrise / 1=noon / 2=dusk / 3=night)
const FOG_DENSITY_BASE:     Array = [0.001, 0.001, 0.003, 0.1]
const FOG_VOL_DENSITY_BASE: Array = [0.02,  0.02,  0.035, 0.015]

var fog_enabled: bool            = true
var fog_density_multiplier: float = 1.0  # 0.0 = off, 3.0 = 3× base

# ── DoF settings ──────────────────────────────────────────────────────────────

var dof_enabled: bool      = true
var dof_blur_amount: float = 0.07  # 0.0–0.2

# ── Shadow settings ───────────────────────────────────────────────────────────

# shadow_quality:       0 = Off, 1 = Low (ORTHOGONAL 60 m), 2 = High (PSSM4 100 m)
# tree_shadow_distance: 0 = Off, 1 = Close (near band only), 2 = Far (both bands)
var shadow_quality:       int = 1
var tree_shadow_distance: int = 1


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	lives_per_team         = cfg.get_value("game",   "lives_per_team",       DEFAULT_LIVES)
	player_name            = cfg.get_value("game",   "player_name",          DEFAULT_PLAYER_NAME)
	fog_enabled            = cfg.get_value("fog",    "enabled",              true)  as bool
	fog_density_multiplier = cfg.get_value("fog",    "density_multiplier",   1.0)   as float
	dof_enabled            = cfg.get_value("dof",    "enabled",              true)  as bool
	dof_blur_amount        = cfg.get_value("dof",    "blur_amount",          0.07)  as float
	shadow_quality         = cfg.get_value("shadow", "quality",              1)     as int
	tree_shadow_distance   = cfg.get_value("shadow", "tree_shadow_distance", 1)     as int


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game",   "lives_per_team",       lives_per_team)
	cfg.set_value("game",   "player_name",          player_name)
	cfg.set_value("fog",    "enabled",              fog_enabled)
	cfg.set_value("fog",    "density_multiplier",   fog_density_multiplier)
	cfg.set_value("dof",    "enabled",              dof_enabled)
	cfg.set_value("dof",    "blur_amount",          dof_blur_amount)
	cfg.set_value("shadow", "quality",              shadow_quality)
	cfg.set_value("shadow", "tree_shadow_distance", tree_shadow_distance)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("ClientSettings: failed to save to %s (error %d)" % [SAVE_PATH, err])


func apply(fog_on: bool, density_mult: float, dof_on: bool, blur_amt: float,
		shad_quality: int = shadow_quality,
		tree_shad_dist: int = tree_shadow_distance) -> void:
	fog_enabled            = fog_on
	fog_density_multiplier = density_mult
	dof_enabled            = dof_on
	dof_blur_amount        = blur_amt
	shadow_quality         = shad_quality
	tree_shadow_distance   = tree_shad_dist
	save_settings()
	settings_changed.emit()


func restore_defaults() -> void:
	apply(true, 1.0, true, 0.07, 1, 1)


func get_fog_density(time_seed: int) -> float:
	var idx: int = clamp(time_seed, 0, 3)
	if not fog_enabled:
		return 0.0
	return FOG_DENSITY_BASE[idx] * fog_density_multiplier


func get_vol_fog_density(time_seed: int) -> float:
	var idx: int = clamp(time_seed, 0, 3)
	if not fog_enabled:
		return 0.0
	return FOG_VOL_DENSITY_BASE[idx] * fog_density_multiplier
