extends Node2D
## Build manager — places isometric cube blocks on a grid, stacking into layers.

const BLOCK_SHEET := "res://assets/sprites/blocks_cubes.png"
const TILE_SIZE := 256
const DEFAULT_TILE := 10          # brown cube (row 1, col 0)
const TILE_COUNT := 60            # 10 cols x 6 rows
const HALF_W := 128.0             # half the diamond's horizontal diagonal
const HALF_H := 64.0              # half the diamond's vertical diagonal
const LAYER_OFFSET_Y := -128.0    # vertical offset between stacked layers

var _blocks: Dictionary = {}      # Vector2i(grid) -> Array[Sprite2D] (one per layer)
var _textures: Dictionary = {}    # tile index -> Texture2D


func _ready() -> void:
	add_to_group("build")


func get_block_texture(tile: int = DEFAULT_TILE) -> Texture2D:
	if not _textures.has(tile):
		var img := _load_image(BLOCK_SHEET)
		if img == null:
			return null
		var cols := int(img.get_width() / TILE_SIZE)
		var col := tile % cols
		var row := int(tile / cols)
		var sub := img.get_region(Rect2i(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE))
		_textures[tile] = ImageTexture.create_from_image(sub)
	return _textures[tile]


func tile_count() -> int:
	return TILE_COUNT


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


func place_block(world_pos: Vector2, layer: int, tile: int = DEFAULT_TILE, flip_h: bool = false, flip_v: bool = false) -> void:
	var grid := grid_coords(world_pos)
	var tex := get_block_texture(tile)
	if tex == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.flip_h = flip_h
	sprite.flip_v = flip_v
	sprite.position = block_anchor(grid, layer)
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
