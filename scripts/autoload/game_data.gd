##############################################################################
# GameData - 游戏数据中心（全局）
#
# 设计目的：
# - 统一加载CSV数据（角色/武器/投射物/召唤/怪物/Boss）
# - 提供基础公式计算（护甲/移速/冷却/暴击）
# - 提供数据查询接口（给角色/武器/刷怪系统调用）
# - 解析角色Spec文本，生成可执行的属性增益规则
#
# 调用链举例：
# - GameManager/Player -> GameData.get_character / calculate_character_stats
# - Weapon/Projectile/Summon -> GameData.get_weapon / get_projectile / get_summon_unit
# - EnemySpawner -> GameData.get_monster / get_boss_id_by_minute
#
# 引擎回调：
# - _ready(): 启动时加载所有CSV并打印统计信息
#
# 修复：2026-01-27 重新写回中文注释与打印信息
##############################################################################
extends Node

##############################################################################
# 数据容器（运行期缓存）
##############################################################################

## 角色数据字典：key=角色id, value=角色字段字典
## 数据来源：res://assets/data/role.csv
var characters: Dictionary = {}

## 武器数据字典：key=武器id
## 数据来源：res://assets/data/weapon.csv
var weapons: Dictionary = {}

## 投射物数据字典：key=投射物id
## 数据来源：res://assets/data/projectile.csv
var projectiles: Dictionary = {}

## 召唤单位数据字典：key=召唤单位id
## 数据来源：res://assets/data/summon.csv
var summon_units: Dictionary = {}

## Boss数据字典：key=boss id`n## 数据来源：res://assets/data/monster_boss.csv`n## 备注：Field_15行为说明已保留在behavior字段
var boss_monsters: Dictionary = {}

## 怪物数据字典：key=怪物id
## 数据来源：res://assets/data/monster.csv
var monsters: Dictionary = {}

## 商店卡牌数据（预留）
var shop_cards: Dictionary = {}

##############################################################################
# 公式常量（数值系统）
##############################################################################

## 护甲减伤K（防止护甲无限放大，典型Diminishing Returns）
const ARMOR_K: float = 60.0

## 移速曲线K（决定正移速收益弯曲程度）
const MOVE_SPEED_K: float = 85.0

## 正移速收益上限倍率（避免移速过高）
const MOVE_SPEED_MAX_MULT: float = 0.8

## 基础移动速度（参考值，非强制）
const BASE_MOVE_SPEED: float = 250.0

## 冷却缩减上限（百分比）
const CDR_CAP: float = 60.0

## 暴击倍率基础值（基础1.5倍）
const CRIT_BASE_MULTIPLIER: float = 1.5

## 减速持续时间
## 单位：秒
## 作用：通用减速效果持续时间
## 调整范围：1-5
## 当前值：3
const SLOW_DURATION: float = 3.0

## 减速倍率
## 单位：倍数
## 作用：通用减速移动倍率（越小越慢）
## 调整范围：0.3-0.9
## 当前值：0.7
const SLOW_MULTIPLIER: float = 0.7

## Boss数据缺失时的怪物ID兜底（按分钟）
const BOSS_FALLBACK_BY_MINUTE: Dictionary = {
	5: "M_CRC_01",
	10: "M_GNR_01",
	15: "M_BRL_01",
	20: "M_ELT_01"
}

##############################################################################
# 生命周期回调
##############################################################################

func _ready() -> void:
	print("[GameData] 开始加载数据...")
	_load_characters()
	_load_weapon_data()
	_load_shop_cards()
	_load_monsters()
	_load_monster_bosses()
	print("[GameData] 数据加载完成!")
	print("  - 角色数量: ", characters.size())
	print("  - 武器数量: ", weapons.size())
	print("  - 商店卡数量: ", shop_cards.size())
	print("  - 投射物数量: ", projectiles.size())
	print("  - 召唤单位数量: ", summon_units.size())
	print("  - 怪物数量: ", monsters.size())
	print("  - Boss数量: ", boss_monsters.size())

##############################################################################
# CSV解析工具
##############################################################################

## 解析一行CSV（支持引号/逗号转义）
## 参数：line 原始行
## 返回：字段数组
func _parse_csv_line(line: String) -> PackedStringArray:
	var result: Array[String] = []
	var current: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < line.length():
		var code: int = line.unicode_at(i)
		if code == 34: # "
			if in_quotes and i + 1 < line.length() and line.unicode_at(i + 1) == 34:
				current += "\""
				i += 1
			else:
				in_quotes = not in_quotes
		elif code == 44 and not in_quotes: # ,
			result.append(current)
			current = ""
		else:
			current += String.chr(code)
		i += 1
	result.append(current)
	return PackedStringArray(result)

## 解析布尔值（兼容英文/数字/中文“是”）
func _parse_bool(value: String) -> bool:
	var v := value.strip_edges()
	return v == "true" or v == "True" or v == "1" or v == "是" or v == "Y" or v == "y"

## 解析浮点数（空或None返回0）
func _parse_float(value: String) -> float:
	var v := value.strip_edges()
	if v.is_empty() or v == "None":
		return 0.0
	return float(v)

