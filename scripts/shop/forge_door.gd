##############################################################################
# ForgeDoor - 工坊门脚本
#
# 设计目的：
# - Boss击杀后生成的工坊入口
# - 30秒倒计时后自动消失
# - 玩家进入后打开工坊UI
#
# 与ShopDoor的区别：
# - 生成时机：Boss击杀后
# - 存在时间：30秒（更短）
# - 生成位置：视野内200-400px
# - 视觉效果：更华丽（Boss奖励感）
#
# 调用链：
# - GameManager.boss_killed → GameManager.forge_available → Main生成ForgeDoor
# - Player进入 → 打开ForgeUI
##############################################################################
extends Area2D

##############################################################################
# 配置参数
##############################################################################

## 门存在时间（秒）
## 单位：秒
## 作用：Boss击杀后的工坊开放时间
## 当前值：30秒（不可改，设计固定）
@export var lifetime: float = 30.0

## 提示文本
@export var hint_text: String = "按 E 进入工坊"

## 是否自动进入
@export var auto_enter: bool = true

## Boss分钟标记（用于ForgeManager限制）
var boss_minute: int = 0

##############################################################################
# 节点引用
##############################################################################

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hint_label: Label = $HintLabel
@onready var countdown_label: Label = $CountdownLabel  # 显示剩余时间
@onready var particles: GPUParticles2D = $Particles

## 生命周期计时器
var lifetime_timer: float = 0.0

## 是否已触发
var triggered: bool = false

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	## 设置碰撞层
	collision_layer = CollisionLayers.get_layer_mask(CollisionLayers.FORGE_DOOR)
	collision_mask = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER)
	
	## 连接信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	## 初始化计时器
	lifetime_timer = lifetime
	
	## 加载精灵图
	_load_sprite()
	
	## 显示提示
	if hint_label:
		hint_label.text = hint_text
		hint_label.visible = false
	
	## 显示倒计时
	if countdown_label:
		countdown_label.visible = true
		_update_countdown()
	
	print("[ForgeDoor] 工坊门生成，位置: ", global_position, " 存在时间: ", lifetime, "秒")

##############################################################################
# 初始化函数（由Main场景调用）
##############################################################################

## 设置Boss分钟标记
## 参数：minute - Boss出现的分钟数（5/10/15/20）
## 作用：传递给ForgeManager，用于升阶次数限制
func initialize(minute: int) -> void:
	boss_minute = minute
	print("[ForgeDoor] Boss分钟标记: ", boss_minute)

##############################################################################
# 物理更新
##############################################################################

func _physics_process(delta: float) -> void:
	## 倒计时
	lifetime_timer -= delta
	
	## 更新倒计时显示
	_update_countdown()
	
	## 超时消失
	if lifetime_timer <= 0:
		_despawn()
	
	## 最后5秒闪烁警告
	if lifetime_timer <= 5.0:
		_flash_warning(delta)

##############################################################################
# 碰撞处理
##############################################################################

func _on_body_entered(body: Node2D) -> void:
	if triggered:
		return
	
	if not body.is_in_group("player"):
		return
	
	## 显示提示
	if hint_label:
		hint_label.visible = true
	
	## 自动进入
	if auto_enter:
		_enter_forge()

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	
	if hint_label:
		hint_label.visible = false

##############################################################################
# 输入处理
##############################################################################

func _unhandled_input(event: InputEvent) -> void:
	if triggered or auto_enter:
		return
	
	var bodies: Array[Node2D] = get_overlapping_bodies()
	var has_player: bool = false
	for body: Node2D in bodies:
		if body.is_in_group("player"):
			has_player = true
			break
	
	if not has_player:
		return
	
	if event.is_action_pressed("ui_accept"):
		_enter_forge()

##############################################################################
# 核心逻辑
##############################################################################

## 进入工坊
func _enter_forge() -> void:
	if triggered:
		return
	
	triggered = true
	
	## 通知ForgeManager当前Boss分钟（重置升阶次数）
	if ForgeManager:
		ForgeManager.set_current_boss_minute(boss_minute)
	
	## 获取ForgeUI并显示
	var forge_ui: Control = _find_forge_ui()
	if forge_ui and forge_ui.has_method("show_forge"):
		forge_ui.show_forge()
		print("[ForgeDoor] 打开工坊UI")
	else:
		push_error("[ForgeDoor] 找不到ForgeUI或show_forge方法")
	
	## 播放音效
	_play_enter_sound()
	
	## 门消失（进入后立即消失）
	_despawn()

## 门消失
func _despawn() -> void:
	print("[ForgeDoor] 工坊门消失")
	queue_free()

##############################################################################
# UI更新
##############################################################################

