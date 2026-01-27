##############################################################################
# AttributePanel - 属性面板UI（场景内Panel）
#
# 设计目的：
# - 提供“按需查看”的属性明细，不常驻显示
# - 面板打开时即时从玩家读取属性，保证数据准确
#
# 主要职责：
# 1) 监听Tab输入切换面板显示
# 2) 从玩家读取可展示属性（get_display_stats）
# 3) 将属性以“名称: 值”的形式动态生成UI行
#
# 依赖与调用链：
# - 依赖玩家节点在group "player" 中
# - 依赖玩家实现 get_display_stats() 并返回 Dictionary
# - _input -> _update_attributes -> 动态生成UI
#
# 引擎回调：
# - _ready(): 初始化隐藏面板，绑定玩家
# - _input(event): 监听Tab切换显示
#
# 修复：2026-01-27 重新写回中文注释与打印信息
##############################################################################
extends Panel

##############################################################################
# 节点引用
##############################################################################

## 属性列表容器：会动态添加每一行属性
@onready var attribute_list: VBoxContainer = $ScrollContainer/AttributeList

##############################################################################
# 运行期数据
##############################################################################

## 玩家节点引用（用于读取属性）
var player: CharacterBody2D = null

##############################################################################
# 生命周期回调
##############################################################################

func _ready() -> void:
	## 初始隐藏：只在按Tab时显示
	visible = false

	## 找到玩家节点
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("[AttributePanel] 未找到玩家节点")

	print("[AttributePanel] 初始化完成")

##############################################################################
# 输入处理
##############################################################################

func _input(event: InputEvent) -> void:
	## 通过ui_focus_next（默认Tab）切换显示
	if event.is_action_pressed("ui_focus_next"):
		visible = !visible
		if visible:
			_update_attributes()

##############################################################################
# UI更新
##############################################################################

func _update_attributes() -> void:
	## 面板只读展示：不修改玩家数值
	if player == null:
		return

	## 先清空旧的行，避免重复显示
	for child in attribute_list.get_children():
		child.queue_free()

	## 从玩家获取“可展示属性”字典
	## 结构假定为：{"属性名": "显示值"}
	var stats_data: Dictionary = player.get_display_stats()
	for attr_name in stats_data.keys():
		## 为每一项属性创建一行（名称 + 数值）
		var row: HBoxContainer = HBoxContainer.new()

		var name_label: Label = Label.new()
		name_label.text = attr_name + ":"
		name_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_label)

		var value_label: Label = Label.new()
		value_label.text = stats_data[attr_name]
		row.add_child(value_label)

		attribute_list.add_child(row)
