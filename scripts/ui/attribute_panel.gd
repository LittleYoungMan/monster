##############################################################################
# AttributePanel - 属性面板UI
#
# 功能说明：
# 1. 显示玩家所有23个属性的详细数值
# 2. 支持中英文切换显示
# 3. 按Tab键显示/隐藏
#
# 挂载节点：AttributePanel (CanvasLayer > Panel)
# 场景路径：res://scenes/AttributePanel.tscn
##############################################################################
extends Panel

##############################################################################
# 节点引用
##############################################################################

## 属性列表容器
@onready var attribute_list: VBoxContainer = $ScrollContainer/AttributeList

##############################################################################
# 玩家引用
##############################################################################

## 玩家节点引用
var player: CharacterBody2D = null

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	# 默认隐藏
	visible = false
	
	# 查找玩家
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("[AttributePanel] 找不到玩家节点")
	
	print("[AttributePanel] 属性面板初始化完成")


func _input(event: InputEvent) -> void:
	# 按Tab键切换显示/隐藏
	if event.is_action_pressed("ui_focus_next"):  # Tab键
		visible = !visible
		
		# 显示时更新数据
		if visible:
			_update_attributes()


##############################################################################
# 更新显示函数
##############################################################################

## 更新属性显示
func _update_attributes() -> void:
	if player == null:
		return
	
	# 清空现有显示
	for child in attribute_list.get_children():
		child.queue_free()
	
	# 获取显示数据
	var stats_data: Dictionary = player.get_display_stats()
	
	# 创建属性行
	for attr_name in stats_data.keys():
		var row := HBoxContainer.new()
		
		# 属性名
		var name_label := Label.new()
		name_label.text = attr_name + ":"
		name_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_label)
		
		# 属性值
		var value_label := Label.new()
		value_label.text = stats_data[attr_name]
		row.add_child(value_label)
		
		attribute_list.add_child(row)
