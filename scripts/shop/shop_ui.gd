##############################################################################
# ShopUI - 商店界面（占位版）
#
# 设计目的：
# - 提供show_shop()接口，避免ShopDoor报错
# - 后续可替换为完整商店逻辑
##############################################################################
extends Control

@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

func _ready() -> void:
	visible = false
	add_to_group("shop_ui")
	close_button.pressed.connect(_on_close_pressed)

func show_shop() -> void:
	visible = true

func _on_close_pressed() -> void:
	visible = false
