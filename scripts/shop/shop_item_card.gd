##############################################################################
# ShopItemCard - 商店商品卡片
#
# 设计目的：
# - 展示武器/商店卡信息
# - 提供购买按钮与售罄显示
# - 将点击事件通知ShopUI
##############################################################################
extends Panel

signal buy_pressed(offer_index: int)

const CARD_BG_BASE: Color = Color(0.085, 0.097, 0.122, 0.965)
const CARD_BG_DARK: Color = Color(0.065, 0.075, 0.095, 0.965)
const CARD_BORDER_BASE: Color = Color(0.36, 0.46, 0.60, 0.95)
const CARD_ACCENT: Color = Color(0.90, 0.72, 0.40, 0.98)
const CARD_BUTTON_BG: Color = Color(0.25, 0.35, 0.48, 0.98)
const CARD_BUTTON_BG_HOVER: Color = Color(0.33, 0.44, 0.58, 0.98)
const CARD_BUTTON_BG_PRESSED: Color = Color(0.18, 0.26, 0.35, 0.98)
const CARD_BUTTON_BG_DISABLED: Color = Color(0.18, 0.20, 0.24, 0.80)

##############################################################################
# 节点引用
##############################################################################

@onready var icon: TextureRect = $VBox/TopRow/Icon
@onready var name_label: Label = $VBox/TopRow/TopText/NameLabel
@onready var rarity_label: Label = $VBox/TopRow/TopText/RarityLabel
@onready var effect_label: Label = $VBox/EffectScroll/EffectVBox/EffectLabel
@onready var price_label: Label = $VBox/BottomRow/PriceLabel
@onready var buy_button: Button = $VBox/BottomRow/BuyButton
@onready var sold_label: Label = $SoldLabel

##############################################################################
# 运行期数据
##############################################################################

var offer_index: int = -1
var offer_data: Dictionary = {}
var card_quality: String = "white"
var panel_style_runtime: StyleBoxFlat = null
var idle_time: float = 0.0
var hover_weight: float = 0.0
var hover_target: float = 0.0
var sold_state: bool = false
var sheen_overlay: TextureRect = null
var sheen_tween: Tween = null
var auto_sheen_timer: float = 0.0
var icon_glow: TextureRect = null

##############################################################################
# 生命周期
##############################################################################

## 初始化按钮信号
##
## 参数：无
## 返回：无
func _ready() -> void:
	## 绑定购买按钮
	buy_button.pressed.connect(_on_buy_pressed)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	idle_time = randf() * TAU
	auto_sheen_timer = randf_range(1.0, 2.6)
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	## 效果列表单列展示，避免分栏挤压导致逐字换行
	if effect_label:
		effect_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_visual_theme()
	_ensure_icon_glow()
	_ensure_sheen_overlay()
	_apply_localized_text()

