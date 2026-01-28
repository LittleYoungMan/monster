##############################################################################
# Boss - Boss脚本（继承Enemy）
#
# 设计目的：
# - 在普通Enemy基础上叠加Boss倍率
# - 负责Boss出生/死亡的奖励与事件通知
# - 预留Boss特殊行为（可从monster_boss.csv扩展）
#
# CSV字段对齐（monster_boss.csv）：
# - BossID   -> 继承Enemy的monster_id
# - NameZH   -> 仅用于显示
# - Minute   -> boss_minute（刷新分钟）
# - Field_15 -> 行为描述（当前未解析，预留）
#
# 调用链：
# - EnemySpawner._spawn_boss -> boss.initialize_boss
# - Enemy._physics_process -> Boss._physics_process（super）
# - Boss die() -> 奖励发放与信号触发
##############################################################################
extends "res://scripts/enemy/enemy.gd"

##############################################################################
# Boss状态
##############################################################################

## Boss刷新分钟（用于倍率/奖励）
var boss_minute: int = 5

## 是否已经触发Boss出生事件（防重复）
var boss_event_triggered: bool = false

##############################################################################
# 初始化
##############################################################################

## 初始化Boss
## 参数：id=BossID, minute_mark=刷新分钟
func initialize_boss(id: String, minute_mark: int) -> void:
	boss_minute = minute_mark

	## 先调用Enemy初始化（加载monster.csv字段）
	initialize(id, minute_mark)
	add_to_group("boss")

	## 叠加Boss倍率
	max_hp *= _get_boss_hp_mult()
	current_hp = max_hp
	damage *= _get_boss_damage_mult()

	## 触发Boss出生事件
	if not boss_event_triggered and GameManager:
		boss_event_triggered = true
		if GameManager.has_signal("boss_spawned"):
			GameManager.boss_spawned.emit(boss_minute)
		if SpawnerConfig.BOSS_PAUSE_TIMER and GameManager.has_method("pause_timer"):
			GameManager.pause_timer()

	print("[Boss] 初始化完成: ", boss_minute, "分钟 - HP=", int(max_hp), " 伤害=", int(damage))

##############################################################################
# Boss倍率
##############################################################################

## Boss生命倍率（可按分钟分段）
func _get_boss_hp_mult() -> float:
	match boss_minute:
		5:  return 3.0
		10: return 5.0
		15: return 8.0
		20: return 12.0
		_:  return 1.0

## Boss伤害倍率（可按分钟分段）
func _get_boss_damage_mult() -> float:
	match boss_minute:
		5:  return 1.5
		10: return 2.0
		15: return 2.5
		20: return 3.0
		_:  return 1.0

##############################################################################
# Boss死亡
##############################################################################

## Boss死亡覆盖：发放额外奖励与事件
func die() -> void:
	var gold_drop: int = _get_boss_gold()
	var ore_drop: int = _get_boss_ore()

	GameManager.add_gold(gold_drop)
	GameManager.add_ore(ore_drop)
	GameManager.add_exp(50)

	if GameManager.has_signal("boss_killed"):
		GameManager.boss_killed.emit(boss_minute)

	if SpawnerConfig.BOSS_PAUSE_TIMER and GameManager.has_method("resume_timer"):
		GameManager.resume_timer()

	# 【新增】通知GameManager
	GameManager.on_boss_defeated(boss_minute)
	
	print("[Boss] 被击杀: ", boss_minute, "分钟 - 金币=", gold_drop, " 矿石=", ore_drop)
	queue_free()

##############################################################################
# Boss奖励表
##############################################################################

func _get_boss_gold() -> int:
	match boss_minute:
		5:  return 100
		10: return 200
		15: return 300
		20: return 500
		_:  return 100

func _get_boss_ore() -> int:
	match boss_minute:
		5:  return 5
		10: return 10
		15: return 15
		20: return 20
		_:  return 5

##############################################################################
# Boss特殊行为入口（预留）
##############################################################################

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_boss_special_behavior(delta)

## Boss特性逻辑（示例：半血狂暴）
func _boss_special_behavior(delta: float) -> void:
	var hp_percent: float = current_hp / max_hp
	if hp_percent < 0.5 and attack_cooldown > 0.5:
		attack_cooldown *= 0.7
		print("[Boss] 进入狂暴状态")
