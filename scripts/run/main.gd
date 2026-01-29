##############################################################################
# Main - 主场景协调脚本
#
# 设计目的：
# - 作为游戏运行时的中心协调节点
# - 监听GameManager的关键信号（商店门/工坊门/Boss/结束）
# - 负责动态生成商店门、工坊门等临时物体
# - 管理玩家初始化与场景生命周期
#
# 主要职责：
# 1) 根据GameManager.selected_character_id初始化玩家
# 2) 监听shop_door_triggered信号，生成商店门
# 3) 监听forge_available信号，生成工坊门
# 4) 监听game_over信号，显示结算界面
# 5) 启动GameManager的游戏计时器
#
# 依赖：
# - GameManager（Autoload）
# - Player场景
# - ShopDoor场景
# - ForgeDoor场景
# - GameOverUI场景
#
# 调用链：
# - GameManager信号 -> Main响应 -> 实例化对应场景
#
# 修复：2026-01-28 创建，填补场景集成空白
##############################################################################
extends Node2D

##############################################################################
# 场景资源（预加载）
##############################################################################

## 玩家场景
var player_scene: PackedScene = preload("res://scenes/player/player.tscn")

## 商店门场景（需要创建）
var shop_door_scene: PackedScene = null

## 工坊门场景（需要创建）
var forge_door_scene: PackedScene = null

## 结算界面（需要创建）
var game_over_ui_scene: PackedScene = null

##############################################################################
# 地图拼接配置
##############################################################################

## 地图图片路径（按 3x2 顺序拼接）
const MAP_TEXTURE_PATHS: Array[String] = [
	"res://assets/PIC/map/4096/2.png",
	"res://assets/PIC/map/4096/3.png",
	"res://assets/PIC/map/4096/4.png",
	"res://assets/PIC/map/4096/5.png",
	"res://assets/PIC/map/4096/6.png",
	"res://assets/PIC/map/4096/7.png"
]

## 地图列数/行数
const MAP_COLUMNS: int = 3
const MAP_ROWS: int = 2

## 每张地图目标高度（1080p）
const MAP_TARGET_HEIGHT: float = 1080.0

##############################################################################
# 节点引用
##############################################################################

## 玩家实例
var player: CharacterBody2D = null

## 敌人生成器
@onready var enemy_spawner: Node2D = $EnemySpawner

## HUD
@onready var hud: CanvasLayer = $HUD

## 地图根节点
@onready var map_root: Node2D = $MapRoot

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	## 尝试加载可选场景（可能不存在）
	_load_optional_scenes()

	## 生成大地图
	_build_map()
	
	## 初始化玩家
	_initialize_player()
	
	## 连接GameManager信号
	_connect_signals()
	
	## 启动游戏计时器
	GameManager.start_game()
	
	print("[Main] 场景初始化完成")

##############################################################################
# 玩家初始化
##############################################################################

func _initialize_player() -> void:
	## 实例化玩家
	player = player_scene.instantiate()
	add_child(player)
	
	## 从GameManager获取选择的角色ID
	var character_id: String = GameManager.selected_character_id
	if character_id.is_empty():
		push_warning("[Main] 未选择角色，使用默认角色")
		character_id = "hero_01"
	
	## 加载角色数据
	player.load_character_data(character_id)
	
	## 设置到GameManager（用于升级回调）
	GameManager.set_player(player)
	
	print("[Main] 玩家初始化: ", character_id)

##############################################################################
# 信号连接
##############################################################################

func _connect_signals() -> void:
	## 商店门触发
	if GameManager.has_signal("shop_door_triggered"):
		GameManager.shop_door_triggered.connect(_on_shop_door_triggered)
	
	## 工坊门可用
	if GameManager.has_signal("forge_available"):
		GameManager.forge_available.connect(_on_forge_available)
	
	## 游戏结束
	if GameManager.has_signal("game_over"):
		GameManager.game_over.connect(_on_game_over)
	
	print("[Main] 信号连接完成")

##############################################################################
# 商店门生成
##############################################################################

func _on_shop_door_triggered() -> void:
	if not shop_door_scene or not player:
		push_warning("[Main] 商店门场景缺失或玩家不存在")
		return
	
	## 实例化商店门
	var shop_door: Area2D = shop_door_scene.instantiate()
	
	## 计算生成位置（玩家附近）
	var spawn_pos: Vector2 = _calculate_shop_door_position()
	shop_door.global_position = spawn_pos
	
	## 添加到场景
	add_child(shop_door)
	
	print("[Main] 商店门生成: ", spawn_pos)

## 计算商店门位置
func _calculate_shop_door_position() -> Vector2:
	if not player:
		return Vector2.ZERO
	
	var current_time: float = GameManager.current_time
	var distance: float
	
	## 前期（0-180秒）：靠近玩家
	if current_time < 180.0:
		distance = randf_range(50.0, 100.0)
	## 后期（180秒后）：随机远近
	else:
		distance = randf_range(100.0, 500.0)
	
	## 随机角度
	var angle: float = randf() * TAU
	var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
	
	return player.global_position + offset

##############################################################################
# 工坊门生成
##############################################################################

