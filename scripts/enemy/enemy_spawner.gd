##############################################################################
# EnemySpawner - 敌人生成器
#
# 设计目的：
# - 按时间刷怪（频率/批次）
# - 依据CSV权重选择怪物（monster.csv的S1~S4字段）
# - 处理Boss刷新与Boss战期间的小怪支援
# - 维护场上怪物数量统计
#
# CSV字段对齐（monster.csv）：
# - S1(1-5)/S2(6-10)/S3(11-15)/S4(16-20) -> 权重
# - remake -> 特殊刷新行为（矿物周边/视野内等）
# - Cap/上限 -> 单怪物上限（可选）
#
# 调用链：
# - GameManager.time_changed/minute_changed -> _on_time_changed/_on_minute_changed
# - GameManager.boss_spawned/boss_killed -> _on_boss_spawned/_on_boss_killed
# - _process -> _spawn_wave -> _spawn_single_enemy
#
# 已实现：刷怪节奏、Boss流程、权重随机、上限控制
# 未实现：靠近矿物刷怪的精确逻辑（_get_spawn_near_ore）
##############################################################################
extends Node2D

##############################################################################
# 资源
##############################################################################

## 小怪场景（可在编辑器注入）
@export var enemy_scene: PackedScene

## Boss场景（可在编辑器注入）
@export var boss_scene: PackedScene

##############################################################################
# 状态
##############################################################################

## 当前分钟（由GameManager驱动）
var current_minute: int = 0

## 刷怪计时器
var spawn_timer: float = 0.0

## 当前刷怪间隔（秒）
var current_spawn_interval: float = 20.0

## 是否处于Boss战
var is_boss_active: bool = false

## Boss小怪计时器
var boss_minion_timer: float = 0.0

## 当前怪物总数
var enemy_count_total: int = 0

## 按怪物ID统计数量（用于上限/统计）
var enemy_count_by_type: Dictionary = {}

## 玩家引用（用于刷怪位置）
var player: CharacterBody2D = null

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	## 兜底加载怪物场景
	if not enemy_scene:
		enemy_scene = load("res://scenes/enemy/enemy.tscn")
		if not enemy_scene:
			push_error("[EnemySpawner] 无法加载Enemy场景")
			return

	## 兜底加载Boss场景
	if not boss_scene:
		boss_scene = load("res://scenes/enemy/boss.tscn")

	## 获取玩家引用
	await get_tree().process_frame
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	## 订阅GameManager事件
	if GameManager:
		if GameManager.has_signal("time_changed"):
			GameManager.time_changed.connect(_on_time_changed)
		if GameManager.has_signal("minute_changed"):
			GameManager.minute_changed.connect(_on_minute_changed)
		if GameManager.has_signal("boss_spawned"):
			GameManager.boss_spawned.connect(_on_boss_spawned)
		if GameManager.has_signal("boss_killed"):
			GameManager.boss_killed.connect(_on_boss_killed)

	_update_spawn_settings(0)
	print("[EnemySpawner] 初始化完成")

##############################################################################
# 主循环
##############################################################################

func _process(delta: float) -> void:
	if not player:
		return

	if is_boss_active:
		_process_boss_minions(delta)
		return

	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_wave()
		spawn_timer = current_spawn_interval

##############################################################################
# 刷怪逻辑
##############################################################################

## 生成一波怪
func _spawn_wave() -> void:
	if enemy_count_total >= SpawnerConfig.MAX_ENEMY_COUNT:
		print("[EnemySpawner] 达到最大怪物数量，暂停刷怪")
		return

	var batch_size: int = SpawnerConfig.get_batch_size(current_minute)
	for i in range(batch_size):
		_spawn_single_enemy()

