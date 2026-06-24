extends CharacterBody3D
## 玩家控制器 —— 挂载在 CharacterBody3D 上
##
## 陆地行为：WASD 移动 + 空格跳跃
## 水中行为：
##   - Y 轴受浮力影响（向水面漂浮）
##   - 水流方向轴（如 X）完全由水流控制，玩家无法操作
##   - 垂直于水流的轴（如 Z）玩家仍可自由移动
##   - 无法跳跃

# ──────────── 导出参数 ────────────

## 陆地移动速度
@export var move_speed: float = 5.0
## 跳跃初速度
@export var jump_velocity: float = 4.5
## 水中移动速度（Z 轴方向）
@export var swim_speed: float = 3.0
## 水中浮力强度，控制角色向水面浮起的速度
@export var buoyancy_strength: float = 6.0
## 水中垂直阻尼，防止角色在水面反复弹跳
@export var water_vertical_damping: float = 4.0
## 旋转速度（平滑转向）
@export var rotation_speed: float = 12.0
@export_group("Physical Impulses")
@export var player_physics_mass: float = 1.0
@export var contact_impulse_scale: float = 1.0
@export var max_contact_mass_ratio: float = 4.0
@export var min_impulse_contact_speed: float = 1.0
@export var max_external_speed: float = 18.0
@export var external_velocity_damping: float = 4.5


# ──────────── 内部状态 ────────────

const RUN_ANIMATION := &"run"
const JUMP_ANIMATION := &"jump"
const STOPPED_ANIMATION := &""
const ANIMATION_MOVE_THRESHOLD := 0.01

@onready var _animation_player: AnimationPlayer = $"Cartoon Character/AnimationPlayer"

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _current_animation: StringName = STOPPED_ANIMATION

## 是否在水中
var _in_water: bool = false
## 当前水流速度向量（由 WaterArea 传入）
var _water_flow: Vector3 = Vector3.ZERO
## 水面 Y 坐标
var _water_surface_y: float = 0.0
## 当前水体区域引用
var _water_area: Node = null
var _external_velocity: Vector3 = Vector3.ZERO
var _applied_external_velocity: Vector3 = Vector3.ZERO

# ━━━━━━━━━━━━━━━━━━━━━━ 水体通知接口 ━━━━━━━━━━━━━━━━━━━━━━

## 由 WaterArea._on_body_entered 调用
func enter_water(water_area: Node) -> void:
	_in_water = true
	_water_area = water_area
	# 读取水流参数
	_water_flow = water_area.flow_direction * water_area.flow_speed

## 由 WaterArea._on_body_exited 调用
func exit_water() -> void:
	_in_water = false
	_water_area = null
	_water_flow = Vector3.ZERO


func is_in_water() -> bool:
	return _in_water


func apply_physics_impulse(impulse: Vector3, source_mass: float = 1.0) -> void:
	if impulse.length_squared() <= 0.0001:
		return

	var safe_player_mass := maxf(player_physics_mass, 0.001)
	var mass_ratio := clampf(source_mass / safe_player_mass, 0.0, max_contact_mass_ratio)
	_add_external_velocity(impulse / safe_player_mass * mass_ratio * contact_impulse_scale)

# ━━━━━━━━━━━━━━━━━━━━━━ 物理帧 ━━━━━━━━━━━━━━━━━━━━━━

func _physics_process(delta: float) -> void:
	if _in_water:
		_process_water_movement(delta)
	else:
		_process_land_movement(delta)

	_apply_external_velocity()

	# ── 转向逻辑 ──
	# 根据水平速度方向进行平滑旋转
	var horiz_vel = Vector3(velocity.x, 0.0, velocity.z)
	var has_land_input := Input.get_vector("left", "right", "up", "down") != Vector2.ZERO
	if horiz_vel.length_squared() > 0.01 and (_in_water or has_land_input):
		var target_dir = horiz_vel.normalized()
		var target_basis = Basis.looking_at(target_dir, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, rotation_speed * delta).orthonormalized()

	move_and_slide()
	_transfer_contact_impulses()
	_restore_control_velocity()
	_damp_external_velocity(delta)
	_update_animation_state(has_land_input)


# ━━━━━━━━━━━━━━━━━━━━━━ 陆地移动 ━━━━━━━━━━━━━━━━━━━━━━

func _process_land_movement(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# 跳跃
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# XZ 平面移动
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := _get_camera_relative_direction(input_dir)

	if direction != Vector3.ZERO:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		var horizontal_velocity := Vector2(velocity.x, velocity.z)
		horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, move_speed * delta * 10.0)
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.y

# ━━━━━━━━━━━━━━━━━━━━━━ 水中移动 ━━━━━━━━━━━━━━━━━━━━━━

