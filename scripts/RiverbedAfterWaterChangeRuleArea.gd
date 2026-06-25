class_name RiverbedAfterWaterChangeRuleArea
extends Area3D

@export var dam_controller_path: NodePath
@export var player_group: StringName = &"player"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	if not _water_level_has_changed():
		return

	for body in get_overlapping_bodies():
		_report_body(body)


func _on_body_entered(body: Node3D) -> void:
	if not _water_level_has_changed():
		return

	_report_body(body)


func _report_body(body: Node3D) -> void:
	if body.is_in_group(player_group) or _is_grabbable_body(body):
		RuleSystem.report_rule_trigger(RuleSystem.RULE_RIVERBED_AFTER_WATER_CHANGE)


func _water_level_has_changed() -> bool:
	var controller := get_node_or_null(dam_controller_path)
	return controller != null and controller.has_method("has_water_level_changed") and controller.has_water_level_changed()


func _is_grabbable_body(body: Node) -> bool:
	return body is RigidBody3D and body.get_node_or_null("Grabbable") != null
