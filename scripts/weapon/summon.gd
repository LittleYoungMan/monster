##############################################################################
# Summon - 召唤物脚本（多行为模式）
#
# 设计目的：
# - 根据summon.csv的BehaviorTags/AttackMode决定召唤物行为
# - 自动寻敌、攻击、巡逻或环绕
# - 超出视野或距离时重部署
#
# CSV字段对齐（summon.csv）：
# - SummonUnitID -> summon_config["summon_unit_id"]
# - SummonType   -> summon_config["summon_type"]
# - BehaviorTags -> summon_config["behavior_tags"]
# - AttackMode   -> summon_config["attack_mode"]
# - BaseDamage   -> summon_config["damage"]（由SummonWeapon合成）
# - SpriteID     -> summon_config["sprite_id"]
#
# 调用链：
# - SummonWeapon._perform_summon -> Summon.initialize
# - AttackTimer.timeout -> _on_attack_timer_timeout -> _perform_attack
# - _physics_process -> AI驱动
##############################################################################
extends CharacterBody2D

##############################################################################
# 行为模式枚举
##############################################################################

enum SummonBehavior {
	FOLLOW_MELEE,       # 跟随玩家，近战追击
	STATIONARY_SHOOTER, # 站桩炮台
	ORBITING_ATTACKER,  # 环绕攻击
	SCOUT_MARKER        # 巡逻标记
}

##############################################################################
# 变量（运行期）
##############################################################################

## 召唤配置（由SummonWeapon合成）
var summon_config: Dictionary = {}

## 玩家引用
var player: CharacterBody2D = null

## 当前行为模式
var behavior_mode: int = SummonBehavior.FOLLOW_MELEE

## 移动速度
const MOVE_SPEED: float = 300.0

## 跟随距离（与玩家保持的舒适距离）
const FOLLOW_DISTANCE: float = 150.0

## 最大跟随距离（超出后重部署）
const MAX_FOLLOW_DISTANCE: float = 800.0

## 当前目标
var current_target: Node2D = null

## 视野外计时
var out_of_view_timer: float = 0.0

## 视野外重部署时间
const REDEPLOY_TIME: float = 5.0

##############################################################################
# 站桩炮台参数
##############################################################################

## 站桩位置
var stationary_position: Vector2 = Vector2.ZERO

## 站桩触发距离
const STATIONARY_RANGE: float = 400.0

## 是否已进入站桩状态
var is_stationed: bool = false

##############################################################################
# 环绕攻击参数
##############################################################################

const ORBIT_RADIUS: float = 150.0
const ORBIT_SPEED: float = 2.0
var current_orbit_angle: float = 0.0

##############################################################################
# 巡逻参数
##############################################################################

var scout_waypoints: Array[Vector2] = []
var current_waypoint_index: int = 0
const SCOUT_SPEED_MULT: float = 1.5
const MARK_DURATION: float = 5.0

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var attack_timer: Timer = $AttackTimer

##############################################################################
# 初始化
##############################################################################

## 初始化召唤物
func initialize(config: Dictionary, owner_player: CharacterBody2D) -> void:
	summon_config = config
	player = owner_player

	_parse_behavior_mode(config)
	_load_sprite()
	_setup_attack_range()

	var attack_speed: float = summon_config.get("attack_speed", 1.0)
	attack_timer.wait_time = attack_speed
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	attack_timer.start()

	collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER_PROJECTILE)
	collision_mask = CollisionLayers.combine_layers([
		CollisionLayers.ENEMY,
		CollisionLayers.WALL
	])

	attack_area.collision_layer = 0
	attack_area.collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)

	print("[Summon] 初始化完成 - 行为模式: ", _get_behavior_name())

##############################################################################
# 行为解析（基于summon.csv）
##############################################################################

## 解析行为模式
func _parse_behavior_mode(config: Dictionary) -> void:
	var summon_unit_id: String = config.get("summon_unit_id", "")
	var unique_mechanic: String = config.get("unique_mechanic", "")
	var behavior_tags: String = config.get("behavior_tags", "")
	var attack_mode: String = config.get("attack_mode", "")
	var summon_type: String = config.get("summon_type", "")
	var merged: String = behavior_tags + "," + attack_mode + "," + unique_mechanic + "," + summon_unit_id + "," + summon_type
	var merged_lower: String = merged.to_lower()

	## 环绕类
	if merged_lower.find("orbit") != -1 or "环绕" in merged:
		behavior_mode = SummonBehavior.ORBITING_ATTACKER
		current_orbit_angle = randf() * TAU
	## 炮台/固定
	elif merged_lower.find("stationary") != -1 or merged_lower.find("turret") != -1 or "站桩" in merged or "炮台" in merged or "固定" in merged:
		behavior_mode = SummonBehavior.STATIONARY_SHOOTER
	## 巡逻/侦巡
	elif merged_lower.find("scout") != -1 or "巡逻" in merged or "侦巡" in merged or "侦查" in merged:
		behavior_mode = SummonBehavior.SCOUT_MARKER
		_generate_scout_waypoints()
	## 特例
	elif "spore_eye" in summon_unit_id or "孢眼" in unique_mechanic:
		behavior_mode = SummonBehavior.STATIONARY_SHOOTER
	else:
		behavior_mode = SummonBehavior.FOLLOW_MELEE

