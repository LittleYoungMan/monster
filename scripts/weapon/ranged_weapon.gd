##############################################################################
# RangedWeapon - 远程武器
#
# 功能说明：
# 1. 继承WeaponBase，实现远程武器的攻击逻辑
# 2. 发射投射物（直线弹、爆炸弹、回旋体等）
# 3. 支持穿透、爆炸、散射等机制
# 4. 管理投射物的生命周期
#
# 场景结构：
#   RangedWeapon (Node2D)
#     ├─ ShootPoint (Marker2D) - 发射点
#     └─ AttackTimer (Timer) - 攻击冷却
##############################################################################
extends WeaponBase
class_name RangedWeapon

##############################################################################
# 投射物场景预加载
##############################################################################

## 投射物场景
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/weapons/projectile.tscn")

##############################################################################
# 节点引用
##############################################################################

## 发射点标记
@onready var shoot_point: Marker2D = $ShootPoint

##############################################################################
# 投射物配置
##############################################################################

## 投射物数据（从GameData加载）
var projectile_data: Dictionary = {}

##############################################################################
# 初始化
##############################################################################

## 初始化武器（重写父类方法）
func initialize(template_data: Dictionary, inst_data: Dictionary, player: CharacterBody2D) -> void:
	super.initialize(template_data, inst_data, player)
	
	# 加载投射物数据
	var projectile_id: String = weapon_data.get("投射物ID（ProjectileID）", "")
	if not projectile_id.is_empty():
		projectile_data = GameData.get_projectile(projectile_id)
	
	# 设置发射点位置
	if shoot_point:
		var base_range: float = weapon_data.get("基础射程（BaseRange）", 100.0)
		shoot_point.position = Vector2(base_range * 0.1, 0)  # 在武器前方10%的位置


##############################################################################
# 攻击逻辑
##############################################################################

## 攻击计时器超时回调（重写父类方法）
func _on_attack_timer_timeout() -> void:
	perform_attack()


## 执行攻击
## 作用：发射投射物
func perform_attack() -> void:
	if not shoot_point:
		return
	
	# 朝向鼠标
	_rotate_to_target()
	
	var attack_type: String = attack_method_config.get("type", "")
	
	match attack_type:
		"ranged_straight", "ranged_burst", "ranged_knife":
			# 直线发射
			_shoot_straight()
		
		"ranged_spread":
			# 散射
			_shoot_spread()
		
		"ranged_boomerang", "ranged_chain":
			# 回旋体/链锤
			_shoot_boomerang()
		
		"ranged_explosive", "ranged_arc":
			# 爆炸弹/抛射
			_shoot_explosive()
		
		"ranged_pull":
			# 牵引矛
			_shoot_pull()
		
		_:
			# 默认直线发射
			_shoot_straight()
	
	# 发出攻击信号
	weapon_attacked.emit()


##############################################################################
# 发射方式
##############################################################################

## 直线发射
func _shoot_straight() -> void:
	_spawn_projectile(Vector2.RIGHT.rotated(rotation))


## 散射发射
func _shoot_spread() -> void:
	# 发射3-5个投射物，扇形散开
	var projectile_count: int = 5
	var spread_angle: float = deg_to_rad(30)  # 总散射角度
	
	for i: int in range(projectile_count):
		var angle_offset: float = -spread_angle / 2 + (spread_angle / (projectile_count - 1)) * i
		var direction: Vector2 = Vector2.RIGHT.rotated(rotation + angle_offset)
		_spawn_projectile(direction)


## 回旋发射
func _shoot_boomerang() -> void:
	var projectile: Node2D = _spawn_projectile(Vector2.RIGHT.rotated(rotation))
	
	# 设置回旋标记
	if projectile and projectile.has_method("set_boomerang_mode"):
		projectile.set_boomerang_mode(true)


