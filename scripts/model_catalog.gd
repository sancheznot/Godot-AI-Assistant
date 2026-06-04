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
		"openai", "lmstudio", "cursor":
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
			elif not api_key.is_empty():
				headers.append("Authorization: Bearer %s" % api_key)
			_jobs.append({
				"provider_id": provider_id,
				"url": models_url,
				"method": HTTPClient.METHOD_GET,
				"headers": headers
			})
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
		_add_fallback_entry(provider_id, provider_cfg)
	else:
		var parsed: Variant = JSON.parse_string(body_text)
		var models: Array = _parse_models(provider_id, parsed, provider_cfg)
		if models.is_empty():
			_add_fallback_entry(provider_id, provider_cfg)
		else:
			for model_id in models:
				_add_entry(provider_id, String(model_id))
	
	provider_models_updated.emit(provider_id, get_entries_for_provider(provider_id))
	_current_job = {}
	_run_next_job()

func _parse_models(provider_id: String, parsed: Variant, provider_cfg: Dictionary) -> Array:
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
							models.append(name)
		"anthropic":
			if parsed is Dictionary:
				for item in parsed.get("data", parsed.get("models", [])):
					if item is Dictionary:
						var model_id: String = String(item.get("id", item.get("name", "")))
						if not model_id.is_empty():
							models.append(model_id)
		"gemini":
			if parsed is Dictionary:
				for item in parsed.get("models", []):
					if item is Dictionary:
						var raw_name: String = String(item.get("name", ""))
						if raw_name.begins_with("models/"):
							raw_name = raw_name.substr(7)
						if raw_name.begins_with("gemini") and "embed" not in raw_name:
							models.append(raw_name)
		_:
			if parsed is Dictionary:
				for item in parsed.get("data", []):
					if item is Dictionary:
						var model_id: String = String(item.get("id", ""))
						if _is_chat_model_id(provider_id, model_id):
							models.append(model_id)
	
	if models.is_empty():
		var fallback: String = String(provider_cfg.get("model", ""))
		if not fallback.is_empty():
			models.append(fallback)
	return models

func _is_chat_model_id(provider_id: String, model_id: String) -> bool:
	if model_id.is_empty():
		return false
	if "embed" in model_id or "tts" in model_id or "whisper" in model_id or "dall-e" in model_id:
		return false
	match provider_id:
		"openai":
			return model_id.begins_with("gpt-") or model_id.begins_with("o1") or model_id.begins_with("o3") or model_id.begins_with("o4") or model_id.begins_with("chatgpt")
		"cursor", "lmstudio":
			return true
		_:
			return true

func _add_entry(provider_id: String, model_id: String) -> void:
	if model_id.is_empty():
		return
	for entry in entries:
		if entry is Dictionary:
			if entry.get("provider_id") == provider_id and entry.get("model_id") == model_id:
				return
	entries.append({
		"provider_id": provider_id,
		"model_id": model_id,
		"label": model_id
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
