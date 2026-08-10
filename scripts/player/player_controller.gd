extends CharacterBody2D
## Player — WASD + right-click-to-move. 8-directional isometric sprite.

@export var speed: float = 250.0

var _target:         Vector2
var _target_set:     bool    = false
var _remote_pos:     Vector2
var _prev_remote_pos: Vector2  # for deriving remote movement direction
var _remote_dir:     Vector2  # last known remote movement direction
var _sync_timer:     float   = 0.0
var _ready_sent:     bool    = false
var _facing_dir:     int     = 0       # 0-7, remembered during idle
var _current_anim:   String  = ""      # track to avoid restarting every frame

# ------------------------------------------------------------------ direction constants
# Row order in the sprite sheet (top to bottom):
#   0=S(down)  1=SW(down-left)  2=W(left)  3=NW(up-left)
#   4=N(up)    5=NE(up-right)   6=E(right)  7=SE(down-right)
#
# Godot angle convention: 0=right(E), PI/2=down(S), PI=left(W), -PI/2=up(N)
# Mapping from godot-angle-sector to sprite-sheet row:
const SECTOR_TO_ROW := [6, 7, 0, 1, 2, 3, 4, 5]
# sector:             0=E 1=SE 2=S 3=SW 4=W 5=NW 6=N 7=NE
# mapped:             6=E 7=SE 0=S 1=SW 2=W 3=NW 4=N 5=NE
const WALK_ROW_OFFSET := 4  # walk rows are rotated 180° vs idle rows in the sheet

const DIR_NAMES := [
	"walk_down",         # 0
	"walk_down_left",    # 1
	"walk_left",         # 2
	"walk_up_left",      # 3
	"walk_up",           # 4
	"walk_up_right",     # 5
	"walk_right",        # 6
	"walk_down_right",   # 7
]

const IDLE_NAMES := [
	"idle_down",
	"idle_down_left",
	"idle_left",
	"idle_up_left",
	"idle_up",
	"idle_up_right",
	"idle_right",
	"idle_down_right",
]

const FRAME_W := 128
const FRAME_H := 160
const WALK_FRAMES := 8
const DIR_COUNT   := 8


func _ready() -> void:
	_remote_pos = global_position
	_prev_remote_pos = global_position
	# Defer target init so game_world can set our position first
	await get_tree().process_frame
	_target = global_position
	_target_set = true

	_setup_sprite_frames()
	_setup_name_label()

	# Tell the server we're ready (client-side only)
	if multiplayer.multiplayer_peer != null and not NetworkManager.is_server:
		_tell_server_ready()


# ------------------------------------------------------------------ sprite setup
func _setup_sprite_frames() -> void:
	var sf := SpriteFrames.new()

	# Load PNGs from raw file bytes (bypasses Godot import system)
	var walk_img := _load_png("res://assets/sprites/spr_normal_walk.png")
	var idle_img := _load_png("res://assets/sprites/spr_normal_idle.png")

	if walk_img == null or idle_img == null:
		push_error("[Player] Missing sprite sheets — check assets/sprites/")
		return

	var walk_tex := ImageTexture.create_from_image(walk_img)
	var idle_tex := ImageTexture.create_from_image(idle_img)

	for row in DIR_COUNT:
		# ---- walk animation (8 frames per row) ----
		sf.add_animation(DIR_NAMES[row])
		sf.set_animation_speed(DIR_NAMES[row], 10.0)
		sf.set_animation_loop(DIR_NAMES[row], true)
		for col in WALK_FRAMES:
			var atlas := AtlasTexture.new()
			atlas.atlas = walk_tex
			atlas.region = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
			sf.add_frame(DIR_NAMES[row], atlas)

		# ---- idle animation (1 frame per row) ----
		sf.add_animation(IDLE_NAMES[row])
		sf.set_animation_speed(IDLE_NAMES[row], 4.0)
		sf.set_animation_loop(IDLE_NAMES[row], true)
		var atlas := AtlasTexture.new()
		atlas.atlas = idle_tex
		atlas.region = Rect2(0, row * FRAME_H, FRAME_W, FRAME_H)
		sf.add_frame(IDLE_NAMES[row], atlas)

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.sprite_frames = sf
	_current_anim = IDLE_NAMES[0]
	sprite.play(_current_anim)


