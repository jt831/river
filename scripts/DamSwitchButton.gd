extends StaticBody3D
class_name DamSwitchButton

signal activated

@export var player_group: StringName = &"player"
@export var activation_range: float = 3.75
@export var press_depth: float = 0.08

var _is_hovered := false
var _is_activated := false
var _green_outline: ShaderMaterial
var _red_outline: ShaderMaterial
var _original_overlays: Dictionary = {}
var _initial_position: Vector3

const OUTLINE_SHADER := """
shader_type spatial;
render_mode cull_front, unshaded;
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_thickness = 0.035;
void vertex() {
	VERTEX += NORMAL * outline_thickness;
}
void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
"""


func _ready() -> void:
	_initial_position = position
	_setup_outline_materials()


func _exit_tree() -> void:
	_clear_outline()


func _process(_delta: float) -> void:
	if _is_activated:
		return

	var hovered := _mouse_is_over_button()
	if hovered != _is_hovered:
		_is_hovered = hovered
		if not _is_hovered:
			_clear_outline()

	if _is_hovered:
		_apply_outline(_is_player_in_range())
		if Input.is_action_just_pressed("grab") and _is_player_in_range():
			_activate()


func lock_triggered() -> void:
	_is_activated = true
	_clear_outline()
	position = _initial_position + transform.basis.z.normalized() * press_depth


func _activate() -> void:
	lock_triggered()
	activated.emit()


func _setup_outline_materials() -> void:
	var outline_shader := Shader.new()
	outline_shader.code = OUTLINE_SHADER

	_green_outline = ShaderMaterial.new()
	_green_outline.shader = outline_shader
	_green_outline.set_shader_parameter("outline_color", Color(0.1, 1.0, 0.2, 0.95))

	_red_outline = ShaderMaterial.new()
	_red_outline.shader = outline_shader
	_red_outline.set_shader_parameter("outline_color", Color(1.0, 0.1, 0.1, 0.95))


func _mouse_is_over_button() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_position) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.collider == self


func _is_player_in_range() -> bool:
	var player := get_tree().get_first_node_in_group(player_group) as Node3D
	if player == null:
		return false
	return global_position.distance_to(player.global_position) <= activation_range


func _apply_outline(in_range: bool) -> void:
	var outline := _green_outline if in_range else _red_outline
	for mesh in _find_meshes(self):
		if not _original_overlays.has(mesh):
			_original_overlays[mesh] = mesh.material_overlay
		mesh.material_overlay = outline


func _clear_outline() -> void:
	for mesh in _original_overlays:
		if is_instance_valid(mesh):
			mesh.material_overlay = _original_overlays[mesh]
	_original_overlays.clear()


func _find_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for child in root.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes
