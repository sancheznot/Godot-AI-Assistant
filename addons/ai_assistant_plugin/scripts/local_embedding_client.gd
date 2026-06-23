extends RefCounted

# Local embedding HTTP client (Ollama / LM Studio) / Cliente HTTP de embeddings locales

signal batch_progress(done: int, total: int, message: String)
signal batch_finished(success: bool, vectors: Dictionary)

const DEFAULT_MODEL := "nomic-embed-text"
const REQUEST_TIMEOUT_SEC := 120.0
const SYNC_POLL_MS := 16

var _owner: Node = null
var _config_manager: RefCounted = null
var _http: HTTPRequest = null
var _queue: Array = []
var _pending_chunk_id: String = ""
var _results: Dictionary = {}
var _running: bool = false
var _done_count: int = 0
var _total_count: int = 0
var _query_cache: Dictionary = {}

func setup(owner: Node, config_mgr: RefCounted = null) -> void:
	_owner = owner
	_config_manager = config_mgr
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.name = "AIAssistantEmbeddingHTTP"
	owner.add_child(_http)
	_http.request_completed.connect(_on_batch_request_completed)
	_http.timeout = REQUEST_TIMEOUT_SEC

func is_available() -> bool:
	if _config_manager == null:
		return false
	if not bool(_config_manager.get_setting("enable_semantic_index", true)):
		return false
	return not get_model().is_empty()

func get_provider() -> String:
	return String(_config_manager.get_setting("embedding_provider", "ollama")).strip_edges()

func get_model() -> String:
	var model: String = String(_config_manager.get_setting("embedding_model", DEFAULT_MODEL)).strip_edges()
	if model.is_empty():
		return DEFAULT_MODEL
	return model

func get_endpoint_base() -> String:
	var custom: String = String(_config_manager.get_setting("embedding_endpoint", "")).strip_edges().trim_suffix("/")
	if not custom.is_empty():
		return custom
	if _config_manager == null or not _config_manager.has_method("get_provider_config"):
		return "http://localhost:11434"
	var provider_id: String = get_provider()
	if provider_id == "lmstudio":
		var endpoint: String = String(_config_manager.get_provider_config("lmstudio").get("api_endpoint", "")).strip_edges()
		endpoint = endpoint.replace("/v1/chat/completions", "").trim_suffix("/")
		if endpoint.is_empty():
			endpoint = "http://localhost:1234"
		return endpoint
	var ollama_cfg: Dictionary = _config_manager.get_provider_config("ollama")
	return String(ollama_cfg.get("api_endpoint", "http://localhost:11434")).strip_edges().trim_suffix("/")

func embed_query(text: String) -> Array:
	var normalized: String = text.strip_edges().to_lower()
	if normalized.is_empty():
		return []
	if _query_cache.has(normalized):
		return (_query_cache[normalized] as Array).duplicate()
	var vector: Array = _embed_blocking(text)
	if not vector.is_empty():
		_query_cache[normalized] = vector.duplicate()
	return vector

func run_batch(chunks: Array) -> void:
	if _running:
		return
	_queue = chunks.duplicate(true)
	_results = {}
	_pending_chunk_id = ""
	_done_count = 0
	_total_count = _queue.size()
	_running = true
	if _total_count == 0:
		_finish_batch(true)
		return
	batch_progress.emit(0, _total_count, "Embedding 0/%d…" % _total_count)
	_process_next()

func cancel_batch() -> void:
	_queue.clear()
	_running = false
	_pending_chunk_id = ""
	if _http != null:
		_http.cancel_request()

func _process_next() -> void:
	if _queue.is_empty():
		_finish_batch(true)
		return
	var item: Dictionary = _queue[0]
	var text: String = String(item.get("text", "")).strip_edges()
	_pending_chunk_id = String(item.get("id", ""))
	if text.is_empty():
		_queue.pop_front()
		_pending_chunk_id = ""
		_done_count += 1
		call_deferred("_process_next")
		return
	var url: String = _build_url()
	var body: String = JSON.stringify(_build_body(text))
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var err: int = _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_finish_batch(false)

