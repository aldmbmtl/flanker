## MortarTowerAI.gd — Mortar tower (TowerBase subclass).
## Long-range ballistic shell, high damage, large splash.
## Stats configured via @export in MortarTower.tscn.

extends TowerBase

const ShellScene := preload("res://scenes/projectiles/MortarShell.tscn")

var attack_damage: float = 80.0

# ── Mortar fire — overrides TowerBase._do_attack() ───────────────────────────

func _do_attack(target: Node3D) -> void:
	var spawn_pos: Vector3 = get_fire_position()
	var aim_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)

	var shell: Node3D = ShellScene.instantiate()
	shell.damage = attack_damage
	shell.shooter_team = team
	shell.target_pos = aim_pos
	shell.position = spawn_pos
	get_tree().root.get_child(0).add_child(shell)
