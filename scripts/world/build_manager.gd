extends Node2D
## Build manager — places isometric cube blocks on a grid, stacking into layers.

const BLOCK_SHEET := "res://assets/sprites/blocks_cubes.png"
const TILE_SIZE := 256
const DEFAULT_TILE := 10          # brown cube (row 1, col 0)
const HALF_W := 128.0             # half the diamond's horizontal diagonal
const HALF_H := 64.0              # half the diamond's vertical diagonal
const ANCHOR := Vector2(128, 128) # tile point that sits on the grid anchor
const LAYER_OFFSET_Y := -128.0    # vertical offset between stacked layers

var _blocks: Dictionary = {}      # Vector2i(grid) -> Array[Sprite2D] (one per layer)
var _texture: Texture2D = null


func _ready() -> void:
	add_to_group("build")


func get_block_texture() -> Texture2D:
	if _texture == null:
		var img := _load_image(BLOCK_SHEET)
		if img == null:
			return null
		var cols := int(img.get_width() / TILE_SIZE)
		var col := DEFAULT_TILE % cols
		var row := int(DEFAULT_TILE / cols)
		var sub := img.get_region(Rect2i(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE))
		_texture = ImageTexture.create_from_image(sub)
	return _texture


func grid_coords(world_pos: Vector2) -> Vector2i:
	var gx := roundf((world_pos.x / HALF_W + world_pos.y / HALF_H) / 2.0)
	var gy := roundf((world_pos.y / HALF_H - world_pos.x / HALF_W) / 2.0)
	return Vector2i(int(gx), int(gy))


func block_anchor(grid: Vector2i, layer: int) -> Vector2:
	## World position of a block's anchor (footprint centre) for a cell + layer.
	return Vector2(
		(grid.x - grid.y) * HALF_W,
		(grid.x + grid.y) * HALF_H + layer * LAYER_OFFSET_Y
	)


func snap_to_grid(world_pos: Vector2) -> Vector2:
	## Anchor point of the cell under `world_pos`.
	return block_anchor(grid_coords(world_pos), 0)


func block_top_left(grid: Vector2i, layer: int) -> Vector2:
	## Top-left corner (sprite position) for a block at a cell + layer.
	return block_anchor(grid, layer) - ANCHOR


func layer_count(grid: Vector2i) -> int:
	var stack: Array = _blocks.get(grid, [])
	return stack.size()


func place_block(world_pos: Vector2, layer: int) -> void:
	var grid := grid_coords(world_pos)
	var tex := get_block_texture()
	if tex == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = block_top_left(grid, layer)
	add_child(sprite)
	if not _blocks.has(grid):
		_blocks[grid] = []
	_blocks[grid].append(sprite)


func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		push_error("[Build] Missing: " + path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img
