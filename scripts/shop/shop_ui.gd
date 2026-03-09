##############################################################################
# ShopUI - shop screen controller (ASCII-only)
##############################################################################
extends Control

const SHOP_ITEM_CARD_SCENE: PackedScene = preload("res://scenes/shop/shop_item_card.tscn")
const SHOP_ICON_ITEM_SCENE: PackedScene = preload("res://scenes/shop/shop_icon_item.tscn")

const UI_BG_PRIMARY: Color = Color(0.055, 0.065, 0.082, 0.975)
const UI_BG_SECONDARY: Color = Color(0.085, 0.097, 0.122, 0.965)
const UI_BORDER_PRIMARY: Color = Color(0.44, 0.54, 0.66, 0.96)
const UI_BORDER_ACCENT: Color = Color(0.90, 0.72, 0.40, 0.98)
const UI_BUTTON_BG: Color = Color(0.24, 0.34, 0.46, 0.98)
const UI_BUTTON_BG_HOVER: Color = Color(0.31, 0.42, 0.56, 0.98)
const UI_BUTTON_BG_PRESSED: Color = Color(0.18, 0.25, 0.34, 0.98)
const UI_BUTTON_BG_DISABLED: Color = Color(0.18, 0.20, 0.24, 0.78)
const TIP_COLOR_ERROR: Color = Color(1.0, 0.72, 0.56, 1.0)
const TIP_COLOR_SUCCESS: Color = Color(0.66, 0.96, 0.78, 1.0)

@onready var grid: GridContainer = $Panel/RootVBox/Grid
@onready var main_panel: Panel = $Panel
@onready var root_vbox: VBoxContainer = $Panel/RootVBox
@onready var header_box: HBoxContainer = $Panel/RootVBox/Header
@onready var status_row: HBoxContainer = $Panel/RootVBox/StatusRow
@onready var bottom_bar: HBoxContainer = $Panel/RootVBox/BottomBar
@onready var refresh_button: Button = $Panel/RootVBox/BottomBar/RefreshButton
@onready var refresh_price_label: Label = $Panel/RootVBox/BottomBar/RefreshPriceLabel
@onready var close_button: Button = $Panel/RootVBox/Header/CloseButton
@onready var tip_label: Label = $Panel/RootVBox/BottomBar/TipLabel
@onready var title_label: Label = $Panel/RootVBox/Header/TitleLabel
@onready var weapons_title: Label = $Panel/RootVBox/StatusRow/WeaponsPanel/WeaponsVBox/WeaponsTitle
@onready var items_title: Label = $Panel/RootVBox/StatusRow/ItemsPanel/ItemsVBox/ItemsTitle
@onready var weapons_panel: Panel = $Panel/RootVBox/StatusRow/WeaponsPanel
@onready var items_panel: Panel = $Panel/RootVBox/StatusRow/ItemsPanel
@onready var weapons_flow: HFlowContainer = $Panel/RootVBox/StatusRow/WeaponsPanel/WeaponsVBox/WeaponsScroll/WeaponsFlow
@onready var items_flow: HFlowContainer = $Panel/RootVBox/StatusRow/ItemsPanel/ItemsVBox/ItemsScroll/ItemsFlow
@onready var tooltip_panel: Panel = $Tooltip
@onready var tooltip_label: Label = $Tooltip/TooltipLabel

var current_offers: Array = []
var item_cards: Array = []
var previous_pause_state: bool = false
var tooltip_active: bool = false
var panel_anim_tween: Tween = null
var button_tweens: Dictionary = {}
var tooltip_target_pos: Vector2 = Vector2.ZERO
var ui_time: float = 0.0
var backdrop_rect: ColorRect = null
var panel_glow_rect: TextureRect = null
var panel_base_position: Vector2 = Vector2.ZERO
var ambient_layer: Control = null
var ambient_particles: Array[ColorRect] = []
var ambient_params: Array[Dictionary] = []
var purchase_locked: bool = false
var tip_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	add_to_group("shop_ui")
	grid.columns = 4
	refresh_button.pressed.connect(_on_refresh_pressed)
	close_button.pressed.connect(_on_close_pressed)
	_bind_button_motion(refresh_button)
	_bind_button_motion(close_button)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_setup_backdrop_fx()
	_apply_visual_theme()
	_setup_panel_glow_fx()
	_fit_panel_to_viewport()
	_setup_ambient_particles()
	panel_base_position = main_panel.position
	_setup_tooltip_style()
	_apply_localized_text()

