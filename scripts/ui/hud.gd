##############################################################################
# HUD - 游戏内HUD
#
# 设计目的：
# - 以“只读展示”为核心：HUD只负责显示，不直接改玩家数值
# - 数据来源统一由玩家节点与GameManager信号提供，避免UI自己计算
#
# 主要职责：
# 1) 显示时间/金币/矿石（顶部）
# 2) 显示生命/经验/等级（底部）
# 3) 监听GameManager信号，实时刷新金币与矿石文本
#
# 依赖与调用链：
# - 依赖玩家节点在group "player" 中（由关卡或Player脚本注册）
# - 依赖GameManager发出 gold_changed / ore_changed 信号
# - _process 每帧读取玩家属性来刷新血条与等级
#
# 引擎回调：
# - _ready(): 节点进入场景树后执行，一次性做节点绑定与信号连接
# - _process(delta): 每帧刷新（生命/等级）
#
# 注意：
# - exp_bar当前未写入，保留给后续经验条逻辑（不改动现有行为）
#
# 修复：2026-01-27 重新写回中文注释与文本
##############################################################################
extends CanvasLayer

##############################################################################
# 节点引用（UI显示组件）
##############################################################################

## 顶部时间显示标签（若场景内有计时器，可由外部更新）
@onready var time_label: Label = $TopBar/TimeLabel
@onready var top_bar: HBoxContainer = $TopBar

## 商店倒计时显示（临时添加在时间标签后面）

## 顶部金币显示标签，文本格式为“金币: 数量”
@onready var gold_label: Label = $TopBar/GoldLabel

## 顶部矿石显示标签，文本格式为“矿石: 数量”
@onready var ore_label: Label = $TopBar/OreLabel

## 底部生命条（max_value由玩家最终生命值决定）
@onready var health_bar: ProgressBar = $BottomBar/HealthBar

## 底部经验条（保留：逻辑未在此脚本刷新）
@onready var exp_bar: ProgressBar = $BottomBar/ExpBar

## 底部等级显示标签，文本格式为“Lv.X”
@onready var level_label: Label = $BottomBar/LevelLabel
@onready var bottom_bar: VBoxContainer = $BottomBar

##############################################################################
# 运行期数据
##############################################################################

## 玩家节点引用（通过group "player" 获取）
## 只读访问：用于刷新血量/等级显示
var player: CharacterBody2D = null
## 低血量脉冲计时
var low_hp_pulse_time: float = 0.0
var ui_time: float = 0.0
var top_plate: Panel = null
var bottom_plate: Panel = null
var gold_label_tween: Tween = null
var ore_label_tween: Tween = null
var gold_icon: TextureRect = null
var ore_icon: TextureRect = null
var danger_overlay: ColorRect = null
var last_player_hp: float = -1.0
var damage_flash_timer: float = 0.0
var low_hp_overlay_alpha: float = 0.0

const BOSS_MINUTE_MARKS: Array[int] = [5, 10, 15, 20]
const DAMAGE_FLASH_DURATION: float = 0.22
const DAMAGE_FLASH_MAX_ALPHA: float = 0.32
const LOW_HP_OVERLAY_MAX_ALPHA: float = 0.24

##############################################################################
# 生命周期回调
##############################################################################

func _ready() -> void:
	## 绑定玩家与信号
	## 等待一帧，确保玩家节点已加入场景树
	await get_tree().process_frame

	## 从group "player" 获取玩家（通常只有一个）
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	## 连接全局货币变更信号，避免HUD主动轮询
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.ore_changed.connect(_on_ore_changed)

	## 连接时间变化信号
	GameManager.time_changed.connect(_on_time_changed)

	## 初始化显示
	_ensure_danger_overlay()
	_ensure_backplates()
	_ensure_currency_icons()
	_apply_visual_theme()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_fit_to_viewport()
	_on_gold_changed(GameManager.gold)
	_on_ore_changed(GameManager.ore)
	_update_time_display()

