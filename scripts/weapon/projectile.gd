##############################################################################
# Projectile - 玩家投射物
#
# 设计目的：
# - 承载玩家远程/元素武器的投射物逻辑
# - 支持命中/穿透/连锁/爆炸/区域持续伤害/追踪
#
# CSV字段对齐（projectile.csv）：
# - ProjectileID   -> projectile_id（在武器模板中引用）
# - Type           -> projectile_type（连锁/区域等）
# - HitRadiusPx    -> hit_radius_px
# - SpeedPxps      -> speed
# - UseWeaponRange -> 决定max_distance使用武器射程还是固定值
# - HitLimit       -> pierce_count或chain_limit
# - Homing         -> homing
# - Explode        -> explode
# - ExplodeRadiusPx-> explode_radius_px
# - AreaDurationS  -> area_duration_s
# - VFXHitID       -> vfx_hit_id
# - SpriteID       -> sprite_sheet_id
#
# 调用链：
# - RangedWeapon._perform_attack -> Projectile.initialize
# - _physics_process -> 飞行/追踪/区域伤害
#
# 已实现：穿透、连锁、爆炸、区域持续
# 未实现：VFX特效落地（需VFX系统）
##############################################################################
extends Area2D

##############################################################################
# 运动与伤害参数（初始化时写入）
##############################################################################

## 当前飞行方向
var direction: Vector2 = Vector2.RIGHT

## 飞行速度（像素/秒）
var speed: float = 600.0

## 基础伤害
var damage: float = 10.0

##############################################################################
# 穿透相关
##############################################################################

## 剩余穿透次数（命中后递减）
var remaining_pierce: int = 0

## 穿透伤害衰减倍率
var pierce_damage_mult: float = 1.0

## 当前伤害倍率（命中后叠乘衰减）
var current_damage_mult: float = 1.0

##############################################################################
# 投射物配置（来自projectile.csv）
##############################################################################

## 命中半径（像素）
var hit_radius_px: float = 0.0

## 是否追踪目标
var homing: bool = false

## 是否爆炸
var explode: bool = false

## 爆炸半径
var explode_radius_px: float = 0.0

## 区域持续时间（>0表示区域型弹）
var area_duration_s: float = 0.0

## 命中特效ID（预留）
var vfx_hit_id: String = ""

## 投射物类型文本（用于连锁/区域判断）
var projectile_type: String = ""

## 连锁上限
var chain_limit: int = 0

## 是否回旋体
var is_boomerang: bool = false

## 是否喷射
var is_spray: bool = false

## 是否抛甩体（带摆动轨迹）
var is_swing: bool = false

## 是否抛物线/榴弹
var is_lob: bool = false

## 是否波形
var is_wave: bool = false

## 是否已进入回程
var is_returning: bool = false

## 抛甩摆幅
var swing_amplitude: float = 60.0

## 抛甩频率
var swing_frequency: float = 0.08

## 抛物线摆幅
var lob_amplitude: float = 80.0

## 命中后是否留下持续区
var leave_area_on_hit: bool = false

## 连锁命中次数（当前已命中）
var chain_hits: int = 0

## 区域伤害tick计时
var area_tick_timer: float = 0.0

##############################################################################
# 命中记录
##############################################################################

## 已命中的敌人（防重复命中）
var hit_enemies: Array[Node] = []

##############################################################################
# 距离生命周期
##############################################################################

## 最大飞行距离（通常=武器射程）
var max_distance: float = 800.0

## 起始位置（用于计算飞行距离）
var start_position: Vector2 = Vector2.ZERO

## 已飞行距离
var traveled_distance: float = 0.0

## 是否命中体弧形（近战弧形命中体）
var is_melee_arc: bool = false

## 弧形命中体寿命
var melee_arc_lifetime: float = 0.12

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER_PROJECTILE)
	collision_mask = CollisionLayers.combine_layers([
		CollisionLayers.ENEMY,
		CollisionLayers.WALL
	])
	start_position = global_position

	## 连锁投射物若速度为0，立即触发连锁
	if speed <= 0.0 and _is_chain_projectile():
		var nearest: Node2D = _find_nearest_enemy()
		if nearest:
			_chain_to_next(damage, nearest.global_position)
		queue_free()

##############################################################################
# 初始化
##############################################################################

