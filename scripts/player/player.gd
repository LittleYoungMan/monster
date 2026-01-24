##############################################################################
# Player - 玩家角色脚本
#
# 功能说明：
# 1. 加载和管理角色数据
# 2. 计算角色所有属性（基础 + 装备 + 商店 + 特性权重）
# 3. 管理6个武器槽位
# 4. 处理移动和受伤
# 5. 提供给其他系统的接口
##############################################################################
extends CharacterBody2D

## 导出：角色ID
## 作用：指定要加载的角色数据
## 调整方式：在Inspector中选择
@export var character_id: String = "hero_01"

##############################################################################
# 核心数据
##############################################################################

## 角色原始数据（从CSV加载）
## 数据来源：GameData.get_character(character_id)
var character_data: Dictionary = {}

## 当前等级
## 单位：级
## 作用：影响属性成长
## 数据来源：GameManager.player_level
var current_level: int = 1

## 基础属性（基础值 + 成长值 × (等级-1)）
## 单位：各属性对应单位
## 作用：角色的基础属性，不包含装备和商店加成
## 数据来源：calculate_base_stats()
var base_stats: Dictionary = {}

## 装备加成（来自武器属性）
## 单位：各属性对应单位
## 作用：所有装备武器的属性加成总和
## 数据来源：recalculate_equipment_bonus()
var equipment_bonus: Dictionary = {}

## 商店加成（来自购买的卡牌）
## 单位：各属性对应单位
## 作用：所有购买的商店卡的属性加成总和
## 数据来源：ShopManager调用add_shop_bonus()
var shop_bonus: Dictionary = {}

## 特性权重（Spec）
## 单位：倍数字典
## 作用：角色特性对某些属性的倍率加成
## 数据来源：parse_character_spec()
## 示例：{ "MeleeDamage": 2.0 } 表示近战伤害×2
var spec_multipliers: Dictionary = {}

## 当前生命值
## 单位：点
var current_hp: float = 0.0

## 当前经验值
## 单位：点
var current_exp: float = 0.0

##############################################################################
# 武器系统
##############################################################################

## 武器槽位数组（最多6个）
## 单位：武器实例数据字典数组
## 作用：存储装备的武器数据
## 数据结构：
##   {
##     "weapon_id": "wp_xxx",
##     "quality": "blue",
##     "attributes": [...],
##     "slot_index": 0
##   }
var weapon_slots: Array[Dictionary] = []

## 武器槽位最大数量
## 单位：个
const MAX_WEAPON_SLOTS: int = 6

##############################################################################
# 节点引用
##############################################################################

## Sprite2D节点引用
@onready var sprite: Sprite2D = $Sprite2D

## WeaponContainer节点引用
@onready var weapon_container: Node2D = $WeaponContainer

## HurtBox节点引用
@onready var hurt_box: Area2D = $HurtBox

## Camera2D节点引用
@onready var camera: Camera2D = $Camera2D

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	# 初始化武器槽
	weapon_slots.clear()
	weapon_slots.resize(MAX_WEAPON_SLOTS)
	for i: int in range(MAX_WEAPON_SLOTS):
		weapon_slots[i] = {}
	
	# 加载角色数据
	load_character_data(character_id)
	
	# 连接受伤信号
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	hurt_box.body_entered.connect(_on_hurt_box_body_entered)
	
	# 设置碰撞层
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.combine_layers([
		CollisionLayers.ENEMY,
		CollisionLayers.ENEMY_PROJECTILE,
		CollisionLayers.PICKUP,
		CollisionLayers.WALL,
		CollisionLayers.SHOP_DOOR,
		CollisionLayers.FORGE_DOOR
	])
	
	print("[Player] 角色初始化完成: ", character_data.get("name_cn", "未知"))


##############################################################################
# 角色数据加载
##############################################################################

