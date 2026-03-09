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
## 当前值：false（正式流程默认关闭）
const DEBUG_START_GOLD_ENABLED: bool = false

## 调试初始金币数量
## 单位：金币
## 作用：启动后直接发放金币
## 调整范围：0-9999
## 当前值：0
const DEBUG_START_GOLD_AMOUNT: int = 0

## 当前游戏时间（秒）
var current_time: float = 0.0

## 游戏总时长（秒）
const GAME_DURATION: float = 1200.0
const FINAL_BOSS_OVERTIME_LIMIT: float = 180.0

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

## P1.1 经济采样：累计获取/消耗
var gold_earned: int = 0
var gold_spent: int = 0
var ore_earned: int = 0
var ore_spent: int = 0

## P1.1 经济采样：按来源/去向归因
var gold_earned_by_reason: Dictionary = {}
var gold_spent_by_reason: Dictionary = {}
var ore_earned_by_reason: Dictionary = {}
var ore_spent_by_reason: Dictionary = {}

## P1.1 经济采样：关键分钟快照（5/10/15/20）
const ECON_SAMPLE_MINUTES: Array[int] = [5, 10, 15, 20]
var economy_snapshots: Dictionary = {}

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
var is_game_over: bool = false

## P1.1 商店节奏：减少频繁打断战斗的问题
const SHOP_TIMER_INITIAL: float = 45.0
const SHOP_TIMER_EARLY: float = 45.0
const SHOP_TIMER_LATE: float = 70.0
const SHOP_TIMER_EARLY_WINDOW: float = 240.0

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
		_record_economy_snapshot(current_minute)

	if current_time >= GAME_DURATION:
		if _should_finish_run():
			trigger_game_over()
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
func add_gold(amount: int, reason: String = "unknown") -> void:
	if amount <= 0:
		return
	gold += amount
	gold_earned += amount
	_add_reason_amount(gold_earned_by_reason, reason, amount, "unknown_gain")
	gold_changed.emit(gold)

## 消耗金币
func spend_gold(amount: int, reason: String = "unknown") -> bool:
	if amount <= 0:
		return true
	if gold >= amount:
		gold -= amount
		gold_spent += amount
		_add_reason_amount(gold_spent_by_reason, reason, amount, "unknown_spend")
		gold_changed.emit(gold)
		return true
	return false

## 增加矿石
func add_ore(amount: int, reason: String = "unknown") -> void:
	if amount <= 0:
		return
	ore += amount
	ore_earned += amount
	_add_reason_amount(ore_earned_by_reason, reason, amount, "unknown_gain")
	ore_changed.emit(ore)

## 消耗矿石
func spend_ore(amount: int, reason: String = "unknown") -> bool:
	if amount <= 0:
		return true
	if ore >= amount:
		ore -= amount
		ore_spent += amount
		_add_reason_amount(ore_spent_by_reason, reason, amount, "unknown_spend")
		ore_changed.emit(ore)
		return true
	return false

##############################################################################
# 经验/等级
##############################################################################

## 增加经验
func add_exp(amount: float) -> void:
	var exp_rate_pct: float = get_player_stat("ExpRate", 0.0)
	var exp_mult: float = max(0.0, 1.0 + exp_rate_pct / 100.0)
	var final_amount: float = amount * exp_mult
	player_exp += final_amount
	check_level_up()

## 检查升级
func check_level_up() -> void:
	if player_level >= EXP_CURVE.size() - 1:
		return
	while player_level < EXP_CURVE.size() - 1 and player_exp >= EXP_CURVE[player_level + 1]:
		player_level += 1
		level_up.emit(player_level)
		print("[GameManager] 升级! 当前等级=", player_level)

## 获取玩家等级
func get_player_level() -> int:
	return player_level

## 设置玩家引用
func set_player(p: CharacterBody2D) -> void:
	player = p

## 获取玩家最终属性（统一入口）
func get_player_stat(stat_name: String, default_value: float = 0.0) -> float:
	if player and is_instance_valid(player) and player.has_method("get_final_stat"):
		return float(player.get_final_stat(stat_name))
	return default_value

