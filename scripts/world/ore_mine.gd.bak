##############################################################################
# OreMine - 矿点脚本
#
# 设计目的：
# - 地图四周固定矿点
# - 需要攻击才能采集
# - 独立刷新时间
# - 依据阶段追加掉落
##############################################################################
extends StaticBody2D

##############################################################################
# 常量
##############################################################################

## 矿点被击碎所需命中次数
## 单位：次
## 作用：避免一次高伤害直接清空矿点
## 调整范围：1-10
## 当前值：3
const MAX_HP: int = 3

## 矿点显示缩放
## 单位：倍数
## 作用：让矿点更显眼
## 调整范围：1.0-2.0
## 当前值：1.4
const MINE_SPRITE_SCALE: float = 1.4

## 掉落点位偏移
## 单位：像素
## 作用：避免掉落完全重叠
## 调整范围：0-24
## 当前值：8
const PICKUP_SPAWN_OFFSET: float = 8.0

##############################################################################
# 导出配置
##############################################################################

## 矿点ID（用于日志）
@export var mine_id: String = ""

## 刷新时间（秒）
@export var respawn_time: float = 120.0

## 掉落区间
@export var drop_min: int = 2
@export var drop_max: int = 4

## 阶段加成（S2/S3/S4）
@export var stage_bonus_s2: int = 0
@export var stage_bonus_s3: int = 0
@export var stage_bonus_s4: int = 0

##############################################################################
# 运行期状态
##############################################################################

## 当前耐久
var current_hp: int = MAX_HP

## 是否可采集
var is_available: bool = true

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var respawn_timer: Timer = $RespawnTimer

##############################################################################
# 初始化
##############################################################################

## 节点就绪
func _ready() -> void:
	add_to_group("mine")
	collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)
	collision_mask = 0
	z_index = 5
	if respawn_timer:
		respawn_timer.timeout.connect(_on_respawn_timeout)
	# 占位绿块会误导玩家，这里不再生成占位贴图；等待正式矿石贴图接入
	if sprite:
		sprite.visible = false
	_reset_mine()

## 初始化矿点配置
##
## 参数：
##   config - 字典配置（来自Main生成）
func initialize(config: Dictionary) -> void:
	mine_id = config.get("mine_id", mine_id)
	respawn_time = float(config.get("respawn_time", respawn_time))
	drop_min = int(config.get("drop_min", drop_min))
	drop_max = int(config.get("drop_max", drop_max))
	stage_bonus_s2 = int(config.get("stage_bonus_s2", stage_bonus_s2))
	stage_bonus_s3 = int(config.get("stage_bonus_s3", stage_bonus_s3))
	stage_bonus_s4 = int(config.get("stage_bonus_s4", stage_bonus_s4))
	_reset_mine()

##############################################################################
# 受击与采集
##############################################################################

## 受击入口
func take_damage(_dmg: float) -> void:
	if not is_available:
		return
	current_hp -= 1
	if current_hp <= 0:
		_harvest()

## 采集矿点并生成掉落
func _harvest() -> void:
	is_available = false
	var ore_drop: int = randi_range(drop_min, drop_max)
	var bonus: int = _get_stage_bonus()
	_spawn_ore_pickup(ore_drop + bonus)
	_disable_mine()
	_start_respawn_timer()
	print("[OreMine] 采集: ", mine_id, " +", ore_drop + bonus)

## 生成矿石拾取物
##
## 参数：
##   amount - 矿石数量
func _spawn_ore_pickup(amount: int) -> void:
	var pickup_scene: PackedScene = load("res://scenes/world/pickup.tscn")
	if not pickup_scene:
		return
	var pickup: Area2D = pickup_scene.instantiate()
	pickup.global_position = global_position + Vector2(
		randf_range(-PICKUP_SPAWN_OFFSET, PICKUP_SPAWN_OFFSET),
		randf_range(-PICKUP_SPAWN_OFFSET, PICKUP_SPAWN_OFFSET)
	)
	var config: Dictionary = {
		"type": "ore",
		"ore": amount
	}
	if pickup.has_method("initialize"):
		pickup.initialize(config)
	get_parent().add_child(pickup)

##############################################################################
# 刷新
##############################################################################

## 启动刷新计时
func _start_respawn_timer() -> void:
	if respawn_timer:
		respawn_timer.wait_time = respawn_time
		respawn_timer.start()

## 刷新计时结束回调
func _on_respawn_timeout() -> void:
	_reset_mine()

## 重置矿点状态
func _reset_mine() -> void:
	is_available = true
	current_hp = MAX_HP
	_enable_mine()

## 隐藏并禁用碰撞
func _disable_mine() -> void:
	if sprite:
		sprite.visible = false
	if collision_shape:
		collision_shape.disabled = true

## 显示并启用碰撞
func _enable_mine() -> void:
	if sprite:
		# 没有正式贴图时仍保持隐藏，避免绿色占位块
		if sprite.texture:
			sprite.visible = true
	if collision_shape:
		collision_shape.disabled = false

##############################################################################
# 阶段加成
##############################################################################

## 根据当前分钟返回阶段加成
func _get_stage_bonus() -> int:
	var minute: int = 0
	if GameManager:
		minute = GameManager.get_current_minute()
	if minute >= 15:
		return stage_bonus_s4
	if minute >= 10:
		return stage_bonus_s3
	if minute >= 5:
		return stage_bonus_s2
	return 0

##############################################################################
# 占位图
##############################################################################

## 生成矿点占位图（无美术资源时使用）
func _generate_placeholder_sprite() -> void:
	# 占位渲染已禁用（避免绿色方块），保留函数占坑以备后续接入正式贴图
	pass
