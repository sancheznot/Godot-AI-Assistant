extends RefCounted

# Obsidian vault access (folder or Local REST API) / Acceso al vault de Obsidian
# ponytail: two backends, one config switch — folder scan or REST plugin

const HttpSyncUtil := preload("res://addons/ai_assistant_plugin/scripts/http_sync_util.gd")

const BACKEND_FOLDER := "folder"
const BACKEND_REST := "rest"
const DEFAULT_REST_URL := "https://127.0.0.1:27124"
const REST_TIMEOUT_MS := 30000
const MAX_NOTE_BYTES := 512 * 1024
const SKIP_DIRS := [".obsidian", ".trash", ".git"]

var _config_manager: RefCounted = null

func setup(config_manager: RefCounted) -> void:
	_config_manager = config_manager

func search(query: String, limit: int = -1) -> Dictionary:
	var normalized_query: String = query.strip_edges()
	if normalized_query.is_empty():
		return {"ok": false, "error": "query is required"}
	if _config_manager == null:
		return {"ok": false, "error": "Config manager not initialized"}
	if not bool(_config_manager.get_setting("enable_obsidian", false)):
		return {"ok": false, "error": "Obsidian integration is disabled in Config → Settings"}
	var max_results: int = limit
	if max_results <= 0:
		max_results = clampi(int(_config_manager.get_setting("obsidian_max_results", 12)), 1, 30)
	match _backend():
		BACKEND_FOLDER:
			return _search_folder(normalized_query, max_results)
		BACKEND_REST:
			return _search_rest(normalized_query, max_results)
	return {"ok": false, "error": "Unknown obsidian_backend"}

func read_note(note_path: String, max_chars: int = 12000) -> Dictionary:
	var normalized_path: String = _normalize_note_path(note_path)
	if normalized_path.is_empty():
		return {"ok": false, "error": "path is required (vault-relative, e.g. Golem-AI/ideas.md)"}
	if _config_manager == null:
		return {"ok": false, "error": "Config manager not initialized"}
	if not bool(_config_manager.get_setting("enable_obsidian", false)):
		return {"ok": false, "error": "Obsidian integration is disabled in Config → Settings"}
	var char_limit: int = clampi(max_chars, 500, 48000)
	match _backend():
		BACKEND_FOLDER:
			return _read_folder(normalized_path, char_limit)
		BACKEND_REST:
			return _read_rest(normalized_path, char_limit)
	return {"ok": false, "error": "Unknown obsidian_backend"}

func _backend() -> String:
	var backend: String = String(_config_manager.get_setting("obsidian_backend", BACKEND_FOLDER)).strip_edges().to_lower()
	if backend not in [BACKEND_FOLDER, BACKEND_REST]:
		backend = BACKEND_FOLDER
	return backend

func _search_folder(query: String, limit: int) -> Dictionary:
	var vault_root := _vault_root_path()
	if vault_root.is_empty():
		return {"ok": false, "error": "Set obsidian_vault_path in Config → Settings (absolute path to your vault folder)"}
	if not DirAccess.dir_exists_absolute(vault_root):
		return {"ok": false, "error": "Vault folder not found: %s" % vault_root}
	var needle: String = query.to_lower()
	var results: Array = []
	_collect_folder_matches(vault_root, vault_root, needle, results, limit)
	return {
		"ok": true,
		"backend": BACKEND_FOLDER,
		"query": query,
		"results": results,
	}

func _read_folder(note_path: String, max_chars: int) -> Dictionary:
	var resolved := _resolve_vault_file(note_path)
	if not bool(resolved.get("ok", false)):
		return resolved
	var abs_path: String = String(resolved.get("abs_path", ""))
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not read note: %s" % note_path}
	var content: String = file.get_as_text()
	file.close()
	return {
		"ok": true,
		"backend": BACKEND_FOLDER,
		"path": String(resolved.get("rel_path", note_path)),
		"content": content.substr(0, max_chars),
		"truncated": content.length() > max_chars,
	}

func _search_rest(query: String, limit: int) -> Dictionary:
	var api_key: String = _rest_api_key()
	if api_key.is_empty():
		return {
			"ok": false,
			"error": "Missing Obsidian REST API key. Copy it from Obsidian → Local REST API settings, or set %s" % [
				_config_manager.get_obsidian_rest_api_key_env_var(),
			],
		}
	var base_url: String = _rest_base_url()
	var path: String = "/search/simple/?query=%s&contextLength=120" % query.uri_encode()
	var headers: PackedStringArray = [
		"Authorization: Bearer %s" % api_key,
		"Accept: application/json",
	]
	var http_result: Dictionary = HttpSyncUtil.request(
		base_url + path,
		headers,
		HTTPClient.METHOD_POST,
		"",
		REST_TIMEOUT_MS,
		_use_insecure_tls(base_url)
	)
	if not bool(http_result.get("ok", false)):
		return _rest_error(http_result)
	var parsed: Variant = JSON.parse_string(String(http_result.get("body_text", "")))
	if not parsed is Array:
		return {"ok": false, "error": "Invalid Obsidian search JSON"}
	var results: Array = []
	for item in parsed:
		if not item is Dictionary or results.size() >= limit:
			break
		var entry: Dictionary = item as Dictionary
		var snippet: String = ""
		for match_entry in entry.get("matches", []):
			if match_entry is Dictionary:
				snippet = String(match_entry.get("context", ""))
				break
		results.append({
			"path": String(entry.get("filename", "")),
			"score": entry.get("score", 0),
			"snippet": snippet,
		})
	return {"ok": true, "backend": BACKEND_REST, "query": query, "results": results}

