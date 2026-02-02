##############################################################################
# Player - 玩家角色主脚本
#
# 职责概述：
# - 从 role.csv 读取角色配置，生成基础属性与 Spec 特性
# - 管理武器的装备/卸载、环绕位置与朝向
# - 处理受击、死亡、回血、升级等生命周期事件
# - 向 UI 提供角色状态和展示数据
# - 驱动基础动画（呼吸/步态）
#
# 主要数据源/信号：
# - GameData.get_character / calculate_character_stats / parse_character_spec
# - GameManager.level_up 信号 -> _on_level_up
# - Weapon / Enemy 调用 take_damage / heal
##############################################################################
extends CharacterBody2D

## 角色ID（role.csv 的 id，用于加载贴图与初始武器）
@export var character_id: String = "hero_01"


##############################################################################
# 运行时角色数据
##############################################################################

## 原始角色配置（GameData.get_character）
var character_data: Dictionary = {}
## 当前等级
var current_level: int = 1
## 基础属性（GameData.calculate_character_stats 计算）
var base_stats: Dictionary = {}
## 装备加成（来自武器/装备系统）
var equipment_bonus: Dictionary = {}
## 商店加成（来自商店购买/升级）
var shop_bonus: Dictionary = {}
## Spec 加成倍率（解析 Spec 文本后得到）
var spec_multipliers: Dictionary = {}
## 当前生命值
var current_hp: float = 0.0
## 当前经验值（本地存储，GameManager 也持有一份）—未使用，如需经验体系再启用
# var current_exp: float = 0.0

##############################################################################
# 武器系统
##############################################################################

## 武器槽列表（每槽存放武器数据字典，空槽为 {}）
var weapon_slots: Array[Dictionary] = []

## 最大武器槽数量；策划改上限时仅需调整该常量
const MAX_WEAPON_SLOTS: int = 6

## 预加载的武器场景缓存（melee/ranged/element/summon），避免战斗中反复加载
var weapon_scenes: Dictionary = {}

## 武器环绕半径（像素），控制武器围绕玩家的距离
@export var weapon_orbit_radius: float = 110.0

## 武器环绕初始角度（弧度）—当前未使用，如需起始朝向可恢复
# var weapon_orbit_base_angle: float = 0.0

## 武器环绕朝向平滑系数—当前未使用，如需插值瞄准可恢复
# const WEAPON_ORBIT_AIM_SMOOTH: float = 6.0

## 武器环绕目标角度（弧度）—当前未使用
# var weapon_orbit_target_angle: float = 0.0

## 环绕中心偏移（基于碰撞体中心与全局坐标差值，抵消父级缩放/位移）
var weapon_orbit_center_offset: Vector2 = Vector2.ZERO

## 环绕调试打印标记（仅打印一次防止刷屏）
var weapon_orbit_debug_printed: bool = false

func _refresh_weapon_orbit_center_offset() -> void:
	# 以碰撞体中心为基准计算环绕中心，抵消父节点缩放/位移造成的偏移
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node and is_instance_valid(shape_node):
		weapon_orbit_center_offset = shape_node.global_position - global_position
	else:
		weapon_orbit_center_offset = Vector2.ZERO
##############################################################################
# 节点引用
##############################################################################

## 角色主精灵节点（贴图与呼吸/步态动画作用对象）
@onready var sprite: Sprite2D = $Sprite2D
## 武器容器（所有武器槽都挂在这里，便于整体旋转/偏移）
@onready var weapon_container: Node2D = $WeaponContainer
## 武器环绕枢轴（当前与容器同一节点；后续若需独立旋转可替换为单独 Pivot）
@onready var orbit_pivot: Node2D = $WeaponContainer
## 受击区域（检测敌人/子弹命中）
@onready var hurt_box: Area2D = $HurtBox
## 跟随摄像机
@onready var camera: Camera2D = $Camera2D

##############################################################################
# 呼吸/步态动画参数
##############################################################################

## 呼吸计时（正弦相位累积，用于呼吸/步态波形）
var breathe_time: float = 0.0

