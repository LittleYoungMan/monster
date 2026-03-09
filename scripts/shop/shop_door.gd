##############################################################################
# ShopDoor - 商店门脚本
#
# 设计目的：
# - 作为商店的物理入口（Area2D碰撞体）
# - 玩家进入后触发商店UI显示
# - 有视觉提示（精灵图+粒子效果）
# - 一段时间后自动消失
#
# 调用链：
# - GameManager.shop_door_triggered → Main场景实例化ShopDoor
# - Player进入Area2D → _on_body_entered → 打开ShopUI
# - 玩家离开或购买后 → queue_free()
#
# 生命周期：
# - 生成后存在30秒（可配置）
# - 玩家进入后立即消失
# - 超时后自动消失
##############################################################################
extends Area2D

##############################################################################
# 配置参数
##############################################################################

## 门存在时间（秒）
## 单位：秒
## 作用：超时后自动消失
## 调整范围：10-60秒
## 当前值：30秒
@export var lifetime: float = 30.0

## 提示文本显示
## 作用：告诉玩家这是商店门
@export var hint_text: String = "按 E 进入商店"

## 是否自动进入（无需按键）
@export var auto_enter: bool = false

##############################################################################
# 节点引用
##############################################################################

## 门的精灵图（可以是光柱、传送门等）
@onready var sprite: Sprite2D = $Sprite2D

## 碰撞形状
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

## 提示标签
@onready var hint_label: Label = $HintLabel

## 粒子特效（可选）
@onready var particles: GPUParticles2D = $Particles

## 生命周期计时器
var lifetime_timer: float = 0.0

## 是否已触发（防止重复进入）
var triggered: bool = false

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	## 设置碰撞层
	collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.SHOP_DOOR)
	collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER)
	
	## 连接信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	## 初始化计时器
	lifetime_timer = lifetime
	
	## 加载精灵图
	_load_sprite()
	
	## 显示提示文本
	if hint_label:
		hint_label.text = hint_text
		hint_label.visible = false  # 初始隐藏，玩家靠近时显示
	
	print("[ShopDoor] 商店门生成，位置: ", global_position, " 存在时间: ", lifetime, "秒")

##############################################################################
# 物理更新
##############################################################################

func _physics_process(delta: float) -> void:
	## 倒计时
	lifetime_timer -= delta
	
	## 超时自动消失
	if lifetime_timer <= 0:
		_despawn()

##############################################################################
# 碰撞处理
##############################################################################

## 玩家进入
func _on_body_entered(body: Node2D) -> void:
	if triggered:
		return
	
	if not body.is_in_group("player"):
		return
	
	## 显示提示
	if hint_label:
		hint_label.visible = true
	
	## 自动进入商店
	if auto_enter:
		_enter_shop()

## 玩家离开
func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	
	## 隐藏提示
	if hint_label:
		hint_label.visible = false

##############################################################################
# 输入处理（非自动模式）
##############################################################################

func _unhandled_input(event: InputEvent) -> void:
	if triggered or auto_enter:
		return
	
	## 检查是否有玩家在范围内
	var bodies: Array[Node2D] = get_overlapping_bodies()
	var has_player: bool = false
	for body: Node2D in bodies:
		if body.is_in_group("player"):
			has_player = true
			break
	
	if not has_player:
		return
	
	## 按E进入商店
	if _is_interact_pressed(event):
		_enter_shop()

##############################################################################
# 核心逻辑
##############################################################################

## 进入商店
func _enter_shop() -> void:
	if triggered:
		return

	triggered = true

	## 获取ShopUI并显示
	var shop_ui: Control = _find_shop_ui()
	if shop_ui:
		shop_ui.show_shop()
		print("[ShopDoor] 打开商店UI, visible=", shop_ui.visible)
	else:
		push_error("[ShopDoor] 找不到ShopUI")

	## 播放进入音效（可选）
	_play_enter_sound()

	## 门消失
	_despawn()

## 门消失
func _despawn() -> void:
	print("[ShopDoor] 商店门消失")
	queue_free()

##############################################################################
# 辅助函数
##############################################################################

