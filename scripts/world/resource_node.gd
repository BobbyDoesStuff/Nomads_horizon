extends StaticBody2D
## Harvestable resource node (tree → wood, rock → stone).
## Highlights when a nearby player has the matching tool out, and can be
## harvested down for its resource.

const HARVEST_TOTAL := 10       # resource each node yields
const HARVEST_INTERVAL := 1.0   # seconds between each +1
const RESPAWN_TIME := 30.0      # seconds a depleted node stays gone

var node_id: String = ""        # stable name, e.g. "Tree_0" / "Rock_1"
var resource: String = "wood"   # "wood" or "stone"
var near_range: float = 120.0   # how close the player must be to harvest

var _sprite_w: int = 0
var _sprite_h: int = 0
var _highlight: Panel = null
var _progress: ProgressBar = null
var _harvester: Node = null
var _left: int = HARVEST_TOTAL
var _accum: float = 0.0
var _respawn_timer: float = -1.0   # -1 = not respawning


func setup(img_path: String, pos: Vector2, fallback_size: Vector2, p_node_id: String, p_resource: String) -> void:
	node_id = p_node_id
	resource = p_resource
	add_to_group("resources")
	global_position = pos
	collision_layer = 1
	collision_mask = 0
	near_range = maxf(fallback_size.x, fallback_size.y) * 0.5 + 48.0

	var img := _load_image(img_path)
	if img == null:
		push_error("[Resource] Missing: " + img_path)
		return
	_sprite_w = img.get_width()
	_sprite_h = img.get_height()

	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = false
	sprite.position = Vector2(-_sprite_w / 2.0, -_sprite_h)
	sprite.z_index = 0
	add_child(sprite)

	_add_collision(img, fallback_size)

	_highlight = _make_highlight()
	_highlight.visible = false
	add_child(_highlight)

	_progress = _make_progress()
	_progress.visible = false
	add_child(_progress)


func can_be_harvested() -> bool:
	return _harvester == null and _left > 0 and _respawn_timer < 0.0


func set_highlighted(on: bool) -> void:
	if _highlight:
		_highlight.visible = on


func start_harvest(harvester: Node) -> void:
	if _harvester != null:
		return
	_harvester = harvester
	_accum = 0.0
	_progress.value = 0.0
	_progress.visible = true
	set_highlighted(false)


func stop_harvest() -> void:
	_harvester = null
	_progress.visible = false


func _process(delta: float) -> void:
	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	if _harvester == null:
		return
	if not is_instance_valid(_harvester):
		stop_harvest()
		return
	_accum += delta
	while _accum >= HARVEST_INTERVAL:
		_accum -= HARVEST_INTERVAL
		_harvest_tick()


func _harvest_tick() -> void:
	_left -= 1
	_progress.value = HARVEST_TOTAL - _left
	if is_instance_valid(_harvester) and _harvester.has_method("add_resource"):
		_harvester.add_resource(resource, 1)
	_spawn_float_text("+1 " + resource, _resource_color())
	if _left <= 0:
		_finish()


func _finish() -> void:
	chopped()
	# Deplete the node everywhere (server relays to the other peers).
	var world := get_parent()
	if world and multiplayer.multiplayer_peer != null:
		if NetworkManager.is_server:
			world._remove_resource.rpc(node_id)
		else:
			world.recv_resource_depleted.rpc_id(1, node_id)


func chopped() -> void:
	# Enter the depleted (respawning) state — also called on remote peers via RPC.
	# Wake whichever harvester is still attached (handles two players racing on one node).
	if is_instance_valid(_harvester) and _harvester.has_method("_on_resource_finished"):
		_harvester._on_resource_finished(self)
	_harvester = null
	_progress.visible = false
	visible = false
	collision_layer = 0
	_respawn_timer = RESPAWN_TIME


func _respawn() -> void:
	_respawn_timer = -1.0
	_left = HARVEST_TOTAL
	visible = true
	collision_layer = 1


func _resource_color() -> Color:
	return Color(0.85, 0.65, 0.3) if resource == "wood" else Color(0.72, 0.74, 0.78)


func _spawn_float_text(txt: String, color: Color) -> void:
	var label := Label.new()
	label.text = txt
	label.size = Vector2(90, 22)
	label.position = global_position + Vector2(-45, -_sprite_h - 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 10
	# Parent to the world (not the node) so the final "+1" isn't hidden when it depletes.
	var parent := get_parent()
	if parent:
		parent.add_child(label)
	else:
		add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tween.finished.connect(label.queue_free)


func _make_highlight() -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(-_sprite_w / 2.0, -_sprite_h)
	panel.size = Vector2(_sprite_w, _sprite_h)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.9, 0.3, 0.06)
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 0.9, 0.3, 0.95)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_progress() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "HarvestProgress"
	bar.min_value = 0
	bar.max_value = HARVEST_TOTAL
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(80, 10)
	bar.position = Vector2(-40, -_sprite_h - 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.35, 0.15, 1.0)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_border_width_all(1)
	bg.border_color = Color(1.0, 1.0, 1.0, 0.5)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _add_collision(img: Image, fallback_size: Vector2) -> void:
	# Build a collision outline from the sprite's opaque pixels (same as obstacles).
	var points := PackedVector2Array()
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			if img.get_pixel(x, y).a > 0.1:
				points.append(Vector2(x - w / 2.0, y - h))
	if points.size() < 3:
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = fallback_size
		shape.position = Vector2(0, -fallback_size.y / 2.0)
		add_child(shape)
		return
	var hull := Geometry2D.convex_hull(points)
	var cp := CollisionPolygon2D.new()
	cp.polygon = hull
	add_child(cp)


func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img
