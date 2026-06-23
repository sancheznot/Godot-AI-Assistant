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
var _local_cancelled: bool = false
var _cancel_http: HTTPRequest = null
var _pending_follow_up: Dictionary = {}
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
	
	_cancel_http = HTTPRequest.new()
	owner.add_child(_cancel_http)

func cancel() -> void:
	_local_cancelled = true
	_stop_polling()
	_pending_action = ""
	if http_request != null and http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_request.cancel_request()
	var agent_id: String = _agent_id
	var run_id: String = _run_id
	var api_key: String = _api_key
	reset_session()
	if not agent_id.is_empty() and not run_id.is_empty() and not api_key.is_empty():
		_post_cancel_run(agent_id, run_id, api_key)

func _post_cancel_run(agent_id: String, run_id: String, api_key: String) -> void:
	if _cancel_http == null or agent_id.is_empty() or run_id.is_empty() or api_key.is_empty():
		return
	if _cancel_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_cancel_http.cancel_request()
	var url: String = "%s/v1/agents/%s/runs/%s/cancel" % [BASE_URL, agent_id, run_id]
	var headers: PackedStringArray = _auth_headers_for_key(api_key)
	_cancel_http.request(url, headers, HTTPClient.METHOD_POST)

func reset_session() -> void:
	_agent_id = ""
	_run_id = ""
	_pending_follow_up.clear()
	_stop_polling()

func has_active_run() -> bool:
	return not _agent_id.is_empty() and not _run_id.is_empty()

func has_active_agent() -> bool:
	return not _agent_id.is_empty()

func is_busy() -> bool:
	# Only block while HTTP or poll timer is active — NOT while a session id exists.
	# Solo bloquear mientras HTTP o el timer de poll están activos — NO por tener sesión.
	if http_request != null and http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return true
	if _cancel_http != null and _cancel_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return true
	if poll_timer != null and not poll_timer.is_stopped():
		return true
	return false

func create_agent_and_run(api_key: String, model_name: String, prompt_text: String) -> void:
	if is_busy():
		request_failed.emit("Cursor cloud request already in progress")
		return
	if api_key.strip_edges().is_empty():
		request_failed.emit("Cursor API key is required")
		return
	
	_local_cancelled = false
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
		_pending_follow_up = {"api_key": api_key, "prompt_text": prompt_text}
		return
	_pending_follow_up.clear()
	
	_local_cancelled = false
	_api_key = api_key.strip_edges()
	_pending_action = "follow_up"
	_poll_attempts = 0
	var payload: Dictionary = {
		"prompt": {"text": prompt_text}
	}
	_post_json("%s/v1/agents/%s/runs" % [BASE_URL, _agent_id], payload)

func _flush_pending_follow_up() -> void:
	if _pending_follow_up.is_empty() or is_busy() or _agent_id.is_empty():
		return
	var pending: Dictionary = _pending_follow_up.duplicate()
	_pending_follow_up.clear()
	follow_up_run(String(pending.get("api_key", "")), String(pending.get("prompt_text", "")))

func _poll_run_status() -> void:
	if _local_cancelled or _agent_id.is_empty() or _run_id.is_empty():
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
	return _auth_headers_for_key(_api_key)

func _auth_headers_for_key(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % api_key.strip_edges(),
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
	if _local_cancelled:
		return
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
	_flush_pending_follow_up()

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
