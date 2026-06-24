@tool
extends Node3D

@export var target_path: NodePath:
	set(value):
		target_path = value
		_target = null

@export var distance: float = 3.9:
	set(value):
		distance = maxf(value, 0.1)
		_update_camera_transform()

@export_range(-180.0, 180.0, 0.1, "degrees") var yaw_degrees: float = -45.0:
	set(value):
		yaw_degrees = value
		_update_camera_transform()

@export_range(-85.0, 85.0, 0.1, "degrees") var pitch_degrees: float = 35.0:
	set(value):
		pitch_degrees = clampf(value, -85.0, 85.0)
		_update_camera_transform()

@export var target_offset: Vector3 = Vector3(0.0, 1.0, 0.0):
	set(value):
		target_offset = value
		_update_camera_transform()

@export var position_damping: float = 8.0

@onready var _camera: Camera3D = $Camera3D

var _target: Node3D
var _has_focus_position := false


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		set_physics_process(false)
	else:
		set_process(false)
		set_physics_process(true)
	_resolve_target()
	_snap_to_target()
	_update_camera_transform()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_resolve_target()
		_snap_to_target()
		_update_camera_transform()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_resolve_target()
	if _target == null:
		return

	var target_position := _get_target_position()
	if not _has_focus_position or position_damping <= 0.0:
		global_position = target_position
		_has_focus_position = true
	else:
		var weight := 1.0 - exp(-position_damping * delta)
		global_position = global_position.lerp(target_position, weight)

	_update_camera_transform()


func _resolve_target() -> void:
	if _target != null and is_instance_valid(_target):
		return
	if target_path.is_empty():
		return

	var node := get_node_or_null(target_path)
	_target = node as Node3D


func _snap_to_target() -> void:
	if _target == null:
		return

	global_position = _get_target_position()
	_has_focus_position = true


func _get_target_position() -> Vector3:
	return _target.global_position + target_offset


func _update_camera_transform() -> void:
	var camera := _get_camera()
	if camera == null:
		return

	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var horizontal_distance := cos(pitch) * distance
	var offset := Vector3(
		sin(yaw) * horizontal_distance,
		sin(pitch) * distance,
		cos(yaw) * horizontal_distance
	)

	camera.position = offset
	if offset.length_squared() > 0.0001:
		camera.look_at(global_position, Vector3.UP)


func _get_camera() -> Camera3D:
	if is_instance_valid(_camera):
		return _camera
	return get_node_or_null("Camera3D") as Camera3D
