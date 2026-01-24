##############################################################################
# AttributePanel - 属性面板脚本
#
# 功能说明：
# 1. 按Tab显示/隐藏
# 2. 显示所有角色属性（中英文）
##############################################################################
extends Panel

@onready var attribute_list: VBoxContainer = $ScrollContainer/AttributeList
@onready var close_button: Button = $CloseButton

var player: CharacterBody2D = null

func _ready() -> void:
	visible = false
	await get_tree().process_frame
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	close_button.pressed.connect(_on_close_button_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_tab"):
		visible = !visible
		if visible:
			refresh_attributes()

func refresh_attributes() -> void:
	if not player:
		return
	for child: Node in attribute_list.get_children():
		child.queue_free()
	var stats: Dictionary = player.get_display_stats()
	for stat_name: String in stats.keys():
		var row: HBoxContainer = HBoxContainer.new()
		var name_lbl: Label = Label.new()
		name_lbl.text = stat_name + ":"
		name_lbl.custom_minimum_size = Vector2(200, 0)
		var val_lbl: Label = Label.new()
		val_lbl.text = stats[stat_name]
		row.add_child(name_lbl)
		row.add_child(val_lbl)
		attribute_list.add_child(row)

func _on_close_button_pressed() -> void:
	visible = false
