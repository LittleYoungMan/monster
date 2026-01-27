##############################################################################
# TestSetup - 测试场景初始化
#
# 设计目的：
# - 为测试场景快速生成“可用的武器套装 + 测试怪群”
# - 仅用于调试，不应影响正式关卡逻辑
#
# 主要职责：
# 1) 给玩家生成6把测试武器（近战/远程/元素/召唤混合）
# 2) 在玩家周围按圆环刷出测试敌人
# 3) 构造简化的怪物数据，驱动敌人脚本初始化
#
# 依赖与调用链：
# - 依赖玩家节点在group "player" 中
# - 依赖玩家具备 WeaponContainer 节点与 weapon_slots 数组
# - 依赖 enemy.tscn 支持 monster_id / monster_data / player 等字段
#
# 引擎回调：
# - _ready(): 测试入口，自动配置武器与刷怪
#
# 修复：2026-01-27 重新写回中文注释与测试文本
##############################################################################
extends Node

##############################################################################
# 可配置参数（编辑器可调）
##############################################################################

## 测试敌人数量
@export var enemy_count: int = 5

## 敌人生成半径（围绕玩家的圆形半径）
@export var spawn_radius: float = 300.0

##############################################################################
# 资源引用
##############################################################################

## 通用敌人场景（用于生成测试怪）
var enemy_scene: PackedScene = preload("res://scenes/enemy/enemy.tscn")

##############################################################################
# 生命周期回调
##############################################################################

func _ready() -> void:
	## 等待一帧，确保玩家节点已在树中
	await get_tree().process_frame

	## 获取玩家
	var player: Node = _get_player()
	if not player:
		push_error("[TestSetup] 未找到玩家节点（group: player）")
		return

	## 为玩家配置测试武器
	_setup_weapons(player)

	## 刷出测试敌人
	_spawn_enemies(player)

##############################################################################
# 玩家获取
##############################################################################

func _get_player() -> Node:
	## 从group "player" 查找玩家（默认第一个）
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0]

##############################################################################
# 武器配置
##############################################################################

func _setup_weapons(player: Node) -> void:
	## 使用真实CSV武器模板，避免占位图与假数据
	var weapon_defs: Array = []
	var weapon_ids: Array[String] = GameData.get_all_weapon_ids()
	if weapon_ids.is_empty():
		push_error("[TestSetup] 武器数据为空，无法配置测试武器")
		return

	## 优先按类型挑选各1把（近战/远程/元素/召唤）
	var picked: Array = []
	picked.append(_pick_weapon_by_class(weapon_ids, ["近战", "melee"]))
	picked.append(_pick_weapon_by_class(weapon_ids, ["远程", "ranged"]))
	picked.append(_pick_weapon_by_class(weapon_ids, ["元素", "element"]))
	picked.append(_pick_weapon_by_class(weapon_ids, ["召唤", "summon"]))

	## 补足到6把（按CSV顺序补）
	for weapon_id: String in weapon_ids:
		if picked.size() >= 6:
			break
		if weapon_id in picked:
			continue
		picked.append(weapon_id)

	for weapon_id: String in picked:
		if weapon_id.is_empty():
			continue
		var template: Dictionary = GameData.get_weapon(weapon_id)
		if template.is_empty():
			continue
		var scene_path: String = _get_weapon_scene_path(template)
		if scene_path.is_empty():
			continue
		weapon_defs.append({
			"scene": scene_path,
			"template": template
		})

	## 获取玩家的武器容器节点
	var weapon_container: Node = player.get_node("WeaponContainer")
	if not weapon_container:
		push_error("[TestSetup] Player缺少WeaponContainer")
		return

	## 重置玩家武器槽（如果存在）
	if "weapon_slots" in player:
		player.weapon_slots.clear()
		player.weapon_slots.resize(6)

	## 实例化并初始化武器
	for i in range(weapon_defs.size()):
		var def: Dictionary = weapon_defs[i]
		var scene: PackedScene = load(def["scene"])
		var weapon: Node2D = scene.instantiate()

		## weapon实例数据：用于存档/装备系统
		var instance_data: Dictionary = {
			"weapon_id": def["template"].get("weapon_id", def["template"].get("id", "")),
			"quality": "white",
			"attributes": [],
			"slot_index": i
		}

		## 先加入场景树，确保@onready节点可用
		weapon_container.add_child(weapon)
		## 调用武器初始化（由具体武器脚本实现）
		weapon.initialize(def["template"], instance_data, player)

		## 同步weapon_slots（若玩家有此结构）
		if "weapon_slots" in player:
			player.weapon_slots[i] = {
				"weapon_id": def["template"].get("weapon_id", def["template"].get("id", "")),
				"quality": "white",
				"attributes": [],
				"slot_index": i,
				"scene_node": weapon
			}

	## 重新计算装备加成（如果玩家支持该方法）
	if player.has_method("recalculate_equipment_bonus"):
		player.recalculate_equipment_bonus()

