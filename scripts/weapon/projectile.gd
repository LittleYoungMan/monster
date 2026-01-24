##############################################################################
# Projectile - 投射物
#
# 功能说明：
# 1. 远程/元素武器发射的投射物
# 2. 支持直线飞行、穿透、爆炸、回旋等特性
# 3. 检测碰撞并造成伤害
# 4. 管理生命周期和销毁
#
# 场景结构：
#   Projectile (Area2D)
#     ├─ Sprite2D - 投射物精灵图
#     ├─ CollisionShape2D - 碰撞形状
#     └─ LifetimeTimer (Timer) - 存活计时器
##############################################################################
extends Area2D
class_name Projectile

##############################################################################
# 核心属性
##############################################################################

## 伤害值
var damage: float = 0.0

## 飞行速度（像素/秒）
var speed: float = 1000.0

## 飞行方向
var direction: Vector2 = Vector2.RIGHT

## 剩余存活时间
var lifetime: float = 2.0

## 剩余穿透次数（0表示不穿透）
var pierce_remaining: int = 0

## 投射物数据（从GameData加载）
var projectile_data: Dictionary = {}

## 拥有者玩家
var owner_player: CharacterBody2D = null

##############################################################################
# 特殊行为标志
##############################################################################

## 是否回旋模式
var is_boomerang: bool = false

## 回旋已返回
var boomerang_returning: bool = false

## 回旋最大距离
var boomerang_max_distance: float = 500.0

## 回旋起始位置
var boomerang_start_pos: Vector2 = Vector2.ZERO

## 是否抛物线轨迹
var has_arc_trajectory: bool = false

## 抛物线当前高度
var arc_height: float = 0.0

## 抛物线速度
var arc_velocity_y: float = -800.0

## 是否有牵引效果
var has_pull_effect: bool = false

## 是否会爆炸
var will_explode: bool = false

##############################################################################
# 命中记录
##############################################################################

## 已命中的敌人列表（用于穿透）
var hit_enemies: Array[Node2D] = []

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var lifetime_timer: Timer = $LifetimeTimer

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	# 设置碰撞层
	collision_layer = CollisionLayers.PLAYER_PROJECTILE
	collision_mask = CollisionLayers.combine_layers([
		CollisionLayers.ENEMY,
		CollisionLayers.WALL
	])
	
	# 连接信号
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


## 初始化投射物
## 参数：
##   dmg - 伤害值
##   spd - 速度
##   dir - 方向
##   life - 存活时间
##   pierce - 穿透次数
##   proj_data - 投射物数据
##   player - 拥有者玩家
func initialize(
	dmg: float,
	spd: float,
	dir: Vector2,
	life: float,
	pierce: int,
	proj_data: Dictionary,
	player: CharacterBody2D
) -> void:
	damage = dmg
	speed = spd
	direction = dir.normalized()
	lifetime = life
	pierce_remaining = pierce
	projectile_data = proj_data
	owner_player = player
	
	# 检查是否会爆炸
	will_explode = projectile_data.get("是否爆炸（Explode）", false)
	
	# 设置存活计时器
	if lifetime_timer:
		lifetime_timer.wait_time = lifetime
		lifetime_timer.one_shot = true
		lifetime_timer.timeout.connect(_on_lifetime_timeout)
		lifetime_timer.start()
	
	# 加载精灵图（如果有）
	_load_sprite()
	
	# 设置碰撞形状
	_setup_collision_shape()


##############################################################################
# 物理更新
##############################################################################

func _physics_process(delta: float) -> void:
	if is_boomerang:
		_update_boomerang(delta)
	elif has_arc_trajectory:
		_update_arc_trajectory(delta)
	else:
		_update_straight(delta)


## 直线飞行更新
func _update_straight(delta: float) -> void:
	global_position += direction * speed * delta


## 回旋更新
func _update_boomerang(delta: float) -> void:
	if not boomerang_returning:
		# 向前飞行
		global_position += direction * speed * delta
		
		# 检查是否到达最大距离
		var distance: float = global_position.distance_to(boomerang_start_pos)
		if distance >= boomerang_max_distance:
			boomerang_returning = true
	else:
		# 返回玩家
		if owner_player:
			var to_player: Vector2 = (owner_player.global_position - global_position).normalized()
			global_position += to_player * speed * delta
			
			# 检查是否返回到玩家
			if global_position.distance_to(owner_player.global_position) < 50.0:
				_destroy()


## 抛物线轨迹更新
func _update_arc_trajectory(delta: float) -> void:
	# 水平移动
	global_position += direction * speed * delta
	
	# 垂直移动（模拟重力）
	arc_velocity_y += 2000.0 * delta  # 重力加速度
	arc_height += arc_velocity_y * delta
	
	# 更新Y坐标
	position.y += arc_velocity_y * delta
	
	# 落地检测
	if arc_height >= 0:
		_on_hit_ground()


##############################################################################
# 碰撞检测
##############################################################################

## Area碰撞（敌人HurtBox）
func _on_area_entered(area: Area2D) -> void:
	if area.get_parent() and area.get_parent().is_in_group("enemy"):
		var enemy: Node2D = area.get_parent()
		_hit_enemy(enemy)


