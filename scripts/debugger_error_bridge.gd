@tool
extends EditorDebuggerPlugin

# Captures debugger errors for Golem-AI tools / Captura errores del debugger para tools de Golem-AI

const MAX_STORED := 128

var _entries: Array = []
var _editor_plugin: EditorPlugin = null

func setup(editor_plugin: EditorPlugin) -> void:
	_editor_plugin = editor_plugin

func _has_capture(capture: String) -> bool:
	return capture == "error"

func _capture(message: String, data: Array, session_id: int) -> bool:
	if message != "error":
		return false
	var entry: Dictionary = _parse_error_payload(data)
	if not String(entry.get("summary", "")).is_empty():
		_entries.append(entry)
		if _entries.size() > MAX_STORED:
			_entries.pop_front()
	return false

func fetch_errors(clear_after: bool = true, max_count: int = 25) -> Array:
	var merged: Array = []
	var seen: Dictionary = {}
	for entry in _entries:
		var key: String = String(entry.get("summary", ""))
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		merged.append(entry)
	for entry in _scrape_debugger_error_tree(max_count):
		var key: String = String(entry.get("summary", ""))
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		merged.append(entry)
	var output: Array = merged.slice(0, maxi(max_count, 1))
	if clear_after:
		_entries.clear()
		_try_clear_debugger_panel()
	return output

func _parse_error_payload(data: Array) -> Dictionary:
	var entry: Dictionary = {
		"summary": "",
		"source_file": "",
		"source_line": 0,
		"source_func": "",
		"error": "",
		"warning": false,
	}
	if data.is_empty():
		return entry
	if data[0] is Dictionary:
		var payload: Dictionary = data[0]
		entry["source_file"] = String(payload.get("source_file", payload.get("file", "")))
		entry["source_func"] = String(payload.get("source_func", payload.get("function", "")))
		entry["source_line"] = int(payload.get("source_line", payload.get("line", 0)))
		entry["error"] = String(payload.get("error_descr", payload.get("error", payload.get("message", ""))))
		entry["warning"] = bool(payload.get("warning", false))
	elif data.size() >= 4:
		entry["source_file"] = String(data[0])
		entry["source_func"] = String(data[1])
		entry["source_line"] = int(data[2])
		entry["error"] = String(data[3])
		if data.size() >= 5:
			var descr: String = String(data[4])
			if not descr.is_empty():
				entry["error"] = descr
		if data.size() >= 6:
			entry["warning"] = bool(data[5])
	if entry["error"].is_empty() and data.size() > 0:
		entry["error"] = str(data)
	if not entry["source_file"].is_empty() and entry["source_line"] > 0:
		entry["summary"] = "%s:%d @ %s(): %s" % [
			entry["source_file"],
			entry["source_line"],
			entry["source_func"],
			entry["error"],
		]
	elif not entry["source_func"].is_empty():
		entry["summary"] = "%s(): %s" % [entry["source_func"], entry["error"]]
	else:
		entry["summary"] = entry["error"]
	return entry

func _get_script_editor_debugger() -> Node:
	if _editor_plugin == null:
		return null
	var ei: EditorInterface = _editor_plugin.get_editor_interface()
	if ei == null:
		return null
	var script_editor: Node = ei.get_script_editor()
	if script_editor == null or not script_editor.has_method("get_debugger"):
		return null
	return script_editor.get_debugger()

func _scrape_debugger_error_tree(max_count: int) -> Array:
	var debugger: Node = _get_script_editor_debugger()
	if debugger == null:
		return []
	var errors: Array = []
	for tree in _find_nodes_of_type(debugger, Tree):
		var tree_root: TreeItem = tree.get_root()
		if tree_root == null:
			continue
		var item: TreeItem = tree_root.get_first_child()
		while item != null and errors.size() < max_count:
			var summary: String = String(item.get_text(1))
			if summary.is_empty():
				summary = String(item.get_text(0))
			if summary.is_empty():
				item = item.get_next()
				continue
			errors.append({
				"summary": summary,
				"source": "debugger_ui",
			})
			item = item.get_next()
	return errors

func _try_clear_debugger_panel() -> void:
	var debugger: Node = _get_script_editor_debugger()
	if debugger == null:
		return
	for btn in _find_nodes_of_type(debugger, Button):
		var label: String = btn.text.strip_edges().to_lower()
		if label in ["clear", "limpiar", "borrar"]:
			btn.pressed.emit()
			return

func _find_nodes_of_type(root: Node, type) -> Array:
	var found: Array = []
	if is_instance_of(root, type):
		found.append(root)
	for child in root.get_children():
		found.append_array(_find_nodes_of_type(child, type))
	return found
