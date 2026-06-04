extends RefCounted

# Cursor Cloud Agents API client / Cliente API Cloud Agents de Cursor

signal poll_update(status: String, message: String)
signal request_failed(error_message: String)
signal run_completed(text: String)

const BASE_URL := "https://api.cursor.com"

var http_request: HTTPRequest = null
var poll_timer: Timer = null

var _api_key: String = ""
var _agent_id: String = ""
var _run_id: String = ""
var _pending_action: String = ""
var _poll_attempts: int = 0
const MAX_POLL_ATTEMPTS := 120

func setup(owner: Node) -> void:
	if http_request != null:
		return
	http_request = HTTPRequest.new()
	owner.add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	poll_timer = Timer.new()
	poll_timer.one_shot = true
	poll_timer.timeout.connect(_poll_run_status)
	owner.add_child(poll_timer)

func reset_session() -> void:
	_agent_id = ""
	_run_id = ""
	_stop_polling()

func has_active_agent() -> bool:
	return not _agent_id.is_empty()

func is_busy() -> bool:
	if http_request == null:
		return false
	return http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED

func create_agent_and_run(api_key: String, model_name: String, prompt_text: String) -> void:
	if is_busy():
		request_failed.emit("Cursor cloud request already in progress")
		return
	if api_key.strip_edges().is_empty():
		request_failed.emit("Cursor API key is required")
		return
	
	_api_key = api_key.strip_edges()
	_agent_id = ""
	_run_id = ""
	_pending_action = "create_agent"
	_poll_attempts = 0
	
	var payload: Dictionary = {
		"prompt": {"text": prompt_text},
		"model": {"id": model_name},
		"mode": "agent"
	}
	_post_json("%s/v1/agents" % BASE_URL, payload)

func follow_up_run(api_key: String, prompt_text: String) -> void:
	if _agent_id.is_empty():
		request_failed.emit("Cursor cloud agent session not initialized")
		return
	if is_busy():
		request_failed.emit("Cursor cloud request already in progress")
		return
	
	_api_key = api_key.strip_edges()
	_pending_action = "follow_up"
	_poll_attempts = 0
	var payload: Dictionary = {
		"prompt": {"text": prompt_text}
	}
	_post_json("%s/v1/agents/%s/runs" % [BASE_URL, _agent_id], payload)

func _poll_run_status() -> void:
	if _agent_id.is_empty() or _run_id.is_empty():
		return
	if _poll_attempts >= MAX_POLL_ATTEMPTS:
		request_failed.emit("Cursor cloud run timed out while polling")
		return
	
	_poll_attempts += 1
	_pending_action = "poll_run"
	var url: String = "%s/v1/agents/%s/runs/%s" % [BASE_URL, _agent_id, _run_id]
	var headers: PackedStringArray = _auth_headers()
	http_request.request(url, headers, HTTPClient.METHOD_GET)

func _post_json(url: String, payload: Dictionary) -> void:
	var headers: PackedStringArray = _auth_headers()
	headers.append("Content-Type: application/json")
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % _api_key,
		"Accept: application/json"
	])

func _stop_polling() -> void:
	if poll_timer:
		poll_timer.stop()
	_poll_attempts = 0

func _schedule_poll(delay_sec: float = 2.0) -> void:
	if poll_timer:
		poll_timer.start(delay_sec)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_text: String = body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_stop_polling()
		request_failed.emit("Cursor cloud network error (%s)" % result)
		return
	if response_code < 200 or response_code >= 300:
		_stop_polling()
		request_failed.emit("Cursor cloud HTTP %d: %s" % [response_code, body_text])
		return
	
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not parsed is Dictionary:
		_stop_polling()
		request_failed.emit("Cursor cloud returned invalid JSON")
		return
	
	match _pending_action:
		"create_agent":
			_handle_create_agent_response(parsed)
		"follow_up":
			_handle_follow_up_response(parsed)
		"poll_run":
			_handle_poll_response(parsed)
		_:
			pass
	
	_pending_action = ""

func _handle_create_agent_response(parsed: Dictionary) -> void:
	var agent: Dictionary = parsed.get("agent", {})
	var run: Dictionary = parsed.get("run", {})
	_agent_id = String(agent.get("id", ""))
	_run_id = String(run.get("id", ""))
	if _agent_id.is_empty() or _run_id.is_empty():
		request_failed.emit("Cursor cloud did not return agent/run ids")
		return
	poll_update.emit(String(run.get("status", "CREATING")), "Cursor agent started...")
	_schedule_poll(1.5)

func _handle_follow_up_response(parsed: Dictionary) -> void:
	var run: Dictionary = parsed.get("run", {})
	_run_id = String(run.get("id", _run_id))
	if _run_id.is_empty():
		request_failed.emit("Cursor cloud follow-up did not return run id")
		return
	poll_update.emit(String(run.get("status", "CREATING")), "Cursor follow-up started...")
	_schedule_poll(1.5)

func _handle_poll_response(parsed: Dictionary) -> void:
	var status: String = String(parsed.get("status", ""))
	poll_update.emit(status, "Cursor run status: %s" % status)
	
	match status:
		"FINISHED":
			_stop_polling()
			var result_text: String = String(parsed.get("result", ""))
			if result_text.is_empty():
				result_text = "Cursor run finished without text result."
			run_completed.emit(result_text)
		"ERROR", "CANCELLED", "EXPIRED":
			_stop_polling()
			request_failed.emit("Cursor cloud run ended with status: %s" % status)
		_:
			_schedule_poll(2.0)