func _process(delta: float) -> void:
	ui_time += delta
	if top_plate:
		top_plate.modulate.a = 0.90 + 0.08 * (0.5 + 0.5 * sin(ui_time * 1.15))
	if bottom_plate:
		bottom_plate.modulate.a = 0.88 + 0.10 * (0.5 + 0.5 * sin(ui_time * 0.95))
	if gold_icon:
		var gold_pulse: float = 0.5 + 0.5 * sin(ui_time * 2.4)
		gold_icon.scale = gold_icon.scale.lerp(Vector2.ONE * (1.0 + 0.05 * gold_pulse), clamp(delta * 10.0, 0.0, 1.0))
		gold_icon.rotation = lerpf(gold_icon.rotation, 0.03 * sin(ui_time * 1.9), clamp(delta * 8.0, 0.0, 1.0))
	if ore_icon:
		var ore_pulse: float = 0.5 + 0.5 * sin(ui_time * 2.1 + 1.1)
		ore_icon.scale = ore_icon.scale.lerp(Vector2.ONE * (1.0 + 0.05 * ore_pulse), clamp(delta * 10.0, 0.0, 1.0))
		ore_icon.rotation = lerpf(ore_icon.rotation, -0.03 * sin(ui_time * 1.7 + 0.4), clamp(delta * 8.0, 0.0, 1.0))
	## 刷新血量/等级与时间显示
	## 每帧刷新玩家生命与等级显示
	## 说明：不在HUD侧进行数值计算，直接读取玩家最新值
	if player:
		var max_hp: float = max(1.0, player.get_final_stat("Health"))
		health_bar.max_value = max_hp
		health_bar.value = player.current_hp
		level_label.text = "Lv." + str(player.current_level)
		var hp_ratio: float = player.current_hp / max_hp
		if last_player_hp < 0.0:
			last_player_hp = player.current_hp
		elif player.current_hp + 0.01 < last_player_hp:
			damage_flash_timer = DAMAGE_FLASH_DURATION
			last_player_hp = player.current_hp
		else:
			last_player_hp = player.current_hp
		_update_low_hp_pulse(delta, hp_ratio)
		_update_danger_overlay(delta, hp_ratio)
	else:
		last_player_hp = -1.0
		_update_danger_overlay(delta, 1.0)
	_update_exp_bar()

	## 每帧刷新时间显示
	_update_time_display()

##############################################################################
# 信号回调：货币变更
##############################################################################

func _on_gold_changed(amount: int) -> void:
	## 金币变更回调
	## 外部逻辑通知金币变更，此处仅更新文本
	gold_label.text = _format_number(amount)
	_pulse_label(gold_label, Color(1.0, 0.90, 0.46), true)

func _on_ore_changed(amount: int) -> void:
	## 矿石变更回调
	## 外部逻辑通知矿石变更，此处仅更新文本
	ore_label.text = _format_number(amount)
	_pulse_label(ore_label, Color(0.62, 0.92, 1.0), false)

##############################################################################
# 时间显示
##############################################################################

func _on_time_changed(seconds: float) -> void:
	## 时间变更回调
	_update_time_display()

func _update_time_display() -> void:
	## 刷新时间与商店倒计时显示
	## 从GameManager获取当前时间并格式化为 MM:SS
	var total_seconds: int = int(GameManager.current_time)
	var remaining_seconds: int = int(GameManager.GAME_DURATION - total_seconds)

	if remaining_seconds < 0:
		remaining_seconds = 0

	var minutes: int = remaining_seconds / 60
	var seconds: int = remaining_seconds % 60

	## 显示时间和商店倒计时
	var shop_countdown: int = int(GameManager.shop_timer)
	var boss_countdown: int = _get_next_boss_countdown_seconds(total_seconds)
	var boss_text: String = "--:--"
	if boss_countdown > 0:
		boss_text = "%02d:%02d" % [boss_countdown / 60, boss_countdown % 60]
	time_label.text = "%02d:%02d | 商店 %02ds | Boss %s" % [minutes, seconds, max(0, shop_countdown), boss_text]
	if boss_countdown > 0 and boss_countdown <= 25:
		var pulse: float = 0.5 + 0.5 * sin(ui_time * 8.0)
		time_label.add_theme_color_override("font_color", Color(1.0, 0.48 + 0.38 * pulse, 0.30 + 0.24 * pulse))
		time_label.scale = Vector2.ONE * (1.0 + 0.04 * pulse)
	else:
		time_label.add_theme_color_override("font_color", Color(0.90, 0.97, 1.0, 1.0))
		time_label.scale = Vector2.ONE

