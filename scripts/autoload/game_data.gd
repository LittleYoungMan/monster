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

##############################################################################
# 生命周期回调
##############################################################################

func _ready() -> void:
	print("[GameData] 开始加载数据...")
	_load_characters()
	_load_weapon_data()
	_load_monsters()
	_load_monster_bosses()
	print("[GameData] 数据加载完成!")
	print("  - 角色数量: ", characters.size())
	print("  - 武器数量: ", weapons.size())
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
		"生命回复": "HealthRegen",
		"吸血": "Lifesteal",
		"全伤害": "AllDamage",
		"暴击率": "CritRate",
		"暴击伤害": "CritDamage"
	}

	var lines: PackedStringArray = spec_text.split("\n")

	for line: String in lines:
		var trimmed_line: String = line.strip_edges()
		if trimmed_line.is_empty():
			continue

		var spec_item: Dictionary = {}
		var found_stat: bool = false
		for keyword: String in keyword_map.keys():
			if keyword in trimmed_line:
				spec_item["stat"] = keyword_map[keyword]
				found_stat = true
				break

		## 特殊文本规则解析
		if not found_stat:
			if ("移速" in trimmed_line and "伤害" in trimmed_line):
				spec_item["stat"] = "MoveSpeed"
				spec_item["special"] = "speed_to_damage"
				spec_item["multiplier"] = 1.0
				spec_item["operation"] = "special"
				results.append(spec_item)
				continue
			elif "敌人数量" in trimmed_line:
				spec_item["stat"] = "EnemyCount"
				spec_item["special"] = "spawn_pressure"
				if "1.5倍" in trimmed_line:
					spec_item["multiplier"] = 1.5
				spec_item["operation"] = "special"
				results.append(spec_item)
				continue
			else:
				spec_item["raw"] = trimmed_line
				results.append(spec_item)
				continue

		## 解析倍率/操作符
		if "*2" in trimmed_line or "×2" in trimmed_line:
			spec_item["multiplier"] = 2.0
			spec_item["operation"] = "multiply"
		elif "/2" in trimmed_line:
			spec_item["multiplier"] = 0.5
			spec_item["operation"] = "multiply"
		elif "*0" in trimmed_line or "×0" in trimmed_line:
			spec_item["multiplier"] = 0.0
			spec_item["operation"] = "set_zero"
		elif "*1.5" in trimmed_line or "1.5倍" in trimmed_line:
			spec_item["multiplier"] = 1.5
			spec_item["operation"] = "multiply"
		else:
			spec_item["multiplier"] = 1.0
			spec_item["operation"] = "none"

		results.append(spec_item)

	return results

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
	for boss_id: String in boss_monsters.keys():
		var data: Dictionary = boss_monsters[boss_id]
		if int(data.get("Minute", -1)) == minute:
			return boss_id
	return ""

## 判断怪物是否为Boss
func is_boss(monster_id: String) -> bool:
	return monster_id in boss_monsters

##############################################################################
# 商店卡牌（预留）
##############################################################################

func _load_shop_cards() -> void:
	# TODO: 实现商店卡牌读取
	pass

func get_shop_card(card_id: String) -> Dictionary:
	# TODO: 实现商店卡牌查询
	return {}

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
			"sprite_id": _get_raw_first(raw, ["SpriteID", "贴图ID", "精灵ID"], "")
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
		var boss_data: Dictionary = {
			"BossID": boss_id,
			"NameZH": raw.get("NameZH", ""),
			"NameEN": raw.get("NameEN", ""),
			"Minute": int(_parse_float(raw.get("Minute", ""))),
			"behavior": raw.get("Field_15", "")
		}
		boss_monsters[boss_id] = boss_data
	file.close()
	print("[GameData] Boss数据加载完成: ", boss_monsters.size(), " 条")
