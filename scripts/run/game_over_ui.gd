##############################################################################
# GameOverUI - 游戏结算界面
#
# 设计目的：
# - 20分钟游戏结束后显示结算信息
# - 展示玩家数据（等级/金币/DPS/武器等）
# - 提供重新开始或退出游戏的选项
#
# 主要职责：
# 1) 显示游戏统计数据
# 2) 提供返回主菜单或重新开始的按钮
# 3) 显示玩家最终装备情况
#
# 调用链：
# - Main._on_game_over -> 实例化此UI
#
# 修复：2026-01-28 创建，补充游戏结束反馈
##############################################################################
extends Control

##############################################################################
# 节点引用
##############################################################################

@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var stats_container: VBoxContainer = $Panel/VBoxContainer/StatsContainer
@onready var restart_button: Button = $Panel/VBoxContainer/ButtonContainer/RestartButton
@onready var quit_button: Button = $Panel/VBoxContainer/ButtonContainer/QuitButton

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	## 初始化结算界面
	## 显示结算数据
	_display_stats()
	
	## 连接按钮信号
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	## 居中显示
	_center_panel()
	
	print("[GameOverUI] 结算界面显示")

##############################################################################
# 数据显示
##############################################################################

func _display_stats() -> void:
	## 刷新结算列表
	## 清空旧数据
	for child: Node in stats_container.get_children():
		child.queue_free()
	
	## 标题
	title_label.text = "游戏结束"
	
	## 从GameManager获取数据
	var stats: Dictionary = _gather_stats()
	
	## 显示每一项
	for key: String in stats.keys():
		var row: HBoxContainer = HBoxContainer.new()
		
		var label_key: Label = Label.new()
		label_key.text = key + ":"
		label_key.custom_minimum_size = Vector2(150, 0)
		
		var label_value: Label = Label.new()
		label_value.text = str(stats[key])
		
		row.add_child(label_key)
		row.add_child(label_value)
		stats_container.add_child(row)

## 收集游戏统计数据
func _gather_stats() -> Dictionary:
	## 汇总结算数据
	var stats: Dictionary = {}
	
	## 基础数据
	stats["游戏时长"] = "20分钟"
	stats["最终等级"] = "Lv." + str(GameManager.player_level)
	stats["剩余金币"] = str(GameManager.gold)
	stats["剩余矿石"] = str(GameManager.ore)
	
	## 玩家数据
	var player: CharacterBody2D = _find_player()
	if player:
		stats["最终生命"] = str(int(player.get_final_stat("Health")))
		stats["护甲"] = str(int(player.get_final_stat("Armor")))
		stats["移速"] = str(int(player.get_actual_move_speed()))
		
		## DPS
		if player.has_method("get_total_dps"):
			stats["总DPS"] = str(int(player.get_total_dps()))
		
		## 武器数量
		var weapon_count: int = _count_weapons(player)
		stats["装备武器数"] = str(weapon_count) + "/6"
	
	return stats

## 查找玩家节点
func _find_player() -> CharacterBody2D:
	## 通过分组获取玩家
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

## 统计武器数量
func _count_weapons(player: CharacterBody2D) -> int:
	## 统计已装备武器数量
	if not player.has("weapon_slots"):
		return 0
	
	var count: int = 0
	for weapon_data: Dictionary in player.weapon_slots:
		if not weapon_data.is_empty():
			count += 1
	return count

##############################################################################
# 按钮回调
##############################################################################

func _on_restart_pressed() -> void:
	## 点击“重新开始”
	## 重置GameManager状态
	GameManager.reset_game()
	
	## 返回角色选择场景
	get_tree().change_scene_to_file("res://scenes/ui/character_selection.tscn")

func _on_quit_pressed() -> void:
	## 点击“退出游戏”
	## 退出游戏
	get_tree().quit()

##############################################################################
# UI布局
##############################################################################

func _center_panel() -> void:
	## 预留：居中布局
	## 确保面板居中显示
	## 注意：需要在场景中设置Panel的锚点为Center
	pass
