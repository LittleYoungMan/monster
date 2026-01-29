##############################################################################
# EnemyProjectile - 敌人投射物
#
# 设计目的：
# - 承载敌人远程攻击的飞行与碰撞
# - 支持分裂/溅射（由Enemy传入参数）
#
# 数据来源：
# - Enemy._create_single_projectile -> initialize(data)
#   data字段：damage/speed/direction/max_distance/splash/splash_radius/splash_count/sprite_id
#
# 调用链：
# - Enemy._perform_ranged_attack -> _create_single_projectile -> EnemyProjectile.initialize
# - 命中玩家 -> _hit_player -> player.take_damage
#
# 已实现：基础飞行、碰撞伤害、分裂
# 未实现：溅射视觉/范围伤害（_create_splash_effect）
##############################################################################
extends Area2D

##############################################################################
# 投射物数据
##############################################################################

## 投射物参数（由Enemy传入）
var projectile_data: Dictionary = {
	"damage": 10.0,          # 对玩家伤害
	"speed": 300.0,          # 飞行速度
	"direction": Vector2.RIGHT, # 飞行方向
	"max_distance": 1000.0,  # 最大飞行距离
	"splash": false,         # 是否溅射
	"splash_radius": 0.0,    # 溅射半径
	"sprite_id": ""         # 贴图ID（可为空）
}

## 分裂数量（若>0，命中时生成分裂弹）
var splash_count: int = 0

## 已飞行距离（用于超过max_distance后销毁）
var traveled_distance: float = 0.0

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

##############################################################################
# 生命周期
##############################################################################

func _ready() -> void:
	## 设置碰撞层：敌方投射物命中玩家
	collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY_PROJECTILE)
	collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER)

	## 连接碰撞回调
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	_load_sprite()

	## 确保存在碰撞形状
	if not collision_shape.shape:
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = 8.0
		collision_shape.shape = shape

##############################################################################
# 初始化
##############################################################################

## 初始化投射物
## 参数：data - 包含伤害/速度/方向等字段
func initialize(data: Dictionary) -> void:
	projectile_data = data
	splash_count = data.get("splash_count", 0)
	if not is_node_ready():
		await ready
	_load_sprite()

##############################################################################
# 飞行更新
##############################################################################

func _physics_process(delta: float) -> void:
	var movement: Vector2 = projectile_data["direction"] * projectile_data["speed"] * delta
	global_position += movement
	traveled_distance += movement.length()

	if traveled_distance > projectile_data["max_distance"]:
		queue_free()

##############################################################################
# 贴图加载
##############################################################################

func _load_sprite() -> void:
	var sprite_id: String = projectile_data.get("sprite_id", "")
	if sprite_id.is_empty():
		_generate_placeholder_sprite()
		return

	var sprite_path: String = "res://assets/PIC/enemy_projectiles/256/" + sprite_id + ".png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		sprite.scale = Vector2(0.125, 0.125)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_generate_placeholder_sprite()

func _generate_placeholder_sprite() -> void:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.3, 0.0, 1.0))
	sprite.texture = ImageTexture.create_from_image(img)

##############################################################################
# 碰撞处理
##############################################################################

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_hurtbox"):
		_hit_player(area.get_parent())

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_hit_player(body)

## 命中玩家
func _hit_player(player: Node) -> void:
	## 溅射/分裂逻辑
	if projectile_data.get("splash", false):
		var split_count: int = projectile_data.get("splash_count", 0)
		if split_count > 0:
			_create_split_projectiles(split_count)
		else:
			_create_splash_effect()

	## 造成伤害
	if player.has_method("take_damage"):
		player.take_damage(projectile_data["damage"])

	queue_free()

##############################################################################
# 分裂与溅射
##############################################################################

## 创建分裂弹（放射状）
func _create_split_projectiles(count: int) -> void:
	var projectile_scene: PackedScene = load("res://scenes/enemy/enemy_projectile.tscn")
	if not projectile_scene:
		return

	for i in range(count):
		var angle: float = (float(i) / float(count)) * TAU
		var direction: Vector2 = Vector2(cos(angle), sin(angle))

		var split_projectile: Area2D = projectile_scene.instantiate()
		var split_data: Dictionary = {
			"damage": projectile_data["damage"] * 0.5,
			"speed": projectile_data["speed"] * 0.7,
			"direction": direction,
			"max_distance": 200.0,
			"splash": false,
			"splash_radius": 0.0,
			"splash_count": 0,
			"sprite_id": projectile_data.get("sprite_id", "")
		}
		split_projectile.initialize(split_data)
		split_projectile.global_position = global_position
		get_parent().add_child(split_projectile)

	print("[EnemyProjectile] 分裂生成: ", count, "个")

## 溅射效果入口（未实现）
func _create_splash_effect() -> void:
	# TODO: 溅射视觉/范围伤害
	var splash_radius: float = projectile_data.get("splash_radius", 50.0)
	pass
