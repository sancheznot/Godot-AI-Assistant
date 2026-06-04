extends RefCounted

# AI Model Handler with multi-step agent loop / Manejador AI con loop agente multi-paso

signal query_started(provider_id: String)
signal query_completed(success: bool, text: String)
signal query_failed(error_message: String)
signal query_cancelled()
signal queue_updated(queue_size: int)
signal request_dequeued(user_prompt: String, options: Dictionary)
signal agent_step_update(step: int, max_steps: int, summary: String)
signal agent_log_updated(text: String, step: int, max_steps: int)
signal response_retry_attempt(attempt: int, max_attempts: int, reason: String)

const MAX_CONVERSATION_MESSAGES := 24
const DEFAULT_RESPONSE_RETRIES := 2

var config_manager: RefCounted = null
var project_context: RefCounted = null
var editor_tools: RefCounted = null
var skills_manager: RefCounted = null
var harness: RefCounted = null

var http_request: HTTPRequest = null
var cursor_cloud: RefCounted = null
var _pending_provider_id: String = ""
var _pending_enable_tools: bool = false
var _pending_options: Dictionary = {}
var _using_cursor_cloud: bool = false

var _agent_active: bool = false
var _agent_step: int = 0
var _agent_max_steps: int = 8
var _agent_messages: Array = []
var _agent_system_prompt: String = ""
var _agent_provider_id: String = ""
var _agent_provider_cfg: Dictionary = {}
var _agent_log: PackedStringArray = []
var _agent_stall_count: int = 0
var _agent_last_response_signature: String = ""
var _agent_tools_executed: int = 0
var _agent_act_nudges: int = 0
var _agent_failed_batches: int = 0
var _active_user_language: String = "es"
var _request_queue: Array = []
var _is_processing: bool = false
var _cancel_requested: bool = false
var _response_retry_count: int = 0
var _http_in_flight: bool = false
var _active_provider_id: String = ""
var _active_provider_cfg: Dictionary = {}
var _active_user_prompt: String = ""
var _pending_system_prompt: String = ""
var _pending_messages: Array = []
var _last_extracted_text: String = ""
var _last_api_body_preview: String = ""

func setup(
	owner: Node,
	config_mgr: RefCounted,
	context_builder: RefCounted,
	tools: RefCounted,
	skills: RefCounted
) -> void:
	config_manager = config_mgr
	project_context = context_builder
	editor_tools = tools
	skills_manager = skills
	
	harness = preload("res://addons/ai_assistant_plugin/scripts/harness.gd").new()
	harness.setup(config_mgr, context_builder, tools, skills)
	
	if http_request != null:
		return
	
	http_request = HTTPRequest.new()
	owner.add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	cursor_cloud = preload("res://addons/ai_assistant_plugin/scripts/cursor_cloud_client.gd").new()
	cursor_cloud.setup(owner)
	cursor_cloud.poll_update.connect(_on_cursor_poll_update)
	cursor_cloud.request_failed.connect(_on_cursor_request_failed)
	cursor_cloud.run_completed.connect(_on_cursor_run_completed)

func reload_from_config() -> void:
	if config_manager:
		config_manager.load_config()

func get_harness_layers_label(options: Dictionary, agent_mode: bool = false) -> String:
	if harness:
		return harness.get_active_layers_label(options, agent_mode)
	return "Harness: base"

func is_busy() -> bool:
	if _is_processing:
		return true
	if _http_in_flight:
		return true
	if cursor_cloud != null and cursor_cloud.is_busy():
		return true
	return false

func get_queue_size() -> int:
	return _request_queue.size()

func cancel_current_request() -> void:
	_cancel_requested = true
	_response_retry_count = 999
	_http_in_flight = false
	_request_queue.clear()
	_emit_queue_updated()
	if http_request != null and http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_request.cancel_request()
	if cursor_cloud != null:
		cursor_cloud.cancel()
	_reset_agent_state()
	_is_processing = false
	_pending_provider_id = ""
	query_cancelled.emit()
	_finish_request_cycle()

func query_provider(provider_id: String, user_prompt: String, options: Dictionary = {}) -> void:
	if http_request == null:
		query_failed.emit("HTTPRequest not initialized")
		return
	
	var request_item: Dictionary = {
		"provider_id": provider_id,
		"user_prompt": user_prompt,
		"options": options.duplicate(true)
	}
	if is_busy():
		_request_queue.append(request_item)
		_emit_queue_updated()
		return
	_start_request(request_item)

