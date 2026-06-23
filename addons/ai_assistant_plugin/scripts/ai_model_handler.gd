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
signal agent_paused_for_user(question: String)
signal response_retry_attempt(attempt: int, max_attempts: int, reason: String)

const MAX_CONVERSATION_MESSAGES := 24
const DEFAULT_RESPONSE_RETRIES := 2
const NATIVE_TOOL_PROVIDERS: Array[String] = [
	"openai", "openrouter", "lmstudio", "kimi", "ollama", "minimax",
]
const ModelCapabilities := preload("res://addons/ai_assistant_plugin/scripts/model_capabilities.gd")
const ComposerAttachments := preload("res://addons/ai_assistant_plugin/scripts/composer_attachments.gd")
const ThinkingTags := preload("res://addons/ai_assistant_plugin/scripts/thinking_tags.gd")

var config_manager: RefCounted = null
var project_context: RefCounted = null
var editor_tools: RefCounted = null
var skills_manager: RefCounted = null
var project_index: RefCounted = null
var harness: RefCounted = null
var local_fallback: RefCounted = null

var http_request: HTTPRequest = null
var cursor_cloud: RefCounted = null
var _pending_provider_id: String = ""
var _pending_enable_tools: bool = false
var _pending_options: Dictionary = {}
var _using_cursor_cloud: bool = false

var _agent_active: bool = false
var _agent_step: int = 0
var _agent_max_steps: int = 24
var _agent_paused: bool = false
var _agent_pause_question: String = ""
var _agent_messages: Array = []
var _agent_system_prompt: String = ""
var _agent_provider_id: String = ""
var _agent_provider_cfg: Dictionary = {}
var _agent_log: PackedStringArray = []
var _agent_stall_count: int = 0
var _agent_last_response_signature: String = ""
var _agent_tools_executed: int = 0
var _agent_act_nudges: int = 0
var _agent_model_tool_batches: int = 0
var _agent_failed_batches: int = 0
var _agent_empty_tag_streak: int = 0
var _agent_verify_streak: int = 0
var _agent_had_mutation: bool = false
var _agent_unparsed_tool_steps: int = 0
var _agent_script_verify_clean: bool = false
var _agent_runtime_checked: bool = false
var _agent_code_only: bool = false
var _agent_read_only_streak: int = 0
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
	skills: RefCounted,
	index_svc: RefCounted = null
) -> void:
	config_manager = config_mgr
	project_context = context_builder
	editor_tools = tools
	skills_manager = skills
	project_index = index_svc
	
	harness = preload("res://addons/ai_assistant_plugin/scripts/harness.gd").new()
	harness.setup(config_mgr, context_builder, tools, skills)
	local_fallback = preload("res://addons/ai_assistant_plugin/scripts/agent_local_fallback.gd").new()
	local_fallback.setup(tools)
	
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

func is_agent_paused() -> bool:
	return _agent_paused

func get_agent_pause_question() -> String:
	return _agent_pause_question

func get_queue_size() -> int:
	return _request_queue.size()

func cancel_current_request() -> void:
	_cancel_requested = true
	_response_retry_count = 999
	_http_in_flight = false
	# Do NOT clear _request_queue — Stop cancels only the active run; queued prompts stay.
	# NO vaciar _request_queue — Stop solo cancela la petición activa; la cola se conserva.
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
	if _agent_paused:
		_resume_agent_loop(user_prompt, provider_id, options)
		return
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
	
	if provider_id in ["openrouter", "kimi", "minimax"] and String(provider_cfg.get("api_key", "")).strip_edges().is_empty():
		_finish_request_cycle()
		query_failed.emit("%s requiere API key" % config_manager.get_provider_label(provider_id))
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
		config_manager.get_setting("agent_max_steps", 24)
	))
	_agent_max_steps = maxi(_agent_max_steps, 1)
	_agent_provider_id = provider_id
	_agent_provider_cfg = provider_cfg
	_agent_log.clear()
	_agent_stall_count = 0
	_agent_last_response_signature = ""
	_agent_tools_executed = 0
	_agent_act_nudges = 0
	_agent_model_tool_batches = 0
	_agent_failed_batches = 0
	_agent_empty_tag_streak = 0
	_agent_verify_streak = 0
	_agent_had_mutation = false
	_agent_unparsed_tool_steps = 0
	_agent_script_verify_clean = false
	_agent_runtime_checked = false
	_agent_code_only = _user_wants_code_only(user_prompt)
	_agent_read_only_streak = 0
	_active_user_language = _detect_language(user_prompt)
	_agent_system_prompt = _build_system_prompt(user_prompt, options, true)
	if _agent_code_only:
		_agent_system_prompt += (
			"\n\n## Code-only request\n"
			+ "The user wants GDScript code to paste manually — do NOT call create_script or other write tools. "
			+ "Reply with a complete ```gdscript code block using exact node paths from @ mentions / attachments. "
			+ "At most ONE inspect tool if a path is truly unknown, then answer with code and short steps."
		)
	if editor_tools != null and editor_tools.has_method("set_conversation_context"):
		editor_tools.set_conversation_context(options.get("conversation_messages", []))
	_agent_messages = _build_conversation_messages(user_prompt, options)
	var bootstrap_context: String = _bootstrap_agent_context(user_prompt)
	if not bootstrap_context.is_empty():
		var bootstrap_mode: String = _bootstrap_context_mode()
		var bootstrap_label: String = (
			"Contexto mínimo — usa tools (search_project_index, get_scene_snapshot, etc.) según necesites."
			if bootstrap_mode == "minimal"
			else "Contexto precargado (índice del proyecto + perfil espacial si aplica)."
		)
		_agent_log.append("### Bootstrap\n%s" % bootstrap_label)
		_agent_messages.append({
			"role": "user",
			"content": bootstrap_context + _language_hint_suffix(),
		})
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
	if messages.is_empty() or _message_plain_text(messages[-1]) != user_prompt:
		messages.append(_make_user_message_dict(user_prompt, options))
	elif not options.get("message_attachments", []).is_empty():
		messages[-1] = _make_user_message_dict(user_prompt, options)
	return messages

func _make_user_message_dict(user_prompt: String, options: Dictionary) -> Dictionary:
	var msg: Dictionary = {"role": "user", "content": user_prompt}
	var attachments: Array = options.get("message_attachments", [])
	if attachments.is_empty():
		return msg
	if bool(options.get("enable_vision", false)):
		var images: Array = ComposerAttachments.get_image_attachments(attachments)
		if not images.is_empty():
			msg["images"] = images
	return msg

func _message_plain_text(message: Dictionary) -> String:
	var content: Variant = message.get("content", "")
	if content is String:
		return content
	if content is Array:
		for part in content:
			if part is Dictionary and String(part.get("type", "")) == "text":
				return String(part.get("text", ""))
	return String(content)

func _sanitize_tool_calls_for_api(tool_calls: Array) -> Array:
	# MiniMax error 2013: index must be int64; function.arguments must be a JSON string.
	# MiniMax error 2013: index int64; function.arguments debe ser string JSON.
	var out: Array = []
	for call in tool_calls:
		if not call is Dictionary:
			continue
		var copy: Dictionary = call.duplicate(true)
		if copy.has("index"):
			copy["index"] = int(copy["index"])
		var func_data: Variant = copy.get("function", null)
		if func_data is Dictionary:
			var fn: Dictionary = func_data.duplicate(true)
			fn["arguments"] = _tool_arguments_to_json_string(fn.get("arguments", {}))
			copy["function"] = fn
		out.append(copy)
	return out

