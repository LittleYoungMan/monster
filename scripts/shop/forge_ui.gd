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

const UI_BG_PRIMARY: Color = Color(0.055, 0.065, 0.082, 0.975)
const UI_BG_SECONDARY: Color = Color(0.085, 0.097, 0.122, 0.965)
const UI_BORDER_PRIMARY: Color = Color(0.44, 0.54, 0.66, 0.96)
const UI_BORDER_ACCENT: Color = Color(0.90, 0.72, 0.40, 0.98)
const UI_BUTTON_BG: Color = Color(0.25, 0.35, 0.48, 0.98)
const UI_BUTTON_BG_HOVER: Color = Color(0.33, 0.44, 0.58, 0.98)
const UI_BUTTON_BG_PRESSED: Color = Color(0.18, 0.26, 0.35, 0.98)
const UI_BUTTON_BG_DISABLED: Color = Color(0.18, 0.20, 0.24, 0.78)
const MESSAGE_COLOR_ERROR: Color = Color(1.0, 0.72, 0.56, 1.0)
const MESSAGE_COLOR_SUCCESS: Color = Color(0.66, 0.96, 0.78, 1.0)

@onready var ore_label: Label = $Panel/VBoxRoot/Header/OreLabel
@onready var main_panel: Panel = $Panel
@onready var root_vbox: VBoxContainer = $Panel/VBoxRoot
@onready var header_box: HBoxContainer = $Panel/VBoxRoot/Header
@onready var footer_box: HBoxContainer = $Panel/VBoxRoot/Footer
@onready var content_row: HBoxContainer = $Panel/VBoxRoot/Content
@onready var weapon_grid: GridContainer = $Panel/VBoxRoot/Content/LeftPanel/WeaponGrid
@onready var weapon_list_label: Label = $Panel/VBoxRoot/Content/LeftPanel/WeaponListLabel
@onready var title_label: Label = $Panel/VBoxRoot/Header/TitleLabel
@onready var selected_label: Label = $Panel/VBoxRoot/Content/RightPanel/SelectedLabel
@onready var weapon_info_label: Label = $Panel/VBoxRoot/Content/RightPanel/WeaponInfoLabel
@onready var attr_title_label: Label = $Panel/VBoxRoot/Content/RightPanel/AttrLabel
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
var panel_anim_tween: Tween = null
var button_tweens: Dictionary = {}
var weapon_buttons: Array[Button] = []
var ui_time: float = 0.0
var backdrop_rect: ColorRect = null
var panel_glow_rect: TextureRect = null
var panel_base_position: Vector2 = Vector2.ZERO
var ambient_layer: Control = null
var ambient_particles: Array[ColorRect] = []
var ambient_params: Array[Dictionary] = []
var message_tween: Tween = null

