##############################################################################
# CodexTest - 自动化最小测试场景
#
# 设计目的：
# - 快速验证关键脚本/CSV/场景是否能正常跑起
# - 给出缺失节点/脚本/Autoload的明确报错
#
# 主要职责：
# 1) 检查 Autoload 是否存在
# 2) 检查玩家核心节点是否齐全
# 3) 验证 GameData 读取与 CSV 装载结果
# 4) 追加一把测试武器，验证装备流程
# 5) 强制刷出一只怪，验证刷怪入口
#
# 使用方式：
# - 仅用于调试场景（res://scenes/debug/codex_test.tscn）
# - 可在出问题时临时加入主场景进行排查
##############################################################################
extends Node2D

##############################################################################
# 可调参数（测试行为）
##############################################################################

## 测试装备选择的武器索引（从GameData武器列表取）
## 作用：快速验证装备流程
## 调整范围：0 ~ weapon_ids.size()-1
const TEST_WEAPON_INDEX: int = 0

## 测试刷怪时的默认刷怪偏移（若EnemySpawner使用player偏移）
## 作用：避免怪物与玩家重叠
const TEST_SPAWN_OFFSET: Vector2 = Vector2(200, 0)

##############################################################################
# 节点引用
##############################################################################

@onready var player: CharacterBody2D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var spawner: Node2D = $EnemySpawner

##############################################################################
# 生命周期
##############################################################################

## 测试入口
## - 顺序执行多个检查与最小动作
func _ready() -> void:
	print("[CodexTest] 开始测试")
	await get_tree().process_frame

	_check_autoloads()
	_check_player_nodes()
	_check_scene_nodes()
	_test_game_data()
	_test_add_weapon()
	_spawn_test_enemy()

	print("[CodexTest] 测试完成")

##############################################################################
# 检查项：Autoload
##############################################################################

## 校验核心Autoload是否存在
## - 仅做存在性检查，不执行逻辑
func _check_autoloads() -> void:
	var names: Array[String] = ["GameData", "GameManager", "SpawnerConfig", "Localization", "CollisionLayers"]
	for name: String in names:
		var node: Node = get_node_or_null("/root/" + name)
		if node == null:
			push_error("[CodexTest] Autoload缺失: " + name)
		else:
			print("[CodexTest] Autoload OK: ", name)

##############################################################################
# 检查项：玩家节点
##############################################################################

## 检查玩家节点与关键子节点
func _check_player_nodes() -> void:
	if player == null:
		push_error("[CodexTest] Player节点缺失")
		return

	if player.get_node_or_null("Sprite2D") == null:
		push_error("[CodexTest] Player缺少Sprite2D")
	if player.get_node_or_null("WeaponContainer") == null:
		push_error("[CodexTest] Player缺少WeaponContainer")
	if player.get_node_or_null("HurtBox") == null:
		push_error("[CodexTest] Player缺少HurtBox")
	if player.get_node_or_null("Camera2D") == null:
		push_error("[CodexTest] Player缺少Camera2D")

##############################################################################
# 检查项：场景节点
##############################################################################

## 检查场景内关键节点是否存在
func _check_scene_nodes() -> void:
	if hud == null:
		push_error("[CodexTest] HUD节点缺失")
	if spawner == null:
		push_error("[CodexTest] EnemySpawner节点缺失")

##############################################################################
# 检查项：GameData
##############################################################################

## 验证GameData是否加载CSV
func _test_game_data() -> void:
	var gd: Node = get_node_or_null("/root/GameData")
	if gd == null:
		push_error("[CodexTest] GameData未加载")
		return

	if gd.has_method("get_all_weapon_ids"):
		var weapon_ids: Array[String] = gd.get_all_weapon_ids()
		print("[CodexTest] 武器数量=", weapon_ids.size())
	else:
		push_error("[CodexTest] GameData缺少get_all_weapon_ids")

	if gd.has_method("get_all_monster_ids"):
		var monster_ids: Array[String] = gd.get_all_monster_ids()
		print("[CodexTest] 怪物数量=", monster_ids.size())
	else:
		push_error("[CodexTest] GameData缺少get_all_monster_ids")

##############################################################################
# 测试：装备武器
##############################################################################

## 向玩家添加一把测试武器，验证装备管线
func _test_add_weapon() -> void:
	var gd: Node = get_node_or_null("/root/GameData")
	if gd == null or player == null:
		return

	if not gd.has_method("get_all_weapon_ids"):
		return

	var weapon_ids: Array[String] = gd.get_all_weapon_ids()
	if weapon_ids.is_empty():
		push_error("[CodexTest] 无武器数据，无法测试装备")
		return

	var safe_index: int = clamp(TEST_WEAPON_INDEX, 0, weapon_ids.size() - 1)
	var weapon_id: String = weapon_ids[safe_index]
	var weapon_data: Dictionary = {
		"weapon_id": weapon_id,
		"quality": "white",
		"attributes": [],
		"slot_index": -1
	}

	if player.has_method("add_weapon"):
		var ok: bool = player.add_weapon(weapon_data)
		print("[CodexTest] 装备测试武器: ", weapon_id, " => ", ok)
	else:
		push_error("[CodexTest] Player缺少add_weapon")

##############################################################################
# 测试：刷怪入口
##############################################################################

## 强制刷出一只怪，验证EnemySpawner入口
func _spawn_test_enemy() -> void:
	var gd: Node = get_node_or_null("/root/GameData")
	if gd == null or spawner == null:
		return

	if not gd.has_method("get_all_monster_ids"):
		return

	var monster_ids: Array[String] = gd.get_all_monster_ids()
	if monster_ids.is_empty():
		push_error("[CodexTest] 无怪物数据，无法测试刷怪")
		return

	var monster_id: String = monster_ids[0]
	if spawner.has_method("force_spawn_monster"):
		spawner.force_spawn_monster(monster_id)
		print("[CodexTest] 刷怪测试: ", monster_id, " offset=", TEST_SPAWN_OFFSET)
	else:
		push_error("[CodexTest] EnemySpawner缺少force_spawn_monster")