func _start_request(request_item: Dictionary) -> void:
	var provider_id: String = String(request_item.get("provider_id", ""))
	var user_prompt: String = String(request_item.get("user_prompt", ""))
	var options: Dictionary = request_item.get("options", {})
	_cancel_requested = false
	_is_processing = true
	
	var provider_cfg: Dictionary = config_manager.get_provider_config(provider_id).duplicate(true)
	if provider_cfg.is_empty():
		_finish_request_cycle()
		query_failed.emit("Proveedor desconocido: %s" % provider_id)
		return
	if not provider_cfg.get("enabled", false):
		_finish_request_cycle()
		query_failed.emit("Proveedor deshabilitado: %s" % provider_id)
		return
	
	if options.has("model_id"):
		provider_cfg["model"] = String(options.get("model_id"))
	
	if provider_id == "cursor":
		var cursor_mode: String = String(provider_cfg.get("api_mode", "local_proxy"))
		if cursor_mode == "cloud_agents" and String(provider_cfg.get("api_key", "")).strip_edges().is_empty():
			_finish_request_cycle()
			query_failed.emit("Cursor cloud_agents requiere API key")
			return
		if cursor_mode == "local_proxy" and String(provider_cfg.get("api_endpoint", "")).strip_edges().is_empty():
			_finish_request_cycle()
			query_failed.emit("Cursor local_proxy requiere endpoint URL")
			return
	
	_pending_provider_id = provider_id
	_pending_enable_tools = bool(options.get("enable_tools", config_manager.get_setting("enable_editor_tools", true)))
	_pending_options = options
	_active_provider_id = provider_id
	_active_provider_cfg = provider_cfg.duplicate(true)
	_active_user_prompt = user_prompt
	_active_user_language = _detect_language(user_prompt)
	_response_retry_count = 0
	
	var use_agent_loop: bool = bool(options.get(
		"enable_agent_loop",
		config_manager.get_setting("enable_agent_loop", true)
	))
	use_agent_loop = use_agent_loop and _pending_enable_tools and _supports_agent_loop(provider_id, provider_cfg)
	
	if use_agent_loop:
		_start_agent_loop(provider_id, provider_cfg, user_prompt, options)
	else:
		_agent_active = false
		_send_single_request(provider_id, provider_cfg, user_prompt, options)

func _finish_request_cycle() -> void:
	_is_processing = false
	_cancel_requested = false
	_process_next_queued_request()

func _process_next_queued_request() -> void:
	_emit_queue_updated()
	if _request_queue.is_empty():
		return
	var next_item: Dictionary = _request_queue.pop_front()
	_emit_queue_updated()
	request_dequeued.emit(String(next_item.get("user_prompt", "")), next_item.get("options", {}))
	_start_request(next_item)

func _emit_queue_updated() -> void:
	queue_updated.emit(_request_queue.size())

func _was_cancelled() -> bool:
	return _cancel_requested

func _handle_request_failure(error_message: String) -> void:
	_http_in_flight = false
	if _was_cancelled():
		return
	if _agent_active:
		_reset_agent_state()
	# Clear processing flag BEFORE emitting so is_busy() is false in the handler.
	# Limpiar el flag antes de emitir para que is_busy() sea false en el handler.
	_is_processing = false
	_cancel_requested = false
	query_failed.emit(error_message)
	_process_next_queued_request()

func _handle_request_success(success: bool, text: String) -> void:
	_http_in_flight = false
	if _was_cancelled():
		return
	# Clear processing flag BEFORE emitting so is_busy() is false in the handler.
	# Limpiar el flag antes de emitir para que is_busy() sea false en el handler.
	_is_processing = false
	_cancel_requested = false
	query_completed.emit(success, text)
	_process_next_queued_request()

func _supports_agent_loop(_provider_id: String, _provider_cfg: Dictionary) -> bool:
	return true

func _is_cursor_cloud_mode(provider_id: String, provider_cfg: Dictionary) -> bool:
	return provider_id == "cursor" and String(provider_cfg.get("api_mode", "local_proxy")) == "cloud_agents"

func _start_agent_loop(provider_id: String, provider_cfg: Dictionary, user_prompt: String, options: Dictionary) -> void:
	_agent_active = true
	_agent_step = 1
	_agent_max_steps = int(options.get(
		"max_agent_steps",
		config_manager.get_setting("agent_max_steps", 8)
	))
	_agent_max_steps = maxi(_agent_max_steps, 1)
	_agent_provider_id = provider_id
	_agent_provider_cfg = provider_cfg
	_agent_log.clear()
	_agent_stall_count = 0
	_agent_last_response_signature = ""
	_agent_tools_executed = 0
	_agent_act_nudges = 0
	_agent_failed_batches = 0
	_active_user_language = _detect_language(user_prompt)
	_agent_system_prompt = _build_system_prompt(user_prompt, options, true)
	_agent_messages = _build_conversation_messages(user_prompt, options)
	agent_step_update.emit(_agent_step, _agent_max_steps, "Starting agent loop...")
	_send_agent_request()

func _send_single_request(provider_id: String, provider_cfg: Dictionary, user_prompt: String, options: Dictionary) -> void:
	var system_prompt: String = _build_system_prompt(user_prompt, options, false)
	var messages: Array = _build_conversation_messages(user_prompt, options)
	_dispatch_request(provider_id, provider_cfg, system_prompt, messages)

func _build_conversation_messages(user_prompt: String, options: Dictionary) -> Array:
	var history: Array = options.get("conversation_messages", [])
	var max_messages: int = int(options.get("max_conversation_messages", MAX_CONVERSATION_MESSAGES))
	max_messages = clampi(max_messages, 2, 80)
	var slice: Array = history
	if history.size() > max_messages:
		slice = history.slice(history.size() - max_messages)
	var messages: Array = []
	for item in slice:
		if not item is Dictionary:
			continue
		var role: String = String(item.get("role", ""))
		var content: String = _sanitize_message_for_context(String(item.get("content", "")))
		if content.is_empty():
			continue
		if role == "user":
			messages.append({"role": "user", "content": content})
		elif role == "assistant" and not bool(item.get("is_error", false)):
			messages.append({"role": "assistant", "content": content})
	if messages.is_empty() or String(messages[-1].get("content", "")) != user_prompt:
		messages.append({"role": "user", "content": user_prompt})
	return messages

