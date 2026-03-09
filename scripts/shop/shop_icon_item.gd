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

const ICON_BG: Color = Color(0.075, 0.085, 0.11, 0.94)
const ICON_BORDER_BASE: Color = Color(0.34, 0.44, 0.58, 0.95)

##############################################################################
# 节点引用
##############################################################################

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $Count

##############################################################################
# 运行期数据
##############################################################################

var tooltip_content: String = ""
var quality_key: String = "white"
var panel_style_runtime: StyleBoxFlat = null
var idle_time: float = 0.0
var hover_weight: float = 0.0
var hover_target: float = 0.0
var icon_glow: TextureRect = null
var sheen_overlay: TextureRect = null
var sheen_tween: Tween = null
var auto_sheen_timer: float = 0.0

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	idle_time = randf() * TAU
	auto_sheen_timer = randf_range(1.0, 3.0)
	_ensure_icon_glow()
	_ensure_sheen_overlay()
	count_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	count_label.add_theme_constant_override("outline_size", 2)

func _process(delta: float) -> void:
	idle_time += delta
	hover_weight = lerpf(hover_weight, hover_target, clamp(delta * 9.0, 0.0, 1.0))
	auto_sheen_timer -= delta
	if auto_sheen_timer <= 0.0 and hover_target < 0.3:
		_play_sheen()
		auto_sheen_timer = randf_range(2.4, 4.8)
	var pulse: float = 0.80 + 0.20 * (0.5 + 0.5 * sin(idle_time * 2.4))
	if panel_style_runtime:
		panel_style_runtime.border_color = _quality_color(quality_key).lerp(Color.WHITE, 0.14 * pulse + 0.14 * hover_weight)
	icon.scale = icon.scale.lerp(Vector2.ONE * (1.0 + 0.035 * pulse + 0.07 * hover_weight), clamp(delta * 8.0, 0.0, 1.0))
	scale = scale.lerp(Vector2.ONE * (1.0 + 0.05 * hover_weight), clamp(delta * 10.0, 0.0, 1.0))
	if icon_glow:
		icon_glow.modulate.a = 0.12 + 0.18 * pulse + 0.16 * hover_weight
	if count_label.visible:
		count_label.scale = count_label.scale.lerp(Vector2.ONE * (1.0 + 0.05 * pulse), clamp(delta * 8.0, 0.0, 1.0))

func _on_resized() -> void:
	pivot_offset = size * 0.5

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
	quality_key = quality
	hover_target = 0.0
	hover_weight = 0.0
	auto_sheen_timer = randf_range(1.2, 3.8)
	_set_count(count)
	_apply_quality_border(quality_key)

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
	panel_style_runtime = StyleBoxFlat.new()
	panel_style_runtime.bg_color = ICON_BG
	panel_style_runtime.set_border_width_all(2)
	panel_style_runtime.corner_radius_top_left = 8
	panel_style_runtime.corner_radius_top_right = 8
	panel_style_runtime.corner_radius_bottom_left = 8
	panel_style_runtime.corner_radius_bottom_right = 8
	panel_style_runtime.shadow_size = 8
	panel_style_runtime.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	panel_style_runtime.shadow_offset = Vector2(0, 3)
	panel_style_runtime.border_color = ICON_BORDER_BASE.lerp(color, 0.62)
	add_theme_stylebox_override("panel", panel_style_runtime)
	if icon_glow:
		icon_glow.modulate = color.lerp(Color.WHITE, 0.24)
		icon_glow.modulate.a = 0.20

func _quality_color(quality: String) -> Color:
	match quality:
		"white":
			return Color(0.92, 0.92, 0.92)
		"blue":
			return Color(0.48, 0.66, 0.96)
		"purple":
			return Color(0.78, 0.56, 0.96)
		"gold":
			return Color(0.98, 0.82, 0.44)
		_:
			return Color(0.92, 0.92, 0.92)

##############################################################################
# 输入
##############################################################################

func _on_mouse_entered() -> void:
	hover_target = 1.0
	auto_sheen_timer = randf_range(2.2, 3.4)
	_play_sheen()
	if not tooltip_content.is_empty():
		hovered.emit(tooltip_content)

func _on_mouse_exited() -> void:
	hover_target = 0.0
	unhovered.emit()

func _ensure_icon_glow() -> void:
	if icon_glow:
		return
	icon_glow = TextureRect.new()
	icon_glow.name = "IconGlow"
	icon_glow.texture = _make_glow_texture()
	icon_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_glow.anchors_preset = PRESET_FULL_RECT
	icon_glow.offset_left = -6.0
	icon_glow.offset_top = -6.0
	icon_glow.offset_right = 6.0
	icon_glow.offset_bottom = 6.0
	icon_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_glow.stretch_mode = TextureRect.STRETCH_SCALE
	icon_glow.modulate = Color(1.0, 1.0, 1.0, 0.2)
	icon.add_child(icon_glow)
	icon.move_child(icon_glow, 0)

func _ensure_sheen_overlay() -> void:
	if sheen_overlay:
		return
	sheen_overlay = TextureRect.new()
	sheen_overlay.name = "SheenOverlay"
	sheen_overlay.texture = _make_sheen_texture()
	sheen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen_overlay.anchors_preset = PRESET_FULL_RECT
	sheen_overlay.offset_left = -24.0
	sheen_overlay.offset_right = -12.0
	sheen_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheen_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	sheen_overlay.rotation_degrees = 16.0
	sheen_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(sheen_overlay)
	move_child(sheen_overlay, get_child_count() - 1)

func _play_sheen() -> void:
	if not sheen_overlay:
		return
	if sheen_tween:
		sheen_tween.kill()
	sheen_overlay.offset_left = -82.0
	sheen_overlay.offset_right = -58.0
	sheen_overlay.modulate.a = 0.0
	sheen_tween = create_tween()
	sheen_tween.set_trans(Tween.TRANS_QUAD)
	sheen_tween.set_ease(Tween.EASE_OUT)
	sheen_tween.tween_property(sheen_overlay, "modulate:a", 0.36, 0.07)
	sheen_tween.parallel().tween_property(sheen_overlay, "offset_left", 96.0, 0.22)
	sheen_tween.parallel().tween_property(sheen_overlay, "offset_right", 120.0, 0.22)
	sheen_tween.tween_property(sheen_overlay, "modulate:a", 0.0, 0.10)

func _make_glow_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.36),
		Color(1.0, 1.0, 1.0, 0.14),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 96
	tex.height = 96
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex

func _make_sheen_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 0.5, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.95),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 48
	tex.height = 160
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex
