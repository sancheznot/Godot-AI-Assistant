extends RefCounted

# UI translations EN/ES / Traducciones de la UI

const LOCALES_DIR := "res://addons/ai_assistant_plugin/locales/"

var config_manager: RefCounted = null
var _locale_code: String = "en"
var _strings: Dictionary = {}

func setup(config_mgr: RefCounted) -> void:
	config_manager = config_mgr
	reload_locale()

func reload_locale() -> void:
	_locale_code = resolve_locale_code()
	_load_locale_file(_locale_code)
	if _locale_code != "en":
		_load_locale_file("en", true)

func resolve_locale_code() -> String:
	var setting: String = "auto"
	if config_manager:
		setting = String(config_manager.get_setting("ui_language", "auto"))
	if setting == "en" or setting == "es":
		return setting
	return _detect_system_locale()

func get_locale_code() -> String:
	return _locale_code

func get_text(key: String, args: Array = []) -> String:
	var text: String = String(_strings.get(key, key))
	if args.is_empty():
		return text
	return text % args

func _detect_system_locale() -> String:
	var locale: String = OS.get_locale().to_lower()
	if locale.begins_with("es"):
		return "es"
	return "en"

func _load_locale_file(code: String, merge_fallback: bool = false) -> void:
	var path: String = "%s%s.json" % [LOCALES_DIR, code]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if not merge_fallback:
			_strings = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		if merge_fallback:
			for key in parsed.keys():
				if not _strings.has(key):
					_strings[key] = parsed[key]
		else:
			_strings = parsed
