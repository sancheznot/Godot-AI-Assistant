extends RefCounted

# Fetches available models from enabled providers / Catálogo dinámico de modelos

signal catalog_updated(entries: Array)
signal provider_models_updated(provider_id: String, entries: Array)
signal refresh_started()
signal refresh_finished()

var config_manager: RefCounted = null
var http_request: HTTPRequest = null

var entries: Array = []
var _jobs: Array = []
var _current_job: Dictionary = {}
var _is_refreshing: bool = false

const MINIMAX_KNOWN_MODELS: Array[String] = [
	"MiniMax-M3",
	"MiniMax-M2.7",
	"MiniMax-M2.7-highspeed",
	"MiniMax-M2.5",
	"MiniMax-M2.5-highspeed",
	"MiniMax-M2.1",
	"MiniMax-M2.1-highspeed",
	"MiniMax-M2",
	"M2-her",
]

func setup(owner: Node, config_mgr: RefCounted) -> void:
	config_manager = config_mgr
	if http_request != null:
		return
	http_request = HTTPRequest.new()
	owner.add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func is_refreshing() -> bool:
	return _is_refreshing

func get_entries() -> Array:
	return entries.duplicate(true)

func get_entries_for_provider(provider_id: String) -> Array:
	var result: Array = []
	for entry in entries:
		if entry is Dictionary and String(entry.get("provider_id", "")) == provider_id:
			result.append(entry)
	return result

func refresh_all() -> void:
	_jobs.clear()
	entries.clear()
	_is_refreshing = true
	refresh_started.emit()
	
	for provider_id in config_manager.PROVIDER_IDS:
		if config_manager.is_provider_enabled(provider_id):
			_queue_provider_job(provider_id)
	
	if _jobs.is_empty():
		_is_refreshing = false
		refresh_finished.emit()
		catalog_updated.emit(entries)
		return
	
	_run_next_job()

func refresh_provider(provider_id: String) -> void:
	_remove_provider_entries(provider_id)
	_queue_provider_job(provider_id)
	if _jobs.is_empty():
		provider_models_updated.emit(provider_id, get_entries_for_provider(provider_id))
		catalog_updated.emit(entries)
		return
	if not _is_refreshing:
		_is_refreshing = true
		refresh_started.emit()
	_run_next_job()

