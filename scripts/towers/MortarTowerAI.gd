## MortarTowerAI.gd — Mortar tower (TowerBase subclass).
## Long-range ballistic shell, high damage, large splash.
## Stats configured via @export in MortarTower.tscn.

extends TowerBase

const ShellScene := preload("res://scenes/projectiles/MortarShell.tscn")
const SND_FIRE := "res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_004.ogg"

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
	SoundManager.play_3d(SND_FIRE, get_fire_position(), 1.0, randf_range(0.88, 1.0))
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		LobbyManager.spawn_mortar_visuals.rpc(spawn_pos, aim_pos, attack_damage, team)
