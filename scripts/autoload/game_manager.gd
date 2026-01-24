##############################################################################
# GameManager - 游戏管理器（预留）
#
# 功能说明：
# 1. 管理游戏时间（20分钟倒计时）
# 2. 管理双经济系统（金币、矿石）
# 3. 管理玩家等级和经验
# 4. 发出各种游戏事件信号
#
# 本脚本为预留接口，角色系统需要但暂未完整实现
##############################################################################
extends Node

## 当前游戏时间（秒）
var current_time: float = 0.0

## 玩家等级
var player_level: int = 1

## 玩家经验
var player_exp: float = 0.0

## 金币
var gold: int = 0

## 矿石
var ore: int = 0

## 信号定义
signal time_changed(seconds: float)
signal level_up(level: int)
signal gold_changed(amount: int)
signal ore_changed(amount: int)
signal game_over()

## 初始化
func _ready() -> void:
	print("[GameManager] 游戏管理器初始化（预留）")

## 添加金币
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

## 消耗金币
func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false

## 添加矿石
func add_ore(amount: int) -> void:
	ore += amount
	ore_changed.emit(ore)

## 消耗矿石
func spend_ore(amount: int) -> bool:
	if ore >= amount:
		ore -= amount
		ore_changed.emit(ore)
		return true
	return false

## 添加经验
func add_exp(amount: float) -> void:
	player_exp += amount
	# TODO: 检查是否升级

## 获取当前等级
func get_player_level() -> int:
	return player_level
