##############################################################################
# ShopManager - 商店系统管理器（Autoload）
#
# 设计目的：
# - 生成商店商品（武器/商店卡）
# - 控制刷新成本、权重与时间阶段
# - 维护商店卡购买次数（上限）
# - 提供购买校验与价格计算
##############################################################################
extends Node

##############################################################################
# 常量：商店基础配置
##############################################################################

## 商店商品槽数量
## 单位：个
## 作用：控制商店界面展示的商品数量
## 调整范围：4-8
## 当前值：6
const SHOP_SLOT_COUNT: int = 6

## 商店刷新基础价格
## 单位：金币
## 作用：刷新商店的基础成本
## 调整范围：5-20
## 当前值：10
const REFRESH_BASE_PRICE: int = 10

## 商店刷新递增价格
## 单位：金币
## 作用：每次刷新增加的价格
## 调整范围：3-10
## 当前值：5
const REFRESH_PRICE_STEP: int = 5

## 每5分钟为一个刷新权重阶段（300秒）
## 单位：秒
## 作用：控制权重切换时间
## 调整范围：180-600
## 当前值：300
const WEIGHT_STAGE_SECONDS: float = 300.0

##############################################################################
# 常量：武器品质与卡牌稀有度
##############################################################################

## 武器品质列表（商店仅到紫色）
const WEAPON_QUALITIES: Array[String] = ["white", "blue", "purple"]

## 卡牌稀有度列表（可包含金色）
const CARD_RARITIES: Array[String] = ["white", "blue", "purple", "gold"]

## 卡牌稀有度权重（每5分钟一档）
## 说明：高品质卡出现几率略增
## 数值越大越常见
const CARD_RARITY_WEIGHTS_BY_STAGE: Array[Dictionary] = [
	{"white": 70.0, "blue": 25.0, "purple": 5.0, "gold": 0.0},   # 0-5min
	{"white": 55.0, "blue": 30.0, "purple": 15.0, "gold": 0.0},  # 5-10min
	{"white": 45.0, "blue": 35.0, "purple": 20.0, "gold": 0.0},  # 10-15min
	{"white": 35.0, "blue": 40.0, "purple": 24.0, "gold": 1.0}   # 15-20min
]

## 武器品质权重（每5分钟一档）
## 说明：随时间略提升蓝/紫概率，但不出现金色
const WEAPON_QUALITY_WEIGHTS_BY_STAGE: Array[Dictionary] = [
	{"white": 70.0, "blue": 25.0, "purple": 5.0},
	{"white": 55.0, "blue": 30.0, "purple": 15.0},
	{"white": 45.0, "blue": 35.0, "purple": 20.0},
	{"white": 35.0, "blue": 40.0, "purple": 25.0}
]

##############################################################################
# 运行期状态
##############################################################################

## 商店刷新次数
var refresh_count: int = 0

## 商店卡购买次数记录
## key=CardID, value=已购买次数
var card_purchase_counts: Dictionary = {}

## RNG
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

##############################################################################
# 生命周期
##############################################################################

## 初始化随机数
##
## 参数：无
## 返回：无
func _ready() -> void:
	rng.randomize()

##############################################################################
# 对外接口：商店商品生成
##############################################################################

## 生成一轮商店商品
## 返回：Array[Dictionary]，每个元素包含type/price/data等字段
## 生成商店商品列表
##
## 参数：无
## 返回：
##   商品数组（Dictionary）
func generate_shop_offers() -> Array:
	var offers: Array = []
	var weapon_ratio: float = _get_weapon_offer_ratio()

	for i in range(SHOP_SLOT_COUNT):
		if rng.randf() < weapon_ratio:
			offers.append(_generate_weapon_offer())
		else:
			offers.append(_generate_card_offer())

	return offers

## 重置刷新次数（用于新一轮商店/新局）
## 重置刷新次数
##
## 参数：无
## 返回：无
func reset_refresh_count() -> void:
	refresh_count = 0

## 获取刷新价格
## 获取当前刷新价格
##
## 参数：无
## 返回：刷新价格（金币）
func get_refresh_price() -> int:
	var base_price: int = REFRESH_BASE_PRICE + refresh_count * REFRESH_PRICE_STEP
	return base_price

## 增加刷新计数
## 增加刷新次数
##
## 参数：无
## 返回：无
func increase_refresh_count() -> void:
	refresh_count += 1

##############################################################################
# 对外接口：卡牌购买限制
##############################################################################

## 判断卡牌是否可购买（受Cap限制）
## 校验卡牌是否可购买（Cap限制）
##
## 参数：
##   card_id - 卡牌ID
## 返回：
##   true/false
func can_purchase_card(card_id: String) -> bool:
	var card: Dictionary = GameData.get_shop_card(card_id)
	if card.is_empty():
		return false
	var cap: int = int(card.get("cap", 0))
	if cap <= 0:
		return true
	var current_count: int = int(card_purchase_counts.get(card_id, 0))
	return current_count < cap