func _queue_provider_job(provider_id: String) -> void:
	var provider_cfg: Dictionary = config_manager.get_provider_config(provider_id)
	if provider_cfg.is_empty():
		return
	
	match provider_id:
		"ollama":
			var base: String = _normalize_ollama_base(String(provider_cfg.get("api_endpoint", "http://localhost:11434")))
			_jobs.append({
				"provider_id": provider_id,
				"url": "%s/api/tags" % base,
				"method": HTTPClient.METHOD_GET,
				"headers": PackedStringArray(["Accept: application/json"])
			})
		"openai", "cursor", "openrouter", "kimi":
			var models_url: String = _openai_models_url(provider_id, provider_cfg)
			if models_url.is_empty():
				_add_fallback_entry(provider_id, provider_cfg)
				return
			var headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
			var api_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
			if provider_id == "cursor" and String(provider_cfg.get("api_mode", "local_proxy")) == "cloud_agents":
				if api_key.is_empty():
					_add_fallback_entry(provider_id, provider_cfg)
					return
				headers.append("Authorization: Bearer %s" % api_key)
			elif provider_id == "openrouter":
				if api_key.is_empty():
					_add_fallback_entry(provider_id, provider_cfg)
					return
				headers.append("Authorization: Bearer %s" % api_key)
				headers.append("HTTP-Referer: https://github.com/sancheznot/Godot-AI-Assistant")
				headers.append("X-OpenRouter-Title: Golem-AI")
			elif not api_key.is_empty():
				headers.append("Authorization: Bearer %s" % api_key)
			elif provider_id in ["kimi"]:
				_add_fallback_entry(provider_id, provider_cfg)
				return
			_jobs.append({
				"provider_id": provider_id,
				"url": models_url,
				"method": HTTPClient.METHOD_GET,
				"headers": headers
			})
		"lmstudio":
			var lmstudio_url: String = _lmstudio_native_models_url(provider_cfg)
			if lmstudio_url.is_empty():
				_add_fallback_entry(provider_id, provider_cfg)
				return
			var lm_headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
			var lm_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
			if not lm_key.is_empty():
				lm_headers.append("Authorization: Bearer %s" % lm_key)
			_jobs.append({
				"provider_id": provider_id,
				"url": lmstudio_url,
				"method": HTTPClient.METHOD_GET,
				"headers": lm_headers,
				"api_style": "lmstudio_native",
			})
		"minimax":
			var minimax_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
			if minimax_key.is_empty():
				_add_fallback_entry(provider_id, provider_cfg)
				return
			for model_id in MINIMAX_KNOWN_MODELS:
				_add_entry(provider_id, model_id)
		"anthropic":
			var anthropic_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
			if anthropic_key.is_empty():
				_add_fallback_entry(provider_id, provider_cfg)
				return
			_jobs.append({
				"provider_id": provider_id,
				"url": "https://api.anthropic.com/v1/models",
				"method": HTTPClient.METHOD_GET,
				"headers": PackedStringArray([
					"Accept: application/json",
					"x-api-key: %s" % anthropic_key,
					"anthropic-version: 2023-06-01"
				])
			})
		"gemini":
			var gemini_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
			if gemini_key.is_empty():
				_add_fallback_entry(provider_id, provider_cfg)
				return
			var gemini_base: String = String(provider_cfg.get("api_endpoint", "https://generativelanguage.googleapis.com/v1beta")).strip_edges().trim_suffix("/")
			_jobs.append({
				"provider_id": provider_id,
				"url": "%s/models?key=%s" % [gemini_base, gemini_key.uri_encode()],
				"method": HTTPClient.METHOD_GET,
				"headers": PackedStringArray(["Accept: application/json"])
			})
		_:
			_add_fallback_entry(provider_id, provider_cfg)

func _run_next_job() -> void:
	if _jobs.is_empty():
		_is_refreshing = false
		refresh_finished.emit()
		catalog_updated.emit(entries)
		return
	
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	
	_current_job = _jobs.pop_front()
	http_request.request(
		String(_current_job.get("url", "")),
		_current_job.get("headers", PackedStringArray()),
		int(_current_job.get("method", HTTPClient.METHOD_GET))
	)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var provider_id: String = String(_current_job.get("provider_id", ""))
	var provider_cfg: Dictionary = config_manager.get_provider_config(provider_id)
	var body_text: String = body.get_string_from_utf8()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("AI Assistant: could not list models for %s (HTTP %d)" % [provider_id, response_code])
		if provider_id == "lmstudio" and String(_current_job.get("api_style", "")) == "lmstudio_native":
			var compat_url: String = _openai_models_url(provider_id, provider_cfg)
			if not compat_url.is_empty():
				var compat_headers: PackedStringArray = PackedStringArray(["Accept: application/json"])
				var lm_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
				if not lm_key.is_empty():
					compat_headers.append("Authorization: Bearer %s" % lm_key)
				_jobs.insert(0, {
					"provider_id": provider_id,
					"url": compat_url,
					"method": HTTPClient.METHOD_GET,
					"headers": compat_headers,
					"api_style": "openai_compat",
				})
				provider_models_updated.emit(provider_id, get_entries_for_provider(provider_id))
				_current_job = {}
				_run_next_job()
				return
		_add_fallback_entry(provider_id, provider_cfg)
	else:
		var parsed: Variant = JSON.parse_string(body_text)
		var models: Array = _parse_models(provider_id, parsed, provider_cfg, _current_job)
		if models.is_empty():
			_add_fallback_entry(provider_id, provider_cfg)
		else:
			for model_item in models:
				if model_item is Dictionary:
					_add_entry(
						provider_id,
						String(model_item.get("model_id", "")),
						model_item.get("capabilities", {}) if model_item.get("capabilities") is Dictionary else {}
					)
				else:
					_add_entry(provider_id, String(model_item))
	
	provider_models_updated.emit(provider_id, get_entries_for_provider(provider_id))
	_current_job = {}
	_run_next_job()

