##############################################################################
# RangedWeapon - 远程武器脚本
#
# 设计目的：
# - 以武器模板（weapon.csv）为核心，驱动远程投射物攻击
# - 负责冷却、发射方向、投射物参数拼装
#
# CSV字段对齐（weapon.csv）：
# - WeaponID      -> weapon_template["weapon_id"]
# - DisplayName   -> name_cn
# - BonusClass    -> bonus_class
# - BaseDamage    -> base_damage
# - DamageMult    -> damage_mult
# - CritMult      -> crit_mult
# - CritInherit   -> crit_rate_inherit / crit_dmg_inherit
# - ProjectileID  -> projectile_id
# - PierceCount   -> pierce_count
# - BaseCooldown  -> base_cooldown
# - BaseRange     -> attack_range
# - IconID        -> icon_id
# - UniqueMechanic-> 目前仅注释（未实现复杂机制）
#
# 调用链：
# - Player.add_weapon -> weapon.initialize
# - AttackTimer.timeout -> _on_attack_timer_timeout -> _perform_attack
# - Projectile.initialize 由本脚本调用
##############################################################################
extends Node2D

##############################################################################
# 变量（运行期）
##############################################################################

## 武器模板数据（来自GameData.get_weapon -> weapon.csv）
var weapon_template: Dictionary = {}

## 武器实例数据（来自Player.weapon_slots）
var weapon_instance: Dictionary = {}

## 玩家引用（读取角色属性）
var player: CharacterBody2D = null

## 当前冷却（秒）
var current_cooldown: float = 1.0

## 投射物场景（玩家投射物）
var projectile_scene: PackedScene = null

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_point: Marker2D = $ShootPoint
@onready var attack_timer: Timer = $AttackTimer

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	## 预加载投射物场景
	projectile_scene = load("res://scenes/weapons/projectile.tscn")

## 初始化武器
## 参数：
## - template: weapon.csv解析后的模板
## - instance: 武器实例（品质/词条/槽位等）
## - owner_player: 玩家
func initialize(template: Dictionary, instance: Dictionary, owner_player: CharacterBody2D) -> void:
	weapon_template = template
	weapon_instance = instance
	player = owner_player

	_load_sprite()
	_calculate_cooldown()

	attack_timer.wait_time = current_cooldown
	attack_timer.start()

	print("[RangedWeapon] 初始化完成:")
	print("  - 名称=", weapon_template.get("name_cn", "未知"))
	print("  - 射程=", weapon_template.get("attack_range", 0), "px")
	print("  - 弹速=", weapon_template.get("projectile_speed", 0), "px/s")
	print("  - 冷却=", current_cooldown, "s")

##############################################################################
# 图标加载
##############################################################################

func _load_sprite() -> void:
	var icon_id: String = weapon_template.get("icon_id", "")
	if icon_id.is_empty():
		if sprite:
			sprite.visible = false
		return

	var sprite_path: String = "res://assets/PIC/wuqi/icon/256/" + icon_id + ".png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		sprite.scale = Vector2(0.25, 0.25)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		print("[RangedWeapon] 图标加载成功: ", sprite_path)
	else:
		_generate_placeholder_sprite()

func _generate_placeholder_sprite() -> void:
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var weapon_id: String = weapon_template.get("id", "default")
	var hash_value: int = weapon_id.hash()
	var r: float = float((hash_value >> 16) & 0xFF) / 255.0
	var g: float = float((hash_value >> 8) & 0xFF) / 255.0
	var b: float = float(hash_value & 0xFF) / 255.0
	img.fill(Color(r, g, b, 1.0))
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.scale = Vector2(1.0, 1.0)

##############################################################################
# 冷却计算
##############################################################################

func _calculate_cooldown() -> void:
	## 基础冷却与武器自身倍率
	var base_cooldown: float = weapon_template.get("base_cooldown", 1.0)
	var cooldown_mult: float = weapon_template.get("cooldown_mult", 1.0)

	## 玩家CDR继承
	var cdr_inherit: float = weapon_template.get("cdr_inherit", 1.0)
	var player_cdr: float = player.get_final_stat("Cooldown")
	var cdr_mult: float = 1.0 - (cdr_inherit * player_cdr / 100.0)

	current_cooldown = base_cooldown * cooldown_mult * cdr_mult
	current_cooldown = max(current_cooldown, 0.1)

##############################################################################
# 攻击逻辑
##############################################################################

func _on_attack_timer_timeout() -> void:
	_perform_attack()

