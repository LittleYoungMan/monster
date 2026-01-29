##############################################################################
# Enemy - 敌人脚本
#
# 设计目的：
# - 负责“普通怪物”在场景中的核心逻辑：数值、AI、攻击、受击、死亡
# - 所有怪物的“特殊行为描述”来自 CSV（monster.csv）的 remake 字段
# - 所有怪物的“攻击方式”来自 CSV（monster.csv）的 acttackWay 字段
#
# CSV字段对齐（monster.csv）：
# - MonsterID     -> monster_id
# - NameZH        -> 用于日志与显示（monster_data["NameZH"]）
# - Size          -> 碰撞/体型/缩放
# - MoveSpeed     -> speed（基础移速）
# - Armor         -> armor（护甲）
# - BaseDamage    -> damage（基础伤害）
# - GrowDamage    -> damage成长（"+2/min"等）
# - HP_S1         -> max_hp（基础生命）
# - hp+/min       -> max_hp成长
# - acttackWay    -> 攻击方式文本（远程/子弹/冲撞/射速极快等）
# - remake        -> 行为说明文本（死亡孵化/死亡爆炸/保持距离/三连发等）
#
# 调用链（关键路径）：
# - EnemySpawner._spawn_single_enemy -> enemy.initialize -> _calculate_stats/_parse_attack_type/_parse_behavior
# - _physics_process -> _ai_melee_attack / _ai_ranged_attack -> _perform_*_attack
# - _perform_ranged_attack -> _create_single_projectile -> EnemyProjectile.initialize
# - take_damage -> die -> _spawn_death_effect
#
# 引擎回调：
# - _ready(): 注册到"enemy"组
# - _physics_process(delta): 每帧AI与移动
#
# 已实现：基础数值成长、近战/远程AI、弹幕/分裂、死亡掉落
# 未实现（与CSV对齐但逻辑未做）：
# - remake里“减速/标记/异常状态”等效果，需状态系统接入
# - 特定怪物的专属AI（例如跳跃/冲刺/路径诡异）
##############################################################################
extends CharacterBody2D

##############################################################################
# 运行期数据（基础属性）
##############################################################################

## 怪物ID（MonsterID）
var monster_id: String = ""

## 怪物原始数据（来自GameData.get_monster -> monster.csv）
var monster_data: Dictionary = {}

## 当前生命值（计算后数值）
var current_hp: float = 0.0

## 最大生命值（基础+成长+倍率）
var max_hp: float = 0.0

## 基础伤害（基础+成长+倍率）
var damage: float = 0.0

## 移动速度（可能受行为标签影响）
var speed: float = 0.0

## 护甲值（影响减伤）
var armor: float = 0.0

##############################################################################
# 攻击与行为（由CSV解析得到）
##############################################################################

## 攻击类型："近战" or "远程"（由acttackWay解析）
var attack_type: String = "近战"

## 攻击范围（远程较大）
var attack_range: float = 50.0

## 攻击冷却（秒）
var attack_cooldown: float = 1.0

## 玩家引用（追踪目标）
var player: CharacterBody2D = null

## 攻击计时器（替代Timer）
var attack_timer: float = 0.0

## 行为描述文本（来自remake字段，保留原文）
var behavior: String = ""

## 存活时间（用于“存活X秒后强化”等行为）
var alive_time: float = 0.0

## 是否已触发强化（例如“15秒强化”）
var is_enhanced: bool = false

## 减速状态
var slow_timer: float = 0.0
var slow_mult: float = 1.0

## 击退速度
var knockback_velocity: Vector2 = Vector2.ZERO
const KNOCKBACK_DAMP: float = 8.0

##############################################################################
# 远程投射物参数
##############################################################################

## 远程投射物飞行速度（可由攻击方式标签决定）
var projectile_speed: float = 300.0

## 投射物贴图ID（预留，若CSV提供可在此填充）
var projectile_sprite: String = ""

## 是否需要后撤（连发完成后退）
var should_retreat: bool = false

## 后撤计时器
var retreat_timer: float = 0.0

## 后撤持续时间（秒）
const RETREAT_DURATION: float = 2.0

## 保持距离的目标距离（远程怪常用）
var keep_distance: float = 250.0

## 连发计数器
var burst_count: int = 0

## 最大连发数
const BURST_MAX: int = 3

