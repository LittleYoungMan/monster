##############################################################################
# CharacterSelection - 角色选择界面
#
# 设计目的：
# - 从GameData读取角色列表
# - 选择角色后进入游戏场景
##############################################################################
extends Control

##############################################################################
# 节点引用
##############################################################################

@onready var big_icon: TextureRect = $Root/MainVBox/MainContent/LeftPanel/BigIcon
@onready var name_label: Label = $Root/MainVBox/MainContent/LeftPanel/StatsPanel/StatsScroll/StatsVBox/NameLabel
@onready var spec_label: Label = $Root/MainVBox/MainContent/LeftPanel/StatsPanel/StatsScroll/StatsVBox/SpecLabel
@onready var stats_grid: GridContainer = $Root/MainVBox/MainContent/LeftPanel/StatsPanel/StatsScroll/StatsVBox/StatsGrid
@onready var grid_container: GridContainer = $Root/MainVBox/MainContent/RightPanel/ScrollContainer/CharacterGrid
@onready var start_button: Button = $Root/MainVBox/MainContent/LeftPanel/ButtonHBox/StartButton
@onready var quit_button: Button = $Root/MainVBox/MainContent/LeftPanel/ButtonHBox/QuitButton

##############################################################################
# 运行期数据
##############################################################################

var selected_id: String = ""
var selected_item: Control = null
var cell_style_normal: StyleBoxFlat = null
var cell_style_selected: StyleBoxFlat = null

##############################################################################
# 可调参数
##############################################################################

## 角色列表小图尺寸
## 单位：像素
## 作用：控制角色列表图标区域
## 调整范围：120-220
## 当前值：180
const ICON_SIZE_SMALL: int = 180

## 角色列表大图尺寸
## 单位：像素
## 作用：控制左侧大图显示区域
## 调整范围：240-360
## 当前值：300
const ICON_SIZE_LARGE: int = 300

## 角色列表格子尺寸
## 单位：像素
## 作用：单个角色格子大小
## 调整范围：180-260
## 当前值：220x210
const CELL_SIZE: Vector2 = Vector2(220, 210)

## 角色列表图标包裹尺寸
## 单位：像素
## 作用：图标显示区域
## 调整范围：160-220
## 当前值：190
const ICON_WRAP_SIZE: Vector2 = Vector2(190, 190)

## 脚底留白像素
## 单位：像素
## 作用：避免脚底被裁切
## 调整范围：0-12
## 当前值：6
const ICON_FOOT_PADDING: float = 6.0

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	## 初始化角色格子样式与列表
	_prepare_cell_styles()
	_build_character_grid()
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# 隐藏原有的SpecLabel，因为Spec内容现在通过stats_grid动态添加
	spec_label.visible = false

##############################################################################
# UI构建
##############################################################################

## 构建角色列表格子
func _build_character_grid() -> void:
	for child: Node in grid_container.get_children():
		child.queue_free()

	var ids: Array[String] = GameData.get_all_character_ids()
	ids.sort()

	for char_id: String in ids:
		if char_id.is_empty():
			continue

		var data: Dictionary = GameData.get_character(char_id)
		if data.is_empty():
			continue

		var display_name: String = data.get("name_cn", char_id)

		var cell: PanelContainer = PanelContainer.new()
		cell.custom_minimum_size = CELL_SIZE
		cell.add_theme_stylebox_override("panel", cell_style_normal)

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 10)
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var icon_wrap: CenterContainer = CenterContainer.new()
		icon_wrap.custom_minimum_size = ICON_WRAP_SIZE

		var icon: TextureRect = TextureRect.new()
		var icon_tex: Texture2D = _load_character_icon(char_id)
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		icon.custom_minimum_size = Vector2(ICON_SIZE_SMALL, ICON_SIZE_SMALL)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 列表小图保持居中显示，避免影响整体布局

		var button: Button = Button.new()
		button.text = ""
		button.flat = true
		button.custom_minimum_size = ICON_WRAP_SIZE
		button.pressed.connect(_on_character_selected.bind(char_id, cell))

		var label: Label = Label.new()
		label.text = display_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		icon_wrap.add_child(icon)
		icon_wrap.add_child(button)
		vbox.add_child(icon_wrap)
		vbox.add_child(label)
		cell.add_child(vbox)
		grid_container.add_child(cell)

		if selected_id.is_empty():
			_set_selected(char_id, cell)

##############################################################################
# 选中逻辑
##############################################################################

func _on_character_selected(char_id: String, cell: Control) -> void:
	_set_selected(char_id, cell)

