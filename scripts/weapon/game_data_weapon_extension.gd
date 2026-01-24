##############################################################################
# GameData扩展 - 武器数据加载
#
# 功能说明：
# 1. 加载weapons.csv（武器模板数据）
# 2. 加载projectiles.csv（投射物数据）
# 3. 加载summon_units.csv（召唤单位数据）
# 4. 提供武器数据查询接口
#
# 注意：此代码需要添加到现有的game_data.gd文件中
##############################################################################

## 武器数据字典
## 单位：Dictionary[String, Dictionary]
## 作用：存储所有武器的模板数据
## 数据来源：res://data/weapons.csv
var weapons: Dictionary = {}

## 投射物数据字典
## 单位：Dictionary[String, Dictionary]
## 作用：存储所有投射物的配置数据
## 数据来源：res://data/projectiles.csv
var projectiles: Dictionary = {}

## 召唤单位数据字典
## 单位：Dictionary[String, Dictionary]
## 作用：存储所有召唤单位的配置数据
## 数据来源：res://data/summon_units.csv
var summon_units: Dictionary = {}


## 在_ready()中调用此函数加载武器数据
func _load_weapon_data() -> void:
	_load_weapons()
	_load_projectiles()
	_load_summon_units()


## 加载武器数据
## 作用：从weapons.csv读取所有武器模板数据
func _load_weapons() -> void:
	var csv_path: String = "res://data/weapons.csv"
	
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 武器数据文件不存在: " + csv_path)
		return
	
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开武器数据文件: " + csv_path)
		return
	
	# 读取表头
	var header_line: String = file.get_line()
	var headers: PackedStringArray = header_line.split(",")
	
	# 读取数据行
	while not file.eof_reached():
		var line: String = file.get_line()
		
		if line.strip_edges().is_empty():
			continue
		
		var values: PackedStringArray = line.split(",")
		
		if values.size() < headers.size():
			continue
		
		# 创建武器数据字典
		var weapon_data: Dictionary = {}
		for i: int in range(headers.size()):
			var key: String = headers[i].strip_edges()
			var value: String = values[i].strip_edges()
			
			# 字符串字段
			if key in ["武器ID（WeaponID）", "显示名称（DisplayName）", "初始品质（W/B/P）（RarityStart）",
					   "武器大类（Class）", "武器子系（Family）", "套装标签（SetTags）",
					   "加成类别（BonusClass）", "投射物ID（ProjectileID）",
					   "攻击方式", "独有机制（UniqueMechanic）", "召唤单位ID（SummonUnitID）",
					   "图标ID（IconID）"]:
				weapon_data[key] = value
			# 数值字段
			else:
				if value.is_empty() or value == "None":
					weapon_data[key] = 0.0
				else:
					weapon_data[key] = float(value)
		
		# 存入字典（以武器ID为键）
		var weapon_id: String = weapon_data.get("武器ID（WeaponID）", "")
		if not weapon_id.is_empty():
			weapons[weapon_id] = weapon_data
	
	file.close()
	print("[GameData] 加载武器数据完成，共 ", weapons.size(), " 个武器")


## 加载投射物数据
## 作用：从projectiles.csv读取所有投射物配置数据
func _load_projectiles() -> void:
	var csv_path: String = "res://data/projectiles.csv"
	
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 投射物数据文件不存在: " + csv_path)
		return
	
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开投射物数据文件: " + csv_path)
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
		
		var proj_data: Dictionary = {}
		for i: int in range(headers.size()):
			var key: String = headers[i].strip_edges()
			var value: String = values[i].strip_edges()
			
			# 字符串字段
			if key in ["投射物ID（ProjectileID）", "显示名称（DisplayName）", "投射物类型（Type）",
					   "是否使用武器射程（UseWeaponRange）", "是否回旋（Return）",
					   "是否追踪（Homing）", "是否爆炸（Explode）", "命中效果ID（OnHitEffectID）",
					   "命中特效ID（VFXHitID）", "爆炸衰减曲线（FalloffCurve）",
					   "备注（Notes）", "精灵ID（SpriteID）", "需要独立精灵（NeedSprite）"]:
				proj_data[key] = value
			else:
				if value.is_empty() or value == "None":
					proj_data[key] = 0.0
				else:
					# 处理中文布尔值
					if value == "是":
						proj_data[key] = true
					elif value == "否":
						proj_data[key] = false
					else:
						proj_data[key] = float(value)
		
		var proj_id: String = proj_data.get("投射物ID（ProjectileID）", "")
		if not proj_id.is_empty():
			projectiles[proj_id] = proj_data
	
	file.close()
	print("[GameData] 加载投射物数据完成，共 ", projectiles.size(), " 个投射物")