func _get_behavior_name() -> String:
	match behavior_mode:
		SummonBehavior.STATIONARY_SHOOTER:
			return "站桩炮台"
		SummonBehavior.ORBITING_ATTACKER:
			return "环绕攻击"
		SummonBehavior.SCOUT_MARKER:
			return "巡逻标记"
		_:
			return "跟随近战"

##############################################################################
# 图标与范围
##############################################################################

func _load_sprite() -> void:
	var sprite_id: String = summon_config.get("sprite_id", "")
	if sprite_id.is_empty():
		_generate_placeholder_sprite()
		return

	var sprite_path: String = "res://assets/PIC/summon/256/" + sprite_id + ".png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		sprite.scale = Vector2(0.3125, 0.3125)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		print("[Summon] 图标加载成功: ", sprite_path)
	else:
		print("[Summon] 图标不存在: ", sprite_path, "，使用占位图")
		_generate_placeholder_sprite()

func _generate_placeholder_sprite() -> void:
	var img: Image = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 1.0, 0.5, 1.0))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.scale = Vector2(1.0, 1.0)

func _setup_attack_range() -> void:
	var attack_range: float = summon_config.get("attack_range", 100.0)
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = attack_range
	attack_shape.shape = shape
	print("[Summon] 攻击范围=", attack_range, "px")

##############################################################################
# AI逻辑
##############################################################################

func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		queue_free()
		return

	match behavior_mode:
		SummonBehavior.STATIONARY_SHOOTER:
			_ai_stationary_shooter(delta)
		SummonBehavior.ORBITING_ATTACKER:
			_ai_orbiting_attacker(delta)
		SummonBehavior.SCOUT_MARKER:
			_ai_scout_marker(delta)
		_:
			_ai_follow_melee(delta)

	move_and_slide()
	_check_view_redeploy(delta)

func _ai_stationary_shooter(delta: float) -> void:
	var distance_to_player: float = global_position.distance_to(player.global_position)
	if distance_to_player > MAX_FOLLOW_DISTANCE:
		_redeploy_near_player()
		is_stationed = false
		return

	if not is_stationed and distance_to_player >= STATIONARY_RANGE:
		is_stationed = true
		stationary_position = global_position
		velocity = Vector2.ZERO
		print("[Summon] 站桩炮台 - 固定位置")
		return

	if is_stationed and distance_to_player > STATIONARY_RANGE * 2.0:
		is_stationed = false
		print("[Summon] 站桩炮台 - 重新跟随")

	if is_stationed:
		velocity = Vector2.ZERO
	else:
		if distance_to_player < STATIONARY_RANGE:
			var direction: Vector2 = (global_position - player.global_position).normalized()
			velocity = direction * MOVE_SPEED
		else:
			velocity = Vector2.ZERO

func _ai_orbiting_attacker(delta: float) -> void:
	current_orbit_angle += ORBIT_SPEED * delta
	if current_orbit_angle > TAU:
		current_orbit_angle -= TAU

	var offset: Vector2 = Vector2(
		cos(current_orbit_angle) * ORBIT_RADIUS,
		sin(current_orbit_angle) * ORBIT_RADIUS
	)
	var target_position: Vector2 = player.global_position + offset

	var direction: Vector2 = (target_position - global_position).normalized()
	velocity = direction * MOVE_SPEED

	var distance_to_player: float = global_position.distance_to(player.global_position)
	if distance_to_player > MAX_FOLLOW_DISTANCE:
		_redeploy_near_player()
		current_orbit_angle = randf() * TAU

func _ai_scout_marker(delta: float) -> void:
	var distance_to_player: float = global_position.distance_to(player.global_position)
	if scout_waypoints.is_empty() or distance_to_player > MAX_FOLLOW_DISTANCE:
		_generate_scout_waypoints()
		current_waypoint_index = 0
		return

	if current_waypoint_index < scout_waypoints.size():
		var target: Vector2 = scout_waypoints[current_waypoint_index]
		var direction: Vector2 = (target - global_position).normalized()
		velocity = direction * MOVE_SPEED * SCOUT_SPEED_MULT

		if global_position.distance_to(target) < 50.0:
			current_waypoint_index += 1
			if current_waypoint_index >= scout_waypoints.size():
				current_waypoint_index = 0
	else:
		velocity = Vector2.ZERO

