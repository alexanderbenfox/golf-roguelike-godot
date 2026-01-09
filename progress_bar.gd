extends ProgressBar

@export var progressBar: ProgressBar

func _ready():
	hide()
	
func show_meter():
	show()
	progressBar.value = 0
	
func update_power(currentPow: float, maxPow: float):
	var percentage = (currentPow / maxPow) * 100.0
	progressBar.value = percentage
	
func hide_meter():
	hide()
	progressBar.value = 0