func _get_next_boss_countdown_seconds(elapsed_seconds: int) -> int:
	for minute_mark: int in BOSS_MINUTE_MARKS:
		var target: int = minute_mark * 60
		if elapsed_seconds < target:
			return target - elapsed_seconds
	return 0

func _update_low_hp_pulse(delta: float, hp_ratio: float) -> void:
	if hp_ratio <= 0.25:
		low_hp_pulse_time += delta * 8.0
		var t: float = 0.5 + 0.5 * sin(low_hp_pulse_time)
		var tone: float = lerp(0.55, 1.0, t)
		health_bar.modulate = Color(1.0, tone, tone, 1.0)
	else:
		low_hp_pulse_time = 0.0
		health_bar.modulate = Color.WHITE

func _update_danger_overlay(delta: float, hp_ratio: float) -> void:
	if not danger_overlay:
		return
	damage_flash_timer = max(0.0, damage_flash_timer - delta)
	var flash_alpha: float = 0.0
	if damage_flash_timer > 0.0:
		var flash_t: float = damage_flash_timer / DAMAGE_FLASH_DURATION
		flash_alpha = flash_t * flash_t * DAMAGE_FLASH_MAX_ALPHA

	var low_target: float = 0.0
	if hp_ratio < 0.42:
		var weight: float = clamp((0.42 - hp_ratio) / 0.42, 0.0, 1.0)
		low_target = LOW_HP_OVERLAY_MAX_ALPHA * (0.35 + 0.65 * weight)
	low_hp_overlay_alpha = lerpf(low_hp_overlay_alpha, low_target, clamp(delta * 5.6, 0.0, 1.0))

	var pulse: float = 1.0
	if hp_ratio < 0.42:
		pulse = 0.86 + 0.14 * (0.5 + 0.5 * sin(ui_time * 6.8))
	var final_alpha: float = clamp(low_hp_overlay_alpha * pulse + flash_alpha, 0.0, 0.45)
	danger_overlay.color = Color(0.62, 0.07, 0.06, final_alpha)

func _on_viewport_size_changed() -> void:
	_fit_to_viewport()