func _read_rest(note_path: String, max_chars: int) -> Dictionary:
	var api_key: String = _rest_api_key()
	if api_key.is_empty():
		return {
			"ok": false,
			"error": "Missing Obsidian REST API key. Copy it from Obsidian → Local REST API settings, or set %s" % [
				_config_manager.get_obsidian_rest_api_key_env_var(),
			],
		}
	var base_url: String = _rest_base_url()
	var api_path: String = _vault_api_path(note_path)
	var headers: PackedStringArray = [
		"Authorization: Bearer %s" % api_key,
		"Accept: text/markdown",
	]
	var http_result: Dictionary = HttpSyncUtil.request(
		base_url + api_path,
		headers,
		HTTPClient.METHOD_GET,
		"",
		REST_TIMEOUT_MS,
		_use_insecure_tls(base_url)
	)
	if not bool(http_result.get("ok", false)):
		return _rest_error(http_result)
	var content: String = String(http_result.get("body_text", ""))
	return {
		"ok": true,
		"backend": BACKEND_REST,
		"path": note_path,
		"content": content.substr(0, max_chars),
		"truncated": content.length() > max_chars,
	}

func _collect_folder_matches(
	root: String,
	current: String,
	needle: String,
	results: Array,
	limit: int
) -> void:
	if results.size() >= limit:
		return
	var dir := DirAccess.open(current)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if entry_name.begins_with("."):
			entry_name = dir.get_next()
			continue
		var full_path: String = current.path_join(entry_name)
		if dir.current_is_dir():
			if entry_name in SKIP_DIRS:
				entry_name = dir.get_next()
				continue
			_collect_folder_matches(root, full_path, needle, results, limit)
		elif entry_name.to_lower().ends_with(".md"):
			var rel_path: String = full_path.substr(root.length()).trim_prefix("/").trim_prefix("\\")
			var name_hit: bool = entry_name.to_lower().contains(needle) or rel_path.to_lower().contains(needle)
			var match_info: Dictionary = _file_match(full_path, needle)
			if name_hit or bool(match_info.get("ok", false)):
				results.append({
					"path": rel_path,
					"snippet": String(match_info.get("snippet", "")),
				})
				if results.size() >= limit:
					dir.list_dir_end()
					return
		entry_name = dir.get_next()
	dir.list_dir_end()

func _file_match(path: String, needle: String) -> Dictionary:
	if FileAccess.get_file_as_bytes(path).size() > MAX_NOTE_BYTES:
		return {"ok": false}
	var text: String = FileAccess.get_file_as_string(path)
	var idx: int = text.to_lower().find(needle)
	if idx < 0:
		return {"ok": false}
	var start: int = maxi(0, idx - 60)
	var end: int = mini(text.length(), idx + needle.length() + 60)
	return {"ok": true, "snippet": text.substr(start, end - start).replace("\n", " ")}

func _resolve_vault_file(note_path: String) -> Dictionary:
	var vault_root := _vault_root_path()
	if vault_root.is_empty():
		return {"ok": false, "error": "Set obsidian_vault_path in Config → Settings"}
	if not DirAccess.dir_exists_absolute(vault_root):
		return {"ok": false, "error": "Vault folder not found: %s" % vault_root}
	var rel: String = _normalize_note_path(note_path)
	var abs_path: String = vault_root.path_join(rel).replace("\\", "/")
	var root_norm: String = vault_root.replace("\\", "/").trim_suffix("/")
	if not abs_path.begins_with(root_norm + "/"):
		return {"ok": false, "error": "Invalid note path"}
	if not FileAccess.file_exists(abs_path):
		return {"ok": false, "error": "Note not found: %s" % rel}
	return {"ok": true, "abs_path": abs_path, "rel_path": rel}

func _vault_root_path() -> String:
	var raw: String = String(_config_manager.get_setting("obsidian_vault_path", "")).strip_edges()
	if raw.is_empty():
		return ""
	if raw.begins_with("~"):
		raw = OS.get_environment("HOME").path_join(raw.substr(1).trim_prefix("/"))
	return raw.replace("\\", "/").trim_suffix("/")

func _normalize_note_path(note_path: String) -> String:
	var rel: String = note_path.strip_edges().trim_prefix("/").replace("\\", "/")
	if rel.is_empty():
		return ""
	if not rel.to_lower().ends_with(".md"):
		rel += ".md"
	return rel

func _rest_base_url() -> String:
	var raw: String = String(_config_manager.get_setting("obsidian_rest_url", DEFAULT_REST_URL)).strip_edges()
	if raw.is_empty():
		raw = DEFAULT_REST_URL
	return raw.trim_suffix("/")

func _rest_api_key() -> String:
	# Quitar "Bearer " si el usuario lo pegó por error / Strip "Bearer " if pasted by mistake
	var raw: String = _config_manager.get_obsidian_rest_api_key()
	if raw.begins_with("Bearer "):
		raw = raw.substr(7)
	return raw.strip_edges()

func _vault_api_path(note_path: String) -> String:
	var rel: String = _normalize_note_path(note_path)
	var parts: PackedStringArray = rel.split("/")
	for i in parts.size():
		parts[i] = String(parts[i]).uri_encode()
	return "/vault/" + "/".join(parts)

func _use_insecure_tls(base_url: String) -> bool:
	return base_url.begins_with("https://127.0.0.1") or base_url.begins_with("https://localhost")

func _rest_error(http_result: Dictionary) -> Dictionary:
	var err: String = String(http_result.get("error", "Obsidian REST request failed"))
	return {
		"ok": false,
		"error": "%s. Is Obsidian open with Local REST API enabled?" % err,
	}
