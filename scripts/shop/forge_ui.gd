##############################################################################
# ForgeUI - 工坊界面
#
# 设计目的：
# - 展示6把武器
# - 选择武器进行升阶/打造
# - 使用矿石消耗与刷新
##############################################################################
extends Control

##############################################################################
# 可调参数
##############################################################################

## 武器格子按钮尺寸
## 单位：像素
## 作用：影响武器列表格子大小
## 调整范围：80-160
## 当前值：120
const WEAPON_BUTTON_SIZE: int = 120

## 词条选择按钮宽度
## 单位：像素
## 作用：影响“选择”按钮大小
## 调整范围：60-120
## 当前值：80
const ATTR_SELECT_BUTTON_WIDTH: int = 80

@onready var ore_label: Label = $Panel/VBoxRoot/Header/OreLabel
@onready var weapon_grid: GridContainer = $Panel/VBoxRoot/Content/LeftPanel/WeaponGrid
@onready var selected_label: Label = $Panel/VBoxRoot/Content/RightPanel/SelectedLabel
@onready var weapon_info_label: Label = $Panel/VBoxRoot/Content/RightPanel/WeaponInfoLabel
@onready var attribute_list: VBoxContainer = $Panel/VBoxRoot/Content/RightPanel/AttributeList
@onready var message_label: Label = $Panel/VBoxRoot/Content/RightPanel/MessageLabel

@onready var upgrade_button: Button = $Panel/VBoxRoot/Content/RightPanel/ActionGrid/UpgradeButton
@onready var punch_button: Button = $Panel/VBoxRoot/Content/RightPanel/ActionGrid/PunchButton
@onready var reroll_value_button: Button = $Panel/VBoxRoot/Content/RightPanel/ActionGrid/RerollValueButton
@onready var reroll_affix_button: Button = $Panel/VBoxRoot/Content/RightPanel/ActionGrid/RerollAffixButton
@onready var reforge_button: Button = $Panel/VBoxRoot/Content/RightPanel/ActionGrid/ReforgeButton
@onready var lock_button: Button = $Panel/VBoxRoot/Content/RightPanel/ActionGrid/LockButton

@onready var refresh_button: Button = $Panel/VBoxRoot/Footer/RefreshButton
@onready var close_button: Button = $Panel/VBoxRoot/Footer/CloseButton

var player: CharacterBody2D = null
var selected_slot_index: int = -1
var selected_attr_index: int = -1
var previous_pause_state: bool = false

