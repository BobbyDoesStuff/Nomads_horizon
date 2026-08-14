extends Node2D
## Game world — spawns players, syncs positions, manages the tile map.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const TILE_DIR     := "res://assets/tiles"
const HEALTH_SYNC_INTERVAL := 0.5
const CELL := 48
const AGENT := 48
const WATER_RES := 4   # fine water-mask resolution (pixels per cell)
const BACKGROUND_TEX := preload("res://assets/tiles/background.png")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const RIPPLE_SCRIPT := preload("res://scripts/effects/ripple.gd")
const TREE_SCRIPT := preload("res://scripts/world/tree.gd")

var _remote_players: Dictionary = {}
var _spawned:         bool      = false
var _map_bounds:      Rect2              # world-coord bounds of the background
var _bg_image:        Image     = null   # for alpha-sampling walkability
var _health_sync_timer: float  = 0.0
var _astar_grid: AStarGrid2D = null
var _gc: int = 0
var _gr: int = 0
var _prects: Array = []        # inflated obstacle rects for the grid
var _water_fine: PackedByteArray = PackedByteArray()  # 0=land, 1=water (fine resolution)
var _water_w: int = 0
var _water_h: int = 0
var _nav_ready: bool = false


func _ready() -> void:
	y_sort_enabled = true   # draw by Y position — lower = behind, higher = in front
	_setup_map()
	_setup_hud()

	await get_tree().process_frame
	_spawn_my_player()

	if multiplayer.multiplayer_peer == null:
		return

	if NetworkManager.is_server:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_server:
		return
	_server_health_tick(delta)


# Server-authoritative health: regen every player + periodic broadcast to clients.
func _server_health_tick(delta: float) -> void:
	for child in get_children():
		if child is CharacterBody2D:
			child.tick_regen(delta)
	_health_sync_timer += delta
	if _health_sync_timer >= HEALTH_SYNC_INTERVAL:
		_health_sync_timer = 0.0
		for child in get_children():
			if child is CharacterBody2D:
				_broadcast_health.rpc(child.name.to_int(), child.health)


# ------------------------------------------------------------------ map building
func _setup_map() -> void:
	# -- background (walkable, no collision, NOT centered so world coords = pixel coords) --
	_bg_image = _load_image(TILE_DIR + "/background.png")  # uncompressed, for walkability sampling
	if _bg_image:
		_map_bounds = Rect2(0, 0, _bg_image.get_width(), _bg_image.get_height())
		# Render the VRAM-compressed imported texture as a single sprite.
		var bg := Sprite2D.new()
		bg.name = "MapBackground"
		bg.texture = BACKGROUND_TEX
		bg.centered = false   # top-left at (0,0); world coords = pixel coords
		bg.z_index = -1000
		var water_mat := ShaderMaterial.new()
		water_mat.shader = WATER_SHADER
		bg.material = water_mat
		add_child(bg)
		print("[World] Background loaded — ", _bg_image.get_width(), "x", _bg_image.get_height())

	# -- path tiles (walkable, no collision) — scattered across the map --
	_place_path("Muddy Road NWxSE A.png", Vector2(2500, 1500))
	_place_path("Muddy Road NWxSE B.png", Vector2(4500, 2600))
	_place_path("Muddy Road NExSW A.png", Vector2(4500, 1500))
	_place_path("Muddy Road NExSW B.png", Vector2(2500, 2600))
	_place_path("Muddy Road Xroad.png",    Vector2(3500, 2041))
	_place_path("Muddy Road E Bend.png",   Vector2(5500, 2000))

	# -- obstacles (unwalkable, with collision) — dispersed across the map --
	# Flora
	_place_tree("flora/Dense Trees - size 2 - 2x2A.png", Vector2(2000, 1500), Vector2(200, 120), 0)
	_place_tree("flora/Dense Trees - size 3 - 3x3A.png", Vector2(5000, 1400), Vector2(260, 160), 1)
	_place_obstacle("flora/Dense Flora - size 1 - 2x2A.png", Vector2(4500, 2600), Vector2(160, 120))
	_place_tree("flora/Dense Trees - size 2 - 2x2B.png", Vector2(2400, 2700), Vector2(200, 120), 2)

	# Rocks
	_place_obstacle("rocks/Rocky Cover - Size 1A.png", Vector2(3000, 900), Vector2(140, 100))
	_place_obstacle("rocks/Rocky Cover - Size 2A.png", Vector2(5200, 2200), Vector2(220, 140))
	_place_obstacle("rocks/Rocky Cover - Size 3A.png", Vector2(1800, 2400), Vector2(280, 180))

	# Infrastructure
	_place_obstacle("infrastructure/Small Crates 1A.png",     Vector2(4000, 3200), Vector2(100, 60))
	_place_obstacle("infrastructure/Tent A.a - Green.png",    Vector2(2800, 2000), Vector2(110, 80))
	_place_obstacle("infrastructure/Sandbags E-W - Tan.png",  Vector2(4600, 1900), Vector2(130, 40))
	_place_obstacle("infrastructure/Concrete Foundation A.png", Vector2(3500, 700), Vector2(180, 120))

	# Structures
	_place_obstacle("structures/Prefab Building - Size 1A.png", Vector2(6000, 2000), Vector2(180, 130))
	_place_obstacle("structures/Prefab Wall NW - 2x1 - Size 1.png", Vector2(1000, 2100), Vector2(160, 40))
	_place_obstacle("structures/Rubble 2x2A.png",              Vector2(3700, 3400), Vector2(180, 140))

	_build_navigation()
	_bg_image = null  # free the ~114 MB source image now that the grid is built
	print("[World] Map built")


