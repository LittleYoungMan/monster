##############################################################################
# GameManager - 游戏管理器
#
# 功能说明：
# 1. 管理游戏时间（20分钟倒计时）
# 2. 管理双经济系统（金币、矿石）
# 3. 管理玩家等级和经验
# 4. 发出各种游戏事件信号
##############################################################################
extends Node

## 经验曲线（每级升级所需累计经验）
## 单位：经验点
## 作用：定义升级所需经验
const EXP_CURVE: Array[int] = [
	0,      # 0级（占位）
	0,      # 1级（起始）
	10,     # 2级
	25,     # 3级
	45,     # 4级
	70,     # 5级
	100,    # 6级
	140,    # 7级
	190,    # 8级
	250,    # 9级
	320,    # 10级
	400,    # 11级
	500,    # 12级
	620,    # 13级
	760,    # 14级
	920,    # 15级
	1100,   # 16级
	1300,   # 17级
	1550,   # 18级
	1850,   # 19级
	2200,   # 20级
	2600,   # 21级
	3050,   # 22级
	3550,   # 23级
	4100,   # 24级
	4700    # 25级
]

## 当前游戏时间（秒）
var current_time: float = 0.0

## 游戏总时长（秒）
const GAME_DURATION: float = 1200.0

## 当前分钟数
var current_minute: int = 0

## 玩家等级
var player_level: int = 1

## 玩家经验
var player_exp: float = 0.0

## 金币
var gold: int = 0

## 矿石
var ore: int = 0

## 玩家引用
var player: CharacterBody2D = null

## 信号定义
signal time_changed(seconds: float)
signal minute_changed(minute: int)
signal level_up(level: int)
signal gold_changed(amount: int)
signal ore_changed(amount: int)
signal game_over()

func _ready() -> void:
	print("[GameManager] 游戏管理器初始化")

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

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false

func add_ore(amount: int) -> void:
	ore += amount
	ore_changed.emit(ore)

func spend_ore(amount: int) -> bool:
	if ore >= amount:
		ore -= amount
		ore_changed.emit(ore)
		return true
	return false

func add_exp(amount: float) -> void:
	player_exp += amount
	check_level_up()

func check_level_up() -> void:
	if player_level >= EXP_CURVE.size() - 1:
		return
	
	while player_level < EXP_CURVE.size() - 1 and player_exp >= EXP_CURVE[player_level + 1]:
		player_level += 1
		level_up.emit(player_level)
		
		if player:
			player.level_up()
		
		print("[GameManager] 升级! 当前等级: ", player_level)

func get_player_level() -> int:
	return player_level

func set_player(p: CharacterBody2D) -> void:
	player = p