## 加载召唤单位数据
## 作用：从summon_units.csv读取所有召唤单位配置数据
func _load_summon_units() -> void:
	var csv_path: String = "res://data/summon_units.csv"
	
	if not FileAccess.file_exists(csv_path):
		push_error("[GameData] 召唤单位数据文件不存在: " + csv_path)
		return
	
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开召唤单位数据文件: " + csv_path)
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
		
		var summon_data: Dictionary = {}
		for i: int in range(headers.size()):
			var key: String = headers[i].strip_edges()
			var value: String = values[i].strip_edges()
			
			# 字符串字段
			if key in ["召唤单位ID（SummonUnitID）", "显示名称（DisplayName）",
					   "召唤类型（SummonType）", "行为标签（BehaviorTags）",
					   "攻击模式（AttackMode）", "攻击投射物ID（ProjectileID）",
					   "生成特效ID（VFXSpawnID）", "消失特效ID（VFXDespawnID）",
					   "备注（Notes）", "精灵ID（SpriteID）"]:
				summon_data[key] = value
			else:
				if value.is_empty() or value == "None":
					summon_data[key] = 0.0
				else:
					summon_data[key] = float(value)
		
		var summon_id: String = summon_data.get("召唤单位ID（SummonUnitID）", "")
		if not summon_id.is_empty():
			summon_units[summon_id] = summon_data
	
	file.close()
	print("[GameData] 加载召唤单位数据完成，共 ", summon_units.size(), " 个召唤单位")


## 获取武器数据
## 参数：
##   weapon_id - 武器ID（如"wp_bone_spike_fist"）
## 返回：
##   武器数据字典，如果不存在则返回空字典
## 示例：
##   var data = GameData.get_weapon("wp_bone_spike_fist")
##   print(data["显示名称（DisplayName）"])  # 输出：骨刺拳（Bone Spike Fist）
func get_weapon(weapon_id: String) -> Dictionary:
	if weapon_id in weapons:
		return weapons[weapon_id]
	else:
		push_warning("[GameData] 武器不存在: " + weapon_id)
		return {}


## 获取投射物数据
## 参数：
##   projectile_id - 投射物ID（如"proj_spore_bullet"）
## 返回：
##   投射物数据字典，如果不存在则返回空字典
func get_projectile(projectile_id: String) -> Dictionary:
	if projectile_id in projectiles:
		return projectiles[projectile_id]
	else:
		push_warning("[GameData] 投射物不存在: " + projectile_id)
		return {}


## 获取召唤单位数据
## 参数：
##   summon_unit_id - 召唤单位ID（如"su_spore_eye"）
## 返回：
##   召唤单位数据字典，如果不存在则返回空字典
func get_summon_unit(summon_unit_id: String) -> Dictionary:
	if summon_unit_id in summon_units:
		return summon_units[summon_unit_id]
	else:
		push_warning("[GameData] 召唤单位不存在: " + summon_unit_id)
		return {}


## 获取所有武器ID列表
## 返回：
##   所有武器ID的数组
func get_all_weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in weapons.keys():
		ids.append(id)
	return ids


## 解析BonusClass字段
## 参数：
##   bonus_class - BonusClass字符串（如"M120", "R80"）
## 返回：
##   { "type": "M/R/S/E", "multiplier": 1.2/0.8/... }
## 示例：
##   var bonus = GameData.parse_bonus_class("M120")
##   # 返回 { "type": "M", "multiplier": 1.2 }
func parse_bonus_class(bonus_class: String) -> Dictionary:
	if bonus_class.is_empty():
		return {"type": "", "multiplier": 1.0}
	
	var result: Dictionary = {}
	result["type"] = bonus_class[0]  # 第一个字符：M/R/S/E
	
	var number_str: String = bonus_class.substr(1)  # 剩余数字部分
	if number_str.is_empty():
		result["multiplier"] = 1.0
	else:
		result["multiplier"] = float(number_str) / 100.0  # 120 -> 1.2
	
	return result


## 根据BonusClass类型获取对应的玩家属性名
## 参数：
##   bonus_type - BonusClass类型（"M"/"R"/"S"/"E"）
## 返回：
##   对应的属性名（"MeleeDamage"/"RangedDamage"/etc）
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
			push_warning("[GameData] 未知的BonusClass类型: " + bonus_type)
			return "AllDamage"
