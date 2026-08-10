extends Node2D
class_name WorldGenerator
## Procedural world generator — continents, rivers, cities, monuments.
##
## Runs on the server when game_world loads.  Updates a loading-screen
## progress bar so the player can see each phase.

# ------------------------------------------------------------------ config
@export var world_width:  int = 160
@export var world_height: int = 120
@export var seed:         int = 0

# Tile atlas coords (placeholder — will be replaced with real tileset)
const TILE_OCEAN     := Vector2i(0, 0)
const TILE_GRASS     := Vector2i(1, 0)
const TILE_SAND      := Vector2i(2, 0)
const TILE_RIVER     := Vector2i(3, 0)
const TILE_MONUMENT  := Vector2i(4, 0)
const TILE_CITY      := Vector2i(5, 0)

# How many set_cell calls between each frame yield (keeps UI responsive)
const CELLS_PER_FRAME := 800

# ------------------------------------------------------------------ public
var continents:      Array[Rect2i] = []
var rivers:          Array[PackedVector2Array] = []
var city_spots:      Array[Vector2i] = []
var monument_spots:  Array[Vector2i] = []


# ------------------------------------------------------------------ lifecycle
func _ready() -> void:
	# HUD overlay (every client)
	var hud_scene := load("res://scenes/ui/hud.tscn")
	if hud_scene:
		add_child(hud_scene.instantiate())

	var loading: CanvasLayer = $LoadingScreen

	if not NetworkManager.is_server:
		if loading: loading.hide()
		return

	var tilemap := $TileMapLayer as TileMapLayer
	if tilemap:
		generate(tilemap, loading)
	else:
		if loading: loading.hide()


func generate(tilemap: TileMapLayer, loading: CanvasLayer = null,
              width: int = 160, height: int = 120, p_seed: int = 0) -> void:
	world_width  = width
	world_height = height
	if p_seed == 0:
		seed = randi()
	else:
		seed = p_seed
	seed(seed)

	print("[WorldGen] Generating %dx%d world (seed=%d)..." % [width, height, seed])

	# Each phase yields a frame so the loading bar actually renders.
	await _set_progress(loading, "Placing continents...", 0.05)
	_generate_continents()
	await _set_progress(loading, "Continents placed", 0.30)

	await _set_progress(loading, "Tracing rivers...", 0.35)
	_generate_rivers()
	await _set_progress(loading, "Rivers carved", 0.50)

	await _set_progress(loading, "Founding cities...", 0.55)
	_place_cities_and_monuments()
	await _set_progress(loading, "Monuments placed", 0.60)

	# Heavy part — paint the tilemap with per-frame yields
	await _paint_tilemap_async(tilemap, loading)

	await _set_progress(loading, "World ready!", 1.0)
	await get_tree().create_timer(0.3).timeout
	if loading: loading.hide()

	print("[WorldGen] Done — %d continents, %d rivers, %d cities, %d monuments" % [
		continents.size(), rivers.size(), city_spots.size(), monument_spots.size(),
	])


# ------------------------------------------------------------------ progress helper
func _set_progress(loading: CanvasLayer, text: String, progress: float) -> void:
	if not loading:
		return
	loading.set_status(text, progress)
	await get_tree().process_frame


# ------------------------------------------------------------------ continent generation
func _generate_continents() -> void:
	var num_continents := randi_range(3, 7)
	var half_w := world_width / 2
	var half_h := world_height / 2

	for _i in num_continents:
		var cx := randi_range(half_w / 4, world_width - half_w / 4)
		var cy := randi_range(half_h / 4, world_height - half_h / 4)
		var rw := randi_range(30, 80)
		var rh := randi_range(20, 50)
		var rect := Rect2i(cx - rw / 2, cy - rh / 2, rw, rh)
		rect.position.x = clampi(rect.position.x, 0, world_width  - rect.size.x)
		rect.position.y = clampi(rect.position.y, 0, world_height - rect.size.y)
		continents.append(rect)


