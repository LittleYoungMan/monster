##############################################################################
# SummonUnit - 召唤单位
#
# 功能说明：
# 1. 召唤武器生成的单位（随从/炮台/爆体）
# 2. 自动索敌和攻击
# 3. 支持跟随、固定、环绕等行为模式
# 4. 有独立的生命值和持续时间
#
# 召唤类型：
#   - 随从（Minions）：跟随玩家，自动攻击
#   - 炮台（Turrets）：固定位置，持续射击
#   - 爆体（Kamikaze）：冲锋自爆
#
# 场景结构：
#   SummonUnit (CharacterBody2D)
#     ├─ Sprite2D - 召唤物精灵图
#     ├─ CollisionShape2D - 物理碰撞
#     ├─ AttackTimer (Timer) - 攻击冷却
#     ├─ LifetimeTimer (Timer) - 存活时间
#     └─ DetectionArea (Area2D) - 敌人检测范围
##############################################################################
extends CharacterBody2D
class_name SummonUnit

##############################################################################
# 信号
##############################################################################

## 召唤物被销毁信号
signal summon_destroyed

##############################################################################
# 投射物场景（如果召唤物会发射投射物）
##############################################################################

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/weapons/projectile.tscn")

##############################################################################
# 核心数据
##############################################################################

## 召唤单位模板数据（从GameData加载）
var summon_data: Dictionary = {}

## 召唤物战斗属性（从召唤武器继承）
var combat_stats: Dictionary = {}

## 拥有者玩家
var owner_player: CharacterBody2D = null

##############################################################################
# 属性
##############################################################################

## 当前生命值
var current_hp: float = 0.0

## 最大生命值
var max_hp: float = 10.0

## 移动速度
var move_speed: float = 150.0

## 攻击范围
var attack_range: float = 300.0

## 攻击伤害
var damage: float = 10.0

## 攻击冷却
var attack_cooldown: float = 1.0

##############################################################################
# AI状态
##############################################################################

## 当前目标敌人
var current_target: Node2D = null

## 召唤类型
var summon_type: String = ""  # Minions/Turrets/Kamikaze

## 行为模式
var behavior_mode: String = ""  # follow/orbit/static/charge

## 是否固定位置（炮台）
var is_static: bool = false

## 环绕半径（如果是环绕模式）
var orbit_radius: float = 150.0

## 环绕角度
var orbit_angle: float = 0.0

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_timer: Timer = $AttackTimer
@onready var lifetime_timer: Timer = $LifetimeTimer
@onready var detection_area: Area2D = $DetectionArea

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	# 设置碰撞层
	collision_layer = 0  # 召唤物不参与物理碰撞
	collision_mask = CollisionLayers.WALL
	
	# 添加到召唤物组
	add_to_group("summon")


## 初始化召唤单位
## 参数：
##   data - 召唤单位模板数据
##   stats - 战斗属性（继承自玩家）
##   player - 拥有者玩家
func initialize(data: Dictionary, stats: Dictionary, player: CharacterBody2D) -> void:
	summon_data = data
	combat_stats = stats
	owner_player = player
	
	# 读取基础属性
	summon_type = summon_data.get("召唤类型（SummonType）", "随从_Minions")
	max_hp = summon_data.get("耐久/生命（HP）", 10.0)
	current_hp = max_hp
	move_speed = summon_data.get("移动速度_px每秒（MoveSpeedPxps）", 150.0)
	attack_range = summon_data.get("基础射程_px（BaseRangePx）", 300.0)
	attack_cooldown = summon_data.get("基础攻击冷却_s（BaseCooldownS）", 1.0)
	
	# 读取战斗属性
	damage = combat_stats.get("damage", 10.0)
	
	# 应用冷却缩减继承
	var inherited_cdr: float = combat_stats.get("cdr", 0.0)
	if inherited_cdr > 0:
		attack_cooldown *= (1.0 - inherited_cdr / 100.0)
	
	# 解析行为模式
	_parse_behavior()
	
	# 设置攻击计时器
	if attack_timer:
		attack_timer.wait_time = attack_cooldown
		attack_timer.timeout.connect(_on_attack_timer_timeout)
		attack_timer.start()
	
	# 设置存活时间
	var duration: float = summon_data.get("持续时间_s（DurationS）", 999.0)
	if duration < 999.0 and lifetime_timer:
		lifetime_timer.wait_time = duration
		lifetime_timer.one_shot = true
		lifetime_timer.timeout.connect(_on_lifetime_timeout)
		lifetime_timer.start()
	
	# 设置检测范围
	if detection_area:
		detection_area.collision_layer = 0
		detection_area.collision_mask = CollisionLayers.ENEMY
		
		# 设置检测半径为攻击范围
		var detection_shape: CollisionShape2D = detection_area.get_node_or_null("CollisionShape2D")
		if detection_shape:
			var circle: CircleShape2D = CircleShape2D.new()
			circle.radius = attack_range
			detection_shape.shape = circle
	
	# 加载精灵图
	_load_sprite()
	
	print("[SummonUnit] 召唤单位初始化完成: ", summon_data.get("显示名称（DisplayName）", "未知"))


