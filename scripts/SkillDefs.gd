extends Node
# Static definitions for all skill tree nodes.
# No state lives here — only the immutable blueprint of every node.
#
# Fields per node:
#   role       : "Fighter" or "Supporter"
#   branch     : visual grouping label
#   type       : "passive" | "active" | "unlock" | "utility"
#   tier       : 1, 2, or 3  (also equals cost in skill points)
#   cost       : int skill points to unlock
#   prereqs    : Array[String] of node IDs that must be unlocked first
#   level_req  : minimum player level required (0 = no gate)
#   name       : short display name (fits in a small HUD card)
#   description: short display string
#   passive_key: String used by SkillTree.get_passive_bonus() (passive/utility only)
#   passive_val: float value contributed by this node to its passive_key
#   cooldown   : float seconds (active nodes only; 0.0 for non-actives)

const ALL: Dictionary = {
	# ─────────────────────────────────────────────────────────────────────────
	# FIGHTER — Guardian branch (healing / aura)
	# ─────────────────────────────────────────────────────────────────────────
	"f_field_medic": {
		"role": "Fighter", "branch": "Guardian", "type": "active",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Field Medic",
		"description": "Heal yourself and nearby allies within 8 m for 25 HP. 15 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 15.0,
	},
	"f_rally_cry": {
		"role": "Fighter", "branch": "Guardian", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["f_field_medic"], "level_req": 0,
		"name": "Rally Cry",
		"description": "Grant nearby allies +20% move speed for 5 s. 30 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 30.0,
	},
	"f_revive_pulse": {
		"role": "Fighter", "branch": "Guardian", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["f_rally_cry"], "level_req": 0,
		"name": "Revive Pulse",
		"description": "Fully heal yourself and restore 30 HP to all allies within 10 m. 60 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 60.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# FIGHTER — DPS branch (burst / mobility)
	# ─────────────────────────────────────────────────────────────────────────
	"f_dash": {
		"role": "Fighter", "branch": "DPS", "type": "active",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Dash",
		"description": "Dash 5 m forward. 6 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 6.0,
	},
	"f_rapid_fire": {
		"role": "Fighter", "branch": "DPS", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["f_dash"], "level_req": 0,
		"name": "Rapid Fire",
		"description": "Current weapon fires 3× faster for 3 s. 20 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 20.0,
	},
	"f_rocket_barrage": {
		"role": "Fighter", "branch": "DPS", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["f_rapid_fire"], "level_req": 0,
		"name": "Rocket Barrage",
		"description": "Fire one rocket at each enemy tower within 50 m (up to 5). No targets = no effect. 45 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 45.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# FIGHTER — Tank branch (mitigation / deploy)
	# ─────────────────────────────────────────────────────────────────────────
	"f_adrenaline": {
		"role": "Fighter", "branch": "Tank", "type": "active",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Adrenaline",
		"description": "Instantly heal 40 HP. 20 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 20.0,
	},
	"f_iron_skin": {
		"role": "Fighter", "branch": "Tank", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["f_adrenaline"], "level_req": 0,
		"name": "Iron Skin",
		"description": "Absorb the next 60 incoming damage as a shield for 8 s. 30 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 30.0,
	},
	"f_deploy_mg": {
		"role": "Fighter", "branch": "Tank", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["f_iron_skin"], "level_req": 0,
		"name": "Deploy MG",
		"description": "Deploy a MachineGun turret at your feet for 20 s (no team point cost). 60 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 60.0,
	},

	# ─────────────────────────────────────────────────────────────────────────
	# SUPPORTER — Formation branch (minion durability)
	# ─────────────────────────────────────────────────────────────────────────
	"s_minion_hp": {
		"role": "Supporter", "branch": "Formation", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Tougher Troops",
		"description": "All friendly minions spawn with +25% max HP.",
		"passive_key": "minion_hp_bonus", "passive_val": 0.25,
		"cooldown": 0.0,
	},
	"s_minion_armor": {
		"role": "Supporter", "branch": "Formation", "type": "passive",
		"tier": 2, "cost": 2, "prereqs": ["s_minion_hp"], "level_req": 0,
		"name": "Battle Hardened",
		"description": "Friendly minions take 15% less damage.",
		"passive_key": "minion_damage_reduction", "passive_val": 0.15,
		"cooldown": 0.0,
	},
	"s_minion_revive": {
		"role": "Supporter", "branch": "Formation", "type": "passive",
		"tier": 3, "cost": 3, "prereqs": ["s_minion_armor"], "level_req": 0,
		"name": "Last Stand",
		"description": "Once per wave, the first friendly minion to die is revived at 30% HP.",
		"passive_key": "minion_revive", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# SUPPORTER — Aggression branch (minion combat power)
	# ─────────────────────────────────────────────────────────────────────────
	"s_minion_damage": {
		"role": "Supporter", "branch": "Aggression", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Sharp Blades",
		"description": "Friendly minions deal +20% attack damage.",
		"passive_key": "minion_damage_bonus", "passive_val": 0.20,
		"cooldown": 0.0,
	},
	"s_minion_speed": {
		"role": "Supporter", "branch": "Aggression", "type": "passive",
		"tier": 2, "cost": 2, "prereqs": ["s_minion_damage"], "level_req": 0,
		"name": "Force March",
		"description": "Friendly minions move +25% faster.",
		"passive_key": "minion_speed_bonus", "passive_val": 0.25,
		"cooldown": 0.0,
	},
	"s_minion_barrage": {
		"role": "Supporter", "branch": "Aggression", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["s_minion_speed"], "level_req": 0,
		"name": "Coordinated Fire",
		"description": "All friendly living minions fire once immediately. 40 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 40.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# SUPPORTER — Logistics branch (wave economy)
	# ─────────────────────────────────────────────────────────────────────────
	"s_minion_count": {
		"role": "Supporter", "branch": "Logistics", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Reinforce",
		"description": "Waves spawn +1 extra minion per lane.",
		"passive_key": "minion_count_bonus", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	"s_minion_xp": {
		"role": "Supporter", "branch": "Logistics", "type": "passive",
		"tier": 2, "cost": 2, "prereqs": ["s_minion_count"], "level_req": 0,
		"name": "Combat Vets",
		"description": "Minion kills award +50% XP.",
		"passive_key": "minion_xp_bonus", "passive_val": 0.5,
		"cooldown": 0.0,
	},
	"s_minion_surge": {
		"role": "Supporter", "branch": "Logistics", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["s_minion_xp"], "level_req": 0,
		"name": "Point Raid",
		"description": "Each living friendly minion grants +1 team point. 60 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 60.0,
	},
}

# ── Helpers ────────────────────────────────────────────────────────────────────

func get_def(node_id: String) -> Dictionary:
	return ALL.get(node_id, {})

func get_nodes_for_role(role: String) -> Array:
	var result: Array = []
	for id in ALL:
		if ALL[id]["role"] == role:
			result.append(id)
	return result

func get_branches_for_role(role: String) -> Array:
	var seen: Dictionary = {}
	for id in ALL:
		if ALL[id]["role"] == role:
			seen[ALL[id]["branch"]] = true
	return seen.keys()

func get_nodes_in_branch(role: String, branch: String) -> Array:
	var result: Array = []
	for id in ALL:
		var d: Dictionary = ALL[id]
		if d["role"] == role and d["branch"] == branch:
			result.append(id)
	# Sort by tier for deterministic display order
	result.sort_custom(func(a: String, b: String) -> bool:
		return ALL[a]["tier"] < ALL[b]["tier"])
	return result
