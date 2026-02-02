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
@export var weapon_orbit_radius: float = 110.0

## 武器环绕起始角度（弧度）
var weapon_orbit_base_angle: float = 0.0

## 武器环绕朝向平滑速度
const WEAPON_ORBIT_AIM_SMOOTH: float = 6.0

## 武器环绕目标角度
var weapon_orbit_target_angle: float = 0.0

## 环绕中心偏移（运行时自动算贴图偏差后存放在这里）
var weapon_orbit_center_offset: Vector2 = Vector2.ZERO

## 首帧调试打印标记
var weapon_orbit_debug_printed: bool = false

func _refresh_weapon_orbit_center_offset() -> void:
	# 以物理碰撞体中心为基准，避免父节点缩放/贴图位移放大误差
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node and is_instance_valid(shape_node):
		weapon_orbit_center_offset = shape_node.global_position - global_position
	else:
		weapon_orbit_center_offset = Vector2.ZERO
##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var weapon_container: Node2D = $WeaponContainer
@onready var orbit_pivot: Node2D = $WeaponContainer
@onready var hurt_box: Area2D = $HurtBox
@onready var camera: Camera2D = $Camera2D

##############################################################################
# 呼吸动画
##############################################################################

## 呼吸计时
var breathe_time: float = 0.0

## 呼吸/步态节奏（静止）
## 单位：Hz
## 作用：静止时的微弱起伏节奏
## 调整范围：0.8-1.6
## 当前值：1.1
const BREATHE_IDLE_SPEED: float = 1.1

## 呼吸/步态节奏（移动）
## 单位：Hz
## 作用：移动时的步态起伏节奏
## 调整范围：2.0-4.0
## 当前值：3.2
const BREATHE_MOVE_SPEED: float = 3.2

## 静止呼吸上移幅度
## 单位：像素
## 作用：静止时轻微上移
## 调整范围：0.3-1.0
## 当前值：0.6
const BREATHE_IDLE_OFFSET: float = 0.6

## 移动步态上下抖动幅度
## 单位：像素
## 作用：移动时的轻微步态起伏（不缩放）
## 调整范围：0.6-2.0
## 当前值：1.4
const MOVE_BOB_OFFSET: float = 1.4

## 步态波形锐化
## 单位：倍率
## 作用：让移动时的起伏更像“脚步”
## 调整范围：1.0-2.0
## 当前值：1.4
const MOVE_BOB_SHARPNESS: float = 1.4

## 记录初始尺度与位置
var base_sprite_scale: Vector2 = Vector2.ONE
var base_sprite_position: Vector2 = Vector2.ZERO
var breathe_initialized: bool = false

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
	if weapon_container:
		weapon_container.position = Vector2.ZERO
		weapon_container.rotation = 0.0
		weapon_container.scale = Vector2.ONE
		orbit_pivot = weapon_container

	# 自动补偿贴图与物理中心偏移，确保武器圆心对齐可见中心
	_refresh_weapon_orbit_center_offset()

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

func _process(delta: float) -> void:
	## 呼吸动画单独更新，避免依赖物理帧
	_update_breathe(delta)

##############################################################################
# 角色数据加载
##############################################################################

## 加载角色数据（role.csv）
func load_character_data(char_id: String) -> void:
	character_id = char_id
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
		## 统一脚底对齐，避免留白导致腿被裁
		_apply_character_sprite_layout(texture, Vector2(offset_x, offset_y))
		_refresh_weapon_orbit_center_offset()
		print("[Player] 角色图加载: ", sprite_path)
	else:
		_generate_placeholder_sprite()
	_init_breathe_base()

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
	_refresh_weapon_orbit_center_offset()
	print("[Player] 使用角色占位图")
	_init_breathe_base()

