##############################################################################
# GameData - 游戏数据加载与管理
#
# 功能说明：
# 1. 加载所有CSV数据到内存（角色、武器、怪物等）
# 2. 提供数据查询接口
# 3. 提供核心公式计算（护甲、移速、冷却等）
# 4. 预留其他系统数据加载接口
#
# 使用方式：
#   var char_data = GameData.get_character("hero_01")
#   var armor_dr = GameData.calculate_armor_dr(50.0)
##############################################################################
extends Node

## 角色数据字典
## 单位：Dictionary[String, Dictionary]
## 作用：存储所有角色的数据
## 数据来源：res://data/role.csv
var characters: Dictionary = {}

## 武器数据字典（预留）
## 单位：Dictionary[String, Dictionary]
## 作用：存储所有武器的数据
## 数据来源：res://data/weapons.csv（待实现）
var weapons: Dictionary = {}

## 怪物数据字典（预留）
## 单位：Dictionary[String, Dictionary]
## 作用：存储所有怪物的数据
## 数据来源：res://data/monsters.csv（待实现）
var monsters: Dictionary = {}

## 商店卡数据字典（预留）
## 单位：Dictionary[String, Dictionary]
## 作用：存储所有商店卡的数据
## 数据来源：res://data/shop_cards.csv（待实现）
var shop_cards: Dictionary = {}


## 护甲减伤公式常量K
## 单位：无量纲
## 作用：护甲减伤公式的系数
## 调整范围：40-100
## 当前值：60（参考base.md修正）
## 调整建议：
##   - K越小，护甲效果越强（如K=40，100护甲减伤71.4%）
##   - K越大，护甲效果越弱（如K=100，100护甲减伤50%）
##   - 推荐范围60-80
const ARMOR_K: float = 60.0

## 移速公式常量K
## 单位：无量纲
## 作用：移速倍率公式的系数
## 调整范围：50-150
## 当前值：85（参考base.md）
## 调整建议：
##   - K越小，移速加成越强
##   - K越大，移速加成越弱
const MOVE_SPEED_K: float = 85.0

## 移速公式最大倍率
## 单位：倍数
## 作用：移速加成的最大倍率
## 调整范围：0.5-1.0
## 当前值：0.8（最多80%加成）
## 调整建议：
##   - 如果玩家移速太快，降低此值（如0.6=最多60%加成）
##   - 如果玩家移速太慢，提高此值（如1.0=最多100%加成）
const MOVE_SPEED_MAX_MULT: float = 0.8

## 基础移速
## 单位：像素/秒
## 作用：角色的基础移动速度
## 调整范围：200-400
## 当前值：250
## 调整建议：
##   - 如果游戏节奏太慢，提高此值（如300）
##   - 如果游戏节奏太快，降低此值（如200）
const BASE_MOVE_SPEED: float = 250.0

## 冷却缩减上限
## 单位：百分比
## 作用：冷却缩减的最大值
## 调整范围：40-80
## 当前值：60（最多60% CDR）
## 调整建议：
##   - 如果玩家攻速太快，降低此值（如40）
##   - 如果玩家攻速太慢，提高此值（如80）
const CDR_CAP: float = 60.0

## 暴击基础倍率
## 单位：倍数
## 作用：暴击伤害的基础倍率
## 调整范围：1.3-2.0
## 当前值：1.5（150%伤害）
## 调整建议：
##   - 如果暴击不够爽，提高此值（如1.8）
##   - 如果暴击太强，降低此值（如1.3）
const CRIT_BASE_MULTIPLIER: float = 1.5


## 初始化GameData
## 作用：游戏启动时自动加载所有CSV数据
func _ready() -> void:
	print("[GameData] 开始加载数据...")
	
	# 加载角色数据
	_load_characters()
	
	# 预留：加载其他数据
	# _load_weapons()
	# _load_monsters()
	# _load_shop_cards()
	
	print("[GameData] 数据加载完成!")
	print("  - 角色数量: ", characters.size())


