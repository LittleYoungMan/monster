##############################################################################
# SummonWeapon - 召唤武器脚本
#
# 设计目的：
# - 定时召唤召唤物（Summon）
# - 将武器模板（weapon.csv）与召唤单位模板（summon.csv）合并成召唤配置
# - 维护召唤上限与清理逻辑
#
# CSV字段对齐：
# - weapon.csv: SummonCount / SummonUnitID / BaseDamage / DamageMult / BaseCooldown
# - summon.csv: SummonUnitID / BehaviorTags / AttackMode / BaseDamage / SpriteID
#
# 调用链：
# - Player.add_weapon -> SummonWeapon.initialize
# - SummonTimer.timeout -> _on_summon_timer_timeout -> _perform_summon
# - Summon.initialize(config, player)
#
# 已实现：召唤、上限、基础伤害继承、暴击继承（商店）
# 未实现：复杂召唤AI策略（需在summon.gd继续扩展）
##############################################################################
extends Node2D

##############################################################################
# 变量（运行期）
##############################################################################

## 武器模板数据（来自GameData.get_weapon -> weapon.csv）
var weapon_template: Dictionary = {}

## 武器实例数据（品质/词条/槽位）
var weapon_instance: Dictionary = {}

## 玩家引用（读取召唤伤害/暴击/冷却）
var player: CharacterBody2D = null

## 召唤冷却（秒）
var current_cooldown: float = 5.0

## 召唤物场景
var summon_scene: PackedScene = null

## 当前存活召唤物列表
var active_summons: Array[Node] = []

## 基础召唤上限（武器可覆盖）
const BASE_SUMMON_LIMIT: int = 1

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var summon_timer: Timer = $SummonTimer

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	## 预加载召唤物场景
	summon_scene = load("res://scenes/weapons/summon.tscn")

## 初始化召唤武器
## 参数：template=武器模板，instance=武器实例，owner_player=玩家
func initialize(template: Dictionary, instance: Dictionary, owner_player: CharacterBody2D) -> void:
	weapon_template = template
	weapon_instance = instance
	player = owner_player

	_load_sprite()
	_calculate_cooldown()

	summon_timer.wait_time = current_cooldown
	summon_timer.start()

	## 初始化后立即召唤一次
	_perform_summon()

	print("[SummonWeapon] 初始化完成: ", weapon_template.get("name_cn", "未知"))
	print("  - 召唤冷却=", current_cooldown, "s")
	print("  - 召唤上限=", get_summon_limit())

##############################################################################
# 图标
##############################################################################

func _load_sprite() -> void:
	var icon_id: String = weapon_template.get("icon_id", "")
	if icon_id.is_empty():
		if sprite:
			sprite.visible = false
		return

	var sprite_path: String = "res://assets/PIC/wuqi/icon/256/" + icon_id + ".png"
	if ResourceLoader.exists(sprite_path):
		var texture: Texture2D = load(sprite_path)
		sprite.texture = texture
		sprite.scale = Vector2(0.25, 0.25)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_apply_handle_pivot(texture, sprite.scale)
	else:
		_generate_placeholder_sprite()

func _generate_placeholder_sprite() -> void:
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.3, 0.9, 1.0))
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.scale = Vector2(1.0, 1.0)
	_apply_handle_pivot(sprite.texture, sprite.scale)

## 将武器握把作为旋转中心
##
## 参数：
##   texture - 纹理
##   scale_value - 当前缩放
func _apply_handle_pivot(texture: Texture2D, scale_value: Vector2) -> void:
	if not sprite or not texture:
		return
	sprite.centered = false
	var size: Vector2 = texture.get_size() * scale_value
	var left_offset: float = _get_opaque_left_offset(texture) * scale_value.x
	# 让武器从玩家向外延伸（握把靠近玩家）
	sprite.position = Vector2(-left_offset, -size.y * 0.5)

