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

## 是否使用手动冷却（避免Timer与移动状态不同步）
const USE_MANUAL_COOLDOWN: bool = true

## 手动冷却计时器
var cooldown_left: float = 0.0

## 攻击计数
## 单位：次
## 作用：支持部分UniqueMechanic（例如每3次强化）
## 数据来源：_perform_attack()累加
var attack_count: int = 0

## 攻击动作描述（来自weapon.csv的actackWay）
var attack_way: String = ""

## 武器原始位置（用于动画复位）
var weapon_rest_position: Vector2 = Vector2.ZERO

## 是否正在攻击动画中
var is_attacking: bool = false

##############################################################################
# 爆炸特效参数
##############################################################################

## 爆炸VFX路径
## 作用：近战爆炸用的简约环形
const EXPLOSION_VFX_PATH: String = "res://assets/PIC/wuqi/VFX/256/vfx_mask_shockwave_ring.png"

## 爆炸VFX基础缩放
## 单位：倍数
## 调整范围：0.1-0.5
## 当前值：0.2
const EXPLOSION_VFX_SCALE: float = 0.2

## 爆炸VFX时长
## 单位：秒
## 调整范围：0.1-0.4
## 当前值：0.2
const EXPLOSION_VFX_DURATION: float = 0.2

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
# 运行时更新
##############################################################################

func _physics_process(delta: float) -> void:
	## 让攻击范围始终以玩家为中心
	if player and attack_area:
		attack_area.global_position = player.global_position

	## 武器位置由Player固定，不跟随玩家移动
	## 只在攻击时播放旋转动画
	if USE_MANUAL_COOLDOWN:
		cooldown_left -= delta
		if cooldown_left <= 0.0:
			_perform_attack()
			cooldown_left = current_cooldown

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
	attack_way = weapon_template.get("attack_way", weapon_template.get("actackWay", ""))

	# 1) 载入图标
	_load_sprite()

	# 2) 配置攻击范围
	_setup_attack_range()

	# 3) 计算冷却
	_calculate_cooldown()

	# 4) 设置碰撞层/掩码
	attack_area.collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER_PROJECTILE)
	attack_area.collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)
	attack_area.add_to_group("weapon_attack")
	attack_area.top_level = true  # 避免父节点移动导致攻击区域偏移
	attack_area.monitoring = true
	attack_area.monitorable = true

	# 5) 启动计时器
	cooldown_left = current_cooldown
	if not USE_MANUAL_COOLDOWN:
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
		_apply_handle_pivot(texture, sprite.scale)
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
	_apply_handle_pivot(texture, sprite.scale)

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
# 攻击范围
##############################################################################

## 设置攻击范围
##
## 作用：将attack_range写入CircleShape2D半径
func _setup_attack_range() -> void:
	var range: float = weapon_template.get("attack_range", 80.0)
	range = max(25.0, range)
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
	if USE_MANUAL_COOLDOWN:
		return
	_perform_attack()

