##############################################################################
# ShopIconItem - 商店底部图标条目
#
# 设计目的：
# - 显示单个武器/道具图标
# - 支持品质边框与数量角标
##############################################################################
extends Panel

signal hovered(tooltip_content: String)
signal unhovered()

##############################################################################
# 节点引用
##############################################################################

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $Count

##############################################################################
# 运行期数据
##############################################################################

var tooltip_content: String = ""

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

##############################################################################
# 对外接口
##############################################################################

## 设置图标内容
##
## 参数：
##   texture - 图标纹理
##   count - 数量（<=1时隐藏）
##   quality - 品质字符串
##   tooltip - 悬浮提示文本
func setup(texture: Texture2D, count: int, quality: String, tooltip: String = "") -> void:
	icon.texture = texture
	tooltip_content = tooltip
	_set_count(count)
	_apply_quality_border(quality)

##############################################################################
# 内部：数量与边框
##############################################################################

func _set_count(count: int) -> void:
	if count <= 1:
		count_label.visible = false
		return
	count_label.visible = true
	count_label.text = "x" + str(count)

func _apply_quality_border(quality: String) -> void:
	var color: Color = _quality_color(quality)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	style.set_border_width_all(2)
	style.border_color = color
	add_theme_stylebox_override("panel", style)

func _quality_color(quality: String) -> Color:
	match quality:
		"white":
			return Color(0.9, 0.9, 0.9)
		"blue":
			return Color(0.4, 0.6, 1.0)
		"purple":
			return Color(0.8, 0.4, 1.0)
		"gold":
			return Color(1.0, 0.85, 0.4)
		_:
			return Color(0.9, 0.9, 0.9)

##############################################################################
# 输入
##############################################################################

func _on_mouse_entered() -> void:
	if not tooltip_content.is_empty():
		hovered.emit(tooltip_content)

func _on_mouse_exited() -> void:
	unhovered.emit()
