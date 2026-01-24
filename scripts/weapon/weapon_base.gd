##############################################################################
# WeaponBase - 武器基类
#
# 功能说明：
# 1. 所有武器的父类（近战/远程/元素/召唤都继承此类）
# 2. 管理武器的通用属性（伤害、冷却、品质等）
# 3. 提供伤害计算、DPS计算等通用接口
# 4. 解析攻击方式和独有机制
#
# 使用方式：
#   不直接实例化，由子类继承
##############################################################################
extends Node2D
class_name WeaponBase

##############################################################################
# 品质倍率常量
##############################################################################

## 品质伤害倍率
## 单位：倍数字典
## 作用：不同品质的伤害倍率
const QUALITY_MULTIPLIERS: Dictionary = {
	"white": 1.0,
	"blue": 1.15,
	"purple": 1.35,
	"gold": 1.6
}

##############################################################################
# 核心数据
##############################################################################

## 武器模板数据（从GameData加载）
## 数据来源：GameData.get_weapon(weapon_id)
var weapon_data: Dictionary = {}

## 武器实例数据（品质、工坊属性等）
## 数据结构：
##   {
##     "weapon_id": "wp_xxx",
##     "quality": "blue",
##     "attributes": [{"type": "crit_rate", "value": 5.0, "locked": false}],
##     "slot_index": 0
##   }
var instance_data: Dictionary = {}

## 拥有者玩家引用
var owner_player: CharacterBody2D = null

##############################################################################
# 解析后的属性
##############################################################################

## BonusClass解析结果
## 结构：{"type": "M/R/S/E", "multiplier": 1.2}
var bonus_class_parsed: Dictionary = {}

## 伤害系数（从BonusClass解析）
var damage_mult: float = 1.0

## 会心率继承系数
var crit_rate_inherit: float = 1.0

## 会心伤害继承系数
var crit_dmg_inherit: float = 1.0

## 冷却缩减继承系数
var cdr_inherit: float = 1.0

##############################################################################
# 攻击方式和独有机制配置
##############################################################################

## 攻击方式配置
## 数据来源：解析"攻击方式"字段
var attack_method_config: Dictionary = {}

## 独有机制配置数组
## 数据来源：解析"独有机制（UniqueMechanic）"字段
var unique_mechanics: Array[Dictionary] = []

##############################################################################
# 节点引用
##############################################################################

## 攻击计时器
@onready var attack_timer: Timer = $AttackTimer

##############################################################################
# 信号
##############################################################################

## 武器攻击信号
signal weapon_attacked

## 武器销毁信号
signal weapon_destroyed

##############################################################################
# 初始化
##############################################################################

## 初始化武器
## 参数：
##   template_data - 武器模板数据（从GameData获取）
##   inst_data - 武器实例数据（品质、属性等）
##   player - 拥有者玩家
## 作用：
##   1. 存储数据
##   2. 解析BonusClass
##   3. 解析攻击方式和独有机制
##   4. 设置攻击计时器
func initialize(template_data: Dictionary, inst_data: Dictionary, player: CharacterBody2D) -> void:
	weapon_data = template_data
	instance_data = inst_data
	owner_player = player
	
	# 解析BonusClass
	var bonus_class: String = weapon_data.get("加成类别（BonusClass）", "")
	bonus_class_parsed = GameData.parse_bonus_class(bonus_class)
	damage_mult = bonus_class_parsed.get("multiplier", 1.0)
	
	# 读取继承系数
	crit_rate_inherit = weapon_data.get("会心继承系数（CritInherit）", 1.0)
	crit_dmg_inherit = weapon_data.get("会心继承系数（CritInherit）", 1.0)  # 注意：会心率和会心伤害用同一个字段
	cdr_inherit = weapon_data.get("冷却继承系数（CDRInherit）", 1.0)
	
	# 解析攻击方式
	var attack_method: String = weapon_data.get("攻击方式", "")
	if not attack_method.is_empty():
		var parser: WeaponMechanicParser = WeaponMechanicParser.new()
		attack_method_config = parser.parse_attack_method(attack_method)
	
	# 解析独有机制
	var unique_mechanic: String = weapon_data.get("独有机制（UniqueMechanic）", "")
	if not unique_mechanic.is_empty():
		var parser: WeaponMechanicParser = WeaponMechanicParser.new()
		unique_mechanics = parser.parse_unique_mechanic(unique_mechanic)
	
	# 设置攻击计时器
	if attack_timer:
		var cooldown: float = _calculate_actual_cooldown()
		attack_timer.wait_time = cooldown
		attack_timer.timeout.connect(_on_attack_timer_timeout)
		attack_timer.start()
	
	print("[WeaponBase] 武器初始化完成: ", weapon_data.get("显示名称（DisplayName）", "未知"))


##############################################################################
# 伤害计算（核心）
##############################################################################