## 初始化
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("forge_ui")
	close_button.pressed.connect(_on_close_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	punch_button.pressed.connect(_on_punch_pressed)
	reroll_value_button.pressed.connect(_on_reroll_value_pressed)
	reroll_affix_button.pressed.connect(_on_reroll_affix_pressed)
	reforge_button.pressed.connect(_on_reforge_pressed)
	lock_button.pressed.connect(_on_lock_pressed)
	if GameManager and GameManager.has_signal("ore_changed"):
		GameManager.ore_changed.connect(_on_ore_changed)

## 打开工坊
func show_forge() -> void:
	visible = true
	previous_pause_state = get_tree().paused
	get_tree().paused = true
	player = get_tree().get_first_node_in_group("player")
	if ForgeManager:
		ForgeManager.begin_forge_visit()
	_refresh_ore_label()
	_build_weapon_grid()
	_select_weapon(0)

## 关闭工坊
func _on_close_pressed() -> void:
	visible = false
	get_tree().paused = previous_pause_state

##############################################################################
# UI刷新
##############################################################################

## 刷新矿石显示
func _refresh_ore_label() -> void:
	if ore_label:
		ore_label.text = "矿石: " + str(GameManager.ore)

## 矿石变化信号回调
func _on_ore_changed(_amount: int) -> void:
	_refresh_ore_label()

## 构建武器列表（6格）
func _build_weapon_grid() -> void:
	for child in weapon_grid.get_children():
		child.queue_free()
	if not player:
		return
	for i in range(player.weapon_slots.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(WEAPON_BUTTON_SIZE, WEAPON_BUTTON_SIZE)
		button.text = str(i + 1)
		var weapon_data: Dictionary = player.weapon_slots[i]
		if not weapon_data.is_empty():
			var weapon_id: String = weapon_data.get("weapon_id", "")
			var icon_tex: Texture2D = _load_weapon_icon(weapon_id)
			if icon_tex:
				button.icon = icon_tex
				button.expand_icon = true
				button.text = ""
			var quality: String = weapon_data.get("quality", "white")
			button.modulate = _get_quality_color(quality)
		else:
			button.text = "空"
			button.modulate = Color(0.7, 0.7, 0.7, 1.0)
		button.pressed.connect(_on_weapon_button_pressed.bind(i))
		weapon_grid.add_child(button)

## 刷新右侧详情面板
func _refresh_weapon_panel() -> void:
	message_label.text = ""
	if not player or selected_slot_index < 0 or selected_slot_index >= player.weapon_slots.size():
		selected_label.text = "未选择武器"
		weapon_info_label.text = ""
		_build_attribute_list([])
		_refresh_action_buttons()
		return
	var weapon_data: Dictionary = player.weapon_slots[selected_slot_index]
	if weapon_data.is_empty():
		selected_label.text = "空槽位"
		weapon_info_label.text = ""
		_build_attribute_list([])
		_refresh_action_buttons()
		return
	var weapon_id: String = weapon_data.get("weapon_id", "")
	var template: Dictionary = GameData.get_weapon(weapon_id)
	var quality: String = weapon_data.get("quality", "white")
	var craft_value: int = ForgeManager.get_craft_value(weapon_data)
	selected_label.text = template.get("name_cn", weapon_id)
	weapon_info_label.text = "品质: " + quality + "  打造值: " + str(craft_value)
	_build_attribute_list(weapon_data.get("attributes", []))
	_refresh_action_buttons()

## 构建词条列表
##
## 参数：
##   attributes - 词条数组
func _build_attribute_list(attributes: Array) -> void:
	for child in attribute_list.get_children():
		child.queue_free()
	selected_attr_index = -1

	for i in range(attributes.size()):
		var attr: Dictionary = attributes[i]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		var lock_text: String = " [锁]" if attr.get("locked", false) else ""
		label.text = str(i + 1) + ". " + _get_attr_name(attr.get("type", "")) + " +" + str(int(attr.get("value", 0))) + lock_text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var select_btn := Button.new()
		select_btn.text = "选择"
		select_btn.custom_minimum_size = Vector2(ATTR_SELECT_BUTTON_WIDTH, 30)
		select_btn.pressed.connect(_on_attr_selected.bind(i))
		row.add_child(label)
		row.add_child(select_btn)
		attribute_list.add_child(row)

## 刷新按钮状态与价格显示
func _refresh_action_buttons() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		upgrade_button.disabled = true
		punch_button.disabled = true
		reroll_value_button.disabled = true
		reroll_affix_button.disabled = true
		reforge_button.disabled = true
		lock_button.disabled = true
		return

	upgrade_button.disabled = false
	punch_button.disabled = false
	reroll_affix_button.disabled = selected_attr_index < 0
	reroll_value_button.disabled = selected_attr_index < 0
	reforge_button.disabled = false
	lock_button.disabled = selected_attr_index < 0

	upgrade_button.text = "升阶 (" + str(ForgeManager.get_upgrade_cost(weapon_data)) + ")"
	var punch_cost: int = ForgeManager.get_punch_slot_cost(weapon_data)
	punch_button.text = "打孔 (" + (str(punch_cost) if punch_cost >= 0 else "-") + ")"
	var value_cost: int = -1
	if selected_attr_index >= 0:
		value_cost = ForgeManager.get_reroll_value_cost(weapon_data, selected_attr_index)
	reroll_value_button.text = "敲数值 (" + (str(value_cost) if value_cost >= 0 else "-") + ")"
	var affix_cost: int = ForgeManager.get_reroll_affix_cost(weapon_data)
	reroll_affix_button.text = "洗词条 (" + (str(affix_cost) if affix_cost >= 0 else "-") + ")"
	var reforge_cost: int = ForgeManager.get_reforge_cost(weapon_data)
	reforge_button.text = "重铸 (" + (str(reforge_cost) if reforge_cost >= 0 else "-") + ")"
	lock_button.text = "锁定/解锁 (" + str(ForgeManager.get_lock_cost(weapon_data)) + ")"
	var refresh_cost: int = ForgeManager.get_refresh_cost()
	refresh_button.text = "刷新 (" + (str(refresh_cost) if refresh_cost >= 0 else "-") + ")"
	refresh_button.disabled = refresh_cost < 0

## 获取当前选中武器数据
func _get_selected_weapon() -> Dictionary:
	if not player or selected_slot_index < 0 or selected_slot_index >= player.weapon_slots.size():
		return {}
	return player.weapon_slots[selected_slot_index]

##############################################################################
# 交互
##############################################################################

## 点击武器格子
func _on_weapon_button_pressed(slot_index: int) -> void:
	_select_weapon(slot_index)

## 选择武器
func _select_weapon(slot_index: int) -> void:
	selected_slot_index = slot_index
	selected_attr_index = -1
	_refresh_weapon_panel()

## 选择词条
func _on_attr_selected(attr_index: int) -> void:
	selected_attr_index = attr_index
	_refresh_action_buttons()

## 刷新工坊
func _on_refresh_pressed() -> void:
	if ForgeManager and ForgeManager.refresh_forge():
		_set_message("刷新完成")
	_build_weapon_grid()
	_refresh_weapon_panel()
	_refresh_ore_label()
	_refresh_action_buttons()

## 升阶
func _on_upgrade_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		return
	if ForgeManager.upgrade_weapon(weapon_data):
		_set_message("升阶成功")
		player.update_all_weapons()
	_build_weapon_grid()
	_refresh_weapon_panel()
	_refresh_ore_label()

## 打孔
func _on_punch_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		return
	if ForgeManager.punch_slot(weapon_data):
		_set_message("打孔成功")
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()

## 敲数值
func _on_reroll_value_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		return
	if ForgeManager.reroll_value(weapon_data, selected_attr_index):
		_set_message("敲数值成功")
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()

## 洗词条
func _on_reroll_affix_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		return
	if ForgeManager.reroll_affix(weapon_data, selected_attr_index):
		_set_message("洗词条成功")
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()

## 重铸
func _on_reforge_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		return
	if ForgeManager.reforge_all(weapon_data):
		_set_message("重铸完成")
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()

## 锁定/解锁词条
func _on_lock_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		return
	var attributes: Array = weapon_data.get("attributes", [])
	if selected_attr_index < 0 or selected_attr_index >= attributes.size():
		return
	var attr: Dictionary = attributes[selected_attr_index]
	var ok: bool = false
	if attr.get("locked", false):
		ok = ForgeManager.unlock_attribute(weapon_data, selected_attr_index)
	else:
		ok = ForgeManager.lock_attribute(weapon_data, selected_attr_index)
	if ok:
		_set_message("锁定状态已更新")
		player.update_all_weapons()
		_refresh_weapon_panel()
		_refresh_ore_label()

## 显示提示
func _set_message(text: String) -> void:
	if message_label:
		message_label.text = text

##############################################################################
# 工具
##############################################################################

## 加载武器图标
func _load_weapon_icon(weapon_id: String) -> Texture2D:
	if weapon_id.is_empty():
		return null
	var template: Dictionary = GameData.get_weapon(weapon_id)
	var icon_id: String = template.get("icon_id", "")
	if icon_id.is_empty():
		return null
	var path: String = "res://assets/PIC/wuqi/icon/256/" + icon_id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

## 品质颜色
func _get_quality_color(quality: String) -> Color:
	match quality:
		"blue":
			return Color(0.45, 0.7, 1.0, 1.0)
		"purple":
			return Color(0.75, 0.5, 1.0, 1.0)
		"gold":
			return Color(1.0, 0.85, 0.35, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)

## 词条名称
func _get_attr_name(attr_type: String) -> String:
	var name_map: Dictionary = {
		"damage": "伤害",
		"crit_rate": "暴击率",
		"crit_dmg": "暴击伤害",
		"cdr": "冷却",
		"all_dmg": "全伤害",
		"melee_dmg": "近战伤害",
		"ranged_dmg": "远程伤害",
		"element_dmg": "元素伤害",
		"summon_dmg": "召唤伤害"
	}
	return name_map.get(attr_type, attr_type)