func _load_png(path: String) -> Image:
	## Reads a PNG from disk via FileAccess (no .import file needed).
	if not FileAccess.file_exists(path):
		push_error("[Player] File not found: " + path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[Player] Cannot open: " + path)
		return null
	var bytes := file.get_buffer(file.get_length())
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("[Player] Failed to decode PNG: " + path)
		return null
	return img


func _setup_name_label() -> void:
	var label: Label = $NameLabel
	label.text = str(multiplayer.get_unique_id()) if multiplayer.multiplayer_peer != null else "You"
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		label.text = "P" + label.text


# ------------------------------------------------------------------ direction helpers
func _get_dir_index(vec: Vector2) -> int:
	## Returns 0-7 for the 8 sprite-sheet rows, or -1 when still.
	if vec.length_squared() < 0.5:
		return -1
	var angle := vec.angle()
	if angle < 0.0:
		angle += TAU
	var sector := posmod(int(round(angle / (TAU / 8.0))), 8)
	return SECTOR_TO_ROW[sector]


func _update_animation(vec: Vector2) -> void:
	var dir := _get_dir_index(vec)
	var desired: String
	if dir >= 0:
		_facing_dir = dir
		# Walk sprite sheet rows are offset from idle rows by 4 (180°)
		desired = DIR_NAMES[(dir + WALK_ROW_OFFSET) % DIR_COUNT]
	else:
		desired = IDLE_NAMES[_facing_dir]

	# Only switch if the animation actually changed — prevents restarting every frame
	if desired != _current_anim:
		_current_anim = desired
		var sprite: AnimatedSprite2D = $AnimatedSprite2D
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(desired):
			sprite.play(desired)


# ------------------------------------------------------------------ network
func _tell_server_ready() -> void:
	for i in 10:
		var world := get_parent()
		if world and world.has_method("_new_client_ready"):
			world._new_client_ready.rpc_id(1)
			_ready_sent = true
			return
		await get_tree().create_timer(0.1).timeout
	print("[Player] Warning: could not send ready signal to server")


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Remote player — interpolate position, use synced facing
		global_position = global_position.lerp(_remote_pos, 0.25)

		var moving := _remote_pos.distance_to(global_position) > 4.0
		var desired: String
		if moving:
			desired = DIR_NAMES[(_facing_dir + WALK_ROW_OFFSET) % DIR_COUNT]
		else:
			desired = IDLE_NAMES[_facing_dir]

		if desired != _current_anim:
			_current_anim = desired
			var sprite: AnimatedSprite2D = $AnimatedSprite2D
			if sprite.sprite_frames and sprite.sprite_frames.has_animation(desired):
				sprite.play(desired)
		return

	# ---- local / authority ----
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input != Vector2.ZERO:
		_target = global_position
		_target_set = true
		velocity = input * speed
	else:
		var dist := _target - global_position
		if dist.length() > 4.0:
			velocity = dist.normalized() * speed
		else:
			velocity = Vector2.ZERO

	_update_animation(velocity)
	move_and_slide()

	# Position sync to server (20× / sec)
	_sync_timer += delta
	if _sync_timer > 0.05 and multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		_sync_timer = 0.0
		var world := get_parent()
		if world and world.has_method("recv_position"):
			if NetworkManager.is_server:
				world._broadcast_position.rpc(name.to_int(), global_position, _facing_dir)
			else:
				world.recv_position.rpc_id(1, multiplayer.get_unique_id(), global_position, _facing_dir)


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Right-click to move
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_target = get_global_mouse_position()
		_target_set = true
	if event.is_action_pressed("ui_cancel"):
		if multiplayer.multiplayer_peer != null:
			NetworkManager.close_connection()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