## 解析行为模式
func _parse_behavior() -> void:
	var behavior_tags: String = summon_data.get("行为标签（BehaviorTags）", "")
	
	# 判断召唤类型
	if "炮台" in summon_type or "Turrets" in summon_type:
		is_static = true
		behavior_mode = "static"
	elif "爆体" in summon_type or "Kamikaze" in summon_type:
		behavior_mode = "charge"
	else:
		# 随从类
		if "环绕" in behavior_tags:
			behavior_mode = "orbit"
		else:
			behavior_mode = "follow"


##############################################################################
# AI更新
##############################################################################

func _physics_process(delta: float) -> void:
	# 查找最近的敌人
	_find_nearest_enemy()
	
	# 根据行为模式移动
	match behavior_mode:
		"follow":
			_update_follow_behavior(delta)
		"orbit":
			_update_orbit_behavior(delta)
		"static":
			_update_static_behavior(delta)
		"charge":
			_update_charge_behavior(delta)
	
	# 应用移动
	move_and_slide()


## 跟随玩家行为
func _update_follow_behavior(_delta: float) -> void:
	if not owner_player:
		return
	
	# 如果有目标且在攻击范围内，停止移动
	if current_target and _is_in_attack_range(current_target):
		velocity = Vector2.ZERO
		return
	
	# 跟随玩家，保持一定距离
	var to_player: Vector2 = owner_player.global_position - global_position
	var distance: float = to_player.length()
	
	# 如果距离玩家太远，瞬移回来
	if distance > 800.0:
		global_position = owner_player.global_position + Vector2(randf_range(-100, 100), randf_range(-100, 100))
		velocity = Vector2.ZERO
		return
	
	# 保持一定距离（100-200px）
	if distance > 200.0:
		velocity = to_player.normalized() * move_speed
	elif distance < 100.0:
		velocity = -to_player.normalized() * move_speed * 0.5
	else:
		velocity = Vector2.ZERO


## 环绕玩家行为
func _update_orbit_behavior(delta: float) -> void:
	if not owner_player:
		return
	
	# 环绕玩家旋转
	orbit_angle += delta * 1.0  # 1弧度/秒
	
	var target_pos: Vector2 = owner_player.global_position + Vector2(
		cos(orbit_angle) * orbit_radius,
		sin(orbit_angle) * orbit_radius
	)
	
	velocity = (target_pos - global_position).normalized() * move_speed


## 固定位置行为（炮台）
func _update_static_behavior(_delta: float) -> void:
	velocity = Vector2.ZERO
	
	# 朝向目标
	if current_target:
		var direction: Vector2 = (current_target.global_position - global_position).normalized()
		rotation = direction.angle()


## 冲锋爆炸行为
func _update_charge_behavior(_delta: float) -> void:
	if not current_target:
		# 没有目标，跟随玩家
		if owner_player:
			velocity = (owner_player.global_position - global_position).normalized() * move_speed
		return
	
	# 冲向目标
	velocity = (current_target.global_position - global_position).normalized() * move_speed * 1.5
	
	# 检查是否接触到目标
	if global_position.distance_to(current_target.global_position) < 30.0:
		# 爆炸
		_explode()


##############################################################################
# 攻击逻辑
##############################################################################

## 攻击计时器超时
func _on_attack_timer_timeout() -> void:
	if current_target and _is_in_attack_range(current_target):
		_perform_attack()


