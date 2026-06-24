extends Node3D
class_name PlayerPositionIndicator

@export var indicator_color := Color(0.15, 0.85, 1.0, 0.9)
@export_range(0.05, 5.0, 0.05) var indicator_radius: float = 0.6
@export_range(0.01, 1.0, 0.01) var ring_width: float = 0.1
@export_range(0.5, 50.0, 0.5) var max_projection_distance: float = 8.0
@export_range(0.1, 20.0, 0.1) var fallback_distance: float = 3.0
@export_range(0.0, 0.1, 0.001) var surface_offset: float = 0.01

@onready var _marker_mesh: MeshInstance3D = $MarkerMesh
@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D


func _ready() -> void:
	_setup_visual()
	_update_indicator()


func _physics_process(_delta: float) -> void:
	_update_indicator()


func _setup_visual() -> void:
	var torus := _marker_mesh.mesh as TorusMesh
	if torus:
		torus.inner_radius = maxf(indicator_radius - ring_width, 0.01)
		torus.outer_radius = indicator_radius

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = indicator_color
	_marker_mesh.material_override = material


func _update_indicator() -> void:
	if not is_instance_valid(_player):
		visible = false
		return
	if _player.is_in_water():
		visible = false
		return

	var ray_origin := _player.global_position + Vector3.UP * 0.1
	var ray_end := ray_origin + Vector3.DOWN * max_projection_distance
	var hit := _find_nearest_surface(ray_origin, ray_end)
	if hit.is_empty():
		global_transform = Transform3D(Basis.IDENTITY, _player.global_position + Vector3.DOWN * fallback_distance)
		visible = true
		return

	var normal: Vector3 = hit.normal.normalized()
	var tangent := normal.cross(Vector3.FORWARD)
	if tangent.length_squared() < 0.001:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(normal).normalized()
	var basis := Basis(tangent, normal, bitangent).orthonormalized()
	var marker_position: Vector3 = hit.position + normal * (surface_offset + ring_width * 0.5)
	global_transform = Transform3D(basis, marker_position)
	visible = true


func _find_nearest_surface(ray_origin: Vector3, ray_end: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var body_query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	body_query.exclude = [_player.get_rid()]
	body_query.collide_with_areas = false
	body_query.collide_with_bodies = true
	var body_hit := space_state.intersect_ray(body_query)

	var area_hit := _find_water_surface(space_state, ray_origin, ray_end)
	if body_hit.is_empty():
		return area_hit
	if area_hit.is_empty():
		return body_hit
	var body_distance := ray_origin.distance_squared_to(body_hit.position)
	var area_distance := ray_origin.distance_squared_to(area_hit.position)
	return area_hit if area_distance < body_distance else body_hit


func _find_water_surface(space_state: PhysicsDirectSpaceState3D, ray_origin: Vector3, ray_end: Vector3) -> Dictionary:
	var excluded: Array[RID] = [_player.get_rid()]
	while true:
		var area_query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		area_query.exclude = excluded
		area_query.collide_with_areas = true
		area_query.collide_with_bodies = false
		var area_hit := space_state.intersect_ray(area_query)
		if area_hit.is_empty():
			return {}
		var collider := area_hit.collider as Area3D
		if collider and collider.has_method("_get_water_surface_y"):
			return area_hit
		excluded.append(area_hit.rid)
	return {}