func _process(delta: float) -> void:
	ui_time += delta
	title_label.scale = title_label.scale.lerp(Vector2.ONE * (1.0 + 0.018 * (0.5 + 0.5 * sin(ui_time * 1.8))), clamp(delta * 7.0, 0.0, 1.0))
	if panel_glow_rect:
		panel_glow_rect.modulate.a = 0.28 + 0.10 * (0.5 + 0.5 * sin(ui_time * 1.25))
		panel_glow_rect.position = Vector2(6.0 * sin(ui_time * 0.52), 5.0 * cos(ui_time * 0.47))
	if ambient_layer:
		_update_ambient_particles(delta)
	if tooltip_active and tooltip_panel.visible:
		tooltip_target_pos = get_local_mouse_position() + Vector2(16, 16)
		tooltip_panel.position = tooltip_panel.position.lerp(tooltip_target_pos, clamp(delta * 14.0, 0.0, 1.0))

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_escape"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()

func show_shop() -> void:
	visible = true
	tip_label.text = ""
	purchase_locked = false
	ShopManager.reset_refresh_count()
	_generate_offers()
	_update_refresh_price()
	_update_player_summary()
	_set_pause(true)
	GameManager.pause_shop_timer()
	_play_panel_open_anim()

func _on_refresh_pressed() -> void:
	var price: int = ShopManager.get_refresh_price()
	if GameManager.gold < price:
		_show_tip(_loc("NotEnoughGold", "Not enough gold"))
		return
	if not GameManager.spend_gold(price, "shop_refresh"):
		_show_tip(_loc("NotEnoughGold", "Not enough gold"))
		return
	ShopManager.increase_refresh_count()
	_generate_offers()
	_update_refresh_price()
	_show_tip(_loc("ShopRefreshed", "已刷新商品"), false)

func _update_refresh_price() -> void:
	var price: int = ShopManager.get_refresh_price()
	refresh_price_label.text = _loc("Price", "价格") + ": " + _format_number(price)

func _apply_localized_text() -> void:
	if title_label:
		title_label.text = _loc("ShopTitle", "Shop")
	if weapons_title:
		weapons_title.text = _loc("Weapons", "Weapons")
	if items_title:
		items_title.text = _loc("Items", "Items")
	if refresh_button:
		refresh_button.text = _loc("Refresh", "Refresh")
	if close_button:
		close_button.text = _loc("Close", "Close")
	if tip_label:
		tip_label.text = ""
	_update_refresh_price()