func _process(delta: float) -> void:
	idle_time += delta
	var lerp_speed: float = 10.0 if hover_target > hover_weight else 7.0
	hover_weight = lerpf(hover_weight, hover_target, clamp(delta * lerp_speed, 0.0, 1.0))
	if sold_state:
		icon.scale = icon.scale.lerp(Vector2.ONE, clamp(delta * 8.0, 0.0, 1.0))
		icon.rotation = lerpf(icon.rotation, 0.0, clamp(delta * 8.0, 0.0, 1.0))
		scale = scale.lerp(Vector2.ONE, clamp(delta * 8.0, 0.0, 1.0))
		rotation = lerpf(rotation, 0.0, clamp(delta * 8.0, 0.0, 1.0))
		return

	auto_sheen_timer -= delta
	if auto_sheen_timer <= 0.0 and hover_target < 0.4:
		_play_sheen()
		auto_sheen_timer = randf_range(2.6, 4.6)

	var bob: float = sin(idle_time * 1.8 + float(offer_index) * 0.47)
	var breath: float = 1.0 + 0.018 * bob + 0.025 * hover_weight
	icon.scale = icon.scale.lerp(Vector2.ONE * breath, clamp(delta * 10.0, 0.0, 1.0))
	icon.rotation = lerpf(icon.rotation, 0.035 * sin(idle_time * 2.2), clamp(delta * 7.5, 0.0, 1.0))
	var local_mouse: Vector2 = get_local_mouse_position()
	var nx: float = 0.0
	if Rect2(Vector2.ZERO, size).has_point(local_mouse):
		nx = clamp((local_mouse.x / max(size.x, 1.0) - 0.5) * 2.0, -1.0, 1.0)
	rotation = lerpf(rotation, 0.02 * nx * hover_weight, clamp(delta * 10.0, 0.0, 1.0))
	scale = scale.lerp(Vector2.ONE * (1.0 + 0.02 * (0.5 + 0.5 * bob) + 0.04 * hover_weight), clamp(delta * 10.0, 0.0, 1.0))

	var pulse: float = 0.82 + 0.18 * (0.5 + 0.5 * sin(idle_time * 2.0))
	if panel_style_runtime:
		panel_style_runtime.border_color = _rarity_color(card_quality).lerp(Color.WHITE, 0.12 * pulse + 0.10 * hover_weight)
	if icon_glow:
		icon_glow.modulate.a = 0.14 + 0.20 * (0.5 + 0.5 * sin(idle_time * 2.1)) + 0.16 * hover_weight

func _on_resized() -> void:
	pivot_offset = size * 0.5

func play_intro_anim(delay: float = 0.0) -> void:
	modulate.a = 0.0
	scale = Vector2(0.92, 0.92)
	var tween: Tween = create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.24)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.20)

## 刷新本地化文本（静态UI）
func _apply_localized_text() -> void:
	if buy_button:
		buy_button.text = _loc("Buy", "购买")
	if sold_label:
		sold_label.text = _loc("Sold", "已售罄")

##############################################################################
# 对外接口
##############################################################################

## 设置商品内容
## 参数：
##   index - 商品槽位索引
##   offer - 商品数据字典
## 设置商品内容
##
## 参数：
##   index - 商品槽位索引
##   offer - 商品数据字典
## 返回：无
func setup(index: int, offer: Dictionary) -> void:
	## 填充商品卡片
	offer_index = index
	offer_data = offer
	hover_target = 0.0
	hover_weight = 0.0

	var item_type: String = offer.get("type", "")
	if item_type == "weapon":
		_setup_weapon(offer)
	elif item_type == "card":
		_setup_card(offer)
	else:
		name_label.text = "未知商品"
		rarity_label.text = ""
		effect_label.text = ""

	_set_price_text(int(offer.get("price", 0)))
	_set_sold(false)

## 仅刷新价格显示（不重置售罄状态/动效）
func update_price(price: int) -> void:
	offer_data["price"] = price
	_set_price_text(price)

## 设置售罄状态
## 设置售罄状态（对外接口）
##
## 参数：
##   is_sold - 是否已购买
## 返回：无
func set_sold(is_sold: bool) -> void:
	_set_sold(is_sold)

##############################################################################
# 内部：UI填充
##############################################################################

## 填充武器卡片UI
##
## 参数：
##   offer - 商品数据字典
## 返回：无
func _setup_weapon(offer: Dictionary) -> void:
	## 武器卡片渲染
	var weapon_data: Dictionary = offer.get("data", {})
	name_label.text = weapon_data.get("display_name", weapon_data.get("name_cn", "武器"))
	card_quality = offer.get("quality", "white")
	rarity_label.text = _loc("Quality", "品质") + ": " + _quality_to_label(card_quality)
	rarity_label.add_theme_color_override("font_color", _rarity_color(card_quality))
	_set_effect_text(_weapon_brief_lines(weapon_data, offer.get("attributes", [])))
	_load_icon(_get_weapon_icon_path(weapon_data.get("icon_id", "")))
	_apply_quality_theme()

