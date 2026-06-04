extends RefCounted

# AI Model Handler with multi-step agent loop / Manejador AI con loop agente multi-paso

signal query_started(provider_id: String)
signal query_completed(success: bool, text: String)
signal query_failed(error_message: String)
signal agent_step_update(step: int, max_steps: int, summary: String)

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

func query_provider(provider_id: String, user_prompt: String, options: Dictionary = {}) -> void:
	if http_request == null:
		query_failed.emit("HTTPRequest not initialized")
		return
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		query_failed.emit("Ya hay una petición en curso")
		return
	if cursor_cloud != null and cursor_cloud.is_busy():
		query_failed.emit("Ya hay una petición Cursor en curso")
		return
	
	var provider_cfg: Dictionary = config_manager.get_provider_config(provider_id).duplicate(true)
	if provider_cfg.is_empty():
		query_failed.emit("Proveedor desconocido: %s" % provider_id)
		return
	if not provider_cfg.get("enabled", false):
		query_failed.emit("Proveedor deshabilitado: %s" % provider_id)
		return
	
	if options.has("model_id"):
		provider_cfg["model"] = String(options.get("model_id"))
	
	if provider_id == "cursor":
		var cursor_mode: String = String(provider_cfg.get("api_mode", "local_proxy"))
		if cursor_mode == "cloud_agents" and String(provider_cfg.get("api_key", "")).strip_edges().is_empty():
			query_failed.emit("Cursor cloud_agents requiere API key")
			return
		if cursor_mode == "local_proxy" and String(provider_cfg.get("api_endpoint", "")).strip_edges().is_empty():
			query_failed.emit("Cursor local_proxy requiere endpoint URL")
			return
	
	_pending_provider_id = provider_id
	_pending_enable_tools = bool(options.get("enable_tools", config_manager.get_setting("enable_editor_tools", true)))
	_pending_options = options
	
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
	_agent_system_prompt = _build_system_prompt(user_prompt, options, true)
	_agent_messages = [{"role": "user", "content": user_prompt}]
	agent_step_update.emit(_agent_step, _agent_max_steps, "Starting agent loop...")
	_send_agent_request()

func _send_single_request(provider_id: String, provider_cfg: Dictionary, user_prompt: String, options: Dictionary) -> void:
	var system_prompt: String = _build_system_prompt(user_prompt, options, false)
	var messages: Array = [{"role": "user", "content": user_prompt}]
	_dispatch_request(provider_id, provider_cfg, system_prompt, messages)

func _send_agent_request() -> void:
	_dispatch_request(_agent_provider_id, _agent_provider_cfg, _agent_system_prompt, _agent_messages)

func _dispatch_request(provider_id: String, provider_cfg: Dictionary, system_prompt: String, messages: Array) -> void:
	_pending_provider_id = provider_id
	if _is_cursor_cloud_mode(provider_id, provider_cfg):
		_using_cursor_cloud = true
		_send_cursor_cloud_request(provider_cfg, system_prompt, messages)
		return
	
	_using_cursor_cloud = false
	var payload: Dictionary = _build_payload(provider_id, provider_cfg, system_prompt, messages)
	var headers: PackedStringArray = _build_headers(provider_id, provider_cfg)
	var url: String = _build_url(provider_id, provider_cfg)
	
	query_started.emit(provider_id)
	var result: int = http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if result != OK:
		_pending_provider_id = ""
		if _agent_active:
			_reset_agent_state()
		query_failed.emit("No se pudo iniciar la petición HTTP")

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
	query_failed.emit(error_message)

func _on_cursor_run_completed(text: String) -> void:
	if _agent_active:
		_handle_agent_response(text)
	else:
		_handle_single_response(text)

func _build_system_prompt(user_prompt: String, options: Dictionary, agent_mode: bool) -> String:
	if harness == null:
		return "You are an AI assistant in Godot 4."
	var built: Dictionary = harness.build_system_prompt(user_prompt, options, agent_mode)
	return String(built.get("system_prompt", ""))

func _process_model_text(raw_text: String) -> Dictionary:
	if harness:
		return harness.parse_model_response(raw_text)
	return {"thinking": "", "content": raw_text, "raw": raw_text}

