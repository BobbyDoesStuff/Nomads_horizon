extends Node
## Lightweight ENet multiplayer manager.

signal connection_succeeded()
signal connection_failed()
signal chat_received(sender_id: int, message: String)

const DEFAULT_PORT := 27015
const MAX_PLAYERS   := 64

var is_server: bool = false
var player_id: int  = 0
var peer: ENetMultiplayerPeer = null


func host_server(port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("[Net] Could not host on port %d" % port)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = true
	is_server = true
	player_id = multiplayer.get_unique_id()
	_connect_signals()
	print("[Net] Hosting on port %d — id=%d" % [port, player_id])


func join_server(address: String, port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("[Net] Could not connect to %s:%d" % [address, port])
		return
	multiplayer.multiplayer_peer = peer
	is_server = false
	player_id = multiplayer.get_unique_id()
	_connect_signals()
	print("[Net] Connecting to %s:%d — id=%d" % [address, port, player_id])


func close_connection() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_server = false
	player_id = 0
	print("[Net] Disconnected")


@rpc("any_peer", "call_remote", "reliable")
func send_chat(text: String) -> void:
	# Runs on the server only (clients call this via rpc_id(1)).
	if not is_server:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	chat_received.emit(sender_id, text)
	# Relay to every other client; the sender already echoes locally.
	for id in multiplayer.get_peers():
		if id != sender_id:
			_relay_chat.rpc_id(id, sender_id, text)


# Host sends its own message without a self-RPC round trip.
func host_send_chat(text: String) -> void:
	var my_id := multiplayer.get_unique_id()
	for id in multiplayer.get_peers():
		_relay_chat.rpc_id(id, my_id, text)


@rpc("authority", "call_remote", "reliable")
func _relay_chat(sender_id: int, text: String) -> void:
	chat_received.emit(sender_id, text)


func _connect_signals() -> void:
	multiplayer.peer_connected.connect(func(id: int): print("[Net] Peer %d connected" % id))
	multiplayer.peer_disconnected.connect(func(id: int): print("[Net] Peer %d disconnected" % id))
	multiplayer.connected_to_server.connect(func(): connection_succeeded.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		close_connection()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
