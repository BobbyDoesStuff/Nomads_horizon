extends CanvasLayer
## HUD overlay — health, hotbar, minimap, and chat toggle.

const MAP_IMAGE_PATH := "res://assets/tiles/background.png"

@onready var health_bar:  ProgressBar = $MarginContainer/HBoxContainer/LeftPanel/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/HBoxContainer/LeftPanel/StaminaBar
@onready var hotbar:      HBoxContainer = $MarginContainer/HBoxContainer/CenterPanel/Hotbar
@onready var chat_box:    Control = $ChatBox

var _minimap:      Control       = null
var _minimap_dot:  ColorRect     = null
var _remote_dots:  Dictionary    = {}    # peer_id → ColorRect
var _map_size:     Vector2       = Vector2.ZERO


func _ready() -> void:
	chat_box.visible = false
	_build_minimap()
	_fix_hotbar_position()


func _fix_hotbar_position() -> void:
	if hotbar:
		var sz: Vector2 = get_viewport().get_visible_rect().size
		hotbar.layout_mode = 0
		hotbar.position = Vector2(sz.x / 2.0 - 120.0, sz.y - 58.0)


# ------------------------------------------------------------------ minimap
func _build_minimap() -> void:
	_minimap = Control.new()
	_minimap.name = "Minimap"
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.anchor_left   = 1.0
	_minimap.anchor_right  = 1.0
	_minimap.anchor_top    = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left   = -212
	_minimap.offset_top    = -129
	_minimap.offset_right  = -12
	_minimap.offset_bottom = -12
	add_child(_minimap)

	# Load map texture and get world size
	var file := FileAccess.open(MAP_IMAGE_PATH, FileAccess.READ)
	if file:
		var bytes := file.get_buffer(file.get_length())
		var img := Image.new()
		if img.load_png_from_buffer(bytes) == OK:
			_map_size = Vector2(img.get_width(), img.get_height())
			var tex := ImageTexture.create_from_image(img)
			var rect := TextureRect.new()
			rect.texture = tex
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_SCALE
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_minimap.add_child(rect)

	# Player position dot
	_minimap_dot = ColorRect.new()
	_minimap_dot.name = "PlayerDot"
	_minimap_dot.color = Color.RED
	_minimap_dot.custom_minimum_size = Vector2(5, 5)
	_minimap_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(_minimap_dot)


func _process(_delta: float) -> void:
	if _map_size == Vector2.ZERO:
		return

	var sx: float = _minimap.size.x / _map_size.x
	var sy: float = _minimap.size.y / _map_size.y
	var seen_ids: Array = []

	for node in get_tree().get_nodes_in_group("players"):
		if not (node is CharacterBody2D):
			continue
		var pid: int = node.name.to_int()
		seen_ids.append(pid)

		if node.is_multiplayer_authority():
			# Local player — red dot
			if _minimap_dot:
				_minimap_dot.position = Vector2(node.global_position.x * sx - 2.0,
				                                node.global_position.y * sy - 2.0)
		else:
			# Remote player — light blue dot
			var dot: ColorRect = _remote_dots.get(pid, null)
			if dot == null:
				dot = _make_remote_dot()
				_remote_dots[pid] = dot
			dot.position = Vector2(node.global_position.x * sx - 2.0,
			                       node.global_position.y * sy - 2.0)

	# Remove dots for players that left
	for pid in _remote_dots.keys():
		if not seen_ids.has(pid):
			var dot: ColorRect = _remote_dots[pid]
			dot.queue_free()
			_remote_dots.erase(pid)


func _make_remote_dot() -> ColorRect:
	var dot := ColorRect.new()
	dot.color = Color(0.3, 0.7, 1.0, 0.9)  # light blue
	dot.custom_minimum_size = Vector2(5, 5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(dot)
	return dot


func _get_local_player() -> CharacterBody2D:
	for node in get_tree().get_nodes_in_group("players"):
		if node is CharacterBody2D and node.is_multiplayer_authority():
			return node
	return null


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_chat"):
		chat_box.visible = not chat_box.visible
		if chat_box.visible:
			chat_box.get_node("LineEdit").grab_focus()

	# Left-click on minimap → move player to that world position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _minimap and _minimap.get_global_rect().has_point(event.global_position):
			var local: Vector2 = event.global_position - _minimap.global_position
			var wx: float = (local.x / _minimap.size.x) * _map_size.x
			var wy: float = (local.y / _minimap.size.y) * _map_size.y
			var player := _get_local_player()
			if player:
				player._target = Vector2(wx, wy)
				player._target_set = true
			get_viewport().set_input_as_handled()


func set_health(value: float, max_value: float) -> void:
	health_bar.max_value = max_value
	health_bar.value = value


func set_stamina(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
