extends CanvasLayer
## HUD overlay — health, hotbar, minimap placeholder, and chat toggle.

@onready var health_bar:  ProgressBar = $MarginContainer/HBoxContainer/LeftPanel/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/HBoxContainer/LeftPanel/StaminaBar
@onready var hotbar:      HBoxContainer = $MarginContainer/HBoxContainer/CenterPanel/Hotbar
@onready var chat_box:    Control = $ChatBox


func _ready() -> void:
	# Hide chat until Enter is pressed
	chat_box.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_chat"):
		chat_box.visible = not chat_box.visible
		if chat_box.visible:
			chat_box.get_node("LineEdit").grab_focus()


func set_health(value: float, max_value: float) -> void:
	health_bar.max_value = max_value
	health_bar.value = value


func set_stamina(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