## 填充卡牌卡片UI
##
## 参数：
##   offer - 商品数据字典
## 返回：无
func _setup_card(offer: Dictionary) -> void:
	## 卡牌卡片渲染
	var card_data: Dictionary = offer.get("data", {})
	name_label.text = card_data.get("name", "商店卡")
	card_quality = card_data.get("rarity", "white")
	rarity_label.text = _loc("Rarity", "稀有度") + ": " + _quality_to_label(card_quality)
	rarity_label.add_theme_color_override("font_color", _rarity_color(card_quality))
	_set_effect_text(_format_card_effects(card_data.get("effects", [])))
	_load_icon(_get_card_icon_path(card_data.get("id", "")))
	_apply_quality_theme()

## 内部设置售罄状态
##
## 参数：
##   is_sold - 是否已购买
## 返回：无
func _set_sold(is_sold: bool) -> void:
	## 更新售罄样式
	sold_state = is_sold
	sold_label.visible = is_sold
	buy_button.disabled = is_sold
	hover_target = 0.0
	self.modulate = Color(1.0, 1.0, 1.0, 0.55) if is_sold else Color(1.0, 1.0, 1.0, 1.0)

func _set_price_text(price: int) -> void:
	if not price_label:
		return
	price_label.text = _loc("Price", "价格") + ": " + str(price)

##############################################################################
# 内部：按钮回调
##############################################################################

## 点击购买按钮回调
##
## 参数：无
## 返回：无
func _on_buy_pressed() -> void:
	## 购买按钮回调
	if offer_index < 0:
		return
	buy_pressed.emit(offer_index)

func _on_mouse_entered() -> void:
	if sold_state:
		return
	hover_target = 1.0
	auto_sheen_timer = randf_range(2.2, 3.6)
	_play_sheen()

func _on_mouse_exited() -> void:
	hover_target = 0.0

func _ensure_icon_glow() -> void:
	if icon_glow:
		return
	icon_glow = TextureRect.new()
	icon_glow.name = "IconGlow"
	icon_glow.texture = _make_icon_glow_texture()
	icon_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_glow.anchors_preset = PRESET_FULL_RECT
	icon_glow.offset_left = -10.0
	icon_glow.offset_top = -10.0
	icon_glow.offset_right = 10.0
	icon_glow.offset_bottom = 10.0
	icon_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_glow.stretch_mode = TextureRect.STRETCH_SCALE
	icon_glow.modulate = Color(0.94, 0.90, 0.80, 0.22)
	icon.add_child(icon_glow)
	icon.move_child(icon_glow, 0)

func _ensure_sheen_overlay() -> void:
	if sheen_overlay:
		return
	sheen_overlay = TextureRect.new()
	sheen_overlay.name = "SheenOverlay"
	sheen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen_overlay.texture = _make_sheen_texture()
	sheen_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheen_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	sheen_overlay.anchors_preset = PRESET_FULL_RECT
	sheen_overlay.offset_left = -24.0
	sheen_overlay.offset_right = -8.0
	sheen_overlay.offset_top = 0.0
	sheen_overlay.offset_bottom = 0.0
	sheen_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	sheen_overlay.rotation_degrees = 14.0
	add_child(sheen_overlay)
	move_child(sheen_overlay, 0)

func _play_sheen() -> void:
	if not sheen_overlay:
		return
	if sheen_tween:
		sheen_tween.kill()
	sheen_overlay.offset_left = -220.0
	sheen_overlay.offset_right = -180.0
	sheen_overlay.modulate.a = 0.0
	sheen_tween = create_tween()
	sheen_tween.set_trans(Tween.TRANS_QUAD)
	sheen_tween.set_ease(Tween.EASE_OUT)
	sheen_tween.tween_property(sheen_overlay, "modulate:a", 0.35, 0.08)
	sheen_tween.parallel().tween_property(sheen_overlay, "offset_left", 230.0, 0.30)
	sheen_tween.parallel().tween_property(sheen_overlay, "offset_right", 270.0, 0.30)
	sheen_tween.tween_property(sheen_overlay, "modulate:a", 0.0, 0.12)

func _make_sheen_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.5, 0.65, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.95),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 96
	tex.height = 640
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex

