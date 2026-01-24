##############################################################################
# ElementalWeapon - 元素武器
#
# 功能说明：
# 1. 继承WeaponBase，实现元素武器的攻击逻辑
# 2. 发射元素投射物（火球、冰刺、连锁闪电等）
# 3. 支持AOE、持续区、连锁等特殊机制
# 4. 使用ElementalDamage属性
#
# 元素类型：
#   - 法术弹：直线飞行
#   - 火球：缓速+爆炸
#   - 冰刺：穿透+减速
#   - 毒镖：穿透+持续伤害
#   - 连锁闪电：自动跳跃多目标
#   - 波形扫掠：范围覆盖
#   - 持续区：定点控场
##############################################################################
extends WeaponBase
class_name ElementalWeapon

##############################################################################
# 投射物场景
##############################################################################

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/weapons/projectile.tscn")

##############################################################################
# 节点引用
##############################################################################

@onready var shoot_point: Marker2D = $ShootPoint

##############################################################################
# 投射物配置
##############################################################################

## 投射物数据
var projectile_data: Dictionary = {}

## 元素类型
var element_type: String = ""  # fire/ice/poison/lightning/shadow/acid

##############################################################################
# 初始化
##############################################################################

## 重写初始化
func initialize(template_data: Dictionary, inst_data: Dictionary, player: CharacterBody2D) -> void:
	super.initialize(template_data, inst_data, player)
	
	# 加载投射物数据
	var projectile_id: String = weapon_data.get("投射物ID（ProjectileID）", "")
	if not projectile_id.is_empty():
		projectile_data = GameData.get_projectile(projectile_id)
	
	# 解析元素类型
	_parse_element_type()
	
	# 设置发射点
	if shoot_point:
		var base_range: float = weapon_data.get("基础射程（BaseRange）", 100.0)
		shoot_point.position = Vector2(base_range * 0.1, 0)


## 解析元素类型
func _parse_element_type() -> void:
	var attack_type: String = attack_method_config.get("type", "")
	var params: Dictionary = attack_method_config.get("params", {})
	
	# 从攻击方式配置提取元素类型
	if params.has("element"):
		element_type = params["element"]
	elif "fireball" in attack_type:
		element_type = "fire"
	elif "chain_lightning" in attack_type:
		element_type = "lightning"
	else:
		element_type = "generic"


##############################################################################
# 攻击逻辑
##############################################################################

## 攻击计时器超时回调
func _on_attack_timer_timeout() -> void:
	perform_attack()


## 执行攻击
func perform_attack() -> void:
	if not shoot_point:
		return
	
	# 朝向鼠标
	_rotate_to_target()
	
	var attack_type: String = attack_method_config.get("type", "")
	
	match attack_type:
		"elemental_spell", "elemental_fireball":
			# 法术弹/火球
			_shoot_spell()
		
		"elemental_chain_lightning":
			# 连锁闪电
			_shoot_chain_lightning()
		
		"elemental_wave":
			# 波形扫掠
			_shoot_wave()
		
		"elemental_area":
			# 持续区
			_create_area_effect()
		
		"elemental_spray":
			# 喷射
			_shoot_spray()
		
		_:
			# 默认法术弹
			_shoot_spell()
	
	weapon_attacked.emit()


##############################################################################
# 发射方式
##############################################################################

## 发射法术弹
func _shoot_spell() -> void:
	_spawn_elemental_projectile(Vector2.RIGHT.rotated(rotation))


## 发射连锁闪电
func _shoot_chain_lightning() -> void:
	# 连锁闪电需要特殊处理
	# 先找到最近的敌人
	var nearest_enemy: Node2D = _find_nearest_enemy()
	
	if not nearest_enemy:
		return
	
	# 直接对最近的敌人造成伤害，然后跳跃
	var damage: float = calculate_damage()
	_apply_chain_lightning(nearest_enemy, damage, 3)  # 最多跳3次


## 连锁闪电递归
## 参数：
##   target - 当前目标
##   damage - 当前伤害
##   remaining_jumps - 剩余跳跃次数
func _apply_chain_lightning(target: Node2D, damage: float, remaining_jumps: int) -> void:
	if not target or not is_instance_valid(target):
		return
	
	# 对当前目标造成伤害
	if target.has_method("take_damage"):
		target.take_damage(damage)
	
	# TODO: 播放闪电特效
	
	if remaining_jumps <= 0:
		return
	
	# 查找下一个目标（距离当前目标最近的其他敌人）
	var next_target: Node2D = _find_nearest_enemy_from(target, 300.0)
	
	if next_target:
		# 伤害衰减
		var next_damage: float = damage * 0.8
		_apply_chain_lightning(next_target, next_damage, remaining_jumps - 1)


## 发射波形扫掠
func _shoot_wave() -> void:
	# 波形是一个扇形AOE
	_create_wave_aoe()


## 发射喷射
func _shoot_spray() -> void:
	# 近距多段喷射，类似散射但更快更近
	var spray_count: int = 3
	var spread_angle: float = deg_to_rad(15)
	
	for i: int in range(spray_count):
		var angle_offset: float = -spread_angle / 2 + (spread_angle / (spray_count - 1)) * i
		var direction: Vector2 = Vector2.RIGHT.rotated(rotation + angle_offset)
		_spawn_elemental_projectile(direction)