func _parse_models(provider_id: String, parsed: Variant, provider_cfg: Dictionary, job: Dictionary = {}) -> Array:
	var models: Array = []
	if parsed == null:
		return models
	
	match provider_id:
		"ollama":
			if parsed is Dictionary:
				for item in parsed.get("models", []):
					if item is Dictionary:
						var name: String = String(item.get("name", item.get("model", "")))
						if not name.is_empty():
							models.append({"model_id": name, "capabilities": {}})
		"lmstudio":
			if parsed is Dictionary:
				if parsed.has("models"):
					for item in parsed.get("models", []):
						if not item is Dictionary:
							continue
						if String(item.get("type", "llm")) != "llm":
							continue
						var native_id: String = String(item.get("id", item.get("key", item.get("name", ""))))
						if native_id.is_empty():
							continue
						var caps_raw: Variant = item.get("capabilities", {})
						var native_caps: Dictionary = {}
						if caps_raw is Dictionary and caps_raw.has("vision"):
							native_caps["vision"] = bool(caps_raw.get("vision"))
						models.append({"model_id": native_id, "capabilities": native_caps})
				elif parsed.has("data"):
					for item in parsed.get("data", []):
						if item is Dictionary:
							var openai_id: String = String(item.get("id", ""))
							if _is_chat_model_id(provider_id, openai_id):
								models.append({"model_id": openai_id, "capabilities": {}})
		"anthropic":
			if parsed is Dictionary:
				for item in parsed.get("data", parsed.get("models", [])):
					if item is Dictionary:
						var model_id: String = String(item.get("id", item.get("name", "")))
						if not model_id.is_empty():
							models.append({"model_id": model_id, "capabilities": {}})
		"gemini":
			if parsed is Dictionary:
				for item in parsed.get("models", []):
					if item is Dictionary:
						var raw_name: String = String(item.get("name", ""))
						if raw_name.begins_with("models/"):
							raw_name = raw_name.substr(7)
						if raw_name.begins_with("gemini") and "embed" not in raw_name:
							models.append({"model_id": raw_name, "capabilities": {}})
		"openrouter":
			if parsed is Dictionary:
				for item in parsed.get("data", []):
					if not item is Dictionary:
						continue
					var openrouter_id: String = String(item.get("id", ""))
					if not _is_chat_model_id(provider_id, openrouter_id):
						continue
					var caps: Dictionary = _parse_openrouter_capabilities(item)
					models.append({"model_id": openrouter_id, "capabilities": caps})
		_:
			if parsed is Dictionary:
				for item in parsed.get("data", []):
					if item is Dictionary:
						var generic_id: String = String(item.get("id", ""))
						if _is_chat_model_id(provider_id, generic_id):
							models.append({"model_id": generic_id, "capabilities": {}})
	
	if models.is_empty():
		var fallback: String = String(provider_cfg.get("model", ""))
		if not fallback.is_empty():
			models.append({"model_id": fallback, "capabilities": {}})
	return models

func _parse_openrouter_capabilities(item: Dictionary) -> Dictionary:
	var caps: Dictionary = {}
	var architecture: Variant = item.get("architecture", {})
	if architecture is Dictionary:
		var modality: String = String(architecture.get("modality", "")).to_lower()
		if modality.contains("image") or modality.contains("vision"):
			caps["vision"] = true
	var name_bits: PackedStringArray = [
		String(item.get("id", "")),
		String(item.get("name", "")),
		String(item.get("description", "")),
	]
	for tag in item.get("tags", []):
		if tag is String:
			name_bits.append(tag)
	var joined: String = " ".join(name_bits).to_lower()
	if joined.contains("vision") or joined.contains("multimodal") or joined.contains("vlm"):
		caps["vision"] = true
	if joined.contains("reasoning") or joined.contains("thinking"):
		caps["thinking"] = true
	return caps

