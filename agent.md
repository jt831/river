# River 项目说明

## 项目定位

`River` 是一个 Godot 4.6 的 3D 水流物理玩法原型。当前可运行内容集中在单一测试场景中，用于验证三组机制：玩家在陆地与水中的差异化移动、刚体在水中的浮力/阻力/水流响应，以及玩家通过鼠标抓取和抛掷刚体。

- 主场景：`res://scenes/game.tscn`
- 渲染器：Forward Plus（Windows 使用 D3D12）
- 3D 物理引擎：Jolt Physics
- 脚本语言：GDScript

## 目录与入口

- `project.godot`：项目配置、主场景和输入映射。
- `scenes/game.tscn`：测试关卡和所有子场景的组装入口。
- `scenes/character_body_3d.tscn`：玩家本体及抓取/投掷子系统。
- `scenes/water.tscn`：可视水体和水域碰撞区域。
- `scenes/body.tscn`：用于测试浮力和抓投的球形刚体。
- `scripts/`：玩家、水域、浮体和抓投逻辑。
- `assets/water.tres`：半透明青色水面材质。
- `.godot/`：Godot 生成缓存，已被 Git 忽略，不属于源码。

## 主场景组成

`game.tscn` 的根节点是 `Game (Node3D)`，包含：

- 一个缩放后的 `water.tscn`，中心约位于 `y = -1.61`，形成宽而浅的水域。
- 一个固定视角的 `Camera3D`；当前没有跟随玩家或鼠标控制镜头的代码。
- 一个 `character_body_3d.tscn` 玩家实例。
- 一个 `body.tscn` 球形刚体实例。
- 一个 `DirectionalLight3D`。
- 两个带网格与碰撞体的 `StaticBody3D`，分别充当地面/平台和较大的底部边界。

场景使用 Godot 基础几何体，没有外部模型或纹理资源。

## 输入与操作

- `W/A/S/D`：移动；输入动作分别为 `up/left/down/right`。
- `Space`：陆地跳跃，对应 `jump`；水中不处理跳跃。
- 鼠标左键：对应 `grab`。指向可抓取刚体时抓起；持有物体时再次点击则投掷。

玩家移动基于当前活动相机在水平 XZ 平面上的前向与右向；相机俯仰不会引入垂直移动。

## 玩家移动系统

`scripts/PlayerController.gd` 挂在 `CharacterBody3D` 上。

陆地状态下，玩家按 WASD 以 `move_speed = 5.0` 移动，按空格以 `jump_velocity = 4.5` 起跳，离地时应用项目默认重力。没有输入时，水平速度保持原方向并快速衰减，角色停止继续追赶残余速度方向；移动输入期间，角色会按照当前水平速度以 `rotation_speed = 12.0` 平滑转向。

角色模型的 `Cartoon Character/AnimationPlayer` 装载了 `run` 和 `jump` 动画。陆地移动且有水平速度时播放 `run`；跳跃或离地时播放 `jump`，并优先于移动动画；落地静止时停止当前动画。水中移动不播放 `run`，水中仍不响应跳跃动画。

水中状态由 `WaterArea` 调用 `enter_water()` / `exit_water()` 切换。水中行为为：

- 根据角色与水面的深度施加向上浮力，并使用垂直阻尼降低水面附近的振荡。
- 水流方向上的速度完全由水流速度覆盖，玩家无法逆流或顺流主动加速。
- 玩家输入只控制水平面中垂直于水流的方向，速度为 `swim_speed = 3.0`。
- 不响应跳跃。

## 水体物理系统

`scenes/water.tscn` 的根节点是挂载 `scripts/WaterArea.gd` 的 `Area3D`。它同时承担触发区、水面高度来源和水体物理执行器的职责。

默认水体参数：密度 `1.0`、粘滞度 `2.0`、流向 `Vector3(1, 0, 0)`、流速 `2.0`、重力常量 `9.8`。启动时会清除流向的 Y 分量并归一化。

水面高度取第一个盒形 `CollisionShape3D` 的顶部；找不到合适碰撞体时退回到 `Area3D.global_position.y`。刚体进入区域后被记录，每个物理帧按碰撞形状估算半高和浸没比例，并施加：

1. 浮力：`water_density * volume * submerge_ratio * g`，方向向上。
2. 粘滞阻力：与线速度反向，随粘滞度和浸没比例增大。
3. 水流推力：沿水平流向，随流速、粘滞度和浸没比例增大。

`scripts/WaterBody.gd` 是刚体的浮力参数组件，提供 `volume`（默认 `1.0`），并在 `_ready()` 中写入父刚体的 `water_volume` metadata。`WaterArea` 优先读取该 metadata，也兼容直接读取名为 `WaterBody` 的子节点。若二者都不存在，则使用默认体积 `1.0`。

## 抓取与投掷系统

`scripts/GrabThrowController.gd` 是玩家的子节点，依赖同级场景中的 `CarryPivot`、`TrajectoryLine` 和 `LandingIndicator`。`scripts/Grabbable.gd` 是空的标识组件；只有包含名为 `Grabbable` 子节点的 `RigidBody3D` 才能被抓取。

未持有物体时，控制器从当前相机穿过鼠标位置发射射线：命中可抓取刚体后，距离玩家不超过 `grab_range = 4.0` 显示绿色描边，超出范围显示红色描边。描边由运行时生成的外扩反面 Shader 实现。

