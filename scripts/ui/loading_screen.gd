extends CanvasLayer
## Loading overlay shown during world generation.
## The WorldGenerator calls update_progress() as each phase completes.

@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var status_label:  Label       = $CenterContainer/VBoxContainer/StatusLabel


func set_status(text: String, progress: float) -> void:
	status_label.text = text
	progress_bar.value = progress * 100.0
