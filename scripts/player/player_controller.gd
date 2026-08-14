extends CharacterBody2D
## Player — WASD + right-click-to-move. 8-directional isometric sprite.

@export var speed: float = 250.0
@export var sprint_speed: float = 400.0
@export var max_stamina: float = 100.0
@export var stamina_drain: float = 25.0   # per second while sprinting
@export var stamina_regen: float = 20.0   # per second while not sprinting
@export var max_health: float = 100.0

const SUBMERGE_SHADER := preload("res://assets/shaders/player_submerge.gdshader")

var stamina: float = 0.0
var health: float = 0.0

var _target:         Vector2
var _path:           Array   = []
var _path_idx:       int     = 0
var _stuck_time:     float   = 0.0
var _stuck_at:       Vector2
var _ripple_timer:   float   = 0.0
var _submerge_mat:   ShaderMaterial = null
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
var _channeling:     bool    = false
var _current_tool:   int     = -1    # -1 = no tool (default)
var wood:            int     = 0     # wood gathered (inventory)
var _nearby_tree:    Node    = null  # tree within chop range (axe equipped)
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
const SECTOR_TO_ROW := [6, 7, 0, 1, 2, 3, 4, 5]
# sector:             0=E 1=SE 2=S 3=SW 4=W 5=NW 6=N 7=NE
# mapped (no rotation):6=E 7=SE 0=S 1=SW 2=W 3=NW 4=N 5=NE

const WALK_ROW_OFFSET := 0   # both sheets share the same rotation, no relative offset

const ANIM_WALK := [
	"walk_down", "walk_down_left", "walk_left", "walk_up_left",
	"walk_up", "walk_up_right", "walk_right", "walk_down_right",
]
const ANIM_IDLE := [
	"idle_down", "idle_down_left", "idle_left", "idle_up_left",
	"idle_up", "idle_up_right", "idle_right", "idle_down_right",
]
const ANIM_ATTACK := [
	"attack_down", "attack_down_left", "attack_left", "attack_up_left",
	"attack_up", "attack_up_right", "attack_right", "attack_down_right",
]

const FRAME_W := 460
const FRAME_H := 460
const WALK_FRAMES := 6
const IDLE_FRAMES := 8
const DIR_COUNT   := 8
# Sheet has 5 directions (down, down-left, left, up-left, up); the right side is mirrored.
const DIR_ROW := [0, 1, 2, 3, 4, 3, 2, 1]
const DIR_FLIP := [false, false, false, false, false, true, true, true]

const SPRITE_SCALE := 0.4
const SPRITE_FEET_Y := 200.0  # character feet offset within the 460px frame (from centre)
const TOOLS := ["sword", "axe", "pickaxe", "hammer", "showel", "fishingpole", "watercan", "shield"]

# Inverse of SECTOR_TO_ROW — maps a facing row back to an on-screen direction.
const ROW_TO_SECTOR := [2, 3, 4, 5, 6, 7, 0, 1]
const ATTACK_DURATION := 0.45
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
	cam.zoom = Vector2(0.7, 0.7)  # zoomed out so tree progress bars stay visible
	# Clamp the camera to the map so it never shows past the water's edge.
	var world := get_parent()
	if world and world.has_method("is_in_bounds"):
		var bounds: Rect2 = world._map_bounds
		if bounds.size != Vector2.ZERO:
			cam.limit_left = int(bounds.position.x)
			cam.limit_top = int(bounds.position.y)
			cam.limit_right = int(bounds.end.x)
			cam.limit_bottom = int(bounds.end.y)
	add_child(cam)
	cam.make_current()


# ------------------------------------------------------------------ sprite setup
func _setup_sprite_frames() -> void:
	var sf := _build_frames("none", "sword", false, 0)
	if sf == null:
		push_error("[Player] Missing sprite sheets")
		return
	_apply_frames(sf)
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.position = Vector2(0, -SPRITE_FEET_Y * SPRITE_SCALE)
	sprite.animation_finished.connect(_on_animation_finished)
	_submerge_mat = ShaderMaterial.new()
	_submerge_mat.shader = SUBMERGE_SHADER
	sprite.material = _submerge_mat


