## MortarTowerAI.gd — Mortar tower (TowerBase subclass).
## Long-range ballistic shell, high damage, large splash.
## Stats configured via @export in MortarTower.tscn.

extends TowerBase

const ShellScene := preload("res://scenes/projectiles/MortarShell.tscn")
const SND_FIRE := "res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_004.ogg"

var attack_damage: float = 80.0

# ── Mortar fire — overrides TowerBase._do_attack() ───────────────────────────

func _do_attack(target: Node3D) -> void:
	_fire_ballistic(ShellScene, attack_damage, "",
		SND_FIRE, 1.0, 0.88, 1.0, target,
		Callable(LobbyManager, "spawn_mortar_visuals"))
