## BallisticTower.gd — shared subclass for ballistic (arc-trajectory) towers.
## Covers Cannon (Tower.tscn) and Mortar (MortarTower.tscn).
## All per-tower stats (damage, sound, projectile scene, pitch range) are set
## via @export vars in the .tscn — no code duplication needed.

class_name TowerAI  # Cannon tower class_name kept for test compatibility
extends TowerBase

@export var projectile_scene_path: String = "res://scenes/projectiles/Cannonball.tscn"
@export var fire_sound_path: String = "res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_001.ogg"
@export var attack_damage: float = 50.0
@export var pitch_scale_min: float = 0.9
@export var pitch_scale_max: float = 1.05
@export var source_tag: String = ""

func _do_attack(target: Node3D) -> void:
	var scene: PackedScene = load(projectile_scene_path)
	if scene == null:
		return
	_fire_ballistic(scene, attack_damage, source_tag,
		fire_sound_path, 0.0, pitch_scale_min, pitch_scale_max, target)