## 初始化投射物
## 由武器脚本调用，参数映射自武器模板+projectile.csv
func initialize(
	dir: Vector2,
	spd: float,
	dmg: float,
	pierce: int = 0,
	pierce_dmg_decay: float = 1.0,
	sprite_sheet_id: String = "",
	attack_range: float = 800.0,
	hit_radius: float = 0.0,
	is_homing: bool = false,
	is_explode: bool = false,
	explode_radius: float = 0.0,
	area_duration: float = 0.0,
	projectile_type_in: String = "",
	chain_limit_in: int = 0,
	vfx_id: String = ""
) -> void:
	direction = dir.normalized()
	speed = spd
	damage = dmg
	remaining_pierce = pierce
	pierce_damage_mult = pierce_dmg_decay
	current_damage_mult = 1.0

	max_distance = attack_range
	hit_radius_px = hit_radius
	homing = is_homing
	explode = is_explode
	explode_radius_px = explode_radius
	area_duration_s = area_duration
	projectile_type = projectile_type_in
	chain_limit = chain_limit_in
	vfx_hit_id = vfx_id

	var type_text: String = projectile_type_in
	is_boomerang = type_text.find("回旋") != -1
	is_spray = type_text.find("喷射") != -1
	is_swing = type_text.find("抛甩") != -1 or type_text.find("抛射") != -1
	is_melee_arc = type_text.find("近战弧形") != -1
	is_lob = type_text.find("榴弹") != -1 or type_text.find("黏液") != -1
	is_wave = type_text.find("波形") != -1
	leave_area_on_hit = (area_duration_s > 0.0 and (type_text.find("黏液") != -1 or type_text.find("持续区") != -1))

	## 若未提供命中半径但有爆炸半径，使用爆炸半径
	if hit_radius_px <= 0.0 and explode_radius_px > 0.0:
		hit_radius_px = explode_radius_px
	area_tick_timer = 0.0

	if is_melee_arc:
		if hit_radius_px <= 0.0:
			hit_radius_px = max(attack_range * 0.5, 40.0)
		area_duration_s = melee_arc_lifetime
	if is_wave and hit_radius_px <= 0.0:
		hit_radius_px = 30.0
	if is_lob and explode_radius_px > 0.0:
		lob_amplitude = max(40.0, explode_radius_px * 0.5)

	_load_sprite(sprite_sheet_id)
	_apply_hit_radius()
	rotation = direction.angle()

	print("[Projectile] 初始化: speed=", speed, " damage=", damage, " pierce=", pierce, " range=", max_distance)

##############################################################################
# 资源与显示
##############################################################################

func _load_sprite(sprite_sheet_id: String) -> void:
	if sprite_sheet_id.is_empty():
		_generate_placeholder_sprite()
		return
	var sprite_path: String = "res://assets/PIC/wuqi/VFX/256/" + sprite_sheet_id + ".png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		sprite.scale = Vector2(0.125, 0.125)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_generate_placeholder_sprite()

func _generate_placeholder_sprite() -> void:
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.8, 0.0, 1.0))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.scale = Vector2(1.0, 1.0)

##############################################################################
# 物理更新
##############################################################################

func _physics_process(delta: float) -> void:
	## 追踪目标
	if homing:
		var target: Node2D = _find_nearest_enemy()
		if target:
			direction = (target.global_position - global_position).normalized()
			rotation = direction.angle()

	## 区域型投射物：停留并周期造成伤害
	if area_duration_s > 0.0 and not is_spray:
		area_duration_s -= delta
		area_tick_timer -= delta
		if area_tick_timer <= 0.0:
			_tick_area_damage()
			area_tick_timer = 0.5
		if area_duration_s <= 0.0:
			queue_free()
			return

	## 直线飞行
	var movement: Vector2 = direction * speed * delta

	if is_boomerang and not is_returning and traveled_distance >= max_distance * 0.5:
		is_returning = true
		hit_enemies.clear()
	if is_returning:
		var return_dir: Vector2 = (start_position - global_position).normalized()
		if return_dir != Vector2.ZERO:
			direction = return_dir
			rotation = direction.angle()

	if is_swing:
		var perp: Vector2 = Vector2(-direction.y, direction.x)
		var swing: float = sin(traveled_distance * swing_frequency) * swing_amplitude
		movement += perp * swing * delta

	if is_wave:
		var perp_wave: Vector2 = Vector2(-direction.y, direction.x)
		var wave: float = sin(traveled_distance * 0.12) * 40.0
		movement += perp_wave * wave * delta

	if is_lob:
		var perp_lob: Vector2 = Vector2(-direction.y, direction.x)
		var progress: float = clamp(traveled_distance / max(max_distance, 1.0), 0.0, 1.0)
		var arc: float = sin(progress * PI) * lob_amplitude
		movement += perp_lob * arc * delta

	position += movement
	traveled_distance += movement.length()
	if traveled_distance >= max_distance:
		if is_boomerang and not is_returning:
			is_returning = true
		else:
			_destroy_out_of_range()

	## 喷射：移动中持续伤害
	if is_spray and area_duration_s > 0.0:
		area_duration_s -= delta
		area_tick_timer -= delta
		if area_tick_timer <= 0.0:
			_tick_area_damage()
			area_tick_timer = 0.15
		if area_duration_s <= 0.0:
			queue_free()

