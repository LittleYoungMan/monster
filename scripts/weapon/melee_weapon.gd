##############################################################################
# MeleeWeapon - 近战武器脚本
#
# 作用：
# - 读取武器模板与实例数据，完成武器初始化
# - 使用AttackArea检测敌人并造成伤害
# - 计算伤害（基础/职业加成/全伤害/品质/暴击/工坊属性）
# - 生成武器图标或占位图
#
# 主要调用关系：
# - Player.add_weapon() -> weapon.initialize()
# - AttackTimer.timeout -> _on_attack_timer_timeout() -> _perform_attack()
# - Enemy.take_damage() 由本脚本调用
#
# 引擎回调：
# - _on_attack_timer_timeout() 由Timer信号触发
#
# 已实现：攻击、冷却、伤害计算、暴击、品质加成
# 未实现：更复杂的UniqueMechanic解析与多段特效
#
# 修改点：2026-01-27 恢复中文注释与打印\n#\n# CSV字段对齐（weapon.csv）：\n# - WeaponID / DisplayName / BonusClass / BaseDamage / DamageMult / CritMult\n# - CritInherit / PierceCount / BaseCooldown / BaseRange / UniqueMechanic / IconID\n
##############################################################################
extends Node2D

##############################################################################
# 变量
##############################################################################

## 武器模板数据
## 单位：无
## 作用：存储武器静态配置（基础伤害/冷却/范围/继承系数等）
## 数据来源：GameData.get_weapon(weapon_id)
## 使用位置：initialize(), calculate_damage(), _setup_attack_range(), _calculate_cooldown()
var weapon_template: Dictionary = {}

## 武器实例数据
## 单位：无
## 作用：存储武器实例信息（品质/工坊属性/槽位）
## 数据来源：Player.weapon_slots[i]
## 使用位置：calculate_damage(), _get_weapon_damage_bonus()
var weapon_instance: Dictionary = {}

## 玩家引用
## 单位：无
## 作用：读取玩家最终属性（冷却/暴击/职业伤害等）
## 数据来源：initialize()传入
## 使用位置：_calculate_cooldown(), calculate_damage()
var player: CharacterBody2D = null

## 当前实际冷却
## 单位：秒
## 作用：控制AttackTimer间隔
## 数据来源：_calculate_cooldown()
## 使用位置：initialize(), update_cooldown()
var current_cooldown: float = 1.0

## 攻击计数
## 单位：次
## 作用：支持部分UniqueMechanic（例如每3次强化）
## 数据来源：_perform_attack()累加
var attack_count: int = 0

##############################################################################
# 节点引用
##############################################################################

## 武器图标
@onready var sprite: Sprite2D = $Sprite2D

## 攻击区域（检测敌人HurtBox）
@onready var attack_area: Area2D = $AttackArea

## 攻击范围Shape（CircleShape2D）
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D

## 攻击计时器
@onready var attack_timer: Timer = $AttackTimer

##############################################################################
# 初始化
##############################################################################

## 初始化武器
##
## 参数：
##   template - 武器模板数据（GameData.get_weapon）
##   instance - 武器实例数据（品质/属性）
##   owner_player - 玩家引用
##
## 返回：
##   无
##
## 调用链：
##   Player.add_weapon -> weapon.initialize
##
## 引擎/系统调用：
##   AttackTimer.timeout -> _on_attack_timer_timeout
func initialize(template: Dictionary, instance: Dictionary, owner_player: CharacterBody2D) -> void:
	weapon_template = template
	weapon_instance = instance
	player = owner_player

	# 1) 载入图标
	_load_sprite()

	# 2) 配置攻击范围
	_setup_attack_range()

	# 3) 计算冷却
	_calculate_cooldown()

	# 4) 设置碰撞层/掩码
	attack_area.collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER_PROJECTILE)
	attack_area.collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)

	# 5) 启动计时器
	attack_timer.wait_time = current_cooldown
	attack_timer.start()

	print("[MeleeWeapon] 初始化完成:")
	print("  - 名称(name_cn)=", weapon_template.get("name_cn", "未知"))
	print("  - 范围(attack_range)=", weapon_template.get("attack_range", 0), "px")
	print("  - 冷却(current_cooldown)=", current_cooldown, "s")
	print("  - 品质(quality)=", weapon_instance.get("quality", "white"))