## 记录卡牌购买
## 记录卡牌购买次数
##
## 参数：
##   card_id - 卡牌ID
## 返回：无
func register_card_purchase(card_id: String) -> void:
	if not card_purchase_counts.has(card_id):
		card_purchase_counts[card_id] = 0
	card_purchase_counts[card_id] += 1

##############################################################################
# 生成武器商品
##############################################################################

## 生成武器商品
##
## 参数：无
## 返回：商品数据字典
func _generate_weapon_offer() -> Dictionary:
	var quality: String = _pick_weapon_quality()
	var weapon_id: String = _pick_weapon_id_by_quality(quality)
	var weapon_data: Dictionary = GameData.get_weapon(weapon_id)
	if not _weapon_quality_allows(weapon_data, quality):
		quality = _get_min_quality_for_weapon(weapon_data)
	if _quality_order_index(quality) > _quality_order_index("purple"):
		quality = "purple"

	var price: int = _get_weapon_price_by_quality(weapon_data, quality)
	price = _apply_price_modifier(price)
	var attributes: Array = _generate_weapon_attributes(quality)

	return {
		"type": "weapon",
		"weapon_id": weapon_id,
		"quality": quality,
		"attributes": attributes,
		"price": price,
		"data": weapon_data
	}

## 按品质筛选武器ID
##
## 参数：
##   quality - 目标品质
## 返回：武器ID
func _pick_weapon_id_by_quality(quality: String) -> String:
	var candidates: Array[String] = []
	for weapon_id: String in GameData.get_all_weapon_ids():
		var weapon_data: Dictionary = GameData.get_weapon(weapon_id)
		if _weapon_quality_allows(weapon_data, quality):
			candidates.append(weapon_id)

	if candidates.is_empty():
		var fallback: Array[String] = []
		for weapon_id: String in GameData.get_all_weapon_ids():
			var weapon_data: Dictionary = GameData.get_weapon(weapon_id)
			var min_quality: String = _get_min_quality_for_weapon(weapon_data)
			if _quality_order_index(min_quality) <= _quality_order_index("purple"):
				fallback.append(weapon_id)
		if fallback.is_empty():
			return GameData.get_all_weapon_ids().pick_random()
		return fallback[rng.randi_range(0, fallback.size() - 1)]

	return candidates[rng.randi_range(0, candidates.size() - 1)]

## 抽取武器品质
##
## 参数：无
## 返回：品质字符串
func _pick_weapon_quality() -> String:
	var weights: Dictionary = _get_weapon_quality_weights()
	return _pick_weighted_key(weights, "white")

## 获取当前阶段武器品质权重
##
## 参数：无
## 返回：权重字典
func _get_weapon_quality_weights() -> Dictionary:
	var stage: int = _get_weight_stage_index()
	return WEAPON_QUALITY_WEIGHTS_BY_STAGE[min(stage, WEAPON_QUALITY_WEIGHTS_BY_STAGE.size() - 1)]

## 判断武器是否可在指定品质出现
##
## 参数：
##   weapon_data - 武器数据
##   quality - 品质
## 返回：true/false
func _weapon_quality_allows(weapon_data: Dictionary, quality: String) -> bool:
	var min_quality: String = _get_min_quality_for_weapon(weapon_data)
	return _quality_order_index(quality) >= _quality_order_index(min_quality)

## 获取武器最低可出现品质
##
## 参数：
##   weapon_data - 武器数据
## 返回：品质字符串
func _get_min_quality_for_weapon(weapon_data: Dictionary) -> String:
	var start_tag: String = String(weapon_data.get("rarity_start", "W"))
	return _convert_weapon_rarity_tag(start_tag)

## 按品质获取武器价格
##
## 参数：
##   weapon_data - 武器数据
##   quality - 品质
## 返回：价格（金币）
func _get_weapon_price_by_quality(weapon_data: Dictionary, quality: String) -> int:
	match quality:
		"white":
			return int(weapon_data.get("price_w_coin", 0))
		"blue":
			return int(weapon_data.get("price_b_coin", 0))
		"purple":
			return int(weapon_data.get("price_p_coin", 0))
		_:
			return int(weapon_data.get("price_w_coin", 0))

##############################################################################
# 武器属性生成（商店用）
##############################################################################

## 按品质生成属性数量
##
## 参数：
##   quality - 品质字符串
## 返回：属性数组
func _generate_weapon_attributes(quality: String) -> Array:
	var count: int = _get_quality_attribute_count(quality)
	var attrs: Array = []
	for i in range(count):
		if ForgeManager:
			attrs.append(ForgeManager.generate_random_attribute())
		else:
			attrs.append({"type": "damage", "value": 5.0, "locked": false})
	return attrs

