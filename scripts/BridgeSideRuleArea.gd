class_name BridgeSideRuleArea
extends Area3D

@export var player_group: StringName = &"player"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		_report_body(body)


func _on_body_entered(body: Node3D) -> void:
	_report_body(body)


func _report_body(body: Node3D) -> void:
	if body.is_in_group(player_group) or _is_grabbable_body(body):
		RuleSystem.report_rule_trigger(RuleSystem.RULE_BRIDGE_SIDE)


func _is_grabbable_body(body: Node) -> bool:
	return body is RigidBody3D and body.get_node_or_null("Grabbable") != null
