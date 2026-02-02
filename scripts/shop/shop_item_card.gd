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
	## 效果列表单列展示，避免分栏挤压导致逐字换行
	if effect_label:
		effect_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_localized_text()

## 刷新本地化文本（静态UI）
func _apply_localized_text() -> void:
	if buy_button:
		buy_button.text = _loc("Buy", "Buy")
	if sold_label:
		sold_label.text = _loc("Sold", "Sold")

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

	var item_type: String = offer.get("type", "")
	if item_type == "weapon":
		_setup_weapon(offer)
	elif item_type == "card":
		_setup_card(offer)
	else:
		name_label.text = "未知商品"
		rarity_label.text = ""
		effect_label.text = ""

	price_label.text = _loc("Price", "Price") + ": " + str(offer.get("price", 0))
	_set_sold(false)

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
	var quality: String = offer.get("quality", "white")
	rarity_label.text = _loc("Quality", "Quality") + ": " + _quality_to_label(quality)
	rarity_label.add_theme_color_override("font_color", _rarity_color(quality))
	_set_effect_text(_weapon_brief_lines(weapon_data, offer.get("attributes", [])))
	_load_icon(_get_weapon_icon_path(weapon_data.get("icon_id", "")))

## 填充卡牌卡片UI
##
## 参数：
##   offer - 商品数据字典
## 返回：无
func _setup_card(offer: Dictionary) -> void:
	## 卡牌卡片渲染
	var card_data: Dictionary = offer.get("data", {})
	name_label.text = card_data.get("name", "商店卡")
	var rarity: String = card_data.get("rarity", "white")
	rarity_label.text = _loc("Rarity", "Rarity") + ": " + _quality_to_label(rarity)
	rarity_label.add_theme_color_override("font_color", _rarity_color(rarity))
	_set_effect_text(_format_card_effects(card_data.get("effects", [])))
	_load_icon(_get_card_icon_path(card_data.get("id", "")))

## 内部设置售罄状态
##
## 参数：
##   is_sold - 是否已购买
## 返回：无
func _set_sold(is_sold: bool) -> void:
	## 更新售罄样式
	sold_label.visible = is_sold
	buy_button.disabled = is_sold
	self.modulate = Color(1, 1, 1, 0.6) if is_sold else Color(1, 1, 1, 1)

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
