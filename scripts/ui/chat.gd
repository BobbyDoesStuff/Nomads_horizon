extends Control
## Chat overlay — text entry + scrollable message log + per-player speech bubbles.

@onready var chat_input: LineEdit = $LineEdit
@onready var chat_log:   RichTextLabel = $ChatLog

var _hide_timer: Timer = null


func _ready() -> void:
	chat_input.text_submitted.connect(_on_send_message)
	NetworkManager.chat_received.connect(_on_chat_received)
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = 5.0
	_hide_timer.timeout.connect(_on_hide_timeout)
	add_child(_hide_timer)


func _on_send_message(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		close_chat()
		return

	var my_id := multiplayer.get_unique_id()
	if NetworkManager.is_server:
		NetworkManager.host_send_chat(text)
	else:
		NetworkManager.send_chat.rpc_id(1, text)

	_add_message("You", text)
	_show_bubble(my_id, text)
	chat_input.clear()
	# Keep the chat open + focused so the player can keep typing.


func _on_chat_received(sender_id: int, message: String) -> void:
	_add_message("Player %d" % sender_id, message)
	_show_bubble(sender_id, message)
	# Auto-open the chat log when a message arrives.
	visible = true
	_hide_timer.start()


func _on_hide_timeout() -> void:
	# Don't yank the box away while the player is typing.
	if not chat_input.has_focus():
		close_chat()


func _add_message(sender: String, message: String) -> void:
	chat_log.append_text("[%s]: %s\n" % [sender, message])


func _show_bubble(sender_id: int, message: String) -> void:
	for node in get_tree().get_nodes_in_group("players"):
		if node.name == str(sender_id):
			node.show_chat_bubble(message)
			return


func close_chat() -> void:
	visible = false
	chat_input.release_focus()
	_hide_timer.stop()
