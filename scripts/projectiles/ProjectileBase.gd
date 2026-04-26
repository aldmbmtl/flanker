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

# ── Splash helper ─────────────────────────────────────────────────────────────

## Sphere-overlap splash damage. Skips exclude_body (the direct-hit collider).
## Friendly-fire guarded via CombatUtils.should_damage.
func _apply_splash(pos: Vector3, radius: float, splash_dmg: float,
		splash_source: String, exclude_body: Object = null) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, pos)
	params.collision_mask = 0xFFFFFFFF
	var overlaps: Array = space.intersect_shape(params, 64)
	for overlap in overlaps:
		var body: Object = overlap.get("collider")
		if body == null or body == exclude_body:
			continue
		if CombatUtils.should_damage(body, shooter_team):
			body.take_damage(splash_dmg, splash_source, shooter_team, shooter_peer_id)