func _make_icon_glow_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.34),
		Color(1.0, 1.0, 1.0, 0.14),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex

##############################################################################
# 内部：显示辅助
##############################################################################

## 生成武器简要信息
##
## 参数：
##   weapon_data - 武器数据
## 返回：简要文字
## 生成武器简要信息（行数组）
func _weapon_brief_lines(weapon_data: Dictionary, attributes: Array) -> Array[String]:
	var lines: Array[String] = []
	lines.append("· 基础伤害 " + str(int(weapon_data.get("base_damage", 0))))
	lines.append("· 冷却 " + str(weapon_data.get("base_cooldown", 0)))
	lines.append("· 范围 " + str(weapon_data.get("base_range", 0)))
	if attributes.size() > 0:
		for attr: Dictionary in attributes:
			var attr_type: String = attr.get("type", "")
			var value: float = attr.get("value", 0.0)
			if attr_type.is_empty():
				continue
			var label: String = _weapon_attr_label(attr_type)
			var sign: String = "+" if value >= 0 else ""
			lines.append("· " + label + " " + sign + str(value))
	return lines

## 武器词条中文映射
##
## 参数：
##   attr_type - 词条key
## 返回：显示名称
## 武器词条中文映射
func _weapon_attr_label(attr_type: String) -> String:
	var map: Dictionary = {
		"damage": "Damage",
		"crit_rate": "CritRate",
		"crit_dmg": "CritDamage",
		"cdr": "Cooldown",
		"all_dmg": "AllDamage",
		"melee_dmg": "MeleeDamage",
		"ranged_dmg": "RangedDamage",
		"element_dmg": "ElementalDamage",
		"summon_dmg": "SummonDamage"
	}
	var key: String = map.get(attr_type, attr_type)
	return _localize_stat(key)

## 格式化卡牌效果文本
##
## 参数：
##   effects - 效果数组
## 返回：多行文本
## 格式化卡牌效果（行数组）
func _format_card_effects(effects: Array) -> Array[String]:
	var lines: Array[String] = []
	for effect in effects:
		var stat: String = effect.get("stat", "")
		var value: float = effect.get("value", 0.0)
		if stat.is_empty():
			continue
		var label: String = _stat_label(stat)
		var sign: String = "+" if value >= 0 else ""
		lines.append("· " + label + " " + sign + str(value))
	if lines.is_empty():
		lines.append("· 无效果")
	return lines

## 将多行效果拆成左右两列显示
func _set_effect_text(lines: Array[String]) -> void:
	if not effect_label:
		return
	if lines.is_empty():
		effect_label.text = ""
		return
	## 单列展示，避免分栏导致视觉混乱
	effect_label.text = "\n".join(lines)

## 属性字段映射为中文
##
## 参数：
##   stat - 属性key
## 返回：显示名称
## 属性字段映射为中文
func _stat_label(stat: String) -> String:
	var map: Dictionary = {
		"summon_count": "SummonCount",
		"summon_cdr_inherit": "SummonCooldownInherit",
		"summon_crit_inherit": "SummonCritInherit"
	}
	var key: String = map.get(stat, stat)
	return _localize_stat(key)

## 统一走本地化（缺失时回退为key）
func _localize_stat(key: String) -> String:
	if Localization:
		var text: String = Localization.tr_text(key)
		return text if not text.is_empty() else key
	return key

## 本地化读取（缺失时回退fallback）
func _loc(key: String, fallback: String) -> String:
	if Localization:
		var text: String = Localization.tr_text(key)
		if not text.is_empty() and text != key:
			return text
	return fallback

## 品质转中文标签
##
## 参数：
##   quality - 品质字符串
## 返回：中文标签
func _quality_to_label(quality: String) -> String:
	match quality:
		"white":
			return "白"
		"blue":
			return "蓝"
		"purple":
			return "紫"
		"gold":
			return "金"
		_:
			return "白"

## 品质颜色
##
## 参数：
##   quality - 品质字符串
## 返回：颜色值
func _rarity_color(quality: String) -> Color:
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
# 内部：图标加载
##############################################################################

