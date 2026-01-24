##############################################################################
# GameData - 游戏数据加载与管理
#
# 功能说明：
# 1. 加载所有CSV数据到内存（角色、武器、怪物等）
# 2. 提供数据查询接口
# 3. 提供核心公式计算（护甲、移速等）
##############################################################################
extends Node

## 角色数据字典
var characters: Dictionary = {}

## 武器数据字典（预留）
var weapons: Dictionary = {}

## 怪物数据字典（预留）
var monsters: Dictionary = {}

## 护甲减伤公式常量K
## 单位：无量纲
## 作用：护甲减伤公式的系数
## 公式：DR = Armor / (Armor + K)
const ARMOR_K: float = 60.0

## 移速公式常量K
## 单位：无量纲
## 作用：移速倍率公式的系数
## 公式：SpeedMult = 1 + MS / (MS + K) × 0.8
const MOVE_SPEED_K: float = 85.0

## 移速公式最大倍率
const MOVE_SPEED_MAX_MULT: float = 0.8

## 基础移速
## 单位：像素/秒
const BASE_MOVE_SPEED: float = 250.0

func _ready() -> void:
	print("[GameData] 开始加载数据...")
	_load_characters()
	print("[GameData] 数据加载完成!")
	print("  - 角色数量: ", characters.size())

func _load_characters() -> void:
	var csv_path: String = "res://data/role.csv"
	
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 角色数据文件不存在: " + csv_path)
		return
	
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开角色数据文件: " + csv_path)
		return
	
	var header_line: String = file.get_line()
	var headers: PackedStringArray = header_line.split(",")
	
	while not file.eof_reached():
		var line: String = file.get_line()
		
		if line.strip_edges().is_empty():
			continue
		
		var values: PackedStringArray = line.split(",")
		
		if values.size() < headers.size():
			continue
		
		var char_data: Dictionary = {}
		for i: int in range(headers.size()):
			var key: String = headers[i].strip_edges()
			var value: String = values[i].strip_edges()
			
			if key != "id" and key != "name_cn" and key != "name_en" and key != "initial_weapon" and key != "Spec":
				if value.is_empty():
					char_data[key] = 0.0
				else:
					char_data[key] = float(value)
			else:
				char_data[key] = value
		
		var char_id: String = char_data.get("id", "")
		if not char_id.is_empty():
			characters[char_id] = char_data
	
	file.close()
	print("[GameData] 加载角色数据完成，共 ", characters.size(), " 个角色")

func get_character(character_id: String) -> Dictionary:
	if character_id in characters:
		return characters[character_id]
	else:
		push_warning("[GameData] 角色不存在: " + character_id)
		return {}

func get_all_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in characters.keys():
		ids.append(id)
	return ids

func calculate_armor_dr(armor: float) -> float:
	if armor < 0.0:
		return 0.0
	return armor / (armor + ARMOR_K)

func calculate_move_speed_mult(move_speed_stat: float) -> float:
	if move_speed_stat >= 0.0:
		return 1.0 + (move_speed_stat / (move_speed_stat + MOVE_SPEED_K)) * MOVE_SPEED_MAX_MULT
	else:
		var penalty_rate: float = 0.004
		var mult: float = 1.0 + move_speed_stat * penalty_rate
		return max(mult, 0.1)

func calculate_character_stats(character_id: String, level: int) -> Dictionary:
	var char_data: Dictionary = get_character(character_id)
	if char_data.is_empty():
		return {}
	
	var stats: Dictionary = {}
	
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
	
	for stat_name: String in stat_names:
		var base_value: float = char_data.get(stat_name, 0.0)
		var growth_value: float = char_data.get("Grow_" + stat_name, 0.0)
		var current_value: float = base_value + growth_value * float(level - 1)
		stats[stat_name] = current_value
	
	stats["id"] = char_data.get("id", "")
	stats["name_cn"] = char_data.get("name_cn", "")
	stats["name_en"] = char_data.get("name_en", "")
	stats["initial_weapon"] = char_data.get("initial_weapon", "")
	stats["Spec"] = char_data.get("Spec", "")
	
	return stats

func parse_character_spec(spec_text: String) -> Dictionary:
	if spec_text.is_empty():
		return {}
	
	var result: Dictionary = {}
	
	var keyword_map: Dictionary = {
		"近战": "MeleeDamage",
		"远程": "RangedDamage",
		"元素": "ElementalDamage",
		"召唤": "SummonDamage",
		"护甲": "Armor",
		"移速": "MoveSpeed",
		"闪避": "Dodge",
		"生命": "Health",
		"所有伤害": "AllDamage",
		"伤害": "AllDamage",
		"会心": "CritRate",
		"暴击": "CritDamage"
	}
	
	for keyword: String in keyword_map.keys():
		if keyword in spec_text:
			result["stat"] = keyword_map[keyword]
			break
	
	if "* 2" in spec_text or "×2" in spec_text or "翻倍" in spec_text:
		result["multiplier"] = 2.0
	elif "减半" in spec_text or "* 0.5" in spec_text:
		result["multiplier"] = 0.5
	elif "1.5倍" in spec_text:
		result["multiplier"] = 1.5
	else:
		result["multiplier"] = 1.0
	
	return result
