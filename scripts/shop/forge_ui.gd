##############################################################################
# ForgeUI - 工坊界面（占位版）
#
# 设计目的：
# - 提供show_forge()接口，避免ForgeDoor报错
# - 后续可替换为完整工坊逻辑
##############################################################################
extends Control

@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

func _ready() -> void:
	visible = false
	add_to_group("forge_ui")
	close_button.pressed.connect(_on_close_pressed)

func show_forge() -> void:
	visible = true

func _on_close_pressed() -> void:
	visible = false
