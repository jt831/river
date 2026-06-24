extends Node3D
class_name GrabThrowController

@export_group("Grab")
@export var grab_range: float = 4.0
@export var carry_lerp_speed: float = 15.0

@export_group("Throw")
@export var arc_peak_height: float = 2.5
@export var max_throw_distance: float = 12.0

@export_group("Visualization")
@export var max_predict_steps: int = 80
@export var time_step: float = 0.033
@export var trajectory_color := Color(1.0, 1.0, 1.0, 0.78)
@export var trajectory_width: float = 0.15
@export var landing_indicator_color := Color(0.15, 0.85, 1.0, 0.9)
@export var landing_indicator_radius: float = 0.6

@onready var carry_pivot: Marker3D = $CarryPivot
@onready var trajectory_line: MeshInstance3D = $TrajectoryLine
@onready var landing_indicator: MeshInstance3D = $LandingIndicator
@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D

var _held_object: RigidBody3D
var _hovered_object: RigidBody3D
var _throw_velocity := Vector3.ZERO
var _outline_original_materials: Dictionary = {}
var _green_outline: ShaderMaterial
var _red_outline: ShaderMaterial

const OUTLINE_SHADER := """
shader_type spatial;
render_mode cull_front, unshaded;
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_thickness = 0.05;
void vertex() {
	VERTEX += NORMAL * outline_thickness;
}
void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
"""


func _ready() -> void:
	# The controller owns the trajectory meshes, so hiding this node also hides
	# both preview children even when their own visible flags are enabled.
	visible = true
	trajectory_line.global_transform = Transform3D.IDENTITY
	_setup_visuals()


func _exit_tree() -> void:
	_clear_hover()


func _process(_delta: float) -> void:
	_update_hover()
	if Input.is_action_just_pressed("grab"):
		if _held_object:
			_throw_held_object()
		elif _hovered_object and _is_in_grab_range(_hovered_object):
			_grab_object(_hovered_object)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_held_object):
		_held_object = null
		_hide_throw_preview()
		return
	_carry_held_object(delta)
	_update_throw_preview()


func _setup_visuals() -> void:
	var outline_shader := Shader.new()
	outline_shader.code = OUTLINE_SHADER
	_green_outline = ShaderMaterial.new()
	_green_outline.shader = outline_shader
	_green_outline.set_shader_parameter("outline_color", Color(0.1, 1.0, 0.2, 0.95))
	_red_outline = ShaderMaterial.new()
	_red_outline.shader = outline_shader
	_red_outline.set_shader_parameter("outline_color", Color(1.0, 0.1, 0.1, 0.95))

	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_material.albedo_color = trajectory_color
	trajectory_line.material_override = line_material

	var indicator_material := StandardMaterial3D.new()
	indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	indicator_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	indicator_material.albedo_color = landing_indicator_color
	landing_indicator.material_override = indicator_material
	trajectory_line.visible = false
	landing_indicator.visible = false


func _update_hover() -> void:
	if _held_object:
		_clear_hover()
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		_clear_hover()
		return
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_position) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var next_hovered: RigidBody3D
	if result and result.collider is RigidBody3D:
		var candidate := result.collider as RigidBody3D
		if candidate.get_node_or_null("Grabbable"):
			next_hovered = candidate
	if next_hovered != _hovered_object:
		_clear_hover()
		_hovered_object = next_hovered
	if _hovered_object:
		_apply_outline(_hovered_object, _is_in_grab_range(_hovered_object))


func _is_in_grab_range(body: RigidBody3D) -> bool:
	return _player.global_position.distance_to(body.global_position) <= grab_range


func _apply_outline(body: Node, in_range: bool) -> void:
	var outline := _green_outline if in_range else _red_outline
	for mesh in _find_meshes(body):
		if not _outline_original_materials.has(mesh):
			_outline_original_materials[mesh] = mesh.material_overlay
		mesh.material_overlay = outline


func _clear_hover() -> void:
	for mesh in _outline_original_materials:
		if is_instance_valid(mesh):
			mesh.material_overlay = _outline_original_materials[mesh]
	_outline_original_materials.clear()
	_hovered_object = null


func _find_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for child in root.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes


func _grab_object(body: RigidBody3D) -> void:
	_held_object = body
	_clear_hover()
	_held_object.linear_velocity = Vector3.ZERO
	_held_object.angular_velocity = Vector3.ZERO
	_held_object.freeze = true
	_held_object.rotation = Vector3.ZERO
	_held_object.add_collision_exception_with(_player)