## 从CSV中按武器类型挑选一个武器ID
func _pick_weapon_by_class(weapon_ids: Array[String], class_names: Array[String]) -> String:
	for weapon_id: String in weapon_ids:
		var template: Dictionary = GameData.get_weapon(weapon_id)
		var class_name: String = template.get("Class", template.get("class", ""))
		if class_name.is_empty():
			continue
		for name in class_names:
			if class_name == name:
				return weapon_id
	return ""

## 根据武器模板获取对应场景路径
func _get_weapon_scene_path(template: Dictionary) -> String:
	var class_name: String = template.get("Class", template.get("class", ""))
	match class_name:
		"近战", "melee":
			return "res://scenes/weapons/melee_weapon.tscn"
		"远程", "ranged":
			return "res://scenes/weapons/ranged_weapon.tscn"
		"元素", "element":
			return "res://scenes/weapons/elemental_weapon.tscn"
		"召唤", "summon":
			return "res://scenes/weapons/summon_weapon.tscn"
		_:
			return "res://scenes/weapons/melee_weapon.tscn"

##############################################################################
# 刷怪逻辑
##############################################################################

func _spawn_enemies(player: Node) -> void:
	## 根据enemy_count数量实例化敌人，并围绕玩家圆形分布
	for i in range(enemy_count):
		var enemy: Node2D = enemy_scene.instantiate()
		add_child(enemy)
		await enemy.ready

		## 构建测试怪物数据并注入到enemy
		var monster_data: Dictionary = _build_test_monster_data(i)
		enemy.monster_id = monster_data.get("id", "M_TEST")
		enemy.monster_data = monster_data
		enemy.player = player

		## 触发敌人内部逻辑初始化
		enemy._calculate_stats(0)
		enemy._parse_attack_type()
		enemy._parse_behavior()
		enemy._setup_collision()
		enemy._load_sprite()

		## 同步血条显示（如果敌人持有health_bar）
		var health_bar: Variant = enemy.get("health_bar")
		if health_bar is ProgressBar:
			health_bar.max_value = enemy.max_hp
			health_bar.value = enemy.current_hp
			health_bar.visible = true

		## 计算环形位置
		var angle: float = (TAU / float(max(1, enemy_count))) * float(i)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * spawn_radius
		enemy.global_position = player.global_position + offset

##############################################################################
# 测试怪物数据构建
##############################################################################

func _build_test_monster_data(index: int) -> Dictionary:
	## 交替生成远程/近战测试怪
	var ranged: bool = (index % 2) == 1
	return {
		"id": "M_TEST_%02d" % index,
		"NameZH": "测试怪物%d" % index,
		"HP_S1": 40.0 + float(index) * 5.0,
		"hp+/min": 5.0,
		"BaseDamage": 4.0 + float(index),
		"Field_11": "+2/min",
		"MoveSpeed": 110.0,
		"Armor": 0.0,
		"Field_12": "弹道" if ranged else "碰撞",
		"Field_18": "",
		"Size": "小型",
		"掉落": 1
	}