## 加载角色数据
## 参数：
##   char_id - 角色ID
## 作用：从GameData加载角色数据并初始化
func load_character_data(char_id: String) -> void:
	character_data = GameData.get_character(char_id)
	
	if character_data.is_empty():
		push_error("[Player] 角色数据不存在: " + char_id)
		return
	
	# 计算基础属性
	calculate_base_stats(current_level)
	
	# 初始化生命值
	current_hp = get_final_stat("Health")
	
	# 解析特性
	parse_character_spec()
	
	# 加载精灵图
	load_character_sprite()
	
	# 装备初始武器
	equip_initial_weapon()


## 计算基础属性（基础值 + 成长）
## 参数：
##   level - 等级
## 作用：计算该等级下的所有基础属性
func calculate_base_stats(level: int) -> void:
	base_stats = GameData.calculate_character_stats(character_id, level)


## 解析角色特性（Spec）
## 作用：解析Spec字段，生成权重倍率字典
func parse_character_spec() -> void:
	var spec_text: String = character_data.get("Spec", "")
	if spec_text.is_empty():
		return
	
	# GameData.parse_character_spec现在返回数组
	var parsed_specs: Array = GameData.parse_character_spec(spec_text)
	if parsed_specs.is_empty():
		return
	
	# 处理每个特性规则
	for spec_item: Dictionary in parsed_specs:
		var stat_name: String = spec_item.get("stat", "")
		var multiplier: float = spec_item.get("multiplier", 1.0)
		var operation: String = spec_item.get("operation", "none")
		
		if stat_name.is_empty():
			# 可能是特殊规则或无法识别的规则
			var raw: String = spec_item.get("raw", "")
			if not raw.is_empty():
				print("[Player] 特性（未识别）: ", raw)
			
			var special: String = spec_item.get("special", "")
			if not special.is_empty():
				print("[Player] 特殊特性: ", special)
			continue
		
		# 根据操作类型处理
		if operation == "multiply":
			# 倍率修改
			spec_multipliers[stat_name] = multiplier
			print("[Player] 特性生效（倍率）: ", stat_name, " × ", multiplier)
		elif operation == "set_zero":
			# 强制归零（*0）
			spec_multipliers[stat_name] = 0.0
			print("[Player] 特性生效（归零）: ", stat_name, " = 0")
		elif operation == "special":
			# 特殊规则（暂不实现，预留）
			print("[Player] 特性生效（特殊）: ", stat_name, " - ", spec_item.get("special", ""))


## 加载角色精灵图
## 作用：从assets/PIC/role/256/加载角色图片
func load_character_sprite() -> void:
	var sprite_path: String = "res://assets/PIC/role/256/" + character_id + ".png"
	
	if ResourceLoader.exists(sprite_path):
		var texture: Texture2D = load(sprite_path)
		sprite.texture = texture
		
		# 设置缩放（256px缩放到128px显示）
		sprite.scale = Vector2(0.5, 0.5)
		
		# 应用精灵图偏移（如果数据中有）
		var offset_x: float = character_data.get("sprite_offset_x", 0.0)
		var offset_y: float = character_data.get("sprite_offset_y", 0.0)
		sprite.offset = Vector2(offset_x, offset_y)
		
		print("[Player] 精灵图加载成功: ", sprite_path)
	else:
		# 生成占位方块
		_generate_placeholder_sprite()


## 生成占位精灵图
## 作用：如果没有图片资源，生成彩色方块
func _generate_placeholder_sprite() -> void:
	# 创建128×128的彩色方块
	var img: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	
	# 根据角色ID生成不同颜色
	var hash_value: int = character_id.hash()
	var r: float = float((hash_value >> 16) & 0xFF) / 255.0
	var g: float = float((hash_value >> 8) & 0xFF) / 255.0
	var b: float = float(hash_value & 0xFF) / 255.0
	
	img.fill(Color(r, g, b, 1.0))
	
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.scale = Vector2(1.0, 1.0)
	
	print("[Player] 使用占位精灵图")