##############################################################################
# 节点引用（场景内节点）
##############################################################################

## 怪物显示贴图
@onready var sprite: Sprite2D = $Sprite2D

## 主碰撞体
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

## 受击判定区域
@onready var hurt_box: Area2D = $HurtBox

## 受击判定形状
@onready var hurt_box_shape: CollisionShape2D = $HurtBox/CollisionShape2D

## 血条UI
@onready var health_bar: ProgressBar = $HealthBar

##############################################################################
# 初始化
##############################################################################

## 初始化入口（由EnemySpawner调用）
## 参数：
## - id: 怪物ID（MonsterID）
## - current_minute: 当前分钟（用于成长）
func initialize(id: String, current_minute: int) -> void:
	monster_id = id
	monster_data = GameData.get_monster(monster_id)
	if monster_data.is_empty():
		push_error("[Enemy] 怪物数据不存在: " + monster_id)
		queue_free()
		return

	## 确保onready节点已就绪
	if not is_node_ready():
		await ready

	_calculate_stats(current_minute)
	_parse_attack_type()
	_parse_behavior()
	_setup_collision()
	_load_sprite()

	## 获取玩家引用（用于追踪）
	await get_tree().process_frame
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	## 初始化血条显示
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current_hp
		health_bar.visible = true

	print("[Enemy] 初始化: ", monster_data.get("NameZH", monster_id), " HP=", int(max_hp), " 攻击类型=", attack_type)

func _ready() -> void:
	## 统一加入敌人组，方便查询与统计
	add_to_group("enemy")

##############################################################################
# 属性计算（成长）
##############################################################################

## 根据CSV字段计算基础属性和成长
func _calculate_stats(minute: int) -> void:
	## HP与成长
	var base_hp: float = monster_data.get("HP_S1", 100.0)
	var hp_growth: float = monster_data.get("hp+/min", 20.0)

	## 伤害与成长（解析"+2/min"格式）
	var base_dmg: float = monster_data.get("BaseDamage", 5.0)
	var dmg_growth_text: String = monster_data.get("GrowDamage", "+2/min")

	var dmg_growth: float = 2.0
	if "+/min" in dmg_growth_text:
		var parts: PackedStringArray = dmg_growth_text.split("/")
		if parts.size() > 0:
			dmg_growth = float(parts[0].replace("+", ""))
	else:
		if not dmg_growth_text.is_empty():
			dmg_growth = float(dmg_growth_text.replace("+", ""))

	max_hp = base_hp + hp_growth * float(minute)
	current_hp = max_hp
	damage = base_dmg + dmg_growth * float(minute)
	speed = monster_data.get("MoveSpeed", 100.0)
	armor = monster_data.get("Armor", 0.0)

	## 统一难度倍率（全局配置）
	if has_node("/root/SpawnerConfig"):
		var config = get_node("/root/SpawnerConfig")
		max_hp *= config.DIFFICULTY_MULT.get("hp", 1.0)
		current_hp = max_hp
		damage *= config.DIFFICULTY_MULT.get("damage", 1.0)
		speed *= config.DIFFICULTY_MULT.get("speed", 1.0)

##############################################################################
# 行为解析（CSV字段 -> 内部状态）
##############################################################################

## 解析攻击方式（acttackWay）
func _parse_attack_type() -> void:
	var attack_way: String = monster_data.get("acttackWay", monster_data.get("Field_12", "近战"))

	## 远程判断：包含“远程/子弹/弹道/投射/射击”等关键词
	var is_ranged: bool = false
	if "远程" in attack_way or "子弹" in attack_way or "弹道" in attack_way or "投射" in attack_way or "射击" in attack_way:
		is_ranged = true

	## 明确近战覆盖：包含“冲撞/碰撞/近战”强制近战
	if "冲撞" in attack_way or "碰撞" in attack_way or "近战" in attack_way:
		is_ranged = false

	if is_ranged:
		attack_type = "远程"
		attack_range = 400.0

		## 远程射速与弹速（按文本关键词调整）
		if "射速极快" in attack_way or "极快" in attack_way or "快" in attack_way:
			attack_cooldown = 0.3
			projectile_speed = 500.0
		elif "中速" in attack_way or "中" in attack_way:
			attack_cooldown = 0.8
			projectile_speed = 400.0
		elif "慢速" in attack_way or "慢" in attack_way:
			attack_cooldown = 2.0
			projectile_speed = 200.0
		else:
			attack_cooldown = 1.0
			projectile_speed = 300.0
	else:
		attack_type = "近战"
		attack_range = 50.0
		## 近战移速修正（快/中/慢）
		if "极快" in attack_way or "快" in attack_way:
			speed *= 1.5
		elif "中" in attack_way:
			speed *= 1.2
		elif "慢" in attack_way:
			speed *= 0.8

