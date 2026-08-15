extends Node2D
## Build manager — places isometric cube blocks on a grid, stacking into layers.
## Blocks are added to the world (game_world) so they y-sort correctly back-to-front.

const BLOCK_SHEET := "res://assets/sprites/blocks_cubes.png"
const TILE_SIZE := 256
const DEFAULT_TILE := 10          # brown cube (row 1, col 0)
const TILE_COUNT := 60            # 10 cols x 6 rows
const HALF_W := 128.0             # half the diamond's horizontal diagonal
const HALF_H := 64.0              # half the diamond's vertical diagonal
const LAYER_OFFSET_Y := -128.0    # vertical offset between stacked layers
const FOOTPRINT_LIFT := -64.0     # cube footprint sits 64px below the tile centre
const LAYER_SORT_BIAS := 4.0      # Y added per layer so stacked blocks sort above (15-layer cap)

var _blocks: Dictionary = {}      # Vector2i(grid) -> Array[Node2D] (one per layer)
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


func block_anchor(grid: Vector2i, layer: int = 0) -> Vector2:
	## Footprint point of a cell (layer 0), or the cell offset by `layer`.
	return Vector2(
		(grid.x - grid.y) * HALF_W,
		(grid.x + grid.y) * HALF_H + layer * LAYER_OFFSET_Y
	)


func block_sprite_pos(grid: Vector2i, layer: int) -> Vector2:
	## World position of a block sprite's centre (footprint + elevation + lift).
	return block_anchor(grid, 0) + Vector2(0, FOOTPRINT_LIFT + layer * LAYER_OFFSET_Y)


func place_block(world_pos: Vector2, layer: int, tile: int = DEFAULT_TILE, flip_h: bool = false, flip_v: bool = false) -> void:
	var grid := grid_coords(world_pos)
	var tex := get_block_texture(tile)
	if tex == null:
		return

	# Wrapper node sits on the footprint (used as the y-sort key); the sprite
	# child carries the visual elevation, so stacked blocks keep the same sort Y.
	var node := Node2D.new()
	# Sort key = footprint + a tiny per-layer bias, so a block stacked on top of
	# another draws in front of it instead of tying in the y-sort.
	node.position = block_anchor(grid, 0) + Vector2(0, layer * LAYER_SORT_BIAS)

	# Collision on the diamond footprint — blocks the player from walking through.
	# The node origin carries the per-layer sort bias, so cancel it here to keep
	# the collision footprint on the ground (not drifting down with each layer).
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(0, -layer * LAYER_SORT_BIAS)
	var shape := CollisionShape2D.new()
	var poly := ConvexPolygonShape2D.new()
	poly.points = PackedVector2Array([
		Vector2(0, -HALF_H), Vector2(HALF_W, 0), Vector2(0, HALF_H), Vector2(-HALF_W, 0),
	])
	shape.shape = poly
	body.add_child(shape)
	node.add_child(body)

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.flip_h = flip_h
	sprite.flip_v = flip_v
	sprite.position = Vector2(0, FOOTPRINT_LIFT + layer * LAYER_OFFSET_Y - layer * LAYER_SORT_BIAS)
	node.add_child(sprite)

	node.set_meta("layer", layer)  # remember the layer so auto-stack can query it
	get_parent().add_child(node)  # add to the y-sorted world, not this manager
	if not _blocks.has(grid):
		_blocks[grid] = []
	_blocks[grid].append(node)


func top_layer_at(grid: Vector2i) -> int:
	## Highest layer present at a cell, or -1 if the cell is empty.
	var top := -1
	if _blocks.has(grid):
		for node in _blocks[grid]:
			top = maxi(top, int(node.get_meta("layer", 0)))
	return top


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
