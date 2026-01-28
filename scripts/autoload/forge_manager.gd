##############################################################################
# ForgeManager - 工坊管理器 (Autoload)
#
# 设计目的：
# - 武器升阶（white→blue→purple→gold）
# - 属性重铸（重新随机生成）
# - 属性锁定（防止重铸影响）
# - Boss击杀限制（每个Boss只能升阶1次）
#
# 调用链：
# - ForgeUI -> ForgeManager.upgrade_weapon()
# - ForgeUI -> ForgeManager.reroll_attribute()
# - ForgeUI -> ForgeManager.lock_attribute()
# - GameManager.boss_killed -> ForgeManager.on_boss_killed()
#
# 依赖：
# - GameManager（矿石消耗）
# - Player（武器槽数据）
##############################################################################
extends Node

##############################################################################
# 工坊常量
##############################################################################

## 升阶矿石费用
const UPGRADE_COSTS: Dictionary = {
	"white": 10,   # white→blue
	"blue": 30,    # blue→purple
	"purple": 100  # purple→gold
}

## 重铸费用
const REROLL_COST: int = 5

## 锁定费用
const LOCK_COST: int = 10

## 每个Boss限制的升阶次数
const UPGRADES_PER_BOSS: int = 1

## 品质升阶路径
const QUALITY_UPGRADE_PATH: Dictionary = {
	"white": "blue",
	"blue": "purple",
	"purple": "gold"
}

## 品质对应的属性槽数量
const QUALITY_ATTRIBUTE_SLOTS: Dictionary = {
	"white": 0,
	"blue": 1,
	"purple": 3,
	"gold": 4
}

##############################################################################
# 运行期状态
##############################################################################

## 本次Boss已升阶次数
var upgrades_this_boss: int = 0

## 工坊是否可用（Boss击杀后30秒内）
var is_forge_available: bool = false

## 工坊可用计时器
var forge_available_timer: float = 0.0

## 工坊可用时长（秒）
const FORGE_AVAILABLE_DURATION: float = 30.0

##############################################################################
# 属性类型池
##############################################################################

## 可重铸的属性类型
const ATTRIBUTE_TYPES: Array[String] = [
	"damage",         # 直接伤害加成
	"crit_rate",      # 暴击率
	"crit_dmg",       # 暴击伤害
	"cdr",            # 冷却缩减
	"all_dmg",        # 全伤害
	"melee_dmg",      # 近战伤害
	"ranged_dmg",     # 远程伤害
	"element_dmg",    # 元素伤害
	"summon_dmg"      # 召唤伤害
]

## 属性数值范围
const ATTRIBUTE_VALUE_RANGES: Dictionary = {
	"damage": {"min": 5.0, "max": 20.0},
	"crit_rate": {"min": 3.0, "max": 10.0},
	"crit_dmg": {"min": 5.0, "max": 15.0},
	"cdr": {"min": 3.0, "max": 10.0},
	"all_dmg": {"min": 5.0, "max": 15.0},
	"melee_dmg": {"min": 5.0, "max": 20.0},
	"ranged_dmg": {"min": 5.0, "max": 20.0},
	"element_dmg": {"min": 5.0, "max": 20.0},
	"summon_dmg": {"min": 5.0, "max": 20.0}
}

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	print("[ForgeManager] 初始化完成")
	
	## 订阅Boss击杀事件
	if GameManager and GameManager.has_signal("boss_killed"):
		GameManager.boss_killed.connect(_on_boss_killed)

func _process(delta: float) -> void:
	if is_forge_available:
		forge_available_timer -= delta
		if forge_available_timer <= 0:
			is_forge_available = false
			print("[ForgeManager] 工坊已关闭（超时）")

##############################################################################
# Boss事件
##############################################################################

## Boss击杀回调
func _on_boss_killed(boss_minute: int) -> void:
	upgrades_this_boss = 0
	is_forge_available = true
	forge_available_timer = FORGE_AVAILABLE_DURATION
	print("[ForgeManager] 工坊已开启，剩余时间: ", FORGE_AVAILABLE_DURATION, "秒")

## 检查工坊是否可用
func is_available() -> bool:
	return is_forge_available

## 获取剩余时间
func get_remaining_time() -> float:
	return forge_available_timer

##############################################################################
# 武器升阶
##############################################################################

## 升阶武器
## 参数：weapon_data - 武器实例数据（Player.weapon_slots[i]）
## 返回：是否成功
func upgrade_weapon(weapon_data: Dictionary) -> bool:
	## 检查工坊是否可用
	if not is_forge_available:
		push_warning("[ForgeManager] 工坊未开启")
		return false
	
	## 检查本次Boss升阶次数
	if upgrades_this_boss >= UPGRADES_PER_BOSS:
		push_warning("[ForgeManager] 本次Boss升阶次数已用完")
		return false
	
	var current_quality: String = weapon_data.get("quality", "white")
	
	## 检查是否已是最高品质
	if current_quality == "gold":
		push_warning("[ForgeManager] 武器已是最高品质")
		return false
	
	## 检查矿石
	var cost: int = UPGRADE_COSTS.get(current_quality, 999)
	if not GameManager.spend_ore(cost):
		push_warning("[ForgeManager] 矿石不足")
		return false
	
	## 升阶
	var next_quality: String = QUALITY_UPGRADE_PATH[current_quality]
	weapon_data["quality"] = next_quality
	
	## 增加属性槽
	var old_slots: int = QUALITY_ATTRIBUTE_SLOTS[current_quality]
	var new_slots: int = QUALITY_ATTRIBUTE_SLOTS[next_quality]
	var slots_to_add: int = new_slots - old_slots
	
	if slots_to_add > 0:
		if "attributes" not in weapon_data:
			weapon_data["attributes"] = []
		
		for i in range(slots_to_add):
			var new_attr: Dictionary = generate_random_attribute()
			weapon_data["attributes"].append(new_attr)
	
	## 记录升阶
	upgrades_this_boss += 1
	
	print("[ForgeManager] 武器升阶成功: ", current_quality, " → ", next_quality)
	print("[ForgeManager] 新增属性槽: ", slots_to_add)
	return true

