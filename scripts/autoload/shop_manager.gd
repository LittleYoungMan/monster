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
## 当前值：4
const SHOP_SLOT_COUNT: int = 4

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

## 商店刷新时间阶梯（秒）
## 作用：随时间增加刷新成本
const REFRESH_TIME_STEP_SECONDS: float = 180.0
const REFRESH_TIME_STEP_PRICE: int = 5
const REFRESH_TIME_STEP_MAX: int = 30

## P1.1 经济曲线：商店价格阶段倍率（前期折扣，后期回收）
## key=起始分钟
const PRICE_STAGE_MULT: Dictionary = {
	0: 0.82,
	5: 0.93,
	10: 1.08,
	15: 1.12
}

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
	{"white": 72.0, "blue": 24.0, "purple": 4.0, "gold": 0.0},   # 0-5min
	{"white": 55.0, "blue": 30.0, "purple": 15.0, "gold": 0.0},  # 5-10min
	{"white": 40.0, "blue": 34.0, "purple": 24.0, "gold": 2.0},  # 10-15min
	{"white": 28.0, "blue": 35.0, "purple": 30.0, "gold": 7.0}   # 15-20min
]

## 武器品质权重（每5分钟一档）
## 说明：随时间略提升蓝/紫概率，但不出现金色
const WEAPON_QUALITY_WEIGHTS_BY_STAGE: Array[Dictionary] = [
	{"white": 74.0, "blue": 22.0, "purple": 4.0},
	{"white": 58.0, "blue": 29.0, "purple": 13.0},
	{"white": 45.0, "blue": 34.0, "purple": 21.0},
	{"white": 31.0, "blue": 41.0, "purple": 28.0}
]

## 15分钟后开始强制给1个“补短板”卡位
const PATCH_CARD_STAGE_MINUTE: int = 15

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
	var minute: int = int(GameManager.current_time / 60.0)
	var patch_slot: int = -1
	if minute >= PATCH_CARD_STAGE_MINUTE:
		patch_slot = rng.randi_range(0, SHOP_SLOT_COUNT - 1)

	for i in range(SHOP_SLOT_COUNT):
		if i == patch_slot:
			offers.append(_generate_patch_card_offer())
			continue
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

## 重置整局商店状态（新开局调用）
func reset_run_state() -> void:
	refresh_count = 0
	card_purchase_counts.clear()

## 获取刷新价格
## 获取当前刷新价格
##
## 参数：无
## 返回：刷新价格（金币）
func get_refresh_price() -> int:
	var time_mult: int = _get_refresh_time_mult()
	var base_price: int = REFRESH_BASE_PRICE + refresh_count * REFRESH_PRICE_STEP + time_mult
	return _apply_price_modifier(base_price)

## 增加刷新计数
## 增加刷新次数
##
## 参数：无
## 返回：无
func increase_refresh_count() -> void:
	refresh_count += 1

## 计算已有商品条目的当前价格（用于购买后动态重算）
##
## 参数：
##   offer - 商店条目字典
## 返回：
##   当前应显示/应扣除的价格
func get_offer_price(offer: Dictionary) -> int:
	var item_type: String = String(offer.get("type", ""))
	if item_type == "weapon":
		var quality: String = String(offer.get("quality", "white"))
		var weapon_data: Dictionary = offer.get("data", {})
		if weapon_data.is_empty():
			var weapon_id: String = String(offer.get("weapon_id", ""))
			weapon_data = GameData.get_weapon(weapon_id)
		if weapon_data.is_empty():
			return max(int(offer.get("price", 1)), 1)
		var base_price: int = _get_weapon_price_by_quality(weapon_data, quality)
		return _apply_price_modifier(base_price)

	if item_type == "card":
		var card_data: Dictionary = offer.get("data", {})
		if card_data.is_empty():
			var card_id: String = String(offer.get("card_id", ""))
			card_data = GameData.get_shop_card(card_id)
		if card_data.is_empty():
			return max(int(offer.get("price", 1)), 1)
		var base_price: int = int(card_data.get("price", 0))
		return _apply_price_modifier(base_price)

	return max(int(offer.get("price", 1)), 1)

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

