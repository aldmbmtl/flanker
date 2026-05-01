## CannonMinionAI — high-damage minion that prioritises enemy towers.
##
## Stats (set in CannonMinion.tscn @exports):
##   max_health    = 40.0   (glass cannon)
##   attack_damage = 40.0   (heavy shot)
##   attack_cooldown = 3.0s (slow fire)
##   shoot_range   = 25.0m  (long range)
##   detect_range  = 28.0m  (must exceed shoot_range)
##
## Behaviour:
##   _find_target() — towers first; falls back to players/minions.
##   _fire_at()     — fires a Cannonball-style projectile (arc, mild splash).
##
## Model chars (blue / red) driven by MinionSpawner based on cannon_tier passive:
##   tier 0 → d, tier 1 → d, tier 2 → g, tier 3 → h

class_name CannonMinionAI
extends MinionBase

# Cannon projectile — uses same Cannonball scene as cannon tower.
const CannonballScene := preload("res://scenes/projectiles/Cannonball.tscn")

# ─── Targeting: tower-priority ────────────────────────────────────────────────

func _find_target() -> Node3D:
	# Phase 1: look for the nearest *enemy tower* within shoot_range.
	var best_tower: Node3D = null
	var best_tower_dist: float = shoot_range

	for t in _cached_towers:
		if not is_instance_valid(t) or t.team == team:
			continue
		var d: float = global_position.distance_to(t.global_position)
		if d < best_tower_dist:
			if _same_team_attackers_on(t) < 3:  # allow extra attackers on towers
				best_tower_dist = d
				best_tower = t

	if best_tower != null:
		return best_tower

	# Phase 2: fall back to standard MinionBase targeting (minions → players → towers).
	return super._find_target()

# ─── Attack: arc cannonball ───────────────────────────────────────────────────

func _fire_at(target: Node3D) -> void:
	if not is_inside_tree() or not is_instance_valid(target) or not target.is_inside_tree():
		return

	var fire_pos: Vector3 = global_position + Vector3(0.0, 1.2, 0.0)
	var target_pos: Vector3 = target.global_position

	var ball: Node3D = CannonballScene.instantiate()
	ball.damage        = attack_damage
	ball.source        = "cannon_minion"
	ball.shooter_team  = team
	ball.target_pos    = target_pos
	ball.position      = fire_pos   # set BEFORE add_child so _ready() / init_ballistic_arc sees correct origin
	VfxUtils.get_scene_root(self).add_child(ball)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		LobbyManager.spawn_bullet_visuals.rpc(fire_pos, (target_pos - fire_pos).normalized(), attack_damage, team)

	shoot_audio.play()