##############################################################################
# 图标加载
##############################################################################

## 载入武器图标
##
## 作用：根据icon_id加载图标；不存在则生成占位图
## 调用：_generate_placeholder_sprite()
func _load_sprite() -> void:
	var icon_id: String = weapon_template.get("icon_id", "")
	if icon_id.is_empty():
		if sprite:
			sprite.visible = false
		print("[MeleeWeapon] 图标缺失：icon_id为空")
		return

	var sprite_path: String = "res://assets/PIC/wuqi/icon/256/" + icon_id + ".png"
	if ResourceLoader.exists(sprite_path):
		var texture: Texture2D = load(sprite_path)
		sprite.texture = texture
		sprite.scale = Vector2(0.25, 0.25)  # 256 -> 64
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		print("[MeleeWeapon] 图标加载成功: ", sprite_path)
	else:
		print("[MeleeWeapon] 图标不存在: ", sprite_path, "，生成占位图")
		_generate_placeholder_sprite()

## 生成占位图
##
## 作用：用武器ID哈希生成颜色块，避免空白
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
	print("[MeleeWeapon] 占位图生成: RGB(", r, ",", g, ",", b, ")")

##############################################################################
# 攻击范围
##############################################################################

## 设置攻击范围
##
## 作用：将attack_range写入CircleShape2D半径
func _setup_attack_range() -> void:
	var range: float = weapon_template.get("attack_range", 80.0)
	if attack_shape and attack_shape.shape is CircleShape2D:
		attack_shape.shape.radius = range
		print("[MeleeWeapon] 攻击范围已设置: ", range, "px")
	else:
		push_error("[MeleeWeapon] AttackArea的CollisionShape2D不是CircleShape2D")

##############################################################################
# 冷却计算
##############################################################################

## 计算实际冷却
##
## 公式：
##   actual = base_cooldown * cooldown_mult * (1 - cdr_inherit * player_cdr / 100)
func _calculate_cooldown() -> void:
	var base_cooldown: float = weapon_template.get("base_cooldown", 1.0)
	var cooldown_mult: float = weapon_template.get("cooldown_mult", 1.0)
	var cdr_inherit: float = weapon_template.get("cdr_inherit", 1.0)
	var player_cdr: float = player.get_final_stat("Cooldown")
	var cdr_mult: float = 1.0 - (cdr_inherit * player_cdr / 100.0)

	current_cooldown = base_cooldown * cooldown_mult * cdr_mult
	current_cooldown = max(current_cooldown, 0.1)

	print("[MeleeWeapon] 冷却计算:")
	print("  - base_cooldown=", base_cooldown, "s")
	print("  - cooldown_mult=", cooldown_mult)
	print("  - cdr_inherit=", cdr_inherit)
	print("  - player_cdr=", player_cdr, "%")
	print("  - current_cooldown=", current_cooldown, "s")

##############################################################################
# 攻击逻辑
##############################################################################

## Timer回调
func _on_attack_timer_timeout() -> void:
	_perform_attack()

## 执行攻击
##
## 流程：
## 1) 获取AttackArea内的敌人HurtBox
## 2) 计算伤害并调用enemy.take_damage()
## 3) 输出调试信息
func _perform_attack() -> void:
	var overlapping_areas: Array[Area2D] = attack_area.get_overlapping_areas()

	var enemies: Array[Node2D] = []
	for area: Area2D in overlapping_areas:
		if area.is_in_group("enemy_hurtbox"):
			var enemy: Node2D = area.get_parent()
			if enemy and enemy.is_in_group("enemy"):
				enemies.append(enemy)

	if enemies.is_empty():
		return

	attack_count += 1
	var unique_mechanic: String = weapon_template.get("unique_mechanic", "")

	if "最多3目标" in unique_mechanic or "三目标" in unique_mechanic or "3目标" in unique_mechanic:
		enemies = enemies.slice(0, 3)

	var damage_mult: float = 1.0
	if "每3次强化" in unique_mechanic and attack_count % 3 == 0:
		damage_mult = 1.2

	for enemy: Node2D in enemies:
		var damage: float = calculate_damage() * damage_mult
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage)
			print("[MeleeWeapon] 命中: ", enemy.name, " damage=", int(damage))
		else:
			push_warning("[MeleeWeapon] 目标没有take_damage(): ", enemy.name)

