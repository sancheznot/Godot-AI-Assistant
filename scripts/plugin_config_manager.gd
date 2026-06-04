extends RefCounted

# Plugin Configuration Manager / Gestor de configuración del plugin

const CONFIG_PATH := "res://addons/ai_assistant_plugin/config/plugin_config.json"

const PROVIDER_IDS := ["ollama", "lmstudio", "openai", "anthropic", "cursor", "gemini"]
const PROVIDER_LABELS := {
	"ollama": "Ollama",
	"lmstudio": "LM Studio",
	"openai": "OpenAI",
	"anthropic": "Anthropic",
	"cursor": "Cursor",
	"gemini": "Gemini",
}

var config := {}

func _init() -> void:
	load_config()

func load_config(config_path: String = CONFIG_PATH) -> bool:
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		create_default_config()
		return false
	
	var json_result = JSON.parse_string(file.get_as_text())
	file.close()
	if json_result == null:
		push_error("AI Assistant: invalid config JSON")
		return false
	
	config = json_result
	_migrate_legacy_config()
	return true

func save_config(config_path: String = CONFIG_PATH) -> bool:
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		push_error("AI Assistant: could not save config")
		return false
	
	file.store_string(JSON.stringify(config, "\t"))
	file.close()
	return true

func create_default_config() -> void:
	config = {
		"plugin": {
			"name": "AI Assistant Plugin",
			"version": "1.3.0",
			"description": "Asistente AI integrado en el editor de Godot",
			"author": "sancheznotdev"
		},
		"ai_models": {
			"default_provider": "ollama",
			"ollama": {
				"enabled": true,
				"api_endpoint": "http://localhost:11434",
				"model": "llama3.2"
			},
			"lmstudio": {
				"enabled": false,
				"api_endpoint": "http://localhost:1234/v1/chat/completions",
				"model": "local-model",
				"api_key": ""
			},
			"openai": {
				"enabled": false,
				"api_key": "",
				"api_endpoint": "https://api.openai.com/v1/chat/completions",
				"model": "gpt-4o-mini"
			},
			"anthropic": {
				"enabled": false,
				"api_key": "",
				"api_endpoint": "https://api.anthropic.com/v1/messages",
				"model": "claude-3-5-haiku-20241022"
			},
			"cursor": {
				"enabled": false,
				"api_key": "",
				"api_endpoint": "http://127.0.0.1:8080/v1/chat/completions",
				"model": "composer-2.5",
				"api_mode": "local_proxy"
			},
			"gemini": {
				"enabled": false,
				"api_key": "",
				"api_endpoint": "https://generativelanguage.googleapis.com/v1beta",
				"model": "gemini-2.0-flash"
			}
		},
		"settings": {
			"max_tokens": 4096,
			"temperature": 0.7,
			"include_project_context": true,
			"context_depth": "intermediate",
			"enable_editor_tools": true,
			"enable_agent_loop": true,
			"enable_thinking": true,
			"ui_language": "auto",
			"agent_max_steps": 8,
			"max_response_retries": 3,
			"ollama_max_num_ctx": 32768,
			"active_skill": "godot_scene_editing",
			"skills_path": "res://addons/ai_assistant_plugin/skills",
			"harness_base_context_path": "res://addons/ai_assistant_plugin/harness/base_context.md",
			"harness_thinking_path": "res://addons/ai_assistant_plugin/harness/thinking_instructions.md"
		}
	}
	save_config()

