extends CharacterBody2D
## Player — WASD + right-click-to-move. 8-directional isometric sprite.

@export var speed: float = 250.0

var _target:         Vector2
var _target_set:     bool    = false
var _remote_pos:     Vector2
var _sync_timer:     float   = 0.0
var _facing_dir:     int     = 0       # 0-7, remembered during idle
var _current_anim:   String  = ""

# ------------------------------------------------------------------ direction constants
# Row order in the sprite sheet (top to bottom):
#   0=S(down)  1=SW(down-left)  2=W(left)  3=NW(up-left)
#   4=N(up)    5=NE(up-right)   6=E(right)  7=SE(down-right)
# NOTE: the actual sprite sheet is rotated 180 deg relative to the
# labels — row 0 shows N(up), row 2 shows E(right), etc.
#
# Godot angle convention: 0=right(E), PI/2=down(S), PI=left(W), -PI/2=up(N)
const SECTOR_TO_ROW := [2, 3, 4, 5, 6, 7, 0, 1]
# sector:             0=E 1=SE 2=S 3=SW 4=W 5=NW 6=N 7=NE
# mapped (180 deg rot):2=E 3=SE 4=S 5=SW 6=W 7=NW 0=N 1=NE

const WALK_ROW_OFFSET := 0   # both sheets share the same rotation, no relative offset

const ANIM_WALK := [
	"walk_down", "walk_down_left", "walk_left", "walk_up_left",
	"walk_up", "walk_up_right", "walk_right", "walk_down_right",
]
const ANIM_IDLE := [
	"idle_down", "idle_down_left", "idle_left", "idle_up_left",
	"idle_up", "idle_up_right", "idle_right", "idle_down_right",
]

const FRAME_W := 128
const FRAME_H := 160
const WALK_FRAMES := 8
const DIR_COUNT   := 8


func _ready() -> void:
	_remote_pos = global_position
	await get_tree().process_frame
	_target = global_position
	_target_set = true

	_setup_sprite_frames()
	_setup_name_label()
	_setup_camera()

	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server:
		_tell_server_ready()


# ------------------------------------------------------------------ camera
func _setup_camera() -> void:
	var is_local := multiplayer.multiplayer_peer == null or is_multiplayer_authority()
	if not is_local:
		return
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.position_smoothing_enabled = false
	cam.make_current()
	add_child(cam)


# ------------------------------------------------------------------ sprite setup
func _setup_sprite_frames() -> void:
	var sf := SpriteFrames.new()
	var walk_img := _load_png("res://assets/sprites/spr_normal_walk.png")
	var idle_img := _load_png("res://assets/sprites/spr_normal_idle.png")
	if walk_img == null or idle_img == null:
		push_error("[Player] Missing sprite sheets")
		return
	var walk_tex := ImageTexture.create_from_image(walk_img)
	var idle_tex := ImageTexture.create_from_image(idle_img)

	for row in DIR_COUNT:
		sf.add_animation(ANIM_WALK[row])
		sf.set_animation_speed(ANIM_WALK[row], 10.0)
		sf.set_animation_loop(ANIM_WALK[row], true)
		for col in WALK_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = walk_tex
			at.region = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
			sf.add_frame(ANIM_WALK[row], at)

		sf.add_animation(ANIM_IDLE[row])
		sf.set_animation_speed(ANIM_IDLE[row], 4.0)
		sf.set_animation_loop(ANIM_IDLE[row], true)
		var at := AtlasTexture.new()
		at.atlas = idle_tex
		at.region = Rect2(0, row * FRAME_H, FRAME_W, FRAME_H)
		sf.add_frame(ANIM_IDLE[row], at)

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.sprite_frames = sf
	_current_anim = ANIM_IDLE[0]
	sprite.play(_current_anim)


func _load_png(path: String) -> Image:
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


func _setup_name_label() -> void:
	var label: Label = $NameLabel
	label.text = str(multiplayer.get_unique_id()) if multiplayer.multiplayer_peer != null else "You"
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		label.text = "P" + label.text


