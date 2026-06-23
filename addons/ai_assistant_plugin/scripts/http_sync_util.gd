extends RefCounted

# HTTP(S) via Thread — no main-thread freeze
# HTTP(S) via Thread — sin congelar el hilo principal

const DEFAULT_TIMEOUT_MS := 60000

static func request(
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	method: HTTPClient.Method = HTTPClient.METHOD_GET,
	body: String = "",
	timeout_ms: int = DEFAULT_TIMEOUT_MS,
	allow_insecure_tls: bool = false
) -> Dictionary:
	var parts: Dictionary = _parse_url(url)
	if not bool(parts.get("ok", false)):
		return parts
	parts["allow_insecure_tls"] = allow_insecure_tls
	var shared := {"done": false, "result": {}}
	var thread := Thread.new()
	thread.start(_http_thread_func.bind(shared, parts, headers, method, body, timeout_ms))
	while not shared.done:
		OS.delay_msec(50)
	thread.wait_to_finish()
	return shared.result

static func _http_thread_func(
	shared: Dictionary,
	parts: Dictionary,
	headers: PackedStringArray,
	method: HTTPClient.Method,
	body: String,
	timeout_ms: int
) -> void:
	shared.result = _do_http(parts, headers, method, body, timeout_ms)
	shared.done = true

static func _do_http(
	parts: Dictionary,
	headers: PackedStringArray,
	method: HTTPClient.Method,
	body: String,
	timeout_ms: int
) -> Dictionary:
	var client := HTTPClient.new()
	var tls: TLSOptions = null
	if bool(parts.get("use_tls", true)):
		tls = TLSOptions.client_unsafe() if bool(parts.get("allow_insecure_tls", false)) else TLSOptions.client()
	var conn_err: int = client.connect_to_host(String(parts.host), int(parts.port), tls)
	if conn_err != OK:
		return {"ok": false, "error": "connect failed: %d" % conn_err}
	var start_ms: int = Time.get_ticks_msec()
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		client.poll()
		if _timed_out(start_ms, timeout_ms):
			return {"ok": false, "error": "Connection timed out"}
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "error": "Could not connect (status %d)" % client.get_status()}
	var req_err: int = client.request(method, String(parts.path), headers, body)
	if req_err != OK:
		return {"ok": false, "error": "request failed: %d" % req_err}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if _timed_out(start_ms, timeout_ms):
			return {"ok": false, "error": "Request timed out"}
		OS.delay_msec(10)
	if not client.has_response():
		return {"ok": false, "error": "No HTTP response"}
	var code: int = client.get_response_code()
	var rb := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk: PackedByteArray = client.read_response_body_chunk()
		if chunk.size() > 0:
			rb.append_array(chunk)
		if _timed_out(start_ms, timeout_ms):
			return {"ok": false, "error": "Read timed out"}
		OS.delay_msec(10)
	var body_text: String = rb.get_string_from_utf8()
	if code < 200 or code >= 300:
		return {"ok": false, "error": "HTTP %d: %s" % [code, body_text.substr(0, 200)]}
	return {"ok": true, "code": code, "body": rb, "body_text": body_text}

static func _parse_url(url: String) -> Dictionary:
	var trimmed: String = url.strip_edges()
	var use_tls: bool = trimmed.begins_with("https://")
	var use_http: bool = trimmed.begins_with("http://")
	if not use_tls and not use_http:
		return {"ok": false, "error": "Only http:// or https:// URLs supported"}
	var rest: String = trimmed.substr(8 if use_tls else 7)
	var slash: int = rest.find("/")
	var host: String = rest.substr(0, slash) if slash >= 0 else rest
	var path: String = rest.substr(slash) if slash >= 0 else "/"
	if path.is_empty():
		path = "/"
	var port: int = 443 if use_tls else 80
	var colon: int = host.rfind(":")
	if colon > 0:
		port = int(host.substr(colon + 1))
		host = host.substr(0, colon)
	if use_http and host.to_lower() not in ["127.0.0.1", "localhost"]:
		return {"ok": false, "error": "http:// allowed only for localhost"}
	return {"ok": true, "host": host, "port": port, "path": path, "use_tls": use_tls}

static func _timed_out(start_ms: int, timeout_ms: int) -> bool:
	return Time.get_ticks_msec() - start_ms > timeout_ms