## 加载角色数据
## 作用：从CSV文件读取所有角色数据
## 数据来源：res://data/role.csv
func _load_characters() -> void:
	var csv_path: String = "res://data/role.csv"
	
	# 检查文件是否存在
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 角色数据文件不存在: " + csv_path)
		return
	
	# 打开CSV文件
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开角色数据文件: " + csv_path)
		return
	
	# 读取表头
	var header_line: String = file.get_line()
	var headers: PackedStringArray = header_line.split(",")
	
	# 字符串字段列表（需要特殊处理的字段）
	var string_fields: Array[String] = ["id", "特性", "name_cn", "name_en", "initial_weapon", "Spec"]
	
	# 读取数据行
	var current_row_data: Dictionary = {}
	var current_id: String = ""
	var is_multiline_spec: bool = false
	var spec_buffer: String = ""
	
	while not file.eof_reached():
		var line: String = file.get_line()
		
		# 检查是否是空行（所有字段都为空）
		var is_empty_row: bool = true
		var test_values: PackedStringArray = line.split(",")
		for val: String in test_values:
			if not val.strip_edges().is_empty():
				is_empty_row = false
				break
		
		if is_empty_row:
			# 如果有缓存的数据，保存它
			if not current_id.is_empty():
				if is_multiline_spec:
					current_row_data["Spec"] = spec_buffer.strip_edges()
				characters[current_id] = current_row_data
				current_row_data = {}
				current_id = ""
				is_multiline_spec = false
				spec_buffer = ""
			continue
		
		var values: PackedStringArray = line.split(",")
		
		# 检查是否是新的角色行（有id字段）
		if values.size() > 0 and not values[0].strip_edges().is_empty():
			# 保存之前的角色数据
			if not current_id.is_empty():
				if is_multiline_spec:
					current_row_data["Spec"] = spec_buffer.strip_edges()
				characters[current_id] = current_row_data
			
			# 开始新角色
			current_row_data = {}
			is_multiline_spec = false
			spec_buffer = ""
			
			# 解析所有字段
			for i: int in range(min(headers.size(), values.size())):
				var key: String = headers[i].strip_edges()
				var value: String = values[i].strip_edges()
				
				if key.is_empty():
					continue
				
				# 转换数值类型
				if key in string_fields:
					# 字符串字段
					current_row_data[key] = value
					
					# 检查Spec字段是否包含换行（判断是否是多行Spec）
					if key == "Spec" and not value.is_empty():
						spec_buffer = value
						# 检查是否包含引号（表示多行开始）
						if value.begins_with('"'):
							is_multiline_spec = true
							spec_buffer = value.trim_prefix('"')
				else:
					# 数值字段
					if value.is_empty():
						current_row_data[key] = 0.0
					else:
						current_row_data[key] = float(value)
			
			# 记录当前角色ID
			current_id = current_row_data.get("id", "")
			
		elif is_multiline_spec:
			# 多行Spec的后续行
			var spec_line: String = line.strip_edges()
			
			# 检查是否是Spec结束（包含引号）
			if spec_line.ends_with('"'):
				spec_buffer += "\n" + spec_line.trim_suffix('"')
				is_multiline_spec = false
				current_row_data["Spec"] = spec_buffer.strip_edges()
			else:
				spec_buffer += "\n" + spec_line
	
	# 保存最后一个角色
	if not current_id.is_empty():
		if is_multiline_spec:
			current_row_data["Spec"] = spec_buffer.strip_edges()
		characters[current_id] = current_row_data
	
	file.close()
	print("[GameData] 加载角色数据完成，共 ", characters.size(), " 个角色")


## 获取角色数据
## 参数：
##   character_id - 角色ID（如"hero_01"）
## 返回：
##   角色数据字典，如果不存在则返回空字典
## 示例：
##   var data = GameData.get_character("hero_01")
##   print(data["name_cn"])  # 输出：雾壳
func get_character(character_id: String) -> Dictionary:
	if character_id in characters:
		return characters[character_id]
	else:
		push_warning("[GameData] 角色不存在: " + character_id)
		return {}


## 获取所有角色ID列表
## 返回：
##   所有角色ID的数组
## 示例：
##   var ids = GameData.get_all_character_ids()  # ["hero_01", "hero_02", ...]
func get_all_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in characters.keys():
		ids.append(id)
	return ids


## 计算护甲减伤率
## 参数：
##   armor - 护甲值
## 返回：
##   减伤率（0.0-1.0，如0.5表示减伤50%）
## 公式：
##   DR = Armor / (Armor + K)
##   其中K=60
## 示例：
##   var dr = GameData.calculate_armor_dr(60.0)  # 返回 0.5 (50%减伤)
func calculate_armor_dr(armor: float) -> float:
	if armor < 0.0:
		return 0.0
	return armor / (armor + ARMOR_K)