func _tool_arguments_to_json_string(args_raw: Variant) -> String:
	if args_raw is Dictionary:
		return JSON.stringify(args_raw)
	var raw: String = String(args_raw).strip_edges()
	if raw.is_empty() or raw == "null":
		return "{}"
	if raw.begins_with("{"):
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return JSON.stringify(parsed)
	return "{}"

func _sanitize_minimax_value(value: Variant) -> Variant:
	# MiniMax strictly rejects floats where int64 is expected (index, token limits, etc.).
	# MiniMax rechaza floats donde espera int64 (index, límites de tokens, etc.).
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value.keys():
			var k: String = String(key)
			var v: Variant = value[key]
			if k in ["index", "max_tokens", "max_completion_tokens", "created"]:
				if v is float or v is int:
					out[k] = int(v)
				else:
					out[k] = _sanitize_minimax_value(v)
			else:
				out[k] = _sanitize_minimax_value(v)
		return out
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(_sanitize_minimax_value(item))
		return arr
	return value

func _extract_openai_choice_message(api_parsed: Dictionary) -> Dictionary:
	var choices: Array = api_parsed.get("choices", [])
	if choices.is_empty() or not choices[0] is Dictionary:
		return {}
	var message: Variant = choices[0].get("message", {})
	return message if message is Dictionary else {}

func _build_native_assistant_history_message(
	provider_id: String,
	api_parsed: Dictionary,
	content: String,
	parsed: Dictionary,
	native_calls: Array
) -> Dictionary:
	# MiniMax-M3: keep full assistant message (tool_calls + reasoning_details) for interleaved thinking.
	# MiniMax-M3: conservar el mensaje assistant completo (tool_calls + reasoning_details).
	if provider_id == "minimax" and not api_parsed.is_empty():
		var api_message: Dictionary = _extract_openai_choice_message(api_parsed)
		if not api_message.is_empty() and api_message.has("tool_calls"):
			var history: Dictionary = api_message.duplicate(true)
			history["role"] = "assistant"
			var raw_calls: Variant = history.get("tool_calls", [])
			if raw_calls is Array:
				history["tool_calls"] = _sanitize_tool_calls_for_api(raw_calls)
			return _sanitize_minimax_value(history)
	var visible: String = _content_for_agent_context(content, parsed)
	var built: Dictionary = {
		"role": "assistant",
		"content": visible if not visible.strip_edges().is_empty() else null,
		"tool_calls": _sanitize_tool_calls_for_api(native_calls),
	}
	if provider_id == "minimax":
		return _sanitize_minimax_value(built)
	return built

func _json_stringify_api_payload(payload: Dictionary, provider_id: String) -> String:
	if provider_id == "minimax":
		return JSON.stringify(_sanitize_minimax_value(payload))
	return JSON.stringify(payload)

func _transform_messages_for_provider(provider_id: String, messages: Array) -> Array:
	var out: Array = []
	for message in messages:
		if not message is Dictionary:
			continue
		var role: String = String(message.get("role", "user"))
		if role == "tool":
			var tool_call_id: String = String(message.get("tool_call_id", "")).strip_edges()
			if tool_call_id.is_empty():
				continue
			var tool_content: String = String(message.get("content", "")).strip_edges()
			if tool_content.is_empty():
				tool_content = "{}"
			out.append({
				"role": "tool",
				"tool_call_id": tool_call_id,
				"content": tool_content,
			})
			continue
		if role == "assistant" and (message.has("tool_calls") or message.has("reasoning_details")):
			var assistant_msg: Dictionary = message.duplicate(true)
			if not assistant_msg.has("content"):
				assistant_msg["content"] = null
			var raw_calls: Variant = assistant_msg.get("tool_calls", [])
			if raw_calls is Array:
				assistant_msg["tool_calls"] = _sanitize_tool_calls_for_api(raw_calls)
			if provider_id == "minimax":
				assistant_msg = _sanitize_minimax_value(assistant_msg)
			out.append(assistant_msg)
			continue
		var content: Variant = message.get("content", "")
		var images: Array = message.get("images", [])
		if role != "user" or images.is_empty():
			out.append({"role": role, "content": _message_plain_text(message) if content is Array else String(content)})
			continue
		match provider_id:
			"ollama":
				var ollama_msg: Dictionary = {
					"role": "user",
					"content": String(content),
					"images": _image_base64_list(images),
				}
				out.append(ollama_msg)
			"anthropic":
				out.append({"role": role, "content": _anthropic_multimodal_parts(String(content), images)})
			"gemini":
				out.append({"role": role, "content": String(content), "images": images})
			_:
				out.append({"role": role, "content": _openai_multimodal_parts(String(content), images)})
	return out

func _image_base64_list(images: Array) -> Array:
	var encoded: Array = []
	for item in images:
		if item is Dictionary:
			var b64: String = String(item.get("base64", ""))
			if not b64.is_empty():
				encoded.append(b64)
	return encoded

func _openai_multimodal_parts(text: String, images: Array) -> Array:
	var parts: Array = [{"type": "text", "text": text}]
	for item in images:
		if not item is Dictionary:
			continue
		var b64: String = String(item.get("base64", ""))
		var mime: String = String(item.get("mime", "image/png"))
		if b64.is_empty():
			continue
		parts.append({
			"type": "image_url",
			"image_url": {"url": "data:%s;base64,%s" % [mime, b64]},
		})
	return parts

func _anthropic_multimodal_parts(text: String, images: Array) -> Array:
	var parts: Array = [{"type": "text", "text": text}]
	for item in images:
		if not item is Dictionary:
			continue
		var b64: String = String(item.get("base64", ""))
		var mime: String = String(item.get("mime", "image/png"))
		if b64.is_empty():
			continue
		parts.append({
			"type": "image",
			"source": {"type": "base64", "media_type": mime, "data": b64},
		})
	return parts

func _sanitize_message_for_context(text: String) -> String:
	var cleaned: String = ThinkingTags.strip_all_thinking(text)
	var regex := RegEx.new()
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
	var result: int = http_request.request(url, headers, HTTPClient.METHOD_POST, _json_stringify_api_payload(payload, provider_id))
	if result != OK:
		_http_in_flight = false
		_pending_provider_id = ""
		if _agent_active:
			_reset_agent_state()
		_handle_request_failure("No se pudo iniciar la petición HTTP")

func _send_cursor_cloud_request(provider_cfg: Dictionary, system_prompt: String, messages: Array) -> void:
	var api_key: String = String(provider_cfg.get("api_key", ""))
	var model_name: String = String(provider_cfg.get("model", "composer-2.5"))
	
	query_started.emit("cursor")
	if _agent_active and cursor_cloud.has_active_agent():
		# Follow-up: only the delta — Cursor keeps session state; resending the full
		# system prompt + history burns minutes and cloud tokens per step.
		# Follow-up: solo el delta — Cursor conserva la sesión; reenviar todo quema minutos y tokens.
		var delta_text: String = _cursor_agent_follow_up_prompt(messages)
		cursor_cloud.follow_up_run(api_key, delta_text)
	else:
		var prompt_text: String = _messages_to_prompt(system_prompt, messages)
		cursor_cloud.reset_session()
		cursor_cloud.create_agent_and_run(api_key, model_name, prompt_text)

func _cursor_agent_follow_up_prompt(messages: Array) -> String:
	if messages.is_empty():
		return ""
	var parts: PackedStringArray = []
	if messages.size() >= 2:
		var prev: Dictionary = messages[-2]
		if String(prev.get("role", "")) == "assistant":
			var assistant_text: String = String(prev.get("content", "")).strip_edges()
			if assistant_text.length() > 1800:
				assistant_text = assistant_text.substr(0, 1800) + "\n...(truncated / truncado)"
			if not assistant_text.is_empty():
				parts.append("Your previous step / paso anterior:\n%s" % assistant_text)
	var last: Dictionary = messages[-1]
	var role: String = String(last.get("role", "user")).capitalize()
	var content: String = String(last.get("content", "")).strip_edges()
	parts.append("%s: %s" % [role, content])
	return "\n".join(parts)

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
	if _pending_enable_tools and _response_has_tool_calls(_tool_source_text(parsed, content, trimmed)):
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

