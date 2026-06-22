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


# ──────────── 内部状态 ────────────

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## 是否在水中
var _in_water: bool = false
## 当前水流速度向量（由 WaterArea 传入）
var _water_flow: Vector3 = Vector3.ZERO
## 水面 Y 坐标
var _water_surface_y: float = 0.0
## 当前水体区域引用
var _water_area: Node = null

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

# ━━━━━━━━━━━━━━━━━━━━━━ 物理帧 ━━━━━━━━━━━━━━━━━━━━━━

func _physics_process(delta: float) -> void:
	if _in_water:
		_process_water_movement(delta)
	else:
		_process_land_movement(delta)

	# ── 转向逻辑 ──
	# 根据水平速度方向进行平滑旋转
	var horiz_vel = Vector3(velocity.x, 0.0, velocity.z)
	if horiz_vel.length_squared() > 0.01:
		var target_dir = horiz_vel.normalized()
		var target_basis = Basis.looking_at(target_dir, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, rotation_speed * delta).orthonormalized()

	move_and_slide()


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
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * delta * 10.0)

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

	# input_dir.y 对应 W/S（前后），映射到垂直于水流的方向
	var perp_input: float = input_dir.y  # W 为负 y，对应正方向
	var perp_velocity: float = perp_input * swim_speed

	# 移除原有的 perp 分量，替换为玩家输入
	velocity = velocity - perp_dir * velocity.dot(perp_dir) + perp_dir * perp_velocity

	# ── 水中禁止跳跃 ──
	# （不处理跳跃输入即可）

## 获取玩家当前的朝向向量 (3D)
func get_facing_direction() -> Vector3:
	return -global_transform.basis.z.normalized()
