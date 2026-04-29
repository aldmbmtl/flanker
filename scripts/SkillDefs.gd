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
#   description: short display string
#   passive_key: String used by SkillTree.get_passive_bonus() (passive/utility only)
#   passive_val: float value contributed by this node to its passive_key
#   cooldown   : float seconds (active nodes only; 0.0 for non-actives)

const ALL: Dictionary = {
	# ─────────────────────────────────────────────────────────────────────────
	# FIGHTER — Combat branch
	# ─────────────────────────────────────────────────────────────────────────
	"f_headshot": {
		"role": "Fighter", "branch": "Combat", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"description": "+15% headshot damage.",
		"passive_key": "headshot_mult", "passive_val": 0.15,
		"cooldown": 0.0,
	},
	"f_reload": {
		"role": "Fighter", "branch": "Combat", "type": "passive",
		"tier": 2, "cost": 2, "prereqs": ["f_headshot"], "level_req": 0,
		"description": "Reload time reduced by 25%.",
		"passive_key": "reload_speed", "passive_val": 0.25,
		"cooldown": 0.0,
	},
	"f_explosive": {
		"role": "Fighter", "branch": "Combat", "type": "unlock",
		"tier": 3, "cost": 3, "prereqs": ["f_reload"], "level_req": 0,
		"description": "Rocket Launcher costs 30 pts instead of 60 in the build shop.",
		"passive_key": "rocket_discount", "passive_val": 30.0,
		"cooldown": 0.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# FIGHTER — Mobility branch
	# ─────────────────────────────────────────────────────────────────────────
	"f_sprint_boost": {
		"role": "Fighter", "branch": "Mobility", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"description": "Sprint speed ×1.2.",
		"passive_key": "sprint_mult", "passive_val": 0.2,
		"cooldown": 0.0,
	},
	"f_stamina": {
		"role": "Fighter", "branch": "Mobility", "type": "passive",
		"tier": 2, "cost": 2, "prereqs": ["f_sprint_boost"], "level_req": 0,
		"description": "Stamina drains 30% slower.",
		"passive_key": "stamina_drain_reduction", "passive_val": 0.3,
		"cooldown": 0.0,
	},
	"f_dash": {
		"role": "Fighter", "branch": "Mobility", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["f_sprint_boost"], "level_req": 0,
		"description": "Dash 5 m forward. 6 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 6.0,
	},
	"f_ghost_step": {
		"role": "Fighter", "branch": "Mobility", "type": "passive",
		"tier": 3, "cost": 3, "prereqs": ["f_dash"], "level_req": 0,
		"description": "No footstep sounds while crouching.",
		"passive_key": "ghost_step", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	# ─────────────────────────────────────────────────────────────────────────
	# FIGHTER — Resilience branch
	# ─────────────────────────────────────────────────────────────────────────
	"f_armor": {
		"role": "Fighter", "branch": "Resilience", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"description": "−8 flat damage per incoming hit.",
		"passive_key": "damage_reduction", "passive_val": 8.0,
		"cooldown": 0.0,
	},
	"f_second_wind": {
		"role": "Fighter", "branch": "Resilience", "type": "utility",
		"tier": 2, "cost": 2, "prereqs": ["f_armor"], "level_req": 0,
		"description": "Auto-heal to 30 HP once per life when HP drops below 10.",
		"passive_key": "second_wind", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	"f_killstreak": {
		"role": "Fighter", "branch": "Resilience", "type": "utility",
		"tier": 2, "cost": 2, "prereqs": ["f_armor"], "level_req": 0,
		"description": "Each kill restores +10 HP (capped at max).",
		"passive_key": "killstreak_heal", "passive_val": 10.0,
		"cooldown": 0.0,
	},
	"f_adrenaline": {
		"role": "Fighter", "branch": "Resilience", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["f_second_wind"], "level_req": 0,
		"description": "Instantly heal 40 HP. 20 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 20.0,
	},

	# ─────────────────────────────────────────────────────────────────────────
	# SUPPORTER — Arsenal branch
	# ─────────────────────────────────────────────────────────────────────────
	"s_build_discount": {
		"role": "Supporter", "branch": "Arsenal", "type": "passive",
		"tier": 1, "cost": 1, "prereqs": [], "level_req": 0,
		"description": "All your placements cost −2 team points.",
		"passive_key": "build_discount", "passive_val": 2.0,
		"cooldown": 0.0,
	},
	"s_turret_overdrive": {
		"role": "Supporter", "branch": "Arsenal", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["s_build_discount"], "level_req": 0,
		"description": "Targeted friendly tower fires 2× speed for 6 s. 25 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 25.0,
	},
	"s_advanced_launcher": {
		"role": "Supporter", "branch": "Arsenal", "type": "unlock",
		"tier": 3, "cost": 3, "prereqs": ["s_turret_overdrive"], "level_req": 0,
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
		"description": "Your personal respawn timer is −2 s.",
		"passive_key": "respawn_reduction", "passive_val": 2.0,
		"cooldown": 0.0,
	},
	"s_ammo_drop": {
		"role": "Supporter", "branch": "Logistics", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["s_fast_respawn"], "level_req": 0,
		"description": "Place an ammo crate at your feet. Allies within 3 m reload instantly. 30 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 30.0,
	},
	"s_build_anywhere": {
		"role": "Supporter", "branch": "Logistics", "type": "utility",
		"tier": 3, "cost": 3, "prereqs": ["s_ammo_drop"], "level_req": 0,
		"description": "Removes lane-setback restriction from your placements.",
		"passive_key": "build_anywhere", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	"s_rally": {
		"role": "Supporter", "branch": "Logistics", "type": "active",
		"tier": 3, "cost": 3, "prereqs": ["s_build_anywhere"], "level_req": 0,
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
		"description": "Friendly towers you place spawn with +20% HP.",
		"passive_key": "tower_hp_bonus", "passive_val": 0.2,
		"cooldown": 0.0,
	},
	"s_repair": {
		"role": "Supporter", "branch": "Defense", "type": "active",
		"tier": 2, "cost": 2, "prereqs": ["s_tower_hp"], "level_req": 0,
		"description": "Restore 30% HP to the nearest friendly tower within 15 m. 20 s cooldown.",
		"passive_key": "", "passive_val": 0.0,
		"cooldown": 20.0,
	},
	"s_fortify": {
		"role": "Supporter", "branch": "Defense", "type": "passive",
		"tier": 2, "cost": 2, "prereqs": ["s_tower_hp"], "level_req": 0,
		"description": "Barrier towers you place have ×2 HP.",
		"passive_key": "barrier_hp_mult", "passive_val": 1.0,
		"cooldown": 0.0,
	},
	"s_point_surge": {
		"role": "Supporter", "branch": "Defense", "type": "utility",
		"tier": 3, "cost": 3, "prereqs": ["s_repair"], "level_req": 0,
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
