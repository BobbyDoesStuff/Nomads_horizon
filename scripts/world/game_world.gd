extends Node2D
## Game world — single-player and multiplayer spawn + position sync.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

var _remote_players: Dictionary = {}
var _spawned:         bool      = false


func _ready() -> void:
	await get_tree().process_frame
	_spawn_my_player()

	if multiplayer.multiplayer_peer == null:
		return

	if NetworkManager.is_server:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# ------------------------------------------------------------------ spawn helpers
func _spawn_my_player() -> void:
	if _spawned: return
	_spawned = true

	var id := multiplayer.get_unique_id()
	var player := _make_player(id)
	player.set_multiplayer_authority(id)
	add_child(player)
	player.global_position = Vector2(640, 360) if multiplayer.multiplayer_peer == null else Vector2(randi_range(200,600), randi_range(200,500))


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
	if not NetworkManager.is_server: return
	var new_id := multiplayer.get_remote_sender_id()
	print("[World] Client %d ready — syncing all players" % new_id)

	# 1) Spawn all existing players on the new client
	for child in get_children():
		if child is CharacterBody2D:
			var pid := child.name.to_int()
			if pid != new_id:
				_spawn_on_client.rpc_id(new_id, pid, child.global_position)

	# 2) Spawn the new player on all remote clients + server
	var new_pos := Vector2(randi_range(200,600), randi_range(200,500))
	_tell_clients_to_spawn.rpc(new_id, new_pos)
	# rpc() only sends to remotes — server must spawn locally
	_spawn_remote_locally(new_id, new_pos)


# ------------------------------------------------------------------ RPCs
@rpc("authority", "call_remote", "reliable")
func _spawn_on_client(peer_id: int, pos: Vector2) -> void:
	_spawn_remote_locally(peer_id, pos)


@rpc("authority", "call_remote", "reliable")
func _tell_clients_to_spawn(peer_id: int, pos: Vector2) -> void:
	_spawn_remote_locally(peer_id, pos)


func _spawn_remote_locally(peer_id: int, pos: Vector2) -> void:
	if peer_id == multiplayer.get_unique_id(): return
	if _remote_players.has(peer_id): return
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
	if node: node.queue_free()


# ------------------------------------------------------------------ position + facing sync
@rpc("any_peer", "call_remote", "unreliable")
func recv_position(peer_id: int, pos: Vector2, facing: int = 0) -> void:
	if not NetworkManager.is_server: return
	var p := get_node_or_null(str(peer_id))
	if p:
		p.global_position = pos
		p._remote_pos = pos  # prevent lerp fight on server
		p._facing_dir = facing
	_broadcast_position.rpc(peer_id, pos, facing)


@rpc("authority", "call_remote", "unreliable")
func _broadcast_position(peer_id: int, pos: Vector2, facing: int = 0) -> void:
	if peer_id == multiplayer.get_unique_id(): return
	var p := get_node_or_null(str(peer_id))
	if p:
		p._remote_pos = pos
		p._facing_dir = facing
	if _remote_players.has(peer_id):
		_remote_players[peer_id]._remote_pos = pos
		_remote_players[peer_id]._facing_dir = facing