func _on_forge_available(boss_minute: int) -> void:
	if not forge_door_scene or not player:
		push_warning("[Main] 工坊门场景缺失或玩家不存在")
		return
	
	## 实例化工坊门
	var forge_door: Area2D = forge_door_scene.instantiate()
	
	## 计算生成位置（视野内）
	var spawn_pos: Vector2 = _calculate_forge_door_position()
	forge_door.global_position = spawn_pos
	
	## 传递Boss分钟标记（用于UI显示）
	if forge_door.has_method("initialize"):
		forge_door.initialize(boss_minute)
	
	## 添加到场景
	add_child(forge_door)
	
	print("[Main] 工坊门生成: ", spawn_pos, " (Boss=", boss_minute, "min)")

## 计算工坊门位置
func _calculate_forge_door_position() -> Vector2:
	if not player:
		return Vector2.ZERO
	
	## 视野内随机位置（距离200-400px）
	var distance: float = randf_range(200.0, 400.0)
	var angle: float = randf() * TAU
	var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
	
	return player.global_position + offset

##############################################################################
# 游戏结束
##############################################################################

func _on_game_over() -> void:
	## 停止敌人生成
	if enemy_spawner:
		enemy_spawner.set_process(false)
	
	## 停止玩家输入
	if player:
		player.set_physics_process(false)
	
	## 显示结算界面
	if game_over_ui_scene:
		var game_over_ui: Control = game_over_ui_scene.instantiate()
		add_child(game_over_ui)
	else:
		## 临时回退：打印结算信息
		print("\n========== 游戏结束 ==========")
		print("游戏时长: 20分钟")
		print("最终等级: Lv.", GameManager.player_level)
		print("剩余金币: ", GameManager.gold)
		print("剩余矿石: ", GameManager.ore)
		if player:
			print("总DPS: ", int(player.get_total_dps()))
		print("==============================\n")

##############################################################################
# 场景加载（容错处理）
##############################################################################

func _load_optional_scenes() -> void:
	## 商店门场景
	var shop_door_path: String = "res://scenes/shop/shop_door.tscn"
	if ResourceLoader.exists(shop_door_path):
		shop_door_scene = load(shop_door_path)
		print("[Main] 商店门场景加载成功")
	else:
		push_warning("[Main] 商店门场景不存在: ", shop_door_path)
	
	## 工坊门场景
	var forge_door_path: String = "res://scenes/shop/forge_door.tscn"
	if ResourceLoader.exists(forge_door_path):
		forge_door_scene = load(forge_door_path)
		print("[Main] 工坊门场景加载成功")
	else:
		push_warning("[Main] 工坊门场景不存在: ", forge_door_path)
	
	## 结算界面场景
	var game_over_path: String = "res://scenes/run/game_over_ui.tscn"
	if ResourceLoader.exists(game_over_path):
		game_over_ui_scene = load(game_over_path)
		print("[Main] 结算界面加载成功")
	else:
		push_warning("[Main] 结算界面不存在: ", game_over_path)

##############################################################################
# 大地图拼接
##############################################################################

func _build_map() -> void:
	if not map_root:
		return

	## 清理旧地图
	for child: Node in map_root.get_children():
		child.queue_free()

	if MAP_TEXTURE_PATHS.size() == 0:
		return

	var first_tex: Texture2D = load(MAP_TEXTURE_PATHS[0])
	if not first_tex:
		push_warning("[Main] 地图贴图加载失败: ", MAP_TEXTURE_PATHS[0])
		return

	var base_size: Vector2 = first_tex.get_size()
	if base_size.y <= 0:
		return

	var scale_factor: float = MAP_TARGET_HEIGHT / base_size.y
	var tile_size: Vector2 = base_size * scale_factor
	var total_width: float = tile_size.x * float(MAP_COLUMNS)
	var total_height: float = tile_size.y * float(MAP_ROWS)

	## 让地图中心对齐场景原点
	map_root.position = Vector2(-total_width * 0.5, -total_height * 0.5)

	var index: int = 0
	for row in range(MAP_ROWS):
		for col in range(MAP_COLUMNS):
			if index >= MAP_TEXTURE_PATHS.size():
				return
			var tex_path: String = MAP_TEXTURE_PATHS[index]
			var tex: Texture2D = load(tex_path)
			if not tex:
				push_warning("[Main] 地图贴图缺失: ", tex_path)
				index += 1
				continue

			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.centered = false
			sprite.position = Vector2(col * tile_size.x, row * tile_size.y)
			sprite.scale = Vector2(scale_factor, scale_factor)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_index = -100
			map_root.add_child(sprite)

			index += 1

##############################################################################
# 调试接口
##############################################################################

func _input(event: InputEvent) -> void:
	## 按F1强制触发商店门（调试用）
	if event.is_action_pressed("ui_home"):
		_on_shop_door_triggered()
	
	## 按F2强制触发工坊门（调试用）
	if event.is_action_pressed("ui_end"):
		_on_forge_available(5)
	
	## 按F3强制结束游戏（调试用）
	if event.is_action_pressed("ui_page_down"):
		_on_game_over()