## 获取武器图标路径
##
## 参数：
##   icon_id - 图标ID
## 返回：路径字符串
func _get_weapon_icon_path(icon_id: String) -> String:
	if icon_id.is_empty():
		return ""
	return "res://assets/PIC/wuqi/icon/256/" + icon_id + ".png"

## 获取卡牌图标路径
##
## 参数：
##   card_id - 卡牌ID
## 返回：路径字符串
func _get_card_icon_path(card_id: String) -> String:
	if card_id.is_empty():
		return ""
	return "res://assets/PIC/shop/256/" + card_id + ".png"

## 加载图标
##
## 参数：
##   path - 纹理路径
## 返回：无
func _load_icon(path: String) -> void:
	if path.is_empty():
		_set_placeholder_icon()
		return
	if ResourceLoader.exists(path):
		icon.texture = load(path)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_set_placeholder_icon()

## 生成占位图标
##
## 参数：无
## 返回：无
func _set_placeholder_icon() -> void:
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.2, 1.0))
	icon.texture = ImageTexture.create_from_image(img)

func _apply_quality_theme() -> void:
	if not panel_style_runtime:
		return
	var rarity_color: Color = _rarity_color(card_quality)
	var tint_bg: Color = CARD_BG_BASE.lerp(rarity_color, 0.10)
	panel_style_runtime.bg_color = tint_bg
	panel_style_runtime.border_color = CARD_BORDER_BASE.lerp(rarity_color, 0.52).lerp(Color.WHITE, 0.10)
	if icon_glow:
		icon_glow.modulate = rarity_color.lerp(Color.WHITE, 0.22)
		icon_glow.modulate.a = 0.22

func _apply_visual_theme() -> void:
	panel_style_runtime = StyleBoxFlat.new()
	panel_style_runtime.bg_color = CARD_BG_DARK
	panel_style_runtime.border_color = CARD_BORDER_BASE
	panel_style_runtime.set_border_width_all(1)
	panel_style_runtime.corner_radius_top_left = 10
	panel_style_runtime.corner_radius_top_right = 10
	panel_style_runtime.corner_radius_bottom_left = 10
	panel_style_runtime.corner_radius_bottom_right = 10
	panel_style_runtime.shadow_size = 14
	panel_style_runtime.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	panel_style_runtime.shadow_offset = Vector2(0, 6)
	add_theme_stylebox_override("panel", panel_style_runtime)
	_apply_quality_theme()

	var button_style: StyleBoxFlat = StyleBoxFlat.new()
	button_style.bg_color = CARD_BUTTON_BG
	button_style.border_color = CARD_ACCENT
	button_style.set_border_width_all(1)
	button_style.corner_radius_top_left = 6
	button_style.corner_radius_top_right = 6
	button_style.corner_radius_bottom_left = 6
	button_style.corner_radius_bottom_right = 6
	var button_hover: StyleBoxFlat = button_style.duplicate()
	button_hover.bg_color = CARD_BUTTON_BG_HOVER
	var button_pressed: StyleBoxFlat = button_style.duplicate()
	button_pressed.bg_color = CARD_BUTTON_BG_PRESSED
	var button_disabled: StyleBoxFlat = button_style.duplicate()
	button_disabled.bg_color = CARD_BUTTON_BG_DISABLED
	button_disabled.border_color = CARD_BORDER_BASE.darkened(0.24)
	buy_button.add_theme_stylebox_override("normal", button_style)
	buy_button.add_theme_stylebox_override("hover", button_hover)
	buy_button.add_theme_stylebox_override("pressed", button_pressed)
	buy_button.add_theme_stylebox_override("disabled", button_disabled)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	effect_label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98))
	price_label.add_theme_color_override("font_color", Color(0.98, 0.90, 0.68))
	price_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.86))
	price_label.add_theme_constant_override("outline_size", 2)

	if sold_label:
		sold_label.modulate = Color(1.0, 0.84, 0.52, 1.0)
		sold_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
		sold_label.add_theme_constant_override("outline_size", 3)