## 装备初始武器
## 作用：根据character_data.initial_weapon装备武器
func equip_initial_weapon() -> void:
	var weapon_id: String = character_data.get("initial_weapon", "")
	if weapon_id.is_empty():
		print("[Player] 无初始武器")
		return
	
	# TODO: 调用武器系统创建武器实例
	# var weapon_data = WeaponManager.create_weapon_instance(weapon_id, "white")
	# add_weapon(weapon_data)
	
	print("[Player] 初始武器: ", weapon_id, " (待实现)")


##############################################################################
# 属性计算（核心）
##############################################################################

## 获取最终属性（基础 + 装备 + 商店 + 特性权重）
## 参数：
##   stat_name - 属性名（如"Health"）
## 返回：
##   最终属性值
## 公式：
##   final = (base + equipment + shop) × spec_multiplier
## 示例：
##   var health = player.get_final_stat("Health")
func get_final_stat(stat_name: String) -> float:
	var base_value: float = base_stats.get(stat_name, 0.0)
	var equip_value: float = equipment_bonus.get(stat_name, 0.0)
	var shop_value: float = shop_bonus.get(stat_name, 0.0)
	
	var total: float = base_value + equip_value + shop_value
	
	# 应用特性权重
	if stat_name in spec_multipliers:
		var multiplier: float = spec_multipliers[stat_name]
		total *= multiplier
	
	return total


## 获取实际移动速度
## 返回：
##   实际移动速度（像素/秒）
## 公式：
##   speed = BASE_SPEED × move_speed_mult
func get_actual_move_speed() -> float:
	var move_speed_stat: float = get_final_stat("MoveSpeed")
	var mult: float = GameData.calculate_move_speed_mult(move_speed_stat)
	return GameData.BASE_MOVE_SPEED * mult


## 获取实际护甲减伤率
## 返回：
##   减伤率（0.0-1.0）
func get_armor_dr() -> float:
	var armor: float = get_final_stat("Armor")
	return GameData.calculate_armor_dr(armor)


##############################################################################
# 武器管理
##############################################################################

## 添加武器到空槽位
## 参数：
##   weapon_data - 武器实例数据字典
## 返回：
##   是否成功添加（true/false）
## 作用：
##   1. 查找空槽位
##   2. 存储武器数据
##   3. 实例化武器场景节点
##   4. 重新计算装备加成
func add_weapon(weapon_data: Dictionary) -> bool:
	# 查找空槽位
	var empty_slot_index: int = -1
	for i: int in range(MAX_WEAPON_SLOTS):
		if weapon_slots[i].is_empty():
			empty_slot_index = i
			break
	
	if empty_slot_index == -1:
		push_warning("[Player] 武器槽已满，无法添加武器")
		return false
	
	# 存储武器数据
	weapon_data["slot_index"] = empty_slot_index
	weapon_slots[empty_slot_index] = weapon_data
	
	# TODO: 实例化武器场景节点
	# var weapon_scene = load("res://scenes/weapons/" + weapon_type + ".tscn")
	# var weapon_instance = weapon_scene.instantiate()
	# weapon_instance.initialize(weapon_data, self)
	# weapon_container.add_child(weapon_instance)
	
	# 重新计算装备加成
	recalculate_equipment_bonus()
	
	print("[Player] 武器已添加到槽位 ", empty_slot_index)
	return true