func _on_buy_pressed(index: int) -> void:
	if purchase_locked:
		return
	if index < 0 or index >= current_offers.size():
		return
	var offer: Dictionary = current_offers[index]
	if bool(offer.get("sold", false)):
		return
	var price: int = int(offer.get("price", 0))
	if GameManager.gold < price:
		_show_tip(_loc("NotEnoughGold", "Not enough gold"))
		return
	var player: CharacterBody2D = _get_player()
	if not player:
		_show_tip(_loc("PlayerNotFound", "Player not found"))
		return
	purchase_locked = true
	var item_type: String = offer.get("type", "")
	if item_type == "weapon":
		if not _can_buy_weapon(player):
			_show_tip(_loc("WeaponSlotsFull", "Weapon slots full"))
			purchase_locked = false
			return
		if not GameManager.spend_gold(price, "shop_weapon"):
			_show_tip(_loc("NotEnoughGold", "Not enough gold"))
			purchase_locked = false
			return
		var weapon_data: Dictionary = {
			"weapon_id": offer.get("weapon_id", ""),
			"quality": offer.get("quality", "white"),
			"attributes": offer.get("attributes", []),
			"slot_index": -1
		}
		if player.add_weapon(weapon_data):
			if player.has_method("update_all_weapons"):
				player.update_all_weapons()
			_mark_offer_sold(index)
			_reprice_visible_offers()
			_update_player_summary()
			var weapon_template: Dictionary = offer.get("data", {})
			var weapon_name: String = weapon_template.get("display_name", weapon_template.get("name_cn", _loc("Weapon", "武器")))
			_show_tip(_loc("PurchaseSuccess", "购买成功") + " " + weapon_name, false)
		else:
			_show_tip(_loc("PurchaseFailed", "Purchase failed"))
			GameManager.add_gold(price, "shop_refund")
			purchase_locked = false
			return
	elif item_type == "card":
		var card_id: String = offer.get("card_id", "")
		if not ShopManager.can_purchase_card(card_id):
			_show_tip(_loc("PurchaseLimitReached", "Purchase limit reached"))
			purchase_locked = false
			return
		if not GameManager.spend_gold(price, "shop_card"):
			_show_tip(_loc("NotEnoughGold", "Not enough gold"))
			purchase_locked = false
			return
		_apply_card_effects(player, offer.get("data", {}))
		ShopManager.register_card_purchase(card_id)
		_mark_offer_sold(index)
		_reprice_visible_offers()
		_update_player_summary()
		var card_name: String = String(offer.get("data", {}).get("name", card_id))
		_show_tip(_loc("PurchaseSuccess", "购买成功") + " " + card_name, false)
	else:
		_show_tip(_loc("PurchaseFailed", "Purchase failed"))
		purchase_locked = false
		return
	purchase_locked = false

func _on_close_pressed() -> void:
	_reset_panel_transform()
	visible = false
	_set_pause(false)
	GameManager.resume_shop_timer()

func _generate_offers() -> void:
	current_offers = ShopManager.generate_shop_offers()
	for i in range(current_offers.size()):
		var offer: Dictionary = current_offers[i]
		offer["sold"] = false
		current_offers[i] = offer
	item_cards.clear()
	for child: Node in grid.get_children():
		child.queue_free()
	var count: int = current_offers.size()
	for i in range(count):
		var offer: Dictionary = current_offers[i]
		var card: Control = SHOP_ITEM_CARD_SCENE.instantiate()
		grid.add_child(card)
		card.setup(i, offer)
		if card.has_method("play_intro_anim"):
			card.play_intro_anim(float(i) * 0.035)
		card.buy_pressed.connect(_on_buy_pressed)
		item_cards.append(card)

func _apply_card_effects(player: CharacterBody2D, card_data: Dictionary) -> void:
	var effects: Array = card_data.get("effects", [])
	for effect: Dictionary in effects:
		var stat: String = effect.get("stat", "")
		var value: float = effect.get("value", 0.0)
		if stat.is_empty():
			continue
		player.add_shop_bonus(stat, value)
	var max_hp_val: float = player.get_final_stat("Health")
	if player.current_hp > max_hp_val:
		player.current_hp = max_hp_val
	player.update_all_weapons()

func _can_buy_weapon(player: CharacterBody2D) -> bool:
	for slot: Dictionary in player.weapon_slots:
		if slot.is_empty():
			return true
	return false

func _mark_offer_sold(index: int) -> void:
	if index < 0 or index >= item_cards.size():
		return
	if index < current_offers.size():
		var offer: Dictionary = current_offers[index]
		offer["sold"] = true
		current_offers[index] = offer
	var card: Node = item_cards[index]
	if card and card.has_method("set_sold"):
		card.set_sold(true)

func _reprice_visible_offers() -> void:
	for i in range(current_offers.size()):
		var offer: Dictionary = current_offers[i]
		if bool(offer.get("sold", false)):
			continue
		var new_price: int = ShopManager.get_offer_price(offer)
		offer["price"] = new_price
		current_offers[i] = offer
		if i < item_cards.size():
			var card: Node = item_cards[i]
			if card and card.has_method("update_price"):
				card.update_price(new_price)
	_update_refresh_price()