func _fit_to_viewport() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var margin_x: float = clamp(vp.x * 0.02, 12.0, 36.0)
	var top_h: float = clamp(vp.y * 0.06, 42.0, 76.0)
	var top_sep: int = int(clamp(vp.x * 0.013, 12.0, 28.0))
	top_bar.add_theme_constant_override("separation", top_sep)

	top_bar.offset_left = margin_x
	top_bar.offset_right = -margin_x
	top_bar.offset_top = margin_x * 0.6
	top_bar.offset_bottom = top_bar.offset_top + top_h
	time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_label.custom_minimum_size.x = clamp(vp.x * 0.26, 260.0, 560.0)
	gold_label.custom_minimum_size.x = clamp(vp.x * 0.09, 120.0, 200.0)
	ore_label.custom_minimum_size.x = clamp(vp.x * 0.09, 120.0, 200.0)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var icon_size: float = clamp(vp.x * 0.018, 24.0, 34.0)
	if gold_icon:
		gold_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	if ore_icon:
		ore_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	if top_plate:
		top_plate.offset_left = top_bar.offset_left - 10.0
		top_plate.offset_right = top_bar.offset_right + 10.0
		top_plate.offset_top = top_bar.offset_top - 6.0
		top_plate.offset_bottom = top_bar.offset_bottom + 8.0

	bottom_bar.offset_left = margin_x
	bottom_bar.offset_right = -margin_x
	bottom_bar.offset_top = -clamp(vp.y * 0.11, 78.0, 140.0)
	bottom_bar.offset_bottom = -margin_x * 0.6
	bottom_bar.add_theme_constant_override("separation", int(clamp(vp.y * 0.008, 4.0, 10.0)))
	if bottom_plate:
		bottom_plate.offset_left = bottom_bar.offset_left - 10.0
		bottom_plate.offset_right = bottom_bar.offset_right + 10.0
		bottom_plate.offset_top = bottom_bar.offset_top - 10.0
		bottom_plate.offset_bottom = bottom_bar.offset_bottom + 8.0

	var bar_w: float = clamp(vp.x * 0.36, 340.0, 760.0)
	health_bar.custom_minimum_size.x = bar_w
	exp_bar.custom_minimum_size.x = bar_w
	health_bar.custom_minimum_size.y = clamp(vp.y * 0.025, 16.0, 30.0)
	exp_bar.custom_minimum_size.y = clamp(vp.y * 0.017, 10.0, 22.0)

	var primary_font_size: int = int(clamp(vp.x / 80.0, 18.0, 28.0))
	var secondary_font_size: int = int(clamp(vp.x / 95.0, 16.0, 24.0))
	var level_font_size: int = int(clamp(vp.x / 102.0, 15.0, 23.0))
	time_label.add_theme_font_size_override("font_size", primary_font_size)
	gold_label.add_theme_font_size_override("font_size", secondary_font_size)
	ore_label.add_theme_font_size_override("font_size", secondary_font_size)
	level_label.add_theme_font_size_override("font_size", level_font_size)

func _update_exp_bar() -> void:
	var level: int = int(GameManager.player_level)
	var curve: Array[int] = GameManager.EXP_CURVE
	if level >= curve.size() - 1:
		exp_bar.max_value = 1.0
		exp_bar.value = 1.0
		return
	var current_need: int = curve[level]
	var next_need: int = curve[level + 1]
	var progress: float = GameManager.player_exp - float(current_need)
	var total: float = max(1.0, float(next_need - current_need))
	exp_bar.max_value = total
	exp_bar.value = clamp(progress, 0.0, total)

func _format_number(value: int) -> String:
	var sign: String = "-" if value < 0 else ""
	var text: String = str(abs(value))
	var chunks: Array[String] = []
	while text.length() > 3:
		chunks.push_front(text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	chunks.push_front(text)
	return sign + ",".join(chunks)

func _ensure_backplates() -> void:
	var base_index: int = 1 if danger_overlay else 0
	if not top_plate:
		top_plate = Panel.new()
		top_plate.name = "TopPlate"
		top_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(top_plate)
	move_child(top_plate, base_index)
	if not bottom_plate:
		bottom_plate = Panel.new()
		bottom_plate.name = "BottomPlate"
		bottom_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bottom_plate)
	move_child(bottom_plate, base_index + 1)

func _ensure_danger_overlay() -> void:
	if danger_overlay:
		return
	danger_overlay = ColorRect.new()
	danger_overlay.name = "DangerOverlay"
	danger_overlay.anchors_preset = Control.PRESET_FULL_RECT
	danger_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_overlay.color = Color(0.62, 0.07, 0.06, 0.0)
	add_child(danger_overlay)
	move_child(danger_overlay, 0)

func _ensure_currency_icons() -> void:
	if not top_bar:
		return
	if not gold_icon:
		gold_icon = TextureRect.new()
		gold_icon.name = "GoldIcon"
		gold_icon.texture = _load_first_texture([
			"res://assets/PIC/map/256/moneyAndExp.png"
		])
		gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gold_icon.custom_minimum_size = Vector2(28, 28)
		gold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(gold_icon)
	if not ore_icon:
		ore_icon = TextureRect.new()
		ore_icon.name = "OreIcon"
		ore_icon.texture = _load_first_texture([
			"res://assets/PIC/map/256/ore_1.png",
			"res://assets/PIC/map/256/ore_2.png"
		])
		ore_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ore_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ore_icon.custom_minimum_size = Vector2(28, 28)
		ore_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(ore_icon)
	var gold_label_index: int = top_bar.get_children().find(gold_label)
	var ore_label_index: int = top_bar.get_children().find(ore_label)
	if gold_label_index >= 0:
		top_bar.move_child(gold_icon, gold_label_index)
	if ore_label_index >= 0:
		top_bar.move_child(ore_icon, ore_label_index)