## 获取贴图非透明像素的最左边界
##
## 参数：
##   texture - 纹理
## 返回：
##   左边界像素坐标（0表示无偏移）
func _get_opaque_left_offset(texture: Texture2D) -> float:
	var img: Image = texture.get_image()
	if img == null:
		return 0.0
	var w: int = img.get_width()
	var h: int = img.get_height()
	var min_x: int = w
	for y in range(h):
		for x in range(w):
			var color: Color = img.get_pixel(x, y)
			if color.a > 0.01:
				if x < min_x:
					min_x = x
	if min_x == w:
		return 0.0
	return float(min_x)

##############################################################################
# 冷却计算
##############################################################################

func _calculate_cooldown() -> void:
	var base_cooldown: float = weapon_template.get("base_cooldown", 5.0)
	var cooldown_mult: float = weapon_template.get("cooldown_mult", 1.0)

	## 召唤武器专用的CDR继承（来自商店）
	var cdr_inherit: float = 0.0
	if player.has_shop_bonus("summon_cdr_inherit"):
		cdr_inherit = player.get_shop_bonus_value("summon_cdr_inherit") / 100.0

	var player_cdr: float = player.get_final_stat("Cooldown")
	var cdr_mult: float = 1.0 - (cdr_inherit * player_cdr / 100.0)

	current_cooldown = base_cooldown * cooldown_mult * cdr_mult
	current_cooldown = max(current_cooldown, 0.5)

	print("[SummonWeapon] 冷却计算:")
	print("  - base_cooldown=", base_cooldown, "s")
	print("  - cdr_inherit=", cdr_inherit * 100, "%")
	print("  - current_cooldown=", current_cooldown, "s")

##############################################################################
# 召唤流程
##############################################################################

func _on_summon_timer_timeout() -> void:
	_perform_summon()

