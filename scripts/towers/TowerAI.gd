## TowerAI.gd — Cannon tower (migrated to TowerBase).
## All shared plumbing (health, death, LOS, hit-flash, Area3D, multiplayer sync)
## is handled by TowerBase. This script only contains cannon-specific behaviour:
##   - Cannonball spawn logic (custom property assignment before add_child)
##   - Stats configured via exports set in Tower.tscn

extends TowerBase

const BulletScene := preload("res://scenes/projectiles/Cannonball.tscn")
const SND_FIRE := "res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_001.ogg"

var attack_damage: float = 50.0

# ── Cannonball fire — overrides TowerBase._do_attack() ───────────────────────

func _do_attack(target: Node3D) -> void:
	_fire_ballistic(BulletScene, attack_damage, "cannonball",
		SND_FIRE, 0.0, 0.9, 1.05, target,
		Callable(LobbyManager, "spawn_cannonball_visuals"))