## 执行攻击
##
## 流程：
## 1) 获取AttackArea内的敌人HurtBox
## 2) 找到最近敌人作为攻击方向
## 3) 播放攻击动画（朝向敌人移动武器）
## 4) 计算伤害并调用enemy.take_damage()
## 5) 输出调试信息
func _perform_attack() -> void:
	var origin: Vector2 = _get_attack_origin()
	var attack_range: float = weapon_template.get("attack_range", 80.0)
	attack_range = max(25.0, attack_range)
	var enemies: Array[Node2D] = _query_enemies_in_range(origin, attack_range)

	if enemies.is_empty():
		return

	var arc_deg: float = _get_attack_arc_deg()
	var base_dir: Vector2 = _get_base_attack_dir(enemies)

	# 播放攻击动画（朝向敌人方向）
	_play_attack_animation(base_dir)

	attack_count += 1
	var unique_mechanic: String = weapon_template.get("unique_mechanic", "")

	if "最多3目标" in unique_mechanic or "三目标" in unique_mechanic or "3目标" in unique_mechanic or "只能打三个" in unique_mechanic:
		enemies = enemies.slice(0, 3)

	var damage_mult: float = 1.0
	if "每3次强化" in unique_mechanic and attack_count % 3 == 0:
		damage_mult = 1.2

	## 单体突刺：只命中最近目标
	if "单体高伤" in unique_mechanic or "直线突刺" in unique_mechanic:
		enemies = enemies.slice(0, 1)

	for enemy: Node2D in enemies:
		# 360°旋转攻击不需要角度检查
		if arc_deg < 360.0 and base_dir != Vector2.ZERO:
			var enemy_dir: Vector2 = (enemy.global_position - origin).normalized()
			var angle_deg: float = rad_to_deg(base_dir.angle_to(enemy_dir))
			if abs(angle_deg) > arc_deg * 0.5:
				continue
		var damage: float = calculate_damage() * damage_mult

		if enemy.has_method("take_damage"):
			enemy.take_damage(damage)
			print("[MeleeWeapon] 命中: ", enemy.name, " damage=", int(damage))
			_continue_after_hit(enemy, damage, base_dir, unique_mechanic)
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
	cooldown_left = current_cooldown
	if not USE_MANUAL_COOLDOWN:
		attack_timer.wait_time = current_cooldown

##############################################################################
# 攻击模板（依据actackWay/UniqueMechanic）
##############################################################################

func _get_attack_arc_deg() -> float:
	var way: String = attack_way

	# 优先匹配具体角度
	if way.find("30°") != -1:
		return 30.0
	if way.find("45°") != -1:
		return 45.0
	if way.find("60°") != -1:
		return 60.0
	if way.find("90°") != -1:
		return 90.0

	# 匹配攻击类型
	if way.find("垂直") != -1 or way.find("突刺") != -1:
		return 20.0
	if way.find("横扫") != -1:
		return 90.0
	if way.find("旋转") != -1:
		return 360.0  # 旋转攻击全向

	# 从UniqueMechanic中提取
	var unique_mechanic: String = weapon_template.get("unique_mechanic", "")
	if unique_mechanic.find("小范围挥击") != -1:
		return 20.0
	if unique_mechanic.find("扇形横扫") != -1:
		return 100.0
	if unique_mechanic.find("横扫范围更大") != -1:
		return 100.0

	# 默认：如果是近战武器但没有定义actackWay，使用45°作为默认扇形
	# 远程武器（有ProjectileID）不会使用这个函数
	return 45.0

func _get_base_attack_dir(enemies: Array[Node2D]) -> Vector2:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	var origin: Vector2 = _get_attack_origin()
	for enemy: Node2D in enemies:
		var dist: float = origin.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	if nearest:
		return (nearest.global_position - origin).normalized()
	return Vector2.ZERO

## 获取攻击中心（默认使用玩家位置）
##
## 参数：无
## 返回：
##   攻击中心位置
func _get_attack_origin() -> Vector2:
	return global_position

## 查询范围内敌人（使用物理查询，避免group/Area延迟）
##
## 参数：
##   origin - 中心点
##   radius - 半径
## 返回：
##   敌人节点数组
func _query_enemies_in_range(origin: Vector2, radius: float) -> Array[Node2D]:
	var results: Array[Node2D] = []
	var mines: Array[Node2D] = []
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, origin)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY)

	var hits: Array = space_state.intersect_shape(params, 16)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Node2D:
			var enemy: Node2D = collider
			if enemy.is_in_group("enemy"):
				results.append(enemy)
			elif enemy.is_in_group("mine"):
				mines.append(enemy)
	if not results.is_empty():
		return results
	## 无敌人时允许攻击矿点
	return mines