func _show_tip(text: String, is_error: bool = true) -> void:
	tip_label.text = text
	tip_label.modulate = TIP_COLOR_ERROR if is_error else TIP_COLOR_SUCCESS
	if tip_tween:
		tip_tween.kill()
	tip_label.scale = Vector2(1.02, 1.02)
	tip_tween = create_tween()
	tip_tween.set_trans(Tween.TRANS_QUAD)
	tip_tween.set_ease(Tween.EASE_OUT)
	tip_tween.tween_property(tip_label, "scale", Vector2.ONE, 0.14)

func _update_player_summary() -> void:
	var player: CharacterBody2D = _get_player()
	if not player:
		_clear_icon_flow(weapons_flow)
		_clear_icon_flow(items_flow)
		_add_icon_item(weapons_flow, _get_placeholder_icon(), 1, "white", "")
		return
	_clear_icon_flow(weapons_flow)
	for weapon_data: Dictionary in player.weapon_slots:
		if weapon_data.is_empty():
			continue
		var weapon_template: Dictionary = GameData.get_weapon(weapon_data.get("weapon_id", ""))
		var weapon_name: String = weapon_template.get("display_name", weapon_template.get("name_cn", "Weapon"))
		var quality: String = weapon_data.get("quality", "white")
		var icon: Texture2D = _load_icon_texture(_get_weapon_icon_path(weapon_template.get("icon_id", "")))
		var tooltip: String = _build_weapon_tooltip(weapon_name, quality, weapon_data.get("attributes", []))
		_add_icon_item(weapons_flow, icon, 1, quality, tooltip)
	if weapons_flow.get_child_count() == 0:
		_add_icon_item(weapons_flow, _get_placeholder_icon(), 1, "white", "")

	_clear_icon_flow(items_flow)
	for card_id: String in ShopManager.card_purchase_counts.keys():
		var count: int = int(ShopManager.card_purchase_counts.get(card_id, 0))
		if count <= 0:
			continue
		var card: Dictionary = GameData.get_shop_card(card_id)
		var card_name: String = card.get("name", card_id)
		var icon: Texture2D = _load_icon_texture(_get_card_icon_path(card_id))
		var tooltip: String = _build_card_tooltip(card_name, card.get("rarity", "white"), card.get("effects", []), count)
		_add_icon_item(items_flow, icon, count, card.get("rarity", "white"), tooltip)
	if items_flow.get_child_count() == 0:
		_add_icon_item(items_flow, _get_placeholder_icon(), 1, "white", "")

func _quality_to_label(quality: String) -> String:
	match quality:
		"white":
			return _loc("QualityWhite", "White")
		"blue":
			return _loc("QualityBlue", "Blue")
		"purple":
			return _loc("QualityPurple", "Purple")
		"gold":
			return _loc("QualityGold", "Gold")
		_:
			return _loc("QualityWhite", "White")

func _quality_color(quality: String) -> Color:
	match quality:
		"white":
			return Color(0.9, 0.9, 0.9)
		"blue":
			return Color(0.4, 0.6, 1.0)
		"purple":
			return Color(0.8, 0.4, 1.0)
		"gold":
			return Color(1.0, 0.85, 0.4)
		_:
			return Color(0.9, 0.9, 0.9)

func _set_pause(enable: bool) -> void:
	if enable:
		previous_pause_state = get_tree().paused
		get_tree().paused = true
	else:
		get_tree().paused = previous_pause_state

func _get_weapon_icon_path(icon_id: String) -> String:
	if icon_id.is_empty():
		return ""
	return "res://assets/PIC/wuqi/icon/256/" + icon_id + ".png"

func _get_card_icon_path(card_id: String) -> String:
	if card_id.is_empty():
		return ""
	return "res://assets/PIC/shop/256/" + card_id + ".png"