## 15分钟后的补短板卡位
func _generate_patch_card_offer() -> Dictionary:
	var card: Dictionary = _pick_shop_card_for_patch()
	if card.is_empty():
		return _generate_card_offer()
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
	var candidates: Array[Dictionary] = _collect_card_candidates(target_rarity)
	if candidates.is_empty():
		candidates = _collect_card_candidates("")
	if candidates.is_empty():
		return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)]

## 15分钟后：根据角色短板筛卡
func _pick_shop_card_for_patch() -> Dictionary:
	var weights: Dictionary = _get_card_rarity_weights()
	var target_rarity: String = _pick_weighted_key(weights, "white")
	var candidates: Array[Dictionary] = _collect_card_candidates(target_rarity)
	if candidates.is_empty():
		candidates = _collect_card_candidates("")
	if candidates.is_empty():
		return {}

	var patch_need: Dictionary = _evaluate_patch_need()
	var best_card: Dictionary = {}
	var best_score: float = -999999.0
	for card: Dictionary in candidates:
		var score: float = _score_card_for_patch(card, patch_need)
		if score > best_score:
			best_score = score
			best_card = card
	if best_card.is_empty():
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	return best_card

func _collect_card_candidates(target_rarity: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for card_id: String in GameData.shop_cards.keys():
		var card: Dictionary = GameData.shop_cards[card_id]
		if not target_rarity.is_empty() and card.get("rarity", "") != target_rarity:
			continue
		if not can_purchase_card(card_id):
			continue
		candidates.append(card)
	return candidates

func _evaluate_patch_need() -> Dictionary:
	var need: Dictionary = {
		"damage": 1.0,
		"survival": 1.0
	}
	var player: CharacterBody2D = _get_player()
	if not player or not player.has_method("get_final_stat"):
		return need

	var health: float = float(player.get_final_stat("Health"))
	var armor: float = float(player.get_final_stat("Armor"))
	var dodge: float = float(player.get_final_stat("Dodge"))
	var regen: float = float(player.get_final_stat("HealthRegen"))
	var lifesteal: float = float(player.get_final_stat("Lifesteal"))
	var melee: float = float(player.get_final_stat("MeleeDamage"))
	var ranged: float = float(player.get_final_stat("RangedDamage"))
	var elemental: float = float(player.get_final_stat("ElementalDamage"))
	var summon: float = float(player.get_final_stat("SummonDamage"))
	var all_dmg: float = float(player.get_final_stat("AllDamage"))
	var crit_rate: float = float(player.get_final_stat("CritRate"))

	var offense_score: float = max(melee, max(ranged, max(elemental, summon))) + all_dmg * 0.8 + crit_rate * 0.3
	var survival_score: float = health * 0.28 + armor * 2.4 + dodge * 1.8 + regen * 4.0 + lifesteal * 4.5

	if offense_score < 58.0:
		need["damage"] = 1.35
	elif offense_score < 82.0:
		need["damage"] = 1.15
	else:
		need["damage"] = 0.85

	if survival_score < 95.0:
		need["survival"] = 1.45
	elif survival_score < 140.0:
		need["survival"] = 1.20
	else:
		need["survival"] = 0.85

	if GameManager.current_time >= 900.0:
		need["survival"] = float(need["survival"]) + 0.15
	return need

func _score_card_for_patch(card: Dictionary, patch_need: Dictionary) -> float:
	var effects: Array = card.get("effects", [])
	var damage_score: float = 0.0
	var survival_score: float = 0.0
	var penalty: float = 0.0
	for effect: Dictionary in effects:
		var stat: String = String(effect.get("stat", ""))
		var value: float = float(effect.get("value", 0.0))
		if _is_damage_effect_stat(stat):
			if value >= 0.0:
				damage_score += value
			else:
				penalty += abs(value) * 0.60
		if _is_survival_effect_stat(stat):
			if value >= 0.0:
				survival_score += value
			else:
				penalty += abs(value) * 0.70
		match stat:
			"EnemyCount", "EnemyHealth", "EnemySpeed", "EnemyCritChance":
				if value > 0.0:
					penalty += value
				else:
					survival_score += abs(value) * 0.5
			"ItemPrice":
				if value < 0.0:
					survival_score += abs(value) * 0.5
				else:
					penalty += value * 0.2
			"MaterialRespawnCooldown":
				if value > 0.0:
					survival_score += value * 0.2
			"DoubleMaterialChance":
				if value > 0.0:
					survival_score += value * 0.2

	var rarity_bonus: float = 0.0
	match String(card.get("rarity", "white")):
		"blue":
			rarity_bonus = 2.0
		"purple":
			rarity_bonus = 5.0
		"gold":
			rarity_bonus = 9.0

	return damage_score * float(patch_need.get("damage", 1.0)) + survival_score * float(patch_need.get("survival", 1.0)) + rarity_bonus - penalty

func _is_damage_effect_stat(stat: String) -> bool:
	return stat in [
		"AllDamage",
		"MeleeDamage",
		"RangedDamage",
		"ElementalDamage",
		"SummonDamage",
		"CritRate",
		"CritDamage",
		"Cooldown",
		"BossDamage",
		"ExplosionDamage",
		"PenetrationDamage"
	]

func _is_survival_effect_stat(stat: String) -> bool:
	return stat in [
		"Health",
		"HealthRegen",
		"Armor",
		"Dodge",
		"Lifesteal",
		"MoveSpeed"
	]

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
	var time_sec: float = GameManager.current_time
	var player: CharacterBody2D = _get_player()
	if player:
		var equipped_weapons: int = _get_equipped_weapon_count(player)
		# 0-5分钟：优先凑6把武器，确保5分钟Boss是“输出坎”
		if time_sec < 300.0:
			if equipped_weapons <= 1:
				return 0.95
			if equipped_weapons <= 3:
				return 0.88
			if equipped_weapons <= 5:
				return 0.76
			return 0.52
		# 5-10分钟：继续补齐武器，但开始让位给卡牌构筑
		if time_sec < 600.0:
			if equipped_weapons <= 3:
				return 0.78
			if equipped_weapons <= 5:
				return 0.64
			return 0.40
		# 10分钟后：更多给卡牌/补短板
		if equipped_weapons <= 3:
			return 0.66
		if equipped_weapons <= 5:
			return 0.52
	return 0.36 if time_sec < 900.0 else 0.26

func _get_equipped_weapon_count(player: CharacterBody2D) -> int:
	var slots: Variant = player.get("weapon_slots")
	if typeof(slots) != TYPE_ARRAY:
		return 0
	var count: int = 0
	for item: Variant in slots:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var weapon_data: Dictionary = item
		if not weapon_data.is_empty():
			count += 1
	return count

## 获取刷新价格的时间附加项
func _get_refresh_time_mult() -> int:
	var time_sec: float = GameManager.current_time
	var stage: int = int(time_sec / REFRESH_TIME_STEP_SECONDS)
	return min(stage * REFRESH_TIME_STEP_PRICE, REFRESH_TIME_STEP_MAX)

## 获取商店价格阶段倍率
func _get_price_stage_mult() -> float:
	var minute: int = int(GameManager.current_time / 60.0)
	if minute >= 15:
		return float(PRICE_STAGE_MULT[15])
	if minute >= 10:
		return float(PRICE_STAGE_MULT[10])
	if minute >= 5:
		return float(PRICE_STAGE_MULT[5])
	return float(PRICE_STAGE_MULT[0])

##############################################################################
# 价格与权重辅助
##############################################################################

## 应用价格加成（ItemPrice）
##
## 参数：
##   base_price - 基础价格
## 返回：修正后价格
func _apply_price_modifier(base_price: int) -> int:
	var staged_price: int = int(round(float(base_price) * _get_price_stage_mult()))
	var player: CharacterBody2D = _get_player()
	if not player:
		return max(staged_price, 1)
	var item_price_pct: float = player.get_final_stat("ItemPrice")
	var price_mult: float = 1.0 + item_price_pct / 100.0
	var price: int = int(round(float(staged_price) * price_mult))
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