func _carry_held_object(delta: float) -> void:
	var target_position := carry_pivot.global_position
	var query := PhysicsRayQueryParameters3D.create(_player.global_position + Vector3.UP * 0.8, target_position)
	query.exclude = [_player.get_rid(), _held_object.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if obstruction:
		target_position = obstruction.position + obstruction.normal * 0.25
	var weight := clampf(carry_lerp_speed * delta, 0.0, 1.0)
	_held_object.global_position = _held_object.global_position.lerp(target_position, weight)


func _throw_held_object() -> void:
	var body := _held_object
	_held_object = null
	body.freeze = false
	body.remove_collision_exception_with(_player)
	body.linear_velocity = _throw_velocity
	body.angular_velocity = Vector3.ZERO
	_hide_throw_preview()


func _update_throw_preview() -> void:
	var start := _held_object.global_position
	var target := _get_mouse_aim_position()
	_throw_velocity = _calculate_throw_velocity(start, target)
	var gravity_strength: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var gravity := Vector3.DOWN * gravity_strength
	var points: Array[Vector3] = [start]
	var position := start
	var velocity := _throw_velocity
	var hit: Dictionary = {}
	for _step in range(max_predict_steps):
		var next_position := position + velocity * time_step + 0.5 * gravity * time_step * time_step
		var query := PhysicsRayQueryParameters3D.create(position, next_position)
		query.exclude = [_player.get_rid(), _held_object.get_rid()]
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if result:
			points.append(result.position)
			hit = result
			break
		points.append(next_position)
		position = next_position
		velocity += gravity * time_step
	_draw_trajectory(points)
	_update_landing_indicator(hit)


func _draw_trajectory(points: Array[Vector3]) -> void:
	var immediate_mesh := trajectory_line.mesh as ImmediateMesh
	immediate_mesh.clear_surfaces()
	if points.size() < 2:
		trajectory_line.visible = false
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		trajectory_line.visible = false
		return
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(points.size()):
		var point := points[index]
		var tangent: Vector3
		if index + 1 < points.size():
			tangent = (points[index + 1] - point).normalized()
		else:
			tangent = (point - points[index - 1]).normalized()
		var view_direction := (camera.global_position - point).normalized()
		var side := tangent.cross(view_direction).normalized()
		if side.length_squared() < 0.001:
			side = tangent.cross(Vector3.UP).normalized()
		side *= trajectory_width * 0.5
		immediate_mesh.surface_add_vertex(point - side)
		immediate_mesh.surface_add_vertex(point + side)
	immediate_mesh.surface_end()
	trajectory_line.visible = true


func _update_landing_indicator(hit: Dictionary) -> void:
	if hit.is_empty():
		landing_indicator.visible = false
		return
	var normal: Vector3 = hit.normal.normalized()
	var tangent := normal.cross(Vector3.FORWARD)
	if tangent.length_squared() < 0.001:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(normal).normalized()
	var basis := Basis(tangent, normal, bitangent).orthonormalized()
	basis = basis.scaled(Vector3.ONE * landing_indicator_radius)
	landing_indicator.global_transform = Transform3D(basis, hit.position + normal * 0.025)
	landing_indicator.visible = true


func _hide_throw_preview() -> void:
	trajectory_line.visible = false
	landing_indicator.visible = false
	var immediate_mesh := trajectory_line.mesh as ImmediateMesh
	if immediate_mesh:
		immediate_mesh.clear_surfaces()


func _get_mouse_aim_position() -> Vector3:
	var player_position := _player.global_position
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return player_position + Vector3.FORWARD * 3.0
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	query.exclude = [_player.get_rid(), _held_object.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3
	if result:
		target = result.position
	elif not is_zero_approx(ray_direction.y):
		var distance_to_plane := (player_position.y - ray_origin.y) / ray_direction.y
		target = ray_origin + ray_direction * maxf(distance_to_plane, 0.0)
	else:
		target = player_position + ray_direction * 3.0
	var horizontal_offset := Vector3(target.x - player_position.x, 0.0, target.z - player_position.z)
	if horizontal_offset.length() > max_throw_distance:
		horizontal_offset = horizontal_offset.normalized() * max_throw_distance
		target.x = player_position.x + horizontal_offset.x
		target.z = player_position.z + horizontal_offset.z
	return target


func _calculate_throw_velocity(start: Vector3, target: Vector3) -> Vector3:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var displacement := target - start
	var horizontal := Vector3(displacement.x, 0.0, displacement.z)
	var peak_above_start := maxf(displacement.y, 0.0) + arc_peak_height
	var vertical_speed := sqrt(2.0 * gravity * peak_above_start)
	var rise_time := vertical_speed / gravity
	var fall_height := peak_above_start - displacement.y
	var fall_time := sqrt(2.0 * maxf(fall_height, 0.0) / gravity)
	var flight_time := rise_time + fall_time
	if flight_time <= 0.001:
		return Vector3.ZERO
	return horizontal / flight_time + Vector3.UP * vertical_speed