## 创建持续区效果
func _create_area_effect() -> void:
	# 在鼠标位置创建持续区
	var mouse_pos: Vector2 = get_global_mouse_position()
	
	# TODO: 创建持续区场景
	# 这里简化为一个临时的Area2D，每隔一段时间造成伤害
	pass


## 创建波形AOE
func _create_wave_aoe() -> void:
	# 创建扇形AOE范围
	var wave_range: float = weapon_data.get("基础射程（BaseRange）", 400.0)
	var wave_angle: float = deg_to_rad(90)  # 90度扇形
	
	# TODO: 实现扇形AOE检测
	# 这里简化为圆形
	var damage: float = calculate_damage()
	_apply_aoe_damage(global_position, wave_range, damage)


##############################################################################
# 投射物生成
##############################################################################

## 生成元素投射物
func _spawn_elemental_projectile(direction: Vector2) -> Node2D:
	if not PROJECTILE_SCENE:
		return null
	
	var projectile: Node2D = PROJECTILE_SCENE.instantiate()
	
	projectile.global_position = shoot_point.global_position
	projectile.rotation = direction.angle()
	
	get_tree().current_scene.add_child(projectile)
	
	if projectile.has_method("initialize"):
		var damage: float = calculate_damage()
		var speed: float = _calculate_projectile_speed()
		var lifetime: float = _calculate_projectile_lifetime()
		var pierce_count: int = _get_pierce_count()
		
		projectile.initialize(
			damage,
			speed,
			direction,
			lifetime,
			pierce_count,
			projectile_data,
			owner_player
		)
	
	return projectile


##############################################################################
# AOE伤害
##############################################################################

## 应用AOE伤害
## 参数：
##   center - 中心位置
##   radius - 半径
##   damage - 伤害
func _apply_aoe_damage(center: Vector2, radius: float, damage: float) -> void:
	# 创建临时检测区域
	var aoe_area: Area2D = Area2D.new()
	var aoe_shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	
	circle.radius = radius
	aoe_shape.shape = circle
	aoe_area.add_child(aoe_shape)
	aoe_area.global_position = center
	aoe_area.collision_layer = 0
	aoe_area.collision_mask = CollisionLayers.ENEMY
	
	get_tree().current_scene.add_child(aoe_area)
	
	await get_tree().process_frame
	
	# 对范围内所有敌人造成伤害
	var enemies: Array[Node2D] = aoe_area.get_overlapping_bodies()
	for enemy: Node2D in enemies:
		if enemy.is_in_group("enemy") and enemy.has_method("take_damage"):
			enemy.take_damage(damage)
	
	aoe_area.queue_free()


##############################################################################
# 敌人检测
##############################################################################

## 查找最近的敌人
func _find_nearest_enemy() -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	
	if enemies.is_empty():
		return null
	
	var nearest: Node2D = null
	var nearest_dist: float = INF
	
	for enemy: Node in enemies:
		if not enemy is Node2D:
			continue
		
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy as Node2D
	
	return nearest


## 查找距离指定点最近的敌人
## 参数：
##   from_pos - 起始节点
##   max_range - 最大搜索距离
func _find_nearest_enemy_from(from_node: Node2D, max_range: float) -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	
	var nearest: Node2D = null
	var nearest_dist: float = INF
	
	for enemy: Node in enemies:
		if not enemy is Node2D:
			continue
		
		if enemy == from_node:
			continue
		
		var dist: float = from_node.global_position.distance_to(enemy.global_position)
		
		if dist > max_range:
			continue
		
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy as Node2D
	
	return nearest


##############################################################################
# 投射物参数计算
##############################################################################

## 计算投射物速度
func _calculate_projectile_speed() -> float:
	var base_speed: float = projectile_data.get("速度_px每秒（SpeedPxps）", 1000.0)
	var speed_mult: float = attack_method_config.get("params", {}).get("speed_mult", 1.0)
	return base_speed * speed_mult


## 计算投射物存活时间
func _calculate_projectile_lifetime() -> float:
	var use_weapon_range: bool = projectile_data.get("是否使用武器射程（UseWeaponRange）", false)
	
	if use_weapon_range:
		var weapon_range: float = weapon_data.get("基础射程（BaseRange）", 800.0)
		var speed: float = _calculate_projectile_speed()
		
		if speed > 0:
			return weapon_range / speed
	
	return projectile_data.get("存活时间_s（LifetimeS）", 2.0)


## 获取穿透次数
func _get_pierce_count() -> int:
	var weapon_pierce: int = int(weapon_data.get("穿透次数（PierceCount）", 0))
	if weapon_pierce > 0:
		return weapon_pierce
	
	var config_pierce: int = attack_method_config.get("params", {}).get("pierce", 0)
	return config_pierce


##############################################################################
# 旋转与朝向
##############################################################################

## 旋转武器朝向目标
func _rotate_to_target() -> void:
	if not owner_player:
		return
	
	var mouse_pos: Vector2 = get_global_mouse_position()
	var direction: Vector2 = (mouse_pos - global_position).normalized()
	rotation = direction.angle()


##############################################################################
# 物理更新
##############################################################################

func _physics_process(_delta: float) -> void:
	if owner_player:
		global_position = owner_player.global_position
