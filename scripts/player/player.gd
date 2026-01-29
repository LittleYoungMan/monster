##############################################################################
# Player - 玩家角色
#
# 设计目的：
# - 读取角色CSV（role.csv）并计算基础属性
# - 叠加装备/商店/Spec加成
# - 管理武器槽与实例化武器
# - 处理受伤/治疗/升级
# - 提供UI显示数据
#
# CSV字段对齐（role.csv）：
# - id/name_cn/name_en/initial_weapon -> character_data
# - 基础属性字段（MeleeDamage/Armor/Health等）-> base_stats
# - Spec -> 角色特性解析（parse_character_spec）
#
# 调用链：
# - GameManager.level_up -> _on_level_up
# - Weapon/Enemy -> take_damage/heal
##############################################################################
extends CharacterBody2D

## 角色ID（role.csv中的id）
@export var character_id: String = "hero_01"


##############################################################################
# 角色数据（运行期）
##############################################################################

## 原始角色数据（GameData.get_character）
var character_data: Dictionary = {}

## 当前等级
var current_level: int = 1

## 基础属性（由GameData.calculate_character_stats计算）
var base_stats: Dictionary = {}

## 装备加成（来自武器词条/装备系统）
var equipment_bonus: Dictionary = {}

## 商店加成（来自商店购买/升级）
var shop_bonus: Dictionary = {}

## Spec倍率（角色特性解析结果）
var spec_multipliers: Dictionary = {}

## 当前生命
var current_hp: float = 0.0

## 当前经验（本脚本存储一份，GameManager也会维护）
var current_exp: float = 0.0

##############################################################################
# 武器系统
##############################################################################

## 武器槽列表（每个元素是Dictionary）
var weapon_slots: Array[Dictionary] = []

## 最大武器槽数量
const MAX_WEAPON_SLOTS: int = 6

## 武器场景缓存（melee/ranged/element/summon）
var weapon_scenes: Dictionary = {}

## 武器环绕显示半径（像素）
const WEAPON_ORBIT_RADIUS: float = 80.0

## 武器环绕起始角度（弧度）
var weapon_orbit_base_angle: float = 0.0

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var weapon_container: Node2D = $WeaponContainer
@onready var hurt_box: Area2D = $HurtBox
@onready var camera: Camera2D = $Camera2D

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	## 初始化武器槽
	weapon_slots.clear()
	weapon_slots.resize(MAX_WEAPON_SLOTS)
	for i: int in range(MAX_WEAPON_SLOTS):
		weapon_slots[i] = {}

	_preload_weapon_scenes()

	## 受击事件
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	hurt_box.body_entered.connect(_on_hurt_box_body_entered)

	## 碰撞层设置
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.combine_layers([
		CollisionLayers.ENEMY,
		CollisionLayers.ENEMY_PROJECTILE,
		CollisionLayers.PICKUP,
		CollisionLayers.WALL,
		CollisionLayers.SHOP_DOOR,
		CollisionLayers.FORGE_DOOR
	])

	print("[Player] 角色加载完成: ", character_data.get("name_cn", "未知"))

	if GameManager and GameManager.has_signal("level_up"):
		GameManager.level_up.connect(_on_level_up)

##############################################################################
# 角色数据加载
##############################################################################

## 加载角色数据（role.csv）
func load_character_data(char_id: String) -> void:
	character_data = GameData.get_character(char_id)
	if character_data.is_empty():
		push_error("[Player] 角色数据不存在: " + char_id)
		return

	calculate_base_stats(current_level)
	current_hp = get_final_stat("Health")
	parse_character_spec()
	load_character_sprite()
	equip_initial_weapon()

## 计算基础属性
func calculate_base_stats(level: int) -> void:
	base_stats = GameData.calculate_character_stats(character_id, level)

## 解析角色Spec文本
func parse_character_spec() -> void:
	var spec_text: String = character_data.get("Spec", "")
	if spec_text.is_empty():
		return

	var parsed_specs: Array = GameData.parse_character_spec(spec_text)
	if parsed_specs.is_empty():
		return

	for spec_item: Dictionary in parsed_specs:
		var stat_name: String = spec_item.get("stat", "")
		var multiplier: float = spec_item.get("multiplier", 1.0)
		var operation: String = spec_item.get("operation", "none")

		if stat_name.is_empty():
			var raw: String = spec_item.get("raw", "")
			if not raw.is_empty():
				print("[Player] 未识别Spec: ", raw)
			var special: String = spec_item.get("special", "")
			if not special.is_empty():
				print("[Player] Spec特殊: ", special)
			continue

		if operation == "multiply":
			spec_multipliers[stat_name] = multiplier
			print("[Player] Spec倍率: ", stat_name, " x", multiplier)
		elif operation == "set_zero":
			spec_multipliers[stat_name] = 0.0
			print("[Player] Spec清零: ", stat_name)
		elif operation == "special":
			print("[Player] Spec特殊处理: ", stat_name, " - ", spec_item.get("special", ""))