func _migrate_legacy_config() -> void:
	if not config.has("ai_models"):
		return
	
	var models: Dictionary = config.ai_models
	if models.has("local") and not models.has("ollama"):
		models["ollama"] = {
			"enabled": models.local.get("enabled", true),
			"api_endpoint": _normalize_ollama_endpoint(String(models.local.get("api_endpoint", "http://localhost:11434"))),
			"model": "llama3.2"
		}
		models.erase("local")
	
	if models.has("default_model") and not models.has("default_provider"):
		var legacy_default := String(models.default_model)
		models["default_provider"] = "ollama" if legacy_default == "local" else legacy_default
		models.erase("default_model")
	
	for provider_id in PROVIDER_IDS:
		if not models.has(provider_id):
			if provider_id == "gemini":
				models["gemini"] = {
					"enabled": false,
					"api_key": "",
					"api_endpoint": "https://generativelanguage.googleapis.com/v1beta",
					"model": "gemini-2.0-flash"
				}
			elif provider_id == "cursor":
				models["cursor"] = {
					"enabled": false,
					"api_key": "",
					"api_endpoint": "http://127.0.0.1:8080/v1/chat/completions",
					"model": "composer-2.5",
					"api_mode": "local_proxy"
				}
			continue
		var provider_cfg: Dictionary = models[provider_id]
		if not provider_cfg.has("model"):
			provider_cfg["model"] = _default_model_for_provider(provider_id)
		if provider_id == "ollama" and provider_cfg.has("api_endpoint"):
			provider_cfg["api_endpoint"] = _normalize_ollama_endpoint(String(provider_cfg.api_endpoint))
		if provider_id == "ollama" and provider_cfg.has("api_mode"):
			provider_cfg.erase("api_mode")
	
	if not config.has("settings"):
		config["settings"] = {}
	
	var settings: Dictionary = config.settings
	if not settings.has("include_project_context"):
		settings["include_project_context"] = true
	if not settings.has("context_depth"):
		settings["context_depth"] = "intermediate"
	if not settings.has("enable_editor_tools"):
		settings["enable_editor_tools"] = true
	if not settings.has("enable_agent_loop"):
		settings["enable_agent_loop"] = true
	if not settings.has("agent_max_steps"):
		settings["agent_max_steps"] = 8
	if not settings.has("max_response_retries"):
		settings["max_response_retries"] = 3
	if not settings.has("active_skill"):
		settings["active_skill"] = "godot_scene_editing"
	if not settings.has("skills_path"):
		settings["skills_path"] = "res://addons/ai_assistant_plugin/skills"
	if not settings.has("enable_thinking"):
		settings["enable_thinking"] = true
	if not settings.has("harness_base_context_path"):
		settings["harness_base_context_path"] = "res://addons/ai_assistant_plugin/harness/base_context.md"
	if not settings.has("harness_thinking_path"):
		settings["harness_thinking_path"] = "res://addons/ai_assistant_plugin/harness/thinking_instructions.md"
	if not settings.has("ui_language"):
		settings["ui_language"] = "auto"

func _normalize_ollama_endpoint(endpoint: String) -> String:
	var value := endpoint.strip_edges().trim_suffix("/")
	if value.ends_with("/api/generate") or value.ends_with("/api/chat"):
		value = value.get_base_dir()
	return value if not value.is_empty() else "http://localhost:11434"

func _default_model_for_provider(provider_id: String) -> String:
	match provider_id:
		"ollama":
			return "llama3.2"
		"lmstudio":
			return "local-model"
		"openai":
			return "gpt-4o-mini"
		"anthropic":
			return "claude-3-5-haiku-20241022"
		"cursor":
			return "composer-2.5"
		"gemini":
			return "gemini-2.0-flash"
		_:
			return "default"

func get_setting(key: String, default_value = null):
	if config.has("settings") and config.settings.has(key):
		return config.settings[key]
	return default_value

func set_setting(key: String, value) -> void:
	if not config.has("settings"):
		config["settings"] = {}
	config.settings[key] = value
	save_config()

func get_provider_config(provider_id: String) -> Dictionary:
	if config.has("ai_models") and config.ai_models.has(provider_id):
		return config.ai_models[provider_id]
	return {}

func set_provider_config(provider_id: String, provider_config: Dictionary) -> void:
	if not config.has("ai_models"):
		config["ai_models"] = {}
	config.ai_models[provider_id] = provider_config
	save_config()

func is_provider_enabled(provider_id: String) -> bool:
	var provider_cfg := get_provider_config(provider_id)
	return provider_cfg.get("enabled", false)

func set_provider_enabled(provider_id: String, enabled: bool) -> void:
	var provider_cfg := get_provider_config(provider_id)
	if provider_cfg.is_empty():
		return
	provider_cfg["enabled"] = enabled
	set_provider_config(provider_id, provider_cfg)

func get_default_provider() -> String:
	if config.has("ai_models"):
		return String(config.ai_models.get("default_provider", "ollama"))
	return "ollama"

func set_default_provider(provider_id: String) -> void:
	if not config.has("ai_models"):
		config["ai_models"] = {}
	config.ai_models["default_provider"] = provider_id
	save_config()

func get_enabled_providers() -> Array[String]:
	var enabled: Array[String] = []
	for provider_id in PROVIDER_IDS:
		if is_provider_enabled(provider_id):
			enabled.append(provider_id)
	return enabled

func get_provider_label(provider_id: String) -> String:
	return String(PROVIDER_LABELS.get(provider_id, provider_id))