func _should_use_native_tools(provider_id: String) -> bool:
	if not _pending_enable_tools or editor_tools == null:
		return false
	if not bool(config_manager.get_setting("enable_native_tool_calling", true)):
		return false
	if provider_id not in NATIVE_TOOL_PROVIDERS:
		return false
	if _is_cursor_cloud_mode(provider_id, _agent_provider_cfg if _agent_active else _active_provider_cfg):
		return false
	return true

func _append_native_tools_to_payload(payload: Dictionary, provider_id: String) -> void:
	if not _should_use_native_tools(provider_id):
		return
	if not editor_tools.has_method("get_native_tool_schemas"):
		return
	var schemas: Array = editor_tools.get_native_tool_schemas()
	if schemas.is_empty():
		return
	payload["tools"] = schemas
	payload["tool_choice"] = "auto"

func _extract_native_tool_calls(provider_id: String, parsed: Dictionary) -> Array:
	if parsed.is_empty():
		return []
	match provider_id:
		"ollama":
			if parsed.has("message") and parsed.message is Dictionary:
				var tool_calls: Variant = parsed.message.get("tool_calls", [])
				return tool_calls if tool_calls is Array else []
			return []
		_:
			var choices: Array = parsed.get("choices", [])
			if choices.is_empty():
				return []
			var first: Variant = choices[0]
			if not first is Dictionary:
				return []
			var message: Variant = first.get("message", {})
			if not message is Dictionary:
				return []
			var tool_calls_openai: Variant = message.get("tool_calls", [])
			return tool_calls_openai if tool_calls_openai is Array else []

