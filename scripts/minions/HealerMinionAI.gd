## HealerMinionAI — support minion.
##
## Marches along lane waypoints exactly like MinionAI (inherits MinionBase
## _physics_process unchanged). The only difference is the attack decision:
##
##   When the attack cooldown fires and a hurt friendly is within heal_radius →
##   pulse-heal instead of shooting.
##   Otherwise → fire a weak bullet at the normal enemy target.
##
## Stats (set in HealerMinion.tscn @exports):
##   max_health      = 60.0
##   attack_damage   = 3.0   (weak shot)
##   attack_cooldown = 2.5s
##   shoot_range     = 8.0m
##   detect_range    = 10.0m

class_name HealerMinionAI
extends MinionBase

## Base heal amount per pulse. Scaled by MinionSpawner per healer tier.
@export var heal_amount: float   = 10.0
## Heal radius in metres.
@export var heal_radius: float   = 8.0
## Kept for backwards-compat; not used as a timer — heal fires on attack cooldown.
@export var heal_interval: float = 3.0

# ─── Attack override ──────────────────────────────────────────────────────────

## Called by MinionBase._physics_process when the attack cooldown expires and
## a target is in range. Prefer healing a hurt ally; fall back to shooting.
func _fire_at(target: Node3D) -> void:
	if _try_heal_nearby():
		return
	# No hurt ally in range — fire weak bullet via base implementation.
	super._fire_at(target)

# ─── Heal helpers ─────────────────────────────────────────────────────────────

## Returns true and heals if any friendly in heal_radius is below max_health.
func _try_heal_nearby() -> bool:
	if not is_inside_tree():
		return false
	var radius_sq: float = heal_radius * heal_radius
	var best: Node = null
	var best_missing: float = 0.0

	for m in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(m) or m == self:
			continue
		var m_team: int = int(m.get("team") if m.get("team") != null else -1)
		if m_team != team:
			continue
		if m.get("_dead"):
			continue
		if global_position.distance_squared_to(m.global_position) > radius_sq:
			continue
		var mhp: float  = float(m.get("health")     if m.get("health")     != null else 0.0)
		var mmax: float = float(m.get("max_health")  if m.get("max_health") != null else 0.0)
		var missing: float = mmax - mhp
		if missing > 0.0 and missing > best_missing:
			best_missing = missing
			best = m

	for p in get_tree().get_nodes_in_group("players"):
		var p_team: int = int(p.get("player_team") if p.get("player_team") != null else -1)
		if p_team != team:
			continue
		if global_position.distance_squared_to(p.global_position) > radius_sq:
			continue
		var php: float  = float(p.get("health")    if p.get("health")    != null else 0.0)
		var pmax: float = float(p.get("max_health") if p.get("max_health") != null else 0.0)
		var missing: float = pmax - php
		if missing > 0.0 and missing > best_missing:
			best_missing = missing
			best = p

	if best == null:
		return false

	if best.has_method("heal"):
		# Minions can be healed directly (server-authoritative, is_puppet guard in MinionBase).
		best.heal(heal_amount)
	elif best.get("player_team") != null:
		# FPSController nodes on remote clients lack heal() on this peer.
		# Route via RPC so the target peer's local controller applies the HP.
		var target_peer: int = int(best.get("peer_id") if best.get("peer_id") != null else -1)
		if target_peer > 0:
			if multiplayer.has_multiplayer_peer():
				LobbyManager.heal_player_broadcast(target_peer, heal_amount)
			else:
				# Singleplayer: best IS the local FPSController — call directly.
				best.call("heal", heal_amount)
	return true

## Legacy explicit pulse — kept so existing test helpers that call _pulse_heal()
## directly still work.
func _pulse_heal() -> void:
	_try_heal_nearby()
