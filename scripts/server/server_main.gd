extends Node
## Dedicated-server entry point.
##
## Run with:  godot --headless server_main.tscn
##
## Automatically starts an ENet server, generates the world, and ticks
## the economy / world-state persistence loop.

# ------------------------------------------------------------------ config
@export var server_port: int = 27015
@export var world_seed:  int = 0


# ------------------------------------------------------------------ lifecycle
func _ready() -> void:
	print("=".repeat(50))
	print("  Nomad's Horizon — Dedicated Server")
	print("  Port: %d  |  Seed: %d" % [server_port, world_seed])
	print("=".repeat(50))

	# Start the server
	NetworkManager.host_server(server_port)

	# Switch to game world — world generation happens automatically
	# on the server when game_world.tscn loads (see WorldGenerator).
	GameManager.switch_to_game_world()
	# In headless mode the TileMapLayer won't render, but the logical
	# world state (continents, cities, etc.) is what the server needs.

	# Economy tick timer
	var eco_timer := Timer.new()
	eco_timer.wait_time = 60.0          # tick every 60 s
	eco_timer.autostart = true
	eco_timer.timeout.connect(_economy_tick)
	add_child(eco_timer)

	print("[Server] Ready — listening on port %d" % server_port)


# ------------------------------------------------------------------ economy
func _economy_tick() -> void:
	# Stub — will update city market prices based on supply/demand,
	# progress clan construction timers, and decay abandoned structures.
	pass
