extends Control
## Server lobby — shows connected players before the game starts.
##
## Only visible to the host.  The "Start Game" button triggers world
## generation, spawns every connected player, and transitions everyone
## to the game world.

@onready var player_list: ItemList  = $VBoxContainer/PlayerList
@onready var start_btn:   Button    = $VBoxContainer/StartBtn
@onready var status_lbl:  Label     = $VBoxContainer/StatusLabel


func _ready() -> void:
	start_btn.pressed.connect(_on_start_pressed)
	start_btn.disabled = not NetworkManager.is_server

	if NetworkManager.is_server:
		status_lbl.text = "Waiting for players..."
		GameManager.player_joined.connect(_add_player_entry)
		GameManager.player_left.connect(_remove_player_entry)

		# Add the host themselves
		_add_player_entry(NetworkManager.player_id, "Host")


func _add_player_entry(peer_id: int, player_name: String) -> void:
	player_list.add_item("%s (ID %d)" % [player_name, peer_id])
	status_lbl.text = "%d player(s) connected" % player_list.item_count


func _remove_player_entry(peer_id: int) -> void:
	for i in player_list.item_count:
		if player_list.get_item_text(i).contains("ID %d)" % peer_id):
			player_list.remove_item(i)
			break
	status_lbl.text = "%d player(s) connected" % player_list.item_count


func _on_start_pressed() -> void:
	if not NetworkManager.is_server:
		return

	status_lbl.text = "Generating world..."
	await get_tree().create_timer(0.5).timeout

	# Tell all clients to switch to the game world
	_start_game.rpc()


@rpc("authority", "call_remote", "reliable")
func _start_game() -> void:
	GameManager.switch_to_game_world()