func _sanitize_message_for_context(text: String) -> String:
	var cleaned: String = text
	var regex := RegEx.new()
	regex.compile("(?i)(?s)<thinking>.*?</thinking>")
	cleaned = regex.sub(cleaned, "", true)
	regex.compile("(?i)(?s)\\[Thinking\\].*?\\[/Thinking\\]")
	cleaned = regex.sub(cleaned, "", true)
	regex.compile("(?m)^### Step \\d+\\s*$")
	cleaned = regex.sub(cleaned, "", true)
	regex.compile("(?m)^### Tool results.*$")
	cleaned = regex.sub(cleaned, "", true)
	while "\n\n\n" in cleaned:
		cleaned = cleaned.replace("\n\n\n", "\n\n")
	return cleaned.strip_edges()

func _send_agent_request() -> void:
	_dispatch_request(_agent_provider_id, _agent_provider_cfg, _agent_system_prompt, _agent_messages)

func _dispatch_request(provider_id: String, provider_cfg: Dictionary, system_prompt: String, messages: Array) -> void:
	_pending_provider_id = provider_id
	_pending_system_prompt = system_prompt
	_pending_messages = messages.duplicate(true)
	if _is_cursor_cloud_mode(provider_id, provider_cfg):
		_using_cursor_cloud = true
		_send_cursor_cloud_request(provider_cfg, system_prompt, messages)
		return
	
	_using_cursor_cloud = false
	var payload: Dictionary = _build_payload(provider_id, provider_cfg, system_prompt, messages, _pending_options)
	var headers: PackedStringArray = _build_headers(provider_id, provider_cfg)
	var url: String = _build_url(provider_id, provider_cfg)
	
	query_started.emit(provider_id)
	_http_in_flight = true
	var result: int = http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if result != OK:
		_http_in_flight = false
		_pending_provider_id = ""
		if _agent_active:
			_reset_agent_state()
		_handle_request_failure("No se pudo iniciar la petición HTTP")

func _send_cursor_cloud_request(provider_cfg: Dictionary, system_prompt: String, messages: Array) -> void:
	var api_key: String = String(provider_cfg.get("api_key", ""))
	var model_name: String = String(provider_cfg.get("model", "composer-2.5"))
	var prompt_text: String = _messages_to_prompt(system_prompt, messages)
	
	query_started.emit("cursor")
	if _agent_active and cursor_cloud.has_active_agent():
		cursor_cloud.follow_up_run(api_key, prompt_text)
	else:
		cursor_cloud.reset_session()
		cursor_cloud.create_agent_and_run(api_key, model_name, prompt_text)

func _on_cursor_poll_update(status: String, message: String) -> void:
	if _agent_active:
		agent_step_update.emit(_agent_step, _agent_max_steps, message)
	else:
		query_started.emit("cursor")

func _on_cursor_request_failed(error_message: String) -> void:
	if _agent_active:
		_reset_agent_state()
	if cursor_cloud:
		cursor_cloud.reset_session()
	if _was_cancelled():
		return
	_handle_request_failure(error_message)

func _on_cursor_run_completed(text: String) -> void:
	if _agent_active:
		_handle_agent_response(text)
	else:
		_handle_single_response(text)

func _build_system_prompt(user_prompt: String, options: Dictionary, agent_mode: bool) -> String:
	if harness == null:
		return "You are an AI assistant in Godot 4."
	var built: Dictionary = harness.build_system_prompt(user_prompt, options, agent_mode)
	var prompt: String = String(built.get("system_prompt", ""))
	var lang: String = _detect_language(user_prompt)
	var directive: String
	if lang == "es":
		directive = (
			"## Idioma\n"
			+ "CRÍTICO: Responde SIEMPRE en español en todos los pasos, sin importar el idioma "
			+ "de los resultados de las herramientas o del contexto de la escena."
		)
	else:
		directive = (
			"## Language\n"
			+ "CRITICAL: Always respond in English across all steps, regardless of the language "
			+ "of tool results or scene context."
		)
	return "%s\n\n%s" % [directive, prompt]

func _process_model_text(raw_text: String) -> Dictionary:
	if harness:
		return harness.parse_model_response(raw_text)
	return {"thinking": "", "content": raw_text, "raw": raw_text}

func _format_model_output(parsed: Dictionary) -> String:
	if harness:
		return harness.format_for_display(parsed)
	return String(parsed.get("content", ""))

func _max_response_retries() -> int:
	return clampi(int(config_manager.get_setting("max_response_retries", DEFAULT_RESPONSE_RETRIES)), 0, 5)

func _retry_nudge_message(reason: String = "empty") -> String:
	match reason:
		"thinking_only":
			return (
				"Your last reply contained only internal reasoning. "
				+ "Reply again with a visible answer for the user in the same language. "
				+ "Use <tool_call> blocks if you need editor actions."
			)
		"unusable":
			return (
				"Your last reply could not be parsed. "
				+ "Reply with plain text for the user, or valid <tool_call>{\"tool\":\"...\",\"params\":{...}}</tool_call> blocks."
			)
		_:
			return (
				"Your last reply was empty. "
				+ "Answer the user's latest request with a clear, non-empty message in the same language as the user."
			)

func _evaluate_response_text(text: String) -> Dictionary:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "reason": "empty"}
	var parsed: Dictionary = _process_model_text(trimmed)
	var content: String = String(parsed.get("content", trimmed)).strip_edges()
	if content.is_empty():
		content = trimmed
	if _pending_enable_tools and _response_has_tool_calls(content):
		return {"ok": true, "parsed": parsed, "content": content}
	return {"ok": true, "parsed": parsed, "content": content}

