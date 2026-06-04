extends RefCounted

# skills.sh catalog client (public search + download) / Cliente del catálogo skills.sh

signal search_completed(results: Array, query: String)
signal search_failed(error_message: String)
signal download_completed(skill_id: String, content: String, metadata: Dictionary)
signal download_failed(skill_id: String, error_message: String)

const SEARCH_URL := "https://skills.sh/api/search"
const DOWNLOAD_BASE := "https://skills.sh/api/download"

var http_request: HTTPRequest = null
var _pending_action: String = ""
var _pending_query: String = ""
var _pending_skill_id: String = ""
var _pending_metadata: Dictionary = {}

func setup(owner: Node) -> void:
	if http_request != null:
		return
	http_request = HTTPRequest.new()
	owner.add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func is_busy() -> bool:
	if http_request == null:
		return false
	return http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED

func search(query: String, limit: int = 40) -> void:
	if http_request == null:
		search_failed.emit("HTTPRequest not initialized")
		return
	if is_busy():
		search_failed.emit("busy")
		return
	var normalized: String = query.strip_edges()
	if normalized.length() < 2:
		search_failed.emit("query_too_short")
		return
	_pending_action = "search"
	_pending_query = normalized
	var url: String = "%s?q=%s&limit=%d" % [SEARCH_URL, normalized.uri_encode(), clampi(limit, 1, 200)]
	http_request.request(url)

func download_skill(source: String, skill_id: String) -> void:
	if http_request == null:
		download_failed.emit(skill_id, "HTTPRequest not initialized")
		return
	if is_busy():
		download_failed.emit(skill_id, "busy")
		return
	var normalized_source: String = source.strip_edges().trim_suffix("/")
	var normalized_skill: String = skill_id.strip_edges()
	if normalized_source.is_empty() or normalized_skill.is_empty():
		download_failed.emit(skill_id, "invalid_skill")
		return
	_pending_action = "download"
	_pending_skill_id = normalized_skill
	_pending_metadata = {"source": normalized_source, "skill_id": normalized_skill}
	var url: String = "%s/%s/%s" % [DOWNLOAD_BASE, normalized_source, normalized_skill]
	http_request.request(url)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_text: String = body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail_current("network_error")
		return
	if response_code < 200 or response_code >= 300:
		_fail_current("HTTP %d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null:
		_fail_current("invalid_json")
		return
	match _pending_action:
		"search":
			_handle_search_response(parsed)
		"download":
			_handle_download_response(parsed)
	_pending_action = ""

func _handle_search_response(parsed: Variant) -> void:
	if parsed is Dictionary and parsed.has("error"):
		search_failed.emit(String(parsed.get("error", "search_failed")))
		return
	var results: Array = []
	if parsed is Dictionary:
		var skills: Variant = parsed.get("skills", [])
		if skills is Array:
			results = skills
	search_completed.emit(results, _pending_query)

func _handle_download_response(parsed: Variant) -> void:
	var skill_id: String = _pending_skill_id
	if parsed is Dictionary and parsed.has("error"):
		download_failed.emit(skill_id, String(parsed.get("error", "download_failed")))
		return
	var content: String = _extract_skill_markdown(parsed)
	if content.is_empty():
		download_failed.emit(skill_id, "missing_skill_md")
		return
	download_completed.emit(skill_id, content, _pending_metadata.duplicate(true))

func _extract_skill_markdown(parsed: Variant) -> String:
	if not parsed is Dictionary:
		return ""
	var files: Variant = parsed.get("files", [])
	if not files is Array:
		return ""
	for entry in files:
		if entry is Dictionary:
			var path: String = String(entry.get("path", ""))
			if path.get_file().to_lower() == "skill.md":
				return String(entry.get("contents", ""))
	for entry in files:
		if entry is Dictionary:
			var path: String = String(entry.get("path", ""))
			if path.ends_with(".md"):
				return String(entry.get("contents", ""))
	return ""

func _fail_current(reason: String) -> void:
	match _pending_action:
		"search":
			search_failed.emit(reason)
		"download":
			download_failed.emit(_pending_skill_id, reason)
