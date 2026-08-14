extends Node2D
## Animated campfire — a looping decorative flame. Placed at the map centre.

const FRAME_W := 640
const FRAME_H := 640
const FRAME_COUNT := 24
const FRAME_DURATION := 0.15   # seconds per frame (matches the source GIF)
const BASE_Y := 490            # frame Y of the campfire's base (bottom of the logs)
const SPRITE_SCALE := 0.3


func setup(img_path: String, pos: Vector2) -> void:
	global_position = pos

	var img := _load_image(img_path)
	if img == null:
		push_error("[Campfire] Missing: " + img_path)
		return

	# Slice each frame into its own texture — avoids one huge 15360px atlas.
	var frames := SpriteFrames.new()
	frames.add_animation("burn")
	frames.set_animation_loop("burn", true)
	frames.set_animation_speed("burn", 1.0 / FRAME_DURATION)
	for f in FRAME_COUNT:
		var sub := img.get_region(Rect2i(f * FRAME_W, 0, FRAME_W, FRAME_H))
		if sub.get_used_rect().size == Vector2i.ZERO:
			continue  # skip blank frames (the sheet's frame 11 is empty)
		frames.add_frame("burn", ImageTexture.create_from_image(sub))

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.centered = false
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.position = Vector2(-FRAME_W / 2.0 * SPRITE_SCALE, -BASE_Y * SPRITE_SCALE)
	sprite.play("burn")
	add_child(sprite)


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