func _setup_hud() -> void:
	# Don't add a second HUD if world_generator already added one
	if get_tree().get_first_node_in_group("hud_group"):
		return
	var hud_scene := load("res://scenes/ui/hud.tscn")
	if hud_scene:
		var hud: Node = hud_scene.instantiate()
		hud.add_to_group("hud_group")
		add_child(hud)


func _add_sprite(img_path: String, pos: Vector2, z: int, center: bool = true) -> Sprite2D:
	var img := _load_image(img_path)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	var s := Sprite2D.new()
	s.texture = tex
	s.global_position = pos
	s.centered = center
	s.z_index = z
	add_child(s)
	return s


func _place_path(filename: String, pos: Vector2) -> void:
	_add_sprite(TILE_DIR + "/path_tiles/" + filename, pos, -1)  # below objects so roads never draw over characters


func _place_obstacle(rel_path: String, pos: Vector2, collision_size: Vector2) -> void:
	## Places an obstacle with a StaticBody2D + collision shape.
	## The sprite is non-centered so its origin is at the base for Y-sorting.
	var img := _load_image(TILE_DIR + "/obstacles/" + rel_path)
	if img == null:
		return

	var body := StaticBody2D.new()
	body.name = "Obstacle_" + rel_path.get_file().get_basename()
	body.global_position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Sprite with origin at base centre (not centred) for correct Y-sorting
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = Vector2(-img.get_width() / 2.0, -img.get_height())
	sprite.z_index = 0
	body.add_child(sprite)

	# Collision matches the sprite's opaque pixels (transparent background is passable).
	_add_collision_polygon(body, img, collision_size)

	# Inflated footprint for the coarse pathfinding grid.
	var inflated := collision_size + Vector2(AGENT * 2, AGENT * 2)
	_prects.append(Rect2(pos + Vector2(0, -collision_size.y / 2.0) - inflated / 2.0, inflated))


func _place_tree(rel_path: String, pos: Vector2, collision_size: Vector2, id: int) -> void:
	## Places a cuttable tree (unwalkable, same as an obstacle, but choppable).
	var tree = TREE_SCRIPT.new()
	tree.name = "Tree_%d" % id
	add_child(tree)
	tree.setup(TILE_DIR + "/obstacles/" + rel_path, pos, collision_size, id)

	# Inflated footprint for the coarse pathfinding grid (same as obstacles).
	var inflated := collision_size + Vector2(AGENT * 2, AGENT * 2)
	_prects.append(Rect2(pos + Vector2(0, -collision_size.y / 2.0) - inflated / 2.0, inflated))


func _add_collision_polygon(body: StaticBody2D, img: Image, fallback_size: Vector2) -> void:
	# Build a collision outline from the sprite's opaque pixels.
	var points := PackedVector2Array()
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			if img.get_pixel(x, y).a > 0.1:
				points.append(Vector2(x - w / 2.0, y - h))
	if points.size() < 3:
		# Fallback rectangle.
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = fallback_size
		shape.position = Vector2(0, -fallback_size.y / 2.0)
		body.add_child(shape)
		return
	var hull := Geometry2D.convex_hull(points)
	var cp := CollisionPolygon2D.new()
	cp.polygon = hull
	body.add_child(cp)