抓取后，刚体会清零速度、冻结物理并暂时忽略与玩家的碰撞。每个物理帧，它以 `carry_lerp_speed = 15.0` 插值到玩家前上方的 `CarryPivot`；玩家到目标点之间若有障碍，会把携带位置推到障碍表面外侧。

投掷目标来自鼠标射线命中点，未命中时退回玩家高度平面，水平距离限制为 `max_throw_distance = 12.0`。控制器根据固定的 `arc_peak_height = 2.5` 和项目重力解析计算初速度，并用离散物理步预测轨迹。轨迹通过 `ImmediateMesh` 绘制成面向相机的带状网格；首次预测碰撞处显示环形落点标记。再次点击左键后解除冻结、恢复玩家碰撞，并把预测初速度赋给刚体。

## 场景组件关系

```text
Game
├─ Water Area3D [WaterArea]
├─ CharacterBody3D [PlayerController]
│  └─ GrabThrowController
│     ├─ CarryPivot
│     ├─ TrajectoryLine
│     └─ LandingIndicator
├─ RigidBody3D (body.tscn)
│  ├─ WaterBody
│  └─ Grabbable
├─ Camera3D / DirectionalLight3D
└─ StaticBody3D platforms
```

关键交互链路：

- `WaterArea` 通过 Area3D 的 `body_entered/body_exited` 信号发现刚体和玩家。
- 对玩家，`WaterArea` 调用其水体通知接口；玩家自行计算水中运动。
- 对刚体，`WaterArea` 直接施加力，并从 `WaterBody` 获取体积。
- `GrabThrowController` 通过鼠标射线和 `Grabbable` 标识发现目标，直接控制目标刚体的冻结、位置与投掷速度。

## 当前实现注意事项

- 这是机制验证原型，除左上角调试时间和玩家移动/跳跃动画触发外，尚无正式 UI、音频、关卡流程、存档或测试代码。
- 相机当前为固定视角；若后续调整相机朝向，玩家的陆地移动和水中可控方向会自动随相机旋转。
- 玩家和刚体采用两套不同的浮力模型：玩家按深度调整速度，刚体按估算浸没比例施力。
- 刚体浸没高度只检查其直接子节点中的第一个常见碰撞形状，不处理旋转后的精确体积或复杂/嵌套碰撞体。
- 抓取会直接冻结刚体并插值修改全局变换，不是关节式物理抓取。
- 轨迹预测使用项目默认重力，未纳入空气阻力、水中力或投掷后可能发生的动态碰撞变化。
- `WaterArea._apply_water_physics_to_rigid()` 中读取了 `body.mass`，但当前浮力计算未直接使用该局部变量；质量仍会通过刚体动力学影响加速度。
- `_rigid_bodies` 保存的 `entry_velocity` 当前未被后续逻辑使用。

## 时间系统

`scripts/TimeSystem.gd` 通过 Autoload 注册为全局 `TimeSystem`。每次启动从 `0` 秒开始，正常运行时按单调时钟累计；如果电脑时钟向前跳变超过采样容差，则补入向前的差值。电脑时钟回拨不会减少或冻结游戏时间。

程序失去焦点或处于后台时仍会累计时间；场景树暂停期间不累计，恢复时会重置采样基准，避免补计暂停时长。外部代码可读取 `TimeSystem.total_seconds`、调用 `get_total_seconds()`，或监听 `time_changed(total_seconds)` 信号。

主场景左上角的 `DebugUI/TimeDisplay` 使用补零的 12 小时制显示 `小时:分钟 AM/PM`，例如 `01:05 PM`。显示每 24 小时循环，不影响底层持续增长的累计秒数。

## Deadzone 组件

`scripts/Deadzone.gd` 和 `scripts/Clearzone.gd` 是可复用的 `Area3D` 结果区域组件，共享 `GameResultZone` 的玩家分组筛选和触发逻辑。玩家进入 Deadzone 后显示全屏“游戏失败”，玩家进入 Clearzone 后显示全屏“游戏成功”；可抓取刚体不会触发胜利。主场景中的 `clearRange` 使用 `StaticBody3D + Area3D` 拆分：实体碰撞体阻挡玩家和可抓取物体，前侧的玩家触发区只负责胜利检测。场景会在结果画面出现时暂停，玩家点击任意位置后解除暂停并重载当前场景。默认玩家分组为 `player`，区域的位置、尺寸和碰撞层由宿主场景配置。

## 协作约定

- 修改前先阅读相关脚本、场景及其节点依赖，尽量保持改动范围最小并沿用现有写法。
- 不要手工维护 `.godot/`、`*.uid` 或 `*.import` 生成内容，除非任务明确要求。
- 批量删除文件前必须先向用户确认。
- 每次修改项目后一并更新本文件
- 使用 `Godot_v4.6.2-stable_win64.exe --headless --path . --quit` 或 `--check-only` 做验证时，需要用提升权限运行；普通沙箱会阻止 Godot 写入 `user://logs` 等用户目录，可能出现 `Failed to open 'user://logs/...'` 后引擎崩溃。

## 玩家位置标记

`scenes/character_body_3d.tscn` 的 `PlayerPositionIndicator` 是独立的玩家位置可视化组件。玩家不在水中时，它每个物理帧从玩家位置向下检测实体表面和水面，并将无碰撞、无阴影的青色圆环贴合到一定距离内最近的有效表面；其他 `Area3D` 不会被当作表面。下方没有有效表面时，圆环固定显示在玩家下方。玩家进入水中后圆环隐藏，离开水中后恢复显示。圆环的颜色、半径、环宽、最大检测距离、无表面时的跟随距离和表面偏移均可在组件脚本中配置。