func _load_icon_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return _get_placeholder_icon()
	return load(path)

func _get_placeholder_icon() -> Texture2D:
	var img: Image = Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func _clear_icon_flow(flow: HFlowContainer) -> void:
	for child: Node in flow.get_children():
		child.queue_free()

func _add_icon_item(flow: HFlowContainer, icon: Texture2D, count: int, quality: String, tooltip: String) -> void:
	var item: Control = SHOP_ICON_ITEM_SCENE.instantiate()
	flow.add_child(item)
	if item.has_method("setup"):
		item.setup(icon, count, quality, tooltip)
	if item.has_signal("hovered"):
		item.hovered.connect(_on_icon_hovered)
	if item.has_signal("unhovered"):
		item.unhovered.connect(_on_icon_unhovered)

func _build_weapon_tooltip(name: String, quality: String, attributes: Array) -> String:
	var lines: Array[String] = []
	lines.append(name + " (" + _quality_to_label(quality) + ")")
	if attributes.size() > 0:
		lines.append("词条:")
		for attr: Dictionary in attributes:
			var attr_type: String = attr.get("type", "")
			var value: float = attr.get("value", 0.0)
			if attr_type.is_empty():
				continue
			var label: String = _weapon_attr_label(attr_type)
			var sign: String = "+" if value >= 0 else ""
			lines.append(" - " + label + " " + sign + str(value))
	return "\n".join(lines)

func _build_card_tooltip(name: String, quality: String, effects: Array, count: int) -> String:
	var lines: Array[String] = []
	lines.append(name + " (" + _quality_to_label(quality) + ") x" + str(count))
	if effects.size() == 0:
		return "\n".join(lines)
	lines.append("效果:")
	for effect: Dictionary in effects:
		var stat: String = effect.get("stat", "")
		var value: float = effect.get("value", 0.0)
		if stat.is_empty():
			continue
		var label: String = _stat_label(stat)
		var sign: String = "+" if value >= 0 else ""
		lines.append(" - " + label + " " + sign + str(value))
	return "\n".join(lines)

func _weapon_attr_label(attr_type: String) -> String:
	var map_dict: Dictionary = {
		"damage": "Damage",
		"crit_rate": "CritRate",
		"crit_dmg": "CritDamage",
		"cdr": "Cooldown",
		"all_dmg": "AllDamage",
		"melee_dmg": "MeleeDamage",
		"ranged_dmg": "RangedDamage",
		"element_dmg": "ElementalDamage",
		"summon_dmg": "SummonDamage"
	}
	var key_str: String = map_dict.get(attr_type, attr_type)
	return _localize_stat(key_str)

func _stat_label(stat: String) -> String:
	var map_dict: Dictionary = {
		"summon_count": "SummonCount",
		"summon_cdr_inherit": "SummonCooldownInherit",
		"summon_crit_inherit": "SummonCritInherit"
	}
	var key_str: String = map_dict.get(stat, stat)
	return _localize_stat(key_str)

func _localize_stat(key_str: String) -> String:
	if Localization:
		var text: String = Localization.tr_text(key_str)
		return text if not text.is_empty() else key_str
	return key_str

func _on_icon_hovered(text: String) -> void:
	if text.is_empty():
		return
	if tooltip_label:
		tooltip_label.text = text
	if tooltip_panel:
		tooltip_panel.visible = true
		tooltip_target_pos = get_local_mouse_position() + Vector2(16, 16)
		tooltip_panel.position = tooltip_target_pos
		tooltip_active = true

func _on_icon_unhovered() -> void:
	if tooltip_panel:
		tooltip_panel.visible = false
	tooltip_active = false

func _setup_backdrop_fx() -> void:
	backdrop_rect = ColorRect.new()
	backdrop_rect.name = "BackdropFX"
	backdrop_rect.anchors_preset = PRESET_FULL_RECT
	backdrop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_rect.color = Color(0.02, 0.03, 0.04, 0.82)
	add_child(backdrop_rect)
	move_child(backdrop_rect, 0)