func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		push_error("[World] Missing: " + path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


# Build the walkable grid once (obstacles are static, so this never changes).
func _build_navigation() -> void:
	_gc = ceili(_map_bounds.size.x / CELL)
	_gr = ceili(_map_bounds.size.y / CELL)
	_astar_grid = AStarGrid2D.new()
	_astar_grid.region = Rect2i(0, 0, _gc, _gr)
	_astar_grid.cell_size = Vector2(CELL, CELL)
	_astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar_grid.update()
	for gy in _gr:
		for gx in _gc:
			var wx := gx * CELL + CELL / 2.0
			var wy := gy * CELL + CELL / 2.0
			var solid := false
			if _bg_image:
				var px := int(wx)
				var py := int(wy)
				if px < 0 or px >= _bg_image.get_width() or py < 0 or py >= _bg_image.get_height():
					solid = true
				elif _bg_image.get_pixel(px, py).a < 0.1:
					solid = true
			if not solid:
				for r in _prects:
					if (r as Rect2).has_point(Vector2(wx, wy)):
						solid = true
						break
			if solid:
				_astar_grid.set_point_solid(Vector2i(gx, gy), true)

	# Finer-resolution water mask so the map edge reads as water, not land.
	_water_w = ceili(_map_bounds.size.x / WATER_RES)
	_water_h = ceili(_map_bounds.size.y / WATER_RES)
	_water_fine.resize(_water_w * _water_h)
	for fy in _water_h:
		for fx in _water_w:
			var px := fx * WATER_RES + WATER_RES / 2
			var py := fy * WATER_RES + WATER_RES / 2
			var w := 0
			if _bg_image and px < _bg_image.get_width() and py < _bg_image.get_height():
				if _bg_image.get_pixel(px, py).a < 0.1:
					w = 1
			_water_fine[fy * _water_w + fx] = w

	_nav_ready = true
	print("[Nav] ", _gc, "x", _gr, " grid, ", _prects.size(), " obstacles")


# ------------------------------------------------------------------ walkability / bounds
func is_in_bounds(pos: Vector2) -> bool:
	if _map_bounds.size == Vector2.ZERO:
		return true
	return pos.x >= 0 and pos.y >= 0 and pos.x <= _map_bounds.size.x and pos.y <= _map_bounds.size.y


func is_water(pos: Vector2) -> bool:
	if not _nav_ready:
		return false
	var fx := clampi(int(pos.x / WATER_RES), 0, _water_w - 1)
	var fy := clampi(int(pos.y / WATER_RES), 0, _water_h - 1)
	return _water_fine[fy * _water_w + fx] == 1


func get_water_depth(pos: Vector2) -> float:
	if not _nav_ready:
		return 0.0
	if not is_water(pos):
		return 0.0
	# Scaled L1 distance to the rhombus boundary: 0 on the shore, 1 at the corners.
	var cx := _map_bounds.size.x / 2.0
	var cy := _map_bounds.size.y / 2.0
	var dx := absf(pos.x - cx) / cx
	var dy := absf(pos.y - cy) / cy
	return clampf(dx + dy - 1.0, 0.0, 1.0)


func spawn_ripple(pos: Vector2) -> void:
	var ripple: Node2D = RIPPLE_SCRIPT.new() as Node2D
	ripple.position = pos
	add_child(ripple)


# ------------------------------------------------------------------ spawn helpers
func _spawn_my_player() -> void:
	if _spawned:
		return
	_spawned = true

	var id := multiplayer.get_unique_id()
	var player := _make_player(id)
	player.set_multiplayer_authority(id)
	add_child(player)
	player.global_position = _find_spawn_pos()


func _find_spawn_pos() -> Vector2:
	# Spawn at the centre of the map.
	if _map_bounds.size != Vector2.ZERO:
		return _map_bounds.get_center()
	return Vector2(3500, 2041)


func _make_player(peer_id: int) -> CharacterBody2D:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(peer_id)
	return p


# ------------------------------------------------------------------ peer lifecycle
func _on_peer_connected(id: int) -> void:
	print("[World] Peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	print("[World] Peer %d left" % id)
	_remove_player(id)
	_remove_player.rpc(id)


# ------------------------------------------------------------------ RPC: new client signals ready
@rpc("any_peer", "call_remote", "reliable")
func _new_client_ready() -> void:
	if not NetworkManager.is_server:
		return
	var new_id := multiplayer.get_remote_sender_id()
	print("[World] Client %d ready — syncing all players" % new_id)

	for child in get_children():
		if child is CharacterBody2D:
			var pid := child.name.to_int()
			if pid != new_id:
				_spawn_on_client.rpc_id(new_id, pid, child.global_position)

	var new_pos := _find_spawn_pos()
	_tell_clients_to_spawn.rpc(new_id, new_pos)
	_spawn_remote_locally(new_id, new_pos)


# ------------------------------------------------------------------ RPCs
@rpc("authority", "call_remote", "reliable")
func _spawn_on_client(peer_id: int, pos: Vector2) -> void:
	_spawn_remote_locally(peer_id, pos)


@rpc("authority", "call_remote", "reliable")
func _tell_clients_to_spawn(peer_id: int, pos: Vector2) -> void:
	_spawn_remote_locally(peer_id, pos)


func _spawn_remote_locally(peer_id: int, pos: Vector2) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	if _remote_players.has(peer_id):
		return
	print("[World] Spawning remote player %d" % peer_id)
	var player := _make_player(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.global_position = pos
	add_child(player)
	_remote_players[peer_id] = player


@rpc("authority", "call_remote", "reliable")
func _remove_player(peer_id: int) -> void:
	if _remote_players.has(peer_id):
		_remote_players[peer_id].queue_free()
		_remote_players.erase(peer_id)
	var node := get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


# ------------------------------------------------------------------ position + facing sync
@rpc("any_peer", "call_remote", "unreliable")
func recv_position(peer_id: int, pos: Vector2, vel: Vector2, facing: int = 0) -> void:
	if not NetworkManager.is_server:
		return
	var p := get_node_or_null(str(peer_id))
	if p:
		p.add_snapshot(pos)
		p._remote_vel = vel
		p._facing_dir = facing
	_broadcast_position.rpc(peer_id, pos, vel, facing)


@rpc("authority", "call_remote", "unreliable")
func _broadcast_position(peer_id: int, pos: Vector2, vel: Vector2, facing: int = 0) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var p := get_node_or_null(str(peer_id))
	if p:
		p.add_snapshot(pos)
		p._remote_vel = vel
		p._facing_dir = facing


# ------------------------------------------------------------------ attack sync
@rpc("any_peer", "call_remote", "reliable")
func recv_attack(peer_id: int, facing: int = 0) -> void:
	if not NetworkManager.is_server:
		return
	# Play the attack on the server's own copy so the host sees it too.
	var p := get_node_or_null(str(peer_id))
	if p:
		p.play_attack_animation(facing)
	_broadcast_attack.rpc(peer_id, facing)


@rpc("authority", "call_remote", "reliable")
func _broadcast_attack(peer_id: int, facing: int = 0) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var p := get_node_or_null(str(peer_id))
	if p:
		p.play_attack_animation(facing)


# ------------------------------------------------------------------ tree chopping
@rpc("any_peer", "call_remote", "reliable")
func recv_tree_chopped(tree_id: int) -> void:
	if not NetworkManager.is_server:
		return
	_remove_tree_node(tree_id)
	_remove_tree.rpc(tree_id)


@rpc("authority", "call_remote", "reliable")
func _remove_tree(tree_id: int) -> void:
	_remove_tree_node(tree_id)


func _remove_tree_node(tree_id: int) -> void:
	var tree := get_node_or_null("Tree_%d" % tree_id)
	if tree:
		tree.queue_free()


# ------------------------------------------------------------------ damage + health
@rpc("any_peer", "call_remote", "reliable")
func recv_damage(victim_id: int, damage: float) -> void:
	if not NetworkManager.is_server:
		return
	_apply_damage(victim_id, damage)


func _apply_damage(victim_id: int, damage: float) -> void:
	var p := get_node_or_null(str(victim_id))
	if not p:
		return
	p.take_damage(damage)
	_broadcast_damage.rpc(victim_id, damage, p.health)


@rpc("authority", "call_remote", "reliable")
func _broadcast_damage(victim_id: int, damage: float, health: float) -> void:
	var p := get_node_or_null(str(victim_id))
	if p:
		p.receive_damage(damage, health)


@rpc("authority", "call_remote", "reliable")
func _broadcast_health(victim_id: int, health: float) -> void:
	var p := get_node_or_null(str(victim_id))
	if p:
		p.set_health(health)


# ------------------------------------------------------------------ pathfinding (AStarGrid2D, native)
func request_path(from: Vector2, to: Vector2, on_done: Callable) -> void:
	if not _nav_ready:
		on_done.call([])
		return
	var from_id := Vector2i(clampi(int(from.x / CELL), 0, _gc - 1), clampi(int(from.y / CELL), 0, _gr - 1))
	var to_id := Vector2i(clampi(int(to.x / CELL), 0, _gc - 1), clampi(int(to.y / CELL), 0, _gr - 1))
	if _astar_grid.is_point_solid(from_id) or _astar_grid.is_point_solid(to_id):
		on_done.call([])
		return
	on_done.call(Array(_astar_grid.get_point_path(from_id, to_id)))