func _store_response_debug(body_text: String, extracted_text: String) -> void:
	_last_api_body_preview = body_text.substr(0, 1200)
	_last_extracted_text = extracted_text.substr(0, 1200)

func _failure_message_for_reason(reason: String) -> String:
	var base: String
	match reason:
		"empty":
			base = "El modelo devolvió una respuesta vacía"
		"unusable":
			base = "El modelo devolvió una respuesta que no se pudo interpretar"
		"thinking_only":
			base = "El modelo solo devolvió razonamiento interno sin respuesta visible"
		"invalid_json":
			base = "Respuesta JSON inválida del modelo"
		_:
			base = "Error al procesar la respuesta del modelo"
	if not _last_extracted_text.is_empty():
		base += "\n\n--- Respuesta cruda del modelo ---\n%s" % _last_extracted_text
	elif not _last_api_body_preview.is_empty():
		base += "\n\n--- Cuerpo API (preview) ---\n%s" % _last_api_body_preview
	push_warning("AI Assistant: model response rejected (%s). Extracted: %s" % [reason, _last_extracted_text])
	return base

func _try_retry_response(reason: String) -> bool:
	if _was_cancelled():
		return false
	var max_retries: int = _max_response_retries()
	if _response_retry_count >= max_retries:
		return false
	_response_retry_count += 1
	response_retry_attempt.emit(_response_retry_count, max_retries, reason)
	var retry_messages: Array = _build_retry_messages(reason)
	if _agent_active:
		agent_step_update.emit(
			_agent_step,
			_agent_max_steps,
			"Retry %d/%d" % [_response_retry_count, max_retries]
		)
		_dispatch_request(_agent_provider_id, _agent_provider_cfg, _agent_system_prompt, retry_messages)
	else:
		_dispatch_request(_active_provider_id, _active_provider_cfg, _pending_system_prompt, retry_messages)
	return true

func _build_retry_messages(reason: String = "empty") -> Array:
	var messages: Array = []
	if _agent_active:
		messages = _agent_messages.duplicate(true)
	else:
		messages = _pending_messages.duplicate(true)
		if messages.is_empty():
			messages = _build_conversation_messages(_active_user_prompt, _pending_options)
	messages.append({"role": "user", "content": _retry_nudge_message(reason)})
	return messages

func _estimate_ollama_num_ctx(messages: Array, max_tokens: int) -> int:
	# Rough token estimate (~4 chars/token) for prompt + room for the reply.
	# Estimación aproximada (~4 chars/token) para el prompt + espacio para la respuesta.
	var total_chars: int = 0
	for msg in messages:
		if msg is Dictionary:
			total_chars += String(msg.get("content", "")).length()
	var prompt_tokens: int = int(ceil(float(total_chars) / 3.5))
	# Reserve room for the reply but don't over-allocate (bigger num_ctx = slower).
	# Reservar espacio para la respuesta sin sobre-asignar (mayor num_ctx = más lento).
	var reply_room: int = mini(max_tokens, 1536)
	var needed: int = prompt_tokens + reply_room + 256
	# Round up to a sane window; cap by config to avoid slow loads / OOM.
	# Redondear a una ventana razonable; tope por config para evitar cargas lentas / OOM.
	var min_ctx: int = 4096
	var max_ctx: int = clampi(int(config_manager.get_setting("ollama_max_num_ctx", 32768)), 4096, 131072)
	var ctx: int = min_ctx
	while ctx < needed and ctx < max_ctx:
		ctx *= 2
	return clampi(ctx, min_ctx, max_ctx)

func _build_payload(provider_id: String, provider_cfg: Dictionary, system_prompt: String, messages: Array, options: Dictionary = {}) -> Dictionary:
	var temperature: float = float(config_manager.get_setting("temperature", 0.7))
	var max_tokens: int = int(config_manager.get_setting("max_tokens", 4096))
	var model_name: String = String(provider_cfg.get("model", "default"))
	
	match provider_id:
		"ollama":
			var enable_thinking: bool = bool(
				options.get("enable_thinking", config_manager.get_setting("enable_thinking", true))
			)
			var ollama_messages: Array = _prepend_system_message(system_prompt, messages)
			# Ollama defaults num_ctx to ~4096 and silently TRUNCATES longer prompts,
			# which makes models emit garbage like "<". Size the context to the prompt.
			# Ollama usa num_ctx ~4096 por defecto y TRUNCA prompts más largos en silencio,
			# lo que hace que el modelo escupa basura como "<". Ajustar al tamaño del prompt.
			var num_ctx: int = _estimate_ollama_num_ctx(ollama_messages, max_tokens)
			var payload: Dictionary = {
				"model": model_name,
				"messages": ollama_messages,
				"stream": false,
				"options": {
					"temperature": temperature,
					"num_predict": max_tokens,
					"num_ctx": num_ctx
				}
			}
			# Only send think to models that support it (qwen2.5-coder returns HTTP 400 otherwise).
			# Solo enviar think a modelos compatibles (qwen2.5-coder devuelve HTTP 400 si no).
			if _ollama_supports_thinking(model_name):
				payload["think"] = enable_thinking
			return payload
		"gemini":
			return _build_gemini_payload(model_name, provider_cfg, system_prompt, messages, max_tokens, temperature)
		"anthropic":
			return {
				"model": model_name,
				"max_tokens": max_tokens,
				"temperature": temperature,
				"system": system_prompt,
				"messages": messages
			}
		"cursor", "openai", "lmstudio":
			return {
				"model": model_name,
				"max_tokens": max_tokens,
				"temperature": temperature,
				"messages": _prepend_system_message(system_prompt, messages)
			}
		_:
			return {
				"model": model_name,
				"max_tokens": max_tokens,
				"temperature": temperature,
				"messages": _prepend_system_message(system_prompt, messages)
			}