# Build the SpriteFrames for a tool (pure — runs on a background thread).
func _build_frames(tool: String, attack_sheet: String, loop_attack: bool, frame_count: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	var walk_path := "res://assets/sprites/spr_walk_%s.png" % tool
	var idle_path := "res://assets/sprites/spr_idle_%s.png" % tool
	if not FileAccess.file_exists(walk_path):
		walk_path = "res://assets/sprites/spr_walk_none.png"
	if not FileAccess.file_exists(idle_path):
		idle_path = "res://assets/sprites/spr_idle_none.png"
	var walk_img := _load_png(walk_path)
	var idle_img := _load_png(idle_path)
	var attack_img := _load_png("res://assets/sprites/spr_attack_%s.png" % attack_sheet)
	if walk_img == null or idle_img == null or attack_img == null:
		return null
	var walk_tex := ImageTexture.create_from_image(walk_img)
	var idle_tex := ImageTexture.create_from_image(idle_img)
	var attack_tex := ImageTexture.create_from_image(attack_img)
	var attack_frames := attack_img.get_width() / FRAME_W
	if frame_count > 0:
		attack_frames = frame_count

	for row in DIR_COUNT:
		var sheet_row: int = DIR_ROW[row]  # character sheet row (direction)

		sf.add_animation(ANIM_WALK[row])
		sf.set_animation_speed(ANIM_WALK[row], 10.0)
		sf.set_animation_loop(ANIM_WALK[row], true)
		for f in WALK_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = walk_tex
			at.region = Rect2(f * FRAME_W, sheet_row * FRAME_H, FRAME_W, FRAME_H)
			sf.add_frame(ANIM_WALK[row], at)

		sf.add_animation(ANIM_IDLE[row])
		sf.set_animation_speed(ANIM_IDLE[row], 4.0)
		sf.set_animation_loop(ANIM_IDLE[row], true)
		for f in IDLE_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = idle_tex
			at.region = Rect2(f * FRAME_W, sheet_row * FRAME_H, FRAME_W, FRAME_H)
			sf.add_frame(ANIM_IDLE[row], at)

		sf.add_animation(ANIM_ATTACK[row])
		sf.set_animation_speed(ANIM_ATTACK[row], 11.0)
		sf.set_animation_loop(ANIM_ATTACK[row], loop_attack)
		for f in attack_frames:
			var at := AtlasTexture.new()
			at.atlas = attack_tex
			at.region = Rect2(f * FRAME_W, sheet_row * FRAME_H, FRAME_W, FRAME_H)
			sf.add_frame(ANIM_ATTACK[row], at)

	return sf


# Apply frames to the sprite (main thread only).
func _apply_frames(sf: SpriteFrames) -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.sprite_frames = sf
	sprite.flip_h = bool(DIR_FLIP[_facing_dir])
	_current_anim = ANIM_IDLE[0]
	sprite.play(_current_anim)


func _on_animation_finished() -> void:
	if _channeling:
		return  # sustained action reached its "hold" frame — stay there
	_attacking = false
	_play_anim(ANIM_IDLE[_facing_dir])


func _set_tool(index: int) -> void:
	if index == _current_tool:
		return
	_cancel_chop()  # stop chopping before switching away from the axe
	_current_tool = index
	_channeling = false  # switching tools interrupts any sustained action
	var tool := "none"
	if index >= 0 and index < TOOLS.size():
		tool = TOOLS[index]
	var attack_sheet := _attack_sheet()
	WorkerThreadPool.add_task(_build_frames_task.bind(tool, attack_sheet, index, _action_loop(), _action_frame_count()))


func _build_frames_task(tool: String, attack_sheet: String, index: int, loop_attack: bool, frame_count: int) -> void:
	var sf := _build_frames(tool, attack_sheet, loop_attack, frame_count)
	_apply_frames_deferred.call_deferred(sf, index)


func _apply_frames_deferred(sf: SpriteFrames, index: int) -> void:
	if sf != null and index == _current_tool:
		_apply_frames(sf)


func _attack_sheet() -> String:
	match _current_tool:
		-1, 0: return "sword"       # empty hands or sword
		1: return "axe"
		2: return "pickaxe"
		3: return "hammer"
		4: return "showel"          # dig
		5: return "fishingpole"     # fish
		6: return "watercan"        # water
		7: return "shield"          # block
		_: return "sword"


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
	label.position = Vector2(-60, -170)


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


func _facing_vector() -> Vector2:
	return Vector2.from_angle(ROW_TO_SECTOR[_facing_dir] * TAU / 8.0)


func _start_attack() -> void:
	if _current_tool == 1:  # axe — only chops trees
		_try_chop_tree()
		return
	if _is_channel_tool():
		# Sustained action (dig/fish/water) — toggle and stay in it until interrupted.
		_channeling = not _channeling
		if _channeling:
			_play_anim(ANIM_ATTACK[_facing_dir])
		else:
			_play_anim(ANIM_IDLE[_facing_dir])
		return
	if _attacking or _attack_cooldown > 0.0:
		return
	_attacking = true
	_attack_cooldown = ATTACK_COOLDOWN
	_play_attack_visual()
	_sync_attack()
	_do_attack_hit()


func _is_channel_tool() -> bool:
	return _current_tool >= 4 and _current_tool <= 6  # showel, fishingpole, watercan


func _action_loop() -> bool:
	return _current_tool == 4 or _current_tool == 1  # showel (dig) + axe (chop) loop their swing


func _action_frame_count() -> int:
	if _current_tool == 5:  # fishing: stop after the cast, hold the rod out
		return 6  # full cast — freeze on the final frame (chord stretched in the water)
	return 0  # auto-detect from sheet width


# ------------------------------------------------------------------ tree chopping
func _try_chop_tree() -> void:
	if _nearby_tree == null or not is_instance_valid(_nearby_tree):
		_spawn_float_text("Need to be next to a tree to cut", Color(1.0, 0.9, 0.4))
		return
	if _channeling:
		return  # already chopping
	_channeling = true
	_nearby_tree.start_chop(self)
	_play_anim(ANIM_ATTACK[_facing_dir])


func _on_tree_finished(_tree: Node) -> void:
	# The tree finished being chopped — return to idle.
	_channeling = false
	_nearby_tree = null
	_play_anim(ANIM_IDLE[_facing_dir])


func add_wood(amount: int) -> void:
	wood += amount


func _cancel_chop() -> void:
	if _current_tool == 1 and is_instance_valid(_nearby_tree):
		_nearby_tree.stop_chop()
		_nearby_tree.set_highlighted(false)
	_nearby_tree = null
	_channeling = false


func _update_nearby_tree() -> void:
	# Highlight the nearest tree in range while the axe is out (and not mid-chop).
	if _current_tool != 1 or _channeling:
		return
	var best: Node = null
	var best_d := INF
	for tree in get_tree().get_nodes_in_group("trees"):
		if not is_instance_valid(tree) or not tree.can_be_chopped():
			continue
		var d := global_position.distance_to(tree.global_position)
		if d < tree.near_range and d < best_d:
			best = tree
			best_d = d
	if best != _nearby_tree:
		if is_instance_valid(_nearby_tree):
			_nearby_tree.set_highlighted(false)
		if best != null:
			best.set_highlighted(true)
		_nearby_tree = best


func _spawn_float_text(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.size = Vector2(200, 22)
	label.position = Vector2(-100, -180)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 10
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 44.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tween.finished.connect(label.queue_free)


# Called by remote players via RPC to replay this player's attack.
func play_attack_animation(facing: int = -1) -> void:
	if facing >= 0:
		_facing_dir = facing
	_play_attack_visual()


func _play_attack_visual() -> void:
	_play_anim(ANIM_ATTACK[_facing_dir])


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
	_healthbar.position = Vector2(-30, -152)
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
	label.position = Vector2(-30 + randf_range(-12.0, 12.0), -195)
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
	# Water submersion: hide the body bottom-up based on depth.
	if _submerge_mat:
		var world := get_parent()
		var depth := 0.0
		if world and world.has_method("get_water_depth"):
			depth = world.get_water_depth(global_position)
		_submerge_mat.set_shader_parameter("submersion", depth)
		# Tilt the water line ~20° when facing a diagonal (isometric look).
		var facing := _facing_vector()
		var slope := 0.0
		if absf(facing.x) > 0.4 and absf(facing.y) > 0.4:
			var tilt := tan(deg_to_rad(20.0))
			slope = -tilt if facing.x * facing.y > 0.0 else tilt
		_submerge_mat.set_shader_parameter("water_slope", slope)
		# Hide the name + health bar once the character is fully submerged.
		var submerged := depth >= 0.85
		var name_label := $NameLabel
		if name_label:
			name_label.visible = not submerged
		if _healthbar:
			_healthbar.visible = not submerged


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
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.flip_h = bool(DIR_FLIP[_facing_dir])
	if anim != _current_anim:
		_current_anim = anim
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

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	_update_nearby_tree()

	# While channeling (digging/fishing/watering/chopping), stand still until movement interrupts.
	if _channeling:
		var tree_gone := _current_tool == 1 and not is_instance_valid(_nearby_tree)
		if input != Vector2.ZERO or tree_gone:
			if _current_tool == 1 and is_instance_valid(_nearby_tree):
				_nearby_tree.stop_chop()
			_channeling = false
			_play_anim(ANIM_IDLE[_facing_dir])
		else:
			velocity = Vector2.ZERO
			return

	# While attacking, stand still and let the attack animation play.
	if _attacking:
		velocity = Vector2.ZERO
		return

	# ---- local / authority ----
	var sprinting := Input.is_action_pressed("sprint") and stamina > 0.0
	var move_speed := sprint_speed if sprinting else speed

	var dir := Vector2.ZERO

	if input != Vector2.ZERO:
		# WASD — cancel any path and move directly.
		_path.clear()
		_target = global_position
		dir = input
		velocity = dir * move_speed
	elif not _path.is_empty() and _path_idx < _path.size():
		# Follow grid path waypoints.
		var wp: Vector2 = _path[_path_idx]
		var to_wp: Vector2 = wp - global_position
		var d: float = to_wp.length()
		if global_position.distance_to(_stuck_at) < 16.0:
			_stuck_time += delta
		else:
			_stuck_time = 0.0
			_stuck_at = global_position
		if d < 12.0 or _stuck_time > 1.0:
			_stuck_time = 0.0
			_stuck_at = global_position
			_path_idx += 1
			if _path_idx >= _path.size():
				_path.clear()
				_target = global_position
				velocity = Vector2.ZERO
			else:
				var nwp: Vector2 = _path[_path_idx]
				dir = (nwp - global_position).normalized()
				velocity = dir * move_speed
		else:
			dir = to_wp / d
			velocity = dir * minf(move_speed, d / delta)
	else:
		# Direct movement toward target (fallback while path computes / no path).
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

	# Water: ripples while wading, and a persistent circle when fully submerged.
	if world and world.has_method("get_water_depth"):
		var water_depth: float = world.get_water_depth(global_position)
		if water_depth >= 0.85:
			# Fully submerged — ripple circles mark the spot.
			_ripple_timer += delta
			if _ripple_timer >= 0.4:
				_ripple_timer = 0.0
				if world.has_method("spawn_ripple"):
					world.spawn_ripple(global_position)
		elif water_depth > 0.0 and velocity.length_squared() > 25.0:
			# Wading — ripples only while moving.
			_ripple_timer += delta
			if _ripple_timer >= 0.25:
				_ripple_timer = 0.0
				if world.has_method("spawn_ripple"):
					world.spawn_ripple(global_position)

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


func move_to(world_pos: Vector2) -> void:
	_cancel_chop()  # moving interrupts any sustained action (chopping included)
	_target = world_pos
	_target_set = true
	_path.clear()
	_path_idx = 0
	_stuck_time = 0.0
	_stuck_at = global_position
	var world := get_parent()
	if world and world.has_method("request_path"):
		world.request_path(global_position, world_pos, _on_path_ready)


func _on_path_ready(path: Array) -> void:
	_path = path
	_path_idx = 0
	_stuck_time = 0.0
	_stuck_at = global_position


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Tool selection: number keys 1-9 (1 = empty hands, 2-9 = tools).
	if event is InputEventKey and event.pressed and not event.echo:
		if not _is_typing():
			if event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_set_tool(event.keycode - KEY_2)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _is_typing():
			_start_attack()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _is_click_on_minimap(event.global_position):
			return  # let the HUD handle minimap clicks
		var click_pos := get_global_mouse_position()
		var world := get_parent()
		if world and world.has_method("is_in_bounds") and world.is_in_bounds(click_pos):
			move_to(click_pos)
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
