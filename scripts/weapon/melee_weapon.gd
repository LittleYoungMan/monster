##############################################################################
# MeleeWeapon - 近战武器
#
# 功能说明：
# 1. 继承WeaponBase，实现近战武器的攻击逻辑
# 2. 支持挥击（30°/45°/60°）和垂直攻击
# 3. 支持穿透、击退、爆炸等独有机制
# 4. 使用Area2D进行范围伤害检测
#
# 场景结构：
#   MeleeWeapon (Node2D)
#     ├─ AttackArea (Area2D) - 攻击范围检测
#     │   └─ CollisionShape2D
#     └─ AttackTimer (Timer) - 攻击冷却
##############################################################################
extends WeaponBase
class_name MeleeWeapon

##############################################################################
# 节点引用
##############################################################################

## 攻击范围检测区域
@onready var attack_area: Area2D = $AttackArea

## 攻击范围碰撞形状
@onready var attack_collision: CollisionShape2D = $AttackArea/CollisionShape2D

##############################################################################
# 攻击状态
##############################################################################

## 连击计数器（用于"第N击"机制）
var combo_counter: int = 0

## 最大连击数
var max_combo: int = 3

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	# 设置碰撞层
	if attack_area:
		attack_area.collision_layer = 0
		attack_area.collision_mask = CollisionLayers.ENEMY


## 初始化武器（重写父类方法）
func initialize(template_data: Dictionary, inst_data: Dictionary, player: CharacterBody2D) -> void:
	super.initialize(template_data, inst_data, player)
	
	# 根据攻击方式配置攻击范围
	_setup_attack_area()


##############################################################################
# 攻击范围配置
##############################################################################

## 配置攻击范围
## 作用：根据攻击方式设置攻击范围的形状和大小
func _setup_attack_area() -> void:
	if not attack_collision:
		return
	
	var attack_type: String = attack_method_config.get("type", "")
	var base_range: float = weapon_data.get("基础射程（BaseRange）", 100.0)
	
	# 应用范围扩大机制
	for mechanic: Dictionary in unique_mechanics:
		if mechanic.get("type", "") == "wide_range":
			base_range *= mechanic.get("params", {}).get("range_mult", 1.3)
	
	match attack_type:
		"melee_swing":
			# 挥击：使用扇形或矩形
			_setup_swing_area(base_range)
		
		"melee_vertical":
			# 垂直攻击：使用矩形
			_setup_vertical_area(base_range)
		
		"melee_thrust":
			# 突刺：使用细长矩形
			_setup_thrust_area(base_range)
		
		_:
			# 默认：圆形范围
			_setup_default_area(base_range)


## 配置挥击范围
func _setup_swing_area(range: float) -> void:
	var angle: int = attack_method_config.get("params", {}).get("angle", 90)
	
	# 使用矩形形状模拟扇形
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(range * 1.5, range)
	attack_collision.shape = shape
	
	# 偏移到前方
	attack_collision.position = Vector2(range * 0.5, 0)


## 配置垂直攻击范围
func _setup_vertical_area(range: float) -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(range * 0.6, range)
	attack_collision.shape = shape
	attack_collision.position = Vector2(range * 0.3, 0)


## 配置突刺范围
func _setup_thrust_area(range: float) -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(range, range * 0.4)
	attack_collision.shape = shape
	attack_collision.position = Vector2(range * 0.5, 0)


## 配置默认圆形范围
func _setup_default_area(range: float) -> void:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = range
	attack_collision.shape = shape


##############################################################################
# 攻击逻辑
##############################################################################

## 攻击计时器超时回调（重写父类方法）
func _on_attack_timer_timeout() -> void:
	perform_attack()


## 执行攻击
## 作用：检测攻击范围内的敌人并造成伤害
func perform_attack() -> void:
	if not attack_area:
		return
	
	# 让攻击范围朝向鼠标（或移动方向）
	_rotate_to_target()
	
	# 获取范围内的所有敌人
	var enemies: Array[Node2D] = attack_area.get_overlapping_bodies()
	
	if enemies.is_empty():
		return
	
	# 应用穿透限制
	var max_targets: int = _get_max_pierce_targets()
	var hit_count: int = 0
	
	# 对每个敌人造成伤害
	for enemy: Node2D in enemies:
		if not enemy.is_in_group("enemy"):
			continue
		
		if hit_count >= max_targets:
			break
		
		# 计算伤害
		var damage: float = calculate_damage()
		
		# 应用爆炸机制
		if _has_explode_mechanic():
			_trigger_explosion(enemy.global_position, damage)
		else:
			# 造成伤害
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage)
		
		# 应用击退
		_apply_knockback(enemy)
		
		# 应用减速
		_apply_slow(enemy)
		
		hit_count += 1
	
	# 更新连击计数
	combo_counter += 1
	if combo_counter > max_combo:
		combo_counter = 1
	
	# 发出攻击信号
	weapon_attacked.emit()


