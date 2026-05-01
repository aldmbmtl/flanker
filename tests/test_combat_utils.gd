# test_combat_utils.gd
# Tier 1 — unit tests for CombatUtils.should_damage, including the self-damage
# exclusion added to prevent players from killing themselves with rockets.
extends GutTest

# A target node with both take_damage and a team property.
class FakeTarget extends Node3D:
	var player_team: int = 0
	var peer_id: int     = -1
	var damage_calls: int = 0

	func take_damage(amount: float, _source: String, _team: int, _peer: int) -> void:
		damage_calls += 1

# A fake ghost hitbox: StaticBody3D (real ghost bodies are StaticBody3D) + take_damage.
class FakeGhostHitbox extends StaticBody3D:
	var player_team: int = 0
	var peer_id: int     = -1
	var damage_calls: int = 0

	func take_damage(amount: float, _source: String, _team: int, _peer: int) -> void:
		damage_calls += 1

func test_same_team_blocked() -> void:
	var t := FakeTarget.new()
	t.player_team = 1
	add_child_autofree(t)
	assert_false(CombatUtils.should_damage(t, 1),
		"Same-team target must not be damaged")

func test_enemy_team_allowed() -> void:
	var t := FakeTarget.new()
	t.player_team = 0
	add_child_autofree(t)
	assert_true(CombatUtils.should_damage(t, 1),
		"Enemy-team target must be damageable")

func test_null_target_returns_false() -> void:
	assert_false(CombatUtils.should_damage(null, 1),
		"Null target must not be damaged")

func test_no_take_damage_method_returns_false() -> void:
	var bare := Node3D.new()
	add_child_autofree(bare)
	assert_false(CombatUtils.should_damage(bare, 1),
		"Node without take_damage must return false")

# ── Self-damage exclusion (new) ───────────────────────────────────────────────

func test_self_peer_direct_body_blocked() -> void:
	# Shooter peer_id 5 hits their own FPS body (peer_id == 5).
	var t := FakeTarget.new()
	t.player_team = 0   # team 0, shooter_team is -1 (player rocket)
	t.peer_id     = 5
	add_child_autofree(t)
	assert_false(CombatUtils.should_damage(t, -1, 5),
		"Shooter must not damage their own body")

func test_self_peer_ghost_hitbox_blocked() -> void:
	# Shooter peer_id 5 hits their own ghost StaticBody3D hitbox.
	var ghost := FakeGhostHitbox.new()
	ghost.set_meta("ghost_peer_id", 5)
	ghost.player_team = 0
	add_child_autofree(ghost)
	assert_false(CombatUtils.should_damage(ghost, -1, 5),
		"Shooter must not damage their own ghost hitbox")

func test_different_peer_ghost_hitbox_allowed() -> void:
	# Shooter peer_id 5 hits peer 7's ghost hitbox — should damage.
	var ghost := FakeGhostHitbox.new()
	ghost.set_meta("ghost_peer_id", 7)
	ghost.player_team = 1   # enemy team
	add_child_autofree(ghost)
	assert_true(CombatUtils.should_damage(ghost, -1, 5),
		"Different-peer ghost hitbox must be damageable")

func test_no_shooter_peer_id_unaffected() -> void:
	# Minion/tower projectiles pass shooter_peer_id = -1 (default).
	# Existing behaviour must be unchanged.
	var t := FakeTarget.new()
	t.player_team = 1   # enemy
	t.peer_id     = 5
	add_child_autofree(t)
	# shooter_team 0 (tower), no peer ID — should still damage enemy player
	assert_true(CombatUtils.should_damage(t, 0, -1),
		"No shooter_peer_id: existing team logic must be unchanged")

func test_self_peer_friendly_team_double_blocked() -> void:
	# Even if team check would also block it, self-peer check fires first.
	var t := FakeTarget.new()
	t.player_team = 0
	t.peer_id     = 3
	add_child_autofree(t)
	assert_false(CombatUtils.should_damage(t, -1, 3),
		"Self-peer check must block even when team check would pass")
