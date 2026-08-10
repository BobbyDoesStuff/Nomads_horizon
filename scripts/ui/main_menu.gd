extends Control

@onready var host_btn:  Button   = $VBoxContainer/HostBtn
@onready var join_btn:  Button   = $VBoxContainer/JoinBtn
@onready var solo_btn: Button   = $VBoxContainer/SoloBtn
@onready var ip_input:  LineEdit = $VBoxContainer/IPInput
@onready var status_lbl: Label  = $VBoxContainer/StatusLabel
@onready var quit_btn:  Button  = $VBoxContainer/QuitBtn


func _ready() -> void:
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	solo_btn.pressed.connect(_on_solo_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_fail)


func _on_host_pressed() -> void:
	status_lbl.text = "Starting server..."
	NetworkManager.close_connection()  # clean up any stale peer first
	NetworkManager.host_server()
	await get_tree().create_timer(0.3).timeout
	if NetworkManager.is_server:
		status_lbl.text = "Server started — connecting locally..."
		await get_tree().create_timer(0.2).timeout
		get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	else:
		status_lbl.text = "Failed to host — port 27015 may be in use. Kill old instances first."


func _on_join_pressed() -> void:
	var ip := ip_input.text.strip_edges()
	if ip.is_empty(): ip = "127.0.0.1"
	status_lbl.text = "Connecting to %s..." % ip
	NetworkManager.join_server(ip)


func _on_solo_pressed() -> void:
	# Ensure clean single-player state (no leftover peer from previous session)
	NetworkManager.close_connection()
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_connected() -> void:
	status_lbl.text = "Connected!"
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")


func _on_connect_fail() -> void:
	status_lbl.text = "Connection failed — check IP and try again."
