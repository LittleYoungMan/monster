##############################################################################
# HUD - 游戏内界面脚本
#
# 功能说明：
# 1. 显示游戏时间、金币、矿石
# 2. 显示玩家生命条、经验条、等级
# 3. 显示武器槽图标
##############################################################################
extends CanvasLayer

@onready var time_label: Label = $TopBar/TimeLabel
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var ore_label: Label = $TopBar/OreLabel
@onready var health_bar: ProgressBar = $BottomBar/HealthBar
@onready var exp_bar: ProgressBar = $BottomBar/ExpBar
@onready var level_label: Label = $BottomBar/LevelLabel

var player: CharacterBody2D = null

func _ready() -> void:
	await get_tree().process_frame
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.ore_changed.connect(_on_ore_changed)

func _process(delta: float) -> void:
	if player:
		health_bar.max_value = player.get_final_stat("Health")
		health_bar.value = player.current_hp
		level_label.text = "Lv." + str(player.current_level)

func _on_gold_changed(amount: int) -> void:
	gold_label.text = "Gold: " + str(amount)

func _on_ore_changed(amount: int) -> void:
	ore_label.text = "Ore: " + str(amount)
