extends Label

var _displayed_minute: int = -1


func _ready() -> void:
	TimeSystem.time_changed.connect(_on_time_changed)
	_update_text(TimeSystem.get_total_seconds())


func _on_time_changed(total_seconds: float) -> void:
	_update_text(total_seconds)


func _update_text(total_seconds: float) -> void:
	var total_minutes := int(total_seconds / 60.0)
	if total_minutes == _displayed_minute:
		return

	_displayed_minute = total_minutes
	var hour_24 := int(total_minutes / 60.0) % 24
	var period := "PM" if hour_24 >= 12 else "AM"
	var hour_12 := hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	var minutes := total_minutes % 60
	text = "%02d:%02d %s" % [hour_12, minutes, period]