## 计算移速倍率
## 参数：
##   move_speed_stat - 角色的移速属性值（可为负）
## 返回：
##   移速倍率（如1.2表示120%速度）
## 公式：
##   Mult = 1 + MS / (MS + K) × 0.8
##   其中K=85，最大加成80%
## 示例：
##   var mult = GameData.calculate_move_speed_mult(85.0)  # 返回 1.4 (140%速度)
func calculate_move_speed_mult(move_speed_stat: float) -> float:
	if move_speed_stat >= 0.0:
		# 正值：加速
		return 1.0 + (move_speed_stat / (move_speed_stat + MOVE_SPEED_K)) * MOVE_SPEED_MAX_MULT
	else:
		# 负值：减速（线性）
		# 例如：-10移速 = 0.96倍速度（减速4%）
		# -100移速 = 0.6倍速度（减速40%）
		var penalty_rate: float = 0.004  # 每点负移速减速0.4%
		var mult: float = 1.0 + move_speed_stat * penalty_rate
		return max(mult, 0.1)  # 最低10%速度


## 计算冷却缩减倍率
## 参数：
##   cdr - 冷却缩减属性值（百分比）
## 返回：
##   冷却倍率（如0.7表示冷却时间为70%）
## 公式：
##   Mult = 1 - min(CDR, 60) / 100
##   其中CDR上限60%
## 示例：
##   var mult = GameData.calculate_cdr_mult(40.0)  # 返回 0.6 (冷却时间60%)
##   实际冷却 = 基础冷却 × mult
func calculate_cdr_mult(cdr: float) -> float:
	var capped_cdr: float = min(cdr, CDR_CAP)
	return 1.0 - (capped_cdr / 100.0)


## 计算暴击倍率
## 参数：
##   crit_damage - 暴击伤害属性值（百分比）
## 返回：
##   暴击倍率（如2.0表示200%伤害）
## 公式：
##   Mult = 1.5 + CritDmg / 100
## 示例：
##   var mult = GameData.calculate_crit_mult(50.0)  # 返回 2.0 (200%伤害)
func calculate_crit_mult(crit_damage: float) -> float:
	return CRIT_BASE_MULTIPLIER + (crit_damage / 100.0)


## 计算角色在指定等级的属性
## 参数：
##   character_id - 角色ID
##   level - 等级（1-20）
## 返回：
##   该等级下的所有属性字典
## 公式：
##   当前属性 = base_属性 + growth_属性 × (level - 1)
## 示例：
##   var stats = GameData.calculate_character_stats("hero_01", 5)
##   print(stats["Health"])  # 等级5的生命值
func calculate_character_stats(character_id: String, level: int) -> Dictionary:
	var char_data: Dictionary = get_character(character_id)
	if char_data.is_empty():
		return {}
	
	var stats: Dictionary = {}
	
	# 所有可成长的属性名
	var stat_names: Array[String] = [
		"MeleeDamage", "RangedDamage", "ElementalDamage", "SummonDamage",
		"Armor", "MoveSpeed", "Dodge",
		"Health", "HealthRegen", "Lifesteal",
		"AllDamage", "Cooldown", "CritRate", "CritDamage", "Range",
		"ExpRate", "MaterialCostRate", "PickupRange", "ItemPrice",
		"ExplosionRange", "ExplosionDamage", "Penetration", "PenetrationDamage",
		"BossDamage", "SummonCooldownInherit", "SummonCritInherit", 
		"SummonCritRateInherit", "SummonCount",
		"BurnChance", "SlowChance", "FreezeChance",
		"DoubleMaterialChance", "MaterialRespawnCooldown",
		"EnemySpeed", "EnemyHealth", "EnemyCritChance", 
		"EnemyMaterialDropRate", "EnemyCount"
	]
	
	# 计算每个属性
	for stat_name: String in stat_names:
		var base_value: float = char_data.get(stat_name, 0.0)
		var growth_value: float = char_data.get("Grow_" + stat_name, 0.0)
		var current_value: float = base_value + growth_value * float(level - 1)
		stats[stat_name] = current_value
	
	# 复制非成长属性
	stats["id"] = char_data.get("id", "")
	stats["name_cn"] = char_data.get("name_cn", "")
	stats["name_en"] = char_data.get("name_en", "")
	stats["initial_weapon"] = char_data.get("initial_weapon", "")
	stats["Spec"] = char_data.get("Spec", "")
	
	return stats