## 加载角色图
func load_character_sprite() -> void:
	var sprite_path: String = "res://assets/PIC/role/256/" + character_id + ".png"
	if ResourceLoader.exists(sprite_path):
		var texture: Texture2D = load(sprite_path)
		sprite.texture = texture
		sprite.scale = Vector2(0.5, 0.5)
		var offset_x: float = character_data.get("sprite_offset_x", 0.0)
		var offset_y: float = character_data.get("sprite_offset_y", 0.0)
		sprite.offset = Vector2(offset_x, offset_y)
		print("[Player] 角色图加载: ", sprite_path)
	else:
		_generate_placeholder_sprite()

## 角色占位图
func _generate_placeholder_sprite() -> void:
	var img: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var hash_value: int = character_id.hash()
	var r: float = float((hash_value >> 16) & 0xFF) / 255.0
	var g: float = float((hash_value >> 8) & 0xFF) / 255.0
	var b: float = float(hash_value & 0xFF) / 255.0
	img.fill(Color(r, g, b, 1.0))
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.scale = Vector2(1.0, 1.0)
	print("[Player] 使用角色占位图")

## 初始武器装备（role.csv的initial_weapon）
func equip_initial_weapon() -> void:
	var weapon_id: String = character_data.get("initial_weapon", "")
	if weapon_id.is_empty():
		print("[Player] 初始武器为空")
		return

	var initial_weapon: Dictionary = {
		"weapon_id": weapon_id,
		"quality": "white",
		"attributes": [],
		"slot_index": -1
	}

	if add_weapon(initial_weapon):
		print("[Player] 装备初始武器: ", weapon_id)
	else:
		push_error("[Player] 初始武器装备失败: " + weapon_id)

##############################################################################
# 属性获取
##############################################################################

## 获取最终属性（基础+装备+商店+Spec倍率）
func get_final_stat(stat_name: String) -> float:
	var base_value: float = base_stats.get(stat_name, 0.0)
	var equip_value: float = equipment_bonus.get(stat_name, 0.0)
	var shop_value: float = shop_bonus.get(stat_name, 0.0)
	var total: float = base_value + equip_value + shop_value
	if stat_name in spec_multipliers:
		total *= spec_multipliers[stat_name]
	return total

## 获取实际移速（基础移速 * 曲线倍率）
func get_actual_move_speed() -> float:
	var move_speed_stat: float = get_final_stat("MoveSpeed")
	var mult: float = GameData.calculate_move_speed_mult(move_speed_stat)
	return GameData.BASE_MOVE_SPEED * mult

## 获取护甲减伤比例
func get_armor_dr() -> float:
	var armor: float = get_final_stat("Armor")
	return GameData.calculate_armor_dr(armor)

##############################################################################
# 武器管理
##############################################################################

func add_weapon(weapon_data: Dictionary) -> bool:
	var empty_slot: int = _find_empty_weapon_slot()
	if empty_slot == -1:
		push_warning("[Player] 武器槽已满")
		return false

	var weapon_template: Dictionary = GameData.get_weapon(weapon_data["weapon_id"])
	if weapon_template.is_empty():
		push_error("[Player] 武器模板不存在: " + weapon_data["weapon_id"])
		return false

	var weapon_class: String = _get_weapon_class(weapon_template)
	var weapon_scene: PackedScene = weapon_scenes.get(weapon_class)
	if not weapon_scene:
		push_error("[Player] 未找到武器场景: " + weapon_class)
		return false

	var weapon: Node2D = weapon_scene.instantiate()
	weapon_container.add_child(weapon)
	weapon.initialize(weapon_template, weapon_data, self)

	weapon_data["slot_index"] = empty_slot
	weapon_data["scene_node"] = weapon
	weapon_slots[empty_slot] = weapon_data

	recalculate_equipment_bonus()

	print("[Player] 装备武器: ", weapon_template.get("name_cn", weapon_data["weapon_id"]), " 槽位=", empty_slot)
	return true