## 品质对应属性数量
##
## 参数：
##   quality - 品质字符串
## 返回：数量
func _get_quality_attribute_count(quality: String) -> int:
	match quality:
		"blue":
			return 1
		"purple":
			return 3
		_:
			return 0

##############################################################################
# 生成卡牌商品
##############################################################################

## 生成卡牌商品
##
## 参数：无
## 返回：商品数据字典
func _generate_card_offer() -> Dictionary:
	var card: Dictionary = _pick_shop_card_by_rarity()
	if card.is_empty():
		return _generate_weapon_offer()
	var price: int = int(card.get("price", 0))
	price = _apply_price_modifier(price)

	return {
		"type": "card",
		"card_id": card.get("id", ""),
		"price": price,
		"rarity": card.get("rarity", "white"),
		"data": card
	}

## 按稀有度抽取卡牌
##
## 参数：无
## 返回：卡牌数据字典
func _pick_shop_card_by_rarity() -> Dictionary:
	var weights: Dictionary = _get_card_rarity_weights()
	var target_rarity: String = _pick_weighted_key(weights, "white")

	var candidates: Array[Dictionary] = []
	for card_id: String in GameData.shop_cards.keys():
		var card: Dictionary = GameData.shop_cards[card_id]
		if card.get("rarity", "") != target_rarity:
			continue
		if not can_purchase_card(card_id):
			continue
		candidates.append(card)

	if candidates.is_empty():
		# 兜底：任意可购买卡
		for card_id: String in GameData.shop_cards.keys():
			if can_purchase_card(card_id):
				candidates.append(GameData.shop_cards[card_id])

	if candidates.is_empty():
		return {}

	return candidates[rng.randi_range(0, candidates.size() - 1)]

## 获取当前阶段卡牌稀有度权重
##
## 参数：无
## 返回：权重字典
func _get_card_rarity_weights() -> Dictionary:
	var stage: int = _get_weight_stage_index()
	return CARD_RARITY_WEIGHTS_BY_STAGE[min(stage, CARD_RARITY_WEIGHTS_BY_STAGE.size() - 1)]

##############################################################################
# 时间阶段与权重工具
##############################################################################

## 获取权重阶段索引
##
## 参数：无
## 返回：阶段索引
func _get_weight_stage_index() -> int:
	var time_sec: float = GameManager.current_time
	return int(time_sec / WEIGHT_STAGE_SECONDS)

## 获取武器商品占比
##
## 参数：无
## 返回：0-1比例
func _get_weapon_offer_ratio() -> float:
	# 0-5分钟：武器 30%，卡牌 70%
	# 5分钟后：武器 15%，卡牌 85%
	return 0.3 if GameManager.current_time < 300.0 else 0.15

##############################################################################
# 价格与权重辅助
##############################################################################

## 应用价格加成（ItemPrice）
##
## 参数：
##   base_price - 基础价格
## 返回：修正后价格
func _apply_price_modifier(base_price: int) -> int:
	var player: CharacterBody2D = _get_player()
	if not player:
		return base_price
	var item_price_pct: float = player.get_final_stat("ItemPrice")
	var price_mult: float = 1.0 + item_price_pct / 100.0
	var price: int = int(round(base_price * price_mult))
	return max(price, 1)

## 按权重抽取键
##
## 参数：
##   weights - 权重字典
##   fallback - 兜底值
## 返回：被选中的key
func _pick_weighted_key(weights: Dictionary, fallback: String) -> String:
	var total: float = 0.0
	for key in weights.keys():
		total += float(weights[key])
	if total <= 0.0:
		return fallback

	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for key in weights.keys():
		acc += float(weights[key])
		if roll <= acc:
			return String(key)
	return fallback

## 品质排序索引
##
## 参数：
##   quality - 品质字符串
## 返回：排序索引
func _quality_order_index(quality: String) -> int:
	match quality:
		"white":
			return 0
		"blue":
			return 1
		"purple":
			return 2
		"gold":
			return 3
		_:
			return 0

## 解析武器品质标记
##
## 参数：
##   tag - CSV中的品质标记
## 返回：品质字符串
func _convert_weapon_rarity_tag(tag: String) -> String:
	match tag:
		"W":
			return "white"
		"B":
			return "blue"
		"P":
			return "purple"
		"G":
			return "gold"
		_:
			return "white"

## 获取玩家引用
##
## 参数：无
## 返回：玩家节点或null
func _get_player() -> CharacterBody2D:
	if GameManager and GameManager.player:
		return GameManager.player
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null