func _perform_summon() -> void:
	_cleanup_dead_summons()

	var summon_limit: int = get_summon_limit()
	if active_summons.size() >= summon_limit:
		## 超过上限时移除最早召唤
		var oldest: Node = active_summons[0]
		if oldest and is_instance_valid(oldest):
			if oldest.has_method("destroy"):
				oldest.destroy()
			else:
				oldest.queue_free()
		active_summons.remove_at(0)

	var summon: CharacterBody2D = summon_scene.instantiate()
	var summon_config: Dictionary = _calculate_summon_config()

	var spawn_offset: Vector2 = Vector2(randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
	if player:
		summon.global_position = player.global_position + spawn_offset

	var parent_node: Node = get_tree().root
	if player and player.get_parent():
		parent_node = player.get_parent()
	parent_node.add_child(summon)
	summon.initialize(summon_config, player)
	active_summons.append(summon)

	print("[SummonWeapon] 召唤完成: ", active_summons.size(), "/", summon_limit)

func _cleanup_dead_summons() -> void:
	var cleaned_summons: Array[Node] = []
	for summon: Node in active_summons:
		if is_instance_valid(summon):
			cleaned_summons.append(summon)
	active_summons = cleaned_summons

## 计算召唤上限
## - weapon.csv: SummonCount
## - 商店加成: summon_count
func get_summon_limit() -> int:
	var base_limit: int = BASE_SUMMON_LIMIT
	var weapon_limit: int = int(weapon_template.get("summon_count", 0))
	if weapon_limit > base_limit:
		base_limit = weapon_limit

	var extra_summons: int = int(player.get_shop_bonus_value("summon_count"))
	return base_limit + extra_summons

##############################################################################
# 召唤配置（weapon.csv + summon.csv）
##############################################################################

func _calculate_summon_config() -> Dictionary:
	var config: Dictionary = {}
	var summon_unit_id: String = weapon_template.get("summon_unit_id", "")
	var summon_unit: Dictionary = {}
	if not summon_unit_id.is_empty():
		summon_unit = GameData.get_summon_unit(summon_unit_id)

	## 基础伤害优先使用summon.csv中的BaseDamage
	var base_damage: float = weapon_template.get("base_damage", 10.0)
	var summon_base: float = summon_unit.get("base_damage", 0.0)
	if summon_base > 0.0:
		base_damage = summon_base

	var summon_dmg_stat: float = player.get_final_stat("SummonDamage")
	var damage_mult: float = weapon_template.get("damage_mult", 1.0)
	var bonus_dmg: float = summon_dmg_stat * damage_mult

	var all_dmg_percent: float = player.get_final_stat("AllDamage")
	var all_dmg_mult: float = 1.0 + all_dmg_percent / 100.0

	var quality: String = weapon_instance.get("quality", "white")
	var quality_mult: float = _get_quality_multiplier(quality)

	var weapon_dmg_bonus: float = _get_weapon_damage_bonus()

	config["damage"] = (base_damage + bonus_dmg) * all_dmg_mult * quality_mult + weapon_dmg_bonus

	## 召唤暴击继承（商店解锁）
	if player.has_shop_bonus("summon_crit_inherit"):
		var crit_inherit_rate: float = player.get_shop_bonus_value("summon_crit_inherit") / 100.0
		config["crit_rate"] = player.get_final_stat("CritRate") * crit_inherit_rate
		config["crit_dmg"] = player.get_final_stat("CritDamage") * crit_inherit_rate
		print("[SummonWeapon] 召唤暴击继承=", crit_inherit_rate * 100, "%")
	else:
		config["crit_rate"] = 0.0
		config["crit_dmg"] = 0.0
		print("[SummonWeapon] 召唤暴击继承未解锁")

	config["attack_speed"] = weapon_template.get("summon_attack_speed", 1.0)
	config["attack_range"] = weapon_template.get("summon_attack_range", 600.0)

	## 图标优先使用weapon模板，否则回落到summon.csv
	config["sprite_id"] = weapon_template.get("summon_sprite_id", "")
	if config["sprite_id"].is_empty():
		config["sprite_id"] = summon_unit.get("sprite_id", "")

	## 行为标签与类型（summon.csv）
	config["summon_unit_id"] = summon_unit_id
	config["summon_type"] = summon_unit.get("summon_type", "")
	config["behavior_tags"] = summon_unit.get("behavior_tags", "")
	config["attack_mode"] = summon_unit.get("attack_mode", "")
	config["unique_mechanic"] = weapon_template.get("unique_mechanic", "")

	print("[SummonWeapon] 召唤配置:")
	print("  - damage=", config["damage"])
	print("  - crit_rate=", config["crit_rate"], "%")
	print("  - crit_dmg=", config["crit_dmg"], "%")

	return config

func _get_quality_multiplier(quality: String) -> float:
	match quality:
		"white": return 1.0
		"blue": return 1.15
		"purple": return 1.35
		"gold": return 1.6
		_: return 1.0

func _get_weapon_damage_bonus() -> float:
	var bonus: float = 0.0
	var attributes: Array = weapon_instance.get("attributes", [])
	for attr: Dictionary in attributes:
		if attr.get("type", "") == "damage":
			bonus += attr.get("value", 0.0)
	return bonus

##############################################################################
# DPS与接口
##############################################################################

func calculate_dps() -> float:
	var summon_config: Dictionary = _calculate_summon_config()
	var single_summon_damage: float = summon_config["damage"]
	var single_summon_attack_speed: float = summon_config["attack_speed"]
	var single_summon_dps: float = single_summon_damage / single_summon_attack_speed
	var summon_limit: int = get_summon_limit()
	return single_summon_dps * summon_limit

func get_display_name() -> String:
	return weapon_template.get("name_cn", "未知召唤武器")

func get_display_name_en() -> String:
	return weapon_template.get("name_en", "Unknown Weapon")

func update_cooldown() -> void:
	_calculate_cooldown()
	summon_timer.wait_time = current_cooldown
	for summon: Node in active_summons:
		if is_instance_valid(summon) and summon.has_method("update_config"):
			var new_config: Dictionary = _calculate_summon_config()
			summon.update_config(new_config)

func cleanup_all_summons() -> void:
	for summon: Node in active_summons:
		if is_instance_valid(summon):
			if summon.has_method("destroy"):
				summon.destroy()
			else:
				summon.queue_free()
	active_summons.clear()
	print("[SummonWeapon] 已清理所有召唤物")
