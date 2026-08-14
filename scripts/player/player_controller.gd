extends CharacterBody2D
## Player — WASD + right-click-to-move. 8-directional isometric sprite.

@export var speed: float = 250.0
@export var sprint_speed: float = 400.0
@export var max_stamina: float = 100.0
@export var stamina_drain: float = 25.0   # per second while sprinting
@export var stamina_regen: float = 20.0   # per second while not sprinting
@export var max_health: float = 100.0

var stamina: float = 0.0
var health: float = 0.0

var _target:         Vector2
var _target_set:     bool    = false
var _snap_pos:       Array[Vector2] = []
var _snap_time:      Array[float]   = []
var _remote_vel:     Vector2
var _sync_timer:     float   = 0.0
var _facing_dir:     int     = 0       # 0-7, remembered during idle
var _current_anim:   String  = ""
var _bubble:         Label   = null
var _bubble_timer:   Timer   = null
var _attacking:      bool    = false
var _attack_cooldown: float  = 0.0
var _slash:          Line2D = null
var _time_since_damage: float      = 0.0
var _healthbar:          ProgressBar = null

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

# Inverse of SECTOR_TO_ROW — maps a facing row back to an on-screen direction.
const ROW_TO_SECTOR := [6, 7, 0, 1, 2, 3, 4, 5]
const ATTACK_DURATION := 0.25
const ATTACK_COOLDOWN := 0.5
const ATTACK_DAMAGE := 10.0
const ATTACK_RANGE := 60.0
const ATTACK_ARC := 1.2       # half-angle of the swing (radians)
const REGEN_DELAY := 5.0      # seconds of no damage before regen starts
const REGEN_RATE := 10.0      # hp restored per second
const INTERP_DELAY := 0.1     # render remote players this far in the past (s)
const SNAP_LIFETIME := 1.0    # discard snapshots older than this (s)


func _ready() -> void:
	add_snapshot(global_position)
	await get_tree().process_frame
	_target = global_position
	_target_set = true
	stamina = max_stamina
	health = max_health

	_setup_sprite_frames()
	_setup_name_label()
	_setup_chat_bubble()
	_setup_attack()
	_setup_healthbar()
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
	# Center the name horizontally over the player's head.
	label.size = Vector2(120, 18)
	label.position = Vector2(-60, -116)


func _setup_chat_bubble() -> void:
	_bubble = get_node_or_null("ChatBubble")
	if _bubble == null:
		return
	_bubble_timer = Timer.new()
	_bubble_timer.one_shot = true
	_bubble_timer.wait_time = 4.0
	_bubble_timer.timeout.connect(_on_bubble_timeout)
	add_child(_bubble_timer)


func show_chat_bubble(text: String) -> void:
	if _bubble == null:
		return
	_bubble.text = text
	_bubble.visible = true
	_bubble_timer.start()


func _on_bubble_timeout() -> void:
	if _bubble:
		_bubble.visible = false


func _setup_attack() -> void:
	_slash = Line2D.new()
	_slash.name = "Slash"
	_slash.width = 6.0
	_slash.default_color = Color(1.0, 0.95, 0.6, 1.0)
	_slash.joint_mode = Line2D.LINE_JOINT_ROUND
	_slash.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_slash.end_cap_mode = Line2D.LINE_CAP_ROUND
	_slash.position = Vector2(0, -40)
	_slash.visible = false
	_slash.z_index = 5
	# Arc swept from -1 to +1 rad, radius 55.
	var pts := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var a: float = -1.0 + 2.0 * float(i) / float(steps)
		pts.append(Vector2(cos(a), sin(a)) * 55.0)
	_slash.points = pts
	add_child(_slash)


func _facing_vector() -> Vector2:
	return Vector2.from_angle(ROW_TO_SECTOR[_facing_dir] * TAU / 8.0)


func _start_attack() -> void:
	if _attacking or _attack_cooldown > 0.0:
		return
	_attacking = true
	_attack_cooldown = ATTACK_COOLDOWN
	_play_attack_visual()
	_sync_attack()
	_do_attack_hit()


