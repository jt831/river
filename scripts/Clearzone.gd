class_name Clearzone
extends GameResultZone


func _init() -> void:
	result_kind = RuleSystem.RESULT_CLEAR
	result_text = "游戏成功"
	background_color = Color(0.02, 0.28, 0.10, 0.95)