##############################################################################
# 伤害计算
##############################################################################

## 计算最终伤害
##
## 返回：
##   最终伤害值（float）
func calculate_damage() -> float:
	var base_damage: float = weapon_template.get("base_damage", 10.0)

	var bonus_class: String = weapon_template.get("bonus_class", "M")
	var damage_mult: float = weapon_template.get("damage_mult", 1.0)

	var bonus_stat_name: String = ""
	match bonus_class:
		"M": bonus_stat_name = "MeleeDamage"
		"R": bonus_stat_name = "RangedDamage"
		"E": bonus_stat_name = "ElementalDamage"
		"S": bonus_stat_name = "SummonDamage"
		_: bonus_stat_name = "MeleeDamage"

	var player_bonus_stat: float = player.get_final_stat(bonus_stat_name)
	var bonus_dmg: float = player_bonus_stat * damage_mult

	var all_dmg_percent: float = player.get_final_stat("AllDamage")
	var all_dmg_mult: float = 1.0 + all_dmg_percent / 100.0

	var quality: String = weapon_instance.get("quality", "white")
	var quality_mult: float = _get_quality_multiplier(quality)

	var weapon_dmg_bonus: float = _get_weapon_damage_bonus()

	var final_dmg: float = (base_damage + bonus_dmg) * all_dmg_mult * quality_mult + weapon_dmg_bonus

	var crit_rate_inherit: float = weapon_template.get("crit_rate_inherit", 1.0)
	var weapon_crit_rate: float = player.get_final_stat("CritRate") * crit_rate_inherit

	if randf() * 100.0 < weapon_crit_rate:
		var crit_dmg_inherit: float = weapon_template.get("crit_dmg_inherit", 1.0)
		var weapon_crit_dmg: float = player.get_final_stat("CritDamage") * crit_dmg_inherit
		var crit_base: float = weapon_template.get("crit_mult", 1.5)
		var crit_mult: float = crit_base + weapon_crit_dmg / 100.0
		final_dmg *= crit_mult
		print("[MeleeWeapon] 暴击触发: crit_mult=", crit_mult)

	return final_dmg

## 获取品质倍率
func _get_quality_multiplier(quality: String) -> float:
	match quality:
		"white":
			return 1.0
		"blue":
			return 1.15
		"purple":
			return 1.35
		"gold":
			return 1.6
		_:
			push_warning("[MeleeWeapon] 未知品质: ", quality, "，使用white倍率")
			return 1.0

## 获取工坊属性中的伤害加成
func _get_weapon_damage_bonus() -> float:
	var bonus: float = 0.0
	var attributes: Array = weapon_instance.get("attributes", [])
	for attr: Dictionary in attributes:
		if attr.get("type", "") == "damage":
			bonus += attr.get("value", 0.0)
	return bonus

##############################################################################
# DPS计算
##############################################################################

## 计算DPS
func calculate_dps() -> float:
	var avg_damage: float = calculate_damage()
	return avg_damage / current_cooldown

##############################################################################
# 公开接口
##############################################################################

func get_display_name() -> String:
	return weapon_template.get("name_cn", "未知武器")

func get_display_name_en() -> String:
	return weapon_template.get("name_en", "Unknown Weapon")

## 冷却变化时刷新
func update_cooldown() -> void:
	_calculate_cooldown()
	attack_timer.wait_time = current_cooldown