## 爆炸弹发射
func _shoot_explosive() -> void:
	var projectile: Node2D = _spawn_projectile(Vector2.RIGHT.rotated(rotation))
	
	# 设置抛物线轨迹（如果是抛射）
	if attack_method_config.get("type", "") == "ranged_arc":
		if projectile and projectile.has_method("set_arc_trajectory"):
			projectile.set_arc_trajectory(true)


## 牵引矛发射
func _shoot_pull() -> void:
	var projectile: Node2D = _spawn_projectile(Vector2.RIGHT.rotated(rotation))
	
	# 设置牵引效果
	if projectile and projectile.has_method("set_pull_effect"):
		projectile.set_pull_effect(true)


##############################################################################
# 投射物生成
##############################################################################

## 生成投射物
## 参数：
##   direction - 发射方向（已归一化）
## 返回：
##   投射物实例
func _spawn_projectile(direction: Vector2) -> Node2D:
	if not PROJECTILE_SCENE:
		push_error("[RangedWeapon] 投射物场景未加载")
		return null
	
	var projectile: Node2D = PROJECTILE_SCENE.instantiate()
	
	# 设置位置和方向
	projectile.global_position = shoot_point.global_position
	projectile.rotation = direction.angle()
	
	# 添加到场景树
	get_tree().current_scene.add_child(projectile)
	
	# 初始化投射物
	if projectile.has_method("initialize"):
		var damage: float = calculate_damage()
		var speed: float = _calculate_projectile_speed()
		var lifetime: float = _calculate_projectile_lifetime()
		var pierce_count: int = _get_pierce_count()
		
		projectile.initialize(
			damage,
			speed,
			direction,
			lifetime,
			pierce_count,
			projectile_data,
			owner_player
		)
	
	return projectile


##############################################################################
# 投射物参数计算
##############################################################################

## 计算投射物速度
## 返回：
##   速度（像素/秒）
func _calculate_projectile_speed() -> float:
	var base_speed: float = projectile_data.get("速度_px每秒（SpeedPxps）", 1000.0)
	
	# 应用攻击方式的速度修正
	var speed_mult: float = attack_method_config.get("params", {}).get("speed_mult", 1.0)
	
	return base_speed * speed_mult


## 计算投射物存活时间
## 返回：
##   存活时间（秒）
func _calculate_projectile_lifetime() -> float:
	# 检查是否使用武器射程
	var use_weapon_range: bool = projectile_data.get("是否使用武器射程（UseWeaponRange）", false)
	
	if use_weapon_range:
		# 根据武器射程计算存活时间
		var weapon_range: float = weapon_data.get("基础射程（BaseRange）", 800.0)
		var speed: float = _calculate_projectile_speed()
		
		if speed > 0:
			return weapon_range / speed
	
	# 使用投射物自身的存活时间
	return projectile_data.get("存活时间_s（LifetimeS）", 2.0)


## 获取穿透次数
## 返回：
##   穿透次数（0表示不穿透）
func _get_pierce_count() -> int:
	# 优先使用武器数据的穿透次数
	var weapon_pierce: int = int(weapon_data.get("穿透次数（PierceCount）", 0))
	if weapon_pierce > 0:
		return weapon_pierce
	
	# 使用攻击方式配置的穿透次数
	var config_pierce: int = attack_method_config.get("params", {}).get("pierce", 0)
	if config_pierce > 0:
		return config_pierce
	
	# 使用投射物数据的命中次数上限
	var hit_limit: int = int(projectile_data.get("命中次数上限（HitLimit）", 0))
	return hit_limit


##############################################################################
# 旋转与朝向
##############################################################################

## 旋转武器朝向目标
func _rotate_to_target() -> void:
	if not owner_player:
		return
	
	# 朝向鼠标
	var mouse_pos: Vector2 = get_global_mouse_position()
	var direction: Vector2 = (mouse_pos - global_position).normalized()
	
	rotation = direction.angle()


##############################################################################
# 物理更新
##############################################################################

func _physics_process(_delta: float) -> void:
	# 跟随玩家位置
	if owner_player:
		global_position = owner_player.global_position