func _set_selected(char_id: String, cell: Control) -> void:
	selected_id = char_id
	if selected_item and is_instance_valid(selected_item):
		if selected_item is PanelContainer:
			selected_item.add_theme_stylebox_override("panel", cell_style_normal)
	selected_item = cell
	if selected_item is PanelContainer:
		selected_item.add_theme_stylebox_override("panel", cell_style_selected)

	_update_top_panel(char_id)

func _update_top_panel(char_id: String) -> void:
	## 更新左侧大图与数值面板
	var data: Dictionary = GameData.get_character(char_id)
	var stats: Dictionary = GameData.calculate_character_stats(char_id, 1)

	name_label.text = data.get("name_cn", char_id)
	var spec_value: String = data.get("Spec", "")
	var big_tex: Texture2D = _load_character_icon(char_id)
	big_icon.texture = big_tex
	big_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	big_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	big_icon.custom_minimum_size = Vector2(ICON_SIZE_LARGE, ICON_SIZE_LARGE)
	big_icon.size = Vector2(ICON_SIZE_LARGE, ICON_SIZE_LARGE)
	_apply_icon_feet_align(big_icon, big_tex, Vector2(ICON_SIZE_LARGE, ICON_SIZE_LARGE))

	# 正确清空stats_grid的所有子节点
	for child: Node in stats_grid.get_children():
		stats_grid.remove_child(child)
		child.queue_free()

	# 收集基础属性（非零）
	var base_attrs: Array = []
	for key in stats:
		var value = stats[key]
		if key != "id" and key != "name_cn" and key != "name_en" and key != "initial_weapon" and key != "Spec":
			# 使用float()转换确保数值比较正确
			var float_value: float = float(value)
			if float_value != 0.0:
				base_attrs.append([key, float_value])

	# 只有在有基础属性时才添加标题和内容
	if not base_attrs.is_empty():
		var base_title: Label = Label.new()
		base_title.text = "基础属性"
		base_title.add_theme_font_size_override("font_size", 14)
		stats_grid.add_child(base_title)
		var base_empty: Label = Label.new()
		base_empty.text = ""
		stats_grid.add_child(base_empty)

		for attr in base_attrs:
			var key_label: Label = Label.new()
			key_label.text = Localization.tr_text(attr[0]) + ":"
			var val_label: Label = Label.new()
			val_label.text = str(attr[1])
			stats_grid.add_child(key_label)
			stats_grid.add_child(val_label)

	# 收集成长属性（非零）
	var growth_attrs: Array = []
	for key in data:
		if key.begins_with("Grow_"):
			var value = data[key]
			# 使用float()转换确保数值比较正确
			var float_value: float = float(value)
			if float_value != 0.0:
				growth_attrs.append([key, float_value])

	# 只有在有成长属性时才添加标题和内容
	if not growth_attrs.is_empty():
		# 如果前面有基础属性，添加间隔行
		if not base_attrs.is_empty():
			var spacer1: Label = Label.new()
			spacer1.text = ""
			stats_grid.add_child(spacer1)
			var spacer2: Label = Label.new()
			spacer2.text = ""
			stats_grid.add_child(spacer2)

		var growth_title: Label = Label.new()
		growth_title.text = "成长属性"
		growth_title.add_theme_font_size_override("font_size", 14)
		stats_grid.add_child(growth_title)
		var growth_empty: Label = Label.new()
		growth_empty.text = ""
		stats_grid.add_child(growth_empty)

		for attr in growth_attrs:
			var attr_name: String = attr[0].replace("Grow_", "")
			var display_name: String = Localization.tr_text(attr_name)
			var key_label: Label = Label.new()
			key_label.text = display_name + ":"
			var val_label: Label = Label.new()
			var value_str: String = str(attr[1])
			if attr[1] > 0:
				value_str = "+" + value_str
			val_label.text = value_str
			stats_grid.add_child(key_label)
			stats_grid.add_child(val_label)

	# 在最底下添加特性标题和内容
	if not spec_value.is_empty() and spec_value != "0":
		# 如果前面有属性，添加间隔行
		if not base_attrs.is_empty() or not growth_attrs.is_empty():
			var spacer1: Label = Label.new()
			spacer1.text = ""
			stats_grid.add_child(spacer1)
			var spacer2: Label = Label.new()
			spacer2.text = ""
			stats_grid.add_child(spacer2)

		var spec_title: Label = Label.new()
		spec_title.text = "特性"
		spec_title.add_theme_font_size_override("font_size", 14)
		stats_grid.add_child(spec_title)
		var empty1: Label = Label.new()
		stats_grid.add_child(empty1)

		# 特性内容占据整行：第一列放内容，第二列留空但让内容扩展
		var spec_content: Label = Label.new()
		spec_content.text = spec_value
		spec_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		spec_content.custom_minimum_size = Vector2(350, 0)  # 设置最小宽度接近整行
		stats_grid.add_child(spec_content)
		var empty2: Label = Label.new()
		stats_grid.add_child(empty2)