# ------------------------------------------------------------------ rivers
func _generate_rivers() -> void:
	for cont in continents:
		if randf() > 0.4:
			var pts := _trace_river(cont)
			if pts.size() >= 2:
				rivers.append(pts)


func _trace_river(cont: Rect2i) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var start := Vector2i(
		cont.position.x + cont.size.x / 2 + randi_range(-cont.size.x / 4, cont.size.x / 4),
		cont.position.y + cont.size.y / 4,
	)
	start = start.clamp(cont.position, cont.end)
	var cur := start
	var steps := randi_range(15, 40)

	for _i in steps:
		pts.append(cur)
		var dx := randi_range(-1, 1)
		var dy := randi_range(0, 2)
		cur += Vector2i(dx, dy)
		cur.x = clampi(cur.x, cont.position.x, cont.end.x - 1)
		cur.y = clampi(cur.y, cont.position.y, cont.end.y - 1)
		if cur.y >= cont.end.y - 2:
			pts.append(cur)
			break
	return pts


# ------------------------------------------------------------------ cities & monuments
func _place_cities_and_monuments() -> void:
	for cont in continents:
		var city_count := randi_range(1, 3)
		for _j in city_count:
			var spot := Vector2i(
				cont.position.x + randi_range(10, cont.size.x - 10),
				cont.position.y + randi_range(5,  cont.size.y - 5),
			)
			city_spots.append(spot)

		var mon_spot := Vector2i(
			cont.position.x + cont.size.x / 2 + randi_range(-15, 15),
			cont.position.y + cont.size.y / 2 + randi_range(-10, 10),
		)
		monument_spots.append(mon_spot.clamp(cont.position, cont.end))


# ------------------------------------------------------------------ async tile painting (yields every N cells)
func _paint_tilemap_async(tilemap: TileMapLayer, loading: CanvasLayer) -> void:
	# Collect all cells first (fast, no I/O)
	var grass_cells:     Array = []
	var sand_cells:      Array = []
	var river_cells:     Array = []
	var city_cells:      Array = []
	var monument_cells:  Array = []

	for cont in continents:
		for x in range(cont.position.x, cont.end.x):
			for y in range(cont.position.y, cont.end.y):
				if (x == cont.position.x or x == cont.end.x - 1 or
					y == cont.position.y or y == cont.end.y - 1):
					sand_cells.append(Vector2i(x, y))
				else:
					grass_cells.append(Vector2i(x, y))

	for river in rivers:
		for pt in river:
			river_cells.append(Vector2i(pt))

	for spot in city_spots:
		city_cells.append(spot)
	for spot in monument_spots:
		monument_cells.append(spot)

	# Paint in batches, yielding between batches for responsive UI
	var all_batches: Array[Dictionary] = [
		{ cells = grass_cells,     tile = TILE_GRASS,     label = "Painting grass..." },
		{ cells = sand_cells,      tile = TILE_SAND,      label = "Painting coastlines..." },
		{ cells = river_cells,     tile = TILE_RIVER,     label = "Carving rivers..." },
		{ cells = city_cells,      tile = TILE_CITY,      label = "Placing cities..." },
		{ cells = monument_cells,  tile = TILE_MONUMENT,  label = "Raising monuments..." },
	]

	var total_cells: int = 0
	var painted:     int = 0
	for batch in all_batches:
		total_cells += batch.cells.size()

	for batch in all_batches:
		if loading:
			loading.set_status(batch.label, 0.60 + 0.35 * float(painted) / max(total_cells, 1))

		var count: int = 0
		for cell in batch.cells:
			tilemap.set_cell(cell, 0, batch.tile)
			count += 1
			painted += 1
			# Yield every N cells to keep the UI alive
			if count >= CELLS_PER_FRAME:
				count = 0
				if loading:
					var frac := 0.60 + 0.35 * float(painted) / max(total_cells, 1)
					loading.set_status(batch.label, frac)
				await get_tree().process_frame