## 解析角色特性（Spec）
## 参数：
##   spec_text - Spec字段文本（支持多行，如"近战伤害*2"或"近战伤害/2\n远程伤害/2"）
## 返回：
##   特性配置数组 [{ "stat": "属性名", "multiplier": 倍数, "operation": "multiply"/"set_zero" }]
##   如果解析失败返回空数组
## 示例：
##   var spec = GameData.parse_character_spec("近战伤害*2")
##   # 返回 [{ "stat": "MeleeDamage", "multiplier": 2.0, "operation": "multiply" }]
##
##   var spec2 = GameData.parse_character_spec("护甲*0\n闪避*0")
##   # 返回 [
##   #   { "stat": "Armor", "multiplier": 0.0, "operation": "set_zero" },
##   #   { "stat": "Dodge", "multiplier": 0.0, "operation": "set_zero" }
##   # ]
func parse_character_spec(spec_text: String) -> Array:
	if spec_text.is_empty():
		return []
	
	var results: Array = []
	
	# 特性关键词映射
	var keyword_map: Dictionary = {
		"近战伤害": "MeleeDamage",
		"近战": "MeleeDamage",
		"远程伤害": "RangedDamage",
		"远程": "RangedDamage",
		"元素伤害": "ElementalDamage",
		"元素": "ElementalDamage",
		"召唤伤害": "SummonDamage",
		"召唤": "SummonDamage",
		"护甲": "Armor",
		"移速": "MoveSpeed",
		"闪避": "Dodge",
		"生命": "Health",
		"生命恢复": "HealthRegen",
		"吸血": "Lifesteal",
		"所有伤害": "AllDamage",
		"全伤害": "AllDamage",
		"伤害": "AllDamage",
		"会心": "CritRate",
		"暴击": "CritDamage"
	}
	
	# 分割多行Spec
	var lines: PackedStringArray = spec_text.split("\n")
	
	for line: String in lines:
		var trimmed_line: String = line.strip_edges()
		if trimmed_line.is_empty():
			continue
		
		var spec_item: Dictionary = {}
		
		# 解析属性名
		var found_stat: bool = false
		for keyword: String in keyword_map.keys():
			if keyword in trimmed_line:
				spec_item["stat"] = keyword_map[keyword]
				found_stat = true
				break
		
		if not found_stat:
			# 尝试解析特殊描述（如"移速转全伤害加成"）
			if "移速转" in trimmed_line and "伤害" in trimmed_line:
				spec_item["stat"] = "MoveSpeed"
				spec_item["special"] = "speed_to_damage"
				spec_item["multiplier"] = 1.0
				spec_item["operation"] = "special"
				results.append(spec_item)
				continue
			elif "小怪刷新压力" in trimmed_line:
				spec_item["stat"] = "EnemyCount"
				spec_item["special"] = "spawn_pressure"
				if "1.5倍" in trimmed_line:
					spec_item["multiplier"] = 1.5
				spec_item["operation"] = "special"
				results.append(spec_item)
				continue
			else:
				# 无法识别的Spec，保存原文以备调试
				spec_item["raw"] = trimmed_line
				results.append(spec_item)
				continue
		
		# 解析倍数和操作类型
		if "*2" in trimmed_line or "×2" in trimmed_line or "翻倍" in trimmed_line:
			spec_item["multiplier"] = 2.0
			spec_item["operation"] = "multiply"
		elif "/2" in trimmed_line or "减半" in trimmed_line:
			spec_item["multiplier"] = 0.5
			spec_item["operation"] = "multiply"
		elif "*0" in trimmed_line or "×0" in trimmed_line:
			spec_item["multiplier"] = 0.0
			spec_item["operation"] = "set_zero"
		elif "*1.5" in trimmed_line or "1.5倍" in trimmed_line:
			spec_item["multiplier"] = 1.5
			spec_item["operation"] = "multiply"
		else:
			# 默认没有倍率修改
			spec_item["multiplier"] = 1.0
			spec_item["operation"] = "none"
		
		results.append(spec_item)
	
	return results


## 预留：武器数据加载接口
## 作用：加载武器数据（待实现）
func _load_weapons() -> void:
	# TODO: 实现武器数据加载
	pass


## 预留：获取武器数据接口
## 参数：
##   weapon_id - 武器ID
## 返回：
##   武器数据字典
func get_weapon(weapon_id: String) -> Dictionary:
	# TODO: 实现武器数据查询
	return {}


## 预留：怪物数据加载接口
## 作用：加载怪物数据（待实现）
func _load_monsters() -> void:
	# TODO: 实现怪物数据加载
	pass


## 预留：获取怪物数据接口
## 参数：
##   monster_id - 怪物ID
## 返回：
##   怪物数据字典
func get_monster(monster_id: String) -> Dictionary:
	# TODO: 实现怪物数据查询
	return {}


## 预留：商店卡数据加载接口
## 作用：加载商店卡数据（待实现）
func _load_shop_cards() -> void:
	# TODO: 实现商店卡数据加载
	pass


## 预留：获取商店卡数据接口
## 参数：
##   card_id - 卡牌ID
## 返回：
##   卡牌数据字典
func get_shop_card(card_id: String) -> Dictionary:
	# TODO: 实现商店卡数据查询
	return {}
