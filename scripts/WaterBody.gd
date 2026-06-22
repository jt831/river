extends Node
class_name WaterBody
## 水体参数组件 —— 挂载在 RigidBody3D 的子节点上
##
## 为物体提供「体积」属性，WaterArea 会读取它来计算浮力。
## 物体的质量直接使用 RigidBody3D.mass。
##
## 行为总结：
##   - 质量大 + 体积小 → 密度 > 水 → 沉底
##   - 质量小 + 体积大 → 密度 < 水 → 上浮
##   - 入水速度快 → 先冲入深处，再被浮力拉回（上下振荡）
##   - 粘滞度高 → 振荡迅速衰减，很快稳定

## 物体的等效排水体积 (m³)
## 浮力 = 水密度 × 体积 × 浸没比例 × g
## 如果 volume × water_density > mass，物体会浮起来
@export var volume: float = 1.0

func _ready() -> void:
	# 将 volume 写入父节点的 meta，方便 WaterArea 快速读取
	var parent = get_parent()
	if parent is RigidBody3D:
		parent.set_meta("water_volume", volume)