## 获取玩家属性百分比倍率（1 + x%）
func get_player_stat_multiplier(
	stat_name: String,
	min_mult: float = 0.0,
	max_mult: float = 10.0
) -> float:
	var value_pct: float = get_player_stat(stat_name, 0.0)
	var mult: float = 1.0 + value_pct / 100.0
	return clamp(mult, min_mult, max_mult)


##############################################################################
# 游戏启动
##############################################################################

## 启动游戏（由Main场景调用）
func start_game() -> void:
	if game_started:
		return

	_reset_economy_metrics()
	is_game_over = false
	game_started = true
	shop_timer_paused = false
	if DEBUG_START_GOLD_ENABLED:
		add_gold(DEBUG_START_GOLD_AMOUNT, "debug_start_gold")
	shop_timer = SHOP_TIMER_INITIAL
	set_process(true)

## 触发游戏结束（统一入口，避免重复触发）
func trigger_game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	game_started = false
	shop_timer_paused = true
	_record_economy_snapshot(int(current_time / 60.0))
	game_over.emit()
	set_process(false)

func _should_finish_run() -> bool:
	if not _has_alive_boss():
		return true
	return current_time >= GAME_DURATION + FINAL_BOSS_OVERTIME_LIMIT

func _has_alive_boss() -> bool:
	var bosses: Array[Node] = get_tree().get_nodes_in_group("boss")
	for boss: Node in bosses:
		if is_instance_valid(boss):
			return true
	return false

##############################################################################
##############################################################################
## 触发商店门生成
func trigger_shop_door() -> void:
	shop_door_triggered.emit()

	## 重置计时器（前期45秒，后期70秒）
	if current_time < SHOP_TIMER_EARLY_WINDOW:
		shop_timer = SHOP_TIMER_EARLY
	else:
		shop_timer = SHOP_TIMER_LATE

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
	_reset_economy_metrics()

	## 重置玩家引用
	player = null

	## 重置商店计时器
	shop_timer = SHOP_TIMER_INITIAL
	shop_timer_paused = false

	## 重置游戏状态
	game_started = false
	is_game_over = false
	set_process(false)

	## 重置跨局系统状态
	if ShopManager and ShopManager.has_method("reset_run_state"):
		ShopManager.reset_run_state()
	if ForgeManager and ForgeManager.has_method("reset_run_state"):
		ForgeManager.reset_run_state()

	## 发出重置信号（UI可监听此信号刷新）
	gold_changed.emit(0)
	ore_changed.emit(0)

##############################################################################
# 经济采样（P1.1）
##############################################################################

func _reset_economy_metrics() -> void:
	gold_earned = 0
	gold_spent = 0
	ore_earned = 0
	ore_spent = 0
	gold_earned_by_reason.clear()
	gold_spent_by_reason.clear()
	ore_earned_by_reason.clear()
	ore_spent_by_reason.clear()
	economy_snapshots.clear()

func _record_economy_snapshot(minute: int) -> void:
	if minute not in ECON_SAMPLE_MINUTES:
		return
	if economy_snapshots.has(minute):
		return
	economy_snapshots[minute] = {
		"minute": minute,
		"gold_balance": gold,
		"ore_balance": ore,
		"gold_earned": gold_earned,
		"gold_spent": gold_spent,
		"ore_earned": ore_earned,
		"ore_spent": ore_spent
	}

func get_economy_metrics() -> Dictionary:
	return {
		"gold_earned": gold_earned,
		"gold_spent": gold_spent,
		"ore_earned": ore_earned,
		"ore_spent": ore_spent,
		"gold_earned_by_reason": gold_earned_by_reason.duplicate(true),
		"gold_spent_by_reason": gold_spent_by_reason.duplicate(true),
		"ore_earned_by_reason": ore_earned_by_reason.duplicate(true),
		"ore_spent_by_reason": ore_spent_by_reason.duplicate(true),
		"snapshots": economy_snapshots.duplicate(true)
	}

func _add_reason_amount(store: Dictionary, reason: String, amount: int, fallback: String) -> void:
	var key: String = reason.strip_edges()
	if key.is_empty():
		key = fallback
	store[key] = int(store.get(key, 0)) + amount

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
	
