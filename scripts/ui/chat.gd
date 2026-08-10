extends Control
## Chat overlay — text entry + scrollable message log.
##
## Press Enter to open, type a message, press Enter again to send.
## Messages are relayed through the server to all clients.

@onready var chat_input:  LineEdit  = $LineEdit
@onready var chat_log:    RichTextLabel = $ChatLog


func _ready() -> void:
	chat_input.text_submitted.connect(_on_send_message)
	NetworkManager.chat_received.connect(_on_chat_received)


func _on_send_message(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return

	# Send to server for relay
	NetworkManager.send_chat.rpc_id(1, text)

	# Echo locally
	_add_message("You", text)
	chat_input.clear()


func _on_chat_received(sender_id: int, message: String) -> void:
	_add_message("Player %d" % sender_id, message)


func _add_message(sender: String, message: String) -> void:
	chat_log.append_text("[%s]: %s\n" % [sender, message])
