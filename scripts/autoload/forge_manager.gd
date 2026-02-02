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
# 工坊常量（来自工坊.xlsx）
##############################################################################

## 工坊刷新
## 单位：矿石
## 作用：刷新工坊的基础费用与递增
const FORGE_REFRESH_BASE: int = 10
const FORGE_REFRESH_STEP: int = 5
const FORGE_REFRESH_MAX_PER_VISIT: int = 3

## 升阶矿石费用
## 单位：矿石
## 作用：白->蓝->紫->金
const UPGRADE_COSTS: Dictionary = {
	"white": 35,   # white→blue
	"blue": 90,    # blue→purple
	"purple": 240  # purple→gold
}

## 打孔/开槽费用
## 单位：矿石
## 作用：紫色第3槽，金色第1-4槽
const PUNCH_SLOT_COST_PURPLE: int = 55
const PUNCH_SLOT_COST_GOLD: Array[int] = [35, 55, 80, 110]

## 敲数值费用
## 单位：矿石
## 作用：不换词条，只改数值
const REROLL_VALUE_COSTS: Dictionary = {
	"blue": 10,
	"purple": 16,
	"gold": 24
}
const REROLL_VALUE_STEP: int = 6
const REROLL_VALUE_MAX_PER_SLOT: int = 3

## 洗词条费用
## 单位：矿石
## 作用：更换词条类型
const REROLL_AFFIX_COSTS: Dictionary = {
	"blue": 18,
	"purple": 28,
	"gold": 42
}
const REROLL_AFFIX_STEP: int = 8

## 重铸费用
## 单位：矿石
## 作用：全洗未锁槽
const REFORGE_ALL_COSTS: Dictionary = {
	"blue": 30,
	"purple": 55,
	"gold": 90
}
const REFORGE_ALL_MAX_PER_VISIT: int = 1

## 锁定费用
## 单位：矿石
## 作用：锁定词条槽位
const LOCK_COST: int = 20
const LOCK_MAX: int = 2

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

## 打造价值基础（每把武器独立）
## 单位：数值
## 作用：驱动工坊价格递增
const CRAFT_VALUE_BASE: Dictionary = {
	"white": 10,
	"blue": 20,
	"purple": 40,
	"gold": 80
}

## 打造价值倍率
## 作用：升阶 x2，其它操作 x1.5
const CRAFT_VALUE_MULT_UPGRADE: float = 2.0
const CRAFT_VALUE_MULT_OTHER: float = 1.5

##############################################################################
# 运行期状态
##############################################################################

## 本次Boss已升阶次数
var upgrades_this_boss: int = 0

## 当前Boss分钟（用于重置计数）
var current_boss_minute: int = -1

## 工坊是否可用（Boss击杀后30秒内）
var is_forge_available: bool = false

## 工坊可用计时器
var forge_available_timer: float = 0.0

## 工坊可用时长（秒）
const FORGE_AVAILABLE_DURATION: float = 30.0

## 本次进工坊的刷新次数
var refresh_count_this_visit: int = 0

## 本次进工坊重铸次数
var reforge_count_this_visit: int = 0

## 本次进工坊洗词条次数
var reroll_affix_count_this_visit: int = 0

## 本次进工坊敲数值次数（按武器/槽位）
var reroll_value_counts: Dictionary = {}

## 武器唯一ID分配
var next_weapon_uid: int = 1

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
# 进出工坊
##############################################################################

## 开始一次工坊访问（用于刷新计数重置）
## 说明：刷新/洗词条/重铸等计数在本次访问内统计
func begin_forge_visit() -> void:
	refresh_count_this_visit = 0
	reforge_count_this_visit = 0
	reroll_affix_count_this_visit = 0
	reroll_value_counts.clear()

## 记录当前Boss分钟（由ForgeDoor传入）
## 说明：每个Boss周期仅允许升阶1次
func set_current_boss_minute(boss_minute: int) -> void:
	if boss_minute != current_boss_minute:
		current_boss_minute = boss_minute
		upgrades_this_boss = 0

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

## 获取打造价值
## 说明：若不存在则按品质初始化
func _ensure_craft_value(weapon_data: Dictionary) -> void:
	if "craft_value" in weapon_data:
		return
	var quality: String = weapon_data.get("quality", "white")
	weapon_data["craft_value"] = CRAFT_VALUE_BASE.get(quality, 10)

## 获取打造价值（内部）
func _get_craft_value(weapon_data: Dictionary) -> int:
	_ensure_craft_value(weapon_data)
	return int(weapon_data.get("craft_value", 10))

## 获取打造价值（对外）
func get_craft_value(weapon_data: Dictionary) -> int:
	return _get_craft_value(weapon_data)

## 更新打造价值倍率
func _apply_craft_value_multiplier(weapon_data: Dictionary, mult: float) -> void:
	_ensure_craft_value(weapon_data)
	var value: float = float(weapon_data["craft_value"])
	value = ceil(value * mult)
	weapon_data["craft_value"] = int(value)