## 刷一个怪
func _spawn_single_enemy() -> void:
	var monster_id: String = _select_monster_by_weight()
	if monster_id.is_empty():
		return

	## 单怪物上限（CSV可提供Cap/上限）
	if SpawnerConfig.USE_INDIVIDUAL_CAP:
		var monster_data: Dictionary = GameData.get_monster(monster_id)
		var cap: int = int(monster_data.get("上限", monster_data.get("Cap", 999)))
		var current_count: int = enemy_count_by_type.get(monster_id, 0)
		if current_count >= cap:
			print("[EnemySpawner] ", monster_id, " 达到上限")
			return

	var spawn_pos: Vector2 = _get_spawn_position(monster_id)
	var enemy: CharacterBody2D = enemy_scene.instantiate()
	enemy.initialize(monster_id, current_minute)
	enemy.global_position = spawn_pos
	enemy.tree_exited.connect(_on_enemy_died.bind(monster_id))
	get_parent().add_child(enemy)

	enemy_count_total += 1
	if monster_id not in enemy_count_by_type:
		enemy_count_by_type[monster_id] = 0
	enemy_count_by_type[monster_id] += 1

##############################################################################
# 权重选择（CSV对齐）
##############################################################################

func _select_monster_by_weight() -> String:
	var all_monsters: Array[String] = GameData.get_all_monster_ids()
	if all_monsters.is_empty():
		return ""

	var weights: Array[float] = []
	var valid_monsters: Array[String] = []

	for monster_id: String in all_monsters:
		var monster_data: Dictionary = GameData.get_monster(monster_id)
		if GameData.has_method("is_boss") and GameData.is_boss(monster_id):
			continue
		var weight: float = _get_monster_weight(monster_data)
		if weight > 0:
			weights.append(weight)
			valid_monsters.append(monster_id)

	if valid_monsters.is_empty():
		return all_monsters[0]

	return _weighted_random(valid_monsters, weights)

func _get_monster_weight(monster_data: Dictionary) -> float:
	if not SpawnerConfig.USE_WEIGHT_FROM_EXCEL:
		return 1.0
	var weight_field: String = SpawnerConfig.get_weight_field(current_minute)
	var weight: float = float(monster_data.get(weight_field, SpawnerConfig.DEFAULT_WEIGHT))
	return weight

func _weighted_random(items: Array, weights: Array[float]) -> String:
	if items.is_empty():
		return ""

	var total_weight: float = 0.0
	for w: float in weights:
		total_weight += w
	if total_weight <= 0:
		return items[0]

	var rand_value: float = randf() * total_weight
	var cumulative: float = 0.0
	for i: int in range(items.size()):
		cumulative += weights[i]
		if rand_value <= cumulative:
			return items[i]

	return items[-1]

##############################################################################
# 刷怪位置（与CSV行为文本对齐）
##############################################################################

func _get_spawn_position(monster_id: String) -> Vector2:
	if not player:
		return Vector2.ZERO
	var monster_data: Dictionary = GameData.get_monster(monster_id)
	var behavior: String = monster_data.get("remake", monster_data.get("Field_18", ""))

	## CSV例："只刷新在矿物周边"
	if "矿" in behavior or "产矿" in behavior or "矿物" in behavior or "M_POO" in monster_id:
		return _get_spawn_near_ore()

	## CSV例："只在玩家视野内刷新"
	if SpawnerConfig.SPLIT_ORB_SPAWN_IN_VIEW_ONLY:
		if "视野" in behavior or "视野内" in behavior or "刷新" in behavior or "M_SPL" in monster_id:
			return _get_spawn_in_view()

	return _get_spawn_around_player()

func _get_spawn_around_player() -> Vector2:
	var angle: float = randf() * TAU
	var distance: float = randf_range(SpawnerConfig.SPAWN_DISTANCE_MIN, SpawnerConfig.SPAWN_DISTANCE_MAX)
	var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
	return player.global_position + offset

func _get_spawn_near_ore() -> Vector2:
	# TODO: 在矿石附近刷怪（需矿物系统提供点位）
	return _get_spawn_around_player()

func _get_spawn_in_view() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if not camera:
		return _get_spawn_around_player()

	var viewport_rect: Rect2 = get_viewport_rect()
	var camera_center: Vector2 = camera.get_screen_center_position()
	var viewport_size: Vector2 = viewport_rect.size / camera.zoom

	var edge_offset: Vector2 = Vector2(
		randf_range(-viewport_size.x / 2, viewport_size.x / 2),
		randf_range(-viewport_size.y / 2, viewport_size.y / 2)
	)
	return camera_center + edge_offset