## Body碰撞（敌人本体或墙）
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		_hit_enemy(body)
	elif body.is_in_group("wall"):
		_hit_wall()


##############################################################################
# 命中处理
##############################################################################

## 命中敌人
func _hit_enemy(enemy: Node2D) -> void:
	# 检查是否已命中过此敌人（穿透时避免重复）
	if enemy in hit_enemies:
		return
	
	# 记录命中
	hit_enemies.append(enemy)
	
	# 造成伤害
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)
	
	# 应用牵引效果
	if has_pull_effect and owner_player:
		var pull_direction: Vector2 = (owner_player.global_position - enemy.global_position).normalized()
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(pull_direction * 300.0)
	
	# 处理穿透
	if pierce_remaining > 0:
		pierce_remaining -= 1
		
		if pierce_remaining <= 0:
			# 穿透次数用尽
			if will_explode:
				_trigger_explosion()
			else:
				_destroy()
	else:
		# 不穿透，直接销毁或爆炸
		if will_explode:
			_trigger_explosion()
		else:
			_destroy()


## 命中墙壁
func _hit_wall() -> void:
	if will_explode:
		_trigger_explosion()
	else:
		_destroy()


## 落地（抛物线）
func _on_hit_ground() -> void:
	if will_explode:
		_trigger_explosion()
	else:
		_destroy()


##############################################################################
# 爆炸
##############################################################################

## 触发爆炸
func _trigger_explosion() -> void:
	var explosion_radius: float = projectile_data.get("爆炸半径_px（ExplodeRadiusPx）", 100.0)
	
	if explosion_radius <= 0:
		_destroy()
		return
	
	# 创建爆炸检测区域
	var explosion_area: Area2D = Area2D.new()
	var explosion_shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	
	circle.radius = explosion_radius
	explosion_shape.shape = circle
	explosion_area.add_child(explosion_shape)
	explosion_area.global_position = global_position
	explosion_area.collision_layer = 0
	explosion_area.collision_mask = CollisionLayers.ENEMY
	
	get_tree().current_scene.add_child(explosion_area)
	
	# 等待一帧
	await get_tree().process_frame
	
	# 计算爆炸伤害（中心到边缘递减）
	var center_dmg_mult: float = projectile_data.get("中心伤害倍率（CenterDmgMul）", 1.0)
	var edge_dmg_mult: float = projectile_data.get("边缘伤害倍率（EdgeDmgMul）", 0.5)
	
	var enemies: Array[Node2D] = explosion_area.get_overlapping_bodies()
	for enemy: Node2D in enemies:
		if not enemy.is_in_group("enemy"):
			continue
		
		# 计算距离比例
		var distance: float = global_position.distance_to(enemy.global_position)
		var distance_ratio: float = distance / explosion_radius
		
		# 线性插值伤害倍率
		var dmg_mult: float = lerp(center_dmg_mult, edge_dmg_mult, distance_ratio)
		var explosion_damage: float = damage * dmg_mult
		
		if enemy.has_method("take_damage"):
			enemy.take_damage(explosion_damage)
	
	# 清理爆炸区域
	explosion_area.queue_free()
	
	# TODO: 播放爆炸特效和音效
	
	_destroy()


##############################################################################
# 特殊模式设置
##############################################################################

## 设置回旋模式
func set_boomerang_mode(enabled: bool) -> void:
	is_boomerang = enabled
	if enabled:
		boomerang_start_pos = global_position


## 设置抛物线轨迹
func set_arc_trajectory(enabled: bool) -> void:
	has_arc_trajectory = enabled


## 设置牵引效果
func set_pull_effect(enabled: bool) -> void:
	has_pull_effect = enabled


##############################################################################
# 精灵图和碰撞
##############################################################################

## 加载精灵图
func _load_sprite() -> void:
	if not sprite:
		return
	
	var sprite_id: String = projectile_data.get("精灵ID（SpriteID）", "")
	if sprite_id.is_empty():
		# 使用占位图
		_create_placeholder_sprite()
		return
	
	var sprite_path: String = "res://assets/PIC/wuqi/VFX/256/" + sprite_id + ".png"
	
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		
		# 设置缩放
		var target_size: float = projectile_data.get("目标显示尺寸px（TargetSizePx）", 16.0)
		var master_size: float = projectile_data.get("母版尺寸px（MasterSizePx）", 256.0)
		var scale_factor: float = target_size / master_size
		sprite.scale = Vector2(scale_factor, scale_factor)
	else:
		_create_placeholder_sprite()


## 创建占位精灵图
func _create_placeholder_sprite() -> void:
	# 创建简单的彩色方块
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.8, 0.2, 1.0))  # 黄色
	
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = texture


## 设置碰撞形状
func _setup_collision_shape() -> void:
	if not collision_shape:
		return
	
	var hit_radius: float = projectile_data.get("命中半径_px（HitRadiusPx）", 4.0)
	
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = hit_radius
	collision_shape.shape = shape


##############################################################################
# 生命周期
##############################################################################

## 存活时间结束
func _on_lifetime_timeout() -> void:
	if will_explode:
		_trigger_explosion()
	else:
		_destroy()


## 销毁投射物
func _destroy() -> void:
	queue_free()