## 执行攻击
func _perform_attack() -> void:
	# 检查召唤物是否有投射物
	var projectile_id: String = summon_data.get("攻击投射物ID（ProjectileID）", "")
	
	if not projectile_id.is_empty():
		# 发射投射物
		_shoot_projectile()
	else:
		# 直接伤害（近战召唤物）
		_apply_melee_damage()


## 发射投射物
func _shoot_projectile() -> void:
	if not current_target:
		return
	
	var projectile: Node2D = PROJECTILE_SCENE.instantiate()
	
	# 设置位置和方向
	projectile.global_position = global_position
	var direction: Vector2 = (current_target.global_position - global_position).normalized()
	projectile.rotation = direction.angle()
	
	# 添加到场景
	get_tree().current_scene.add_child(projectile)
	
	# 初始化投射物
	if projectile.has_method("initialize"):
		var proj_damage: float = _calculate_damage()
		var proj_data: Dictionary = GameData.get_projectile(summon_data.get("攻击投射物ID（ProjectileID）", ""))
		
		projectile.initialize(
			proj_damage,
			1000.0,  # 速度
			direction,
			2.0,  # 存活时间
			0,  # 不穿透
			proj_data,
			owner_player
		)


## 近战伤害
func _apply_melee_damage() -> void:
	if not current_target:
		return
	
	var dmg: float = _calculate_damage()
	
	if current_target.has_method("take_damage"):
		current_target.take_damage(dmg)


## 计算伤害
func _calculate_damage() -> float:
	var base_dmg: float = damage
	
	# 应用会心判定
	var crit_rate: float = combat_stats.get("crit_rate", 0.0)
	if randf() * 100.0 < crit_rate:
		var crit_dmg: float = combat_stats.get("crit_dmg", 0.0)
		var crit_mult: float = 1.5 + crit_dmg / 100.0
		base_dmg *= crit_mult
	
	return base_dmg


##############################################################################
# 敌人检测
##############################################################################

## 查找最近的敌人
func _find_nearest_enemy() -> void:
	if not detection_area:
		return
	
	var enemies: Array[Node2D] = detection_area.get_overlapping_bodies()
	
	if enemies.is_empty():
		current_target = null
		return
	
	# 找到最近的敌人
	var nearest: Node2D = null
	var nearest_dist: float = INF
	
	for enemy: Node2D in enemies:
		if not enemy.is_in_group("enemy"):
			continue
		
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	
	current_target = nearest


## 检查是否在攻击范围内
func _is_in_attack_range(enemy: Node2D) -> bool:
	if not enemy:
		return false
	
	return global_position.distance_to(enemy.global_position) <= attack_range


##############################################################################
# 生命周期
##############################################################################

## 受到伤害
func take_damage(dmg: float) -> void:
	current_hp -= dmg
	
	# TODO: 播放受伤特效
	
	if current_hp <= 0:
		die()


## 死亡
func die() -> void:
	# TODO: 播放死亡特效
	
	summon_destroyed.emit()
	queue_free()


## 存活时间结束
func _on_lifetime_timeout() -> void:
	# TODO: 播放消失特效
	
	summon_destroyed.emit()
	queue_free()


## 爆炸（冲锋爆体）
func _explode() -> void:
	# 创建爆炸范围
	var explosion_radius: float = 100.0
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
	
	await get_tree().process_frame
	
	# 对范围内所有敌人造成伤害
	var enemies: Array[Node2D] = explosion_area.get_overlapping_bodies()
	var explosion_damage: float = damage * 2.0  # 爆炸伤害是普通攻击的2倍
	
	for enemy: Node2D in enemies:
		if enemy.is_in_group("enemy") and enemy.has_method("take_damage"):
			enemy.take_damage(explosion_damage)
	
	explosion_area.queue_free()
	
	# TODO: 播放爆炸特效
	
	# 自毁
	summon_destroyed.emit()
	queue_free()


##############################################################################
# 精灵图
##############################################################################

## 加载精灵图
func _load_sprite() -> void:
	if not sprite:
		return
	
	var sprite_id: String = summon_data.get("精灵ID（SpriteID）", "")
	if sprite_id.is_empty():
		_create_placeholder_sprite()
		return
	
	# TODO: 加载实际精灵图
	_create_placeholder_sprite()


## 创建占位精灵图
func _create_placeholder_sprite() -> void:
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 1.0, 0.5, 1.0))  # 绿色
	
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = texture