func _is_chat_model_id(provider_id: String, model_id: String) -> bool:
	if model_id.is_empty():
		return false
	if "embed" in model_id or "tts" in model_id or "whisper" in model_id or "dall-e" in model_id:
		return false
	match provider_id:
		"openai":
			return model_id.begins_with("gpt-") or model_id.begins_with("o1") or model_id.begins_with("o3") or model_id.begins_with("o4") or model_id.begins_with("chatgpt")
		"cursor", "lmstudio", "openrouter", "kimi", "minimax":
			return true
		_:
			return true

func _add_entry(provider_id: String, model_id: String, capabilities: Dictionary = {}) -> void:
	if model_id.is_empty():
		return
	for entry in entries:
		if entry is Dictionary:
			if entry.get("provider_id") == provider_id and entry.get("model_id") == model_id:
				if not capabilities.is_empty():
					entry["capabilities"] = capabilities
				return
	entries.append({
		"provider_id": provider_id,
		"model_id": model_id,
		"label": model_id,
		"capabilities": capabilities.duplicate(true),
	})

func _add_fallback_entry(provider_id: String, provider_cfg: Dictionary) -> void:
	var model_id: String = String(provider_cfg.get("model", ""))
	if model_id.is_empty():
		model_id = "default"
	_add_entry(provider_id, model_id)

func _remove_provider_entries(provider_id: String) -> void:
	var filtered: Array = []
	for entry in entries:
		if entry is Dictionary and String(entry.get("provider_id", "")) != provider_id:
			filtered.append(entry)
	entries = filtered

func _normalize_ollama_base(endpoint: String) -> String:
	var value: String = endpoint.strip_edges().trim_suffix("/")
	if value.ends_with("/api/generate") or value.ends_with("/api/chat") or value.ends_with("/api/tags"):
		value = value.get_base_dir()
		if value.ends_with("/api"):
			value = value.get_base_dir()
	return value if not value.is_empty() else "http://localhost:11434"

func _openai_models_url(provider_id: String, provider_cfg: Dictionary) -> String:
	var endpoint: String = String(provider_cfg.get("api_endpoint", "")).strip_edges().trim_suffix("/")
	if provider_id == "cursor" and String(provider_cfg.get("api_mode", "local_proxy")) == "cloud_agents":
		return "https://api.cursor.com/v1/models"
	if provider_id == "openrouter":
		return "https://openrouter.ai/api/v1/models"
	if endpoint.is_empty():
		return ""
	if endpoint.ends_with("/chat/completions"):
		return endpoint.replace("/chat/completions", "/models")
	if endpoint.ends_with("/completions"):
		return endpoint.replace("/completions", "/models")
	if endpoint.ends_with("/messages"):
		return ""
	if endpoint.ends_with("/models"):
		return endpoint
	if endpoint.ends_with("/v1"):
		return "%s/models" % endpoint
	return "%s/v1/models" % endpoint

func _lmstudio_base_url(provider_cfg: Dictionary) -> String:
	var endpoint: String = String(provider_cfg.get("api_endpoint", "http://localhost:1234/v1/chat/completions")).strip_edges().trim_suffix("/")
	if endpoint.ends_with("/v1/chat/completions"):
		return endpoint.replace("/v1/chat/completions", "")
	if endpoint.ends_with("/chat/completions"):
		endpoint = endpoint.replace("/chat/completions", "")
	if endpoint.ends_with("/v1"):
		return endpoint.get_base_dir()
	return endpoint if not endpoint.is_empty() else "http://localhost:1234"

func _lmstudio_native_models_url(provider_cfg: Dictionary) -> String:
	return "%s/api/v1/models" % _lmstudio_base_url(provider_cfg)
