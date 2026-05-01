## test_health_pack_pickup.gd
## Regression tests for HealthPackPickup — specifically the `is_local` guard
## (was `_is_local` before the fix, causing all pickups to fail).
##
## Tier 1 (OfflineMultiplayerPeer → is_server=true).

extends GutTest

const HealthPackScript := preload("res://scripts/HealthPackPickup.gd")

# ── Fake body stand-ins ────────────────────────────────────────────────────────

## Local player stand-in: has is_local=true and heal() method.
class FakeLocalPlayer extends CharacterBody3D:
	var is_local: bool = true
	var player_team: int = 0
	var healed_amount: float = 0.0
	func heal(amount: float) -> void:
		healed_amount += amount

## Puppet/remote player stand-in: is_local=false.
class FakePuppet extends CharacterBody3D:
	var is_local: bool = false
	var player_team: int = 0
	var healed_amount: float = 0.0
	func heal(amount: float) -> void:
		healed_amount += amount

## Node with neither heal() nor is_local — should be ignored silently.
class FakeUnrelatedBody extends CharacterBody3D:
	pass

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_pack(team: int = -1) -> Area3D:
	var pack: Area3D = Area3D.new()
	pack.set_script(HealthPackScript)
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	pack.add_child(col)
	add_child_autofree(pack)
	pack.setup(team)
	return pack

# ── is_local guard ─────────────────────────────────────────────────────────────

func test_local_player_is_healed() -> void:
	## Regression: before fix, body.get("_is_local") was always null → pickup blocked.
	var pack: Area3D = _make_pack()
	var player := FakeLocalPlayer.new()
	add_child_autofree(player)
	pack._on_body_entered(player)
	assert_almost_eq(player.healed_amount, HealthPackScript.HEAL_AMOUNT, 0.001,
		"Local player must receive HEAL_AMOUNT from pickup")

func test_puppet_player_is_not_healed() -> void:
	## Puppet nodes (is_local=false) must not trigger pickup; only the owning client fires it.
	var pack: Area3D = _make_pack()
	var puppet := FakePuppet.new()
	add_child_autofree(puppet)
	pack._on_body_entered(puppet)
	assert_almost_eq(puppet.healed_amount, 0.0, 0.001,
		"Puppet (is_local=false) must not be healed by pickup")

func test_body_without_heal_is_ignored() -> void:
	## No method heal() → early return, no error.
	var pack: Area3D = _make_pack()
	var body := FakeUnrelatedBody.new()
	add_child_autofree(body)
	# Should not error
	pack._on_body_entered(body)
	assert_true(true, "Unrelated body should be silently ignored")

# ── Team guard ────────────────────────────────────────────────────────────────

func test_correct_team_is_healed() -> void:
	var pack: Area3D = _make_pack(0)  # blue team pack
	var player := FakeLocalPlayer.new()
	player.player_team = 0
	add_child_autofree(player)
	pack._on_body_entered(player)
	assert_almost_eq(player.healed_amount, HealthPackScript.HEAL_AMOUNT, 0.001,
		"Same-team local player must receive heal")

func test_wrong_team_is_blocked() -> void:
	var pack: Area3D = _make_pack(0)  # blue pack
	var player := FakeLocalPlayer.new()
	player.player_team = 1  # red
	add_child_autofree(player)
	pack._on_body_entered(player)
	assert_almost_eq(player.healed_amount, 0.0, 0.001,
		"Wrong-team local player must be blocked by team guard")

func test_any_team_pack_heals_any_local_player() -> void:
	var pack: Area3D = _make_pack(-1)  # team=-1 → any team
	var player := FakeLocalPlayer.new()
	player.player_team = 1
	add_child_autofree(player)
	pack._on_body_entered(player)
	assert_almost_eq(player.healed_amount, HealthPackScript.HEAL_AMOUNT, 0.001,
		"team=-1 pack must heal any local player regardless of team")

# ── Heal amount ────────────────────────────────────────────────────────────────

func test_heal_amount_constant_is_50() -> void:
	assert_almost_eq(HealthPackScript.HEAL_AMOUNT, 50.0, 0.001,
		"HEAL_AMOUNT must be 50.0")

func test_heal_amount_applied_exactly() -> void:
	var pack: Area3D = _make_pack()
	var player := FakeLocalPlayer.new()
	add_child_autofree(player)
	pack._on_body_entered(player)
	assert_almost_eq(player.healed_amount, 50.0, 0.001,
		"Exactly 50 HP must be applied")