## 计算动作最终价格
func _get_action_cost(weapon_data: Dictionary, base_cost: int) -> int:
	var craft_value: int = _get_craft_value(weapon_data)
	return base_cost + int(round(float(craft_value) / 10.0))

## 获取武器唯一ID（用于计数）
func _get_weapon_uid(weapon_data: Dictionary) -> int:
	if "forge_uid" in weapon_data:
		return int(weapon_data["forge_uid"])
	weapon_data["forge_uid"] = next_weapon_uid
	next_weapon_uid += 1
	return int(weapon_data["forge_uid"])

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
	var base_cost: int = UPGRADE_COSTS.get(current_quality, 999)
	var cost: int = _get_action_cost(weapon_data, base_cost)
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

	## 打造价值提升
	_apply_craft_value_multiplier(weapon_data, CRAFT_VALUE_MULT_UPGRADE)
	
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
	return reroll_affix(weapon_data, attr_index)

##############################################################################
# 打孔/重铸/敲数值
##############################################################################

## 获取升阶成本
func get_upgrade_cost(weapon_data: Dictionary) -> int:
	var quality: String = weapon_data.get("quality", "white")
	var base_cost: int = UPGRADE_COSTS.get(quality, 999)
	return _get_action_cost(weapon_data, base_cost)

## 获取打孔成本
func get_punch_slot_cost(weapon_data: Dictionary) -> int:
	var quality: String = weapon_data.get("quality", "white")
	var current_slots: int = int(weapon_data.get("attributes", []).size())
	if quality == "purple":
		return _get_action_cost(weapon_data, PUNCH_SLOT_COST_PURPLE)
	if quality == "gold":
		var idx: int = clamp(current_slots, 0, PUNCH_SLOT_COST_GOLD.size() - 1)
		return _get_action_cost(weapon_data, PUNCH_SLOT_COST_GOLD[idx])
	return -1

## 获取敲数值成本
func get_reroll_value_cost(weapon_data: Dictionary, attr_index: int) -> int:
	var quality: String = weapon_data.get("quality", "white")
	if quality not in REROLL_VALUE_COSTS:
		return -1
	var attributes: Array = weapon_data.get("attributes", [])
	if attr_index < 0 or attr_index >= attributes.size():
		return -1
	var uid: int = _get_weapon_uid(weapon_data)
	var key: String = str(uid) + ":" + str(attr_index)
	var count: int = int(reroll_value_counts.get(key, 0))
	if count >= REROLL_VALUE_MAX_PER_SLOT:
		return -1
	var base_cost: int = int(REROLL_VALUE_COSTS[quality])
	return _get_action_cost(weapon_data, base_cost + REROLL_VALUE_STEP * count)

## 获取洗词条成本
func get_reroll_affix_cost(weapon_data: Dictionary) -> int:
	var quality: String = weapon_data.get("quality", "white")
	if quality not in REROLL_AFFIX_COSTS:
		return -1
	var base_cost: int = int(REROLL_AFFIX_COSTS[quality])
	return _get_action_cost(weapon_data, base_cost + REROLL_AFFIX_STEP * reroll_affix_count_this_visit)

## 获取重铸成本
func get_reforge_cost(weapon_data: Dictionary) -> int:
	var quality: String = weapon_data.get("quality", "white")
	if quality not in REFORGE_ALL_COSTS:
		return -1
	var base_cost: int = int(REFORGE_ALL_COSTS[quality])
	return _get_action_cost(weapon_data, base_cost)

## 获取锁槽成本
func get_lock_cost(weapon_data: Dictionary) -> int:
	return _get_action_cost(weapon_data, LOCK_COST)

## 获取刷新成本
func get_refresh_cost() -> int:
	if refresh_count_this_visit >= FORGE_REFRESH_MAX_PER_VISIT:
		return -1
	return FORGE_REFRESH_BASE + FORGE_REFRESH_STEP * refresh_count_this_visit

## 打孔（增加1个词条槽）
func punch_slot(weapon_data: Dictionary) -> bool:
	if not is_forge_available:
		return false
	var quality: String = weapon_data.get("quality", "white")
	var slot_cap: int = int(QUALITY_ATTRIBUTE_SLOTS.get(quality, 0))
	if slot_cap <= 0:
		return false
	if "attributes" not in weapon_data:
		weapon_data["attributes"] = []
	var attributes: Array = weapon_data["attributes"]
	if attributes.size() >= slot_cap:
		return false

	var cost: int = get_punch_slot_cost(weapon_data)
	if cost < 0 or not GameManager.spend_ore(cost):
		push_warning("[ForgeManager] 矿石不足")
		return false

	var new_attr: Dictionary = generate_random_attribute()
	attributes.append(new_attr)
	_apply_craft_value_multiplier(weapon_data, CRAFT_VALUE_MULT_OTHER)
	print("[ForgeManager] 打孔成功: 新槽位=", attributes.size())
	return true