func _load_first_texture(paths: Array[String]) -> Texture2D:
	for path: String in paths:
		if ResourceLoader.exists(path):
			return load(path)
	return null

func _pulse_label(target: Label, accent: Color, is_gold: bool) -> void:
	if not target:
		return
	var key_tween: Tween = gold_label_tween if is_gold else ore_label_tween
	if key_tween:
		key_tween.kill()
	target.scale = Vector2.ONE
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", Vector2(1.08, 1.08), 0.10)
	tween.parallel().tween_property(target, "modulate", accent, 0.08)
	tween.tween_property(target, "scale", Vector2.ONE, 0.16)
	tween.parallel().tween_property(target, "modulate", Color.WHITE, 0.14)
	if is_gold:
		gold_label_tween = tween
	else:
		ore_label_tween = tween

func _apply_visual_theme() -> void:
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.04, 0.07, 0.10, 0.88)
	top_style.border_color = Color(0.28, 0.46, 0.68, 0.94)
	top_style.set_border_width_all(1)
	top_style.corner_radius_top_left = 12
	top_style.corner_radius_top_right = 12
	top_style.corner_radius_bottom_left = 12
	top_style.corner_radius_bottom_right = 12
	if top_plate:
		top_plate.add_theme_stylebox_override("panel", top_style)

	var bottom_style := StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.03, 0.05, 0.08, 0.86)
	bottom_style.border_color = Color(0.26, 0.40, 0.60, 0.94)
	bottom_style.set_border_width_all(1)
	bottom_style.corner_radius_top_left = 12
	bottom_style.corner_radius_top_right = 12
	bottom_style.corner_radius_bottom_left = 12
	bottom_style.corner_radius_bottom_right = 12
	if bottom_plate:
		bottom_plate.add_theme_stylebox_override("panel", bottom_style)
	time_label.add_theme_color_override("font_color", Color(0.90, 0.97, 1.0))
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.60))
	ore_label.add_theme_color_override("font_color", Color(0.70, 0.96, 1.0))
	if gold_icon:
		gold_icon.modulate = Color(1.0, 0.95, 0.68, 0.95)
	if ore_icon:
		ore_icon.modulate = Color(0.72, 0.98, 1.0, 0.95)

	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	hp_bg.corner_radius_top_left = 6
	hp_bg.corner_radius_top_right = 6
	hp_bg.corner_radius_bottom_left = 6
	hp_bg.corner_radius_bottom_right = 6
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.88, 0.26, 0.24, 1.0)
	hp_fill.corner_radius_top_left = 6
	hp_fill.corner_radius_top_right = 6
	hp_fill.corner_radius_bottom_left = 6
	hp_fill.corner_radius_bottom_right = 6
	health_bar.add_theme_stylebox_override("background", hp_bg)
	health_bar.add_theme_stylebox_override("fill", hp_fill)

	var exp_bg := StyleBoxFlat.new()
	exp_bg.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	exp_bg.corner_radius_top_left = 6
	exp_bg.corner_radius_top_right = 6
	exp_bg.corner_radius_bottom_left = 6
	exp_bg.corner_radius_bottom_right = 6
	var exp_fill := StyleBoxFlat.new()
	exp_fill.bg_color = Color(0.22, 0.70, 0.98, 1.0)
	exp_fill.corner_radius_top_left = 6
	exp_fill.corner_radius_top_right = 6
	exp_fill.corner_radius_bottom_left = 6
	exp_fill.corner_radius_bottom_right = 6
	exp_bar.add_theme_stylebox_override("background", exp_bg)
	exp_bar.add_theme_stylebox_override("fill", exp_fill)
