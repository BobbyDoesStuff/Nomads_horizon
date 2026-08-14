extends Node2D
## Game world — spawns players, syncs positions, manages the tile map.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const TILE_DIR     := "res://assets/tiles"
const HEALTH_SYNC_INTERVAL := 0.5
const CELL := 48
const AGENT := 48
const CHUNK_SIZE := 512
const MAX_PATH_ITERS := 6000

var _remote_players: Dictionary = {}
var _spawned:         bool      = false
var _map_bounds:      Rect2              # world-coord bounds of the background
var _bg_image:        Image     = null   # for alpha-sampling walkability
var _health_sync_timer: float  = 0.0
var _grid: Array = []          # _grid[gy][gx] — walkable boolean
var _gc: int = 0
var _gr: int = 0
var _prects: Array = []        # inflated obstacle rects for the grid
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
	_bg_image = _load_image(TILE_DIR + "/background.png")
	if _bg_image:
		_map_bounds = Rect2(0, 0, _bg_image.get_width(), _bg_image.get_height())
		print("[World] Background loaded — ", _bg_image.get_width(), "x", _bg_image.get_height())
		_chunk_background()

	# -- path tiles (walkable, no collision) — around map centre --
	_place_path("Muddy Road NWxSE A.png", Vector2(3300, 1900))
	_place_path("Muddy Road NWxSE B.png", Vector2(3600, 2100))
	_place_path("Muddy Road NExSW A.png", Vector2(3500, 2000))
	_place_path("Muddy Road NExSW B.png", Vector2(3800, 2200))
	_place_path("Muddy Road Xroad.png",    Vector2(3400, 2100))
	_place_path("Muddy Road E Bend.png",   Vector2(3700, 1950))

	# -- obstacles (unwalkable, with collision) — around map centre --
	# Flora
	_place_obstacle("flora/Dense Trees - size 2 - 2x2A.png", Vector2(3200, 1800), Vector2(200, 120))
	_place_obstacle("flora/Dense Trees - size 3 - 3x3A.png", Vector2(3800, 1900), Vector2(260, 160))
	_place_obstacle("flora/Dense Flora - size 1 - 2x2A.png", Vector2(3600, 2300), Vector2(160, 120))
	_place_obstacle("flora/Dense Trees - size 2 - 2x2B.png", Vector2(3100, 2200), Vector2(200, 120))

	# Rocks
	_place_obstacle("rocks/Rocky Cover - Size 1A.png", Vector2(3400, 1800), Vector2(140, 100))
	_place_obstacle("rocks/Rocky Cover - Size 2A.png", Vector2(3900, 2150), Vector2(220, 140))
	_place_obstacle("rocks/Rocky Cover - Size 3A.png", Vector2(3200, 2000), Vector2(280, 180))

	# Infrastructure
	_place_obstacle("infrastructure/Small Crates 1A.png",     Vector2(3500, 1850), Vector2(100, 60))
	_place_obstacle("infrastructure/Tent A.a - Green.png",    Vector2(3300, 2100), Vector2(110, 80))
	_place_obstacle("infrastructure/Sandbags E-W - Tan.png",  Vector2(3700, 2050), Vector2(130, 40))
	_place_obstacle("infrastructure/Concrete Foundation A.png", Vector2(3550, 2200), Vector2(180, 120))

	# Structures
	_place_obstacle("structures/Prefab Building - Size 1A.png", Vector2(3750, 1900), Vector2(180, 130))
	_place_obstacle("structures/Prefab Wall NW - 2x1 - Size 1.png", Vector2(3400, 1950), Vector2(160, 40))
	_place_obstacle("structures/Rubble 2x2A.png",              Vector2(3650, 2150), Vector2(180, 140))

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
	_add_sprite(TILE_DIR + "/path_tiles/" + filename, pos, 0)  # same z so Y-sort works


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

	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = collision_size
	body.add_child(shape)


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


# Split the big background into 512px chunks so off-screen chunks are culled.
func _chunk_background() -> void:
	var w := _bg_image.get_width()
	var h := _bg_image.get_height()
	for y in range(0, h, CHUNK_SIZE):
		for x in range(0, w, CHUNK_SIZE):
			var cw := mini(CHUNK_SIZE, w - x)
			var ch := mini(CHUNK_SIZE, h - y)
			var region := _bg_image.get_region(Rect2(x, y, cw, ch))
			var tex := ImageTexture.create_from_image(region)
			var s := Sprite2D.new()
			s.name = "BGChunk_%d_%d" % [x, y]
			s.texture = tex
			s.centered = false
			s.position = Vector2(x, y)
			s.z_index = -1000
			add_child(s)