## 从多候选字段中获取第一个非空值（兼容中英字段名）
func _get_raw_first(raw: Dictionary, keys: Array[String], default_value: String = "") -> String:
	for k in keys:
		if raw.has(k) and not String(raw.get(k, "")).is_empty():
			return String(raw.get(k, ""))
	return default_value

##############################################################################
# 角色数据加载与查询
##############################################################################

## 加载角色数据（role.csv）
func _load_characters() -> void:
	var csv_path: String = "res://assets/data/role.csv"
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 角色数据文件不存在: " + csv_path)
		return

	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开角色数据文件: " + csv_path)
		return

	var header_line: String = file.get_line()
	var headers: PackedStringArray = _parse_csv_line(header_line)

	## 需要保留为字符串的字段
	var string_fields: Array[String] = ["id", "name_cn", "name_en", "initial_weapon", "Spec"]

	## 处理Spec多行的临时缓存
	var current_row_data: Dictionary = {}
	var current_id: String = ""
	var is_multiline_spec: bool = false
	var spec_buffer: String = ""

	while not file.eof_reached():
		var line: String = file.get_line()
		var is_empty_row: bool = true
		var test_values: PackedStringArray = _parse_csv_line(line)
		for val: String in test_values:
			if not val.strip_edges().is_empty():
				is_empty_row = false
				break

		## 空行 => 结束当前角色的Spec块
		if is_empty_row:
			if not current_id.is_empty():
				if is_multiline_spec:
					current_row_data["Spec"] = spec_buffer.strip_edges()
				characters[current_id] = current_row_data
				current_row_data = {}
				current_id = ""
				is_multiline_spec = false
				spec_buffer = ""
			continue

		var values: PackedStringArray = _parse_csv_line(line)

		## 如果该行首列有值，视为新角色开始
		if values.size() > 0 and not values[0].strip_edges().is_empty():
			if not current_id.is_empty():
				if is_multiline_spec:
					current_row_data["Spec"] = spec_buffer.strip_edges()
				characters[current_id] = current_row_data

			current_row_data = {}
			is_multiline_spec = false
			spec_buffer = ""

			for i: int in range(min(headers.size(), values.size())):
				var key: String = headers[i].strip_edges()
				var value: String = values[i].strip_edges()

				if key.is_empty():
					continue

				## 兼容重复字段（如SummonCritInherit出现两次）
				if key == "SummonCritInherit" and current_row_data.has("SummonCritInherit"):
					key = "Grow_SummonCritInherit"

				if key in string_fields:
					current_row_data[key] = value
					if key == "Spec" and not value.is_empty():
						spec_buffer = value
						if value.begins_with('"'):
							is_multiline_spec = true
							spec_buffer = value.trim_prefix('"')
				else:
					if value.is_empty():
						current_row_data[key] = 0.0
					else:
						current_row_data[key] = float(value)

			current_id = current_row_data.get("id", "")

		## Spec多行处理（直到遇到结尾引号）
		elif is_multiline_spec:
			var spec_line: String = line.strip_edges()
			if spec_line.ends_with('"'):
				spec_buffer += "\n" + spec_line.trim_suffix('"')
				is_multiline_spec = false
				current_row_data["Spec"] = spec_buffer.strip_edges()
			else:
				spec_buffer += "\n" + spec_line

	## 文件结束后，将最后一条写入
	if not current_id.is_empty():
		if is_multiline_spec:
			current_row_data["Spec"] = spec_buffer.strip_edges()
		characters[current_id] = current_row_data

	file.close()
	print("[GameData] 角色数据加载完成: ", characters.size(), " 条")

## 获取单个角色数据
func get_character(character_id: String) -> Dictionary:
	if character_id in characters:
		return characters[character_id]
	push_warning("[GameData] 角色不存在: " + character_id)
	return {}

## 获取所有角色ID列表
func get_all_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in characters.keys():
		ids.append(id)
	return ids

##############################################################################
# 公式计算
##############################################################################

## 护甲减伤（返回0~1之间比例）
func calculate_armor_dr(armor: float) -> float:
	if armor < 0.0:
		return 0.0
	return armor / (armor + ARMOR_K)

## 移速倍率（正移速收益递减，负移速线性惩罚）
func calculate_move_speed_mult(move_speed_stat: float) -> float:
	if move_speed_stat >= 0.0:
		return 1.0 + (move_speed_stat / (move_speed_stat + MOVE_SPEED_K)) * MOVE_SPEED_MAX_MULT
	else:
		var penalty_rate: float = 0.004
		var mult: float = 1.0 + move_speed_stat * penalty_rate
		return max(mult, 0.1)

## 冷却倍率（限制最大CDR）
func calculate_cdr_mult(cdr: float) -> float:
	var capped_cdr: float = min(cdr, CDR_CAP)
	return 1.0 - (capped_cdr / 100.0)

## 暴击倍率（基础+额外暴伤）
func calculate_crit_mult(crit_damage: float) -> float:
	return CRIT_BASE_MULTIPLIER + (crit_damage / 100.0)

##############################################################################
# 角色属性计算
##############################################################################

