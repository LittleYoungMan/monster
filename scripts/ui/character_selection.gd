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

@onready var big_icon: TextureRect = $Root/MainVBox/TopPanel/TopHBox/BigIcon
@onready var name_label: Label = $Root/MainVBox/TopPanel/TopHBox/InfoVBox/NameLabel
@onready var spec_label: Label = $Root/MainVBox/TopPanel/TopHBox/InfoVBox/SpecLabel
@onready var stats_grid: GridContainer = $Root/MainVBox/TopPanel/TopHBox/InfoVBox/StatsGrid
@onready var grid_container: GridContainer = $Root/MainVBox/BottomPanel/BottomHBox/ScrollContainer/CharacterGrid
@onready var start_button: Button = $Root/MainVBox/BottomPanel/BottomHBox/RightPanel/StartButton
@onready var quit_button: Button = $Root/MainVBox/BottomPanel/BottomHBox/RightPanel/QuitButton

##############################################################################
# 运行期数据
##############################################################################

var selected_id: String = ""
var selected_item: Control = null
var cell_style_normal: StyleBoxFlat = null
var cell_style_selected: StyleBoxFlat = null

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	_prepare_cell_styles()
	_build_character_grid()
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

##############################################################################
# UI构建
##############################################################################

func _build_character_grid() -> void:
	for child: Node in grid_container.get_children():
		child.queue_free()

	var ids: Array[String] = GameData.get_all_character_ids()
	ids.sort()

	for char_id: String in ids:
		var data: Dictionary = GameData.get_character(char_id)
		var display_name: String = data.get("name_cn", char_id)

		var cell: PanelContainer = PanelContainer.new()
		cell.custom_minimum_size = Vector2(64, 80)
		cell.add_theme_stylebox_override("panel", cell_style_normal)

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 3)
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var icon_wrap: CenterContainer = CenterContainer.new()
		icon_wrap.custom_minimum_size = Vector2(48, 48)

		var icon: TextureRect = TextureRect.new()
		icon.texture = _load_character_icon(char_id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40, 40)

		var button: Button = Button.new()
		button.text = ""
		button.flat = true
		button.custom_minimum_size = Vector2(48, 48)
		button.pressed.connect(_on_character_selected.bind(char_id, cell))

		var label: Label = Label.new()
		label.text = display_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)

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
	var data: Dictionary = GameData.get_character(char_id)
	var stats: Dictionary = GameData.calculate_character_stats(char_id, 1)

	name_label.text = data.get("name_cn", char_id)
	spec_label.text = data.get("Spec", "")
	big_icon.texture = _load_character_icon(char_id)

	for child: Node in stats_grid.get_children():
		child.queue_free()

	var display_stats: Array = [
		["生命", stats.get("Health", 0)],
		["护甲", stats.get("Armor", 0)],
		["移速", stats.get("MoveSpeed", 0)],
		["近战", stats.get("MeleeDamage", 0)],
		["远程", stats.get("RangedDamage", 0)],
		["元素", stats.get("ElementalDamage", 0)],
		["召唤", stats.get("SummonDamage", 0)],
		["暴击率", stats.get("CritRate", 0)],
		["暴击伤害", stats.get("CritDamage", 0)],
		["冷却", stats.get("Cooldown", 0)],
		["闪避", stats.get("Dodge", 0)]
	]

	for row in display_stats:
		var key_label: Label = Label.new()
		key_label.text = str(row[0]) + ":"
		var val_label: Label = Label.new()
		val_label.text = str(row[1])
		stats_grid.add_child(key_label)
		stats_grid.add_child(val_label)

##############################################################################
# 资源加载
##############################################################################

func _load_character_icon(char_id: String) -> Texture2D:
	var path: String = "res://assets/PIC/role/256/" + char_id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return _generate_placeholder_texture(char_id)

func _generate_placeholder_texture(char_id: String) -> Texture2D:
	var img: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var hash_value: int = char_id.hash()
	var r: float = float((hash_value >> 16) & 0xFF) / 255.0
	var g: float = float((hash_value >> 8) & 0xFF) / 255.0
	var b: float = float(hash_value & 0xFF) / 255.0
	img.fill(Color(r, g, b, 1.0))
	return ImageTexture.create_from_image(img)

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