##############################################################################
# 旋转与朝向
##############################################################################

## 旋转武器朝向目标
## 作用：让攻击范围朝向鼠标或移动方向
func _rotate_to_target() -> void:
	if not owner_player:
		return
	
	# 朝向鼠标
	var mouse_pos: Vector2 = get_global_mouse_position()
	var direction: Vector2 = (mouse_pos - global_position).normalized()
	
	rotation = direction.angle()


##############################################################################
# 独有机制实现
##############################################################################

## 获取最大穿透目标数
## 返回：
##   最大可击中目标数量
func _get_max_pierce_targets() -> int:
	# 检查独有机制中的穿透设置
	for mechanic: Dictionary in unique_mechanics:
		if mechanic.get("type", "") == "pierce":
			return mechanic.get("params", {}).get("max_targets", 999)
	
	# 检查武器数据中的穿透次数
	var pierce_count: int = int(weapon_data.get("穿透次数（PierceCount）", 0))
	if pierce_count > 0:
		return pierce_count
	
	# 默认无限制
	return 999


## 检查是否有爆炸机制
func _has_explode_mechanic() -> bool:
	for mechanic: Dictionary in unique_mechanics:
		if mechanic.get("type", "") == "explode":
			return true
	return false


## 触发爆炸
## 参数：
##   center - 爆炸中心位置
##   base_damage - 基础伤害
func _trigger_explosion(center: Vector2, base_damage: float) -> void:
	var explosion_radius: float = 80.0
	
	# 从独有机制获取爆炸半径
	for mechanic: Dictionary in unique_mechanics:
		if mechanic.get("type", "") == "explode":
			explosion_radius = mechanic.get("params", {}).get("radius", 80.0)
			break
	
	# 创建临时爆炸检测区域
	var explosion_area: Area2D = Area2D.new()
	var explosion_shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	
	circle.radius = explosion_radius
	explosion_shape.shape = circle
	explosion_area.add_child(explosion_shape)
	explosion_area.global_position = center
	explosion_area.collision_layer = 0
	explosion_area.collision_mask = CollisionLayers.ENEMY
	
	get_tree().current_scene.add_child(explosion_area)
	
	# 等待一帧让碰撞检测生效
	await get_tree().process_frame
	
	# 对范围内所有敌人造成伤害
	var enemies: Array[Node2D] = explosion_area.get_overlapping_bodies()
	for enemy: Node2D in enemies:
		if enemy.is_in_group("enemy") and enemy.has_method("take_damage"):
			enemy.take_damage(base_damage)
	
	# 清理爆炸区域
	explosion_area.queue_free()
	
	# TODO: 播放爆炸特效和音效


## 应用击退效果
## 参数：
##   enemy - 目标敌人
func _apply_knockback(enemy: Node2D) -> void:
	for mechanic: Dictionary in unique_mechanics:
		if mechanic.get("type", "") != "knockback":
			continue
		
		# 检查是否是指定的连击数
		var on_hit_number: int = mechanic.get("params", {}).get("on_hit_number", 0)
		if on_hit_number > 0 and combo_counter != on_hit_number:
			continue
		
		# 应用击退
		var force: float = mechanic.get("params", {}).get("force", 350.0)
		var direction: Vector2 = (enemy.global_position - owner_player.global_position).normalized()
		
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(direction * force)


## 应用减速效果
## 参数：
##   enemy - 目标敌人
func _apply_slow(enemy: Node2D) -> void:
	for mechanic: Dictionary in unique_mechanics:
		if mechanic.get("type", "") != "slow":
			continue
		
		# 检查概率
		var chance: float = mechanic.get("params", {}).get("chance", 1.0)
		if randf() > chance:
			continue
		
		# 应用减速
		var slow_mult: float = mechanic.get("params", {}).get("slow_mult", 0.7)
		var duration: float = mechanic.get("params", {}).get("duration", 2.0)
		
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(slow_mult, duration)


##############################################################################
# 物理更新
##############################################################################

func _physics_process(_delta: float) -> void:
	# 跟随玩家位置
	if owner_player:
		global_position = owner_player.global_position