func _setup_panel_glow_fx() -> void:
	if panel_glow_rect:
		return
	panel_glow_rect = TextureRect.new()
	panel_glow_rect.name = "PanelGlowFX"
	panel_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_glow_rect.anchors_preset = PRESET_FULL_RECT
	panel_glow_rect.texture = _create_glow_texture()
	panel_glow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_glow_rect.stretch_mode = TextureRect.STRETCH_SCALE
	panel_glow_rect.modulate = Color(0.88, 0.80, 0.58, 0.25)
	main_panel.add_child(panel_glow_rect)
	main_panel.move_child(panel_glow_rect, 0)

func _create_glow_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.00),
		Color(1.0, 1.0, 1.0, 0.22),
		Color(1.0, 1.0, 1.0, 0.08),
		Color(1.0, 1.0, 1.0, 0.00)
	])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 1000
	tex.height = 1000
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex

func _setup_ambient_particles() -> void:
	if ambient_layer:
		return
	ambient_layer = Control.new()
	ambient_layer.name = "AmbientFX"
	ambient_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ambient_layer.anchors_preset = PRESET_FULL_RECT
	ambient_layer.clip_contents = true
	main_panel.add_child(ambient_layer)
	main_panel.move_child(ambient_layer, 1)

	ambient_particles.clear()
	ambient_params.clear()
	for _i in range(18):
		var dot := ColorRect.new()
		var size_px: float = randf_range(2.0, 6.0)
		dot.size = Vector2(size_px, size_px)
		dot.color = Color(0.72 + randf() * 0.18, 0.78 + randf() * 0.14, 0.94 + randf() * 0.06, randf_range(0.08, 0.22))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ambient_layer.add_child(dot)
		ambient_particles.append(dot)
		ambient_params.append({
			"speed": randf_range(12.0, 28.0),
			"drift": randf_range(6.0, 14.0) * (1.0 if randf() < 0.5 else -1.0),
			"phase": randf() * TAU,
			"base_a": randf_range(0.08, 0.22)
		})
	_reset_ambient_particles()

func _reset_ambient_particles() -> void:
	if not ambient_layer or not main_panel:
		return
	var panel_size: Vector2 = main_panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	for i in range(ambient_particles.size()):
		var dot: ColorRect = ambient_particles[i]
		if not is_instance_valid(dot):
			continue
		dot.position = Vector2(
			randf_range(8.0, max(12.0, panel_size.x - 12.0)),
			randf_range(8.0, max(12.0, panel_size.y - 12.0))
		)
		var data: Dictionary = ambient_params[i]
		data["phase"] = randf() * TAU
		ambient_params[i] = data

func _update_ambient_particles(delta: float) -> void:
	if not main_panel:
		return
	var panel_size: Vector2 = main_panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	for i in range(ambient_particles.size()):
		var dot: ColorRect = ambient_particles[i]
		if not is_instance_valid(dot):
			continue
		var data: Dictionary = ambient_params[i]
		var speed: float = float(data.get("speed", 18.0))
		var drift: float = float(data.get("drift", 8.0))
		var phase: float = float(data.get("phase", 0.0))
		var base_a: float = float(data.get("base_a", 0.14))
		var pos: Vector2 = dot.position
		pos.y -= speed * delta
		pos.x += drift * sin(ui_time * 1.2 + phase) * delta
		if pos.y < -10.0:
			pos.y = panel_size.y + randf_range(2.0, 20.0)
			pos.x = randf_range(8.0, max(12.0, panel_size.x - 12.0))
		if pos.x < -12.0:
			pos.x = panel_size.x + randf_range(0.0, 8.0)
		elif pos.x > panel_size.x + 12.0:
			pos.x = -randf_range(0.0, 8.0)
		dot.position = pos
		var alpha: float = base_a + 0.10 * (0.5 + 0.5 * sin(ui_time * 2.0 + phase))
		var c: Color = dot.color
		c.a = alpha
		dot.color = c
		data["phase"] = phase + delta * 0.35
		ambient_params[i] = data

