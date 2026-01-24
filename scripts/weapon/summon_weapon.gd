##############################################################################
# SummonWeapon - 召唤武器
#
# 功能说明：
# 1. 继承WeaponBase，实现召唤武器的逻辑
# 2. 召唤单位（随从/炮台/爆体）
# 3. 管理召唤单位的数量和生命周期
# 4. 召唤物属性继承系统
#
# 场景结构：
#   SummonWeapon (Node2D)
#     └─ AttackTimer (Timer) - 召唤冷却
##############################################################################
extends WeaponBase
class_name SummonWeapon

##############################################################################
# 召唤单位场景
##############################################################################

const SUMMON_UNIT_SCENE: PackedScene = preload("res://scenes/weapons/summon_unit.tscn")

##############################################################################
# 召唤配置
##############################################################################

## 召唤单位数据（从GameData加载）
var summon_unit_data: Dictionary = {}

## 每次召唤数量
var summon_count: int = 1

## 当前存活的召唤物列表
var active_summons: Array[Node2D] = []

## 最大同时存在数量
var max_active: int = 4

##############################################################################
# 初始化
##############################################################################

## 初始化武器（重写父类方法）
func initialize(template_data: Dictionary, inst_data: Dictionary, player: CharacterBody2D) -> void:
	super.initialize(template_data, inst_data, player)
	
	# 加载召唤单位数据
	var summon_unit_id: String = weapon_data.get("召唤单位ID（SummonUnitID）", "")
	if not summon_unit_id.is_empty():
		summon_unit_data = GameData.get_summon_unit(summon_unit_id)
		max_active = int(summon_unit_data.get("最大同时存在（MaxActive）", 4))
	
	# 读取召唤数量
	summon_count = int(weapon_data.get("召唤数量（SummonCount）", 1))


##############################################################################
# 攻击逻辑（召唤）
##############################################################################

## 攻击计时器超时回调（重写父类方法）
func _on_attack_timer_timeout() -> void:
	perform_summon()


## 执行召唤
func perform_summon() -> void:
	# 清理已死亡的召唤物
	_cleanup_dead_summons()
	
	# 检查是否达到数量上限
	if active_summons.size() >= max_active:
		# 移除最老的召唤物
		if active_summons.size() > 0:
			var oldest: Node2D = active_summons[0]
			oldest.queue_free()
			active_summons.remove_at(0)
	
	# 召唤新单位
	for i: int in range(summon_count):
		if active_summons.size() >= max_active:
			break
		
		_spawn_summon_unit()
	
	# 发出攻击信号
	weapon_attacked.emit()


##############################################################################
# 召唤单位生成
##############################################################################

## 生成召唤单位
func _spawn_summon_unit() -> void:
	if not SUMMON_UNIT_SCENE:
		push_error("[SummonWeapon] 召唤单位场景未加载")
		return
	
	var summon: Node2D = SUMMON_UNIT_SCENE.instantiate()
	
	# 设置生成位置（玩家附近随机位置）
	var spawn_offset: Vector2 = Vector2(randf_range(-100, 100), randf_range(-100, 100))
	summon.global_position = owner_player.global_position + spawn_offset
	
	# 添加到场景树
	get_tree().current_scene.add_child(summon)
	
	# 初始化召唤单位
	if summon.has_method("initialize"):
		var summon_stats: Dictionary = _calculate_summon_stats()
		summon.initialize(summon_unit_data, summon_stats, owner_player)
	
	# 连接销毁信号
	if summon.has_signal("summon_destroyed"):
		summon.summon_destroyed.connect(_on_summon_destroyed.bind(summon))
	
	# 记录
	active_summons.append(summon)


##############################################################################
# 召唤物属性计算
##############################################################################

## 计算召唤物属性
## 返回：
##   召唤物的战斗属性字典
func _calculate_summon_stats() -> Dictionary:
	var stats: Dictionary = {}
	
	# 基础伤害：武器基础伤害 + 玩家召唤伤害
	var base_dmg: float = weapon_data.get("基础伤害（BaseDamage）", 100.0)
	var summon_bonus: float = owner_player.get_final_stat("SummonDamage")
	stats["damage"] = base_dmg + summon_bonus
	
	# 全伤害加成（总是继承）
	var all_dmg_mult: float = 1.0 + owner_player.get_final_stat("AllDamage") / 100.0
	stats["damage"] *= all_dmg_mult
	
	# 会心（检查是否继承）
	var crit_inherit: float = summon_unit_data.get("会心继承系数（CritInherit）", 0.0)
	if crit_inherit > 0:
		# 检查是否有商店卡解锁继承
		if owner_player.has_shop_bonus("summon_crit_inherit"):
			var inherit_rate: float = owner_player.get_shop_bonus_value("summon_crit_inherit") / 100.0
			stats["crit_rate"] = owner_player.get_final_stat("CritRate") * crit_inherit * inherit_rate
			stats["crit_dmg"] = owner_player.get_final_stat("CritDamage") * crit_inherit * inherit_rate
		else:
			# 未解锁，直接继承
			stats["crit_rate"] = owner_player.get_final_stat("CritRate") * crit_inherit
			stats["crit_dmg"] = owner_player.get_final_stat("CritDamage") * crit_inherit
	else:
		stats["crit_rate"] = 0.0
		stats["crit_dmg"] = 0.0
	
	# 冷却（检查是否继承）
	var cdr_inherit: float = summon_unit_data.get("冷却继承系数（CDRInherit）", 0.0)
	if cdr_inherit > 0:
		if owner_player.has_shop_bonus("summon_cdr_inherit"):
			var inherit_rate: float = owner_player.get_shop_bonus_value("summon_cdr_inherit") / 100.0
			stats["cdr"] = owner_player.get_final_stat("Cooldown") * cdr_inherit * inherit_rate
		else:
			stats["cdr"] = owner_player.get_final_stat("Cooldown") * cdr_inherit
	else:
		stats["cdr"] = 0.0
	
	return stats


##############################################################################
# 召唤物管理
##############################################################################

## 清理已死亡的召唤物
func _cleanup_dead_summons() -> void:
	var i: int = 0
	while i < active_summons.size():
		var summon: Node2D = active_summons[i]
		if not is_instance_valid(summon) or summon.is_queued_for_deletion():
			active_summons.remove_at(i)
		else:
			i += 1


## 召唤物被销毁时的回调
func _on_summon_destroyed(summon: Node2D) -> void:
	var index: int = active_summons.find(summon)
	if index >= 0:
		active_summons.remove_at(index)


##############################################################################
# 物理更新
##############################################################################

func _physics_process(_delta: float) -> void:
	# 跟随玩家位置
	if owner_player:
		global_position = owner_player.global_position