func _generate_scout_waypoints() -> void:
	scout_waypoints.clear()
	if not player:
		return

	var waypoint_count: int = randi_range(4, 6)
	var radius: float = 300.0
	for i in range(waypoint_count):
		var angle: float = (float(i) / waypoint_count) * TAU
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * radius
		scout_waypoints.append(player.global_position + offset)

	print("[Summon] 生成巡逻路径: ", waypoint_count, "点")

func _ai_follow_melee(delta: float) -> void:
	if current_target and is_instance_valid(current_target):
		_move_to_target(current_target)
		return

	var new_target: Node2D = _find_nearest_enemy()
	if new_target:
		current_target = new_target
		_move_to_target(current_target)
		return

	_follow_player()

##############################################################################
# 目标与移动
##############################################################################

func _move_to_target(target: Node2D) -> void:
	var attack_range: float = summon_config.get("attack_range", 100.0)
	var distance: float = global_position.distance_to(target.global_position)
	if distance > attack_range:
		var direction: Vector2 = (target.global_position - global_position).normalized()
		velocity = direction * MOVE_SPEED
	else:
		velocity = Vector2.ZERO

func _follow_player() -> void:
	var distance: float = global_position.distance_to(player.global_position)
	if distance > MAX_FOLLOW_DISTANCE:
		_redeploy_near_player()
	elif distance > FOLLOW_DISTANCE:
		var direction: Vector2 = (player.global_position - global_position).normalized()
		velocity = direction * MOVE_SPEED
	else:
		velocity = Vector2.ZERO

func _find_nearest_enemy() -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_distance: float = 500.0
	for enemy: Node in enemies:
		if enemy is Node2D and is_instance_valid(enemy):
			var distance: float = global_position.distance_to(enemy.global_position)
			if distance < nearest_distance:
				nearest = enemy
				nearest_distance = distance
	return nearest

##############################################################################
# 视野外重部署
##############################################################################

func _check_view_redeploy(delta: float) -> void:
	if not _is_in_camera_view():
		out_of_view_timer += delta
		if out_of_view_timer >= REDEPLOY_TIME:
			_redeploy_near_player()
			out_of_view_timer = 0.0
	else:
		out_of_view_timer = 0.0

func _is_in_camera_view() -> bool:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if not camera:
		return true

	var viewport_rect: Rect2 = get_viewport_rect()
	var camera_center: Vector2 = camera.get_screen_center_position()
	var viewport_size: Vector2 = viewport_rect.size / camera.zoom
	var view_rect: Rect2 = Rect2(camera_center - viewport_size / 2.0, viewport_size)
	return view_rect.has_point(global_position)

func _redeploy_near_player() -> void:
	if not player:
		return
	var offset: Vector2 = Vector2(randf_range(-150.0, 150.0), randf_range(-150.0, 150.0))
	global_position = player.global_position + offset
	print("[Summon] 视野外重部署")

##############################################################################
# 攻击逻辑
##############################################################################

func _on_attack_timer_timeout() -> void:
	_perform_attack()

func _perform_attack() -> void:
	var enemies: Array[Node2D] = []
	for area: Area2D in attack_area.get_overlapping_areas():
		if area.is_in_group("enemy_hurtbox"):
			var enemy: Node2D = area.get_parent()
			if enemy and enemy.is_in_group("enemy"):
				enemies.append(enemy)

	if enemies.is_empty():
		return

	match behavior_mode:
		SummonBehavior.SCOUT_MARKER:
			for enemy in enemies:
				_mark_enemy(enemy)
		_:
			var target: Node2D = enemies[0]
			var damage: float = _calculate_damage()
			if target.has_method("take_damage"):
				target.take_damage(damage)
				print("[Summon] 命中: ", target.name, " damage=", int(damage))

##############################################################################
# 伤害与标记
##############################################################################

func _calculate_damage() -> float:
	var base_damage: float = summon_config.get("damage", 10.0)
	var crit_rate: float = summon_config.get("crit_rate", 0.0)
	if randf() * 100.0 < crit_rate:
		var crit_dmg: float = summon_config.get("crit_dmg", 0.0)
		var crit_mult: float = 1.5 + (crit_dmg / 100.0)
		return base_damage * crit_mult
	return base_damage

func _mark_enemy(enemy: Node) -> void:
	if not enemy.has_method("apply_mark"):
		return
	enemy.apply_mark(MARK_DURATION)
	print("[Summon] 标记敌人: ", enemy.name)

##############################################################################
# 召唤配置更新（供SummonWeapon调用）
##############################################################################

func update_config(config: Dictionary) -> void:
	summon_config = config
	_setup_attack_range()

##############################################################################
# VFX/SFX预留接口
##############################################################################

func _play_mark_vfx(enemy: Node) -> void:
	pass

func _play_attack_sound() -> void:
	pass

func _play_orbit_trail_vfx() -> void:
	pass