## 解析行为文本（remake）
func _parse_behavior() -> void:
	behavior = monster_data.get("remake", monster_data.get("Field_18", ""))

	## 远程保持距离/风筝
	if "保持距离" in behavior or "风筝" in behavior or "不靠近" in behavior:
		keep_distance = 250.0

	## 连发/三连发
	if "连发" in behavior or "三连发" in behavior:
		burst_count = 0

	## 缓慢标签
	if "缓慢" in behavior or "很慢" in behavior:
		speed *= 0.5

	## 15秒强化
	if "15秒" in behavior and "强化" in behavior:
		alive_time = 0.0
		is_enhanced = false

##############################################################################
# 碰撞设置
##############################################################################

func _setup_collision() -> void:
	collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)
	collision_mask = CollisionLayers.combine_layers([
		CollisionLayers.PLAYER,
		CollisionLayers.PLAYER_PROJECTILE,
		CollisionLayers.WALL
	])

	hurt_box.collision_layer = 0
	hurt_box.collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)
	hurt_box.collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER_PROJECTILE)
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	hurt_box.add_to_group("enemy_hurtbox")

	## 体型决定碰撞半径
	var size_text: String = monster_data.get("Size", "小型")
	var radius: float = 24.0
	if "中" in size_text:
		radius = 40.0
	elif "大" in size_text:
		radius = 60.0

	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = radius
	collision_shape.shape = shape

	var hurt_shape: CircleShape2D = CircleShape2D.new()
	hurt_shape.radius = radius + 10.0
	hurt_box_shape.shape = hurt_shape

##############################################################################
# 贴图加载
##############################################################################

func _load_sprite() -> void:
	var sprite_path: String = "res://assets/PIC/diren/256/xiaoguai/" + monster_id + ".png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		var size_text: String = monster_data.get("Size", "小型")
		if "中" in size_text:
			sprite.scale = Vector2(0.375, 0.375)
		else:
			sprite.scale = Vector2(0.25, 0.25)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_generate_placeholder_sprite()

func _generate_placeholder_sprite() -> void:
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	if attack_type == "远程":
		img.fill(Color(1.0, 0.5, 0.0, 1.0))
	else:
		img.fill(Color(0.8, 0.2, 0.2, 1.0))
	sprite.texture = ImageTexture.create_from_image(img)

##############################################################################
# AI主循环
##############################################################################

func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		return

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_mult = 1.0

	## “存活X秒后强化”逻辑
	if "15秒" in behavior and not is_enhanced:
		alive_time += delta
		if alive_time >= 15.0:
			_enhance_split_orb()

	if attack_timer > 0:
		attack_timer -= delta

	## 连发后的后撤行为
	if should_retreat:
		retreat_timer -= delta
		if retreat_timer <= 0:
			should_retreat = false
		else:
			_retreat_from_player(delta)
			return

	if attack_type == "远程":
		_ai_ranged_attack(delta)
	else:
		_ai_melee_attack(delta)

	## 击退衰减
	if knockback_velocity.length() > 1.0:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, delta * KNOCKBACK_DAMP)

	move_and_slide()

	if health_bar:
		health_bar.value = current_hp

##############################################################################
# 近战AI
##############################################################################

func _ai_melee_attack(delta: float) -> void:
	var distance: float = global_position.distance_to(player.global_position)
	if distance > attack_range:
		var direction: Vector2 = (player.global_position - global_position).normalized()
		velocity = direction * _get_current_speed()
	else:
		velocity = Vector2.ZERO
		if attack_timer <= 0:
			_perform_melee_attack()
			attack_timer = attack_cooldown

##############################################################################
# 远程AI
##############################################################################

