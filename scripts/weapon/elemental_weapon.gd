##############################################################################
# ElementalWeapon - 元素武器脚本
#
# 设计目的：
# - 以“范围AOE”为核心攻击方式
# - 利用玩家属性：燃烧/减速/冻结等状态触发概率
# - 叠加爆炸伤害/范围相关加成
#
# CSV字段对齐（weapon.csv）：
# - BaseDamage / DamageMult / BaseCooldown / BaseRange / IconID
# - BonusClass决定加成属性
#
# 调用链：
# - Player.add_weapon -> initialize
# - AttackTimer.timeout -> _on_attack_timer_timeout -> _perform_attack
#
# 已实现：范围伤害/状态触发/爆炸范围加成
# 未实现：复杂状态叠加/抗性系统
##############################################################################
extends Node2D

##############################################################################
# 变量（运行期）
##############################################################################

## 武器模板数据（来自GameData.get_weapon）
var weapon_template: Dictionary = {}

## 武器实例数据（品质/词条/槽位）
var weapon_instance: Dictionary = {}

## 玩家引用
var player: CharacterBody2D = null

## 当前冷却（秒）
var current_cooldown: float = 1.0

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var attack_timer: Timer = $AttackTimer
@onready var vfx_particles: GPUParticles2D = $VFXParticles

##############################################################################
# 爆炸特效参数
##############################################################################

## 爆炸VFX路径
const ELEMENT_VFX_PATH: String = "res://assets/PIC/wuqi/VFX/256/vfx_mask_explosion_core.png"

## 爆炸VFX基础缩放
const ELEMENT_VFX_SCALE: float = 0.25

## 爆炸VFX时长
const ELEMENT_VFX_DURATION: float = 0.2

##############################################################################
# 初始化
##############################################################################

func initialize(template: Dictionary, instance: Dictionary, owner_player: CharacterBody2D) -> void:
	weapon_template = template
	weapon_instance = instance
	player = owner_player

	_load_sprite()
	_setup_attack_range()
	_calculate_cooldown()

	attack_area.collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER_PROJECTILE)
	attack_area.collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)

	attack_timer.wait_time = current_cooldown
	attack_timer.start()

	print("[ElementalWeapon] 初始化完成: ", weapon_template.get("name_cn", "未知"))

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
	img.fill(Color(1.0, 0.5, 0.0, 1.0))
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
# 范围与冷却
##############################################################################

func _setup_attack_range() -> void:
	var base_range: float = weapon_template.get("attack_range", 120.0)
	var explosion_range_bonus: float = player.get_final_stat("ExplosionRange")
	var range_bonus: float = player.get_final_stat("Range")
	var final_range: float = base_range + explosion_range_bonus + range_bonus

	if attack_shape and attack_shape.shape is CircleShape2D:
		attack_shape.shape.radius = final_range
		print(
			"[ElementalWeapon] 攻击范围=",
			final_range,
			"px (base=",
			base_range,
			"+爆炸范围=",
			explosion_range_bonus,
			"+范围=",
			range_bonus,
			")"
		)

func _calculate_cooldown() -> void:
	var base_cooldown: float = weapon_template.get("base_cooldown", 1.2)
	var cooldown_mult: float = weapon_template.get("cooldown_mult", 1.0)
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

func _perform_attack() -> void:
	var enemies: Array[Node2D] = []
	for area: Area2D in attack_area.get_overlapping_areas():
		if area.is_in_group("enemy_hurtbox"):
			var enemy: Node2D = area.get_parent()
			if enemy and enemy.is_in_group("enemy"):
				enemies.append(enemy)

	if enemies.is_empty():
		return

	for enemy: Node2D in enemies:
		var damage: float = calculate_damage()
		enemy.take_damage(damage)
		_apply_elemental_effects(enemy, damage)
		print("[ElementalWeapon] 命中: ", enemy.name, " damage=", int(damage))

	_play_attack_animation()
	_play_vfx()