func _process_water_movement(delta: float) -> void:
	# 获取水面高度
	if _water_area and _water_area.has_method("_get_water_surface_y"):
		_water_surface_y = _water_area._get_water_surface_y()

	# ── Y 轴：浮力 + 阻尼 ──
	var depth: float = _water_surface_y - global_position.y
	# depth > 0 表示在水面以下，给予向上的浮力
	# depth < 0 表示在水面以上，让重力拉回
	if depth > 0.0:
		# 在水面以下：浮力向上
		velocity.y += buoyancy_strength * depth * delta
	else:
		# 在水面以上：正常重力
		velocity.y -= _gravity * delta

	# 垂直方向阻尼，防止剧烈振荡
	velocity.y -= velocity.y * water_vertical_damping * delta

	# ── X 轴（水流方向）：完全由水流控制 ──
	# 玩家无法操控水流方向上的分量
	# 水流向量的 X/Z 都可能有值，这里用投影方式处理
	var flow_dir: Vector3 = _water_flow.normalized() if _water_flow.length_squared() > 0.0 else Vector3.ZERO

	if flow_dir != Vector3.ZERO:
		var flow_spd: float = _water_flow.length()
		# 水流方向上的速度强制设为水流速度
		velocity = velocity - flow_dir * velocity.dot(flow_dir) + flow_dir * flow_spd

	# ── Z 轴（垂直于水流的水平方向）：玩家可控 ──
	var input_dir := Input.get_vector("left", "right", "up", "down")
	# 计算垂直于水流的水平方向
	var perp_dir: Vector3
	if flow_dir != Vector3.ZERO:
		perp_dir = Vector3(-flow_dir.z, 0.0, flow_dir.x)  # 水平面上的垂直向量
	else:
		perp_dir = Vector3(0, 0, 1)

	# 将相机相对移动方向投影到垂直于水流的可控方向
	var perp_input: float = _get_camera_relative_direction(input_dir).dot(perp_dir)
	var perp_velocity: float = perp_input * swim_speed

	# 移除原有的 perp 分量，替换为玩家输入
	velocity = velocity - perp_dir * velocity.dot(perp_dir) + perp_dir * perp_velocity

	# ── 水中禁止跳跃 ──
	# （不处理跳跃输入即可）

## 获取玩家当前的朝向向量 (3D)
func _apply_external_velocity() -> void:
	_applied_external_velocity = _external_velocity
	velocity += _applied_external_velocity


func _restore_control_velocity() -> void:
	velocity -= _applied_external_velocity
	_applied_external_velocity = Vector3.ZERO


func _damp_external_velocity(delta: float) -> void:
	var damping := maxf(external_velocity_damping, 0.0)
	if damping <= 0.0:
		return
	_external_velocity = _external_velocity.move_toward(Vector3.ZERO, damping * delta)


func _transfer_contact_impulses() -> void:
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		if collider is RigidBody3D:
			var body := collider as RigidBody3D
			var contact_point := collision.get_position()
			var contact_offset := contact_point - body.global_position
			var surface_velocity := body.linear_velocity + body.angular_velocity.cross(contact_offset)
			if surface_velocity.length() < min_impulse_contact_speed:
				continue

			var safe_player_mass := maxf(player_physics_mass, 0.001)
			var mass_influence := clampf(body.mass / safe_player_mass, 0.0, 1.0)
			_inherit_external_velocity(surface_velocity * mass_influence * contact_impulse_scale)
		else:
			var collider_velocity := collision.get_collider_velocity()
			if collider_velocity.length() < min_impulse_contact_speed:
				continue
			_inherit_external_velocity(collider_velocity * contact_impulse_scale)


func _inherit_external_velocity(target_velocity: Vector3) -> void:
	if target_velocity.length_squared() <= 0.0001:
		return

	var target_direction := target_velocity.normalized()
	var current_speed := _external_velocity.dot(target_direction)
	var target_speed := target_velocity.length()
	if current_speed >= target_speed:
		return

	_external_velocity += target_direction * (target_speed - current_speed)
	_clamp_external_velocity()


func _add_external_velocity(delta_velocity: Vector3) -> void:
	if delta_velocity.length_squared() <= 0.0001:
		return

	_external_velocity += delta_velocity
	_clamp_external_velocity()


func _clamp_external_velocity() -> void:
	if _external_velocity.length() > max_external_speed:
		_external_velocity = _external_velocity.normalized() * max_external_speed


func get_facing_direction() -> Vector3:
	return -global_transform.basis.z.normalized()


func _update_animation_state(has_land_input: bool) -> void:
	if _animation_player == null:
		return

	if _in_water:
		_stop_animation()
		return

	if not is_on_floor():
		_play_animation(JUMP_ANIMATION)
		return

	var horizontal_speed_squared := Vector2(velocity.x, velocity.z).length_squared()
	if has_land_input and horizontal_speed_squared > ANIMATION_MOVE_THRESHOLD:
		_play_animation(RUN_ANIMATION)
	else:
		_stop_animation()


func _play_animation(animation_name: StringName) -> void:
	if _current_animation == animation_name:
		return
	if not _animation_player.has_animation(animation_name):
		return

	_animation_player.play(animation_name)
	_current_animation = animation_name


func _stop_animation() -> void:
	if _current_animation == STOPPED_ANIMATION:
		return

	_animation_player.stop()
	_current_animation = STOPPED_ANIMATION


func _get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	var camera_forward := -camera.global_transform.basis.z
	camera_forward.y = 0.0
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0

	if camera_forward.is_zero_approx() or camera_right.is_zero_approx():
		return Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	return (camera_right * input_dir.x - camera_forward * input_dir.y).normalized()