func _format_model_output(parsed: Dictionary) -> String:
	if harness:
		return harness.format_for_display(parsed)
	return String(parsed.get("content", ""))

func _build_payload(provider_id: String, provider_cfg: Dictionary, system_prompt: String, messages: Array) -> Dictionary:
	var temperature: float = float(config_manager.get_setting("temperature", 0.7))
	var max_tokens: int = int(config_manager.get_setting("max_tokens", 4096))
	var model_name: String = String(provider_cfg.get("model", "default"))
	
	match provider_id:
		"ollama":
			return {
				"model": model_name,
				"messages": _prepend_system_message(system_prompt, messages),
				"stream": false
			}
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
	var provider_id: String = _pending_provider_id
	_pending_provider_id = ""
	
	if result != HTTPRequest.RESULT_SUCCESS:
		if _agent_active:
			_reset_agent_state()
		query_failed.emit("Error de red HTTP (%s)" % result)
		return
	if response_code < 200 or response_code >= 300:
		if _agent_active:
			_reset_agent_state()
		query_failed.emit("HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
		return
	
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null:
		if _agent_active:
			_reset_agent_state()
		query_failed.emit("Respuesta JSON inválida del modelo")
		return
	
	var text: String = _extract_response_text(provider_id, parsed)
	if text.is_empty():
		if _agent_active:
			_reset_agent_state()
		query_failed.emit("El modelo devolvió una respuesta vacía")
		return
	
	if _agent_active:
		_handle_agent_response(text)
	else:
		_handle_single_response(text)

func _handle_single_response(text: String) -> void:
	var parsed: Dictionary = _process_model_text(text)
	var content: String = String(parsed.get("content", text))
	var final_text: String = _format_model_output(parsed)
	if _pending_enable_tools and editor_tools and _response_has_tool_calls(content):
		var tool_results: Array = editor_tools.parse_and_execute_tool_calls(content)
		if not tool_results.is_empty():
			final_text += "\n\n---\nTool results:\n%s" % JSON.stringify(tool_results, "\t")
	query_completed.emit(true, final_text)

func _handle_agent_response(text: String) -> void:
	var parsed: Dictionary = _process_model_text(text)
	var content: String = String(parsed.get("content", text))
	var formatted: String = _format_model_output(parsed)
	_agent_log.append("### Step %d\n%s" % [_agent_step, formatted])
	_agent_messages.append({"role": "assistant", "content": content})
	
	var tool_results: Array = []
	if _pending_enable_tools and editor_tools and _response_has_tool_calls(content):
		tool_results = editor_tools.parse_and_execute_tool_calls(content)
	
	if not tool_results.is_empty():
		_agent_log.append("### Tool results (step %d)\n%s" % [_agent_step, JSON.stringify(tool_results, "\t")])
	
	if not tool_results.is_empty() and _agent_step < _agent_max_steps:
		var followup: String = _build_tool_followup(tool_results)
		_agent_messages.append({"role": "user", "content": followup})
		_agent_step += 1
		agent_step_update.emit(_agent_step, _agent_max_steps, "Executed %d tool(s), continuing..." % tool_results.size())
		_send_agent_request()
		return
	
	if not tool_results.is_empty() and _agent_step >= _agent_max_steps:
		_finish_agent_loop(true, _compose_agent_output() + "\n\n---\nAgent stopped: max steps reached.")
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
	)
	return "\n\n".join(parts)

func _compose_agent_output() -> String:
	return "\n\n".join(_agent_log)

func _finish_agent_loop(success: bool, text: String) -> void:
	_reset_agent_state()
	query_completed.emit(success, text)

func _reset_agent_state() -> void:
	_agent_active = false
	_agent_step = 0
	_agent_messages.clear()
	_agent_log.clear()
	_agent_provider_id = ""
	_agent_provider_cfg = {}
	_agent_system_prompt = ""
	if cursor_cloud:
		cursor_cloud.reset_session()

func _response_has_tool_calls(text: String) -> bool:
	return text.contains("<tool_call>")

func _extract_response_text(provider_id: String, parsed: Variant) -> String:
	if not parsed is Dictionary:
		return str(parsed)
	
	match provider_id:
		"ollama":
			if parsed.has("message") and parsed.message is Dictionary:
				return String(parsed.message.get("content", ""))
			return String(parsed.get("response", ""))
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
