##############################################################################
# SpawnerConfig - 刷怪配置（全局）
#
# 设计目的：
# - 以“时间段”为索引，集中管理刷怪频率/批量/阶段权重等关键参数
# - 作为刷怪系统与Boss系统的统一配置来源，避免散落常量
#
# 主要职责：
# 1) 提供按“分钟”查询刷怪间隔与批量大小
# 2) 提供Boss出现规则与小怪规则
# 3) 提供阶段映射与权重字段名
#
# 调用链示例：
# - EnemySpawner(或刷怪系统) -> get_spawn_interval / get_batch_size
# - Boss系统 -> BOSS_* 常量与 get_stage / get_weight_field
#
# 修复：2026-01-27 重新写回中文注释
##############################################################################
extends Node

##############################################################################
# 刷怪频率
##############################################################################

## 每分钟刷怪频率（值越大 => 刷怪越快）
## key为“起始分钟”（含），value为该阶段每分钟刷怪次数
const SPAWN_RATE_PER_MINUTE: Dictionary = {
	0:  12.0,   # 0-5分钟
	5:  20.0,   # 5-10分钟
	10: 30.0,  # 10-15分钟
	15: 45.0   # 15-20分钟
}

## 获取刷怪间隔（秒）
## 参数：minute 当前分钟
## 返回：每次刷怪的间隔秒数
func get_spawn_interval(minute: int) -> float:
	var rate: float = _get_spawn_rate(minute)
	return 60.0 / rate

## 每次刷怪批量（同样按阶段配置）
const SPAWN_BATCH_SIZE: Dictionary = {
	0:  3,
	5:  5,
	10: 7,
	15: 9
}

## 获取当前阶段的刷怪数量
## 参数：minute 当前分钟
## 返回：该阶段的刷怪数量
func get_batch_size(minute: int) -> int:
	return _get_config_value(SPAWN_BATCH_SIZE, minute)

##############################################################################
# 难度倍率
##############################################################################

## 难度倍率：可作为全局增益或惩罚（目前默认1.0）
const DIFFICULTY_MULT: Dictionary = {
	"hp": 1.0,
	"damage": 1.0,
	"speed": 1.0
}

##############################################################################
# 权重与Excel
##############################################################################

## 是否使用Excel权重（从表格读取刷怪权重）
const USE_WEIGHT_FROM_EXCEL: bool = true

## 默认权重（未读取到时回退）
const DEFAULT_WEIGHT: float = 1.0

##############################################################################
# 刷怪距离
##############################################################################

## 刷怪最小距离（相对玩家的最小半径）
const SPAWN_DISTANCE_MIN: float = 600.0

## 刷怪最大距离（相对玩家的最大半径）
const SPAWN_DISTANCE_MAX: float = 1000.0

## 区域权重（决定刷怪更偏向哪个方向）
const SPAWN_REGION_WEIGHT: Dictionary = {
	"center": 0.6,
	"north": 0.1,
	"south": 0.1,
	"east": 0.1,
	"west": 0.1
}

##############################################################################
# Boss规则
##############################################################################

## Boss出现分钟列表（与表格或关卡逻辑匹配）
const BOSS_SPAWN_MINUTES: Array[int] = [5, 10, 15, 20]

## Boss出现时是否清理场上小怪
const BOSS_CLEAR_ENEMIES: bool = true

## Boss出现时是否暂停刷怪计时
const BOSS_PAUSE_TIMER: bool = true

## Boss战时间限制（0表示不限制）
const BOSS_TIME_LIMIT: float = 0.0

## 是否在特定Boss分钟刷新小怪
const BOSS_SPAWN_MINIONS: Dictionary = {
	5: false,
	10: false,
	15: true,
	20: true
}

## Boss小怪刷新间隔（秒）
const BOSS_MINION_SPAWN_INTERVAL: float = 10.0

## 每次Boss小怪刷新数量
const BOSS_MINION_SPAWN_COUNT: int = 3

##############################################################################
# 其他扩展规则
##############################################################################

## POO系怪物是否在矿石附近刷出（用于“产矿”类逻辑）
const POO_SPAWN_NEAR_ORE_RADIUS: float = 200.0

## SPLIT_ORB是否只在视野范围内刷出（避免离屏生成）
const SPLIT_ORB_SPAWN_IN_VIEW_ONLY: bool = true

## 全局怪物数量上限
const MAX_ENEMY_COUNT: int = 220

## 是否使用“单怪物类型上限”（与MAX_ENEMY_COUNT叠加使用）
const USE_INDIVIDUAL_CAP: bool = true

##############################################################################
# 工具函数
##############################################################################

## 获取当前分钟的刷怪频率
func _get_spawn_rate(minute: int) -> float:
	return _get_config_value(SPAWN_RATE_PER_MINUTE, minute)

## 通用配置读取：根据minute匹配最近的“起始分钟”配置
## 参数：
## - config_dict: 以分钟为key的配置字典
## - minute: 当前分钟
## 返回：匹配到的配置值
func _get_config_value(config_dict: Dictionary, minute: int) -> float:
	var keys: Array = config_dict.keys()
	keys.sort()

	var selected_key: int = 0
	for key: int in keys:
		if minute >= key:
			selected_key = key
		else:
			break

	return config_dict[selected_key]

## 获取当前阶段（用于权重字段与阶段UI）
## 规则：0-5分钟为1阶段，依次递增
func get_stage(minute: int) -> int:
	if minute < 5:
		return 1
	elif minute < 10:
		return 2
	elif minute < 15:
		return 3
	else:
		return 4

## 获取Excel表中权重字段名（S1/S2/S3/S4）
func get_weight_field(minute: int) -> String:
	var stage: int = get_stage(minute)
	return "S1(1-5)" if stage == 1 else "S2(6-10)" if stage == 2 else "S3(11-15)" if stage == 3 else "S4(16-20)"

## 打印当前配置（用于调试）
func print_current_config(minute: int) -> void:
	print("\n=== 刷怪配置：", minute, "分钟 ===")
	print("刷怪间隔: ", get_spawn_interval(minute), "秒")
	print("批量大小: ", get_batch_size(minute))
	print("难度倍率: HP=", DIFFICULTY_MULT["hp"], " 伤害=", DIFFICULTY_MULT["damage"])
	print("阶段: S", get_stage(minute))
