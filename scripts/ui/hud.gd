##############################################################################
# HUD - 游戏内HUD
#
# 设计目的：
# - 以“只读展示”为核心：HUD只负责显示，不直接改玩家数值
# - 数据来源统一由玩家节点与GameManager信号提供，避免UI自己计算
#
# 主要职责：
# 1) 显示时间/金币/矿石（顶部）
# 2) 显示生命/经验/等级（底部）
# 3) 监听GameManager信号，实时刷新金币与矿石文本
#
# 依赖与调用链：
# - 依赖玩家节点在group "player" 中（由关卡或Player脚本注册）
# - 依赖GameManager发出 gold_changed / ore_changed 信号
# - _process 每帧读取玩家属性来刷新血条与等级
#
# 引擎回调：
# - _ready(): 节点进入场景树后执行，一次性做节点绑定与信号连接
# - _process(delta): 每帧刷新（生命/等级）
#
# 注意：
# - exp_bar当前未写入，保留给后续经验条逻辑（不改动现有行为）
#
# 修复：2026-01-27 重新写回中文注释与文本
##############################################################################
extends CanvasLayer

##############################################################################
# 节点引用（UI显示组件）
##############################################################################

## 顶部时间显示标签（若场景内有计时器，可由外部更新）
@onready var time_label: Label = $TopBar/TimeLabel

## 顶部金币显示标签，文本格式为“金币: 数量”
@onready var gold_label: Label = $TopBar/GoldLabel

## 顶部矿石显示标签，文本格式为“矿石: 数量”
@onready var ore_label: Label = $TopBar/OreLabel

## 底部生命条（max_value由玩家最终生命值决定）
@onready var health_bar: ProgressBar = $BottomBar/HealthBar

## 底部经验条（保留：逻辑未在此脚本刷新）
@onready var exp_bar: ProgressBar = $BottomBar/ExpBar

## 底部等级显示标签，文本格式为“Lv.X”
@onready var level_label: Label = $BottomBar/LevelLabel

##############################################################################
# 运行期数据
##############################################################################

## 玩家节点引用（通过group "player" 获取）
## 只读访问：用于刷新血量/等级显示
var player: CharacterBody2D = null

##############################################################################
# 生命周期回调
##############################################################################

func _ready() -> void:
	## 等待一帧，确保玩家节点已加入场景树
	await get_tree().process_frame

	## 从group "player" 获取玩家（通常只有一个）
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	## 连接全局货币变更信号，避免HUD主动轮询
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.ore_changed.connect(_on_ore_changed)

func _process(delta: float) -> void:
	## 每帧刷新玩家生命与等级显示
	## 说明：不在HUD侧进行数值计算，直接读取玩家最新值
	if player:
		health_bar.max_value = player.get_final_stat("Health")
		health_bar.value = player.current_hp
		level_label.text = "Lv." + str(player.current_level)

##############################################################################
# 信号回调：货币变更
##############################################################################

func _on_gold_changed(amount: int) -> void:
	## 外部逻辑通知金币变更，此处仅更新文本
	gold_label.text = "金币: " + str(amount)

func _on_ore_changed(amount: int) -> void:
	## 外部逻辑通知矿石变更，此处仅更新文本
	ore_label.text = "矿石: " + str(amount)
