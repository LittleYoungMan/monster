extends Node2D

# CodexTest - 自动化最小测试场景
# 目的：快速验证关键脚本/CSV/场景是否能正常跑起

@onready var player: CharacterBody2D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var spawner: Node2D = $EnemySpawner

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

func _check_autoloads() -> void:
	var names: Array[String] = ["GameData", "GameManager", "SpawnerConfig", "Localization", "CollisionLayers"]
	for name: String in names:
		var node: Node = get_node_or_null("/root/" + name)
		if node == null:
			push_error("[CodexTest] Autoload缺失: " + name)
		else:
			print("[CodexTest] Autoload OK: ", name)

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

func _check_scene_nodes() -> void:
	if hud == null:
		push_error("[CodexTest] HUD节点缺失")
	if spawner == null:
		push_error("[CodexTest] EnemySpawner节点缺失")

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

	var weapon_id: String = weapon_ids[0]
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
		print("[CodexTest] 刷怪测试: ", monster_id)
	else:
		push_error("[CodexTest] EnemySpawner缺少force_spawn_monster")
