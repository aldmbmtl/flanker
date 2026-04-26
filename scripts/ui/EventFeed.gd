extends Control

# ── EventFeed ─────────────────────────────────────────────────────────────────
# Scrolling event log anchored bottom-right of HUD.
# Call add_event(text) from Main.gd to post a new entry.
# Entries are visible for EVENT_LIFETIME seconds; the last FADE_DURATION seconds
# are spent fading out. Max MAX_ENTRIES lines shown at once (oldest removed).

const MAX_ENTRIES    := 6
const EVENT_LIFETIME := 8.0   # total seconds an entry lives
const FADE_DURATION  := 2.0   # seconds of the fade-out at the end

# Each entry: { label: Label, tween: Tween, age: float }
var _entries: Array = []

@onready var _vbox: VBoxContainer = $VBox

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func add_event(text: String) -> void:
	# Trim oldest if at cap
	if _entries.size() >= MAX_ENTRIES:
		var oldest: Dictionary = _entries[0]
		_entries.remove_at(0)
		if oldest["label"] and is_instance_valid(oldest["label"]):
			oldest["label"].queue_free()
		if oldest["tween"] and oldest["tween"].is_valid():
			oldest["tween"].kill()

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(lbl)

	var tw: Tween = create_tween()
	# Stay opaque until (EVENT_LIFETIME - FADE_DURATION), then fade
	tw.tween_interval(EVENT_LIFETIME - FADE_DURATION)
	tw.tween_property(lbl, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(_remove_entry.bind(lbl))

	_entries.append({ "label": lbl, "tween": tw })

func _remove_entry(lbl: Label) -> void:
	for i in range(_entries.size()):
		if _entries[i]["label"] == lbl:
			_entries.remove_at(i)
			break
	if is_instance_valid(lbl):
		lbl.queue_free()