## 初始化
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
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
	for btn: Button in [
		upgrade_button,
		punch_button,
		reroll_value_button,
		reroll_affix_button,
		reforge_button,
		lock_button,
		refresh_button,
		close_button
	]:
		_bind_button_motion(btn)
	if GameManager and GameManager.has_signal("ore_changed"):
		GameManager.ore_changed.connect(_on_ore_changed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_setup_backdrop_fx()
	_apply_visual_theme()
	_setup_panel_glow_fx()
	_fit_panel_to_viewport()
	_setup_ambient_particles()
	panel_base_position = main_panel.position

func _process(delta: float) -> void:
	ui_time += delta
	title_label.scale = title_label.scale.lerp(Vector2.ONE * (1.0 + 0.015 * (0.5 + 0.5 * sin(ui_time * 1.7))), clamp(delta * 7.0, 0.0, 1.0))
	if panel_glow_rect:
		panel_glow_rect.modulate.a = 0.26 + 0.10 * (0.5 + 0.5 * sin(ui_time * 1.2))
		panel_glow_rect.position = Vector2(5.0 * sin(ui_time * 0.48), 4.0 * cos(ui_time * 0.44))
	if ambient_layer:
		_update_ambient_particles(delta)

## 打开工坊
func show_forge() -> void:
	visible = true
	previous_pause_state = get_tree().paused
	get_tree().paused = true
	player = get_tree().get_first_node_in_group("player")
	if ForgeManager:
		ForgeManager.begin_forge_visit()
	if message_label:
		message_label.text = ""
		message_label.modulate = Color.WHITE
	_refresh_ore_label()
	_build_weapon_grid()
	_select_weapon(0)
	_play_panel_open_anim()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_escape"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()

## 关闭工坊
func _on_close_pressed() -> void:
	_reset_panel_transform()
	visible = false
	get_tree().paused = previous_pause_state

##############################################################################
# UI刷新
##############################################################################

## 刷新矿石显示
func _refresh_ore_label() -> void:
	if ore_label:
		ore_label.text = "矿石: " + _format_number(GameManager.ore)

## 矿石变化信号回调
func _on_ore_changed(_amount: int) -> void:
	_refresh_ore_label()

## 构建武器列表（6格）
func _build_weapon_grid() -> void:
	weapon_buttons.clear()
	for child in weapon_grid.get_children():
		child.queue_free()
	if not player:
		return
	for i in range(player.weapon_slots.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(WEAPON_BUTTON_SIZE, WEAPON_BUTTON_SIZE)
		button.text = str(i + 1)
		var weapon_data: Dictionary = player.weapon_slots[i]
		var quality: String = "white"
		var is_empty: bool = weapon_data.is_empty()
		if not weapon_data.is_empty():
			var weapon_id: String = weapon_data.get("weapon_id", "")
			var icon_tex: Texture2D = _load_weapon_icon(weapon_id)
			if icon_tex:
				button.icon = icon_tex
				button.expand_icon = true
				button.text = ""
			quality = weapon_data.get("quality", "white")
		else:
			button.text = "空"
			button.modulate = Color(0.7, 0.7, 0.7, 1.0)
		button.set_meta("quality", quality)
		button.set_meta("slot_index", i)
		button.set_meta("is_empty", is_empty)
		button.pressed.connect(_on_weapon_button_pressed.bind(i))
		button.mouse_entered.connect(_on_weapon_button_hovered.bind(button))
		button.mouse_exited.connect(_on_weapon_button_unhovered.bind(button))
		weapon_grid.add_child(button)
		weapon_buttons.append(button)
	_refresh_weapon_button_states()

## 刷新右侧详情面板
func _refresh_weapon_panel() -> void:
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
	_refresh_weapon_button_states()
	_refresh_weapon_panel()

## 选择词条
func _on_attr_selected(attr_index: int) -> void:
	selected_attr_index = attr_index
	_refresh_action_buttons()

func _refresh_weapon_button_states() -> void:
	for button: Button in weapon_buttons:
		if not is_instance_valid(button):
			continue
		var slot_index: int = int(button.get_meta("slot_index", -1))
		var quality: String = String(button.get_meta("quality", "white"))
		var is_empty: bool = bool(button.get_meta("is_empty", false))
		var is_selected: bool = slot_index == selected_slot_index
		_apply_weapon_button_theme(button, quality, is_selected, is_empty)

func _apply_weapon_button_theme(button: Button, quality: String, is_selected: bool, is_empty: bool) -> void:
	var border_color: Color = _get_quality_color(quality)
	if is_empty:
		border_color = Color(0.45, 0.47, 0.52, 0.95)
	var base_bg: Color = Color(0.09, 0.10, 0.14, 0.96)
	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = base_bg.lerp(border_color, 0.10 if not is_empty else 0.03)
	normal_style.border_color = border_color.lerp(Color.WHITE, 0.12 if is_selected else 0.0)
	normal_style.set_border_width_all(2 if is_selected else 1)
	normal_style.corner_radius_top_left = 10
	normal_style.corner_radius_top_right = 10
	normal_style.corner_radius_bottom_left = 10
	normal_style.corner_radius_bottom_right = 10

	var hover_style: StyleBoxFlat = normal_style.duplicate()
	hover_style.bg_color = normal_style.bg_color.lerp(Color.WHITE, 0.08)
	hover_style.border_color = border_color.lerp(Color.WHITE, 0.24)
	hover_style.set_border_width_all(2)

	var pressed_style: StyleBoxFlat = normal_style.duplicate()
	pressed_style.bg_color = normal_style.bg_color.darkened(0.15)
	pressed_style.set_border_width_all(2)

	var disabled_style: StyleBoxFlat = normal_style.duplicate()
	disabled_style.bg_color = Color(0.16, 0.16, 0.18, 0.82)
	disabled_style.border_color = Color(0.36, 0.36, 0.39, 0.78)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.scale = Vector2.ONE * (1.04 if is_selected else 1.0)

func _on_weapon_button_hovered(button: Button) -> void:
	_tween_button_scale(button, 1.06)

func _on_weapon_button_unhovered(button: Button) -> void:
	var slot_index: int = int(button.get_meta("slot_index", -1))
	_tween_button_scale(button, 1.04 if slot_index == selected_slot_index else 1.0)

## 刷新工坊
func _on_refresh_pressed() -> void:
	var success: bool = bool(ForgeManager and ForgeManager.refresh_forge())
	_build_weapon_grid()
	_refresh_weapon_panel()
	_refresh_ore_label()
	_refresh_action_buttons()
	if success:
		_set_message("刷新完成", false)
	else:
		_set_message("刷新失败：矿石不足或次数已达上限", true)

## 升阶
func _on_upgrade_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		_set_message("升阶失败：请先选择武器", true)
		return
	var success: bool = ForgeManager.upgrade_weapon(weapon_data)
	if success:
		player.update_all_weapons()
	_build_weapon_grid()
	_refresh_weapon_panel()
	_refresh_ore_label()
	if success:
		_set_message("升阶成功", false)
	else:
		_set_message("升阶失败：条件不满足或矿石不足", true)

## 打孔
func _on_punch_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		_set_message("打孔失败：请先选择武器", true)
		return
	var success: bool = ForgeManager.punch_slot(weapon_data)
	if success:
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()
	if success:
		_set_message("打孔成功", false)
	else:
		_set_message("打孔失败：槽位已满或矿石不足", true)

## 敲数值
func _on_reroll_value_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		_set_message("敲数值失败：请先选择武器", true)
		return
	var success: bool = ForgeManager.reroll_value(weapon_data, selected_attr_index)
	if success:
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()
	if success:
		_set_message("敲数值成功", false)
	else:
		_set_message("敲数值失败：词条被锁定或矿石不足", true)

## 洗词条
func _on_reroll_affix_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		_set_message("洗词条失败：请先选择武器", true)
		return
	var success: bool = ForgeManager.reroll_affix(weapon_data, selected_attr_index)
	if success:
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()
	if success:
		_set_message("洗词条成功", false)
	else:
		_set_message("洗词条失败：词条被锁定或矿石不足", true)

## 重铸
func _on_reforge_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		_set_message("重铸失败：请先选择武器", true)
		return
	var success: bool = ForgeManager.reforge_all(weapon_data)
	if success:
		player.update_all_weapons()
	_refresh_weapon_panel()
	_refresh_ore_label()
	if success:
		_set_message("重铸完成", false)
	else:
		_set_message("重铸失败：次数已达上限或矿石不足", true)

## 锁定/解锁词条
func _on_lock_pressed() -> void:
	var weapon_data: Dictionary = _get_selected_weapon()
	if weapon_data.is_empty():
		_set_message("锁定失败：请先选择武器", true)
		return
	var attributes: Array = weapon_data.get("attributes", [])
	if selected_attr_index < 0 or selected_attr_index >= attributes.size():
		_set_message("锁定失败：请先选择词条", true)
		return
	var attr: Dictionary = attributes[selected_attr_index]
	var ok: bool = false
	if attr.get("locked", false):
		ok = ForgeManager.unlock_attribute(weapon_data, selected_attr_index)
	else:
		ok = ForgeManager.lock_attribute(weapon_data, selected_attr_index)
	if ok:
		player.update_all_weapons()
		_refresh_weapon_panel()
		_refresh_ore_label()
		_set_message("锁定状态已更新", false)
	else:
		_set_message("锁定失败：已达上限或矿石不足", true)

## 显示提示
func _set_message(text: String, is_error: bool = false) -> void:
	if message_label:
		message_label.text = text
		message_label.modulate = MESSAGE_COLOR_ERROR if is_error else MESSAGE_COLOR_SUCCESS
		if message_tween:
			message_tween.kill()
		message_label.scale = Vector2(1.02, 1.02)
		message_tween = create_tween()
		message_tween.set_trans(Tween.TRANS_QUAD)
		message_tween.set_ease(Tween.EASE_OUT)
		message_tween.tween_property(message_label, "scale", Vector2.ONE, 0.14)

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

func _format_number(value: int) -> String:
	var sign: String = "-" if value < 0 else ""
	var text: String = str(abs(value))
	var chunks: Array[String] = []
	while text.length() > 3:
		chunks.push_front(text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	chunks.push_front(text)
	return sign + ",".join(chunks)

func _bind_button_motion(button: Button) -> void:
	if not button:
		return
	button.mouse_entered.connect(_on_action_button_hovered.bind(button))
	button.mouse_exited.connect(_on_action_button_unhovered.bind(button))

func _on_action_button_hovered(button: Button) -> void:
	_tween_button_scale(button, 1.05)

func _on_action_button_unhovered(button: Button) -> void:
	_tween_button_scale(button, 1.0)

func _tween_button_scale(button: Control, target: float) -> void:
	if not button:
		return
	var key: String = str(button.get_instance_id())
	if button_tweens.has(key):
		var old_tween: Tween = button_tweens[key]
		if old_tween:
			old_tween.kill()
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * target, 0.12)
	button_tweens[key] = tween

func _setup_backdrop_fx() -> void:
	backdrop_rect = ColorRect.new()
	backdrop_rect.name = "BackdropFX"
	backdrop_rect.anchors_preset = PRESET_FULL_RECT
	backdrop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_rect.color = Color(0.02, 0.03, 0.04, 0.82)
	add_child(backdrop_rect)
	move_child(backdrop_rect, 0)

func _setup_panel_glow_fx() -> void:
	if panel_glow_rect:
		return
	panel_glow_rect = TextureRect.new()
	panel_glow_rect.name = "PanelGlowFX"
	panel_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_glow_rect.anchors_preset = PRESET_FULL_RECT
	panel_glow_rect.texture = _create_glow_texture()
	panel_glow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_glow_rect.stretch_mode = TextureRect.STRETCH_SCALE
	panel_glow_rect.modulate = Color(0.88, 0.80, 0.58, 0.25)
	main_panel.add_child(panel_glow_rect)
	main_panel.move_child(panel_glow_rect, 0)

func _create_glow_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.36, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.20),
		Color(1.0, 1.0, 1.0, 0.06),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 1024
	tex.height = 1024
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex

func _setup_ambient_particles() -> void:
	if ambient_layer:
		return
	ambient_layer = Control.new()
	ambient_layer.name = "AmbientFX"
	ambient_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ambient_layer.anchors_preset = PRESET_FULL_RECT
	ambient_layer.clip_contents = true
	main_panel.add_child(ambient_layer)
	main_panel.move_child(ambient_layer, 1)

	ambient_particles.clear()
	ambient_params.clear()
	for _i in range(16):
		var spark := ColorRect.new()
		var size_px: float = randf_range(2.0, 5.0)
		spark.size = Vector2(size_px, size_px)
		spark.color = Color(0.74 + randf() * 0.18, 0.80 + randf() * 0.14, 0.95 + randf() * 0.05, randf_range(0.08, 0.22))
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ambient_layer.add_child(spark)
		ambient_particles.append(spark)
		ambient_params.append({
			"speed": randf_range(10.0, 24.0),
			"drift": randf_range(5.0, 11.0) * (1.0 if randf() < 0.5 else -1.0),
			"phase": randf() * TAU,
			"base_a": randf_range(0.08, 0.22)
		})
	_reset_ambient_particles()

func _reset_ambient_particles() -> void:
	if not ambient_layer or not main_panel:
		return
	var panel_size: Vector2 = main_panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	for i in range(ambient_particles.size()):
		var spark: ColorRect = ambient_particles[i]
		if not is_instance_valid(spark):
			continue
		spark.position = Vector2(
			randf_range(8.0, max(12.0, panel_size.x - 12.0)),
			randf_range(8.0, max(12.0, panel_size.y - 12.0))
		)
		var data: Dictionary = ambient_params[i]
		data["phase"] = randf() * TAU
		ambient_params[i] = data

func _update_ambient_particles(delta: float) -> void:
	if not main_panel:
		return
	var panel_size: Vector2 = main_panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	for i in range(ambient_particles.size()):
		var spark: ColorRect = ambient_particles[i]
		if not is_instance_valid(spark):
			continue
		var data: Dictionary = ambient_params[i]
		var speed: float = float(data.get("speed", 16.0))
		var drift: float = float(data.get("drift", 8.0))
		var phase: float = float(data.get("phase", 0.0))
		var base_a: float = float(data.get("base_a", 0.14))
		var pos: Vector2 = spark.position
		pos.y -= speed * delta
		pos.x += drift * sin(ui_time * 1.15 + phase) * delta
		if pos.y < -10.0:
			pos.y = panel_size.y + randf_range(2.0, 20.0)
			pos.x = randf_range(8.0, max(12.0, panel_size.x - 12.0))
		if pos.x < -12.0:
			pos.x = panel_size.x + randf_range(0.0, 8.0)
		elif pos.x > panel_size.x + 12.0:
			pos.x = -randf_range(0.0, 8.0)
		spark.position = pos
		var alpha: float = base_a + 0.10 * (0.5 + 0.5 * sin(ui_time * 1.8 + phase))
		var c: Color = spark.color
		c.a = alpha
		spark.color = c
		data["phase"] = phase + delta * 0.32
		ambient_params[i] = data

func _apply_visual_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI_BG_PRIMARY
	panel_style.border_color = UI_BORDER_PRIMARY
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.shadow_size = 20
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.44)
	panel_style.shadow_offset = Vector2(0, 10)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	var action_style := StyleBoxFlat.new()
	action_style.bg_color = UI_BUTTON_BG
	action_style.border_color = UI_BORDER_ACCENT
	action_style.set_border_width_all(1)
	action_style.corner_radius_top_left = 8
	action_style.corner_radius_top_right = 8
	action_style.corner_radius_bottom_left = 8
	action_style.corner_radius_bottom_right = 8
	var action_hover := action_style.duplicate()
	action_hover.bg_color = UI_BUTTON_BG_HOVER
	var action_pressed := action_style.duplicate()
	action_pressed.bg_color = UI_BUTTON_BG_PRESSED
	var action_disabled := action_style.duplicate()
	action_disabled.bg_color = UI_BUTTON_BG_DISABLED
	action_disabled.border_color = UI_BORDER_PRIMARY.darkened(0.24)
	for btn: Button in [
		upgrade_button,
		punch_button,
		reroll_value_button,
		reroll_affix_button,
		reforge_button,
		lock_button,
		refresh_button,
		close_button
	]:
		btn.add_theme_stylebox_override("normal", action_style)
		btn.add_theme_stylebox_override("hover", action_hover)
		btn.add_theme_stylebox_override("pressed", action_pressed)
		btn.add_theme_stylebox_override("disabled", action_disabled)
	title_label.add_theme_color_override("font_color", Color(0.98, 0.97, 0.92))
	ore_label.add_theme_color_override("font_color", Color(0.98, 0.90, 0.68))
	weapon_list_label.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
	selected_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	weapon_info_label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98))
	attr_title_label.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
	message_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.86))
	message_label.add_theme_constant_override("outline_size", 2)