## 移除武器
## 参数：
##   slot_index - 槽位索引（0-5）
## 作用：
##   1. 移除槽位中的武器数据
##   2. 销毁武器场景节点
##   3. 重新计算装备加成
func remove_weapon(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= MAX_WEAPON_SLOTS:
		push_error("[Player] 无效的槽位索引: ", slot_index)
		return
	
	if weapon_slots[slot_index].is_empty():
		push_warning("[Player] 槽位 ", slot_index, " 为空")
		return
	
	# 移除数据
	var removed_weapon: Dictionary = weapon_slots[slot_index]
	weapon_slots[slot_index] = {}
	
	# TODO: 销毁武器场景节点
	# var weapon_node = weapon_container.get_child(slot_index)
	# if weapon_node:
	#     weapon_node.queue_free()
	
	# 重新计算装备加成
	recalculate_equipment_bonus()
	
	print("[Player] 武器已从槽位 ", slot_index, " 移除")


## 重新计算装备加成
## 作用：遍历所有武器槽，累加属性加成
func recalculate_equipment_bonus() -> void:
	# 清空装备加成
	equipment_bonus.clear()
	
	# 遍历所有武器槽
	for weapon_data: Dictionary in weapon_slots:
		if weapon_data.is_empty():
			continue
		
		# 获取武器属性列表
		var attributes: Array = weapon_data.get("attributes", [])
		
		# 累加属性
		for attr: Dictionary in attributes:
			var attr_type: String = attr.get("type", "")
			var attr_value: float = attr.get("value", 0.0)
			
			if attr_type.is_empty():
				continue
			
			if attr_type not in equipment_bonus:
				equipment_bonus[attr_type] = 0.0
			
			equipment_bonus[attr_type] += attr_value
	
	print("[Player] 装备加成重新计算完成")


##############################################################################
# 商店系统接口
##############################################################################

## 添加商店加成
## 参数：
##   attribute - 属性名
##   value - 加成值
## 作用：购买商店卡后，永久增加属性
func add_shop_bonus(attribute: String, value: float) -> void:
	if attribute not in shop_bonus:
		shop_bonus[attribute] = 0.0
	
	shop_bonus[attribute] += value
	
	print("[Player] 商店加成: ", attribute, " +", value)
	
	# 如果是影响怪物的属性，通知EnemySpawner
	if attribute.begins_with("Enemy"):
		# TODO: 通知EnemySpawner应用难度修正
		pass


## 获取商店加成值
## 参数：
##   attribute - 属性名
## 返回：
##   该属性的商店加成值
func get_shop_bonus_value(attribute: String) -> float:
	return shop_bonus.get(attribute, 0.0)


## 检查是否有某个商店加成
## 参数：
##   attribute - 属性名
## 返回：
##   是否有该加成
func has_shop_bonus(attribute: String) -> bool:
	return attribute in shop_bonus and shop_bonus[attribute] > 0.0


##############################################################################
# 移动与物理
##############################################################################

func _physics_process(delta: float) -> void:
	# 获取输入方向
	var input_dir: Vector2 = Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	
	# 归一化方向向量（防止斜向移动过快）
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	
	# 计算速度
	var speed: float = get_actual_move_speed()
	velocity = input_dir * speed
	
	# 移动
	move_and_slide()


##############################################################################
# 受伤与死亡
##############################################################################

## 受到伤害
## 参数：
##   damage - 原始伤害
## 作用：
##   1. 应用护甲减伤
##   2. 应用闪避判定
##   3. 扣除生命值
##   4. 检查死亡
func take_damage(damage: float) -> void:
	# 闪避判定
	var dodge_chance: float = get_final_stat("Dodge")
	if randf() * 100.0 < dodge_chance:
		print("[Player] 闪避成功!")
		return
	
	# 护甲减伤
	var dr: float = get_armor_dr()
	var actual_damage: float = damage * (1.0 - dr)
	
	# 扣除生命值
	current_hp -= actual_damage
	current_hp = max(current_hp, 0.0)
	
	print("[Player] 受到伤害: ", actual_damage, " (剩余HP: ", current_hp, ")")
	
	# TODO: 播放受伤动画/音效
	
	# 检查死亡
	if current_hp <= 0.0:
		die()


## 治疗
## 参数：
##   amount - 治疗量
func heal(amount: float) -> void:
	var max_hp: float = get_final_stat("Health")
	current_hp += amount
	current_hp = min(current_hp, max_hp)
	
	print("[Player] 治疗: ", amount, " (当前HP: ", current_hp, "/", max_hp, ")")


## 死亡
func die() -> void:
	print("[Player] 玩家死亡")
	
	# TODO: 触发游戏结束
	# GameManager.on_player_died()
	
	# 禁用移动
	set_physics_process(false)


## HurtBox碰撞信号处理（Area2D）
func _on_hurt_box_area_entered(area: Area2D) -> void:
	# 敌人投射物
	if area.is_in_group("enemy_projectile"):
		# TODO: 获取投射物伤害
		# var damage = area.get_damage()
		# take_damage(damage)
		pass


## HurtBox碰撞信号处理（Body2D）
func _on_hurt_box_body_entered(body: Node2D) -> void:
	# 敌人本体（近战攻击）
	if body.is_in_group("enemy"):
		# TODO: 获取敌人伤害
		# var damage = body.get_damage()
		# take_damage(damage)
		pass


##############################################################################
# 升级系统接口
##############################################################################

## 升级
## 作用：提升等级，重新计算基础属性
func level_up() -> void:
	current_level += 1
	calculate_base_stats(current_level)
	
	# 升级时恢复生命
	var max_hp: float = get_final_stat("Health")
	current_hp = max_hp
	
	print("[Player] 升级! 当前等级: ", current_level)


##############################################################################
# 拾取系统接口
##############################################################################

## 获取拾取范围
## 返回：
##   拾取范围（像素）
func get_pickup_range() -> float:
	return get_final_stat("PickupRange")


##############################################################################
# UI显示接口
##############################################################################

## 获取显示用属性（中文）
## 返回：
##   属性字典（键为中文名，值为显示文本）
func get_display_stats() -> Dictionary:
	var display: Dictionary = {}
	
	# 基础属性
	display[Localization.tr_text("Health")] = str(int(current_hp)) + "/" + str(int(get_final_stat("Health")))
	display[Localization.tr_text("Armor")] = str(int(get_final_stat("Armor"))) + " (" + str(int(get_armor_dr() * 100)) + "%减伤)"
	display[Localization.tr_text("MoveSpeed")] = str(int(get_actual_move_speed())) + " px/s"
	display[Localization.tr_text("Dodge")] = str(int(get_final_stat("Dodge"))) + "%"
	
	# 伤害属性
	display[Localization.tr_text("MeleeDamage")] = str(int(get_final_stat("MeleeDamage")))
	display[Localization.tr_text("RangedDamage")] = str(int(get_final_stat("RangedDamage")))
	display[Localization.tr_text("ElementalDamage")] = str(int(get_final_stat("ElementalDamage")))
	display[Localization.tr_text("SummonDamage")] = str(int(get_final_stat("SummonDamage")))
	display[Localization.tr_text("AllDamage")] = str(int(get_final_stat("AllDamage"))) + "%"
	
	# 会心属性
	display[Localization.tr_text("CritRate")] = str(int(get_final_stat("CritRate"))) + "%"
	display[Localization.tr_text("CritDamage")] = str(int(get_final_stat("CritDamage"))) + "%"
	
	# 其他属性
	display[Localization.tr_text("Cooldown")] = str(int(get_final_stat("Cooldown"))) + "%"
	display[Localization.tr_text("Range")] = str(int(get_final_stat("Range")))
	display[Localization.tr_text("PickupRange")] = str(int(get_pickup_range()))
	
	return display


## 获取显示用属性（英文）
## 返回：
##   属性字典（键为英文名，值为显示文本）
func get_display_stats_en() -> Dictionary:
	# 切换到英文
	var prev_lang: String = Localization.get_current_language()
	Localization.set_language("en")
	
	var display: Dictionary = get_display_stats()
	
	# 恢复之前的语言
	Localization.set_language(prev_lang)
	
	return display
