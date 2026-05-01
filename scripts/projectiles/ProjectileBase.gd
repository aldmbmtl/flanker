## ProjectileBase.gd
## Base class for all projectiles in the game.
##
## Handles: lifetime expiry, gravity, per-frame movement, raycast collision,
##          splash damage helper, and friendly-fire guard via CombatUtils.
##
## Overridable hooks:
##   _on_hit(pos, collider)  — called when raycast hits something. Default applies
##                             CombatUtils.should_damage + take_damage on the collider.
##   _after_move()           — called each frame after position is updated (no hit).
##                             Use for trail timers, orientation, acceleration, etc.
##   _on_expire()            — called just before queue_free() on lifetime expiry.
##                             Use to detach trails or spawn death VFX.
##
## Configuration (set vars before add_child so _ready() sees them):
##   damage, source, shooter_team, shooter_peer_id — combat identity
##   max_lifetime   — seconds until self-destruct (default 3.0)
##   gravity        — m/s² applied to _velocity.y each frame (default 18.0, set 0.0 to disable)
##   velocity       — set in _ready() or configure() on subclass before movement starts
##
## Splash helper:
##   _apply_splash(pos, radius, splash_dmg, splash_source)
##   — sphere overlap, CombatUtils.should_damage, take_damage on all nearby valid targets.
##   — pass the direct-hit collider as exclude_body to skip it.

class_name ProjectileBase
extends Node3D

# ── Combat identity ───────────────────────────────────────────────────────────
var damage: float        = 10.0
var source: String       = "unknown"
var shooter_team: int    = -1
var shooter_peer_id: int = -1   # -1 = minion / unknown; set for player-fired projectiles

## RID of the node that spawned this projectile (e.g. the firing tower).
## Set by the spawner before add_child. Excluded from the raycast so the
## projectile never immediately hits its own spawn point.
var spawner_rid: RID = RID()

# Whether this projectile can destroy trees when it hits a tree trunk.
# Default false - only specific projectiles (rockets, missiles) are allowed to.
var can_destroy_trees: bool = false

# ── Movement ──────────────────────────────────────────────────────────────────
var max_lifetime: float  = 3.0
var gravity: float       = 18.0   # set 0.0 for non-ballistic projectiles (rockets, missiles)
var velocity: Vector3    = Vector3.ZERO
var _age: float          = 0.0

# ── Core loop ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_age += delta
	if _age >= max_lifetime:
		_on_expire()
		queue_free()
		return

	if gravity != 0.0:
		velocity.y -= gravity * delta

	var prev_pos: Vector3 = global_position
	var new_pos: Vector3  = prev_pos + velocity * delta

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev_pos, new_pos)
	if spawner_rid.is_valid():
		query.exclude = [spawner_rid]
	var result: Dictionary = space.intersect_ray(query)

	if not result.is_empty():
		_on_hit(result.position, result.collider)
		queue_free()
		return

	global_position = new_pos
	_after_move()

# ── Overridable hooks ─────────────────────────────────────────────────────────

## Called when the raycast hits a collider. Default: apply damage via CombatUtils.
## Override for custom hit logic (ghost peers, splash, VFX, tree clearing, etc.).
func _on_hit(pos: Vector3, collider: Object) -> void:
	if CombatUtils.should_damage(collider, shooter_team):
		collider.take_damage(damage, source, shooter_team, shooter_peer_id)

## Called each frame after global_position is updated (no collision this frame).
## Override for: orientation toward velocity, trail timers, acceleration, light flicker.
func _after_move() -> void:
	pass

## Called just before queue_free() when max_lifetime expires.
## Override to detach trails or spawn timeout VFX.
func _on_expire() -> void:
	pass

# ── Ballistic arc helper ──────────────────────────────────────────────────────

## Compute velocity for a fixed-time ballistic arc to p_target.
## Call in _ready() after global_position is set. Requires gravity != 0.
func init_ballistic_arc(p_target: Vector3, flight_time: float) -> void:
	var start: Vector3 = global_position
	var dt: float = flight_time
	velocity.x = (p_target.x - start.x) / dt
	velocity.z = (p_target.z - start.z) / dt
	velocity.y = (p_target.y - start.y + 0.5 * gravity * dt * dt) / dt

# ── Ghost-hitbox helper ───────────────────────────────────────────────────────

## Route damage through GameSync when the collider is a ghost-peer hitbox.
## Returns true if the collider was a ghost hitbox (caller should skip further
## damage but may still run VFX). Server-authoritative.
func _handle_ghost_hit(collider: Object, dmg: float) -> bool:
	if not (collider is StaticBody3D and collider.has_meta("ghost_peer_id")):
		return false
	var target_peer: int = collider.get_meta("ghost_peer_id")
	if not GameSync.player_dead.get(target_peer, false):
		var ghost_team: int = GameSync.get_player_team(target_peer)
		var friendly: bool = (shooter_team >= 0 and ghost_team == shooter_team)
		if not friendly and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
			var new_hp: float = GameSync.damage_player(target_peer, dmg, shooter_team, shooter_peer_id)
			if multiplayer.has_multiplayer_peer():
				LobbyManager.apply_player_damage.rpc(target_peer, new_hp)
				if new_hp <= 0.0:
					LobbyManager.notify_player_died.rpc(target_peer)
	return true

# ── Tree clearing helper ──────────────────────────────────────────────────────

## Shared tree-clearing helper used by Bullet, Cannonball, and MortarShell.
## In multiplayer: server fans out sync_destroy_tree to all peers.
## In singleplayer: calls clear_trees_at directly on TreePlacer.
func _request_destroy_tree(pos: Vector3) -> void:
	# Only allow tree destruction if this projectile is allowed to destroy trees
	if not can_destroy_trees:
		return

	if multiplayer.is_server():
		LobbyManager.sync_destroy_tree.rpc(pos)
	else:
		LobbyManager.request_destroy_tree.rpc_id(1, pos)

# ── Splash helper ─────────────────────────────────────────────────────────────

## Sphere-overlap splash damage. Skips exclude_body (the direct-hit collider).
## Friendly-fire guarded via CombatUtils.should_damage.
static var _splash_shape: SphereShape3D = null
static var _splash_params: PhysicsShapeQueryParameters3D = null

func _apply_splash(pos: Vector3, radius: float, splash_dmg: float,
		splash_source: String, exclude_body: Object = null) -> void:
	if _splash_shape == null:
		_splash_shape = SphereShape3D.new()
		_splash_params = PhysicsShapeQueryParameters3D.new()
		_splash_params.shape = _splash_shape
		_splash_params.collision_mask = 0xFFFFFFFF
	_splash_shape.radius = radius
	_splash_params.transform = Transform3D(Basis.IDENTITY, pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var overlaps: Array = space.intersect_shape(_splash_params, 64)
	for overlap in overlaps:
		var body: Object = overlap.get("collider")
		if body == null or body == exclude_body:
			continue
		if CombatUtils.should_damage(body, shooter_team):
			body.take_damage(splash_dmg, splash_source, shooter_team, shooter_peer_id)