# Called by remote players via RPC to replay this player's attack.
func play_attack_animation(facing: int = -1) -> void:
	if facing >= 0:
		_facing_dir = facing
	_play_attack_visual()


func _play_attack_visual() -> void:
	var facing := _facing_vector()
	_slash.rotation = facing.angle()
	_slash.modulate.a = 1.0
	_slash.visible = true

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var base_pos: Vector2 = sprite.position

	# Quick lunge toward the facing direction and back.
	var lunge := create_tween()
	lunge.tween_property(sprite, "position", base_pos + facing * 26.0, 0.05)
	lunge.tween_property(sprite, "position", base_pos, 0.10)

	# Fade the slash arc out over the attack, then finish.
	var fade := create_tween()
	fade.tween_property(_slash, "modulate:a", 0.0, ATTACK_DURATION)
	fade.tween_callback(func() -> void:
		_slash.visible = false
		_attacking = false
	)


func _sync_attack() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.get_peers().size() == 0:
		return
	var world := get_parent()
	if world and world.has_method("recv_attack"):
		var pid := name.to_int()
		if NetworkManager.is_server:
			world._broadcast_attack.rpc(pid, _facing_dir)
		else:
			world.recv_attack.rpc_id(1, pid, _facing_dir)


func _setup_healthbar() -> void:
	_healthbar = ProgressBar.new()
	_healthbar.name = "HealthBar"
	_healthbar.max_value = max_health
	_healthbar.value = health
	_healthbar.show_percentage = false
	_healthbar.size = Vector2(60, 8)
	_healthbar.position = Vector2(-30, -98)
	_healthbar.visible = true
	_healthbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.85, 0.35, 1.0)
	_healthbar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	_healthbar.add_theme_stylebox_override("background", bg)
	add_child(_healthbar)


func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	_time_since_damage = 0.0
	_show_damage(amount)


func receive_damage(damage: float, new_health: float) -> void:
	health = clampf(new_health, 0.0, max_health)
	_show_damage(damage)


func set_health(value: float) -> void:
	health = clampf(value, 0.0, max_health)


func tick_regen(delta: float) -> void:
	_time_since_damage += delta
	if _time_since_damage >= REGEN_DELAY and health < max_health:
		health = minf(max_health, health + REGEN_RATE * delta)


func _show_damage(damage: float) -> void:
	_flash_damage()
	_spawn_damage_number(damage)


func _spawn_damage_number(amount: float) -> void:
	var label := Label.new()
	label.text = "-%d" % int(round(amount))
	label.size = Vector2(60, 22)
	label.position = Vector2(-30 + randf_range(-12.0, 12.0), -140)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.25))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 10
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 46.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.finished.connect(label.queue_free)


func _flash_damage() -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3), 0.08)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), 0.2)


func _process(_delta: float) -> void:
	# Keep the always-visible overhead bar in sync with `health`.
	if _healthbar:
		_healthbar.max_value = max_health
		_healthbar.value = health


func _do_attack_hit() -> void:
	if multiplayer.multiplayer_peer == null:
		return  # solo: no other players to hit
	var facing := _facing_vector()
	for node in get_tree().get_nodes_in_group("players"):
		if node == self:
			continue
		var offset: Vector2 = node.global_position - global_position
		if offset.length() > ATTACK_RANGE:
			continue
		if offset.normalized().dot(facing) < cos(ATTACK_ARC):
			continue
		_send_damage(node.name.to_int(), ATTACK_DAMAGE)


func _send_damage(victim_id: int, damage: float) -> void:
	var world := get_parent()
	if not world or not world.has_method("recv_damage"):
		return
	if NetworkManager.is_server:
		world._apply_damage(victim_id, damage)
	else:
		world.recv_damage.rpc_id(1, victim_id, damage)


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


func _is_typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


# ------------------------------------------------------------------ network
func _tell_server_ready() -> void:
	for i in 10:
		var world := get_parent()
		if world and world.has_method("_new_client_ready"):
			world._new_client_ready.rpc_id(1)
			return
		await get_tree().create_timer(0.1).timeout
	print("[Player] Warning: could not send ready signal to server")


