## SoundManager — global audio autoload.
## Creates an SFX bus at runtime, pools AudioStreamPlayer3D + AudioStreamPlayer
## nodes, and exposes play_3d / play_2d helpers used by all game systems.
## Callers pass res:// paths; Godot's resource cache deduplicates loads.

extends Node

const BUS_SFX := "SFX"

const POOL_3D_SIZE := 8
const POOL_2D_SIZE := 3

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_3d_idx: int = 0

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_2d_idx: int = 0

func _ready() -> void:
	# Create SFX bus if it doesn't already exist
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, BUS_SFX)
		AudioServer.set_bus_send(idx, "Master")

	# 3D spatial pool — used for world-space sounds (impacts, explosions, footsteps)
	for i: int in POOL_3D_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS_SFX
		p.max_distance = 80.0
		p.unit_size = 10.0
		add_child(p)
		_pool_3d.append(p)

	# 2D non-spatial pool — reserved for future UI/announcement sounds
	for i: int in POOL_2D_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool_2d.append(p)

## Play a spatial sound at world position `pos`.
## `vol_db`   — volume in dB, 0.0 = nominal.
## `pitch`    — pitch scale, 1.0 = original.
func play_3d(path: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = load(path)
	if stream == null:
		return
	var p: AudioStreamPlayer3D = _pool_3d[_pool_3d_idx]
	_pool_3d_idx = (_pool_3d_idx + 1) % POOL_3D_SIZE
	p.stream = stream
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

## Release all stream references so loaded OGG resources are freed cleanly at exit.
## Explicitly stop + null + free each pool player so the AudioServer releases
## its internal playback objects before the resource cache is cleared.
func _exit_tree() -> void:
	for p: AudioStreamPlayer3D in _pool_3d:
		p.stop()
		p.stream = null
		p.free()
	_pool_3d.clear()
	for p: AudioStreamPlayer in _pool_2d:
		p.stop()
		p.stream = null
		p.free()
	_pool_2d.clear()

## Play a non-spatial (UI / music) sound.
func play_2d(path: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = load(path)
	if stream == null:
		return
	var p: AudioStreamPlayer = _pool_2d[_pool_2d_idx]
	_pool_2d_idx = (_pool_2d_idx + 1) % POOL_2D_SIZE
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()