func _on_batch_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _running:
		return
	if not _queue.is_empty():
		_queue.pop_front()
	var chunk_id: String = _pending_chunk_id
	_pending_chunk_id = ""
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		var vector: Array = _parse_embedding_response(parsed)
		if not vector.is_empty() and not chunk_id.is_empty():
			_results[chunk_id] = vector
	else:
		push_warning("AI Assistant: embedding HTTP failed (%s / %d)" % [result, response_code])
	_done_count += 1
	batch_progress.emit(_done_count, _total_count, "Embedding %d/%d…" % [_done_count, _total_count])
	call_deferred("_process_next")

func _finish_batch(success: bool) -> void:
	_running = false
	batch_finished.emit(success, _results.duplicate(true))

func _embed_blocking(text: String) -> Array:
	var url: String = _build_url()
	var parsed_url: Dictionary = _parse_url(url)
	if parsed_url.is_empty():
		return []
	var host: String = String(parsed_url.get("host", ""))
	var port: int = int(parsed_url.get("port", 80))
	var use_tls: bool = bool(parsed_url.get("tls", false))
	var path: String = String(parsed_url.get("path", "/"))
	var client := HTTPClient.new()
	var tls := TLSOptions.client()
	var connect_err: int = client.connect_to_host(host, port, tls if use_tls else null)
	if connect_err != OK:
		return []
	var deadline: int = Time.get_ticks_msec() + int(REQUEST_TIMEOUT_SEC * 1000.0)
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return []
		OS.delay_msec(SYNC_POLL_MS)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return []
	var body: String = JSON.stringify(_build_body(text))
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var err: int = client.request(HTTPClient.METHOD_POST, path, headers, body)
	if err != OK:
		return []
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return []
		OS.delay_msec(SYNC_POLL_MS)
	var response_body: PackedByteArray = PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return []
		response_body.append_array(client.read_response_body_chunk())
		OS.delay_msec(SYNC_POLL_MS)
	if client.get_response_code() < 200 or client.get_response_code() >= 300:
		return []
	return _parse_embedding_response(JSON.parse_string(response_body.get_string_from_utf8()))

func _build_url() -> String:
	var base: String = get_endpoint_base()
	if get_provider() == "lmstudio":
		return "%s/v1/embeddings" % base
	return "%s/api/embeddings" % base

func _build_body(text: String) -> Dictionary:
	var model: String = get_model()
	if get_provider() == "lmstudio":
		return {"model": model, "input": text}
	return {"model": model, "prompt": text}

func _parse_embedding_response(parsed: Variant) -> Array:
	if not parsed is Dictionary:
		return []
	if parsed.has("embedding") and parsed.get("embedding") is Array:
		return parsed.get("embedding")
	if parsed.has("data") and parsed.get("data") is Array:
		var data: Array = parsed.get("data")
		if not data.is_empty() and data[0] is Dictionary:
			var embedding: Variant = (data[0] as Dictionary).get("embedding", [])
			if embedding is Array:
				return embedding
	return []

func _parse_url(full_url: String) -> Dictionary:
	var trimmed: String = full_url.strip_edges()
	if trimmed.is_empty():
		return {}
	var use_tls: bool = false
	if trimmed.begins_with("https://"):
		use_tls = true
		trimmed = trimmed.substr(8)
	elif trimmed.begins_with("http://"):
		use_tls = false
		trimmed = trimmed.substr(7)
	else:
		return {}
	var slash_idx: int = trimmed.find("/")
	var host_port: String = trimmed if slash_idx == -1 else trimmed.substr(0, slash_idx)
	var path: String = "" if slash_idx == -1 else trimmed.substr(slash_idx)
	if path.is_empty():
		path = "/"
	var host: String = host_port
	var port: int = 443 if use_tls else 80
	var colon_idx: int = host_port.rfind(":")
	if colon_idx != -1:
		host = host_port.substr(0, colon_idx)
		port = int(host_port.substr(colon_idx + 1))
	return {"host": host, "port": port, "tls": use_tls, "path": path}
