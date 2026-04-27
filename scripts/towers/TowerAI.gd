## TowerAI.gd — Cannon tower (migrated to TowerBase).
## All shared plumbing (health, death, LOS, hit-flash, Area3D, multiplayer sync)
## is handled by TowerBase. This script only contains cannon-specific behaviour:
##   - Cannonball spawn logic (custom property assignment before add_child)
##   - Stats configured via exports set in Tower.tscn

extends TowerBase

const BulletScene := preload("res://scenes/projectiles/Cannonball.tscn")

var attack_damage: float = 50.0

# ── Cannonball fire — overrides TowerBase._do_attack() ───────────────────────

func _do_attack(target: Node3D) -> void:
	var spawn_pos: Vector3 = get_fire_position()
	var aim_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)

	var ball: Node3D = BulletScene.instantiate()
	ball.damage = attack_damage
	ball.source = "cannonball"
	ball.shooter_team = team
	ball.target_pos = aim_pos
	# Position set before add_child so Cannonball._ready() computes arc from correct origin
	ball.position = spawn_pos
	get_tree().root.get_child(0).add_child(ball)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		LobbyManager.spawn_cannonball_visuals.rpc(spawn_pos, aim_pos, attack_damage, team)
