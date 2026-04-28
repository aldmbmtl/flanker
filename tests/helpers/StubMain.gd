# StubMain.gd
# Stub for a "Main" scene root node — records method calls that LobbyManager
# dispatches via get_node_or_null("Main").method(...).
#
# Supported stubs (add more as needed):
#   update_wave_info(wave_num, next_in)
#   show_wave_announcement(wave_num)
#   apply_recon_reveal(target_pos, reveal_radius, reveal_duration)
extends Node
class_name StubMain

var wave_info_calls:        Array = []  # each: {wave_num, next_in}
var wave_announce_calls:    Array = []  # each: int wave_num
var recon_reveal_calls:     Array = []  # each: {pos, radius, duration}

func update_wave_info(wave_num: int, next_in: int) -> void:
	wave_info_calls.append({"wave_num": wave_num, "next_in": next_in})

func show_wave_announcement(wave_num: int) -> void:
	wave_announce_calls.append(wave_num)

func apply_recon_reveal(target_pos: Vector3, reveal_radius: float, reveal_duration: float) -> void:
	recon_reveal_calls.append({"pos": target_pos, "radius": reveal_radius, "duration": reveal_duration})

func reset() -> void:
	wave_info_calls.clear()
	wave_announce_calls.clear()
	recon_reveal_calls.clear()