func _bind_button_motion(button: Button) -> void:
	if not button:
		return
	button.mouse_entered.connect(_on_button_hovered.bind(button))
	button.mouse_exited.connect(_on_button_unhovered.bind(button))

func _on_button_hovered(button: Button) -> void:
	_tween_button_scale(button, 1.05)

func _on_button_unhovered(button: Button) -> void:
	_tween_button_scale(button, 1.0)

func _tween_button_scale(button: Button, target: float) -> void:
	if not button:
		return
	var key: String = str(button.get_instance_id())
	if button_tweens.has(key):
		var old_tween: Tween = button_tweens[key]
		if old_tween:
			old_tween.kill()
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * target, 0.12)
	button_tweens[key] = tween

func _setup_tooltip_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_BG_SECONDARY
	style.set_border_width_all(2)
	style.border_color = UI_BORDER_ACCENT
	style.shadow_size = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_offset = Vector2(0, 4)
	tooltip_panel.add_theme_stylebox_override("panel", style)
	tooltip_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	tooltip_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.86))
	tooltip_label.add_theme_constant_override("outline_size", 2)

func _apply_visual_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI_BG_PRIMARY
	panel_style.border_color = UI_BORDER_PRIMARY
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.shadow_size = 22
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.44)
	panel_style.shadow_offset = Vector2(0, 10)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	var sub_panel_style := StyleBoxFlat.new()
	sub_panel_style.bg_color = UI_BG_SECONDARY
	sub_panel_style.border_color = UI_BORDER_PRIMARY.darkened(0.14)
	sub_panel_style.set_border_width_all(1)
	sub_panel_style.corner_radius_top_left = 12
	sub_panel_style.corner_radius_top_right = 12
	sub_panel_style.corner_radius_bottom_left = 12
	sub_panel_style.corner_radius_bottom_right = 12
	sub_panel_style.shadow_size = 6
	sub_panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	sub_panel_style.shadow_offset = Vector2(0, 3)
	weapons_panel.add_theme_stylebox_override("panel", sub_panel_style)
	items_panel.add_theme_stylebox_override("panel", sub_panel_style)

	var action_style := StyleBoxFlat.new()
	action_style.bg_color = UI_BUTTON_BG
	action_style.border_color = UI_BORDER_ACCENT
	action_style.set_border_width_all(1)
	action_style.corner_radius_top_left = 8
	action_style.corner_radius_top_right = 8
	action_style.corner_radius_bottom_left = 8
	action_style.corner_radius_bottom_right = 8
	var action_hover := action_style.duplicate()
	action_hover.bg_color = UI_BUTTON_BG_HOVER
	var action_pressed := action_style.duplicate()
	action_pressed.bg_color = UI_BUTTON_BG_PRESSED
	var action_disabled := action_style.duplicate()
	action_disabled.bg_color = UI_BUTTON_BG_DISABLED
	action_disabled.border_color = UI_BORDER_PRIMARY.darkened(0.24)
	for btn: Button in [refresh_button, close_button]:
		btn.add_theme_stylebox_override("normal", action_style)
		btn.add_theme_stylebox_override("hover", action_hover)
		btn.add_theme_stylebox_override("pressed", action_pressed)
		btn.add_theme_stylebox_override("disabled", action_disabled)
	title_label.add_theme_color_override("font_color", Color(0.98, 0.97, 0.92))
	weapons_title.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
	items_title.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
	refresh_price_label.add_theme_color_override("font_color", Color(0.98, 0.90, 0.68))
	tip_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	tip_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.82))
	tip_label.add_theme_constant_override("outline_size", 2)

func _fit_panel_to_viewport() -> void:
	if not main_panel:
		return
	var vp: Vector2 = get_viewport_rect().size
	var panel_w: float = clamp(vp.x * 0.95, 920.0, 1520.0)
	var panel_h: float = clamp(vp.y * 0.92, 620.0, 900.0)
	main_panel.offset_left = -panel_w * 0.5
	main_panel.offset_right = panel_w * 0.5
	main_panel.offset_top = -panel_h * 0.5
	main_panel.offset_bottom = panel_h * 0.5
	panel_base_position = main_panel.position
	if vp.x < 900.0:
		grid.columns = 1
	elif vp.x < 1200.0:
		grid.columns = 2
	else:
		grid.columns = 4
	_apply_responsive_layout(vp)