## 静止呼吸频率（Hz），站立时的轻微起伏；范围建议 0.8-1.6
const BREATHE_IDLE_SPEED: float = 1.1

## 移动步态频率（Hz），行走时的起伏节奏；范围建议 1.0-4.0
const BREATHE_MOVE_SPEED: float = 3.2

## 静止呼吸的上下偏移幅度（像素）
const BREATHE_IDLE_OFFSET: float = 0.6

## 移动步态的上下摆幅（像素）
const MOVE_BOB_OFFSET: float = 1.4

## 移动步态波形锐度（0=正弦，2=方波），影响脚步的“跳跃感”
const MOVE_BOB_SHARPNESS: float = 1.4

## 精灵初始缩放（用于动画结束还原）
var base_sprite_scale: Vector2 = Vector2.ONE
## 精灵初始局部位置
var base_sprite_position: Vector2 = Vector2.ZERO
## 呼吸动画是否已完成初始化
var breathe_initialized: bool = false

##############################################################################
# 初始化
##############################################################################

## 节点就绪：初始化武器槽/预加载场景/绑定信号
func _ready() -> void:
	## 初始化武器槽列表，预留空字典便于直接下标赋值
	weapon_slots.clear()
	weapon_slots.resize(MAX_WEAPON_SLOTS)
	for i: int in range(MAX_WEAPON_SLOTS):
		weapon_slots[i] = {}

	## 预加载武器场景，避免战斗中动态加载卡顿
	_preload_weapon_scenes()
	if weapon_container:
		# 重置容器变换，确保武器环绕以玩家中心为基准
		weapon_container.position = Vector2.ZERO
		weapon_container.rotation = 0.0
		weapon_container.scale = Vector2.ONE
		orbit_pivot = weapon_container

	# 自动校准精灵与碰撞体中心差值，避免环绕偏移
	_refresh_weapon_orbit_center_offset()

	## 受击事件监听：投射物/敌人体积触碰
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	hurt_box.body_entered.connect(_on_hurt_box_body_entered)

	## 碰撞层/掩码配置：玩家自身 layer，mask 仅包含敌人/子弹/拾取/墙/门
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
	## 每帧更新呼吸/步态动画，独立于物理帧
	_update_breathe(delta)

##############################################################################
# 角色数据加载
##############################################################################

## 从 role.csv 读取角色配置，计算基础属性并装备初始武器
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

## 计算角色基础属性（不含装备/商店/Spec 加成）
func calculate_base_stats(level: int) -> void:
	base_stats = GameData.calculate_character_stats(character_id, level)

## 解析角色 Spec 文本，填充 spec_multipliers 字典
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
				print("[Player] 未识别的 Spec 条目: ", raw)
			var special: String = spec_item.get("special", "")
			if not special.is_empty():
				print("[Player] Spec 特殊处理: ", special)
			continue

		if operation == "multiply":
			spec_multipliers[stat_name] = multiplier
			print("[Player] Spec 倍率: ", stat_name, " x", multiplier)
		elif operation == "set_zero":
			spec_multipliers[stat_name] = 0.0
			print("[Player] Spec 置零: ", stat_name)
		elif operation == "special":
			print("[Player] Spec 特殊处理: ", stat_name, " - ", spec_item.get("special", ""))

## 加载角色贴图（若缺失则生成占位图），并初始化呼吸动画基准
func load_character_sprite() -> void:
	var sprite_path: String = "res://assets/PIC/role/256/" + character_id + ".png"
	if ResourceLoader.exists(sprite_path):
		var texture: Texture2D = load(sprite_path)
		sprite.texture = texture
		sprite.scale = Vector2(0.5, 0.5)
		var offset_x: float = character_data.get("sprite_offset_x", 0.0)
		var offset_y: float = character_data.get("sprite_offset_y", 0.0)
		## 统一脚底对齐，避免透明边导致脚下漂移
		_apply_character_sprite_layout(texture, Vector2(offset_x, offset_y))
		_refresh_weapon_orbit_center_offset()
		print("[Player] 角色贴图加载: ", sprite_path)
	else:
		_generate_placeholder_sprite()
	_init_breathe_base()