##############################################################################
# Boss流程
##############################################################################

func _on_boss_spawned(boss_minute: int) -> void:
	is_boss_active = true
	boss_minion_timer = 0.0

	if SpawnerConfig.BOSS_CLEAR_ENEMIES:
		_clear_all_enemies()

	print("[EnemySpawner] Boss出现: ", boss_minute, "分钟")

func _on_boss_killed(_boss_minute: int) -> void:
	is_boss_active = false
	print("[EnemySpawner] Boss已击杀，恢复刷怪")

func _clear_all_enemies() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	for enemy: Node in enemies:
		if not enemy.is_in_group("boss"):
			enemy.queue_free()

	enemy_count_total = 0
	enemy_count_by_type.clear()
	print("[EnemySpawner] 已清空全部普通怪物")

func _process_boss_minions(delta: float) -> void:
	var should_spawn_minions: bool = SpawnerConfig.BOSS_SPAWN_MINIONS.get(current_minute, false)
	if not should_spawn_minions:
		return

	boss_minion_timer -= delta
	if boss_minion_timer <= 0:
		_spawn_boss_minions()
		boss_minion_timer = SpawnerConfig.BOSS_MINION_SPAWN_INTERVAL

func _spawn_boss_minions() -> void:
	var count: int = SpawnerConfig.BOSS_MINION_SPAWN_COUNT
	for i in range(count):
		_spawn_single_enemy()
	print("[EnemySpawner] Boss召唤小怪: ", count, "只")

##############################################################################
# 时间回调
##############################################################################

func _on_time_changed(seconds: float) -> void:
	var new_minute: int = int(seconds / 60.0)
	if new_minute != current_minute:
		current_minute = new_minute
		_update_spawn_settings(current_minute)

func _on_minute_changed(minute: int) -> void:
	if is_boss_active:
		return
	var boss_id: String = ""
	if GameData.has_method("get_boss_id_by_minute"):
		boss_id = GameData.get_boss_id_by_minute(minute)
	if boss_id.is_empty():
		return
	_spawn_boss(boss_id, minute)

func _spawn_boss(boss_id: String, minute_mark: int) -> void:
	if not boss_scene:
		push_error("[EnemySpawner] Boss场景未加载")
		return
	var boss: CharacterBody2D = boss_scene.instantiate()
	if boss.has_method("initialize_boss"):
		boss.initialize_boss(boss_id, minute_mark)
	else:
		boss.initialize(boss_id, minute_mark)
	boss.global_position = _get_spawn_around_player()
	get_parent().add_child(boss)
	print("[EnemySpawner] 刷新Boss: ", boss_id, " @", minute_mark, "min")

func _update_spawn_settings(minute: int) -> void:
	current_spawn_interval = SpawnerConfig.get_spawn_interval(minute)
	if minute % 5 == 0:
		SpawnerConfig.print_current_config(minute)

##############################################################################
# 统计与调试
##############################################################################

func _on_enemy_died(monster_id: String) -> void:
	enemy_count_total -= 1
	if monster_id in enemy_count_by_type:
		enemy_count_by_type[monster_id] -= 1

func force_spawn_monster(monster_id: String) -> void:
	var enemy: CharacterBody2D = enemy_scene.instantiate()
	enemy.initialize(monster_id, current_minute)
	enemy.global_position = player.global_position + Vector2(200, 0)
	get_parent().add_child(enemy)
	print("[EnemySpawner] 强制刷怪: ", monster_id)

func get_enemy_stats() -> Dictionary:
	return {
		"total": enemy_count_total,
		"by_type": enemy_count_by_type,
		"spawn_interval": current_spawn_interval,
		"current_minute": current_minute
	}

func print_stats() -> void:
	print("\n=== 敌人统计 ===")
	print("总数: ", enemy_count_total)
	print("分布:")
	for monster_id: String in enemy_count_by_type.keys():
		print("  ", monster_id, ": ", enemy_count_by_type[monster_id])