## 施加元素状态（燃烧/减速/冻结）
func _apply_elemental_effects(enemy: Node2D, dealt_damage: float) -> void:
	var burn_chance: float = player.get_final_stat("BurnChance")
	if randf() * 100.0 < burn_chance:
		if enemy.has_method("apply_burn"):
			enemy.apply_burn(dealt_damage)
			print("[ElementalWeapon] 触发燃烧")

	var slow_chance: float = player.get_final_stat("SlowChance")
	if randf() * 100.0 < slow_chance:
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(GameData.SLOW_DURATION, GameData.SLOW_MULTIPLIER)
			print("[ElementalWeapon] 触发减速")

	var freeze_chance: float = player.get_final_stat("FreezeChance")
	if randf() * 100.0 < freeze_chance:
		if enemy.has_method("apply_freeze"):
			enemy.apply_freeze(1.1)
			print("[ElementalWeapon] 触发冻结")

func _play_vfx() -> void:
	## 低成本VFX：短暂缩放+淡出
	if not ResourceLoader.exists(ELEMENT_VFX_PATH):
		return
	var vfx_node: Node2D = Node2D.new()
	var vfx_sprite: Sprite2D = Sprite2D.new()
	vfx_sprite.texture = load(ELEMENT_VFX_PATH)
	vfx_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vfx_sprite.scale = Vector2(ELEMENT_VFX_SCALE, ELEMENT_VFX_SCALE)
	vfx_node.add_child(vfx_sprite)
	get_parent().add_child(vfx_node)
	vfx_node.global_position = global_position
	var tween: Tween = vfx_node.create_tween()
	tween.tween_property(vfx_sprite, "scale", vfx_sprite.scale * 1.7, ELEMENT_VFX_DURATION)
	tween.parallel().tween_property(vfx_sprite, "modulate:a", 0.0, ELEMENT_VFX_DURATION)
	tween.tween_callback(vfx_node.queue_free)

func _play_attack_animation() -> void:
	if not sprite:
		return
	var base_scale: Vector2 = sprite.scale
	var base_rot: float = sprite.rotation
	var target_rot: float = base_rot + randf_range(-0.10, 0.10)
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", base_scale * 1.12, 0.06)
	tween.parallel().tween_property(sprite, "rotation", target_rot, 0.06)
	tween.tween_property(sprite, "scale", base_scale, 0.12)
	tween.parallel().tween_property(sprite, "rotation", base_rot, 0.12)

##############################################################################
# 伤害计算
##############################################################################

func calculate_damage() -> float:
	var base_damage: float = weapon_template.get("base_damage", 12.0)
	var bonus_class: String = weapon_template.get("bonus_class", "E")
	var damage_mult: float = weapon_template.get("damage_mult", 1.0)

	var bonus_stat_name: String = ""
	match bonus_class:
		"M": bonus_stat_name = "MeleeDamage"
		"R": bonus_stat_name = "RangedDamage"
		"E": bonus_stat_name = "ElementalDamage"
		"S": bonus_stat_name = "SummonDamage"
		_: bonus_stat_name = "ElementalDamage"

	var player_bonus_stat: float = player.get_final_stat(bonus_stat_name)
	var bonus_dmg: float = player_bonus_stat * damage_mult
	var all_dmg_percent: float = player.get_final_stat("AllDamage")
	var all_dmg_mult: float = 1.0 + all_dmg_percent / 100.0

	var quality: String = weapon_instance.get("quality", "white")
	var quality_mult: float = _get_quality_multiplier(quality)

	var weapon_dmg_bonus: float = _get_weapon_damage_bonus()
	var explosion_dmg_bonus: float = player.get_final_stat("ExplosionDamage")

	var final_dmg: float = (base_damage + bonus_dmg + explosion_dmg_bonus) * all_dmg_mult * quality_mult + weapon_dmg_bonus

	var crit_rate_inherit: float = weapon_template.get("crit_rate_inherit", 1.0)
	var weapon_crit_rate: float = player.get_final_stat("CritRate") * crit_rate_inherit
	if randf() * 100.0 < weapon_crit_rate:
		var crit_dmg_inherit: float = weapon_template.get("crit_dmg_inherit", 1.0)
		var weapon_crit_dmg: float = player.get_final_stat("CritDamage") * crit_dmg_inherit
		var crit_base: float = weapon_template.get("crit_mult", 1.5)
		var crit_mult: float = crit_base + weapon_crit_dmg / 100.0
		final_dmg *= crit_mult
		print("[ElementalWeapon] 暴击触发: crit_mult=", crit_mult)

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
# DPS与接口
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
	_setup_attack_range()
