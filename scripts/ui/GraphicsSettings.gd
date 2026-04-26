extends Node

signal settings_changed

const SAVE_PATH := "user://graphics.cfg"

# Fog settings — multiplier applied to per-time-of-day base densities
var fog_enabled: bool = true
var fog_density_multiplier: float = 1.0  # 0.0 = off, 3.0 = 3x base

# Per-time-of-day base densities (index matches GameSync.time_seed 0=sunrise/1=noon/2=dusk/3=night)
const FOG_DENSITY_BASE: Array = [0.001, 0.001, 0.003, 0.1]
const FOG_VOL_DENSITY_BASE: Array = [0.02, 0.02, 0.035, 0.015]

# DoF settings
var dof_enabled: bool = true
var dof_blur_amount: float = 0.07  # 0.0–0.2


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		return
	fog_enabled = cfg.get_value("fog", "enabled", true) as bool
	fog_density_multiplier = cfg.get_value("fog", "density_multiplier", 1.0) as float
	dof_enabled = cfg.get_value("dof", "enabled", true) as bool
	dof_blur_amount = cfg.get_value("dof", "blur_amount", 0.07) as float


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("fog", "enabled", fog_enabled)
	cfg.set_value("fog", "density_multiplier", fog_density_multiplier)
	cfg.set_value("dof", "enabled", dof_enabled)
	cfg.set_value("dof", "blur_amount", dof_blur_amount)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("GraphicsSettings: failed to save to %s (error %d)" % [SAVE_PATH, err])


func apply(fog_on: bool, density_mult: float, dof_on: bool, blur_amt: float) -> void:
	fog_enabled = fog_on
	fog_density_multiplier = density_mult
	dof_enabled = dof_on
	dof_blur_amount = blur_amt
	save_settings()
	settings_changed.emit()


func restore_defaults() -> void:
	apply(true, 1.0, true, 0.07)


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
