##############################################################################
# Localization - 多语言系统
#
# 功能说明：
# 1. 管理中英文切换
# 2. 提供翻译接口给所有UI
# 3. 使用Godot内置Translation系统
#
# 使用方式：
#   var text = Localization.tr_text("Health")  # 返回"生命"或"Health"
#   Localization.set_language("en")  # 切换到英文
##############################################################################
extends Node

## 当前语言
## 单位：语言代码
## 作用：存储当前使用的语言
## 调整范围："zh"(中文) 或 "en"(英文)
var current_language: String = "zh"

## 支持的语言列表
## 单位：语言代码数组
## 作用：定义游戏支持的所有语言
const SUPPORTED_LANGUAGES: Array[String] = ["zh", "en"]

## 语言切换信号
## 参数：
##   language - 新语言代码
## 作用：通知所有UI刷新显示文本
signal language_changed(language: String)


## 初始化多语言系统
## 作用：设置默认语言
func _ready() -> void:
	# 从系统语言获取，如果不支持则使用中文
	var system_locale: String = OS.get_locale().substr(0, 2)
	if system_locale in SUPPORTED_LANGUAGES:
		current_language = system_locale
	else:
		current_language = "zh"
	
	# 设置Godot的翻译系统
	TranslationServer.set_locale(current_language)
	
	print("[Localization] 初始化完成，当前语言: ", current_language)


## 翻译文本
## 作用：获取指定key的翻译文本
## 参数：
##   key - 翻译键名（对应localization.csv的id列）
## 返回：
##   翻译后的文本（中文或英文）
## 示例：
##   var health_text = Localization.tr_text("Health")  # 中文环境返回"生命"
func tr_text(key: String) -> String:
	return tr(key)


## 切换语言
## 作用：改变当前语言并刷新所有UI
## 参数：
##   language - 目标语言代码（"zh"或"en"）
## 示例：
##   Localization.set_language("en")  # 切换到英文
func set_language(language: String) -> void:
	if language not in SUPPORTED_LANGUAGES:
		push_error("[Localization] 不支持的语言: " + language)
		return
	
	current_language = language
	TranslationServer.set_locale(language)
	language_changed.emit(language)
	
	print("[Localization] 语言已切换为: ", language)


## 获取当前语言
## 返回：
##   当前语言代码
func get_current_language() -> String:
	return current_language


## 切换到下一个语言（循环切换）
## 作用：在支持的语言间循环切换
## 示例：
##   Localization.toggle_language()  # zh -> en -> zh -> ...
func toggle_language() -> void:
	var current_index: int = SUPPORTED_LANGUAGES.find(current_language)
	var next_index: int = (current_index + 1) % SUPPORTED_LANGUAGES.size()
	set_language(SUPPORTED_LANGUAGES[next_index])


## 批量翻译属性名
## 作用：将属性名数组批量翻译
## 参数：
##   keys - 属性键名数组
## 返回：
##   翻译后的文本数组
## 示例：
##   var keys = ["Health", "Armor", "MoveSpeed"]
##   var translated = Localization.tr_batch(keys)  # ["生命", "护甲", "移速"]
func tr_batch(keys: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for key: String in keys:
		result.append(tr(key))
	return result