func remove_weapon(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= MAX_WEAPON_SLOTS:
		push_error("[Player] 槽位越界: " + str(slot_index))
		return

	if weapon_slots[slot_index].is_empty():
		push_warning("[Player] 槽位为空: " + str(slot_index))
		return

	var weapon_data: Dictionary = weapon_slots[slot_index]
	if weapon_data.has("scene_node"):
		var weapon_node: Node = weapon_data["scene_node"]
		if is_instance_valid(weapon_node):
			if weapon_node.has_method("cleanup_all_summons"):
				weapon_node.cleanup_all_summons()
			weapon_node.queue_free()

	weapon_slots[slot_index] = {}
	recalculate_equipment_bonus()
	print("[Player] 卸下武器: 槽位=", slot_index)

## 重新计算装备加成
func recalculate_equipment_bonus() -> void:
	equipment_bonus.clear()
	for weapon_data: Dictionary in weapon_slots:
		if weapon_data.is_empty():
			continue
		var attributes: Array = weapon_data.get("attributes", [])
		for attr: Dictionary in attributes:
			var attr_type: String = attr.get("type", "")
			var attr_value: float = attr.get("value", 0.0)
			if attr_type.is_empty():
				continue
			if attr_type not in equipment_bonus:
				equipment_bonus[attr_type] = 0.0
			equipment_bonus[attr_type] += attr_value
	print("[Player] 装备加成已重算")

##############################################################################
# 商店加成
##############################################################################

func add_shop_bonus(attribute: String, value: float) -> void:
	if attribute not in shop_bonus:
		shop_bonus[attribute] = 0.0
	shop_bonus[attribute] += value
	print("[Player] 商店加成: ", attribute, " +", value)

	update_all_weapons()
	if attribute.begins_with("Enemy"):
		# TODO: 通知EnemySpawner刷新参数
		pass

func get_shop_bonus_value(attribute: String) -> float:
	return shop_bonus.get(attribute, 0.0)

func has_shop_bonus(attribute: String) -> bool:
	return attribute in shop_bonus and shop_bonus[attribute] > 0.0

##############################################################################
# 移动与战斗
##############################################################################

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	var speed: float = get_actual_move_speed()
	velocity = input_dir * speed
	move_and_slide()
	_update_weapon_positions()

## 玩家受伤入口
func take_damage(damage: float) -> void:
	var dodge_chance: float = get_final_stat("Dodge")
	if randf() * 100.0 < dodge_chance:
		print("[Player] 闪避成功!")
		return

	var dr: float = get_armor_dr()
	var actual_damage: float = damage * (1.0 - dr)
	current_hp -= actual_damage
	current_hp = max(current_hp, 0.0)
	print("[Player] 受到伤害: ", actual_damage, " 当前HP=", current_hp)
	if current_hp <= 0.0:
		die()

## 玩家治疗
func heal(amount: float) -> void:
	var max_hp: float = get_final_stat("Health")
	current_hp += amount
	current_hp = min(current_hp, max_hp)
	print("[Player] 治疗: ", amount, " 当前HP=", current_hp, "/", max_hp)

## 玩家死亡
func die() -> void:
	print("[Player] 玩家死亡")
	set_physics_process(false)

## 被敌人投射物命中（TODO：读取投射物伤害）
func _on_hurt_box_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy_projectile"):
		# TODO: 读取投射物伤害
		pass

## 与敌人碰撞（TODO：读取敌人伤害）
func _on_hurt_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		# TODO: 读取敌人伤害
		pass

##############################################################################
# 升级
##############################################################################

func level_up() -> void:
	current_level += 1
	calculate_base_stats(current_level)
	current_hp = get_final_stat("Health")
	print("[Player] 升级! 当前等级=", current_level)

##############################################################################
# UI显示
##############################################################################

func get_pickup_range() -> float:
	return get_final_stat("PickupRange")

func get_display_stats() -> Dictionary:
	var display: Dictionary = {}
	display[Localization.tr_text("Health")] = str(int(current_hp)) + "/" + str(int(get_final_stat("Health")))
	display[Localization.tr_text("Armor")] = str(int(get_final_stat("Armor"))) + " (" + str(int(get_armor_dr() * 100)) + "%减伤)"
	display[Localization.tr_text("MoveSpeed")] = str(int(get_actual_move_speed())) + " px/s"
	display[Localization.tr_text("Dodge")] = str(int(get_final_stat("Dodge"))) + "%"

	display[Localization.tr_text("MeleeDamage")] = str(int(get_final_stat("MeleeDamage")))
	display[Localization.tr_text("RangedDamage")] = str(int(get_final_stat("RangedDamage")))
	display[Localization.tr_text("ElementalDamage")] = str(int(get_final_stat("ElementalDamage")))
	display[Localization.tr_text("SummonDamage")] = str(int(get_final_stat("SummonDamage")))
	display[Localization.tr_text("AllDamage")] = str(int(get_final_stat("AllDamage"))) + "%"

	display[Localization.tr_text("CritRate")] = str(int(get_final_stat("CritRate"))) + "%"
	display[Localization.tr_text("CritDamage")] = str(int(get_final_stat("CritDamage"))) + "%"
	display[Localization.tr_text("Cooldown")] = str(int(get_final_stat("Cooldown"))) + "%"
	display[Localization.tr_text("Range")] = str(int(get_final_stat("Range")))
	display[Localization.tr_text("PickupRange")] = str(int(get_pickup_range()))
	return display

func get_display_stats_en() -> Dictionary:
	var prev_lang: String = Localization.get_current_language()
	Localization.set_language("en")
	var display: Dictionary = get_display_stats()
	Localization.set_language(prev_lang)
	return display

##############################################################################
# 武器辅助
##############################################################################

func _preload_weapon_scenes() -> void:
	weapon_scenes["melee"] = load("res://scenes/weapons/melee_weapon.tscn")
	weapon_scenes["ranged"] = load("res://scenes/weapons/ranged_weapon.tscn")
	weapon_scenes["element"] = load("res://scenes/weapons/elemental_weapon.tscn")
	weapon_scenes["summon"] = load("res://scenes/weapons/summon_weapon.tscn")
	print("[Player] 武器场景预加载完成")

func _find_empty_weapon_slot() -> int:
	for i in range(MAX_WEAPON_SLOTS):
		if weapon_slots[i].is_empty():
			return i
	return -1

func _get_weapon_class(weapon_template: Dictionary) -> String:
	var summon_id: String = weapon_template.get("summon_unit_id", "")
	if not summon_id.is_empty():
		return "summon"

	var projectile_id: String = weapon_template.get("projectile_id", "")
	var bonus_class_raw: String = weapon_template.get("bonus_class_raw", weapon_template.get("bonus_class", ""))
	var bonus_prefix: String = bonus_class_raw.left(1)

	if not projectile_id.is_empty():
		if bonus_prefix == "E":
			return "element"
		return "ranged"

	if bonus_prefix == "E":
		return "element"
	if bonus_prefix == "R":
		return "ranged"
	if bonus_prefix == "S":
		return "summon"

	return "melee"

func replace_weapon(slot_index: int, new_weapon_data: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= MAX_WEAPON_SLOTS:
		return false
	remove_weapon(slot_index)
	return add_weapon(new_weapon_data)

func get_weapon_node(slot_index: int) -> Node2D:
	if slot_index < 0 or slot_index >= MAX_WEAPON_SLOTS:
		return null
	var weapon_data: Dictionary = weapon_slots[slot_index]
	if weapon_data.has("scene_node"):
		var node: Node = weapon_data["scene_node"]
		if is_instance_valid(node) and node is Node2D:
			return node
	return null

func update_all_weapons() -> void:
	for i in range(MAX_WEAPON_SLOTS):
		var weapon_node: Node2D = get_weapon_node(i)
		if weapon_node and weapon_node.has_method("update_cooldown"):
			weapon_node.update_cooldown()
	_update_weapon_positions()

## 让武器围绕玩家显示（类似土豆兄弟）
func _update_weapon_positions() -> void:
	if weapon_container == null:
		return

	var weapon_nodes: Array[Node2D] = []
	for i in range(MAX_WEAPON_SLOTS):
		var weapon_node: Node2D = get_weapon_node(i)
		if weapon_node and is_instance_valid(weapon_node):
			weapon_nodes.append(weapon_node)

	if weapon_nodes.is_empty():
		return

	var count: int = weapon_nodes.size()
	var angle_step: float = TAU / float(count)
	for i in range(count):
		var angle: float = weapon_orbit_base_angle + angle_step * float(i)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * WEAPON_ORBIT_RADIUS
		weapon_nodes[i].position = offset
		weapon_nodes[i].rotation = angle

func get_total_dps() -> float:
	var total_dps: float = 0.0
	for i in range(MAX_WEAPON_SLOTS):
		var weapon_node: Node2D = get_weapon_node(i)
		if weapon_node and weapon_node.has_method("calculate_dps"):
			total_dps += weapon_node.calculate_dps()
	return total_dps

func _on_level_up(level: int) -> void:
	current_level = level
	calculate_base_stats(level)
	current_hp = get_final_stat("Health")
	update_all_weapons()
	print("[Player] 同步等级: Lv.", level)