## 旧版脚底偏移计算（保留备用）
func _apply_feet_offset(texture: Texture2D, base_offset: Vector2) -> Vector2:
	var img: Image = texture.get_image()
	if img == null:
		return base_offset
	var w: int = img.get_width()
	var h: int = img.get_height()
	var bottom: int = -1
	for y in range(h - 1, -1, -1):
		for x in range(w):
			var color: Color = img.get_pixel(x, y)
			if color.a > 0.01:
				bottom = y
				break
		if bottom != -1:
			break
	if bottom == -1:
		return base_offset
	var desired_bottom: float = h * 0.5
	var auto_offset_y: float = desired_bottom - float(bottom)
	return Vector2(base_offset.x, base_offset.y + auto_offset_y)

## 应用角色贴图布局（强制脚底对齐）
##
## 参数：
##   texture - 角色贴图
##   base_offset - 表内偏移（sprite_offset_x/y）
func _apply_character_sprite_layout(texture: Texture2D, base_offset: Vector2) -> void:
	if not sprite or not texture:
		return
	var img: Image = texture.get_image()
	if img == null:
		sprite.centered = true
		sprite.offset = base_offset
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var min_x: int = w
	var min_y: int = h
	var max_x: int = -1
	var max_y: int = -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.01:
				if x < min_x:
					min_x = x
				if y < min_y:
					min_y = y
				if x > max_x:
					max_x = x
				if y > max_y:
					max_y = y
	if max_x == -1:
		sprite.centered = true
		sprite.offset = base_offset
		return
	sprite.centered = false
	var scale_value: Vector2 = sprite.scale
	var min_x_px: float = float(min_x) * scale_value.x
	var max_y_px: float = float(max_y) * scale_value.y
	sprite.position = Vector2(-min_x_px, -max_y_px) + base_offset

## 记录呼吸动画基准
func _init_breathe_base() -> void:
	if not sprite:
		return
	base_sprite_scale = sprite.scale
	base_sprite_position = sprite.position
	breathe_initialized = true

## 更新呼吸动画
func _update_breathe(delta: float) -> void:
	if not breathe_initialized or not sprite:
		return
	## 移动强度（0=静止，1=全速）
	var move_speed: float = max(get_actual_move_speed(), 1.0)
	var speed_ratio: float = clamp(velocity.length() / move_speed, 0.0, 1.0)

	## 统一节奏（移动更快，静止更慢）
	var speed: float = lerp(BREATHE_IDLE_SPEED, BREATHE_MOVE_SPEED, speed_ratio)
	breathe_time += delta * speed

	if speed_ratio > 0.05:
		## 移动：只做步态起伏，不做缩放
		var step_wave: float = abs(sin(breathe_time))
		var step_centered: float = (step_wave - 0.5) * 2.0
		var step_sharp: float = sign(step_centered) * pow(abs(step_centered), MOVE_BOB_SHARPNESS)
		sprite.scale = base_sprite_scale
		sprite.position = base_sprite_position + Vector2(0.0, step_sharp * MOVE_BOB_OFFSET)
	else:
		## 静止：极弱上下呼吸
		var wave: float = sin(breathe_time)
		sprite.scale = base_sprite_scale
		sprite.position = base_sprite_position + Vector2(0.0, wave * BREATHE_IDLE_OFFSET)

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

	# 创建槽位节点，包裹武器，统一环绕位置，避免各武器原点不同导致偏移
	var slot: Node2D = Node2D.new()
	slot.name = "WeaponSlot" + str(empty_slot)
	slot.position = Vector2.ZERO
	slot.rotation = 0.0
	slot.scale = Vector2.ONE

	var weapon: Node2D = weapon_scene.instantiate()
	weapon.position = Vector2.ZERO
	weapon.rotation = 0.0
	weapon.scale = Vector2.ONE

	slot.add_child(weapon)
	if orbit_pivot:
		orbit_pivot.add_child(slot)
	else:
		weapon_container.add_child(slot)

	# 计算武器围绕玩家的角度位置（类似土豆兄弟）
	# 统计当前已装备的武器数量
	var current_weapon_count: int = 0
	for i in range(MAX_WEAPON_SLOTS):
		if not weapon_slots[i].is_empty():
			current_weapon_count += 1

	# 初始角度对齐最近敌人方向，若无敌人则朝上(0度)
	var base_angle: float = 0.0
	var nearest_enemy: Node2D = _find_nearest_in_group("enemy", global_position)
	if nearest_enemy:
		base_angle = (nearest_enemy.global_position - global_position).angle()
	var count: int = max(current_weapon_count + 1, 1)
	var angle_step: float = TAU / float(count)
	var weapon_angle: float = base_angle + angle_step * float(current_weapon_count)
	var weapon_pos: Vector2 = Vector2(
		cos(weapon_angle) * weapon_orbit_radius,
		sin(weapon_angle) * weapon_orbit_radius
	)

	slot.position = weapon_pos
	slot.rotation = 0.0
	weapon.rotation = weapon_angle
	weapon.initialize(weapon_template, weapon_data, self)

	weapon_data["slot_index"] = empty_slot
	weapon_data["scene_node"] = weapon
	weapon_data["slot_node"] = slot
	weapon_slots[empty_slot] = weapon_data

	recalculate_equipment_bonus()

	print("[Player] 装备武器: ", weapon_template.get("name_cn", weapon_data["weapon_id"]), " 槽位=", empty_slot, " 角度=", rad_to_deg(weapon_angle))
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
	# 优先移除槽位节点（包含武器本体）
	if weapon_data.has("slot_node"):
		var slot_node: Node = weapon_data["slot_node"]
		if is_instance_valid(slot_node):
			slot_node.queue_free()
	elif weapon_data.has("scene_node"):
		var weapon_node: Node = weapon_data["scene_node"]
		if is_instance_valid(weapon_node):
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
	## 限制玩家在地图边界内
	_clamp_to_map_bounds()
	_update_weapon_positions()