func _fit_panel_to_viewport() -> void:
	if not main_panel:
		return
	var vp: Vector2 = get_viewport_rect().size
	var panel_w: float = clamp(vp.x * 0.95, 960.0, 1420.0)
	var panel_h: float = clamp(vp.y * 0.93, 640.0, 920.0)
	main_panel.offset_left = -panel_w * 0.5
	main_panel.offset_right = panel_w * 0.5
	main_panel.offset_top = -panel_h * 0.5
	main_panel.offset_bottom = panel_h * 0.5
	panel_base_position = main_panel.position
	if vp.x < 940.0:
		weapon_grid.columns = 1
	elif vp.x < 1180.0:
		weapon_grid.columns = 2
	else:
		weapon_grid.columns = 3
	_apply_responsive_layout(vp)

func _apply_responsive_layout(vp: Vector2 = get_viewport_rect().size) -> void:
	root_vbox.add_theme_constant_override("separation", int(clamp(vp.y * 0.014, 10.0, 20.0)))
	header_box.add_theme_constant_override("separation", int(clamp(vp.x * 0.008, 10.0, 20.0)))
	footer_box.add_theme_constant_override("separation", int(clamp(vp.x * 0.008, 10.0, 18.0)))
	content_row.add_theme_constant_override("separation", int(clamp(vp.x * 0.012, 12.0, 24.0)))
	weapon_grid.add_theme_constant_override("h_separation", int(clamp(vp.x * 0.008, 10.0, 18.0)))
	weapon_grid.add_theme_constant_override("v_separation", int(clamp(vp.y * 0.012, 10.0, 18.0)))
	title_label.add_theme_font_size_override("font_size", int(clamp(vp.x / 58.0, 24.0, 34.0)))
	ore_label.add_theme_font_size_override("font_size", int(clamp(vp.x / 96.0, 16.0, 24.0)))
	selected_label.add_theme_font_size_override("font_size", int(clamp(vp.x / 84.0, 17.0, 25.0)))
	attr_title_label.add_theme_font_size_override("font_size", int(clamp(vp.x / 100.0, 15.0, 22.0)))
	weapon_info_label.add_theme_font_size_override("font_size", int(clamp(vp.x / 110.0, 13.0, 18.0)))
	message_label.add_theme_font_size_override("font_size", int(clamp(vp.x / 112.0, 13.0, 18.0)))
	var action_h: float = clamp(vp.y * 0.048, 38.0, 52.0)
	for btn: Button in [
		upgrade_button,
		punch_button,
		reroll_value_button,
		reroll_affix_button,
		reforge_button,
		lock_button
	]:
		btn.custom_minimum_size = Vector2(max(160.0, vp.x * 0.13), action_h)
	refresh_button.custom_minimum_size = Vector2(max(160.0, vp.x * 0.13), action_h + 2.0)
	close_button.custom_minimum_size = Vector2(max(160.0, vp.x * 0.13), action_h + 2.0)

func _on_viewport_size_changed() -> void:
	_fit_panel_to_viewport()
	_reset_ambient_particles()

func _play_panel_open_anim() -> void:
	if not main_panel:
		return
	_reset_panel_transform()
	main_panel.pivot_offset = main_panel.size * 0.5
	main_panel.position = panel_base_position + Vector2(0.0, 14.0)
	main_panel.scale = Vector2(0.96, 0.96)
	main_panel.modulate.a = 0.0
	if panel_anim_tween:
		panel_anim_tween.kill()
	panel_anim_tween = create_tween()
	panel_anim_tween.set_trans(Tween.TRANS_CUBIC)
	panel_anim_tween.set_ease(Tween.EASE_OUT)
	panel_anim_tween.tween_property(main_panel, "scale", Vector2.ONE, 0.22)
	panel_anim_tween.parallel().tween_property(main_panel, "modulate:a", 1.0, 0.20)
	panel_anim_tween.parallel().tween_property(main_panel, "position", panel_base_position, 0.20)

func _reset_panel_transform() -> void:
	if not main_panel:
		return
	main_panel.position = panel_base_position
	main_panel.scale = Vector2.ONE
	main_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