func _destroy_out_of_range() -> void:
	queue_free()

##############################################################################
# 碰撞处理
##############################################################################

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy_hurtbox"):
		var enemy: Node = area.get_parent()
		if enemy and enemy.is_in_group("enemy"):
			_hit_enemy(enemy)
	if area.is_in_group("wall"):
		_hit_wall()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("wall"):
		_hit_wall()

func _hit_enemy(enemy: Node) -> void:
	if enemy in hit_enemies:
		return

	hit_enemies.append(enemy)
	var actual_damage: float = damage * current_damage_mult

	## 爆炸类型：直接AOE后销毁
	if explode and explode_radius_px > 0.0:
		_explode_at(enemy.global_position, actual_damage)
		if leave_area_on_hit:
			speed = 0.0
			direction = Vector2.ZERO
			area_duration_s = max(area_duration_s, 1.0)
			return
		queue_free()
		return

	## 普通命中
	if enemy.has_method("take_damage"):
		enemy.take_damage(actual_damage)

	## 连锁类型
	if _is_chain_projectile() and chain_limit > 0:
		_chain_to_next(actual_damage, enemy.global_position)
		queue_free()
		return

	## 区域类型：停留
	if _is_area_projectile() and area_duration_s > 0.0:
		speed = 0.0
		direction = Vector2.ZERO
		return

	## 穿透衰减
	remaining_pierce -= 1
	if remaining_pierce >= 0:
		current_damage_mult *= pierce_damage_mult
	if remaining_pierce < 0:
		queue_free()

func _hit_wall() -> void:
	queue_free()

##############################################################################
# 区域与连锁
##############################################################################

func _tick_area_damage() -> void:
	var areas: Array[Area2D] = get_overlapping_areas()
	for area: Area2D in areas:
		if area.is_in_group("enemy_hurtbox"):
			var enemy: Node = area.get_parent()
			if enemy and enemy.is_in_group("enemy") and enemy.has_method("take_damage"):
				enemy.take_damage(damage)

func _apply_hit_radius() -> void:
	if hit_radius_px <= 0.0:
		return
	if collision_shape and collision_shape.shape is CircleShape2D:
		collision_shape.shape.radius = hit_radius_px
	else:
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = hit_radius_px
		collision_shape.shape = shape

func _find_nearest_enemy() -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for e: Node in enemies:
		if e is Node2D:
			var dist: float = global_position.distance_to(e.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = e
	return nearest

func _find_nearest_enemy_excluding(excluded: Array, from_pos: Vector2) -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for e: Node in enemies:
		if e is Node2D and e not in excluded:
			var dist: float = from_pos.distance_to(e.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = e
	return nearest

func _chain_to_next(base_damage: float, from_pos: Vector2) -> void:
	if chain_limit <= 1:
		return
	var remaining: int = chain_limit - 1
	var current_pos: Vector2 = from_pos
	while remaining > 0:
		var next_enemy: Node2D = _find_nearest_enemy_excluding(hit_enemies, current_pos)
		if not next_enemy:
			break
		hit_enemies.append(next_enemy)
		if next_enemy.has_method("take_damage"):
			next_enemy.take_damage(base_damage)
		current_pos = next_enemy.global_position
		remaining -= 1

func _explode_at(pos: Vector2, base_damage: float) -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	for e: Node in enemies:
		if e is Node2D:
			var dist: float = pos.distance_to(e.global_position)
			if dist <= explode_radius_px:
				if e.has_method("take_damage"):
					e.take_damage(base_damage)
	# TODO: area_duration_s persistent effects

func _is_chain_projectile() -> bool:
	return projectile_type.find("连锁") != -1 or projectile_type.to_lower().find("chain") != -1

func _is_area_projectile() -> bool:
	return projectile_type.find("区域") != -1 or projectile_type.to_lower().find("area") != -1