func _apply_responsive_layout(vp: Vector2 = get_viewport_rect().size) -> void:
	var title_size: int = int(clamp(vp.x / 52.0, 26.0, 40.0))
	var section_size: int = int(clamp(vp.x / 95.0, 15.0, 22.0))
	var body_size: int = int(clamp(vp.x / 110.0, 13.0, 18.0))
	title_label.add_theme_font_size_override("font_size", title_size)
	weapons_title.add_theme_font_size_override("font_size", section_size)
	items_title.add_theme_font_size_override("font_size", section_size)
	refresh_price_label.add_theme_font_size_override("font_size", body_size)
	tip_label.add_theme_font_size_override("font_size", body_size)
	tooltip_label.add_theme_font_size_override("font_size", int(clamp(body_size - 1, 12, 17)))
	root_vbox.add_theme_constant_override("separation", int(clamp(vp.y * 0.014, 10.0, 20.0)))
	header_box.add_theme_constant_override("separation", int(clamp(vp.x * 0.008, 10.0, 18.0)))
	status_row.add_theme_constant_override("separation", int(clamp(vp.x * 0.008, 8.0, 16.0)))
	bottom_bar.add_theme_constant_override("separation", int(clamp(vp.x * 0.008, 8.0, 16.0)))
	grid.add_theme_constant_override("h_separation", int(clamp(vp.x * 0.008, 10.0, 18.0)))
	grid.add_theme_constant_override("v_separation", int(clamp(vp.y * 0.012, 10.0, 18.0)))
	var button_h: float = clamp(vp.y * 0.05, 40.0, 56.0)
	refresh_button.custom_minimum_size = Vector2(max(140.0, vp.x * 0.12), button_h)
	close_button.custom_minimum_size = Vector2(max(130.0, vp.x * 0.10), button_h)

func _on_viewport_size_changed() -> void:
	_fit_panel_to_viewport()
	_reset_ambient_particles()

func _play_panel_open_anim() -> void:
	if not main_panel:
		return
	_reset_panel_transform()
	main_panel.pivot_offset = main_panel.size * 0.5
	main_panel.position = panel_base_position + Vector2(0.0, 14.0)
	main_panel.scale = Vector2(0.96, 0.96)
	main_panel.modulate.a = 0.0
	if panel_anim_tween:
		panel_anim_tween.kill()
	panel_anim_tween = create_tween()
	panel_anim_tween.set_trans(Tween.TRANS_CUBIC)
	panel_anim_tween.set_ease(Tween.EASE_OUT)
	panel_anim_tween.tween_property(main_panel, "scale", Vector2.ONE, 0.22)
	panel_anim_tween.parallel().tween_property(main_panel, "modulate:a", 1.0, 0.20)
	panel_anim_tween.parallel().tween_property(main_panel, "position", panel_base_position, 0.20)

func _reset_panel_transform() -> void:
	if not main_panel:
		return
	main_panel.position = panel_base_position
	main_panel.scale = Vector2.ONE
	main_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _get_player() -> CharacterBody2D:
	if GameManager and GameManager.player:
		return GameManager.player
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _loc(key: String, fallback: String) -> String:
	if Localization:
		var text: String = Localization.tr_text(key)
		if not text.is_empty() and text != key:
			return text
	return fallback

func _format_number(value: int) -> String:
	var sign: String = "-" if value < 0 else ""
	var text: String = str(abs(value))
	var chunks: Array[String] = []
	while text.length() > 3:
		chunks.push_front(text.substr(text.length() - 3, 3))
		text = text.substr(0, text.length() - 3)
	chunks.push_front(text)
	return sign + ",".join(chunks)
