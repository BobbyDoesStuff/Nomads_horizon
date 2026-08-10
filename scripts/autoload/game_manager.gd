extends Node
## Global game-state manager and signal bus.
##
## Owns the top-level state machine (menu → lobby → game) and emits
## signals that other systems (UI, networking, world) can subscribe to.

# ------------------------------------------------------------------ enum
enum GameState {
	MAIN_MENU,
	IN_LOBBY,
	IN_GAME,
}

# ------------------------------------------------------------------ public
var current_state: GameState = GameState.MAIN_MENU

# ------------------------------------------------------------------ signals
signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)
signal game_started()
signal state_changed(new_state: GameState)


# ------------------------------------------------------------------ scene switching
func switch_to_scene(scene_path: String) -> void:
	# Cancel any in-flight scene change
	if get_tree().has_group("persistent"):
		for node in get_tree().get_nodes_in_group("persistent"):
			node.queue_free()

	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[GameManager] Failed to switch to scene: %s (err=%d)" % [scene_path, err])


func switch_to_main_menu() -> void:
	_set_state(GameState.MAIN_MENU)
	switch_to_scene("res://scenes/main_menu.tscn")


func switch_to_lobby() -> void:
	_set_state(GameState.IN_LOBBY)
	switch_to_scene("res://scenes/server_lobby.tscn")


func switch_to_game_world() -> void:
	_set_state(GameState.IN_GAME)
	switch_to_scene("res://scenes/game_world.tscn")


# ------------------------------------------------------------------ helpers
func is_host() -> bool:
	return multiplayer.is_server()


func get_my_id() -> int:
	return multiplayer.get_unique_id()


# ------------------------------------------------------------------ internal
func _set_state(new_state: GameState) -> void:
	if current_state != new_state:
		current_state = new_state
		state_changed.emit(new_state)
		print("[GameManager] State → %s" % GameState.keys()[new_state])
