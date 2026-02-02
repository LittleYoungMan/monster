##############################################################################
# ShopUI - shop screen controller (ASCII-only)
##############################################################################
extends Control

const SHOP_ITEM_CARD_SCENE: PackedScene = preload("res://scenes/shop/shop_item_card.tscn")
const SHOP_ICON_ITEM_SCENE: PackedScene = preload("res://scenes/shop/shop_icon_item.tscn")

@onready var grid: GridContainer = $Panel/RootVBox/Grid
@onready var refresh_button: Button = $Panel/RootVBox/BottomBar/RefreshButton
@onready var refresh_price_label: Label = $Panel/RootVBox/BottomBar/RefreshPriceLabel
@onready var close_button: Button = $Panel/RootVBox/Header/CloseButton
@onready var tip_label: Label = $Panel/RootVBox/BottomBar/TipLabel
@onready var title_label: Label = $Panel/RootVBox/Header/TitleLabel
@onready var weapons_title: Label = $Panel/RootVBox/StatusRow/WeaponsPanel/WeaponsVBox/WeaponsTitle
@onready var items_title: Label = $Panel/RootVBox/StatusRow/ItemsPanel/ItemsVBox/ItemsTitle
@onready var weapons_flow: HFlowContainer = $Panel/RootVBox/StatusRow/WeaponsPanel/WeaponsVBox/WeaponsScroll/WeaponsFlow
@onready var items_flow: HFlowContainer = $Panel/RootVBox/StatusRow/ItemsPanel/ItemsVBox/ItemsScroll/ItemsFlow
@onready var tooltip_panel: Panel = $Tooltip
@onready var tooltip_label: Label = $Tooltip/TooltipLabel

var current_offers: Array = []
var item_cards: Array = []
var previous_pause_state: bool = false
var tooltip_active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	add_to_group("shop_ui")
	grid.columns = 4
	refresh_button.pressed.connect(_on_refresh_pressed)
	close_button.pressed.connect(_on_close_pressed)
	_setup_tooltip_style()
	_apply_localized_text()

func _process(_delta: float) -> void:
	if tooltip_active and tooltip_panel.visible:
		tooltip_panel.position = get_local_mouse_position() + Vector2(16, 16)

func show_shop() -> void:
	visible = true
	tip_label.text = ""
	ShopManager.reset_refresh_count()
	_generate_offers()
	_update_refresh_price()
	_update_player_summary()
	_set_pause(true)
	GameManager.pause_shop_timer()

func _on_refresh_pressed() -> void:
	var price: int = ShopManager.get_refresh_price()
	if GameManager.gold < price:
		_show_tip(_loc("NotEnoughGold", "Not enough gold"))
		return
	if not GameManager.spend_gold(price):
		_show_tip(_loc("NotEnoughGold", "Not enough gold"))
		return
	ShopManager.increase_refresh_count()
	_generate_offers()
	_update_refresh_price()

func _update_refresh_price() -> void:
	var price: int = ShopManager.get_refresh_price()
	refresh_price_label.text = _loc("Price", "Price") + ": " + str(price)

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
	if index < 0 or index >= current_offers.size():
		return
	var offer: Dictionary = current_offers[index]
	var price: int = int(offer.get("price", 0))
	if GameManager.gold < price:
		_show_tip(_loc("NotEnoughGold", "Not enough gold"))
		return
	var player: CharacterBody2D = _get_player()
	if not player:
		_show_tip(_loc("PlayerNotFound", "Player not found"))
		return
	var item_type: String = offer.get("type", "")
	if item_type == "weapon":
		if not _can_buy_weapon(player):
			_show_tip(_loc("WeaponSlotsFull", "Weapon slots full"))
			return
		if not GameManager.spend_gold(price):
			_show_tip(_loc("NotEnoughGold", "Not enough gold"))
			return
		var weapon_data: Dictionary = {
			"weapon_id": offer.get("weapon_id", ""),
			"quality": offer.get("quality", "white"),
			"attributes": offer.get("attributes", []),
			"slot_index": -1
		}
		if player.add_weapon(weapon_data):
			_mark_offer_sold(index)
			_update_player_summary()
		else:
			_show_tip(_loc("PurchaseFailed", "Purchase failed"))
			GameManager.add_gold(price)
	elif item_type == "card":
		var card_id: String = offer.get("card_id", "")
		if not ShopManager.can_purchase_card(card_id):
			_show_tip(_loc("PurchaseLimitReached", "Purchase limit reached"))
			return
		if not GameManager.spend_gold(price):
			_show_tip(_loc("NotEnoughGold", "Not enough gold"))
			return
		_apply_card_effects(player, offer.get("data", {}))
		ShopManager.register_card_purchase(card_id)
		_mark_offer_sold(index)
		_update_player_summary()

func _on_close_pressed() -> void:
	visible = false
	_set_pause(false)
	GameManager.resume_shop_timer()

func _generate_offers() -> void:
	current_offers = ShopManager.generate_shop_offers()
	item_cards.clear()
	for child: Node in grid.get_children():
		child.queue_free()
	var count: int = min(4, current_offers.size())
	for i in range(count):
		var offer: Dictionary = current_offers[i]
		var card: Control = SHOP_ITEM_CARD_SCENE.instantiate()
		grid.add_child(card)
		card.setup(i, offer)
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
	var card: Node = item_cards[index]
	if card and card.has_method("set_sold"):
		card.set_sold(true)

func _show_tip(text: String) -> void:
	tip_label.text = text

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
		lines.append("Affixes:")
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
	lines.append("Effects:")
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
		tooltip_active = true

func _on_icon_unhovered() -> void:
	if tooltip_panel:
		tooltip_panel.visible = false
	tooltip_active = false

func _setup_tooltip_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.09, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.48, 0.36)
	tooltip_panel.add_theme_stylebox_override("panel", style)

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
