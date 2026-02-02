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

## 是否启用调试初始金币
## 作用：方便商店测试
## 当前值：true
const DEBUG_START_GOLD_ENABLED: bool = true

## 调试初始金币数量
## 单位：金币
## 作用：启动后直接发放金币
## 调整范围：0-9999
## 当前值：2000
const DEBUG_START_GOLD_AMOUNT: int = 2000

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

## 选中的角色ID
var selected_character_id: String = ""

## 地图边界（世界坐标）
## 作用：限制玩家/怪物不出地图
## 数据来源：Main._build_map()
var map_bounds: Rect2 = Rect2()

## 商店门计时器
var shop_timer: float = 30.0
var shop_timer_paused: bool = false
var game_started: bool = false

##############################################################################
# 信号
##############################################################################

## 游戏时间变化信号（每帧触发）
## 参数：seconds - 当前游戏时间（秒）
signal time_changed(seconds: float)

## 游戏分钟变化信号（每分钟触发）
## 参数：minute - 当前分钟数（0开始）
signal minute_changed(minute: int)

## 玩家升级信号
## 参数：level - 新等级（1开始）
signal level_up(level: int)

## 金币数量变化信号
## 参数：amount - 当前金币总数
signal gold_changed(amount: int)

## 矿石数量变化信号
## 参数：amount - 当前矿石总数
signal ore_changed(amount: int)

## 游戏结束信号（20分钟到）
signal game_over()

## 商店门触发信号（前期30秒/后期60秒触发一次）
signal shop_door_triggered()

## 工坊门可用信号（Boss出现前30秒或击杀后触发）
## 参数：boss_minute - Boss分钟数（5/10/15/20）
signal forge_available(boss_minute: int)

## Boss刷新信号
## 参数：boss_minute - Boss分钟数（5/10/15/20）
signal boss_spawned(boss_minute: int)

## Boss击杀信号
## 参数：boss_minute - Boss分钟数（5/10/15/20）
signal boss_killed(boss_minute: int)

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	pass  # autoload节点的process默认就是开启的

func _process(delta: float) -> void:
	if not game_started:
		return

	current_time += delta
	time_changed.emit(current_time)

	var new_minute: int = int(current_time / 60.0)
	if new_minute != current_minute:
		current_minute = new_minute
		minute_changed.emit(current_minute)

	if current_time >= GAME_DURATION:
		game_over.emit()
		set_process(false)
		return  # 立即返回，避免后续逻辑继续执行

	# 商店门计时器
	if not shop_timer_paused:
		shop_timer -= delta
		if shop_timer <= 0:
			trigger_shop_door()

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


##############################################################################
# 游戏启动
##############################################################################

## 启动游戏（由Main场景调用）
func start_game() -> void:
	if game_started:
		return

	game_started = true
	if DEBUG_START_GOLD_ENABLED:
		add_gold(DEBUG_START_GOLD_AMOUNT)
	shop_timer = 30.0  # 初始30秒后第一次商店门
	set_process(true)

##############################################################################
##############################################################################
## 触发商店门生成
func trigger_shop_door() -> void:
	shop_door_triggered.emit()

	## 重置计时器（前期30秒，后期60秒）
	if current_time < 180.0:  # 前3分钟
		shop_timer = 30.0
	else:
		shop_timer = 60.0

##############################################################################
# Boss系统回调
##############################################################################

## Boss被击杀（由Boss脚本或EnemySpawner调用）
func on_boss_defeated(boss_minute: int) -> void:
	boss_killed.emit(boss_minute)
	
	## 触发工坊门（30秒内可用）
	forge_available.emit(boss_minute)
	
	print("[GameManager] Boss击杀: ", boss_minute, "分钟 - 工坊开启")

##############################################################################
# 游戏重置
##############################################################################

## 重置游戏状态（用于重新开始）
func reset_game() -> void:
	## 重置时间
	current_time = 0.0
	current_minute = 0

	## 重置等级和经验
	player_level = 1
	player_exp = 0.0

	## 重置金币和矿石
	gold = 0
	ore = 0

	## 重置玩家引用
	player = null

	## 重置商店计时器
	shop_timer = 30.0
	shop_timer_paused = false

	## 重置游戏状态
	game_started = false

	## 发出重置信号（UI可监听此信号刷新）
	gold_changed.emit(0)
	ore_changed.emit(0)

##############################################################################
# 暂停/恢复商店门计时器（用于Boss战）
##############################################################################

## 暂停商店门计时器
func pause_shop_timer() -> void:
	shop_timer_paused = true
	print("[GameManager] 商店门计时器已暂停")

## 恢复商店门计时器
func resume_shop_timer() -> void:
	shop_timer_paused = false
	print("[GameManager] 商店门计时器已恢复")

##############################################################################
# 兼容接口（供Boss系统调用）
##############################################################################

func pause_timer() -> void:
	pause_shop_timer()

func resume_timer() -> void:
	resume_shop_timer()

##############################################################################
# 获取当前分钟（供外部调用）
##############################################################################

## 获取当前游戏分钟数
func get_current_minute() -> int:
	return current_minute
	