# ------------------------------------------------------------------ direction helpers
func _get_dir_index(vec: Vector2) -> int:
	if vec.length_squared() < 0.5:
		return -1
	var angle := vec.angle()
	if angle < 0.0:
		angle += TAU
	var sector := posmod(int(round(angle / (TAU / 8.0))), 8)
	return SECTOR_TO_ROW[sector]


func _play_anim(anim: String) -> void:
	if anim != _current_anim:
		_current_anim = anim
		var sprite: AnimatedSprite2D = $AnimatedSprite2D
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)


# ------------------------------------------------------------------ network
func _tell_server_ready() -> void:
	for i in 10:
		var world := get_parent()
		if world and world.has_method("_new_client_ready"):
			world._new_client_ready.rpc_id(1)
			return
		await get_tree().create_timer(0.1).timeout
	print("[Player] Warning: could not send ready signal to server")


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not _target_set:
		return

	if not is_multiplayer_authority():
		# Remote player — interpolate, use synced _facing_dir
		global_position = global_position.lerp(_remote_pos, 0.25)
		var moving := _remote_pos.distance_to(global_position) > 4.0
		if moving:
			_play_anim(ANIM_WALK[(_facing_dir + WALK_ROW_OFFSET) % DIR_COUNT])
		else:
			_play_anim(ANIM_IDLE[_facing_dir])
		return

	# ---- local / authority ----
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector2.ZERO

	if input != Vector2.ZERO:
		_target = global_position
		dir = input
		velocity = dir * speed
	else:
		var to_target := _target - global_position
		var dist := to_target.length()
		# Threshold must be >1 frame of movement to catch WASD release,
		# where _target lags behind and points opposite to movement.
		var stop_dist := maxf(2.0, speed * delta * 1.5)
		if dist > stop_dist:
			dir = to_target / dist
			velocity = dir * minf(speed, dist / delta)
		else:
			_target = global_position
			velocity = Vector2.ZERO

	var idx := _get_dir_index(dir)
	if idx >= 0:
		_facing_dir = idx
		_play_anim(ANIM_WALK[(idx + WALK_ROW_OFFSET) % DIR_COUNT])
	else:
		_play_anim(ANIM_IDLE[_facing_dir])


	move_and_slide()

	# Clamp to map bounds
	var world := get_parent()
	if world and world.has_method("is_in_bounds") and not world.is_in_bounds(global_position):
		global_position.x = clampf(global_position.x, 0, world._map_bounds.size.x)
		global_position.y = clampf(global_position.y, 0, world._map_bounds.size.y)

	# Position sync to server (20x / sec)
	_sync_timer += delta
	if _sync_timer > 0.05 and multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		_sync_timer = 0.0
		if world and world.has_method("recv_position"):
			if NetworkManager.is_server:
				world._broadcast_position.rpc(name.to_int(), global_position, _facing_dir)
			else:
				world.recv_position.rpc_id(1, multiplayer.get_unique_id(), global_position, _facing_dir)


# ------------------------------------------------------------------ input
func _is_click_on_minimap(screen_pos: Vector2) -> bool:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var mm_right: float  = vs.x - 12.0
	var mm_bottom: float = vs.y - 12.0
	var mm_left: float   = mm_right - 200.0
	var mm_top: float    = mm_bottom - 117.0
	return screen_pos.x >= mm_left and screen_pos.x <= mm_right and \
	       screen_pos.y >= mm_top  and screen_pos.y <= mm_bottom


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _is_click_on_minimap(event.global_position):
			return  # let the HUD handle minimap clicks
		var click_pos := get_global_mouse_position()
		var world := get_parent()
		if world and world.has_method("is_in_bounds") and world.is_in_bounds(click_pos):
			_target = click_pos
			_target_set = true
	if event.is_action_pressed("ui_cancel"):
		if multiplayer.multiplayer_peer != null:
			NetworkManager.close_connection()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