## 生成角色占位图（缺贴图时确保可见），同时刷新环绕中心
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

# 贴图脚底偏移计算（当前未使用，预留兜底函数）
# func _apply_feet_offset(texture: Texture2D, base_offset: Vector2) -> Vector2:
# 	var img: Image = texture.get_image()
# 	if img == null:
# 		return base_offset
# 	var w: int = img.get_width()
# 	var h: int = img.get_height()
# 	var bottom: int = -1
# 	for y in range(h - 1, -1, -1):
# 		for x in range(w):
# 			var color: Color = img.get_pixel(x, y)
# 			if color.a > 0.01:
# 				bottom = y
# 				break
# 		if bottom != -1:
# 			break
# 	if bottom == -1:
# 		return base_offset
# 	var desired_bottom: float = h * 0.5
# 	var auto_offset_y: float = desired_bottom - float(bottom)
# 	return Vector2(base_offset.x, base_offset.y + auto_offset_y)

## 应用角色贴图布局（裁剪透明边，脚底贴地）
##
## 参数:
##   texture - 角色贴图
##   base_offset - 配置的贴图偏移（sprite_offset_x/y）
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

## 记录呼吸/步态动画的初始基准
func _init_breathe_base() -> void:
	if not sprite:
		return
	base_sprite_scale = sprite.scale
	base_sprite_position = sprite.position
	breathe_initialized = true

## 按速度比例驱动呼吸/步态动画
func _update_breathe(delta: float) -> void:
	if not breathe_initialized or not sprite:
		return
	## 速度比例：0=静止，1=满速
	var move_speed: float = max(get_actual_move_speed(), 1.0)
	var speed_ratio: float = clamp(velocity.length() / move_speed, 0.0, 1.0)

	## 插值动画频率：移动越快，频率越高
	var speed: float = lerp(BREATHE_IDLE_SPEED, BREATHE_MOVE_SPEED, speed_ratio)
	breathe_time += delta * speed

	if speed_ratio > 0.05:
		## 移动：用锐化正弦模拟步伐起伏（不做缩放）
		var step_wave: float = abs(sin(breathe_time))
		var step_centered: float = (step_wave - 0.5) * 2.0
		var step_sharp: float = sign(step_centered) * pow(abs(step_centered), MOVE_BOB_SHARPNESS)
		sprite.scale = base_sprite_scale
		sprite.position = base_sprite_position + Vector2(0.0, step_sharp * MOVE_BOB_OFFSET)
	else:
		## 静止：轻微正弦呼吸
		var wave: float = sin(breathe_time)
		sprite.scale = base_sprite_scale
		sprite.position = base_sprite_position + Vector2(0.0, wave * BREATHE_IDLE_OFFSET)

## 装备初始武器（role.csv 的 initial_weapon）
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

## 获取最终属性值（基础+装备+商店+Spec 倍率）
func get_final_stat(stat_name: String) -> float:
	var base_value: float = base_stats.get(stat_name, 0.0)
	var equip_value: float = equipment_bonus.get(stat_name, 0.0)
	var shop_value: float = shop_bonus.get(stat_name, 0.0)
	var total: float = base_value + equip_value + shop_value
	if stat_name in spec_multipliers:
		total *= spec_multipliers[stat_name]
	return total

## 获取实际移动速度（基础 MoveSpeed 经 GameData 曲线转换）
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

## 向空槽添加武器：实例化场景、分配槽位、初始化武器数据
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

	# 创建武器槽节点并挂载武器实例，确保环绕位置以玩家为基准
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

	# 计算武器环绕角度：面向最近敌人并均分圆周
	# 统计当前已装备的武器数量
	var current_weapon_count: int = 0
	for i in range(MAX_WEAPON_SLOTS):
		if not weapon_slots[i].is_empty():
			current_weapon_count += 1

	# 初始角度对准最近敌人；无敌人则保持 0 弧度
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

	print("[Player] 装备武器: ", weapon_template.get("name_cn", weapon_data["weapon_id"]), " 槽=", empty_slot, " 角度=", rad_to_deg(weapon_angle))
	return true

