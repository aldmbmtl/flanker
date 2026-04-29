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
	# SUPPORTER — Arsenal branch
	# ─────────────────────────────────────────────────────────────────────────
	"s_build_discount": {
		"role": "Supporter", "branch": "Arsenal", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Build Discount",
		"description": "All your placements cost −2 team points.",
		"passive_key": "build_discount", "passive_val": 2.0,
		"cooldown": 0.0,
	},
	"s_turret_overdrive": {
		"role": "Supporter", "branch": "Arsenal", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["s_build_discount"], "level_req": 0,
		"name": "Turret Overdrive",
		"description": "Targeted friendly tower fires 2× speed for 6 s. 25 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 25.0,
	},
	"s_advanced_launcher": {
		"role": "Supporter", "branch": "Arsenal", "type": "unlock",
		"tier": 3, "cost": 3, "prereqs": ["s_turret_overdrive"], "level_req": 0,
		"name": "Adv. Launcher",
		"description": "Unlocks Advanced Launcher missile type in the build shop.",
		"passive_key": "advanced_launcher", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# SUPPORTER — Logistics branch
	# ─────────────────────────────────────────────────────────────────────────
	"s_fast_respawn": {
		"role": "Supporter", "branch": "Logistics", "type": "utility",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Fast Respawn",
		"description": "Your personal respawn timer is −2 s.",
		"passive_key": "respawn_reduction", "passive_val": 2.0,
		"cooldown": 0.0,
	},
	"s_ammo_drop": {
		"role": "Supporter", "branch": "Logistics", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["s_fast_respawn"], "level_req": 0,
		"name": "Ammo Drop",
		"description": "Place an ammo crate at your feet. Allies within 3 m reload instantly. 30 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 30.0,
	},
	"s_build_anywhere": {
		"role": "Supporter", "branch": "Logistics", "type": "utility",
		"tier": 3, "cost": 3, "prereqs": ["s_ammo_drop"], "level_req": 0,
		"name": "Build Anywhere",
		"description": "Removes lane-setback restriction from your placements.",
		"passive_key": "build_anywhere", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	"s_rally": {
		"role": "Supporter", "branch": "Logistics", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["s_build_anywhere"], "level_req": 0,
		"name": "Rally",
		"description": "Rally beacon: all teammates gain +10% move speed for 8 s. 45 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 45.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# SUPPORTER — Defense branch
	# ─────────────────────────────────────────────────────────────────────────
	"s_tower_hp": {
		"role": "Supporter", "branch": "Defense", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"name": "Tower HP",
		"description": "Friendly towers you place spawn with +20% HP.",
		"passive_key": "tower_hp_bonus", "passive_val": 0.2,
		"cooldown": 0.0,
	},
	"s_repair": {
		"role": "Supporter", "branch": "Defense", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["s_tower_hp"], "level_req": 0,
		"name": "Repair",
		"description": "Restore 30% HP to the nearest friendly tower within 15 m. 20 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 20.0,
	},
	"s_fortify": {
		"role": "Supporter", "branch": "Defense", "type": "passive",
		"tier": 2, "cost": 2, "prereqs": ["s_tower_hp"], "level_req": 0,
		"name": "Fortify",
		"description": "Barrier towers you place have ×2 HP.",
		"passive_key": "barrier_hp_mult", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	"s_point_surge": {
		"role": "Supporter", "branch": "Defense", "type": "utility",
		"tier": 3, "cost": 3, "prereqs": ["s_repair"], "level_req": 0,
		"name": "Point Surge",
		"description": "On kill: your team gains +3 points.",
		"passive_key": "point_surge", "passive_val": 3.0,
		"cooldown": 0.0,
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
