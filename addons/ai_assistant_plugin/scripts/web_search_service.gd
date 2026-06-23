extends RefCounted

# Web search for agent tools (Serper, Brave) / Búsqueda web para tools del agente

const SERPER_WEB_URL := "https://google.serper.dev/search"
const SERPER_IMAGES_URL := "https://google.serper.dev/images"
const BRAVE_WEB_URL := "https://api.search.brave.com/res/v1/web/search"
const BRAVE_IMAGES_URL := "https://api.search.brave.com/res/v1/images/search"
const HTTP_TIMEOUT_MS := 60000

const HttpSyncUtil := preload("res://addons/ai_assistant_plugin/scripts/http_sync_util.gd")

const PROVIDER_SERPER := "serper"
const PROVIDER_BRAVE := "brave"

var _editor_plugin: EditorPlugin = null
var _config_manager: RefCounted = null

func setup(editor_plugin: EditorPlugin, config_manager: RefCounted) -> void:
	_editor_plugin = editor_plugin
	_config_manager = config_manager

func search(query: String, mode: String = "web", limit: int = -1) -> Dictionary:
	var normalized_query: String = query.strip_edges()
	if normalized_query.is_empty():
		return {"ok": false, "error": "query is required"}
	if _config_manager == null:
		return {"ok": false, "error": "Config manager not initialized"}
	if not bool(_config_manager.get_setting("enable_web_search", true)):
		return {"ok": false, "error": "Web search is disabled in Config → Settings"}
	var provider: String = String(_config_manager.get_setting("web_search_provider", PROVIDER_SERPER)).strip_edges().to_lower()
	if provider not in [PROVIDER_SERPER, PROVIDER_BRAVE]:
		provider = PROVIDER_SERPER
	var api_key: String = _config_manager.get_web_search_api_key(provider)
	if api_key.is_empty():
		return {
			"ok": false,
			"error": "Missing API key for %s. Set it in Config → Settings or %s" % [
				provider,
				_config_manager.get_web_search_api_key_env_var(provider),
			],
		}
	var max_results: int = limit
	if max_results <= 0:
		max_results = clampi(int(_config_manager.get_setting("web_search_max_results", 8)), 1, 20)
	var search_mode: String = mode.strip_edges().to_lower()
	if search_mode not in ["web", "images"]:
		search_mode = "web"
	match provider:
		PROVIDER_SERPER:
			return _search_serper(normalized_query, search_mode, max_results, api_key)
		PROVIDER_BRAVE:
			return _search_brave(normalized_query, search_mode, max_results, api_key)
	return {"ok": false, "error": "Unknown provider: %s" % provider}

func _search_serper(query: String, mode: String, limit: int, api_key: String) -> Dictionary:
	var url: String = SERPER_IMAGES_URL if mode == "images" else SERPER_WEB_URL
	var body: String = JSON.stringify({"q": query, "num": limit})
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-API-KEY: %s" % api_key,
	]
	var http_result: Dictionary = _http_request_sync(url, headers, HTTPClient.METHOD_POST, body)
	if not bool(http_result.get("ok", false)):
		return http_result
	var parsed: Variant = JSON.parse_string(String(http_result.get("body_text", "")))
	if not parsed is Dictionary:
		return {"ok": false, "error": "Invalid Serper JSON response"}
	return {
		"ok": true,
		"provider": PROVIDER_SERPER,
		"mode": mode,
		"query": query,
		"results": _parse_serper_results(parsed as Dictionary, mode),
	}

func _search_brave(query: String, mode: String, limit: int, api_key: String) -> Dictionary:
	var base_url: String = BRAVE_IMAGES_URL if mode == "images" else BRAVE_WEB_URL
	var url: String = "%s?q=%s&count=%d" % [base_url, query.uri_encode(), limit]
	var headers: PackedStringArray = [
		"Accept: application/json",
		"X-Subscription-Token: %s" % api_key,
	]
	var http_result: Dictionary = _http_request_sync(url, headers, HTTPClient.METHOD_GET, "")
	if not bool(http_result.get("ok", false)):
		return http_result
	var parsed: Variant = JSON.parse_string(String(http_result.get("body_text", "")))
	if not parsed is Dictionary:
		return {"ok": false, "error": "Invalid Brave JSON response"}
	return {
		"ok": true,
		"provider": PROVIDER_BRAVE,
		"mode": mode,
		"query": query,
		"results": _parse_brave_results(parsed as Dictionary, mode),
	}

func _parse_serper_results(data: Dictionary, mode: String) -> Array:
	var out: Array = []
	if mode == "images":
		for item in data.get("images", []):
			if not item is Dictionary:
				continue
			out.append({
				"title": String(item.get("title", "")),
				"url": String(item.get("link", item.get("imageUrl", ""))),
				"image_url": String(item.get("imageUrl", "")),
				"snippet": String(item.get("source", "")),
			})
	else:
		for item in data.get("organic", []):
			if not item is Dictionary:
				continue
			out.append({
				"title": String(item.get("title", "")),
				"url": String(item.get("link", "")),
				"snippet": String(item.get("snippet", "")),
			})
	return out

func _parse_brave_results(data: Dictionary, mode: String) -> Array:
	var out: Array = []
	if mode == "images":
		for item in data.get("results", []):
			if not item is Dictionary:
				continue
			var props: Dictionary = item.get("properties", {})
			var thumb: Dictionary = item.get("thumbnail", {})
			out.append({
				"title": String(item.get("title", "")),
				"url": String(item.get("url", props.get("url", ""))),
				"image_url": String(props.get("url", thumb.get("src", ""))),
				"snippet": String(item.get("source", "")),
			})
	else:
		var web: Dictionary = data.get("web", {})
		for item in web.get("results", []):
			if not item is Dictionary:
				continue
			out.append({
				"title": String(item.get("title", "")),
				"url": String(item.get("url", "")),
				"snippet": String(item.get("description", "")),
			})
	return out

func _http_request_sync(
	url: String,
	headers: PackedStringArray,
	method: HTTPClient.Method,
	body: String
) -> Dictionary:
	var http_result: Dictionary = HttpSyncUtil.request(url, headers, method, body, HTTP_TIMEOUT_MS)
	if not bool(http_result.get("ok", false)):
		return http_result
	return {"ok": true, "body_text": String(http_result.get("body_text", ""))}
