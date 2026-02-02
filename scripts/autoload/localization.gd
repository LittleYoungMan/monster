##############################################################################
# Localization - 本地化系统
#
# 设计目的：
# - 提供中英文切换
# - 封装TranslationServer
# - 对外提供翻译接口
##############################################################################
extends Node

## 当前语言（"zh"/"en"）
var current_language: String = "zh"

## 支持语言列表
const SUPPORTED_LANGUAGES: Array[String] = ["zh", "en"]

## 语言切换信号
signal language_changed(language: String)

##############################################################################
# 初始化
##############################################################################

func _ready() -> void:
	var system_locale: String = OS.get_locale().substr(0, 2)
	if system_locale in SUPPORTED_LANGUAGES:
		current_language = system_locale
	else:
		current_language = "zh"

	# 加载翻译资源
	_load_translations()

	TranslationServer.set_locale(current_language)
	print("[Localization] 初始化完成，当前语言=", current_language)

##############################################################################
# 内部函数
##############################################################################

func _load_translations() -> void:
	var zh_trans: Translation = load("res://assets/data/localization.zh.translation")
	if zh_trans:
		TranslationServer.add_translation(zh_trans)
		print("[Localization] 已加载中文翻译")

	var en_trans: Translation = load("res://assets/data/localization.en.translation")
	if en_trans:
		TranslationServer.add_translation(en_trans)
		print("[Localization] 已加载英文翻译")

##############################################################################
# 对外接口
##############################################################################

## 翻译单个key
func tr_text(key: String) -> String:
	return tr(key)

## 设置语言
func set_language(language: String) -> void:
	if language not in SUPPORTED_LANGUAGES:
		push_error("[Localization] 不支持的语言: " + language)
		return
	current_language = language
	TranslationServer.set_locale(language)
	language_changed.emit(language)
	print("[Localization] 语言已切换为: ", language)

## 获取当前语言
func get_current_language() -> String:
	return current_language

## 切换语言（循环）
func toggle_language() -> void:
	var current_index: int = SUPPORTED_LANGUAGES.find(current_language)
	var next_index: int = (current_index + 1) % SUPPORTED_LANGUAGES.size()
	set_language(SUPPORTED_LANGUAGES[next_index])

## 批量翻译
func tr_batch(keys: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for key: String in keys:
		result.append(tr(key))
	return result
