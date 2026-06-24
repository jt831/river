class_name Deadzone
extends GameResultZone


func _init() -> void:
	result_kind = RuleSystem.RESULT_FAILURE
	result_text = "游戏失败"
	background_color = Color(0.35, 0.02, 0.02, 0.95)
