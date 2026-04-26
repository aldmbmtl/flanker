extends Control

signal role_selected(role: int)

const ROLE_FIGHTER := 0
const ROLE_SUPPORTER := 1

var _slots_taken: Dictionary = {
	ROLE_FIGHTER: false,
	ROLE_SUPPORTER: false,
}
var _my_team: int = 0

@onready var fighter_button: Button = $Panel/VBox/FighterButton
@onready var supporter_button: Button = $Panel/VBox/SupporterButton

func _ready() -> void:
	_refresh_buttons()

# Singleplayer — pass a local dict directly
func set_slots(taken: Dictionary) -> void:
	_slots_taken = taken.duplicate()
	_refresh_buttons()

# Multiplayer — seed from server-side supporter_claimed dict + our team
func set_slots_from_network(supporter_claimed: Dictionary, my_team: int) -> void:
	_my_team = my_team
	_slots_taken[ROLE_SUPPORTER] = supporter_claimed.get(my_team, false)
	_slots_taken[ROLE_FIGHTER] = false
	_refresh_buttons()

# Called live via LobbyManager.role_slots_updated signal
func on_slots_updated(supporter_claimed: Dictionary) -> void:
	_slots_taken[ROLE_SUPPORTER] = supporter_claimed.get(_my_team, false)
	_refresh_buttons()

func _refresh_buttons() -> void:
	if not is_node_ready():
		return
	fighter_button.disabled = _slots_taken.get(ROLE_FIGHTER, false)
	supporter_button.disabled = _slots_taken.get(ROLE_SUPPORTER, false)

func _on_fighter_pressed() -> void:
	emit_signal("role_selected", ROLE_FIGHTER)

func _on_supporter_pressed() -> void:
	emit_signal("role_selected", ROLE_SUPPORTER)
