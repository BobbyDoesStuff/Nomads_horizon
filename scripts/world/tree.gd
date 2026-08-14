extends StaticBody2D
## Cuttable tree — highlights when a nearby player has the axe out, and can be
## chopped down for wood.

const WOOD_TOTAL := 10          # wood each tree yields
const WOOD_INTERVAL := 1.0      # seconds between each +1 wood
const RESPAWN_TIME := 10.0      # seconds a felled tree stays gone

var tree_id: int = -1
var near_range: float = 120.0   # how close the player must be to chop

var _sprite_w: int = 0
var _sprite_h: int = 0
var _highlight: Panel = null
var _progress: ProgressBar = null
var _chopper: Node = null
var _wood_left: int = WOOD_TOTAL
var _accum: float = 0.0
var _respawn_timer: float = -1.0   # -1 = not respawning


func setup(img_path: String, pos: Vector2, fallback_size: Vector2, id: int) -> void:
	tree_id = id
	add_to_group("trees")
	global_position = pos
	collision_layer = 1
	collision_mask = 0
	near_range = maxf(fallback_size.x, fallback_size.y) * 0.5 + 48.0

	var img := _load_image(img_path)
	if img == null:
		push_error("[Tree] Missing: " + img_path)
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


func can_be_chopped() -> bool:
	return _chopper == null and _wood_left > 0 and _respawn_timer < 0.0


func set_highlighted(on: bool) -> void:
	if _highlight:
		_highlight.visible = on


func start_chop(chopper: Node) -> void:
	if _chopper != null:
		return
	_chopper = chopper
	_accum = 0.0
	_progress.value = 0.0
	_progress.visible = true
	set_highlighted(false)


func stop_chop() -> void:
	_chopper = null
	_progress.visible = false


func _process(delta: float) -> void:
	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	if _chopper == null:
		return
	if not is_instance_valid(_chopper):
		stop_chop()
		return
	_accum += delta
	while _accum >= WOOD_INTERVAL:
		_accum -= WOOD_INTERVAL
		_chop_tick()


func _chop_tick() -> void:
	_wood_left -= 1
	_progress.value = WOOD_TOTAL - _wood_left
	if is_instance_valid(_chopper) and _chopper.has_method("add_wood"):
		_chopper.add_wood(1)
	_spawn_float_text("+1 wood", Color(0.85, 0.65, 0.3))
	if _wood_left <= 0:
		_finish()


func _finish() -> void:
	chopped()
	# Fell the tree everywhere (server relays to the other peers).
	var world := get_parent()
	if world and multiplayer.multiplayer_peer != null:
		if NetworkManager.is_server:
			world._remove_tree.rpc(tree_id)
		else:
			world.recv_tree_chopped.rpc_id(1, tree_id)


func chopped() -> void:
	# Enter the felled (respawning) state — also called on remote peers via RPC.
	# Wake whichever chopper is still attached (handles two players racing on one tree).
	if is_instance_valid(_chopper) and _chopper.has_method("_on_tree_finished"):
		_chopper._on_tree_finished(self)
	_chopper = null
	_progress.visible = false
	visible = false
	collision_layer = 0
	_respawn_timer = RESPAWN_TIME


func _respawn() -> void:
	_respawn_timer = -1.0
	_wood_left = WOOD_TOTAL
	visible = true
	collision_layer = 1


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
	# Parent to the world (not the tree) so the final "+1 wood" isn't hidden when
	# the tree fells itself.
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
	bar.name = "ChopProgress"
	bar.min_value = 0
	bar.max_value = WOOD_TOTAL
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
