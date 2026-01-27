##############################################################################
# AttributePanel - 属性面板脚本（autoload/UI版本）
#
# 设计目的：
# - 作为全局UI节点提供随时可查看的属性面板
# - 支持Tab键快速显示/隐藏
# - 可通过关闭按钮手动隐藏
#
# 主要职责：
# 1) 监听ui_tab输入切换显示
# 2) 点击关闭按钮隐藏面板
# 3) 打开时刷新玩家属性列表
#
# 依赖与调用链：
# - 依赖玩家节点在group "player" 中
# - 依赖玩家实现 get_display_stats()
# - refresh_attributes() 会在显示时调用
#
# 引擎回调：
# - _ready(): 获取玩家、连接按钮事件
# - _unhandled_input(): 监听Tab输入（未被UI消费时）
#
# 修复：2026-01-27 重新写回中文注释
##############################################################################
extends Panel

##############################################################################
# 节点引用
##############################################################################

## 属性列表容器（动态创建每条属性行）
@onready var attribute_list: VBoxContainer = $ScrollContainer/AttributeList

## 关闭按钮（点击后隐藏面板）
@onready var close_button: Button = $CloseButton

##############################################################################
# 运行期数据
##############################################################################

## 玩家节点引用：用于读取展示属性
var player: CharacterBody2D = null

##############################################################################
# 生命周期回调
##############################################################################

func _ready() -> void:
	## 初始隐藏
	visible = false

	## 等待一帧，确保玩家节点已经加入树
	await get_tree().process_frame
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	## 绑定关闭按钮
	close_button.pressed.connect(_on_close_button_pressed)

##############################################################################
# 输入处理
##############################################################################

func _unhandled_input(event: InputEvent) -> void:
	## 使用ui_tab切换显示（避免被其他UI消费后仍可触发）
	if event.is_action_pressed("ui_tab"):
		visible = !visible
		if visible:
			refresh_attributes()

##############################################################################
# UI刷新
##############################################################################

func refresh_attributes() -> void:
	## 只读刷新：不修改玩家数据
	if not player:
		return

	## 清空旧行
	for child: Node in attribute_list.get_children():
		child.queue_free()

	## 从玩家获取可展示属性
	var stats: Dictionary = player.get_display_stats()
	for stat_name: String in stats.keys():
		## 创建一行（属性名 + 属性值）
		var row: HBoxContainer = HBoxContainer.new()
		var name_lbl: Label = Label.new()
		name_lbl.text = stat_name + ":"
		name_lbl.custom_minimum_size = Vector2(200, 0)
		var val_lbl: Label = Label.new()
		val_lbl.text = stats[stat_name]
		row.add_child(name_lbl)
		row.add_child(val_lbl)
		attribute_list.add_child(row)

##############################################################################
# 按钮回调
##############################################################################

func _on_close_button_pressed() -> void:
	## 点击关闭按钮后隐藏面板
	visible = false
