class_name GameResultZone
extends Area3D

const OVERLAY_NAME: StringName = &"GameResultOverlay"

@export var player_group: StringName = &"player"
@export var result_kind: StringName = &"failure"
@export var result_text: String = "游戏结束"
@export var background_color: Color = Color(0.05, 0.05, 0.05, 0.95)

var _result_shown: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _result_shown or not body.is_in_group(player_group):
		return

	_result_shown = true
	RuleSystem.handle_result(result_kind, result_text, background_color)