# Build the walkable grid once (obstacles are static, so this never changes).
func _build_navigation() -> void:
	for child in get_children():
		if child is StaticBody2D:
			for gc in child.get_children():
				if gc is CollisionShape2D and gc.shape is RectangleShape2D:
					var s: RectangleShape2D = gc.shape
					var sz: Vector2 = s.size + Vector2(AGENT * 2, AGENT * 2)
					_prects.append(Rect2(child.global_position - sz / 2.0, sz))
					break

	_gc = ceili(_map_bounds.size.x / CELL)
	_gr = ceili(_map_bounds.size.y / CELL)
	_grid.clear()
	for gy in _gr:
		var row: Array = []
		row.resize(_gc)
		for gx in _gc:
			var wx := gx * CELL + CELL / 2.0
			var wy := gy * CELL + CELL / 2.0
			var ok := true
			if _bg_image:
				var px := int(wx)
				var py := int(wy)
				if px < 0 or px >= _bg_image.get_width() or py < 0 or py >= _bg_image.get_height():
					ok = false
				elif _bg_image.get_pixel(px, py).a < 0.1:
					ok = false
			if ok:
				for r in _prects:
					if (r as Rect2).has_point(Vector2(wx, wy)):
						ok = false
						break
			row[gx] = ok
		_grid.append(row)
	_nav_ready = true
	print("[Nav] ", _gc, "x", _gr, " grid, ", _prects.size(), " obstacles")


# ------------------------------------------------------------------ walkability / bounds
func is_in_bounds(pos: Vector2) -> bool:
	if _map_bounds.size == Vector2.ZERO:
		return true
	return pos.x >= 0 and pos.y >= 0 and pos.x <= _map_bounds.size.x and pos.y <= _map_bounds.size.y


func is_walkable(pos: Vector2) -> bool:
	if not is_in_bounds(pos):
		return false
	if not _nav_ready:
		return true
	var gx := clampi(int(pos.x / CELL), 0, _gc - 1)
	var gy := clampi(int(pos.y / CELL), 0, _gr - 1)
	return _walkable(gx, gy)


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


# ------------------------------------------------------------------ pathfinding (A* on a background thread)
func request_path(from: Vector2, to: Vector2, on_done: Callable) -> void:
	if not _nav_ready:
		on_done.call([])
		return
	WorkerThreadPool.add_task(_run_pathfinding.bind(from, to, on_done))


# Runs on a worker thread: computes the path, then delivers it back on the main thread.
func _run_pathfinding(from: Vector2, to: Vector2, on_done: Callable) -> void:
	var path := _astar(from, to)
	on_done.call_deferred(path)


func _astar(from: Vector2, to: Vector2) -> Array:
	var sx := clampi(int(from.x / CELL), 0, _gc - 1)
	var sy := clampi(int(from.y / CELL), 0, _gr - 1)
	var ex := clampi(int(to.x / CELL), 0, _gc - 1)
	var ey := clampi(int(to.y / CELL), 0, _gr - 1)
	if not _walkable(sx, sy) or not _walkable(ex, ey):
		return []

	var start_id := sy * _gc + sx
	var end_id := ey * _gc + ex
	var g_score := {start_id: 0.0}
	var came := {}
	var heap: Array = []
	_heap_push(heap, _heuristic(sx, sy, ex, ey), start_id)
	var dirs := [[0,1],[0,-1],[1,0],[-1,0],[1,1],[1,-1],[-1,1],[-1,-1]]
	var iters := 0

	while not heap.is_empty():
		iters += 1
		if iters > MAX_PATH_ITERS:
			return []
		var cur: Array = _heap_pop(heap)
		var cid: int = cur[1]
		if cid == end_id:
			return _reconstruct(came, end_id)
		var cg: float = g_score.get(cid, INF)
		var cx := cid % _gc
		var cy := cid / _gc
		for d in dirs:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if not _walkable(nx, ny):
				continue
			if d[0] != 0 and d[1] != 0 and not _walkable(cx + d[0], cy) and not _walkable(cx, cy + d[1]):
				continue
			var nid: int = ny * _gc + nx
			var cost := 1.414 if (d[0] != 0 and d[1] != 0) else 1.0
			var ng := cg + cost
			if ng < g_score.get(nid, INF):
				came[nid] = cid
				g_score[nid] = ng
				_heap_push(heap, ng + _heuristic(nx, ny, ex, ey), nid)
	return []


func _walkable(cx: int, cy: int) -> bool:
	return cx >= 0 and cx < _gc and cy >= 0 and cy < _gr and _grid[cy][cx]


func _heuristic(x1: int, y1: int, x2: int, y2: int) -> float:
	var dx := absi(x1 - x2)
	var dy := absi(y1 - y2)
	return maxf(dx, dy) + 0.414 * minf(dx, dy)


func _reconstruct(came: Dictionary, end_id: int) -> Array:
	var path: Array = []
	var k := end_id
	while true:
		var cx := k % _gc
		var cy := k / _gc
		path.push_front(Vector2(cx * CELL + CELL / 2.0, cy * CELL + CELL / 2.0))
		if not came.has(k):
			break
		k = came[k]
	return path


func _heap_push(h: Array, f: float, id: int) -> void:
	var entry: Array = [f, id]
	h.append(entry)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		var pe: Array = h[p]
		var ie: Array = h[i]
		if pe[0] <= ie[0]:
			break
		h[p] = ie
		h[i] = pe
		i = p


func _heap_pop(h: Array) -> Array:
	if h.is_empty():
		return [-1.0, -1]
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var sm := i
		var l := 2 * i + 1
		var r := 2 * i + 2
		var se: Array = h[sm]
		if l < n:
			var le: Array = h[l]
			if le[0] < se[0]:
				sm = l
				se = h[sm]
		if r < n:
			var re: Array = h[r]
			if re[0] < se[0]:
				sm = r
		if sm == i:
			break
		var tmp: Array = h[i]
		h[i] = h[sm]
		h[sm] = tmp
		i = sm
	return top