func _ai_ranged_attack(delta: float) -> void:
	var distance: float = global_position.distance_to(player.global_position)

	## 远程保持距离逻辑
	if "保持距离" in behavior or "不靠近" in behavior:
		if distance < keep_distance:
			var direction: Vector2 = (global_position - player.global_position).normalized()
			velocity = direction * _get_current_speed()
		elif distance > keep_distance + 100.0:
			var direction: Vector2 = (player.global_position - global_position).normalized()
			velocity = direction * _get_current_speed() * 0.5
		else:
			velocity = Vector2.ZERO
	else:
		if distance > attack_range:
			var direction: Vector2 = (player.global_position - global_position).normalized()
			velocity = direction * _get_current_speed()
		elif distance < attack_range * 0.5:
			var direction: Vector2 = (global_position - player.global_position).normalized()
			velocity = direction * _get_current_speed() * 0.3
		else:
			velocity = Vector2.ZERO

	if attack_timer <= 0 and distance <= attack_range:
		_perform_ranged_attack()

		## 连发行为
		if "连发" in behavior or "三连发" in behavior:
			burst_count += 1
			if burst_count >= BURST_MAX:
				burst_count = 0
				should_retreat = true
				retreat_timer = RETREAT_DURATION
				attack_timer = attack_cooldown * 3.0
			else:
				attack_timer = 0.2
		else:
			attack_timer = attack_cooldown

##############################################################################
# 攻击实现
##############################################################################

## 近战攻击：直接对玩家造成伤害
func _perform_melee_attack() -> void:
	if player.has_method("take_damage"):
		var final_damage: float = _calculate_final_damage()
		player.take_damage(final_damage)
		print("[Enemy] 近战命中: ", int(final_damage))

## 远程攻击：发射投射物
func _perform_ranged_attack() -> void:
	var projectile_scene: PackedScene = load("res://scenes/enemy/enemy_projectile.tscn")
	if not projectile_scene:
		push_error("[Enemy] 投射物场景不存在")
		return

	var direction: Vector2 = (player.global_position - global_position).normalized()

	## 散射/溅射行为
	if "散射" in behavior:
		for i in range(5):
			var spread_angle: float = (i - 2) * 0.2
			var spread_dir: Vector2 = direction.rotated(spread_angle)
			_create_single_projectile(spread_dir)
	elif "溅射" in behavior or "爆炸" in behavior or "M_POO" in monster_id:
		_create_single_projectile(direction, true)
	else:
		_create_single_projectile(direction)

## 创建单发投射物（可附带溅射/分裂）
func _create_single_projectile(direction: Vector2, splash: bool = false) -> void:
	var projectile_scene: PackedScene = load("res://scenes/enemy/enemy_projectile.tscn")
	var projectile: Area2D = projectile_scene.instantiate()
	var has_splash: bool = splash or "溅射" in behavior or "爆炸" in behavior

	var projectile_data: Dictionary = {
		"damage": _calculate_final_damage(),
		"speed": projectile_speed,
		"direction": direction,
		"max_distance": attack_range * 2.0,
		"splash": has_splash,
		"splash_radius": 80.0,
		"splash_count": 4 if "分裂" in behavior else 0,
		"sprite_id": projectile_sprite
	}

	projectile.initialize(projectile_data)
	projectile.global_position = global_position
	get_parent().add_child(projectile)

## 伤害计算入口（目前返回damage）
func _calculate_final_damage() -> float:
	return damage

##############################################################################
# 退避与强化
##############################################################################

func _retreat_from_player(delta: float) -> void:
	var direction: Vector2 = (global_position - player.global_position).normalized()
	velocity = direction * _get_current_speed() * 1.5

func _get_current_speed() -> float:
	if slow_timer > 0.0:
		return speed * slow_mult
	return speed

## 15秒强化示例：翻倍血量与护甲
func _enhance_split_orb() -> void:
	is_enhanced = true
	max_hp *= 2.0
	current_hp *= 2.0
	armor += 10.0
	print("[Enemy] 进入强化状态")

##############################################################################
# 受击与死亡
##############################################################################

## 受击入口：玩家武器碰撞触发
func _on_hurt_box_area_entered(area: Area2D) -> void:
	if area.is_in_group("weapon_attack"):
		var weapon: Node = area.get_parent()
		if weapon.has_method("calculate_damage"):
			var dmg: float = weapon.calculate_damage()
			take_damage(dmg)

