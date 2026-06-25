extends Node
class_name DamGateController

@export var gate_path: NodePath
@export var water_area_path: NodePath
@export var switch_button_path: NodePath
@export var gate_raise_height: float = 3.2
@export var gate_raise_duration: float = 1.5
@export var water_drain_duration: float = 1.8

var _triggered := false
var _gate: Node3D
var _water_area: Node
var _switch_button: Node


func _ready() -> void:
	_gate = get_node_or_null(gate_path) as Node3D
	_water_area = get_node_or_null(water_area_path)
	_switch_button = get_node_or_null(switch_button_path)

	if _switch_button and _switch_button.has_signal("activated"):
		_switch_button.activated.connect(_on_switch_activated)


func _on_switch_activated() -> void:
	if _triggered:
		return
	_triggered = true

	if _switch_button and _switch_button.has_method("lock_triggered"):
		_switch_button.lock_triggered()

	_raise_gate()

	if _water_area and _water_area.has_method("drain"):
		_water_area.drain(water_drain_duration)


func has_water_level_changed() -> bool:
	return _triggered


func _raise_gate() -> void:
	if _gate == null:
		return

	var target_position := _gate.position + Vector3.UP * gate_raise_height
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_gate, "position", target_position, gate_raise_duration)