## 计算角色在指定等级下的属性值
## 参数：character_id 角色id；level 等级（>=1）
## 返回：包含最终属性与基础字段的Dictionary
func calculate_character_stats(character_id: String, level: int) -> Dictionary:
	var char_data: Dictionary = get_character(character_id)
	if char_data.is_empty():
		return {}

	var stats: Dictionary = {}

	## 需要参与“基础值+成长值”的属性列表
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

	## 附加基础字段（用于显示/系统引用）
	stats["id"] = char_data.get("id", "")
	stats["name_cn"] = char_data.get("name_cn", "")
	stats["name_en"] = char_data.get("name_en", "")
	stats["initial_weapon"] = char_data.get("initial_weapon", "")
	stats["Spec"] = char_data.get("Spec", "")

	return stats

##############################################################################
# Spec解析（角色特性文本）
##############################################################################

## 解析Spec文本为规则数组
## 返回：包含stat/multiplier/operation等字段的数组
func parse_character_spec(spec_text: String) -> Array:
	if spec_text.is_empty():
		return []

	var results: Array = []

	## 关键词映射（中文 -> 内部属性名）
	var keyword_map: Dictionary = {
		"近战伤害": "MeleeDamage",
		"远程伤害": "RangedDamage",
		"元素伤害": "ElementalDamage",
		"召唤伤害": "SummonDamage",
		"生命回复": "HealthRegen",
		"暴击伤害": "CritDamage",
		"暴击率": "CritRate",
		"全伤害": "AllDamage",
		"护甲": "Armor",
		"闪避": "Dodge",
		"移速": "MoveSpeed",
		"生命": "Health",
		"吸血": "Lifesteal",
		"近战": "MeleeDamage",
		"远程": "RangedDamage",
		"元素": "ElementalDamage",
		"召唤": "SummonDamage"
	}
	## 长关键词优先，避免“生命”先于“生命回复”被命中
	var keyword_priority: Array[String] = [
		"近战伤害",
		"远程伤害",
		"元素伤害",
		"召唤伤害",
		"生命回复",
		"暴击伤害",
		"暴击率",
		"全伤害",
		"护甲",
		"闪避",
		"移速",
		"生命",
		"吸血",
		"近战",
		"远程",
		"元素",
		"召唤"
	]

	var normalized_text: String = spec_text.replace("\r", "")
	normalized_text = normalized_text.replace("，", "、").replace(",", "、")
	normalized_text = normalized_text.replace("；", "、").replace(";", "、")
	normalized_text = normalized_text.replace("。", "、").replace("|", "、")

	var lines: PackedStringArray = normalized_text.split("\n")
	for line: String in lines:
		var trimmed_line: String = line.strip_edges()
		if trimmed_line.is_empty():
			continue
		var clauses: PackedStringArray = trimmed_line.split("、", false)
		for clause: String in clauses:
			_parse_spec_clause(clause.strip_edges(), keyword_map, keyword_priority, results)

	return results

## 解析单条Spec语句
func _parse_spec_clause(
	clause: String,
	keyword_map: Dictionary,
	keyword_priority: Array[String],
	results: Array
) -> void:
	if clause.is_empty():
		return

	var normalized_clause: String = clause.strip_edges()
	if normalized_clause.begins_with("所有来源"):
		normalized_clause = normalized_clause.trim_prefix("所有来源").strip_edges()
	elif normalized_clause.begins_with("所有"):
		normalized_clause = normalized_clause.trim_prefix("所有").strip_edges()
	if normalized_clause.is_empty():
		return

	## 特殊规则：移速转全伤
	if "移速转全伤害" in normalized_clause:
		var speed_to_damage_ratio: float = _extract_speed_to_damage_ratio(normalized_clause, 0.5)
		results.append({
			"operation": "special",
			"special": "speed_to_damage",
			"ratio": speed_to_damage_ratio,
			"raw": clause
		})
		return

	## 特殊规则：闪避触发回血
	if "闪避" in normalized_clause and ("回复" in normalized_clause or "回血" in normalized_clause or "回生命" in normalized_clause):
		var numbers: Array[float] = _extract_numbers_from_text(normalized_clause)
		var chance: float = 10.0
		var heal_amount: float = 1.0
		if numbers.size() >= 2:
			chance = numbers[0]
			heal_amount = numbers[1]
		elif numbers.size() == 1:
			if "%" in normalized_clause:
				chance = numbers[0]
			else:
				heal_amount = numbers[0]
		chance = clamp(chance, 0.0, 100.0)
		heal_amount = max(0.0, heal_amount)
		if heal_amount <= 0.0:
			heal_amount = 1.0
		results.append({
			"operation": "special",
			"special": "dodge_heal_on_dodge",
			"chance": chance,
			"heal": heal_amount,
			"raw": clause
		})
		return

	## 特殊规则：每+1移速换伤害和生命（最低生命保底）
	if "每+1移速" in normalized_clause and "近战" in normalized_clause and "生命" in normalized_clause:
		var signed_numbers: Array[float] = _extract_signed_numbers_from_text(normalized_clause)
		var melee_per_speed: float = 2.0
		var health_penalty_per_speed: float = 1.0
		var health_floor: float = _extract_number_after_keyword(normalized_clause, "最低生命", 1.0)
		for value: float in signed_numbers:
			if value > 0.0 and absf(value - 1.0) > 0.001:
				melee_per_speed = absf(value)
				break
		for value: float in signed_numbers:
			if value < 0.0:
				health_penalty_per_speed = absf(value)
				break
		results.append({
			"operation": "special",
			"special": "speed_tradeoff",
			"melee_per_speed": melee_per_speed,
			"health_penalty_per_speed": health_penalty_per_speed,
			"health_floor": max(1.0, health_floor),
			"raw": clause
		})
		return

	## 特殊规则：周期随机双姿态
	var has_stance_cycle: bool = (
		"随机" in normalized_clause
		and "近战" in normalized_clause
		and "远程" in normalized_clause
		and ("+30" in normalized_clause or "-50" in normalized_clause)
	)
	if has_stance_cycle:
		var interval_sec: float = _extract_interval_seconds(normalized_clause, 3600.0)
		interval_sec = clamp(interval_sec, 15.0, 600.0)
		results.append({
			"operation": "special",
			"special": "stance_cycle_melee_ranged",
			"interval_sec": interval_sec,
			"raw": clause
		})
		return

	## 特殊规则：小怪刷新压力
	if "小怪刷新压力" in normalized_clause or "敌人数量" in normalized_clause:
		var pressure_mult: float = _extract_multiplier_from_clause(normalized_clause, 1.0)
		pressure_mult = clamp(pressure_mult, 0.3, 3.0)
		results.append({
			"stat": "EnemyCount",
			"operation": "multiply",
			"multiplier": pressure_mult,
			"raw": clause
		})
		return

	var matched_stat: String = _find_spec_stat_by_keyword(normalized_clause, keyword_map, keyword_priority)
	if matched_stat.is_empty():
		if "buff" in normalized_clause and "清除另一种" in normalized_clause:
			return
		results.append({"raw": clause})
		return

	## 乘除与置零规则
	var multiplier_value: float = _extract_multiplier_from_clause(normalized_clause, NAN)
	if not is_nan(multiplier_value):
		if absf(multiplier_value) < 0.0001:
			results.append({
				"stat": matched_stat,
				"operation": "set_zero",
				"multiplier": 0.0,
				"raw": clause
			})
			return
		results.append({
			"stat": matched_stat,
			"operation": "multiply",
			"multiplier": multiplier_value,
			"raw": clause
		})
		return

	## 加减规则（如 近战伤害+30 / 远程-50）
	var signed_value: Variant = _extract_first_signed_delta(normalized_clause)
	if typeof(signed_value) == TYPE_FLOAT:
		results.append({
			"stat": matched_stat,
			"operation": "add",
			"value": float(signed_value),
			"raw": clause
		})
		return

	results.append({
		"stat": matched_stat,
		"operation": "none",
		"multiplier": 1.0,
		"raw": clause
	})

