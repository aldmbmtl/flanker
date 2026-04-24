extends Node

var _health_bar_packed: PackedScene = null

var active_entities: Array[Dictionary] = []
var next_id: int = 1

var _screen_width: int = 0
var _screen_height: int = 0
var _hud_root: Node = null

func _ready() -> void:
	_health_bar_packed = load("res://scenes/HUD/HealthBar.tscn")
	var vp := get_viewport()
	if vp:
		_screen_width = vp.size.x
		_screen_height = vp.size.y

func setup(hud_root: Node) -> void:
	_hud_root = hud_root

func register_entity(entity: Node3D, max_health: float, team: int = -1) -> int:
	if not _hud_root or not _health_bar_packed:
		return -1

	var health_bar: Control = _health_bar_packed.instantiate()
	_hud_root.add_child(health_bar)
	health_bar.visible = false

	var entity_id: int = next_id
	next_id += 1

	active_entities.append({
		id = entity_id,
		entity = entity,
		health = max_health,
		max_health = max_health,
		ui_node = health_bar,
		team = team,
		camera_dist = 0.0
	})

	return entity_id

func update_entity_health(entity_id: int, health: float) -> void:
	for e in active_entities:
		if e.id == entity_id:
			e.health = health
			return

func get_entity_by_id(entity_id: int) -> Dictionary:
	for e in active_entities:
		if e.id == entity_id:
			return e
	return {}

func process_entity_hud(_delta: float, active_camera: Camera3D, crosshair_pos: Vector2 = Vector2.ZERO) -> void:
	if not active_camera or not _hud_root:
		return

	var to_remove: Array = []
	var visible_entries: Array = []

	for entity in active_entities:
		if not is_instance_valid(entity.entity) or entity.entity._dead:
			to_remove.append(entity.id)
			continue

		entity.camera_dist = active_camera.global_position.distance_to(entity.entity.global_position)
		if entity.camera_dist > 25.0:
			entity.ui_node.visible = false
			continue

		# Project world pos to screen — lower offset
		var head_pos: Vector3 = entity.entity.global_position + Vector3(0, 1.2, 0)

		# Check if behind camera before unprojecting (avoids p.d == 0 error)
		var to_entity: Vector3 = head_pos - active_camera.global_position
		var cam_fwd: Vector3 = -active_camera.global_transform.basis.z
		if to_entity.dot(cam_fwd) <= 0.0:
			entity.ui_node.visible = false
			continue

		var screen_pos: Vector2 = active_camera.unproject_position(head_pos)

		# Check if outside viewport bounds
		if _screen_width > 0 and _screen_height > 0:
			if screen_pos.x < 0 or screen_pos.x > _screen_width or screen_pos.y < 0 or screen_pos.y > _screen_height:
				entity.ui_node.visible = false
				continue

		# Check crosshair proximity (Vector2(-1,-1) means show all)
		if crosshair_pos != Vector2.ZERO and crosshair_pos != Vector2(-1, -1):
			var to_crosshair: Vector2 = screen_pos - crosshair_pos
			if to_crosshair.length() > 80.0:
				entity.ui_node.visible = false
				continue

		visible_entries.append({entry = entity, screen_pos = screen_pos})

	# Sort closest first so closer bars render on top
	visible_entries.sort_custom(func(a, b):
		return a.entry.camera_dist < b.entry.camera_dist
	)

	for item in visible_entries:
		var entity: Dictionary = item.entry
		var sp: Vector2 = item.screen_pos
		var pct: float = clamp(entity.health / entity.max_health, 0.0, 1.0)

		# Center bar horizontally on entity screen position
		var bar_width: float = 150.0
		var bar_height: float = 20.0
		entity.ui_node.position = Vector2(sp.x - bar_width * 0.5, sp.y - bar_height - 4.0)
		entity.ui_node.visible = true

		# Update foreground width to reflect health pct
		var fg: ColorRect = entity.ui_node.get_node_or_null("Foreground")
		if fg:
			fg.size = Vector2(pct * bar_width, bar_height)

	for id in to_remove:
		_remove_entity(id)

func _remove_entity(entity_id: int) -> void:
	for i in range(active_entities.size()):
		var e: Dictionary = active_entities[i]
		if e.id == entity_id:
			if is_instance_valid(e.ui_node):
				e.ui_node.queue_free()
			active_entities.remove_at(i)
			return