## 发射投射物
func _perform_attack() -> void:
	var shoot_direction: Vector2 = _get_shoot_direction()
	if shoot_direction == Vector2.ZERO:
		return

	var damage: float = calculate_damage()

	## 从projectile.csv读取投射物配置
	var projectile_id: String = weapon_template.get("projectile_id", "")
	var projectile_cfg: Dictionary = {}
	if not projectile_id.is_empty():
		projectile_cfg = GameData.get_projectile(projectile_id)

	var projectile_speed: float = projectile_cfg.get("speed_pxps", weapon_template.get("projectile_speed", 600.0))
	var pierce_count: int = weapon_template.get("pierce_count", 0)
	var pierce_dmg_mult: float = weapon_template.get("pierce_dmg_mult", 1.0)
	var sprite_id: String = projectile_cfg.get("sprite_id", weapon_template.get("sprite_id", ""))
	var hit_limit: int = int(projectile_cfg.get("hit_limit", 0))
	var projectile_type: String = projectile_cfg.get("type", "")
	if hit_limit > 0:
		pierce_count = max(hit_limit - 1, 0)

	var attack_range: float = weapon_template.get("attack_range", 500.0)
	var use_weapon_range: bool = projectile_cfg.get("use_weapon_range", true)
	if not use_weapon_range:
		attack_range = 800.0

	var hit_radius: float = projectile_cfg.get("hit_radius_px", 0.0)
	var homing: bool = projectile_cfg.get("homing", false)
	var explode: bool = projectile_cfg.get("explode", false)
	var explode_radius: float = projectile_cfg.get("explode_radius_px", 0.0)
	var area_duration: float = projectile_cfg.get("area_duration_s", 0.0)
	var vfx_hit_id: String = projectile_cfg.get("vfx_hit_id", "")

	## 连锁类型：链数=HitLimit
	var chain_limit: int = 0
	if "连锁" in projectile_type and hit_limit > 0:
		chain_limit = hit_limit

	var projectile: Area2D = projectile_scene.instantiate()
	projectile.global_position = shoot_point.global_position
	get_tree().root.add_child(projectile)

	projectile.initialize(
		shoot_direction,
		projectile_speed,
		damage,
		pierce_count,
		pierce_dmg_mult,
		sprite_id,
		attack_range,
		hit_radius,
		homing,
		explode,
		explode_radius,
		area_duration,
		projectile_type,
		chain_limit,
		vfx_hit_id
	)

	print("[RangedWeapon] 发射投射物: dir=", shoot_direction, " damage=", int(damage))

## 获取射击方向（优先最近敌人）
func _get_shoot_direction() -> Vector2:
	var nearest_enemy: Node2D = _find_nearest_enemy()
	if nearest_enemy:
		return (nearest_enemy.global_position - global_position).normalized()

	var mouse_pos: Vector2 = get_global_mouse_position()
	return (mouse_pos - global_position).normalized()

## 查找最近敌人
func _find_nearest_enemy() -> Node2D:
	var attack_range: float = weapon_template.get("attack_range", 500.0)
	var all_enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")

	var nearest_enemy: Node2D = null
	var nearest_distance: float = INF
	for enemy: Node in all_enemies:
		if enemy is Node2D:
			var distance: float = global_position.distance_to(enemy.global_position)
			if distance <= attack_range and distance < nearest_distance:
				nearest_distance = distance
				nearest_enemy = enemy
	return nearest_enemy

##############################################################################
# 伤害计算
##############################################################################

func calculate_damage() -> float:
	var base_damage: float = weapon_template.get("base_damage", 10.0)
	var bonus_class: String = weapon_template.get("bonus_class", "R")
	var damage_mult: float = weapon_template.get("damage_mult", 1.0)

	## BonusClass决定受哪些属性加成
	var bonus_stat_name: String = ""
	match bonus_class:
		"M": bonus_stat_name = "MeleeDamage"
		"R": bonus_stat_name = "RangedDamage"
		"E": bonus_stat_name = "ElementalDamage"
		"S": bonus_stat_name = "SummonDamage"
		_: bonus_stat_name = "RangedDamage"

	var player_bonus_stat: float = player.get_final_stat(bonus_stat_name)
	var bonus_dmg: float = player_bonus_stat * damage_mult
	var all_dmg_percent: float = player.get_final_stat("AllDamage")
	var all_dmg_mult: float = 1.0 + all_dmg_percent / 100.0
	var quality: String = weapon_instance.get("quality", "white")
	var quality_mult: float = _get_quality_multiplier(quality)
	var weapon_dmg_bonus: float = _get_weapon_damage_bonus()
	var final_dmg: float = (base_damage + bonus_dmg) * all_dmg_mult * quality_mult + weapon_dmg_bonus

	## 暴击判定
	var crit_rate_inherit: float = weapon_template.get("crit_rate_inherit", 1.0)
	var weapon_crit_rate: float = player.get_final_stat("CritRate") * crit_rate_inherit
	if randf() * 100.0 < weapon_crit_rate:
		var crit_dmg_inherit: float = weapon_template.get("crit_dmg_inherit", 1.0)
		var weapon_crit_dmg: float = player.get_final_stat("CritDamage") * crit_dmg_inherit
		var crit_base: float = weapon_template.get("crit_mult", 1.5)
		var crit_mult: float = crit_base + weapon_crit_dmg / 100.0
		final_dmg *= crit_mult
		print("[RangedWeapon] 暴击触发: crit_mult=", crit_mult)

	return final_dmg

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
# DPS计算与接口
##############################################################################

func calculate_dps() -> float:
	var avg_damage: float = calculate_damage()
	return avg_damage / current_cooldown

func get_display_name() -> String:
	return weapon_template.get("name_cn", "未知武器")

func get_display_name_en() -> String:
	return weapon_template.get("name_en", "Unknown Weapon")

func update_cooldown() -> void:
	_calculate_cooldown()
	attack_timer.wait_time = current_cooldown
