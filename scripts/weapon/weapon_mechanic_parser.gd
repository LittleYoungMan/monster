##############################################################################
# WeaponMechanicParser - 武器机制解析器
#
# 功能说明：
# 1. 解析武器的"攻击方式"和"独有机制"中文描述
# 2. 提取关键参数（角度、穿透、数量等）
# 3. 返回结构化的机制配置
#
# 使用方式：
#   var parser = WeaponMechanicParser.new()
#   var config = parser.parse_attack_method("45°挥击")
#   var mechanic = parser.parse_unique_mechanic("近战穿透，只能打三个")
##############################################################################
class_name WeaponMechanicParser
extends RefCounted

## 解析攻击方式
## 参数：
##   text - 攻击方式文本（如"45°挥击"）
## 返回：
##   配置字典 { "type": "...", "params": {...} }
func parse_attack_method(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	
	var config: Dictionary = {}
	
	# 挥击类（近战）
	if "挥击" in text:
		config["type"] = "melee_swing"
		config["params"] = {}
		
		# 提取角度
		var angle: int = _extract_number(text, "°")
		if angle > 0:
			config["params"]["angle"] = angle
		else:
			config["params"]["angle"] = 90  # 默认90度
		
		return config
	
	# 垂直攻击（近战）
	if "垂直攻击" in text:
		config["type"] = "melee_vertical"
		config["params"] = {"angle": 90}
		return config
	
	# 直线突刺（近战）
	if "直线突刺" in text or "连刺" in text:
		config["type"] = "melee_thrust"
		config["params"] = {}
		return config
	
	# 单发直线弹（远程）
	if "单发直线弹" in text or "直线弹" in text or "法术弹直线飞行" in text:
		config["type"] = "ranged_straight"
		config["params"] = {}
		
		# 提取穿透
		var pierce: int = _extract_pierce_count(text)
		config["params"]["pierce"] = pierce
		
		# 判断速度
		if "中速" in text:
			config["params"]["speed_mult"] = 1.0
		elif "慢速" in text:
			config["params"]["speed_mult"] = 0.7
		elif "高速" in text:
			config["params"]["speed_mult"] = 1.3
		
		return config
	
	# 连射弹（远程）
	if "连射" in text or "点射" in text:
		config["type"] = "ranged_burst"
		config["params"] = {}
		config["params"]["pierce"] = _extract_pierce_count(text)
		return config
	
	# 飞刀（远程）
	if "飞刀" in text:
		config["type"] = "ranged_knife"
		config["params"] = {}
		config["params"]["pierce"] = _extract_pierce_count(text)
		return config
	
	# 散射（远程）
	if "散射" in text:
		config["type"] = "ranged_spread"
		config["params"] = {}
		config["params"]["pierce"] = _extract_pierce_count(text)
		return config
	
	# 回旋体（远程）
	if "回旋" in text or "往返" in text:
		config["type"] = "ranged_boomerang"
		config["params"] = {"multi_hit": true}
		return config
	
	# 链锤（远程）
	if "链锤" in text:
		config["type"] = "ranged_chain"
		config["params"] = {"multi_hit": true}
		return config
	
	# 牵引矛（远程）
	if "牵引矛" in text:
		config["type"] = "ranged_pull"
		config["params"] = {"pull_effect": true}
		return config
	
	# 爆炸类（远程/元素）
	if "爆炸" in text or "榴弹" in text or "火箭" in text:
		config["type"] = "ranged_explosive"
		config["params"] = {"explode": true}
		
		if "落点" in text:
			config["params"]["explode_on_impact"] = true
		
		if "残留" in text:
			config["params"]["lingering"]= true
		
		return config
	
	# 抛射弹（元素）
	if "抛射" in text or "抛物线" in text:
		config["type"] = "ranged_arc"
		config["params"] = {"arc_trajectory": true}
		
		if "爆炸" in text:
			config["params"]["explode"] = true
		
		return config
	
	# 火球（元素）
	if "火球" in text:
		config["type"] = "elemental_fireball"
		config["params"] = {"explode": true}
		
		if "缓速" in text:
			config["params"]["speed_mult"] = 0.7
		
		return config
	
	# 法术弹（元素）
	if "法术弹" in text:
		config["type"] = "elemental_spell"
		config["params"] = {}
		config["params"]["pierce"] = _extract_pierce_count(text)
		
		if "冰刺" in text:
			config["params"]["element"] = "ice"
		elif "毒镖" in text:
			config["params"]["element"] = "poison"
		
		return config
	
	# 喷射（元素）
	if "喷射" in text:
		config["type"] = "elemental_spray"
		config["params"] = {"multi_hit": true}
		config["params"]["pierce"] = _extract_pierce_count(text)
		return config
	
	# 持续区（元素）
	if "持续区" in text or "覆盖" in text:
		config["type"] = "elemental_area"
		config["params"] = {"duration": 3.0}
		
		if "酸雾" in text:
			config["params"]["effect"] = "acid"
		
		return config
	
	# 波形扫掠（元素）
	if "波形扫掠" in text or "暗影" in text:
		config["type"] = "elemental_wave"
		config["params"] = {"multi_target": true}
		return config
	
	# 连锁闪电（元素）
	if "连锁闪电" in text:
		config["type"] = "elemental_chain_lightning"
		config["params"] = {"chain": true}
		return config
	
	# 召唤类
	if "召唤" in text:
		config["type"] = "summon"
		config["params"] = {}
		
		# 提取召唤单位ID
		var summon_id: String = _extract_summon_id(text)
		if not summon_id.is_empty():
			config["params"]["summon_unit_id"] = summon_id
		
		# 提取数量
		var count: int = _extract_summon_count(text)
		if count > 0:
			config["params"]["count"] = count
		
		# 提取持续时间
		var duration: float = _extract_duration(text)
		if duration > 0:
			config["params"]["duration"] = duration
		
		return config
	
	# 未识别的攻击方式
	push_warning("[WeaponMechanicParser] 未识别的攻击方式: " + text)
	config["type"] = "unknown"
	config["params"] = {"raw_text": text}
	return config


## 解析独有机制
## 参数：
##   text - 独有机制文本（如"近战穿透，只能打三个"）
## 返回：
##   机制列表 [{ "type": "...", "params": {...} }, ...]
func parse_unique_mechanic(text: String) -> Array[Dictionary]:
	if text.is_empty():
		return []
	
	var mechanics: Array[Dictionary] = []
	
	# 穿透机制
	if "穿透" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "pierce"
		mechanic["params"] = {}
		
		# 提取穿透数量
		var pierce_count: int = _extract_chinese_number(text)
		if pierce_count > 0:
			mechanic["params"]["max_targets"] = pierce_count
		
		mechanics.append(mechanic)
	
	# 击退机制
	if "击退" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "knockback"
		mechanic["params"] = {}
		
		if "小幅" in text:
			mechanic["params"]["force"] = 200.0
		elif "大幅" in text:
			mechanic["params"]["force"] = 500.0
		else:
			mechanic["params"]["force"] = 350.0
		
		# 检查是否是第N击
		var hit_number: int = _extract_hit_number(text)
		if hit_number > 0:
			mechanic["params"]["on_hit_number"] = hit_number
		
		mechanics.append(mechanic)
	
	# 减速机制
	if "减速" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "slow"
		mechanic["params"] = {"slow_mult": 0.7, "duration": 2.0}
		
		if "概率" in text:
			mechanic["params"]["chance"] = 0.3
		
		mechanics.append(mechanic)
	
	# 标记机制
	if "标记" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "mark"
		mechanic["params"] = {"duration": 5.0}
		mechanics.append(mechanic)
	
	# 爆炸机制
	if "爆炸" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "explode"
		mechanic["params"] = {}
		
		if "小范围" in text:
			mechanic["params"]["radius"] = 80.0
		elif "范围" in text:
			mechanic["params"]["radius"] = 120.0
		
		if "残留" in text:
			mechanic["params"]["lingering"] = true
		
		mechanics.append(mechanic)
	
	# 高会心机制
	if "会心" in text and ("高" in text or "更高" in text):
		var mechanic: Dictionary = {}
		mechanic["type"] = "high_crit"
		mechanic["params"] = {"crit_rate_bonus": 0.2}
		mechanics.append(mechanic)
	
	# 攻速机制
	if "攻速快" in text or "快速" in text or "超快" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "fast_attack"
		mechanic["params"] = {}
		
		if "超快" in text:
			mechanic["params"]["cooldown_mult"] = 0.5
		else:
			mechanic["params"]["cooldown_mult"] = 0.7
		
		mechanics.append(mechanic)
	
	# 慢速机制
	if "慢速" in text and ("重击" in text or "巨斩" in text):
		var mechanic: Dictionary = {}
		mechanic["type"] = "slow_heavy"
		mechanic["params"] = {"cooldown_mult": 1.5, "damage_mult": 1.3}
		mechanics.append(mechanic)
	
	# 范围扩大机制
	if "范围更大" in text or "横扫" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "wide_range"
		mechanic["params"] = {"range_mult": 1.3}
		mechanics.append(mechanic)
	
	# 环绕机制
	if "环绕" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "orbit"
		mechanic["params"] = {"orbit_radius": 150.0}
		mechanics.append(mechanic)
	
	# 冲锋自爆机制
	if "冲锋" in text and "爆" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "charge_explode"
		mechanic["params"] = {"explode_on_death": true}
		mechanics.append(mechanic)
	
	# 增益机制
	if "增益" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "buff"
		mechanic["params"] = {"buff_radius": 200.0}
		mechanics.append(mechanic)
	
	# 领域机制
	if "领域" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "field"
		mechanic["params"] = {}
		
		if "减速" in text:
			mechanic["params"]["slow_enemies"] = true
		
		mechanics.append(mechanic)
	
	# 清杂机制
	if "清杂" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "aoe_clear"
		mechanic["params"] = {"bonus_vs_small": 1.5}
		mechanics.append(mechanic)
	
	# 单体高伤机制
	if "单体高伤" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "single_target"
		mechanic["params"] = {"damage_mult": 1.5}
		mechanics.append(mechanic)
	
	# 耐久机制
	if "耐久" in text:
		var mechanic: Dictionary = {}
		mechanic["type"] = "durable"
		mechanic["params"] = {"hp_mult": 2.0}
		mechanics.append(mechanic)
	
	# 如果没有识别到任何机制，返回原始文本
	if mechanics.is_empty():
		push_warning("[WeaponMechanicParser] 未识别的独有机制: " + text)
		var mechanic: Dictionary = {}
		mechanic["type"] = "unknown"
		mechanic["params"] = {"raw_text": text}
		mechanics.append(mechanic)
	
	return mechanics


## 提取数字（如"45°" -> 45）
func _extract_number(text: String, suffix: String) -> int:
	var regex: RegEx = RegEx.new()
	regex.compile("(\\d+)" + suffix)
	var result: RegExMatch = regex.search(text)
	if result:
		return int(result.get_string(1))
	return 0


## 提取穿透次数
func _extract_pierce_count(text: String) -> int:
	var regex: RegEx = RegEx.new()
	regex.compile("穿透(\\d+)")
	var result: RegExMatch = regex.search(text)
	if result:
		return int(result.get_string(1))
	return 0


## 提取中文数字（一、二、三等）
func _extract_chinese_number(text: String) -> int:
	var chinese_numbers: Dictionary = {
		"一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
		"六": 6, "七": 7, "八": 8, "九": 9, "十": 10
	}
	
	for chinese: String in chinese_numbers.keys():
		if chinese in text:
			return chinese_numbers[chinese]
	
	# 尝试提取阿拉伯数字
	var regex: RegEx = RegEx.new()
	regex.compile("(\\d+)个")
	var result: RegExMatch = regex.search(text)
	if result:
		return int(result.get_string(1))
	
	return 0


## 提取第N击
func _extract_hit_number(text: String) -> int:
	var regex: RegEx = RegEx.new()
	regex.compile("第(\\d+)击")
	var result: RegExMatch = regex.search(text)
	if result:
		return int(result.get_string(1))
	return 0


## 提取召唤单位ID
func _extract_summon_id(text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("召唤(su_[a-z_]+)")
	var result: RegExMatch = regex.search(text)
	if result:
		return result.get_string(1)
	return ""


## 提取召唤数量
func _extract_summon_count(text: String) -> int:
	var regex: RegEx = RegEx.new()
	regex.compile("每次(\\d+)个")
	var result: RegExMatch = regex.search(text)
	if result:
		return int(result.get_string(1))
	return 1


## 提取持续时间
func _extract_duration(text: String) -> float:
	var regex: RegEx = RegEx.new()
	regex.compile("持续([\\d.]+)s")
	var result: RegExMatch = regex.search(text)
	if result:
		var duration: float = float(result.get_string(1))
		if duration >= 999:
			return -1.0  # 永久
		return duration
	return 0.0
