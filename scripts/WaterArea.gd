extends Area3D
## 水体模拟 —— 挂载在 Area3D（水体区域）上
##
## 功能：
##   1. 对 RigidBody3D 施加浮力、粘滞阻力、水流推力
##   2. 通知 CharacterBody3D（玩家）进入/离开水中

# ──────────── 导出参数 ────────────

## 水体密度 (kg/m³ 的比例因子，1.0 ≈ 淡水)
@export var water_density: float = 1.0
## 水体粘滞度，越大阻力越强
@export var viscosity: float = 2.0
## 水流方向（仅 XZ 平面，Y 分量会被强制清零）
@export var flow_direction: Vector3 = Vector3(1, 0, 0)
## 水流速度 (m/s)
@export var flow_speed: float = 2.0
## 重力加速度大小（与 ProjectSettings 保持一致）
@export var g: float = 9.8

# ──────────── 内部状态 ────────────

## 记录当前在水中的 RigidBody3D 及其入水瞬间速度
## key = RigidBody3D, value = { "entry_velocity": Vector3 }
var _rigid_bodies: Dictionary = {}
var _is_drained: bool = false
var _drain_tween: Tween

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 水流方向归一化，强制忽略 Y
	flow_direction.y = 0.0
	if flow_direction.length_squared() > 0.0:
		flow_direction = flow_direction.normalized()

# ━━━━━━━━━━━━━━━━━━━━━━ 物理帧 ━━━━━━━━━━━━━━━━━━━━━━

func _physics_process(delta: float) -> void:
	if _is_drained:
		return

	# 水面 Y 坐标 = 这个 Area3D 碰撞体的顶部
	var water_surface_y: float = _get_water_surface_y()

	# ── RigidBody3D（通用物体）──
	for body in _rigid_bodies.keys():
		if not is_instance_valid(body):
			_rigid_bodies.erase(body)
			continue
		_apply_water_physics_to_rigid(body, water_surface_y, delta)

func _get_water_surface_y() -> float:
	# 取 CollisionShape3D 的上表面作为水面
	for child in get_children():
		if child is CollisionShape3D:
			var shape = child.shape
			if shape is BoxShape3D:
				return child.global_position.y + shape.size.y * child.global_transform.basis.get_scale().y * 0.5
	# 回退：用 Area3D 自身位置
	return global_position.y

# ━━━━━━━━━━━━━━━━━━━━━━ RigidBody3D 水体物理 ━━━━━━━━━━━━━━━━━━━━━━

func _apply_water_physics_to_rigid(body: RigidBody3D, surface_y: float, delta: float) -> void:
	# ── 读取物体水体参数（由 WaterBody 组件提供，否则用默认值）──
	var obj_volume: float = 1.0
	var obj_mass: float = body.mass

	if body.has_meta("water_volume"):
		obj_volume = body.get_meta("water_volume")
	elif body.has_node("WaterBody"):
		var wb = body.get_node("WaterBody")
		obj_volume = wb.volume

	# ── 计算浸没比例 submerge_ratio ∈ [0, 1] ──
	var body_y: float = body.global_position.y
	# 用碰撞体近似高度
	var body_half_height: float = _estimate_half_height(body)
	var body_top: float = body_y + body_half_height
	var body_bottom: float = body_y - body_half_height

	var submerge_ratio: float = 0.0
	if body_top <= surface_y:
		# 完全浸没
		submerge_ratio = 1.0
	elif body_bottom >= surface_y:
		# 完全在水面之上（不应该出现，但防御）
		submerge_ratio = 0.0
	else:
		# 部分浸没
		submerge_ratio = clampf((surface_y - body_bottom) / (body_top - body_bottom), 0.0, 1.0)

	# ── 1. 浮力 (Archimedes) ──
	# F_buoyancy = ρ_water * V_submerged * g
	var buoyancy_force: float = water_density * obj_volume * submerge_ratio * g
	body.apply_central_force(Vector3.UP * buoyancy_force)

	# ── 2. 粘滞阻力（与速度方向相反）──
	var vel: Vector3 = body.linear_velocity
	# 阻力 = -viscosity * submerge_ratio * velocity
	var drag_force: Vector3 = -viscosity * submerge_ratio * vel
	body.apply_central_force(drag_force)

	# ── 3. 水流推力（仅 XZ 平面）──
	# 将物体推向水流方向，力的大小与浸没比例和粘滞度成正比
	var flow_force: Vector3 = flow_direction * flow_speed * viscosity * submerge_ratio
	flow_force.y = 0.0
	body.apply_central_force(flow_force)

# ━━━━━━━━━━━━━━━━━━━━━━ 信号回调 ━━━━━━━━━━━━━━━━━━━━━━

func _on_body_entered(body: Node3D) -> void:
	if _is_drained:
		return

	if body is RigidBody3D:
		_rigid_bodies[body] = {
			"entry_velocity": body.linear_velocity.length()
		}
	# 通知玩家进入水中
	if body.has_method("enter_water"):
		body.enter_water(self)

func _on_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		_rigid_bodies.erase(body)
	# 通知玩家离开水中
	if body.has_method("exit_water"):
		body.exit_water()


func drain(duration: float = 1.8, drain_depth: float = 1.25) -> void:
	if _is_drained:
		return

	_is_drained = true
	flow_speed = 0.0
	_rigid_bodies.clear()
	_notify_water_exit_for_overlapping_bodies()
	_disable_dead_zones(self)

	if _drain_tween:
		_drain_tween.kill()

	_drain_tween = create_tween()
	_drain_tween.set_parallel(true)
	_drain_tween.set_trans(Tween.TRANS_SINE)
	_drain_tween.set_ease(Tween.EASE_IN_OUT)

	var target_offset := Vector3.DOWN * drain_depth
	for child in get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			_drain_tween.tween_property(child, "position", child.position + target_offset, duration)

	_drain_tween.finished.connect(_finish_drain)


func _finish_drain() -> void:
	monitoring = false
	monitorable = false
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true


func _notify_water_exit_for_overlapping_bodies() -> void:
	for body in get_overlapping_bodies():
		if body.has_method("exit_water"):
			body.exit_water()


func _disable_dead_zones(root: Node) -> void:
	for child in root.get_children():
		if child is Area3D and child != self:
			child.monitoring = false
			child.monitorable = false
		if child is CollisionShape3D:
			child.disabled = true
		_disable_dead_zones(child)

# ━━━━━━━━━━━━━━━━━━━━━━ 辅助函数 ━━━━━━━━━━━━━━━━━━━━━━

## 估算物体的半高度，用于计算浸没比例
func _estimate_half_height(body: RigidBody3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape:
			var s = child.shape
			if s is BoxShape3D:
				return s.size.y * 0.5
			elif s is SphereShape3D:
				return s.radius
			elif s is CapsuleShape3D:
				return s.height * 0.5
			elif s is CylinderShape3D:
				return s.height * 0.5
	return 0.5  # 默认