# ------------------------------------------------------------------ snapshot interpolation
func add_snapshot(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_snap_pos.append(pos)
	_snap_time.append(now)
	# Prune old snapshots, keeping at least two for interpolation.
	var cutoff := now - SNAP_LIFETIME
	while _snap_pos.size() > 2 and _snap_time[0] < cutoff:
		_snap_pos.pop_front()
		_snap_time.pop_front()


func _interpolate_position() -> Vector2:
	if _snap_pos.is_empty():
		return global_position
	var render_time := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	if _snap_pos.size() == 1 or render_time <= _snap_time[0]:
		return _snap_pos[0]
	if render_time >= _snap_time[-1]:
		return _snap_pos[-1]
	for i in _snap_pos.size() - 1:
		if render_time <= _snap_time[i + 1]:
			var t0 := _snap_time[i]
			var t1 := _snap_time[i + 1]
			var f := (render_time - t0) / (t1 - t0)
			return _snap_pos[i].lerp(_snap_pos[i + 1], f)
	return _snap_pos[-1]


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not _target_set:
		return

	if not is_multiplayer_authority():
		# Remote player — render the interpolated position from the snapshot buffer.
		global_position = _interpolate_position()
		if _remote_vel.length_squared() > 25.0:
			_play_anim(ANIM_WALK[(_facing_dir + WALK_ROW_OFFSET) % DIR_COUNT])
		else:
			_play_anim(ANIM_IDLE[_facing_dir])
		return

	# While typing in chat, stand still.
	if _is_typing():
		velocity = Vector2.ZERO
		_play_anim(ANIM_IDLE[_facing_dir])
		return

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# While attacking, stand still and let the animation play.
	if _attacking:
		velocity = Vector2.ZERO
		_play_anim(ANIM_IDLE[_facing_dir])
		return

	# ---- local / authority ----
	var sprinting := Input.is_action_pressed("sprint") and stamina > 0.0
	var move_speed := sprint_speed if sprinting else speed

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector2.ZERO

	if input != Vector2.ZERO:
		_target = global_position
		dir = input
		velocity = dir * move_speed
	else:
		var to_target := _target - global_position
		var dist := to_target.length()
		# Threshold must be >1 frame of movement to catch WASD release,
		# where _target lags behind and points opposite to movement.
		var stop_dist := maxf(2.0, move_speed * delta * 1.5)
		if dist > stop_dist:
			dir = to_target / dist
			velocity = dir * minf(move_speed, dist / delta)
		else:
			_target = global_position
			velocity = Vector2.ZERO

	# Drain stamina while sprinting-and-moving; regenerate otherwise.
	if sprinting and dir != Vector2.ZERO:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
	else:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)

	var idx := _get_dir_index(dir)
	if idx >= 0:
		_facing_dir = idx
		_play_anim(ANIM_WALK[(idx + WALK_ROW_OFFSET) % DIR_COUNT])
	else:
		_play_anim(ANIM_IDLE[_facing_dir])

	# Only move when actually moving. Calling move_and_slide() while idle runs
	# collision recovery, which lets a nearby moving player shove us around.
	if velocity != Vector2.ZERO:
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
				world._broadcast_position.rpc(name.to_int(), global_position, velocity, _facing_dir)
			else:
				world.recv_position.rpc_id(1, multiplayer.get_unique_id(), global_position, velocity, _facing_dir)


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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _is_typing():
			_start_attack()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _is_click_on_minimap(event.global_position):
			return  # let the HUD handle minimap clicks
		var click_pos := get_global_mouse_position()
		var world := get_parent()
		if world and world.has_method("is_in_bounds") and world.is_in_bounds(click_pos):
			_target = click_pos
			_target_set = true
	if event.is_action_pressed("ui_cancel"):
		# Escape closes chat first if it's open; otherwise exit to menu.
		var chat: Control = get_tree().get_first_node_in_group("chat_box")
		if chat and chat.visible:
			chat.visible = false
			var line_edit: LineEdit = chat.get_node_or_null("LineEdit")
			if line_edit:
				line_edit.release_focus()
			get_viewport().set_input_as_handled()
			return
		if multiplayer.multiplayer_peer != null:
			NetworkManager.close_connection()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