func _build_gemini_payload(
	model_name: String,
	provider_cfg: Dictionary,
	system_prompt: String,
	messages: Array,
	max_tokens: int,
	temperature: float
) -> Dictionary:
	var contents: Array = []
	for message in messages:
		if message is Dictionary:
			var role: String = "user" if String(message.get("role", "user")) == "user" else "model"
			contents.append({
				"role": role,
				"parts": [{"text": String(message.get("content", ""))}]
			})
	return {
		"systemInstruction": {"parts": [{"text": system_prompt}]},
		"contents": contents,
		"generationConfig": {
			"temperature": temperature,
			"maxOutputTokens": max_tokens
		}
	}

func _prepend_system_message(system_prompt: String, messages: Array) -> Array:
	var payload_messages: Array = [{"role": "system", "content": system_prompt}]
	payload_messages.append_array(messages)
	return payload_messages

func _messages_to_prompt(system_prompt: String, messages: Array) -> String:
	var parts: PackedStringArray = [system_prompt, ""]
	for message in messages:
		if message is Dictionary:
			var role: String = String(message.get("role", "user"))
			var content: String = String(message.get("content", ""))
			parts.append("%s: %s" % [role.capitalize(), content])
			parts.append("")
	return "\n".join(parts)

func _build_headers(provider_id: String, provider_cfg: Dictionary) -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	match provider_id:
		"openai", "lmstudio", "cursor":
			var api_key: String = String(provider_cfg.get("api_key", ""))
			if not api_key.is_empty():
				headers.append("Authorization: Bearer %s" % api_key)
		"anthropic":
			var anthropic_key: String = String(provider_cfg.get("api_key", ""))
			headers.append("x-api-key: %s" % anthropic_key)
			headers.append("anthropic-version: 2023-06-01")
	return headers