## 计算武器伤害
## 返回：
##   最终伤害值（含所有加成和暴击判定）
## 公式：
##   final_dmg = (base + bonus_dmg) × all_dmg_mult × quality_mult + weapon_dmg_bonus
##   如果暴击：final_dmg ×= crit_mult
func calculate_damage() -> float:
	# 第一步：基础伤害
	var base: float = weapon_data.get("基础伤害（BaseDamage）", 0.0)
	
	# 第二步：属性加成
	var bonus_type: String = bonus_class_parsed.get("type", "")
	var bonus_attr: String = GameData.get_damage_attribute_from_bonus_type(bonus_type)
	var bonus_dmg: float = owner_player.get_final_stat(bonus_attr) * damage_mult
	
	# 第三步：全伤害加成
	var all_dmg_mult: float = 1.0 + owner_player.get_final_stat("AllDamage") / 100.0
	
	# 第四步：品质加成
	var quality: String = instance_data.get("quality", "white")
	var quality_mult: float = QUALITY_MULTIPLIERS.get(quality, 1.0)
	
	# 第五步：工坊属性直接伤害加成
	var weapon_dmg_bonus: float = _get_weapon_damage_bonus()
	
	# 第六步：计算最终伤害（不含暴击）
	var final_dmg: float = (base + bonus_dmg) * all_dmg_mult * quality_mult + weapon_dmg_bonus
	
	# 应用独有机制的伤害修正
	final_dmg *= _get_mechanic_damage_multiplier()
	
	# 第七步：暴击判定
	var crit_rate: float = owner_player.get_final_stat("CritRate") * crit_rate_inherit
	if randf() * 100.0 < crit_rate:
		var crit_dmg: float = owner_player.get_final_stat("CritDamage") * crit_dmg_inherit
		var crit_mult: float = 1.5 + crit_dmg / 100.0
		final_dmg *= crit_mult
	
	return final_dmg


## 计算DPS（每秒伤害）
## 返回：
##   DPS值
## 公式：
##   DPS = calculate_damage() / actual_cooldown
func get_dps() -> float:
	var damage: float = calculate_damage()
	var cooldown: float = _calculate_actual_cooldown()
	
	if cooldown <= 0:
		return 0.0
	
	return damage / cooldown


##############################################################################
# 冷却计算
##############################################################################

## 计算实际冷却时间
## 返回：
##   实际冷却时间（秒）
## 公式：
##   actual_cd = base_cd × (1 - cdr_inherit × player_cdr / 100) × mechanic_mult
func _calculate_actual_cooldown() -> float:
	var base_cd: float = weapon_data.get("基础冷却（BaseCooldown）\n计算：基础* （1+ 角色 * 系数）", 1.0)
	var player_cdr: float = owner_player.get_final_stat("Cooldown")
	
	# 应用冷却继承
	var actual_cd: float = base_cd * (1.0 - cdr_inherit * player_cdr / 100.0)
	
	# 应用独有机制的冷却修正
	actual_cd *= _get_mechanic_cooldown_multiplier()
	
	return max(actual_cd, 0.1)  # 最小0.1秒


##############################################################################
# 工坊属性和机制加成
##############################################################################

## 获取工坊属性的直接伤害加成
## 返回：
##   伤害加成值
func _get_weapon_damage_bonus() -> float:
	var bonus: float = 0.0
	
	var attributes: Array = instance_data.get("attributes", [])
	for attr: Dictionary in attributes:
		if attr.get("type", "") == "damage":
			bonus += attr.get("value", 0.0)
	
	return bonus


## 获取独有机制的伤害倍率
## 返回：
##   伤害倍率（如1.5表示150%伤害）
func _get_mechanic_damage_multiplier() -> float:
	var mult: float = 1.0
	
	for mechanic: Dictionary in unique_mechanics:
		var mech_type: String = mechanic.get("type", "")
		
		# 单体高伤机制
		if mech_type == "single_target":
			mult *= mechanic.get("params", {}).get("damage_mult", 1.5)
		
		# 慢速重击机制
		if mech_type == "slow_heavy":
			mult *= mechanic.get("params", {}).get("damage_mult", 1.3)
	
	return mult


## 获取独有机制的冷却倍率
## 返回：
##   冷却倍率（如0.7表示冷却时间70%）
func _get_mechanic_cooldown_multiplier() -> float:
	var mult: float = 1.0
	
	for mechanic: Dictionary in unique_mechanics:
		var mech_type: String = mechanic.get("type", "")
		
		# 快速攻击机制
		if mech_type == "fast_attack":
			mult *= mechanic.get("params", {}).get("cooldown_mult", 0.7)
		
		# 慢速重击机制
		if mech_type == "slow_heavy":
			mult *= mechanic.get("params", {}).get("cooldown_mult", 1.5)
	
	return mult


##############################################################################
# 攻击触发（由子类实现）
##############################################################################

## 攻击计时器超时回调
## 作用：子类需要重写此方法实现具体的攻击逻辑
func _on_attack_timer_timeout() -> void:
	push_warning("[WeaponBase] _on_attack_timer_timeout() 未被子类重写")


##############################################################################
# 辅助函数
##############################################################################

## 获取武器显示名称
## 返回：
##   武器名称（中文）
func get_display_name() -> String:
	return weapon_data.get("显示名称（DisplayName）", "未知武器")


## 获取武器ID
## 返回：
##   武器ID
func get_weapon_id() -> String:
	return weapon_data.get("武器ID（WeaponID）", "")


## 获取武器品质
## 返回：
##   品质字符串（white/blue/purple/gold）
func get_quality() -> String:
	return instance_data.get("quality", "white")


## 销毁武器
## 作用：从游戏中移除此武器
func destroy_weapon() -> void:
	weapon_destroyed.emit()
	queue_free()
