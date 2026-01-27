##############################################################################
# GameManager - 游戏管理器
#
# 设计目的：
# - 统一管理游戏计时、经验/等级、金币/矿石
# - 广播核心信号给UI/刷怪系统
#
# 调用链：
# - _process -> time_changed/minute_changed
# - add_exp -> check_level_up -> level_up
# - Player等订阅这些信号
##############################################################################
extends Node

##############################################################################
# 经验曲线（累计阈值）
##############################################################################

## index=等级，value=该等级的累计经验阈值
const EXP_CURVE: Array[int] = [
	0, 0, 10, 25, 45, 70, 100, 140, 190, 250,
	320, 400, 500, 620, 760, 920, 1100, 1300, 1550, 1850,
	2200, 2600, 3050, 3550, 4100, 4700
]

##############################################################################
# 运行期状态
##############################################################################

## 当前游戏时间（秒）
var current_time: float = 0.0

## 游戏总时长（秒）
const GAME_DURATION: float = 1200.0

## 当前分钟
var current_minute: int = 0

## 玩家等级
var player_level: int = 1

## 玩家经验
var player_exp: float = 0.0

## 金币
var gold: int = 0

## 矿石
var ore: int = 0

## 玩家引用（用于同步level_up）
var player: CharacterBody2D = null

##############################################################################
# 信号
##############################################################################

signal time_changed(seconds: float)
signal minute_changed(minute: int)
signal level_up(level: int)
signal gold_changed(amount: int)
signal ore_changed(amount: int)
signal game_over()

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	print("[GameManager] 初始化完成")

func _process(delta: float) -> void:
	current_time += delta
	time_changed.emit(current_time)

	var new_minute: int = int(current_time / 60.0)
	if new_minute != current_minute:
		current_minute = new_minute
		minute_changed.emit(current_minute)

	if current_time >= GAME_DURATION:
		game_over.emit()
		set_process(false)

##############################################################################
# 金币/矿石
##############################################################################

## 增加金币
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

## 增加矿石
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

##############################################################################
# 经验/等级
##############################################################################

## 增加经验
func add_exp(amount: float) -> void:
	player_exp += amount
	check_level_up()

## 检查升级
func check_level_up() -> void:
	if player_level >= EXP_CURVE.size() - 1:
		return
	while player_level < EXP_CURVE.size() - 1 and player_exp >= EXP_CURVE[player_level + 1]:
		player_level += 1
		level_up.emit(player_level)
		if player:
			player.level_up()
		print("[GameManager] 升级! 当前等级=", player_level)

## 获取玩家等级
func get_player_level() -> int:
	return player_level

## 设置玩家引用
func set_player(p: CharacterBody2D) -> void:
	player = p