## 提取文本中全部数字（支持符号与小数）
func _extract_numbers_from_text(text: String) -> Array[float]:
	var regex := RegEx.new()
	regex.compile("[-+]?\\d+(?:\\.\\d+)?")
	var numbers: Array[float] = []
	var matches: Array[RegExMatch] = regex.search_all(text)
	for item: RegExMatch in matches:
		numbers.append(float(item.get_string()))
	return numbers

## 提取文本中全部“带符号”的数字
func _extract_signed_numbers_from_text(text: String) -> Array[float]:
	var regex := RegEx.new()
	regex.compile("[-+]\\d+(?:\\.\\d+)?")
	var numbers: Array[float] = []
	var matches: Array[RegExMatch] = regex.search_all(text)
	for item: RegExMatch in matches:
		numbers.append(float(item.get_string()))
	return numbers

## 从语句中提取乘除倍率（支持 * / x / × / “倍”）
func _extract_multiplier_from_clause(text: String, fallback: float) -> float:
	var multiply_regex := RegEx.new()
	multiply_regex.compile("[xX×*]\\s*([-+]?\\d+(?:\\.\\d+)?)")
	var multiply_match: RegExMatch = multiply_regex.search(text)
	if multiply_match != null:
		return float(multiply_match.get_string(1))

	var divide_regex := RegEx.new()
	divide_regex.compile("/\\s*([-+]?\\d+(?:\\.\\d+)?)")
	var divide_match: RegExMatch = divide_regex.search(text)
	if divide_match != null:
		var divisor: float = float(divide_match.get_string(1))
		if absf(divisor) > 0.0001:
			return 1.0 / divisor
		return 0.0

	var times_regex := RegEx.new()
	times_regex.compile("([-+]?\\d+(?:\\.\\d+)?)\\s*倍")
	var times_match: RegExMatch = times_regex.search(text)
	if times_match != null:
		return float(times_match.get_string(1))

	return fallback

## 提取某关键词后的第一个数字
func _extract_number_after_keyword(text: String, keyword: String, default_value: float) -> float:
	var escaped_key: String = keyword.replace("(", "\\(").replace(")", "\\)")
	var regex := RegEx.new()
	regex.compile(escaped_key + "[^\\d\\-+]*([-+]?\\d+(?:\\.\\d+)?)")
	var matched: RegExMatch = regex.search(text)
	if matched == null:
		return default_value
	return float(matched.get_string(1))

## 提取“每隔XX秒/min”时长（统一转换到秒）
func _extract_interval_seconds(text: String, default_seconds: float) -> float:
	var regex := RegEx.new()
	regex.compile("每(?:隔)?\\s*([-+]?\\d+(?:\\.\\d+)?)\\s*(秒|s|sec|min|分钟)?")
	var matched: RegExMatch = regex.search(text)
	if matched == null:
		return default_seconds
	var value: float = float(matched.get_string(1))
	var unit: String = matched.get_string(2).to_lower()
	if unit == "min" or unit == "分钟":
		return value * 60.0
	return value

