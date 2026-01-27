# GameData怪物加载补丁
# 将以下代码添加到 game_data.gd 中

##############################################################################
# 在_ready()函数中添加这行：
##############################################################################
func _ready() -> void:
	print("[GameData] 开始加载数据...")
	
	# 加载角色数据
	_load_characters()
	
	# 【新增】加载怪物数据
	_load_monsters()
	
	print("[GameData] 数据加载完成!")
	print("  - 角色数量: ", characters.size())
	print("  - 怪物数量: ", monsters.size())  # 【新增】

##############################################################################
# 添加以下函数：
##############################################################################

## 加载怪物数据
## 作用：从CSV文件读取所有怪物数据
## 数据来源：res://data/monsters.csv（需要从Excel导出）
func _load_monsters() -> void:
	var csv_path: String = "res://data/monsters.csv"
	
	# 检查文件是否存在
	if not FileAccess.file_exists(csv_path):
		push_warning("[GameData] 怪物数据文件不存在: " + csv_path)
		push_warning("[GameData] 请先将怪物final.xlsx导出为CSV")
		return
	
	# 打开CSV文件
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("[GameData] 无法打开怪物数据文件: " + csv_path)
		return
	
	# 读取表头
	var header_line: String = file.get_line()
	var headers: PackedStringArray = header_line.split(",")
	
	# 读取数据行
	while not file.eof_reached():
		var line: String = file.get_line()
		
		# 跳过空行
		if line.strip_edges().is_empty():
			continue
		
		var values: PackedStringArray = line.split(",")
		
		# 跳过不完整的行
		if values.size() < headers.size():
			continue
		
		# 创建怪物数据字典
		var monster_data: Dictionary = {}
		for i: int in range(headers.size()):
			var key: String = headers[i].strip_edges()
			var value: String = values[i].strip_edges()
			
			# 根据字段名判断数据类型
			var numeric_fields: Array[String] = [
				"MoveSpeed", "Armor", "BaseDamage", 
				"刷新权重_S1(1-5)", "刷新权重_S2(6-10)", 
				"刷新权重_S3(11-15)", "刷新权重_S4(16-20)",
				"掉落", "上限", "HP_S1", "hp+/min"
			]
			
			if key in numeric_fields:
				# 数值字段
				if value.is_empty():
					monster_data[key] = 0.0
				else:
					monster_data[key] = float(value)
			else:
				# 字符串字段
				monster_data[key] = value
		
		# 存入字典（以MonsterID为键）
		var monster_id: String = monster_data.get("MonsterID（怪物ID）", "")
		if not monster_id.is_empty():
			monsters[monster_id] = monster_data
	
	file.close()
	print("[GameData] 加载怪物数据完成，共 ", monsters.size(), " 个怪物")


## 获取怪物数据
## 参数：
##   monster_id - 怪物ID（如"M_SLM_01"）
## 返回：
##   怪物数据字典，如果不存在则返回空字典
## 示例：
##   var data = GameData.get_monster("M_SLM_01")
##   print(data["NameZH"])  # 输出：史莱姆
func get_monster(monster_id: String) -> Dictionary:
	if monster_id in monsters:
		return monsters[monster_id]
	else:
		push_warning("[GameData] 怪物不存在: " + monster_id)
		return {}


## 获取所有怪物ID列表
## 返回：
##   所有怪物ID的数组
## 示例：
##   var ids = GameData.get_all_monster_ids()  # ["M_SLM_01", "M_SPD_01", ...]
func get_all_monster_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in monsters.keys():
		ids.append(id)
	return ids


## 根据类型获取怪物ID列表
## 参数：
##   size_type - 怪物体型（"小型"/"中型"/"大型"）
## 返回：
##   符合条件的怪物ID数组
## 示例：
##   var small_monsters = GameData.get_monsters_by_size("小型")
func get_monsters_by_size(size_type: String) -> Array[String]:
	var result: Array[String] = []
	for monster_id: String in monsters.keys():
		var data: Dictionary = monsters[monster_id]
		if data.get("Size（体型）", "") == size_type:
			result.append(monster_id)
	return result


## 获取Boss怪物ID列表（预留）
## 返回：
##   Boss怪物ID数组
## 注意：当前Excel中没有单独的Boss，可能需要手动指定
func get_boss_ids() -> Array[String]:
	# TODO: 根据实际Boss设计返回
	# 临时：返回中型怪物作为Boss
	return get_monsters_by_size("中型")