func _build_url(provider_id: String, provider_cfg: Dictionary) -> String:
	var endpoint: String = String(provider_cfg.get("api_endpoint", "")).strip_edges().trim_suffix("/")
	match provider_id:
		"ollama":
			return "%s/api/chat" % endpoint
		"gemini":
			var gemini_base: String = endpoint.strip_edges().trim_suffix("/")
			var gemini_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
			return "%s/models/%s:generateContent?key=%s" % [gemini_base, String(provider_cfg.get("model", "gemini-2.0-flash")), gemini_key.uri_encode()]
		_:
			return endpoint

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http_in_flight = false
	var provider_id: String = _pending_provider_id
	_pending_provider_id = ""
	
	if _was_cancelled():
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		if _agent_active:
			_reset_agent_state()
		_handle_request_failure("Error de red HTTP (%s)" % result)
		return
	if response_code < 200 or response_code >= 300:
		if _agent_active:
			_reset_agent_state()
		_handle_request_failure("HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		return
	
	var body_text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null:
		_store_response_debug(body_text, "")
		if _try_retry_response("invalid_json"):
			return
		if _agent_active:
			_reset_agent_state()
		_handle_request_failure(_failure_message_for_reason("invalid_json"))
		return
	
	if parsed is Dictionary and parsed.has("error"):
		_store_response_debug(body_text, String(parsed.get("error", "")))
		_handle_request_failure("Ollama/API error: %s" % String(parsed.get("error", "unknown")))
		return
	
	var text: String = _extract_response_text(provider_id, parsed)
	_store_response_debug(body_text, text)
	if text.is_empty():
		if _try_retry_response("empty"):
			return
		if _agent_active:
			_reset_agent_state()
		_handle_request_failure(_failure_message_for_reason("empty"))
		return
	
	if _agent_active:
		_handle_agent_response(text)
	else:
		_handle_single_response(text)

func _handle_single_response(text: String) -> void:
	var evaluation: Dictionary = _evaluate_response_text(text)
	if not bool(evaluation.get("ok", false)):
		if _try_retry_response(String(evaluation.get("reason", "unusable"))):
			return
		_handle_request_failure(_failure_message_for_reason(String(evaluation.get("reason", "unusable"))))
		return
	var parsed: Dictionary = evaluation.get("parsed", _process_model_text(text))
	var content: String = String(evaluation.get("content", String(parsed.get("content", text))))
	var final_text: String = _format_model_output(parsed)
	if _pending_enable_tools and editor_tools and _response_has_tool_calls(content):
		var tool_results: Array = editor_tools.parse_and_execute_tool_calls(content)
		if not tool_results.is_empty():
			final_text += "\n\n---\nTool results:\n%s" % JSON.stringify(tool_results, "\t")
	_handle_request_success(true, final_text)

func _handle_agent_response(text: String) -> void:
	var evaluation: Dictionary = _evaluate_response_text(text)
	if not bool(evaluation.get("ok", false)):
		if _try_retry_response(String(evaluation.get("reason", "unusable"))):
			return
		_reset_agent_state()
		_handle_request_failure(_failure_message_for_reason(String(evaluation.get("reason", "unusable"))))
		return
	var parsed: Dictionary = evaluation.get("parsed", _process_model_text(text))
	var content: String = String(evaluation.get("content", String(parsed.get("content", text))))
	var display_parsed: Dictionary = _parsed_for_display(parsed, content)
	var formatted: String = _format_model_output(display_parsed)
	_agent_log.append("### Step %d\n%s" % [_agent_step, formatted])
	_agent_messages.append({"role": "assistant", "content": _content_for_agent_context(content, parsed)})
	agent_log_updated.emit(_compose_agent_output(), _agent_step, _agent_max_steps)
	
	var signature: String = _agent_response_signature(content, parsed)
	var repeated: bool = not signature.is_empty() and signature == _agent_last_response_signature
	_agent_last_response_signature = signature
	
	var tool_calls_detected: bool = _pending_enable_tools and editor_tools != null and editor_tools.has_tool_calls(content)
	var tool_results: Array = []
	if tool_calls_detected:
		tool_results = editor_tools.parse_and_execute_tool_calls(content)
	
	# Count tool calls that actually changed/inspected the scene without error.
	# Contar las tool calls que realmente se ejecutaron sin error.
	var ok_tool_count: int = 0
	for result in tool_results:
		if result is Dictionary and bool(result.get("result", {}).get("ok", false)):
			ok_tool_count += 1
	_agent_tools_executed += ok_tool_count
	
	if tool_calls_detected and tool_results.is_empty():
		_agent_log.append("### Tool parse warning (step %d)\nNo se pudieron ejecutar los bloques JSON detectados." % _agent_step)
	
	if not tool_results.is_empty():
		_agent_log.append("### Tool results (step %d)\n%s" % [_agent_step, JSON.stringify(tool_results, "\t")])
	
	# Track batches where every tool call failed (e.g. unknown tools). Stop the loop
	# after two such batches instead of burning all steps re-trying the same broken plan.
	# Seguir los lotes donde TODAS las tools fallaron (p. ej. tools inexistentes). Cortar
	# tras dos lotes así en vez de quemar todos los pasos repitiendo el mismo plan roto.
	var all_failed: bool = not tool_results.is_empty() and ok_tool_count == 0
	if ok_tool_count > 0:
		_agent_stall_count = 0
		_agent_failed_batches = 0
	elif all_failed:
		_agent_failed_batches += 1
	
	if _agent_failed_batches >= 2:
		_finish_agent_loop(
			false,
			_compose_agent_output()
			+ "\n\n---\nEl agente se detuvo: las tool calls fallaron repetidamente "
			+ "(revisa nombres de tools/rutas). No se completó la tarea."
		)
		return
	
	# 1) Tools executed (any) and steps remaining -> feed results back, continue.
	if not tool_results.is_empty() and _agent_step < _agent_max_steps:
		var followup: String = _build_tool_followup(tool_results)
		_agent_messages.append({"role": "user", "content": followup})
		_agent_step += 1
		agent_step_update.emit(_agent_step, _agent_max_steps, "Ejecutadas %d tool(s), continuando…" % tool_results.size())
		_send_agent_request()
		return
	
	if not tool_results.is_empty() and _agent_step >= _agent_max_steps:
		_finish_agent_loop(true, _compose_agent_output() + "\n\n---\nAgente detenido: máximo de pasos alcanzado.")
		return
	
	# 2) No tools this turn. If the model is just summarizing/inspecting but never
	#    actually performed the task, push it to ACT (limited nudges).
	# 2) Sin tools este turno. Si el modelo solo resume/inspecciona pero nunca
	#    ejecutó la tarea, empujarlo a ACTUAR (nudges limitados).
	var looks_done: bool = _looks_like_task_complete(_visible_response_text(content, parsed))
	if (looks_done or repeated) and _agent_tools_executed > 0:
		_finish_agent_loop(true, _compose_agent_output())
		return
	
	if repeated and _agent_tools_executed == 0:
		_agent_stall_count += 1
	if _agent_response_is_stalled(content, parsed):
		_agent_stall_count += 1
	else:
		_agent_stall_count = 0
	
	if _agent_stall_count >= 2:
		_finish_agent_loop(
			false,
			_compose_agent_output()
			+ "\n\n---\nEl agente se detuvo: el modelo no ejecutó ninguna acción tras varios intentos."
		)
		return
	
	if _agent_step >= _agent_max_steps:
		_finish_agent_loop(true, _compose_agent_output() + "\n\n---\nAgente detenido: máximo de pasos alcanzado.")
		return
	
	if _pending_enable_tools:
		var nudge: String
		if _agent_tools_executed == 0:
			_agent_act_nudges += 1
			if _agent_act_nudges > 3:
				_finish_agent_loop(
					false,
					_compose_agent_output()
					+ "\n\n---\nEl modelo no ejecutó ninguna acción pese a varias indicaciones. "
					+ "Prueba con un modelo más capaz para tools o reformula la petición."
				)
				return
			nudge = _act_now_nudge()
		else:
			nudge = (
				"No tool calls were detected in your last response. "
				+ "If the task requires more scene edits, emit <tool_call> blocks now. "
				+ "If the task is already complete, reply with a short final summary only."
			)
		_agent_messages.append({"role": "user", "content": nudge + _language_hint_suffix()})
		_agent_step += 1
		agent_step_update.emit(_agent_step, _agent_max_steps, "Esperando tools o resumen final…")
		_send_agent_request()
		return
	
	_finish_agent_loop(true, _compose_agent_output())

func _build_tool_followup(tool_results: Array) -> String:
	var parts: PackedStringArray = [
		"Tool execution results:",
		JSON.stringify(tool_results, "\t")
	]
	if editor_tools:
		var snapshot: Dictionary = editor_tools.execute_tool("get_scene_snapshot", {"max_depth": 6})
		parts.append("Current scene snapshot after tools:")
		parts.append(JSON.stringify(snapshot, "\t"))
	parts.append(
		"Continue the task. Call more tools if you need to verify or fix the scene. "
		+ "If the task is complete, reply with a final summary only and do NOT include <tool_call> blocks."
		+ _language_hint_suffix()
	)
	return "\n\n".join(parts)

func _compose_agent_output() -> String:
	return "\n\n".join(_agent_log)

func _finish_agent_loop(success: bool, text: String) -> void:
	_reset_agent_state()
	_handle_request_success(success, text)

func _reset_agent_state() -> void:
	_agent_active = false
	_agent_step = 0
	_agent_stall_count = 0
	_agent_last_response_signature = ""
	_agent_failed_batches = 0
	_agent_tools_executed = 0
	_agent_act_nudges = 0
	_agent_messages.clear()
	_agent_log.clear()
	_agent_provider_id = ""
	_agent_provider_cfg = {}
	_agent_system_prompt = ""
	if cursor_cloud:
		cursor_cloud.reset_session()

func _response_has_tool_calls(text: String) -> bool:
	if editor_tools and editor_tools.has_method("has_tool_calls"):
		return editor_tools.has_tool_calls(text)
	if text.contains("<tool_call>"):
		return true
	var regex := RegEx.new()
	regex.compile("<tool_call>\\s*\\{")
	if regex.search(text) != null:
		return true
	regex.compile("\\{\\s*\"tool\"\\s*:\\s*\"[^\"]+\"\\s*,\\s*\"params\"\\s*:")
	return regex.search(text) != null

func _ollama_supports_thinking(model_name: String) -> bool:
	var model_lower: String = model_name.to_lower()
	var prefixes: PackedStringArray = [
		"gemma4", "gemma3", "qwen3", "qwq", "deepseek", "gpt-oss", "magistral"
	]
	for prefix in prefixes:
		if model_lower.contains(prefix):
			return true
	return false

func _is_fragment_content(text: String) -> bool:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return false
	if trimmed.length() <= 4 and trimmed.begins_with("<"):
		return true
	return trimmed in ["<", ">", "</", "<t", "<to", "<tool"]

func _visible_response_text(content: String, parsed: Dictionary) -> String:
	var body: String = String(parsed.get("content", content)).strip_edges()
	var thinking: String = String(parsed.get("thinking", "")).strip_edges()
	if _is_fragment_content(body) and not thinking.is_empty():
		return thinking
	if body.is_empty() and not thinking.is_empty():
		return thinking
	return body if not body.is_empty() else content.strip_edges()

func _parsed_for_display(parsed: Dictionary, content: String) -> Dictionary:
	var body: String = String(parsed.get("content", content)).strip_edges()
	var thinking: String = String(parsed.get("thinking", "")).strip_edges()
	if _is_fragment_content(body) and not thinking.is_empty():
		return {"thinking": thinking, "content": "", "raw": parsed.get("raw", content)}
	return parsed

func _content_for_agent_context(content: String, parsed: Dictionary) -> String:
	var visible: String = _visible_response_text(content, parsed)
	return visible if not visible.is_empty() else content.strip_edges()

func _agent_response_signature(content: String, parsed: Dictionary) -> String:
	# Normalize so near-identical plans (e.g. only markdown bold differs) collapse to
	# the same signature and get caught as repetition.
	# Normalizar para que planes casi idénticos (p. ej. solo difiere el markdown) colapsen
	# a la misma firma y se detecten como repetición.
	var text: String = _visible_response_text(content, parsed).to_lower()
	var regex := RegEx.new()
	regex.compile("[*`#\\s]+")
	text = regex.sub(text, " ", true)
	return text.strip_edges().substr(0, 200)

func _looks_like_task_complete(text: String) -> bool:
	var lower: String = text.to_lower()
	var markers: PackedStringArray = [
		"resumen final",
		"final summary",
		"task is complete",
		"task complete",
		"¿necesitas ayuda",
		"need any additional",
		"need further help",
		"need additional help",
		"anything else",
		"algo más",
	]
	for marker in markers:
		if lower.contains(marker):
			return true
	return false

func _language_hint_suffix() -> String:
	if _active_user_language == "es":
		return " IMPORTANTE: Responde SIEMPRE en español."
	return " IMPORTANT: Always reply in the user's language (%s)." % _active_user_language

func _act_now_nudge() -> String:
	# Force the model to perform real edits instead of only inspecting/summarizing.
	# Forzar al modelo a hacer cambios reales en lugar de solo inspeccionar/resumir.
	if _active_user_language == "es":
		return (
			"Todavía NO has hecho ningún cambio en la escena. No te limites a inspeccionar ni a resumir. "
			+ "Ejecuta AHORA las tool calls necesarias para completar la tarea del usuario "
			+ "(por ejemplo instance_scene para colocar el .tscn, o add_node / create_box_mesh). "
			+ "Usa exactamente el formato <tool_call>{\"tool\":\"...\",\"params\":{...}}</tool_call>."
		)
	return (
		"You have NOT made any scene changes yet. Do not just inspect or summarize. "
		+ "Execute the tool calls needed to complete the user's task NOW "
		+ "(e.g. instance_scene to place the .tscn, or add_node / create_box_mesh). "
		+ "Use exactly the format <tool_call>{\"tool\":\"...\",\"params\":{...}}</tool_call>."
	)

func _detect_language(text: String) -> String:
	var lower: String = text.to_lower()
	if lower.is_empty():
		return "es"
	# Spanish accents / common words as a quick heuristic.
	# Acentos en español / palabras comunes como heurística rápida.
	for marker in ["á", "é", "í", "ó", "ú", "ñ", "¿", "¡"]:
		if lower.contains(marker):
			return "es"
	var es_words: PackedStringArray = [
		" que ", " para ", " mas ", " más ", " quiero ", " necesito ", " con ",
		" pisos ", " paredes ", " escena ", " mapa ", " mundo ", " por favor ",
		" hola ", " crear ", " colocar ", " el ", " la ", " los ", " las ", " en mi ",
	]
	var padded: String = " %s " % lower
	for word in es_words:
		if padded.contains(word):
			return "es"
	return "en"

func _agent_response_is_final(content: String, parsed: Dictionary) -> bool:
	var visible: String = _visible_response_text(content, parsed)
	if _looks_like_task_complete(visible):
		return true
	if _response_has_tool_calls(content):
		return false
	return visible.length() >= 80

func _agent_response_is_stalled(content: String, parsed: Dictionary) -> bool:
	var visible: String = _visible_response_text(content, parsed)
	if visible.is_empty():
		return true
	if visible.length() <= 4 and visible.begins_with("<"):
		return true
	return false

func _ollama_content_to_string(content: Variant) -> String:
	if content == null:
		return ""
	if content is String:
		return content.strip_edges()
	if content is Array:
		var parts: PackedStringArray = []
		for item in content:
			if item is Dictionary:
				var text: String = String(item.get("text", item.get("content", ""))).strip_edges()
				if not text.is_empty():
					parts.append(text)
			elif item is String:
				var chunk: String = String(item).strip_edges()
				if not chunk.is_empty():
					parts.append(chunk)
		return "\n".join(parts)
	return String(content).strip_edges()

func _ollama_tool_call_to_tag(entry: Dictionary) -> String:
	var func_data: Variant = entry.get("function", entry)
	if not func_data is Dictionary:
		return ""
	var tool_name: String = String(func_data.get("name", ""))
	if tool_name.is_empty():
		return ""
	var args: Variant = func_data.get("arguments", {})
	if args is String:
		var parsed_args: Variant = JSON.parse_string(String(args))
		args = parsed_args if parsed_args is Dictionary else {}
	if not args is Dictionary:
		args = {}
	return "<tool_call>{\"tool\":\"%s\",\"params\":%s}</tool_call>" % [
		tool_name,
		JSON.stringify(args)
	]

func _ollama_message_to_text(message: Dictionary) -> String:
	var parts: PackedStringArray = []
	var thinking: String = _ollama_content_to_string(message.get("thinking", ""))
	var content: String = _ollama_content_to_string(message.get("content", ""))
	# Gemma4 + think:true often leaves content empty; promote thinking as visible text.
	# Gemma4 con think:true suele dejar content vacío; usar thinking como texto visible.
	if _is_fragment_content(content) and not thinking.is_empty():
		content = ""
	if not content.is_empty() and not thinking.is_empty():
		parts.append("<thinking>\n%s\n</thinking>" % thinking)
		parts.append(content)
	elif not content.is_empty():
		parts.append(content)
	elif not thinking.is_empty():
		parts.append(thinking)
	var tool_calls: Variant = message.get("tool_calls", [])
	if tool_calls is Array:
		for entry in tool_calls:
			if entry is Dictionary:
				var tag: String = _ollama_tool_call_to_tag(entry)
				if not tag.is_empty():
					parts.append(tag)
	return "\n\n".join(parts)

func _extract_response_text(provider_id: String, parsed: Variant) -> String:
	if not parsed is Dictionary:
		return str(parsed)
	
	match provider_id:
		"ollama":
			if parsed.has("message") and parsed.message is Dictionary:
				var text: String = _ollama_message_to_text(parsed.message)
				if not text.is_empty():
					return text
			var legacy: String = String(parsed.get("response", "")).strip_edges()
			if not legacy.is_empty():
				return legacy
			return _ollama_content_to_string(parsed.get("content", ""))
		"gemini":
			var candidates: Array = parsed.get("candidates", [])
			if candidates.is_empty():
				return ""
			var first: Variant = candidates[0]
			if first is Dictionary and first.has("content"):
				var content: Dictionary = first.content
				var parts: Array = content.get("parts", [])
				if not parts.is_empty() and parts[0] is Dictionary:
					return String(parts[0].get("text", ""))
			return ""
		"anthropic":
			var content: Array = parsed.get("content", [])
			var parts: PackedStringArray = []
			for block in content:
				if block is Dictionary and block.get("type", "") == "text":
					parts.append(String(block.get("text", "")))
			return "\n".join(parts)
		_:
			var choices: Array = parsed.get("choices", [])
			if choices.is_empty():
				return ""
			var first: Variant = choices[0]
			if first is Dictionary:
				if first.has("message"):
					return String(first.message.get("content", ""))
				return String(first.get("text", ""))
			return ""
