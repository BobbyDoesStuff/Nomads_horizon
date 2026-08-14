extends CanvasLayer
## HUD overlay — health, hotbar, minimap, and chat toggle.

const MAP_IMAGE_PATH := "res://assets/tiles/background.png"
const WATER_MINIMAP_SHADER := preload("res://assets/shaders/water_minimap.gdshader")
const TOOL_NAMES := ["", "sword", "axe", "pickaxe", "hammer", "showel", "fishingpole", "watercan", "shield"]
const ICON_FRAME := 460

@onready var health_bar:  ProgressBar = $MarginContainer/HBoxContainer/LeftPanel/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/HBoxContainer/LeftPanel/StaminaBar
@onready var wood_label:  Label = $MarginContainer/HBoxContainer/LeftPanel/WoodLabel
@onready var hotbar:      HBoxContainer = $MarginContainer/HBoxContainer/CenterPanel/Hotbar
@onready var chat_box:    Control = $ChatBox

var _minimap:      Control       = null
var _minimap_dot:  ColorRect     = null
var _remote_dots:  Dictionary    = {}    # peer_id → ColorRect
var _map_size:     Vector2       = Vector2.ZERO
var _hotbar_styles: Array = []
var _last_tool:     int   = -2


func _ready() -> void:
	chat_box.visible = false
	chat_box.add_to_group("chat_box")
	_build_minimap()
	_build_hotbar()
	_fix_hotbar_position()


func _fix_hotbar_position() -> void:
	if hotbar:
		var sz: Vector2 = get_viewport().get_visible_rect().size
		hotbar.layout_mode = 0
		# Center on screen. The hotbar's parent (CenterPanel) is offset ~192px by
		# the 180px left panel + 12px margin, so subtract it. 9 slots = 464px wide.
		hotbar.position = Vector2(sz.x / 2.0 - 424.0, sz.y - 58.0)


# Build 9 slots: empty hands + 8 tools, each with an icon.
func _build_hotbar() -> void:
	for child in hotbar.get_children():
		child.queue_free()
	_hotbar_styles.clear()
	for i in TOOL_NAMES.size():
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(48, 48)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.2, 0.85)
		style.set_border_width_all(2)
		style.border_color = Color(0.35, 0.35, 0.45, 1)
		slot.add_theme_stylebox_override("panel", style)
		_hotbar_styles.append(style)

		var icon := TextureRect.new()
		icon.texture = _tool_icon(TOOL_NAMES[i])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		hotbar.add_child(slot)
	_update_hotbar_selection()


func _tool_icon(tool: String) -> Texture2D:
	var path := "res://assets/sprites/spr_idle_%s.png" % (tool if tool != "" else "none")
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
		return null
	var region := img.get_region(Rect2i(0, 0, ICON_FRAME, ICON_FRAME))
	return ImageTexture.create_from_image(region)


func _update_hotbar_selection() -> void:
	for i in _hotbar_styles.size():
		var style: StyleBoxFlat = _hotbar_styles[i]
		style.border_color = Color(1.0, 0.9, 0.3, 1) if (i - 1 == _last_tool) else Color(0.35, 0.35, 0.45, 1)


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
			var water_mat := ShaderMaterial.new()
			water_mat.shader = WATER_MINIMAP_SHADER
			rect.material = water_mat
			_minimap.add_child(rect)

	# Player position dot
	_minimap_dot = ColorRect.new()
	_minimap_dot.name = "PlayerDot"
	_minimap_dot.color = Color.RED
	_minimap_dot.custom_minimum_size = Vector2(5, 5)
	_minimap_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(_minimap_dot)

	# Border — separates the minimap from the identical world background
	var border := Panel.new()
	border.name = "Border"
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.set_border_width_all(2)
	border_style.border_color = Color(0.85, 0.85, 0.85, 1)
	border.add_theme_stylebox_override("panel", border_style)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_minimap.add_child(border)


func _process(_delta: float) -> void:
	# Update stamina bar from the local player.
	var local := _get_local_player()
	if local:
		set_stamina(local.stamina, local.max_stamina)
		set_health(local.health, local.max_health)
		wood_label.text = "Wood: %d" % local.wood
		if local._current_tool != _last_tool:
			_last_tool = local._current_tool
			_update_hotbar_selection()

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
		var line_edit: LineEdit = chat_box.get_node("LineEdit")
		if not line_edit.has_focus():
			chat_box.visible = true
			line_edit.grab_focus()
			get_viewport().set_input_as_handled()
		return

	# Right-click on minimap → move player to that world position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _minimap and _minimap.get_global_rect().has_point(event.global_position):
			var local: Vector2 = event.global_position - _minimap.global_position
			var wx: float = (local.x / _minimap.size.x) * _map_size.x
			var wy: float = (local.y / _minimap.size.y) * _map_size.y
			var player := _get_local_player()
			if player:
				player.move_to(Vector2(wx, wy))
			get_viewport().set_input_as_handled()


func set_health(value: float, max_value: float) -> void:
	health_bar.max_value = max_value
	health_bar.value = value


func set_stamina(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