func remove_weapon(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= MAX_WEAPON_SLOTS:
		push_error("[Player] 武器槽越界: " + str(slot_index))
		return

	if weapon_slots[slot_index].is_empty():
		push_warning("[Player] 武器槽为空: " + str(slot_index))
		return

	var weapon_data: Dictionary = weapon_slots[slot_index]
	if weapon_data.has("scene_node"):
		var weapon_node: Node = weapon_data["scene_node"]
		if is_instance_valid(weapon_node):
			if weapon_node.has_method("cleanup_all_summons"):
				weapon_node.cleanup_all_summons()
	# 优先移除槽节点（包含武器实例）
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
	print("[Player] 卸下武器: 槽=", slot_index)

## 重新计算装备加成（遍历所有武器附加属性）
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
	print("[Player] 装备加成已刷新")

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
		# TODO: 通知 EnemySpawner 重新计算生成参数
		pass

func get_shop_bonus_value(attribute: String) -> float:
	return shop_bonus.get(attribute, 0.0)

func has_shop_bonus(attribute: String) -> bool:
	return attribute in shop_bonus and shop_bonus[attribute] > 0.0

##############################################################################
# 移动与物理
##############################################################################

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	var speed: float = get_actual_move_speed()
	velocity = input_dir * speed
	# Godot 物理移动并处理碰撞
	move_and_slide()
	## 限制玩家在地图边界内
	_clamp_to_map_bounds()
	_update_weapon_positions()

## 限制玩家全局坐标在地图范围内
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

## 玩家回血
func heal(amount: float) -> void:
	var max_hp: float = get_final_stat("Health")
	current_hp += amount
	current_hp = min(current_hp, max_hp)
	print("[Player] 回复: ", amount, " 当前HP=", current_hp, "/", max_hp)

## 玩家死亡
func die() -> void:
	print("[Player] 玩家死亡")
	set_physics_process(false)

## 被敌方投射物命中（TODO: 读取子弹伤害）
func _on_hurt_box_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy_projectile"):
		# TODO: 读取投射物伤害
		pass

## 与敌人本体碰撞（TODO: 读取敌人伤害）
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

## 刷新武器环绕位置与朝向（自动居中、瞄准最近敌人）
func _update_weapon_positions() -> void:
	if orbit_pivot == null:
		return

	# 同步容器位置/朝向，但移除父级缩放，避免比例影响环绕半径
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

	# 以精灵可视区域中心为环绕中心，转换到容器本地坐标
	var orbit_center_local: Vector2 = Vector2.ZERO
	if sprite and is_instance_valid(sprite) and sprite.texture:
		var rect: Rect2 = sprite.get_rect() # Sprite2D 本地可见矩形
		var center_local_in_sprite: Vector2 = rect.position + rect.size * 0.5
		var center_world: Vector2 = sprite.to_global(center_local_in_sprite)
		orbit_center_local = orbit_pivot.to_local(center_world)

	# 首帧调试输出（仅一次，避免刷屏）
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

	# 以最近敌人方向为基准；无敌人则角度为 0
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

		# 直接使用本地坐标放置，父级缩放不会放大偏移
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

## 寻找最近敌人方向
## 参数:
##   from_pos - 基准位置
## 返回:
##   最近敌人的单位方向（若无则 Vector2.ZERO）
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

# 预留：更新武器环绕目标角度（最近敌人或矿）。当前未被调用，如需朝向插值可启用。
# func _update_weapon_orbit_target() -> bool:
# 	var nearest: Node2D = _find_nearest_in_group("enemy", global_position)
# 	if not nearest:
# 		nearest = _find_nearest_in_group("mine", global_position)
# 	if nearest:
# 		var dir: Vector2 = (nearest.global_position - global_position).normalized()
# 		weapon_orbit_target_angle = dir.angle()
# 		return true
# 	return false

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