## 更新倒计时显示
func _update_countdown() -> void:
	if not countdown_label:
		return
	
	var seconds: int = int(ceil(lifetime_timer))
	countdown_label.text = str(seconds) + "s"
	
	## 根据剩余时间改变颜色
	if lifetime_timer > 15.0:
		countdown_label.modulate = Color.WHITE
	elif lifetime_timer > 5.0:
		countdown_label.modulate = Color.YELLOW
	else:
		countdown_label.modulate = Color.RED

## 最后5秒闪烁警告
var flash_timer: float = 0.0
func _flash_warning(delta: float) -> void:
	flash_timer += delta
	if flash_timer > 0.3:
		flash_timer = 0.0
		sprite.visible = !sprite.visible

##############################################################################
# 辅助函数
##############################################################################

## 查找ForgeUI节点
func _find_forge_ui() -> Control:
	## 通过场景树查找
	var ui_layer: CanvasLayer = get_tree().root.get_node_or_null("Main/UI")
	if ui_layer:
		var forge_ui: Control = ui_layer.get_node_or_null("ForgeUI")
		if forge_ui:
			return forge_ui
	
	## 通过组查找
	var forge_uis: Array[Node] = get_tree().get_nodes_in_group("forge_ui")
	if forge_uis.size() > 0:
		return forge_uis[0]
	
	## 通过节点名查找
	return get_tree().root.find_child("ForgeUI", true, false)

## 加载精灵图
func _load_sprite() -> void:
	if not sprite:
		return
	
	## 尝试加载工坊门图片
	var sprite_path: String = "res://assets/PIC/forge/256/forge_door.png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		sprite.scale = Vector2(0.5, 0.5)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		print("[ForgeDoor] 图片加载: ", sprite_path)
	else:
		## 生成占位图（紫色光柱）
		_generate_placeholder_sprite()

## 生成占位图（紫色，区别于商店的金色）
func _generate_placeholder_sprite() -> void:
	if not sprite:
		return
	
	var img: Image = Image.create(64, 128, false, Image.FORMAT_RGBA8)
	
	## 紫色渐变光柱（工坊感）
	for y in range(128):
		var alpha: float = 1.0 - (float(y) / 128.0) * 0.7
		for x in range(64):
			var dist_from_center: float = abs(float(x) - 32.0) / 32.0
			var brightness: float = (1.0 - dist_from_center) * alpha
			## 紫色 (0.8, 0.3, 1.0)
			img.set_pixel(x, y, Color(0.8, 0.3, 1.0, brightness))
	
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.scale = Vector2(1.0, 1.0)
	print("[ForgeDoor] 使用占位图（紫色光柱）")

## 播放进入音效
func _play_enter_sound() -> void:
	# TODO: 工坊进入音效
	pass


##############################################################################
# 场景搭建指南
##############################################################################

# === forge_door.tscn 场景结构 ===
#
# ForgeDoor (Area2D)
#     [script: forge_door.gd]
#     [groups: "forge_door"]
#     ├─ Sprite2D
#     │   [texture: 空]
#     │   [centered: true]
#     ├─ CollisionShape2D
#     │   [shape: CircleShape2D]
#     │   [radius: 60.0]  # 比商店门稍大
#     ├─ HintLabel (Label)
#     │   [text: "按 E 进入工坊"]
#     │   [horizontal_alignment: Center]
#     │   [position: Vector2(0, -100)]
#     │   [visible: false]
#     ├─ CountdownLabel (Label)
#     │   [text: "30s"]
#     │   [horizontal_alignment: Center]
#     │   [position: Vector2(0, 80)]
#     │   [theme_override_font_sizes/font_size: 24]
#     └─ Particles (GPUParticles2D) [可选]
#         [amount: 64]  # 比商店门更多粒子
#         [lifetime: 1.5]
#
# === 创建步骤 ===
#
# 1. 场景 → 新建场景 → 其他节点 → Area2D → 命名为ForgeDoor
# 2. 附加脚本 forge_door.gd
# 3. 添加Sprite2D子节点
# 4. 添加CollisionShape2D子节点（CircleShape2D, radius=60）
# 5. 添加HintLabel子节点
#    - Text = "按 E 进入工坊"
#    - Position = (0, -100)
# 6. 添加CountdownLabel子节点
#    - Text = "30s"
#    - Position = (0, 80)
#    - Font Size = 24
# 7. 保存为 res://scenes/ui/forge_door.tscn
#
# === 在Main场景中使用 ===
#
# var forge_door_scene: PackedScene = load("res://scenes/ui/forge_door.tscn")
#
# func _on_forge_available():
#     var forge_door: Area2D = forge_door_scene.instantiate()
#     
#     # Boss击杀后在视野内生成
#     var player_pos: Vector2 = player.global_position
#     var distance: float = randf_range(200.0, 400.0)
#     var angle: float = randf() * TAU
#     var spawn_pos: Vector2 = player_pos + Vector2(cos(angle), sin(angle)) * distance
#     
#     forge_door.global_position = spawn_pos
#     forge_door.initialize(GameManager.current_boss_minute)
#     add_child(forge_door)