##############################################################################
# 属性重铸
##############################################################################

## 重铸单个属性
## 参数：
##   weapon_data - 武器实例数据
##   attr_index - 属性索引
## 返回：是否成功
func reroll_attribute(weapon_data: Dictionary, attr_index: int) -> bool:
	if "attributes" not in weapon_data:
		push_warning("[ForgeManager] 武器没有属性")
		return false
	
	var attributes: Array = weapon_data["attributes"]
	if attr_index < 0 or attr_index >= attributes.size():
		push_error("[ForgeManager] 属性索引越界: ", attr_index)
		return false
	
	var attr: Dictionary = attributes[attr_index]
	
	## 检查是否锁定
	if attr.get("locked", false):
		push_warning("[ForgeManager] 该属性已锁定")
		return false
	
	## 检查矿石
	if not GameManager.spend_ore(REROLL_COST):
		push_warning("[ForgeManager] 矿石不足")
		return false
	
	## 重铸
	var new_attr: Dictionary = generate_random_attribute()
	attr["type"] = new_attr["type"]
	attr["value"] = new_attr["value"]
	
	print("[ForgeManager] 属性重铸成功: ", attr["type"], "=", attr["value"])
	return true

##############################################################################
# 属性锁定
##############################################################################

## 锁定属性
func lock_attribute(weapon_data: Dictionary, attr_index: int) -> bool:
	if "attributes" not in weapon_data:
		return false
	
	var attributes: Array = weapon_data["attributes"]
	if attr_index < 0 or attr_index >= attributes.size():
		return false
	
	var attr: Dictionary = attributes[attr_index]
	
	## 检查是否已锁定
	if attr.get("locked", false):
		push_warning("[ForgeManager] 该属性已锁定")
		return false
	
	## 检查矿石
	if not GameManager.spend_ore(LOCK_COST):
		push_warning("[ForgeManager] 矿石不足")
		return false
	
	attr["locked"] = true
	print("[ForgeManager] 属性已锁定: ", attr["type"])
	return true

## 解锁属性
func unlock_attribute(weapon_data: Dictionary, attr_index: int) -> bool:
	if "attributes" not in weapon_data:
		return false
	
	var attributes: Array = weapon_data["attributes"]
	if attr_index < 0 or attr_index >= attributes.size():
		return false
	
	var attr: Dictionary = attributes[attr_index]
	attr["locked"] = false
	print("[ForgeManager] 属性已解锁: ", attr["type"])
	return true

##############################################################################
# 属性生成（带权重钩子）
##############################################################################

## 生成随机属性（预留权重调整钩子）
func generate_random_attribute() -> Dictionary:
	## 获取玩家引用（用于权重调整）
	var player: Node = get_tree().get_first_node_in_group("player")
	
	## 基础权重
	var weights: Dictionary = {}
	for attr_type: String in ATTRIBUTE_TYPES:
		weights[attr_type] = 1.0
	
	## 钩子1：根据角色调整权重（预留）
	# if player and player.character_id == "hero_melee":
	#     weights["melee_dmg"] = 2.0
	
	## 钩子2：根据装备武器调整权重（预留）
	# if player and player.has_method("get_dominant_weapon_class"):
	#     var dominant_class = player.get_dominant_weapon_class()
	#     if dominant_class == "melee":
	#         weights["melee_dmg"] = 1.5
	
	## 按权重随机选择
	var selected_type: String = _weighted_random_attribute(weights)
	var value_range: Dictionary = ATTRIBUTE_VALUE_RANGES[selected_type]
	var value: float = randf_range(value_range["min"], value_range["max"])
	
	return {
		"type": selected_type,
		"value": value,
		"locked": false
	}

## 按权重随机属性类型
func _weighted_random_attribute(weights: Dictionary) -> String:
	var total_weight: float = 0.0
	for weight: float in weights.values():
		total_weight += weight
	
	var rand_value: float = randf() * total_weight
	var cumulative: float = 0.0
	
	for attr_type: String in weights.keys():
		cumulative += weights[attr_type]
		if rand_value <= cumulative:
			return attr_type
	
	return ATTRIBUTE_TYPES[0]

##############################################################################
# 武器卖出（预留）
##############################################################################

## 卖出武器
## 返回：回收金币（0表示不折算）
func sell_weapon(weapon_data: Dictionary) -> int:
	var quality: String = weapon_data.get("quality", "white")
	
	## 可配置：是否折算金币
	const ENABLE_SELL_REFUND: bool = false
	
	if not ENABLE_SELL_REFUND:
		return 0
	
	## 折算价格
	match quality:
		"blue":
			return 50
		"purple":
			return 150
		"gold":
			return 500
		_:
			return 0

##############################################################################
# 调试接口
##############################################################################

## 强制开启工坊（调试用）
func debug_open_forge() -> void:
	is_forge_available = true
	forge_available_timer = FORGE_AVAILABLE_DURATION
	upgrades_this_boss = 0
	print("[ForgeManager] 调试：强制开启工坊")