## 查找ShopUI节点
func _find_shop_ui() -> Control:
	## 方案1：通过场景树查找
	var ui_layer: CanvasLayer = get_tree().root.get_node_or_null("Main/UI")
	if ui_layer:
		var shop_ui: Control = ui_layer.get_node_or_null("ShopUI")
		if shop_ui:
			return shop_ui
	
	## 方案2：通过组查找
	var shop_uis: Array[Node] = get_tree().get_nodes_in_group("shop_ui")
	if shop_uis.size() > 0:
		return shop_uis[0]
	
	## 方案3：通过节点名查找
	return get_tree().root.find_child("ShopUI", true, false)

## 加载精灵图
func _load_sprite() -> void:
	if not sprite:
		return
	
	## 尝试加载商店门图片
	var sprite_path: String = "res://assets/PIC/map/256/shop_door.png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		sprite.scale = Vector2(0.5, 0.5)  # 256→128px
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		print("[ShopDoor] 图片加载: ", sprite_path)
	else:
		## 生成占位图（光柱效果）
		_generate_placeholder_sprite()

## 生成占位图
func _generate_placeholder_sprite() -> void:
	if not sprite:
		return
	
	var img: Image = Image.create(64, 128, false, Image.FORMAT_RGBA8)
	
	## 画一个渐变光柱
	for y in range(128):
		var alpha: float = 1.0 - (float(y) / 128.0) * 0.7  # 顶部亮，底部暗
		for x in range(64):
			var dist_from_center: float = abs(float(x) - 32.0) / 32.0
			var brightness: float = (1.0 - dist_from_center) * alpha
			img.set_pixel(x, y, Color(1.0, 0.8, 0.0, brightness))
	
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.scale = Vector2(1.0, 1.0)
	print("[ShopDoor] 使用占位图（光柱）")

## 播放进入音效
func _play_enter_sound() -> void:
	# TODO: 添加音效播放
	pass

## 统一交互输入检测
## 优先使用InputMap中的interact，其次回退到常见键位
func _is_interact_pressed(event: InputEvent) -> bool:
	if event.is_action_pressed("interact"):
		return true
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_E:
				return true
			if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
				return true
	return false


##############################################################################
# 场景搭建指南
##############################################################################

#
# ShopDoor (Area2D)
#     [script: shop_door.gd]
#     [groups: "shop_door"]
#     ├─ Sprite2D
#     │   [name: "Sprite2D"]
#     │   [texture: 空（由脚本加载）]
#     │   [centered: true]
#     ├─ CollisionShape2D
#     │   [shape: CircleShape2D]
#     │   [radius: 50.0]
#     ├─ HintLabel (Label)
#     │   [text: "按 E 进入商店"]
#     │   [horizontal_alignment: Center]
#     │   [position: Vector2(0, -80)]
#     │   [visible: false]
#     └─ Particles (GPUParticles2D) [可选]
#         [amount: 32]
#         [lifetime: 1.0]
#         [emitting: true]
#
# === 创建步骤 ===
#
# 1. 场景 → 新建场景 → 其他节点 → Area2D → 命名为ShopDoor
# 2. 右键ShopDoor → 附加脚本 → 选择shop_door.gd
# 3. 右键ShopDoor → 添加子节点 → Sprite2D
# 4. 右键ShopDoor → 添加子节点 → CollisionShape2D
#    - Inspector → Shape → 新建CircleShape2D
#    - Radius = 50
# 5. 右键ShopDoor → 添加子节点 → Label → 命名为HintLabel
#    - Text = "按 E 进入商店"
#    - Horizontal Alignment = Center
#    - Position = (0, -80)
#    - Visible = false
# 6. 保存场景为 res://scenes/ui/shop_door.tscn
#
# === 在Main场景中使用 ===
#
# 在main.gd中：
#
# var shop_door_scene: PackedScene = load("res://scenes/ui/shop_door.tscn")
#
# func _on_shop_door_triggered():
#     var shop_door: Area2D = shop_door_scene.instantiate()
#     
#     # 计算生成位置
#     var player_pos: Vector2 = player.global_position
#     var distance: float = 100.0
#     if GameManager.current_time > 180.0:
#         distance = randf_range(200.0, 500.0)
#     
#     var angle: float = randf() * TAU
#     var spawn_pos: Vector2 = player_pos + Vector2(cos(angle), sin(angle)) * distance
#     
#     shop_door.global_position = spawn_pos
#     add_child(shop_door)