## 提取“移速转全伤害”规则中的换算比例
func _extract_speed_to_damage_ratio(text: String, default_ratio: float) -> float:
	var numbers: Array[float] = _extract_numbers_from_text(text)
	if numbers.is_empty():
		return default_ratio
	if "每+1" in text or "每1" in text:
		if numbers.size() >= 2:
			var speed_unit: float = max(1.0, absf(numbers[0]))
			return clamp(absf(numbers[1]) / speed_unit, 0.05, 3.0)
	if "%" in text or "加成" in text:
		return clamp(absf(numbers[0]) / 100.0, 0.05, 3.0)
	return clamp(absf(numbers[0]), 0.05, 3.0)

## 提取第一组“带符号”的增减值
func _extract_first_signed_delta(text: String) -> Variant:
	var regex := RegEx.new()
	regex.compile("[-+]\\d+(?:\\.\\d+)?")
	var matched: RegExMatch = regex.search(text)
	if matched == null:
		return null
	return float(matched.get_string())

## 按优先级匹配关键词映射到属性
func _find_spec_stat_by_keyword(
	clause: String,
	keyword_map: Dictionary,
	keyword_priority: Array[String]
) -> String:
	for keyword: String in keyword_priority:
		if keyword in clause:
			return String(keyword_map.get(keyword, ""))
	return ""

##############################################################################
# 怪物数据查询
##############################################################################

## 获取怪物数据
func get_monster(monster_id: String) -> Dictionary:
	if monster_id in monsters:
		return monsters[monster_id]
	push_warning("[GameData] 怪物不存在: " + monster_id)
	return {}

## 获取全部怪物ID
func get_all_monster_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in monsters.keys():
		ids.append(id)
	return ids

## 根据体型筛选怪物ID
func get_monsters_by_size(size_type: String) -> Array[String]:
	var result: Array[String] = []
	for monster_id: String in monsters.keys():
		var data: Dictionary = monsters[monster_id]
		if data.get("Size", "") == size_type:
			result.append(monster_id)
	return result

## 获取全部Boss ID
func get_boss_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in boss_monsters.keys():
		ids.append(id)
	return ids

## 获取Boss数据
func get_boss_data(boss_id: String) -> Dictionary:
	if boss_id in boss_monsters:
		return boss_monsters[boss_id]
	return {}

## 根据分钟获取Boss ID（匹配Minute字段）
func get_boss_id_by_minute(minute: int) -> String:
	var candidates: Array[String] = get_boss_ids_by_minute(minute)
	if candidates.is_empty():
		return ""
	return candidates.pick_random()

## 根据分钟获取全部Boss ID
func get_boss_ids_by_minute(minute: int) -> Array[String]:
	var ids: Array[String] = []
	for boss_id: String in boss_monsters.keys():
		var data: Dictionary = boss_monsters[boss_id]
		if int(data.get("Minute", -1)) == minute:
			ids.append(boss_id)
	return ids

## 获取Boss实际使用的怪物ID（用于刷怪）
func get_boss_spawn_monster_id(boss_id: String) -> String:
	var data: Dictionary = get_boss_data(boss_id)
	if data.is_empty():
		return ""
	return String(data.get("monster_id", boss_id))

## 判断怪物是否为Boss
func is_boss(monster_id: String) -> bool:
	return monster_id in boss_monsters

##############################################################################
# 商店卡牌（预留）
##############################################################################

## 加载商店卡数据（shop.csv）
##
## 参数：无
## 返回：无
func _load_shop_cards() -> void:
	var csv_path: String = "res://assets/data/shop.csv"
	if not FileAccess.file_exists(csv_path):
		push_warning("[GameData] 商店卡数据文件不存在: " + csv_path)
		return

	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开商店卡数据文件: " + csv_path)
		return

	var header_line: String = file.get_line()
	var headers: PackedStringArray = _parse_csv_line(header_line)

	# 处理BOM
	if headers.size() > 0:
		headers[0] = headers[0].replace("\ufeff", "")

	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges().is_empty():
			continue
		var values: PackedStringArray = _parse_csv_line(line)
		if values.size() < headers.size():
			continue

		var raw: Dictionary = {}
		for i: int in range(headers.size()):
			raw[headers[i].strip_edges()] = values[i].strip_edges()

		var card_id: String = _get_raw_first(raw, ["CardID（卡ID）", "CardID", "card_id"])
		if card_id.is_empty():
			continue

		var card_name: String = _get_raw_first(raw, ["CardName（卡名）", "CardName", "name"])
		var rarity_raw: String = _get_raw_first(raw, ["Rarity（稀有度）", "Rarity", "rarity"])
		var cap_raw: String = _get_raw_first(raw, ["Cap（上限）", "Cap", "cap"])
		var price_raw: String = _get_raw_first(raw, ["Price（价格）", "Price", "price"])
		var tags_raw: String = _get_raw_first(raw, ["Tags（标签）", "Tags", "tags"])
		var effects_raw: String = _get_raw_first(raw, ["EffectsEN（效果英文合集）", "EffectsEN", "effects"])

		var effects: Array = _parse_shop_effects(effects_raw)

		var card_data: Dictionary = {
			"id": card_id,
			"name": card_name,
			"rarity": _convert_shop_rarity(rarity_raw),
			"cap": int(_parse_float(cap_raw)),
			"price": int(_parse_float(price_raw)),
			"tags": tags_raw,
			"effects": effects
		}

		shop_cards[card_id] = card_data

	file.close()
	print("[GameData] 商店卡数据加载完成: ", shop_cards.size(), " 条")