## 限制玩家在地图范围内
func _clamp_to_map_bounds() -> void:
	var bounds: Rect2 = GameManager.map_bounds
	if bounds.size == Vector2.ZERO:
		return
	var radius: float = 32.0
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		radius = (shape_node.shape as CircleShape2D).radius
	var min_x: float = bounds.position.x + radius
	var max_x: float = bounds.position.x + bounds.size.x - radius
	var min_y: float = bounds.position.y + radius
	var max_y: float = bounds.position.y + bounds.size.y - radius
	var clamped: Vector2 = Vector2(
		clamp(global_position.x, min_x, max_x),
		clamp(global_position.y, min_y, max_y)
	)
	if clamped != global_position:
		global_position = clamped
		velocity = Vector2.ZERO

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

func get_weapon_slot_node(slot_index: int) -> Node2D:
	if slot_index < 0 or slot_index >= MAX_WEAPON_SLOTS:
		return null
	var weapon_data: Dictionary = weapon_slots[slot_index]
	if weapon_data.has("slot_node"):
		var node: Node = weapon_data["slot_node"]
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
	if orbit_pivot == null:
		return

	# 同步容器位置/朝向，但去除父级缩放，避免非等比缩放拉扯环绕半径
	orbit_pivot.global_transform = Transform2D(global_rotation, global_position)

	var slot_nodes: Array[Node2D] = []
	var weapon_nodes: Array[Node2D] = []
	for i in range(MAX_WEAPON_SLOTS):
		var slot_node: Node2D = get_weapon_slot_node(i)
		var weapon_node: Node2D = get_weapon_node(i)
		if slot_node and is_instance_valid(slot_node) and weapon_node and is_instance_valid(weapon_node):
			slot_nodes.append(slot_node)
			weapon_nodes.append(weapon_node)

	if slot_nodes.is_empty():
		return

	# 以角色可见区域中心为圆心（sprite 的可见矩形中心），转换到容器本地坐标
	var orbit_center_local: Vector2 = Vector2.ZERO
	if sprite and is_instance_valid(sprite) and sprite.texture:
		var rect: Rect2 = sprite.get_rect() # Sprite2D 本地可见矩形
		var center_local_in_sprite: Vector2 = rect.position + rect.size * 0.5
		var center_world: Vector2 = sprite.to_global(center_local_in_sprite)
		orbit_center_local = orbit_pivot.to_local(center_world)

	# 首帧调试输出（运行时仅一次）
	if not Engine.is_editor_hint() and not weapon_orbit_debug_printed:
		var slot_pos: Vector2 = slot_nodes[0].global_position if slot_nodes.size() > 0 else Vector2.ZERO
		var weapon_pos: Vector2 = weapon_nodes[0].global_position if weapon_nodes.size() > 0 else Vector2.ZERO
		var sprite_pos: Vector2 = sprite.global_position if sprite and is_instance_valid(sprite) else Vector2.ZERO
		var coll_pos: Vector2 = Vector2.ZERO
		var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
		if shape_node and is_instance_valid(shape_node):
			coll_pos = shape_node.global_position
		print_rich("[orbit_debug] player=", global_position, " orbit_center_local=", orbit_center_local, " sprite=", sprite_pos, " collision=", coll_pos, " slot0=", slot_pos, " weapon0=", weapon_pos, " radius=", weapon_orbit_radius, " count=", slot_nodes.size())
		weapon_orbit_debug_printed = true

	# 以最近敌人方向为基角；无敌人则为0
	var base_angle: float = 0.0
	var nearest_enemy: Node2D = _find_nearest_in_group("enemy", global_position)
	if nearest_enemy:
		base_angle = (nearest_enemy.global_position - global_position).angle()

	var count: int = slot_nodes.size()

	for i in range(count):
		var angle: float = base_angle + TAU / float(count) * float(i)
		var offset: Vector2 = Vector2(
			cos(angle) * weapon_orbit_radius,
			sin(angle) * weapon_orbit_radius
		)

		# 直接在本地坐标放置，父级缩放不会放大偏移
		slot_nodes[i].position = orbit_center_local + offset
		slot_nodes[i].rotation = 0.0
		slot_nodes[i].scale = Vector2.ONE
		weapon_nodes[i].position = Vector2.ZERO
		weapon_nodes[i].scale = Vector2.ONE

		var aim_dir: Vector2 = _get_nearest_enemy_dir(slot_nodes[i].global_position)
		var allow_aim: bool = true
		if weapon_nodes[i].has_method("get_is_attacking") and weapon_nodes[i].get_is_attacking():
			allow_aim = false
		if allow_aim:
			if aim_dir != Vector2.ZERO:
				weapon_nodes[i].rotation = aim_dir.angle()
			else:
				weapon_nodes[i].rotation = angle

## 查找最近敌人方向
##
## 参数：
##   from_pos - 起点位置
## 返回：
##   最近敌人的单位方向向量（无则Vector2.ZERO）
func _get_nearest_enemy_dir(from_pos: Vector2) -> Vector2:
	var nearest: Node2D = _find_nearest_in_group("enemy", from_pos)
	if not nearest:
		nearest = _find_nearest_in_group("mine", from_pos)
	if nearest:
		return (nearest.global_position - from_pos).normalized()
	return Vector2.ZERO

func _find_nearest_in_group(group_name: String, from_pos: Vector2) -> Node2D:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for node: Node in nodes:
		if node is Node2D and is_instance_valid(node):
			var dist: float = from_pos.distance_to(node.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = node
	return nearest

## 更新武器环绕目标角度（朝向最近敌人）
##
## 返回：
##   是否存在敌人
func _update_weapon_orbit_target() -> bool:
	var nearest: Node2D = _find_nearest_in_group("enemy", global_position)
	if not nearest:
		nearest = _find_nearest_in_group("mine", global_position)
	if nearest:
		var dir: Vector2 = (nearest.global_position - global_position).normalized()
		weapon_orbit_target_angle = dir.angle()
		return true
	return false

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
