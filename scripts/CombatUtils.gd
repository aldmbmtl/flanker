## Shared static helpers for projectile damage and team tinting.
## No state — use via preload or direct autoload path.
class_name CombatUtils

static func should_damage(hit: Object, shooter_team: int) -> bool:
	if hit == null or not hit.has_method("take_damage"):
		return false
	var hit_team = hit.get("team")
	if hit_team == null:
		hit_team = hit.get("player_team")
	if hit_team == null:
		hit_team = -999
	# Friendly fire: same team = no damage
	if shooter_team >= 0 and hit_team == shooter_team:
		return false
	# Player bullet hitting player = no damage
	if shooter_team == -1 and hit_team == -1:
		return false
	return true

static func make_team_tracer_material(shooter_team: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.flags_unshaded = true
	mat.emission_enabled = true
	if shooter_team == -1:
		mat.albedo_color = Color(1.0, 0.95, 0.6, 1.0)
		mat.emission     = Color(1.0, 0.95, 0.6)
	elif shooter_team == 0:
		mat.albedo_color = Color(0.4, 0.6, 1.0, 1.0)
		mat.emission     = Color(0.4, 0.6, 1.0)
	else:
		mat.albedo_color = Color(1.0, 0.4, 0.4, 1.0)
		mat.emission     = Color(1.0, 0.4, 0.4)
	mat.emission_energy_multiplier = 8.0
	mat.no_depth_test = true
	return mat