func _build_payload(provider_id: String, provider_cfg: Dictionary, system_prompt: String, messages: Array, options: Dictionary = {}) -> Dictionary:
	var temperature: float = float(config_manager.get_setting("temperature", 0.7))
	var max_tokens: int = int(config_manager.get_setting("max_tokens", 4096))
	var model_name: String = String(provider_cfg.get("model", "default"))
	var api_messages: Array = _transform_messages_for_provider(provider_id, messages)
	var payload: Dictionary = {}
	
	match provider_id:
		"ollama":
			var enable_thinking: bool = bool(
				options.get("enable_thinking", config_manager.get_setting("enable_thinking", true))
			)
			var ollama_messages: Array = _prepend_system_message(system_prompt, api_messages)
			# Ollama defaults num_ctx to ~4096 and silently TRUNCATES longer prompts,
			# which makes models emit garbage like "<". Size the context to the prompt.
			# Ollama usa num_ctx ~4096 por defecto y TRUNCA prompts más largos en silencio,
			# lo que hace que el modelo escupa basura como "<". Ajustar al tamaño del prompt.
			var num_ctx: int = _estimate_ollama_num_ctx(ollama_messages, max_tokens)
			payload = {
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
			if ModelCapabilities.supports_thinking(provider_id, model_name):
				payload["think"] = enable_thinking
		"gemini":
			return _build_gemini_payload(model_name, provider_cfg, system_prompt, api_messages, max_tokens, temperature)
		"anthropic":
			return {
				"model": model_name,
				"max_tokens": max_tokens,
				"temperature": temperature,
				"system": system_prompt,
				"messages": api_messages
			}
		"cursor", "openai", "lmstudio", "openrouter", "kimi":
			payload = {
				"model": model_name,
				"max_tokens": max_tokens,
				"temperature": temperature,
				"messages": _prepend_system_message(system_prompt, api_messages)
			}
		"minimax":
			payload = {
				"model": model_name,
				"max_tokens": max_tokens,
				"temperature": temperature,
				"messages": _prepend_system_message(system_prompt, api_messages),
				"reasoning_split": true,
			}
		_:
			payload = {
				"model": model_name,
				"max_tokens": max_tokens,
				"temperature": temperature,
				"messages": _prepend_system_message(system_prompt, api_messages)
			}
	
	_append_native_tools_to_payload(payload, provider_id)
	return payload

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
			var parts: Array = []
			var text: String = String(message.get("content", ""))
			if not text.is_empty():
				parts.append({"text": text})
			var images: Array = message.get("images", [])
			for item in images:
				if item is Dictionary:
					var b64: String = String(item.get("base64", ""))
					var mime: String = String(item.get("mime", "image/png"))
					if not b64.is_empty():
						parts.append({"inlineData": {"mimeType": mime, "data": b64}})
			if parts.is_empty():
				parts.append({"text": text})
			contents.append({"role": role, "parts": parts})
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
		"openrouter":
			var openrouter_key: String = String(provider_cfg.get("api_key", "")).strip_edges()
			if not openrouter_key.is_empty():
				headers.append("Authorization: Bearer %s" % openrouter_key)
			headers.append("HTTP-Referer: https://github.com/sancheznot/Godot-AI-Assistant")
			headers.append("X-OpenRouter-Title: Golem-AI")
		"openai", "lmstudio", "cursor", "kimi", "minimax":
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
	var api_dict: Dictionary = parsed if parsed is Dictionary else {}
	var native_calls: Array = _extract_native_tool_calls(provider_id, api_dict)
	_store_response_debug(body_text, text)
	if text.is_empty() and native_calls.is_empty():
		if _try_retry_response("empty"):
			return
		if _agent_active:
			_reset_agent_state()
		_handle_request_failure(_failure_message_for_reason("empty"))
		return
	
	if _agent_active:
		_handle_agent_response(text, api_dict, provider_id, native_calls)
	else:
		_handle_single_response(text, api_dict, provider_id, native_calls)

func _handle_single_response(text: String, api_parsed: Dictionary = {}, provider_id: String = "", native_calls: Array = []) -> void:
	var evaluation: Dictionary = _evaluate_response_text(text)
	if not bool(evaluation.get("ok", false)):
		if _try_retry_response(String(evaluation.get("reason", "unusable"))):
			return
		_handle_request_failure(_failure_message_for_reason(String(evaluation.get("reason", "unusable"))))
		return
	var parsed: Dictionary = evaluation.get("parsed", _process_model_text(text))
	var content: String = String(evaluation.get("content", String(parsed.get("content", text))))
	var final_text: String = _format_model_output(parsed)
	var tool_results: Array = []
	if _pending_enable_tools and editor_tools:
		if not native_calls.is_empty() and editor_tools.has_method("execute_native_tool_calls"):
			tool_results = editor_tools.execute_native_tool_calls(native_calls)
		else:
			var tool_source: String = _tool_source_text(parsed, content, text)
			if _response_has_tool_calls(tool_source):
				var tool_context: String = "%s\n%s" % [_active_user_prompt, tool_source]
				tool_results = editor_tools.parse_and_execute_tool_calls(tool_context)
	if not tool_results.is_empty():
		final_text += "\n\n### Tool results\n%s" % JSON.stringify(tool_results, "\t")
	_handle_request_success(true, final_text)

func _handle_agent_response(
	text: String,
	api_parsed: Dictionary = {},
	provider_id: String = "",
	native_calls: Array = []
) -> void:
	var evaluation: Dictionary = _evaluate_response_text(text)
	if not bool(evaluation.get("ok", false)):
		if _try_retry_response(String(evaluation.get("reason", "unusable"))):
			return
		_reset_agent_state()
		_handle_request_failure(_failure_message_for_reason(String(evaluation.get("reason", "unusable"))))
		return
	var parsed: Dictionary = evaluation.get("parsed", _process_model_text(text))
	var content: String = String(evaluation.get("content", String(parsed.get("content", text))))
	var tool_source: String = _tool_source_text(parsed, content, text)
	var display_parsed: Dictionary = _parsed_for_display(parsed, content)
	var formatted: String = _format_model_output(display_parsed)
	if harness != null and harness.has_method("sanitize_display_text"):
		formatted = harness.sanitize_display_text(formatted)
	_agent_log.append("### Step %d\n%s" % [_agent_step, formatted])
	
	var used_native_tools: bool = (
		_pending_enable_tools
		and editor_tools != null
		and not native_calls.is_empty()
		and editor_tools.has_method("execute_native_tool_calls")
	)
	if used_native_tools:
		_agent_messages.append(
			_build_native_assistant_history_message(
				provider_id if not provider_id.is_empty() else _agent_provider_id,
				api_parsed,
				content,
				parsed,
				native_calls
			)
		)
	else:
		_agent_messages.append({"role": "assistant", "content": _content_for_agent_context(content, parsed)})
	agent_log_updated.emit(_compose_agent_output(), _agent_step, _agent_max_steps)
	
	var signature: String = _agent_response_signature(content, parsed)
	var repeated: bool = not signature.is_empty() and signature == _agent_last_response_signature
	_agent_last_response_signature = signature
	
	var tool_calls_detected: bool = (
		_pending_enable_tools
		and editor_tools != null
		and (
			used_native_tools
			or editor_tools.has_tool_calls(tool_source)
		)
	)
	var empty_tool_tags: bool = (
		not used_native_tools
		and editor_tools != null
		and editor_tools.has_method("has_empty_tool_call_tags")
		and editor_tools.has_empty_tool_call_tags(tool_source)
	)
	var tool_results: Array = []
	if tool_calls_detected:
		if used_native_tools:
			tool_results = editor_tools.execute_native_tool_calls(native_calls)
		else:
			var tool_context: String = "%s\n%s" % [_active_user_prompt, tool_source]
			tool_results = editor_tools.parse_and_execute_tool_calls(tool_context)
	
	if tool_results.is_empty() and local_fallback != null:
		var fallback_text: String = "%s\n%s" % [tool_source, content]
		var should_fallback: bool = (
			tool_calls_detected
			or _response_has_code_block(content)
			or _agent_unparsed_tool_steps >= 1
			or editor_tools.has_xml_tool_markup(fallback_text)
		)
		if should_fallback:
			var fallback_results: Array = local_fallback.try_execute(
				_active_user_prompt,
				fallback_text,
				_agent_unparsed_tool_steps
			)
			if not fallback_results.is_empty():
				tool_results = fallback_results
				_agent_log.append(
					"### Local fallback (Cursor mode)\n"
					+ "Ejecutadas %d acción(es) localmente — el parseo del modelo falló o estaba incompleto."
					% fallback_results.size()
				)
	
	# Count tool calls that actually changed/inspected the scene without error.
	# Contar las tool calls que realmente se ejecutaron sin error.
	var ok_tool_count: int = 0
	for result in tool_results:
		if result is Dictionary and bool(result.get("result", {}).get("ok", false)):
			ok_tool_count += 1
	_agent_tools_executed += ok_tool_count
	
	if tool_calls_detected and tool_results.is_empty():
		_agent_unparsed_tool_steps += 1
		_agent_log.append(
			"### Tool parse warning (step %d)\nNo se pudieron ejecutar tools del modelo "
			+ "(JSON/XML). Revisa el formato MiniMax." % _agent_step
		)
		if _agent_step < _agent_max_steps:
			_agent_messages.append({
				"role": "user",
				"content": (
					"ERROR: Your tool markup was NOT executed. Use ONE of these formats NOW:\n"
					+ "1) Native tool_calls from the API, OR\n"
					+ "2) <tool_call>{\"tool\":\"get_scene_snapshot\",\"params\":{}}</tool_call>, OR\n"
					+ "3) <tool name=\"read_script\"><param name=\"path\">res://scripts/player.gd</param></tool>\n"
					+ "Do NOT repeat the plan — execute tools immediately."
					+ _language_hint_suffix()
				),
			})
			_agent_step += 1
			agent_step_update.emit(_agent_step, _agent_max_steps, "Reintentando parseo de tools…")
			_send_agent_request()
			return
	elif empty_tool_tags and tool_results.is_empty():
		_agent_empty_tag_streak += 1
		_agent_log.append("### Tool parse warning (step %d)\nDetecté <tool_call></tool_call> vacío — falta JSON dentro del tag. (racha: %d)" % [_agent_step, _agent_empty_tag_streak])
		if _agent_empty_tag_streak >= 3:
			# 3+ empty tags in a row: strip the model's last message to remove the
			# broken pattern, inject a concrete example, and give one last chance.
			# 3+ tags vacíos seguidos: limpiar el último mensaje del modelo para quitar
			# el patrón roto, inyectar un ejemplo concreto y dar una última oportunidad.
			_agent_messages.append({
				"role": "user",
				"content": (
					"LAST CHANCE: You have sent empty <tool_call></tool_call> %d times. " % _agent_empty_tag_streak
					+ "The tags are NOT optional formatting — they MUST wrap JSON. "
					+ "Copy this EXACT pattern, replacing only the values:\n"
					+ "<tool_call>{\"tool\":\"get_scene_snapshot\",\"params\":{}}</tool_call>\n"
					+ "<tool_call>{\"tool\":\"inspect_node\",\"params\":{\"node_path\":\"MainMenu\"}}</tool_call>\n"
					+ "<tool_call>{\"tool\":\"set_node_property\",\"params\":{\"node_path\":\"MainMenu\",\"property\":\"visible\",\"value\":true}}</tool_call>\n"
					+ "If you truly have nothing to do, write ONLY a plain text summary with NO <tool_call> tags at all."
					+ _language_hint_suffix()
				),
			})
			_agent_step += 1
			agent_step_update.emit(_agent_step, _agent_max_steps, "Último intento de tool_call…")
			_send_agent_request()
			return
		if _agent_empty_tag_streak >= 5:
			_finish_agent_loop(
				false,
				_compose_agent_output()
				+ "\n\n---\nEl modelo generó tool_call vacíos %d veces seguidas y no logró ejecutar herramientas. " % _agent_empty_tag_streak
				+ "Prueba con otro modelo o reformula la petición."
			)
			return
		if _agent_step < _agent_max_steps:
			_agent_messages.append({
				"role": "user",
				"content": (
					"ERROR: Your <tool_call></tool_call> tag was EMPTY (attempt %d). " % _agent_empty_tag_streak
					+ "You MUST put JSON inside the tags on a SINGLE LINE with no line breaks. Example:\n"
					+ "<tool_call>{\"tool\":\"inspect_node\",\"params\":{\"node_path\":\"MainMenu\"}}</tool_call>\n"
					+ "Do it NOW — one line, no spaces before/after the JSON."
					+ _language_hint_suffix()
				),
			})
			_agent_step += 1
			agent_step_update.emit(_agent_step, _agent_max_steps, "Corrigiendo tool_call vacío (%d)…" % _agent_empty_tag_streak)
			_send_agent_request()
			return
	
	if not tool_results.is_empty():
		_agent_model_tool_batches += 1
		var compact_results: String = (
			editor_tools.compact_tool_results_for_context(tool_results)
			if editor_tools else JSON.stringify(tool_results, "\t")
		)
		_agent_log.append("### Tool results (step %d)\n%s" % [_agent_step, compact_results])
	
	for entry in tool_results:
		if entry is Dictionary:
			var tool_result: Variant = entry.get("result", {})
			if tool_result is Dictionary and bool(tool_result.get("awaiting_user", false)):
				_pause_agent_for_user(String(tool_result.get("question", "")), true)
				return
	
	if _agent_code_only and _response_has_code_block(content):
		_finish_agent_loop(true, _compose_agent_output())
		return
	
	var batch_read_only: bool = (
		not tool_results.is_empty()
		and ok_tool_count > 0
		and editor_tools != null
		and editor_tools.batch_is_read_only_only(tool_results)
	)
	var verify_only: bool = (
		editor_tools != null
		and editor_tools.batch_is_verify_only(tool_results)
	)
	var clean_scripts: bool = (
		editor_tools != null
		and editor_tools.batch_has_clean_script_check(tool_results)
	)
	if batch_read_only:
		_agent_read_only_streak += 1
	elif ok_tool_count > 0:
		_agent_read_only_streak = 0
	if editor_tools != null and editor_tools.batch_had_mutation(tool_results):
		_agent_had_mutation = true
		_agent_script_verify_clean = false
		_agent_runtime_checked = false
	if editor_tools != null and editor_tools.batch_has_clean_script_check(tool_results):
		_agent_script_verify_clean = true
	if editor_tools != null and editor_tools.batch_has_clean_runtime_check(tool_results):
		_agent_runtime_checked = true
	if _agent_script_verify_clean and _runtime_verify_optional():
		_agent_runtime_checked = true
	if verify_only and clean_scripts:
		_agent_verify_streak += 1
	elif editor_tools != null and editor_tools.batch_had_mutation(tool_results):
		_agent_verify_streak = 0
	
	# Track batches where every tool call failed
	# after two such batches instead of burning all steps re-trying the same broken plan.
	# Seguir los lotes donde TODAS las tools fallaron (p. ej. tools inexistentes). Cortar
	# tras dos lotes así en vez de quemar todos los pasos repitiendo el mismo plan roto.
	var all_failed: bool = not tool_results.is_empty() and ok_tool_count == 0
	if all_failed and editor_tools != null and editor_tools.batch_only_disabled_tool_failures(tool_results):
		all_failed = false
	if ok_tool_count > 0:
		_agent_stall_count = 0
		_agent_failed_batches = 0
		_agent_empty_tag_streak = 0
	
	if verify_only and _agent_had_mutation and _agent_script_verify_clean and _agent_runtime_checked:
		if editor_tools == null or not editor_tools.batch_has_error_reports(tool_results):
			_finish_agent_loop(
				true,
				_compose_agent_output()
				+ "\n\n---\nVerificación completada (0 errores de script y debugger). "
				+ "Prueba el juego (F5) si cambiaste gameplay. Si algo falla, pega el error de consola."
			)
			return
	elif all_failed:
		if _try_recover_from_tool_errors(tool_results):
			return
		var only_broken_inspect: bool = (
			not tool_results.is_empty()
			and editor_tools != null
			and editor_tools.has_method("batch_only_broken_inspect_failures")
			and editor_tools.batch_only_broken_inspect_failures(tool_results)
		)
		if not only_broken_inspect:
			_agent_failed_batches += 1
	
	if _agent_failed_batches >= 2:
		_finish_agent_loop(
			false,
			_compose_agent_output()
			+ "\n\n---\nEl agente se detuvo: las tool calls fallaron repetidamente "
			+ "(revisa nombres de tools/rutas). No se completó la tarea."
		)
		return
	
	var visible_turn: String = _visible_response_text(content, parsed)
	var had_mutation: bool = (
		ok_tool_count > 0
		and editor_tools != null
		and editor_tools.batch_had_mutation(tool_results)
	)
	if _content_has_degenerate_repetition(visible_turn) and not had_mutation and not empty_tool_tags:
		if _agent_tools_executed == 0 and _response_has_tool_calls(tool_source):
			_agent_messages.append({
				"role": "user",
				"content": (
					"STOP repeating the plan. You already said what you will do — "
					+ "call the tools NOW (get_scene_snapshot, read_script, create_script, set_node_property)."
					+ _language_hint_suffix()
				),
			})
			_agent_step += 1
			agent_step_update.emit(_agent_step, _agent_max_steps, "Forzando ejecución de tools…")
			_send_agent_request()
			return
		_finish_agent_loop(
			true,
			_compose_agent_output()
			+ "\n\n---\nEl agente se detuvo: respuesta repetitiva detectada."
		)
		return
	
	# 1) Tools executed -> feed compact results back, continue.
	# Read-only batches (list/find/inspect) do NOT consume an agent step.
	# Los lotes solo lectura (list/find/inspect) NO consumen un paso del agente.
	if not tool_results.is_empty() and (_agent_step < _agent_max_steps or batch_read_only or verify_only):
		if ok_tool_count > 0 and editor_tools != null and editor_tools.batch_had_mutation(tool_results):
			if _looks_like_task_complete(visible_turn) and not _needs_verify_before_finish():
				_finish_agent_loop(true, _compose_agent_output())
				return
		if used_native_tools:
			for entry in tool_results:
				if not entry is Dictionary:
					continue
				var tool_call_id: String = String(entry.get("tool_call_id", "")).strip_edges()
				if tool_call_id.is_empty():
					continue
				var compact_entry: String = JSON.stringify(entry.get("result", entry))
				if editor_tools != null and editor_tools.has_method("compact_tool_results_for_context"):
					compact_entry = editor_tools.compact_tool_results_for_context([entry])
				if compact_entry.strip_edges().is_empty():
					compact_entry = "{}"
				_agent_messages.append({
					"role": "tool",
					"tool_call_id": tool_call_id,
					"content": compact_entry,
				})
		else:
			var followup: String = _build_tool_followup(tool_results)
			_agent_messages.append({"role": "user", "content": followup})
		if not batch_read_only and not verify_only:
			_agent_step += 1
		var summary: String = "Ejecutadas %d tool(s), continuando…" % tool_results.size()
		if batch_read_only:
			summary = "Exploración (%d tool(s)) — no consume paso" % tool_results.size()
		elif verify_only:
			summary = "Verificación (%d tool(s)) — no consume paso" % tool_results.size()
		elif _agent_read_only_streak >= 2:
			summary = "Inspección repetida — actúa o entrega código"
		agent_step_update.emit(_agent_step, _agent_max_steps, summary)
		_send_agent_request()
		return
	
	if not tool_results.is_empty() and _agent_step >= _agent_max_steps:
		_pause_agent_for_user(_max_steps_pause_question(), true)
		return
	
	# 2) No tools this turn — decide: is the response a complete answer or stalling?
	# 2) Sin tools este turno — decidir: ¿respuesta completa o estancado?
	var visible_text: String = _visible_response_text(content, parsed)
	var looks_done: bool = _looks_like_task_complete(visible_text)
	var is_substantial: bool = _response_is_substantial(visible_text)

	# A) If the response looks complete OR is substantial text without tools,
	#    finish immediately — no nudges, no extra steps.
	#    Covers: informational Q&A, final summaries, explanations.
	# A) Si la respuesta se ve completa O es texto sustancial sin tools,
	#    terminar inmediatamente — sin nudges ni pasos extra.
	if looks_done or (is_substantial and not _response_is_narration_only(content, parsed)):
		if _block_hallucinated_summary(visible_text) and _push_summary_blocked_nudge():
			return
		if _needs_verify_before_finish() and _push_verify_nudge([]):
			return
		_finish_agent_loop(true, _compose_agent_output())
		return
	if (looks_done or repeated) and _agent_tools_executed > 0:
		if _block_hallucinated_summary(visible_text) and _push_summary_blocked_nudge():
			return
		if _needs_verify_before_finish() and _push_verify_nudge([]):
			return
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
		_pause_agent_for_user(_max_steps_pause_question(), true)
		return
	
	if _pending_enable_tools:
		var nudge: String
		if _agent_code_only and _agent_read_only_streak >= 1:
			nudge = (
				"Ya inspeccionaste la escena. Responde AHORA con el bloque ```gdscript completo "
				+ "y pasos breves. No uses más tools."
			)
		elif _agent_model_tool_batches == 0:
			_agent_act_nudges += 1
			var needs_example: bool = empty_tool_tags or _response_is_narration_only(content, parsed)
			if _agent_act_nudges > 3:
				_finish_agent_loop(
					_agent_tools_executed > 0 or is_substantial,
					_compose_agent_output()
					+ (
						"\n\n---\nEl modelo no ejecutó ninguna acción pese a varias indicaciones. "
						+ "Prueba con un modelo más capaz para tools o reformula la petición."
						if not is_substantial else ""
					)
				)
				return
			nudge = _act_now_nudge(needs_example)
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

func _try_recover_from_tool_errors(tool_results: Array) -> bool:
	if _agent_step >= _agent_max_steps or tool_results.is_empty():
		return false
	var hints: PackedStringArray = []
	for entry in tool_results:
		if not entry is Dictionary:
			continue
		var err: String = String(entry.get("result", {}).get("error", ""))
		var lower: String = err.to_lower()
		if "property not found" in lower and "mesh" in lower:
			hints.append(
				"Use create_cylinder_mesh on the parent (e.g. Player) — NOT set_node_property mesh/height."
			)
		elif err.contains("create_cylinder_mesh"):
			hints.append(err)
	if hints.is_empty():
		return false
	var nudge: String = (
		"Tool error — retry with the correct tool:\n- "
		+ "\n- ".join(hints)
		+ "\nFor a visible player body: "
		+ "<tool_call>{\"tool\":\"create_cylinder_mesh\",\"params\":{\"parent_node_path\":\"Player\",\"node_name\":\"Body\",\"radius\":0.4,\"height\":1.8,\"color\":[0.2,0.6,1.0]}}</tool_call>"
	)
	_agent_messages.append({"role": "user", "content": nudge + _language_hint_suffix()})
	_agent_step += 1
	agent_step_update.emit(_agent_step, _agent_max_steps, "Corrigiendo tool incorrecta…")
	_send_agent_request()
	return true

func _needs_verify_before_finish() -> bool:
	if not _agent_had_mutation or _agent_code_only:
		return false
	if not _agent_script_verify_clean:
		return true
	if _agent_runtime_checked or _runtime_verify_optional():
		return false
	return true

func _runtime_verify_optional() -> bool:
	return editor_tools == null or not editor_tools.is_tool_allowed("get_runtime_errors")

func _push_verify_nudge(tool_results: Array) -> bool:
	if not _needs_verify_before_finish():
		return false
	if editor_tools != null and editor_tools.batch_has_error_reports(tool_results):
		return false
	if _agent_step >= _agent_max_steps:
		return false
	var nudge: String
	if not _agent_script_verify_clean:
		nudge = (
			"STOP — do NOT give the final summary yet. You edited scripts/scenes. "
			+ "Call get_script_errors once to check parse/compile and debugger buffer."
		)
	elif not _agent_runtime_checked and not _runtime_verify_optional():
		nudge = (
			"Script check passed. BEFORE final summary call get_runtime_errors once "
			+ "(debugger/console panel; ask user to F5 first if gameplay logic changed). "
			+ "If count is 0, then give a short final summary and note playtest if F5 was not run."
		)
	else:
		return false
	_agent_messages.append({"role": "user", "content": nudge + _language_hint_suffix()})
	_agent_step += 1
	agent_step_update.emit(_agent_step, _agent_max_steps, "Verificación obligatoria antes del resumen…")
	_send_agent_request()
	return true

func _summary_claims_scene_edits(text: String) -> bool:
	var lower: String = text.to_lower()
	var markers: PackedStringArray = [
		"añadí", "agregué", "bajé", "creé", "modifiqu", "cambié", "actualicé",
		"cilindro", "player/body", "cambios en la escena", "res://scenes/",
		"added", "lowered", "created", "updated the scene", "changes in",
	]
	for marker in markers:
		if lower.contains(marker):
			return true
	return false

func _block_hallucinated_summary(text: String) -> bool:
	if _agent_code_only or not _summary_claims_scene_edits(text):
		return false
	return not _agent_had_mutation and _agent_tools_executed == 0

func _push_summary_blocked_nudge() -> bool:
	if _agent_step >= _agent_max_steps:
		return false
	_agent_messages.append({
		"role": "user",
		"content": (
			"STOP: You wrote a final summary claiming scene/script edits, but NO editor tool succeeded. "
			+ "Do NOT describe changes that did not happen. Execute tools NOW "
			+ "(create_cylinder_mesh, set_node_property, create_script, etc.) or admit failure."
			+ _language_hint_suffix()
		),
	})
	_agent_step += 1
	agent_step_update.emit(_agent_step, _agent_max_steps, "Resumen bloqueado — sin tools exitosas…")
	_send_agent_request()
	return true

func _build_tool_followup(tool_results: Array) -> String:
	var compact: String = (
		editor_tools.compact_tool_results_for_context(tool_results)
		if editor_tools else JSON.stringify(tool_results, "\t")
	)
	var parts: PackedStringArray = [
		"Tool execution results (compact):",
		compact,
	]
	if _agent_read_only_streak >= 2:
		parts.append(
			"STOP inspecting repeatedly. You already have enough scene data. "
			+ "Either call create_script / set_node_property NOW to finish the task, "
			+ "or reply with a final ```gdscript code block if the user wanted code only."
		)
	elif editor_tools and editor_tools.batch_had_mutation(tool_results):
		if _runtime_verify_optional():
			parts.append(
				"Changes applied. Call get_script_errors ONCE (parse/compile). "
				+ "get_runtime_errors is OFF in core harness — note F5 playtest in the final summary."
			)
		else:
			parts.append(
				"Changes applied. BEFORE final summary call get_script_errors ONCE, then get_runtime_errors ONCE "
				+ "(debugger/console; user must F5 first for in-game errors). Fix any errors, verify again, then summarize."
			)
	elif editor_tools and editor_tools.batch_is_verify_only(tool_results):
		if editor_tools.batch_has_error_reports(tool_results):
			parts.append(
				"Errors reported — fix with create_script/set_node_property, then verify again."
			)
		elif not editor_tools.batch_has_clean_script_check(tool_results):
			parts.append(
				"Call get_script_errors once to check parse/compile errors."
				+ ("" if _runtime_verify_optional() else ", then get_runtime_errors for debugger/console.")
			)
		elif not editor_tools.batch_has_clean_runtime_check(tool_results) and not _runtime_verify_optional():
			parts.append(
				"Script check passed. Call get_runtime_errors once (debugger panel; F5 first if gameplay changed), then final summary."
			)
		elif editor_tools.batch_has_clean_script_check(tool_results):
			parts.append(
				"Script check passed (0 errors). Reply with a short FINAL SUMMARY"
				+ (" and note F5 playtest." if _runtime_verify_optional() else ". Call get_runtime_errors once first.")
				+ " Do NOT loop save_scene/get_script_errors unless you changed something."
			)
	parts.append(
		"Continue the task. Prefer ONE action per step. "
		+ "If the task is complete, reply with ONE short final summary only (max 8 lines, no emoji spam) "
		+ "and do NOT include <tool_call> blocks."
		+ _language_hint_suffix()
	)
	return "\n\n".join(parts)

func _compose_agent_output() -> String:
	return "\n\n".join(_agent_log)

func _max_steps_pause_question() -> String:
	if _active_user_language == "es":
		return (
			"Alcancé el límite de %d pasos de edición. "
			% _agent_max_steps
			+ "Responde «continuar» para seguir con la misma tarea, o reformula lo que falta."
		)
	return (
		"Reached the %d-step edit limit. "
		% _agent_max_steps
		+ "Reply «continue» to keep working on the same task, or clarify what is still missing."
	)

func _looks_like_continue_reply(text: String) -> bool:
	var lower: String = text.to_lower().strip_edges()
	var markers: PackedStringArray = [
		"continuar", "continue", "adelante", "go ahead", "sí adelante", "si adelante",
		"yes continue", "keep going", "sigue", "proceed",
	]
	for marker in markers:
		if lower == marker or lower.begins_with(marker + " ") or lower.ends_with(" " + marker):
			return true
	return lower in ["sí", "si", "yes", "ok", "vale"]

func _pause_agent_for_user(question: String, partial_success: bool) -> void:
	if question.strip_edges().is_empty():
		question = _max_steps_pause_question()
	_agent_paused = true
	_agent_pause_question = question.strip_edges()
	_agent_log.append("### Pausado\n%s" % _agent_pause_question)
	var output: String = (
		_compose_agent_output()
		+ "\n\n---\n**Esperando tu respuesta:** "
		+ _agent_pause_question
	)
	_is_processing = false
	_http_in_flight = false
	agent_paused_for_user.emit(_agent_pause_question)
	_handle_request_success(partial_success, output)

func _resume_agent_loop(user_reply: String, provider_id: String, options: Dictionary) -> void:
	_agent_paused = false
	_agent_pause_question = ""
	_cancel_requested = false
	_is_processing = true
	_pending_provider_id = provider_id
	_pending_enable_tools = bool(options.get("enable_tools", config_manager.get_setting("enable_editor_tools", true)))
	_pending_options = options
	if _looks_like_continue_reply(user_reply):
		var extension: int = int(config_manager.get_setting("agent_step_extension", 12))
		_agent_max_steps += maxi(extension, 1)
	_agent_messages.append({"role": "user", "content": user_reply.strip_edges() + _language_hint_suffix()})
	agent_step_update.emit(_agent_step, _agent_max_steps, "Reanudando agente…")
	_send_agent_request()

func _finish_agent_loop(success: bool, text: String) -> void:
	_reset_agent_state()
	_handle_request_success(success, text)

func _reset_agent_state() -> void:
	_agent_active = false
	_agent_paused = false
	_agent_pause_question = ""
	_agent_step = 0
	_agent_stall_count = 0
	_agent_last_response_signature = ""
	_agent_failed_batches = 0
	_agent_empty_tag_streak = 0
	_agent_verify_streak = 0
	_agent_had_mutation = false
	_agent_unparsed_tool_steps = 0
	_agent_script_verify_clean = false
	_agent_runtime_checked = false
	_agent_tools_executed = 0
	_agent_act_nudges = 0
	_agent_model_tool_batches = 0
	_agent_code_only = false
	_agent_read_only_streak = 0
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

func _tool_source_text(parsed: Dictionary, content: String, raw_text: String) -> String:
	# Parse tools from the full model payload (thinking tags may strip them from content).
	# Parsear tools del payload completo (los tags thinking pueden quitarlos del content).
	var raw: String = String(parsed.get("raw", raw_text)).strip_edges()
	if not raw.is_empty():
		return raw
	if not content.strip_edges().is_empty():
		return content
	return raw_text.strip_edges()

func _bootstrap_context_mode() -> String:
	if config_manager == null:
		return "minimal"
	return String(config_manager.get_setting("bootstrap_context_mode", "minimal")).strip_edges().to_lower()

func _bootstrap_agent_context(user_prompt: String) -> String:
	if _agent_code_only:
		return ""
	var mode: String = _bootstrap_context_mode()
	var lower: String = user_prompt.to_lower()
	if project_index != null and project_index.has_method("is_ready"):
		if bool(config_manager.get_setting("enable_project_index", true)) and project_index.is_ready():
			var indexed: String = String(project_index.build_agent_bootstrap(user_prompt, mode))
			if not indexed.is_empty():
				if _active_user_language == "es":
					if mode == "minimal":
						indexed = (
							"Contexto mínimo (índice bajo demanda). "
							+ "Usa search_project_index, get_scene_snapshot, read_script cuando lo necesites.\n"
							+ indexed
						)
					else:
						indexed = (
							"Contexto precargado del índice (NO vuelvas a escanear res:// entero). "
							+ "Usa search_project_index para assets en cualquier carpeta (SceneBuilder es opcional). "
							+ "Antes de colocar props 3D: get_scene_spatial_profile + get_asset_bounds para escala correcta.\n"
							+ indexed
						)
				if mode == "full":
					indexed = _append_spatial_bootstrap(indexed, lower)
				elif _prompt_needs_spatial_mapping(lower):
					indexed += (
						"\n\nSpatial task detected — call get_scene_spatial_profile + get_asset_bounds before placing props."
					)
				return indexed
	if editor_tools == null or mode == "minimal":
		return ""
	var keywords: PackedStringArray = [
		"mapa", "piso", "pisos", "mundo", "scenebuilder", "scene builder", "pared",
		"floor_", "edificio", "escalera", "stairs", "constru", "build", "coloca",
	]
	var relevant: bool = false
	for keyword in keywords:
		if lower.contains(keyword):
			relevant = true
			break
	if not relevant:
		return ""
	var tool_results: Array = []
	var catalog: Dictionary = editor_tools.execute_tool(
		"list_scene_builder_catalog",
		{"path": "res://Data/SceneBuilder"}
	)
	tool_results.append({"tool": "list_scene_builder_catalog", "result": catalog})
	var snapshot: Dictionary = editor_tools.execute_tool("get_scene_snapshot", {"max_depth": 4})
	tool_results.append({"tool": "get_scene_snapshot", "result": snapshot})
	var ok_count: int = 0
	for entry in tool_results:
		if entry is Dictionary and bool(entry.get("result", {}).get("ok", false)):
			ok_count += 1
	_agent_tools_executed += ok_count
	var compact: String = (
		editor_tools.compact_tool_results_for_context(tool_results)
		if editor_tools else JSON.stringify(tool_results, "\t")
	)
	var fallback: String = ""
	if _active_user_language == "es":
		fallback = (
			"Contexto precargado (NO vuelvas a listar el proyecto entero). "
			+ "Usa estos datos; assets en cualquier carpeta res://; SceneBuilder es opcional. "
			+ "Antes de colocar: get_scene_spatial_profile + get_asset_bounds.\n"
			+ compact
		)
	else:
		fallback = (
			"Preloaded context (do NOT re-list the whole project). "
			+ "Assets anywhere under res://; SceneBuilder optional. "
			+ "Before placing: get_scene_spatial_profile + get_asset_bounds.\n"
			+ compact
		)
	return _append_spatial_bootstrap(fallback, lower)

func _prompt_needs_spatial_mapping(lower_prompt: String) -> bool:
	var keywords: PackedStringArray = [
		"mapa", "piso", "pisos", "mundo", "floor_", "edificio", "escalera", "stairs",
		"constru", "build", "coloca", "tile", "nivel", "level", "layout",
	]
	for keyword in keywords:
		if lower_prompt.contains(keyword):
			return true
	return false

func _append_spatial_bootstrap(base: String, lower_prompt: String) -> String:
	if editor_tools == null or not _prompt_needs_spatial_mapping(lower_prompt):
		return base
	var spatial: Dictionary = editor_tools.execute_tool("get_scene_spatial_profile", {"max_nodes": 60})
	if not bool(spatial.get("ok", false)):
		return base
	var summary: String = String(spatial.get("mapping_summary", "")).strip_edges()
	if summary.is_empty():
		return base
	return "%s\n\n## Spatial mapping (open scene)\n%s" % [base, summary]

func _response_is_narration_only(content: String, parsed: Dictionary) -> bool:
	var visible: String = _visible_response_text(content, parsed).to_lower()
	if visible.is_empty():
		return true
	# Short "I will…" plans with no real content are narration.
	# But long explanations that happen to contain "voy a" are NOT narration.
	# Planes cortos "voy a…" sin contenido real son narración.
	# Pero explicaciones largas que casualmente contienen "voy a" NO lo son.
	if visible.length() > 300:
		return false
	var markers: PackedStringArray = [
		"voy a ", "let me ", "i will ", "i'll ", "empezar", "explorar", "explore",
		"primero", "first i", "esta vez", "this time", "correctamente",
	]
	for marker in markers:
		if visible.contains(marker):
			return true
	return false

func _response_is_substantial(text: String) -> bool:
	# A response with real content (>150 chars, not just plan headers).
	# Used to detect informational answers that don't need tools.
	# Respuesta con contenido real (>150 chars, no solo encabezados de plan).
	var stripped: String = text.strip_edges()
	if stripped.length() < 150:
		return false
	var line_count: int = 0
	for line in stripped.split("\n"):
		if not line.strip_edges().is_empty():
			line_count += 1
	return line_count >= 3

func _ollama_supports_thinking(model_name: String) -> bool:
	return ModelCapabilities.supports_thinking("ollama", model_name)

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
	for token in ["🎮", "✅", "❌", "*", "#", "`", "—"]:
		text = text.replace(token, "")
	var regex := RegEx.new()
	regex.compile("[*`#\\s]+")
	text = regex.sub(text, " ", true)
	return text.strip_edges().substr(0, 200)

func _content_has_degenerate_repetition(text: String) -> bool:
	if harness != null and harness.has_method("has_degenerate_repetition"):
		return harness.has_degenerate_repetition(text)
	return false

func _looks_like_task_complete(text: String) -> bool:
	var lower: String = text.to_lower()
	var markers: PackedStringArray = [
		"resumen final",
		"final summary",
		"task is complete",
		"task complete",
		"tarea completada",
		"tarea complete",
		"problemas resueltos",
		"problema resuelto",
		"listo para probar",
		"esperando tu prueba",
		"esperando feedback",
		"sin errores de script",
		"sin errores de compilación",
		"compila sin errores",
		"¿necesitas ayuda",
		"need any additional",
		"need further help",
		"need additional help",
		"anything else",
		"algo más",
		"en resumen",
		"puedo ayudarte a",
		"i can help you",
		"dime qué necesitas",
		"let me know",
		"indica qué tarea",
		"indícame qué",
		"esperando la tarea",
		"waiting for",
		"¿qué quieres que haga",
	]
	for marker in markers:
		if lower.contains(marker):
			return true
	return false

func _language_hint_suffix() -> String:
	if _active_user_language == "es":
		return " IMPORTANTE: Responde SIEMPRE en español. No cambies al inglés en el resumen final."
	return " IMPORTANT: Always reply in the user's language (%s)." % _active_user_language

func _user_wants_code_only(prompt: String) -> bool:
	var lower: String = prompt.to_lower()
	var markers: PackedStringArray = [
		"dame el codigo", "dame el código", "solo el codigo", "solo el código",
		"no te pedi crear", "no me pidas crear", "no crear el script", "no lo crees",
		"yo lo hago", "para yo hacerlo", "yo lo pego", "yo lo aplico",
		"give me the code", "just the code", "don't create", "do not create",
		"don't write the file", "do not write the file", "i'll paste", "i will paste",
	]
	for marker in markers:
		if lower.contains(marker):
			return true
	return false

func _response_has_code_block(text: String) -> bool:
	return text.contains("```gdscript") or text.contains("```csharp")

func _act_now_nudge(force_example: bool = false) -> String:
	# Force the model to perform real edits instead of only inspecting/summarizing.
	# Forzar al modelo a hacer cambios reales en lugar de solo inspeccionar/resumir.
	var example: String = (
		"\n\nEjemplo válido (copia el formato, NO dejes <tool_call></tool_call> vacío):\n"
		+ "<tool_call>{\"tool\":\"place_scene_builder_item\",\"params\":{"
		+ "\"item_path\":\"res://Data/SceneBuilder/Wall/Wall_08.tres\","
		+ "\"parent_node_path\":\"Floor_1_exit\",\"node_name\":\"Wall_n1\","
		+ "\"position\":[0,0,0],\"scale\":[100,100,100]}}</tool_call>"
	)
	if _active_user_language == "es":
		var msg := (
			"Todavía NO has ejecutado tools válidas. NO narres el plan — EMITE <tool_call> con JSON ahora. "
			+ "NO repitas list_project_files desde res://. Usa el contexto precargado o find_project_paths. "
			+ "Para mapas: place_scene_builder_item / instance_scene. "
			+ "Formato exacto: <tool_call>{\"tool\":\"...\",\"params\":{...}}</tool_call>."
		)
		return msg + (example if force_example else "")
	return (
		"You have NOT executed valid tools yet. Do NOT narrate — EMIT <tool_call> JSON now. "
		+ "Do NOT repeat list_project_files from res://. Use preloaded context or find_project_paths. "
		+ "For maps: place_scene_builder_item / instance_scene. "
		+ "Exact format: <tool_call>{\"tool\":\"...\",\"params\":{...}}</tool_call>."
		+ (example if force_example else "")
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
	if _response_has_tool_calls(content):
		return false
	return _response_asks_user_instead_of_acting(visible)

func _response_asks_user_instead_of_acting(text: String) -> bool:
	var lower: String = text.to_lower()
	var ask_markers: PackedStringArray = [
		"¿cuál es", "cual es el nombre", "dime el nombre", "tell me the",
		"what is the name", "what action", "input map", "project settings",
		"project → project settings", "can you tell me", "could you tell me",
		"¿cuál action", "¿cual action", "revisa en:", "check in:",
	]
	for marker in ask_markers:
		if lower.contains(marker):
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
	if editor_tools != null and editor_tools.has_method("parse_tool_arguments"):
		args = editor_tools.parse_tool_arguments(args)
	elif args is String:
		var raw: String = String(args).strip_edges()
		args = {} if raw.is_empty() or not raw.begins_with("{") else JSON.parse_string(raw)
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
				return _openai_choice_to_text(first)
			return ""

func _openai_choice_to_text(choice: Dictionary) -> String:
	if choice.has("message") and choice.message is Dictionary:
		var message: Dictionary = choice.message
		var content: String = String(message.get("content", "")).strip_edges()
		var reasoning: String = String(message.get("reasoning_content", "")).strip_edges()
		if reasoning.is_empty():
			var extracted: Dictionary = ThinkingTags.extract_all_thinking(content)
			reasoning = String(extracted.get("thinking", "")).strip_edges()
			content = String(extracted.get("content", content)).strip_edges()
		if not reasoning.is_empty() and content.is_empty():
			return reasoning
		if not reasoning.is_empty() and not content.is_empty():
			return "<thinking>\n%s\n</thinking>\n\n%s" % [reasoning, content]
		return content
	return String(choice.get("text", "")).strip_edges()