## 获取商店卡数据
##
## 参数：
##   card_id - 卡牌ID
## 返回：卡牌数据字典
func get_shop_card(card_id: String) -> Dictionary:
	if card_id in shop_cards:
		return shop_cards[card_id]
	return {}

##############################################################################
# 商店卡解析辅助
##############################################################################

## 解析卡牌效果文本
##
## 参数：
##   effect_text - 效果字符串
## 返回：效果数组
func _parse_shop_effects(effect_text: String) -> Array:
	var results: Array = []
	if effect_text.is_empty():
		return results

	var cleaned: String = effect_text.replace("，", ",").replace("；", ",").replace("、", ",")
	var parts: PackedStringArray = cleaned.split(",", false)
	for part: String in parts:
		var trimmed: String = part.strip_edges()
		if trimmed.is_empty():
			continue
		var sep_idx: int = trimmed.find(":")
		if sep_idx == -1:
			sep_idx = trimmed.find("：")
		if sep_idx == -1:
			continue
		var key: String = trimmed.substr(0, sep_idx).strip_edges()
		var value_str: String = trimmed.substr(sep_idx + 1).strip_edges()
		if key.is_empty() or value_str.is_empty():
			continue
		if value_str.begins_with("+"):
			value_str = value_str.substr(1)
		value_str = value_str.replace("%", "")

		var value: float = _parse_float(value_str)
		var stat_key: String = _normalize_shop_effect_key(key)
		results.append({
			"stat": stat_key,
			"value": value,
			"raw": key
		})
	return results

## 规范化卡牌属性名
##
## 参数：
##   raw_key - 原始字段名
## 返回：规范化字段名
func _normalize_shop_effect_key(raw_key: String) -> String:
	var key: String = raw_key.strip_edges()
	var mapping: Dictionary = {
		"SummonCooldownInheritPct": "SummonCooldownInherit",
		"SummonCooldownInherit": "SummonCooldownInherit",
		"SummonCritInheritPct": "SummonCritInherit",
		"SummonCritInherit": "SummonCritInherit",
		"SummonCount": "SummonCount",
		"EnemyMaterialDropChance": "EnemyMaterialDropRate"
	}
	if mapping.has(key):
		return mapping[key]
	return key

## 转换卡牌稀有度（中文->内部）
##
## 参数：
##   raw_rarity - 原始稀有度
## 返回：内部稀有度字符串
func _convert_shop_rarity(raw_rarity: String) -> String:
	match raw_rarity:
		"白":
			return "white"
		"蓝":
			return "blue"
		"紫":
			return "purple"
		"金":
			return "gold"
		_:
			return "white"

##############################################################################
# 武器/投射物/召唤单位加载
##############################################################################

## 加载武器CSV
func _load_weapons() -> void:
	var csv_path: String = "res://assets/data/weapon.csv"
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 武器数据文件不存在: " + csv_path)
		return
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开武器数据文件: " + csv_path)
		return

	var header_line: String = file.get_line()
	var headers: PackedStringArray = _parse_csv_line(header_line)
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges().is_empty():
			continue
		var values: PackedStringArray = _parse_csv_line(line)
		if values.size() < headers.size():
			continue
		var raw: Dictionary = {}
		for i: int in range(headers.size()):
			var key: String = headers[i].strip_edges()
			var value: String = values[i].strip_edges()
			raw[key] = value
		var weapon_id: String = raw.get("WeaponID", "")
		if weapon_id.is_empty():
			continue
		var bonus_class_raw: String = raw.get("BonusClass", "")
		var bonus_parsed: Dictionary = parse_bonus_class(bonus_class_raw)
		var weapon_data: Dictionary = {
			"weapon_id": weapon_id,
			"id": weapon_id,
			"display_name": raw.get("DisplayName", ""),
			"name_cn": raw.get("DisplayName", ""),
			"rarity_start": raw.get("RarityStart", ""),
			"Class": raw.get("Class", ""),
			"Family": raw.get("Family", ""),
			"SetTags": raw.get("SetTags", ""),
			"bonus_class": bonus_parsed.get("type", ""),
			"bonus_class_raw": bonus_class_raw,
			"bonus_class_mult": bonus_parsed.get("multiplier", 1.0),
			"base_damage": _parse_float(raw.get("BaseDamage", "")),
			"damage_mult": _parse_float(raw.get("DamageMult", "")),
			"crit_mult": _parse_float(raw.get("CritMult", "")),
			"crit_rate_inherit": _parse_float(raw.get("CritInherit", "")),
			"crit_dmg_inherit": _parse_float(raw.get("CritInherit", "")),
			"projectile_id": raw.get("ProjectileID", ""),
			"pierce_count": int(_parse_float(raw.get("PierceCount", ""))),
			"attack_way": raw.get("actackWay", ""),
			"unique_mechanic": raw.get("UniqueMechanic", ""),
			"cdr_inherit": _parse_float(raw.get("CDRInherit", "")),
			"base_cooldown": _parse_float(raw.get("BaseCooldown", "")),
			"attack_range": _parse_float(raw.get("BaseRange", "")),
			"base_range": _parse_float(raw.get("BaseRange", "")),
			"summon_count": int(_parse_float(raw.get("SummonCount", ""))),
			"summon_unit_id": raw.get("SummonUnitID", ""),
			"icon_id": raw.get("IconID", ""),
			"price_w_coin": int(_parse_float(raw.get("Price_W_Coin", ""))),
			"price_b_coin": int(_parse_float(raw.get("Price_B_Coin", ""))),
			"price_p_coin": int(_parse_float(raw.get("Price_P_Coin", "")))
		}
		weapons[weapon_id] = weapon_data
	file.close()
	print("[GameData] 武器数据加载完成: ", weapons.size(), " 条")

