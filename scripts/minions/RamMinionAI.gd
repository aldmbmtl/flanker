## RamMinionAI — high-HP minion that ignores all enemies and rushes the enemy base.
## Three tiers: beaver (300 HP / $15), cow (600 HP / $30), elephant (1000 HP / $50).
## Double the physical and visual size of a standard minion.
## Requestable via SupporterHUD or injected randomly into auto-waves.
class_name RamMinionAI
extends MinionBase

const RAM_TIER_PATHS: Array[String] = [
	"res://assets/kenney_cube-pets/Models/GLB format/animal-beaver.glb",
	"res://assets/kenney_cube-pets/Models/GLB format/animal-cow.glb",
	"res://assets/kenney_cube-pets/Models/GLB format/animal-elephant.glb",
]

## Tier index: 0 = beaver, 1 = cow, 2 = elephant.
## Set by MinionSpawner via minion.set("_ram_tier", tier) before add_child.
var _ram_tier: int = 0

func _ready() -> void:
	super()
	# Ram minions never attack — zero out all combat ranges.
	detect_range   = 0.0
	attack_range   = 0.0
	shoot_range    = 0.0
	attack_damage  = 0.0
	attack_cooldown = 99.0

## Never selects a target — ram minions ignore all enemies.
func _find_target() -> Node3D:
	return null

## No-op — ram minions never fire.
func _fire_at(_target: Node3D) -> void:
	pass

## Loads the correct cube-pet GLB for this tier.
## Falls back silently if the asset isn't present (e.g. not yet imported).
func _build_visuals() -> void:
	var tier_idx: int = clampi(_ram_tier, 0, 2)
	var path: String  = RAM_TIER_PATHS[tier_idx]
	if not ResourceLoader.exists(path):
		push_warning("RamMinionAI: model not found: %s" % path)
		return
	var model: Node3D = load(path).instantiate()
	# Model is added at natural scale; the scene root is already scaled ×2 in the .tscn
	add_child(model)
