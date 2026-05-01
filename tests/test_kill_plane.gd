extends GutTest

## test_kill_plane.gd — KP1–KP4
## Verifies the kill-plane constant and the death pathway it invokes.
## Tier 1: OfflineMultiplayerPeer — multiplayer.is_server() == true.
##
## Strategy: instantiate FPSPlayer.tscn, name it "FPSPlayer_1" so _ready()
## sees is_local == true (OfflineMultiplayerPeer uid == 1). Manually set the
## player active so take_damage runs. Confirm KILL_PLANE_Y is sufficiently
## below the terrain floor, and that the void take_damage call kills the player.

const FPSPlayerScene := preload("res://scenes/roles/FPSPlayer.tscn")
const TERRAIN_FLOOR_Y := 0.0   # lowest point of map geometry

# ── Helpers ───────────────────────────────────────────────────────────────────

func _spawn_player() -> CharacterBody3D:
	var p: CharacterBody3D = FPSPlayerScene.instantiate()
	p.name = "FPSPlayer_1"
	add_child_autofree(p)
	return p

# ── KP1: KILL_PLANE_Y constant is below terrain floor ────────────────────────

func test_kp1_kill_plane_below_terrain() -> void:
	var p: CharacterBody3D = _spawn_player()
	var kill_y: float = p.get("KILL_PLANE_Y") as float
	assert_lt(kill_y, TERRAIN_FLOOR_Y,
		"KILL_PLANE_Y must be below terrain floor y=0")

# ── KP2: KILL_PLANE_Y is at least 10 units below the terrain floor ────────────

func test_kp2_kill_plane_has_sufficient_clearance() -> void:
	var p: CharacterBody3D = _spawn_player()
	var kill_y: float = p.get("KILL_PLANE_Y") as float
	assert_lt(kill_y, TERRAIN_FLOOR_Y - 10.0,
		"KILL_PLANE_Y must be at least 10 units below terrain floor")

# ── KP3: massive void damage kills an active player (_dead becomes true) ──────

func test_kp3_void_damage_kills_player() -> void:
	var p: CharacterBody3D = _spawn_player()
	# Player starts active; call the exact take_damage used by the kill-plane
	p.call("take_damage", 999999.0, "void", -1, -1)
	assert_true(p.get("_dead"),
		"Player must be dead after void take_damage")

# ── KP4: void damage does not double-kill an already dead player ───────────────

func test_kp4_void_damage_no_op_when_already_dead() -> void:
	var p: CharacterBody3D = _spawn_player()
	p.call("take_damage", 999999.0, "void", -1, -1)
	assert_true(p.get("_dead"))
	# Calling again must not crash or change state
	p.call("take_damage", 999999.0, "void", -1, -1)
	assert_true(p.get("_dead"),
		"Second void take_damage on dead player must be a no-op")