func _continue_after_hit(enemy: Node2D, damage: float, base_dir: Vector2, unique_mechanic: String) -> void:
	## 小范围爆炸
	if "小范围爆炸" in unique_mechanic or "爆炸" in unique_mechanic:
		_apply_aoe_damage(enemy.global_position, 80.0, damage)
		_spawn_explosion_vfx(enemy.global_position)

func _apply_aoe_damage(center: Vector2, radius: float, damage: float) -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	for node: Node in enemies:
		if node is Node2D:
			var dist: float = center.distance_to(node.global_position)
			if dist <= radius:
				if node.has_method("take_damage"):
					node.take_damage(damage)

## 爆炸特效（低性能开销）
func _spawn_explosion_vfx(pos: Vector2) -> void:
	if not ResourceLoader.exists(EXPLOSION_VFX_PATH):
		return
	var vfx_node: Node2D = Node2D.new()
	var vfx_sprite: Sprite2D = Sprite2D.new()
	vfx_sprite.texture = load(EXPLOSION_VFX_PATH)
	vfx_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vfx_sprite.scale = Vector2(EXPLOSION_VFX_SCALE, EXPLOSION_VFX_SCALE)
	vfx_node.add_child(vfx_sprite)
	get_parent().add_child(vfx_node)
	vfx_node.global_position = pos
	var tween: Tween = vfx_node.create_tween()
	tween.tween_property(vfx_sprite, "scale", vfx_sprite.scale * 1.8, EXPLOSION_VFX_DURATION)
	tween.parallel().tween_property(vfx_sprite, "modulate:a", 0.0, EXPLOSION_VFX_DURATION)
	tween.tween_callback(vfx_node.queue_free)

##############################################################################
# 攻击动作表现
##############################################################################

## 播放攻击动画
##
## 参数：
##   attack_direction - 攻击方向（归一化向量）
## 作用：
##   - 武器向外挥砍（移动位置+旋转）
##   - 动画匹配实际攻击范围
func _play_attack_animation(attack_direction: Vector2) -> void:
	if not sprite:
		return

	is_attacking = true

	var tween: Tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 获取攻击范围（用于计算挥砍距离）
	var attack_range: float = weapon_template.get("attack_range", 120.0)
	var swing_distance: float = attack_range * 0.8  # 挥砍移动距离为攻击范围的80%

	# 记录原始位置和旋转
	var original_pos: Vector2 = position
	var original_sprite_rot: float = sprite.rotation

	# 挥砍角度范围（在朝向敌人的基础上的偏移）
	var swing_angle_offset: float = 0.4
	if "45" in attack_way:
		swing_angle_offset = 0.6
	elif "垂直" in attack_way:
		swing_angle_offset = 0.5
	elif "横" in attack_way:
		swing_angle_offset = 0.2

	# 旋转攻击模式
	if "旋转" in attack_way:
		# 旋转360度攻击
		tween.parallel().tween_property(sprite, "rotation", sprite.rotation + TAU, 0.20)
		tween.tween_callback(func(): is_attacking = false)
		return

	# 挥砍动画（更慢更流畅）
	var anim_duration: float = 0.18
	var return_duration: float = 0.10

	# 第二步：朝向敌人方向挥砍（包含前后摆动）
	# 向后蓄力
	var swing_back_angle: float = -swing_angle_offset
	var swing_forward_angle: float = swing_angle_offset

	# 同时执行旋转和位移
	tween.parallel().tween_property(sprite, "rotation", swing_forward_angle, anim_duration)
	tween.parallel().tween_property(self, "position", original_pos + attack_direction * swing_distance, anim_duration)

	# 第三步：复位
	tween.tween_property(sprite, "rotation", original_sprite_rot, return_duration)
	tween.parallel().tween_property(self, "position", original_pos, return_duration)

	# 动画完成后重置状态
	tween.tween_callback(func(): is_attacking = false)

## 获取攻击状态
##
## 参数：无
## 返回：
##   true/false
func get_is_attacking() -> bool:
	return is_attacking