## 敲数值（不换词条）
func reroll_value(weapon_data: Dictionary, attr_index: int) -> bool:
	if not is_forge_available:
		return false
	if "attributes" not in weapon_data:
		return false
	var attributes: Array = weapon_data["attributes"]
	if attr_index < 0 or attr_index >= attributes.size():
		return false
	var attr: Dictionary = attributes[attr_index]
	if attr.get("locked", false):
		return false

	var cost: int = get_reroll_value_cost(weapon_data, attr_index)
	if cost < 0 or not GameManager.spend_ore(cost):
		push_warning("[ForgeManager] 矿石不足")
		return false

	var attr_type: String = attr.get("type", "")
	var value_range: Dictionary = ATTRIBUTE_VALUE_RANGES.get(attr_type, {"min": 1.0, "max": 10.0})
	var value: float = randf_range(value_range["min"], value_range["max"])
	attr["value"] = value

	var uid: int = _get_weapon_uid(weapon_data)
	var key: String = str(uid) + ":" + str(attr_index)
	reroll_value_counts[key] = int(reroll_value_counts.get(key, 0)) + 1

	_apply_craft_value_multiplier(weapon_data, CRAFT_VALUE_MULT_OTHER)
	print("[ForgeManager] 敲数值成功: ", attr["type"], "=", attr["value"])
	return true

## 洗词条（更换词条类型）
func reroll_affix(weapon_data: Dictionary, attr_index: int) -> bool:
	if not is_forge_available:
		return false
	if "attributes" not in weapon_data:
		return false
	var attributes: Array = weapon_data["attributes"]
	if attr_index < 0 or attr_index >= attributes.size():
		return false
	var attr: Dictionary = attributes[attr_index]
	if attr.get("locked", false):
		return false

	var cost: int = get_reroll_affix_cost(weapon_data)
	if cost < 0 or not GameManager.spend_ore(cost):
		push_warning("[ForgeManager] 矿石不足")
		return false

	var new_attr: Dictionary = generate_random_attribute()
	attr["type"] = new_attr["type"]
	attr["value"] = new_attr["value"]
	reroll_affix_count_this_visit += 1

	_apply_craft_value_multiplier(weapon_data, CRAFT_VALUE_MULT_OTHER)
	print("[ForgeManager] 洗词条成功: ", attr["type"], "=", attr["value"])
	return true

## 重铸（全洗未锁槽）
func reforge_all(weapon_data: Dictionary) -> bool:
	if not is_forge_available:
		return false
	if reforge_count_this_visit >= REFORGE_ALL_MAX_PER_VISIT:
		return false
	if "attributes" not in weapon_data:
		return false
	var cost: int = get_reforge_cost(weapon_data)
	if cost < 0 or not GameManager.spend_ore(cost):
		push_warning("[ForgeManager] 矿石不足")
		return false
	var attributes: Array = weapon_data["attributes"]
	for i in range(attributes.size()):
		var attr: Dictionary = attributes[i]
		if attr.get("locked", false):
			continue
		var new_attr: Dictionary = generate_random_attribute()
		attr["type"] = new_attr["type"]
		attr["value"] = new_attr["value"]
	reforge_count_this_visit += 1
	_apply_craft_value_multiplier(weapon_data, CRAFT_VALUE_MULT_OTHER)
	print("[ForgeManager] 重铸完成")
	return true

## 刷新工坊（仅消耗与计数）
func refresh_forge() -> bool:
	if not is_forge_available:
		return false
	if refresh_count_this_visit >= FORGE_REFRESH_MAX_PER_VISIT:
		return false
	var cost: int = get_refresh_cost()
	if cost < 0 or not GameManager.spend_ore(cost):
		return false
	refresh_count_this_visit += 1
	return true

##############################################################################
# 属性锁定
##############################################################################

## 锁定属性
func lock_attribute(weapon_data: Dictionary, attr_index: int) -> bool:
	if not is_forge_available:
		return false
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

	## 检查锁槽上限
	var locked_count: int = 0
	for item: Dictionary in attributes:
		if item.get("locked", false):
			locked_count += 1
	if locked_count >= LOCK_MAX:
		return false
	
	## 检查矿石
	var cost: int = _get_action_cost(weapon_data, LOCK_COST)
	if not GameManager.spend_ore(cost):
		push_warning("[ForgeManager] 矿石不足")
		return false
	
	attr["locked"] = true
	_apply_craft_value_multiplier(weapon_data, CRAFT_VALUE_MULT_OTHER)
	print("[ForgeManager] 属性已锁定: ", attr["type"])
	return true

## 解锁属性
func unlock_attribute(weapon_data: Dictionary, attr_index: int) -> bool:
	if not is_forge_available:
		return false
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