## 加载投射物CSV
func _load_projectiles() -> void:
	var csv_path: String = "res://assets/data/projectile.csv"
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 投射物数据文件不存在: " + csv_path)
		return
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开投射物数据文件: " + csv_path)
		return
	var header_line: String = file.get_line()
	var headers: PackedStringArray = _parse_csv_line(header_line)
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges().is_empty():
			continue
		var values: PackedStringArray = _parse_csv_line(line)
		if values.size() < headers.size():
			continue
		var raw: Dictionary = {}
		for i: int in range(headers.size()):
			raw[headers[i].strip_edges()] = values[i].strip_edges()
		var proj_id: String = raw.get("ProjectileID", "")
		if proj_id.is_empty():
			continue
		var proj_data: Dictionary = {
			"projectile_id": proj_id,
			"display_name": raw.get("DisplayName", ""),
			"type": raw.get("Type", ""),
			"hit_radius_px": _parse_float(raw.get("HitRadiusPx", "")),
			"speed_pxps": _parse_float(raw.get("SpeedPxps", "")),
			"use_weapon_range": _parse_bool(raw.get("UseWeaponRange", "")),
			"hit_limit": int(_parse_float(raw.get("HitLimit", ""))),
			"homing": _parse_bool(raw.get("Homing", "")),
			"explode": _parse_bool(raw.get("Explode", "")),
			"explode_radius_px": _parse_float(raw.get("ExplodeRadiusPx", "")),
			"area_duration_s": _parse_float(raw.get("AreaDurationS", "")),
			"vfx_hit_id": raw.get("VFXHitID", ""),
			"sprite_id": raw.get("SpriteID", "")
		}
		projectiles[proj_id] = proj_data
	file.close()
	print("[GameData] 投射物数据加载完成: ", projectiles.size(), " 条")

## 加载召唤单位CSV
func _load_summon_units() -> void:
	var csv_path: String = "res://assets/data/summon.csv"
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 召唤单位数据文件不存在: " + csv_path)
		return
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开召唤单位数据文件: " + csv_path)
		return
	var header_line: String = file.get_line()
	var headers: PackedStringArray = _parse_csv_line(header_line)
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges().is_empty():
			continue
		var values: PackedStringArray = _parse_csv_line(line)
		if values.size() < headers.size():
			continue
		var raw: Dictionary = {}
		for i: int in range(headers.size()):
			raw[headers[i].strip_edges()] = values[i].strip_edges()
		var summon_id: String = raw.get("SummonUnitID", "")
		if summon_id.is_empty():
			continue
		var summon_data: Dictionary = {
			"summon_unit_id": summon_id,
			"display_name": raw.get("DisplayName", ""),
			"summon_type": raw.get("SummonType", ""),
			"behavior_tags": raw.get("BehaviorTags", ""),
			"attack_mode": raw.get("AttackMode", ""),
			"base_damage": _parse_float(_get_raw_first(raw, ["BaseDamage", "基础伤害", "基础伤害(BaseDamage)"])) ,
			"notes": _get_raw_first(raw, ["Notes", "备注", "说明"], ""),
			"sprite_id": _get_raw_first(raw, ["SpriteID", "贴图ID", "精灵ID", "精灵ID（SpriteID）"], "")
		}
		summon_units[summon_id] = summon_data
	file.close()
	print("[GameData] 召唤单位数据加载完成: ", summon_units.size(), " 条")

##############################################################################
# 查询接口
##############################################################################

## 获取武器数据
func get_weapon(weapon_id: String) -> Dictionary:
	if weapon_id in weapons:
		return weapons[weapon_id]
	push_warning("[GameData] 武器不存在: " + weapon_id)
	return {}

## 获取投射物数据
func get_projectile(projectile_id: String) -> Dictionary:
	if projectile_id in projectiles:
		return projectiles[projectile_id]
	push_warning("[GameData] 投射物不存在: " + projectile_id)
	return {}

## 获取召唤单位数据
func get_summon_unit(summon_unit_id: String) -> Dictionary:
	if summon_unit_id in summon_units:
		return summon_units[summon_unit_id]
	push_warning("[GameData] 召唤单位不存在: " + summon_unit_id)
	return {}

## 获取全部武器ID
func get_all_weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in weapons.keys():
		ids.append(id)
	return ids