## 受伤计算（护甲减伤）
func take_damage(dmg: float) -> void:
	var dr: float = armor / (armor + 60.0)
	var actual_damage: float = dmg * (1.0 - dr)
	current_hp -= actual_damage
	if current_hp <= 0:
		die()

## 死亡处理（掉落金币/经验/矿石）
func die() -> void:
	var gold: int = int(monster_data.get("Money", 1))
	GameManager.add_gold(gold)
	GameManager.add_exp(3)
	if randf() < 0.1:
		GameManager.add_ore(1)
	print("[Enemy] 死亡: ", monster_data.get("NameZH", monster_id))
	_spawn_death_effect()
	queue_free()

## 死亡特效/召唤（由remake文本决定）
func _spawn_death_effect() -> void:
	var behavior_text: String = monster_data.get("remake", monster_data.get("Field_18", ""))

	## CSV例："死亡孵化三只史莱姆"
	if "死亡孵化" in behavior_text:
		var count: int = _extract_number_from_text(behavior_text, 3)
		_spawn_death_minions("M_SLM_01", count)
		return

	## CSV例："死亡爆炸6颗飞弹"
	if "死亡爆炸" in behavior_text or ("爆炸" in behavior_text and "飞弹" in behavior_text):
		var count: int = _extract_number_from_text(behavior_text, 6)
		_spawn_death_projectiles(count)
		return

	## CSV例："死亡掉落一只半血鼻屎兽"
	if "死亡掉落" in behavior_text:
		var hp_mult: float = 0.5 if "半血" in behavior_text else 1.0
		_spawn_death_minions(monster_id, 1, hp_mult)
		return

	## 兼容旧的关键字逻辑
	if "分裂" in behavior_text and "小怪" in behavior_text:
		_spawn_death_minions("M_SLM_01", 3)
	elif "爆裂" in behavior_text and "弹幕" in behavior_text:
		_spawn_death_projectiles(6)
	elif "复活" in behavior_text and "再生" in behavior_text:
		_spawn_death_minions(monster_id, 1, 0.5)

## 提取文本中的数字（用于“6颗飞弹”等）
func _extract_number_from_text(text: String, default_value: int) -> int:
	var number_str: String = ""
	for i in range(text.length()):
		var code: int = text.unicode_at(i)
		if code >= 48 and code <= 57:
			number_str += String.chr(code)
	if number_str.is_empty():
		return default_value
	return int(number_str)

## 死亡召唤小怪
func _spawn_death_minions(minion_id: String, count: int, hp_mult: float = 1.0) -> void:
	var enemy_scene: PackedScene = load("res://scenes/enemy/enemy.tscn")
	if not enemy_scene:
		return
	for i in range(count):
		var minion: CharacterBody2D = enemy_scene.instantiate()
		var angle: float = (float(i) / float(count)) * TAU
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * 50.0
		minion.global_position = global_position + offset
		minion.initialize(monster_id if minion_id.is_empty() else minion_id, GameManager.get_current_minute() if GameManager.has_method("get_current_minute") else 0)
		if hp_mult != 1.0:
			minion.max_hp *= hp_mult
			minion.current_hp *= hp_mult
		get_parent().add_child(minion)
	print("[Enemy] 死亡召唤: ", count, "只 ", minion_id)

## 死亡弹幕
func _spawn_death_projectiles(count: int) -> void:
	var projectile_scene: PackedScene = load("res://scenes/enemy/enemy_projectile.tscn")
	if not projectile_scene:
		return
	for i in range(count):
		var angle: float = (float(i) / float(count)) * TAU
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var projectile: Area2D = projectile_scene.instantiate()
		var projectile_data: Dictionary = {
			"damage": damage * 0.5,
			"speed": 400.0,
			"direction": direction,
			"max_distance": 300.0,
			"splash": false,
			"splash_radius": 0.0,
			"sprite_id": ""
		}
		projectile.initialize(projectile_data)
		projectile.global_position = global_position
		get_parent().add_child(projectile)
	print("[Enemy] 死亡弹幕: ", count, "发")

##############################################################################
# 状态效果
##############################################################################

func apply_slow(duration: float, mult: float) -> void:
	slow_timer = max(slow_timer, duration)
	slow_mult = min(slow_mult, mult)

func apply_knockback(direction: Vector2, strength: float) -> void:
	knockback_velocity = direction.normalized() * strength