##############################################################################
# 资源加载
##############################################################################

func _load_character_icon(char_id: String) -> Texture2D:
	## 加载角色图标（失败则占位）
	var path: String = "res://assets/PIC/role/256/" + char_id + ".png"
	var texture: Texture2D = load(path)
	if texture:
		return texture
	print("[CharacterSelection] 图标加载失败: ", char_id, " 路径: ", path)
	return _generate_placeholder_texture(char_id)

func _generate_placeholder_texture(char_id: String) -> Texture2D:
	## 生成占位图标（按ID哈希着色）
	var img: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var hash_value: int = char_id.hash()
	var r: float = float((hash_value >> 16) & 0xFF) / 255.0
	var g: float = float((hash_value >> 8) & 0xFF) / 255.0
	var b: float = float(hash_value & 0xFF) / 255.0
	img.fill(Color(r, g, b, 1.0))
	return ImageTexture.create_from_image(img)

## 角色图标脚底对齐（解决不同留白造成的裁切）
##
## 参数：
##   rect - 目标TextureRect
##   texture - 图标贴图
##   target_size - 目标尺寸
func _apply_icon_feet_align(rect: TextureRect, texture: Texture2D, target_size: Vector2) -> void:
	if not rect or not texture:
		return
	var img: Image = texture.get_image()
	if img == null:
		return
	if target_size.x <= 0.0 or target_size.y <= 0.0:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var min_x: int = w
	var min_y: int = h
	var max_x: int = -1
	var max_y: int = -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.01:
				if x < min_x:
					min_x = x
				if y < min_y:
					min_y = y
				if x > max_x:
					max_x = x
				if y > max_y:
					max_y = y
	if max_x == -1:
		return
	var content_w: float = float(max_x - min_x + 1)
	var content_h: float = float(max_y - min_y + 1)
	# 使用内容尺寸作为纹理矩形基础，避免父容器未设置size导致不可见
	rect.custom_minimum_size = Vector2(content_w, content_h)
	rect.size = Vector2(content_w, content_h)
	var scale: float = min(target_size.x / content_w, target_size.y / content_h)
	rect.scale = Vector2(scale, scale)
	var content_bottom: float = float(max_y - min_y + 1) * scale
	var desired_bottom: float = target_size.y - ICON_FOOT_PADDING
	var offset_y: float = desired_bottom - content_bottom - float(min_y) * scale
	var offset_x: float = -float(min_x) * scale + (target_size.x - content_w * scale) * 0.5
	rect.position = Vector2(offset_x, offset_y)

func _prepare_cell_styles() -> void:
	cell_style_normal = StyleBoxFlat.new()
	cell_style_normal.bg_color = Color(0.12, 0.12, 0.13, 1.0)
	cell_style_normal.border_width_left = 2
	cell_style_normal.border_width_top = 2
	cell_style_normal.border_width_right = 2
	cell_style_normal.border_width_bottom = 2
	cell_style_normal.border_color = Color(0.18, 0.18, 0.2, 1.0)
	cell_style_normal.corner_radius_top_left = 4
	cell_style_normal.corner_radius_top_right = 4
	cell_style_normal.corner_radius_bottom_left = 4
	cell_style_normal.corner_radius_bottom_right = 4

	cell_style_selected = StyleBoxFlat.new()
	cell_style_selected.bg_color = Color(0.16, 0.14, 0.08, 1.0)
	cell_style_selected.border_width_left = 2
	cell_style_selected.border_width_top = 2
	cell_style_selected.border_width_right = 2
	cell_style_selected.border_width_bottom = 2
	cell_style_selected.border_color = Color(0.95, 0.7, 0.25, 1.0)
	cell_style_selected.corner_radius_top_left = 4
	cell_style_selected.corner_radius_top_right = 4
	cell_style_selected.corner_radius_bottom_left = 4
	cell_style_selected.corner_radius_bottom_right = 4

##############################################################################
# 回调
##############################################################################

func _on_start_pressed() -> void:
	if selected_id.is_empty():
		return

	GameManager.selected_character_id = selected_id
	GameManager.reset_game()
	get_tree().change_scene_to_file("res://scenes/run/main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