##############################################################################
# BonusClass解析
##############################################################################

## 解析BonusClass（如M120 => type=M, multiplier=1.2）
func parse_bonus_class(bonus_class: String) -> Dictionary:
	if bonus_class.is_empty():
		return {"type": "", "multiplier": 1.0}

	var result: Dictionary = {}
	result["type"] = bonus_class[0]

	var number_str: String = bonus_class.substr(1)
	if number_str.is_empty():
		result["multiplier"] = 1.0
	else:
		result["multiplier"] = float(number_str) / 100.0

	return result

## 根据BonusClass类型获取对应伤害属性
func get_damage_attribute_from_bonus_type(bonus_type: String) -> String:
	match bonus_type:
		"M":
			return "MeleeDamage"
		"R":
			return "RangedDamage"
		"S":
			return "SummonDamage"
		"E":
			return "ElementalDamage"
		_:
			push_warning("[GameData] 未知BonusClass类型: " + bonus_type)
			return "AllDamage"

## 武器数据加载入口（调用内部3类加载）
func _load_weapon_data() -> void:
	_load_weapons()
	_load_projectiles()
	_load_summon_units()

##############################################################################
# 怪物数据加载
##############################################################################

## 加载怪物CSV
func _load_monsters() -> void:
	var csv_path: String = "res://assets/data/monster.csv"
	if not FileAccess.file_exists(csv_path):
		push_warning("[GameData] 怪物数据文件不存在: " + csv_path)
		return
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开怪物数据文件: " + csv_path)
		return
	var header_line: String = file.get_line()
	var headers: PackedStringArray = _parse_csv_line(header_line)
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges().is_empty():
			continue
		var values: PackedStringArray = _parse_csv_line(line)
		if values.size() < headers.size():
			continue
		var raw: Dictionary = {}
		for i: int in range(headers.size()):
			raw[headers[i].strip_edges()] = values[i].strip_edges()
		var monster_id: String = raw.get("MonsterID", "")
		if monster_id.is_empty():
			continue
		var monster_data: Dictionary = {
			"MonsterID": monster_id,
			"NameZH": raw.get("NameZH", ""),
			"NameEN": raw.get("NameEN", ""),
			"Size": raw.get("Size", ""),
			"MoveSpeed": _parse_float(raw.get("MoveSpeed", "")),
			"Armor": _parse_float(raw.get("Armor", "")),
			"BaseDamage": _parse_float(raw.get("BaseDamage", "")),
			"GrowDamage": raw.get("GrowDamage", ""),
			"acttackWay": raw.get("acttackWay", ""),
			"S1(1-5)": _parse_float(raw.get("S1(1-5)", "")),
			"S2(6-10)": _parse_float(raw.get("S2(6-10)", "")),
			"S3(11-15)": _parse_float(raw.get("S3(11-15)", "")),
			"S4(16-20)": _parse_float(raw.get("S4(16-20)", "")),
			"Money": _parse_float(raw.get("Money", "")),
			"remake": raw.get("remake", ""),
			"HP_S1": _parse_float(raw.get("HP_S1", "")),
			"hp+/min": _parse_float(raw.get("hp+/min", ""))
		}
		monsters[monster_id] = monster_data
	file.close()
	print("[GameData] 怪物数据加载完成: ", monsters.size(), " 条")

## 加载Boss CSV
func _load_monster_bosses() -> void:
	var csv_path: String = "res://assets/data/monster_boss.csv"
	if not FileAccess.file_exists(csv_path):
		push_warning("[GameData] Boss数据文件不存在: " + csv_path)
		return
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开Boss数据文件: " + csv_path)
		return
	var header_line: String = file.get_line()
	var headers: PackedStringArray = _parse_csv_line(header_line)
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.strip_edges().is_empty():
			continue
		var values: PackedStringArray = _parse_csv_line(line)
		if values.size() < headers.size():
			continue
		var raw: Dictionary = {}
		for i: int in range(headers.size()):
			raw[headers[i].strip_edges()] = values[i].strip_edges()
		var boss_id: String = raw.get("BossID", "")
		if boss_id.is_empty():
			continue
		var minute: int = int(_parse_float(raw.get("Minute", "")))
		var resolved_monster_id: String = _resolve_boss_monster_id(boss_id, minute)
		var boss_data: Dictionary = {
			"BossID": boss_id,
			"NameZH": raw.get("NameZH", ""),
			"NameEN": raw.get("NameEN", ""),
			"Minute": minute,
			"behavior": raw.get("Field_15", ""),
			"monster_id": resolved_monster_id
		}
		if resolved_monster_id != boss_id:
			push_warning(
				"[GameData] BossID未在monster.csv中找到，使用兜底怪物: "
				+ boss_id + " -> " + resolved_monster_id
			)
		boss_monsters[boss_id] = boss_data
	file.close()
	print("[GameData] Boss数据加载完成: ", boss_monsters.size(), " 条")

func _resolve_boss_monster_id(boss_id: String, minute: int) -> String:
	if monsters.has(boss_id):
		return boss_id
	var fallback_id: String = String(BOSS_FALLBACK_BY_MINUTE.get(minute, ""))
	if not fallback_id.is_empty() and monsters.has(fallback_id):
		return fallback_id
	for monster_id: String in monsters.keys():
		return monster_id
	return ""
