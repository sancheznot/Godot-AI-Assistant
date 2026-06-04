extends RefCounted

# Local documentation index (project markdown + Godot ClassDB) / Índice de documentación local

const GODOT_URI_PREFIX := "godot:"
const PRIORITY_GODOT_CLASSES: PackedStringArray = [
	"Object", "Node", "Node2D", "Node3D", "Control", "Resource", "RefCounted",
	"CharacterBody2D", "CharacterBody3D", "RigidBody2D", "RigidBody3D", "StaticBody2D", "StaticBody3D",
	"Area2D", "Area3D", "CollisionShape2D", "CollisionShape3D", "Camera2D", "Camera3D",
	"MeshInstance2D", "MeshInstance3D", "Sprite2D", "AnimatedSprite2D", "AnimationPlayer",
	"Timer", "TileMapLayer", "MultiplayerAPI", "MultiplayerSpawner", "HTTPRequest",
	"PackedScene", "SceneTree", "Viewport", "Window", "CanvasLayer", "Label", "Button",
	"Input", "InputMap", "ProjectSettings", "EditorInterface", "EditorPlugin",
]

static func should_index_docs(config_manager: RefCounted) -> bool:
	if config_manager == null:
		return false
	if not bool(config_manager.get_setting("enable_project_index", true)):
		return false
	return bool(config_manager.get_setting("enable_docs_index", true))

static func build_docs_entries(
	config_manager: RefCounted,
	built: Dictionary,
	ignore_patterns: PackedStringArray,
	read_text: Callable,
	tokenize: Callable,
	should_ignore_dir: Callable,
	should_ignore_file: Callable
) -> Array:
	if not should_index_docs(config_manager):
		return []
	var max_entries: int = clampi(
		int(config_manager.get_setting("docs_max_entries", 600)),
		32,
		4000
	)
	var entries: Array = []
	if bool(config_manager.get_setting("docs_include_project_md", true)):
		_index_project_markdown(
			config_manager,
			entries,
			max_entries,
			ignore_patterns,
			read_text,
			tokenize,
			should_ignore_dir,
			should_ignore_file
		)
	if bool(config_manager.get_setting("docs_include_global_classes", true)):
		_index_global_script_classes(config_manager, entries, max_entries, read_text, tokenize)
	if bool(config_manager.get_setting("docs_include_godot_classes", true)):
		_index_godot_engine_classes(config_manager, built, entries, max_entries, tokenize)
	return entries.slice(0, max_entries)

static func _index_project_markdown(
	config_manager: RefCounted,
	entries: Array,
	max_entries: int,
	ignore_patterns: PackedStringArray,
	read_text: Callable,
	tokenize: Callable,
	should_ignore_dir: Callable,
	should_ignore_file: Callable
) -> void:
	var max_chars: int = clampi(int(config_manager.get_setting("docs_max_md_chars", 8000)), 1000, 50000)
	var chunk_size: int = clampi(int(config_manager.get_setting("docs_md_chunk_size", 1400)), 400, 6000)
	_scan_markdown_dir(
		"res://",
		entries,
		max_entries,
		max_chars,
		chunk_size,
		read_text,
		tokenize,
		should_ignore_dir,
		should_ignore_file
	)

static func _scan_markdown_dir(
	path: String,
	entries: Array,
	max_entries: int,
	max_chars: int,
	chunk_size: int,
	read_text: Callable,
	tokenize: Callable,
	should_ignore_dir: Callable,
	should_ignore_file: Callable
) -> void:
	if entries.size() >= max_entries:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if entries.size() >= max_entries:
			break
		if entry_name != "." and entry_name != "..":
			var full_path := path.path_join(entry_name)
			if dir.current_is_dir():
				if not should_ignore_dir.call(full_path, entry_name):
					_scan_markdown_dir(
						full_path,
						entries,
						max_entries,
						max_chars,
						chunk_size,
						read_text,
						tokenize,
						should_ignore_dir,
						should_ignore_file
					)
			elif entry_name.ends_with(".md") and not should_ignore_file.call(full_path, entry_name):
				var text: String = String(read_text.call(full_path))
				if text.is_empty():
					entry_name = dir.get_next()
					continue
				if text.length() > max_chars:
					text = text.substr(0, max_chars)
				var chunks: Array = _split_markdown_chunks(text, chunk_size)
				for chunk_idx in chunks.size():
					if entries.size() >= max_entries:
						break
					var chunk: Dictionary = chunks[chunk_idx]
					var body: String = String(chunk.get("text", ""))
					if body.strip_edges().is_empty():
						continue
					var title: String = String(chunk.get("title", full_path.get_file()))
					var doc_path: String = "%s#chunk:%d" % [full_path, chunk_idx]
					entries.append(_make_doc_entry(
						"project_md",
						doc_path,
						title,
						body,
						tokenize
					))
		entry_name = dir.get_next()
	dir.list_dir_end()

static func _split_markdown_chunks(text: String, chunk_size: int) -> Array:
	var sections: Array = []
	var current_title: String = "Document"
	var current_lines: PackedStringArray = []
	for line in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			if not current_lines.is_empty():
				sections.append({
					"title": current_title,
					"text": "\n".join(current_lines).strip_edges(),
				})
				current_lines.clear()
			current_title = trimmed.trim_prefix("#").strip_edges()
			current_lines.append(line)
		else:
			current_lines.append(line)
	if not current_lines.is_empty():
		sections.append({
			"title": current_title,
			"text": "\n".join(current_lines).strip_edges(),
		})
	var out: Array = []
	for section in sections:
		if not section is Dictionary:
			continue
		var body: String = String(section.get("text", ""))
		var title: String = String(section.get("title", "Document"))
		if body.length() <= chunk_size:
			out.append({"title": title, "text": body})
			continue
		var pos: int = 0
		var part: int = 0
		while pos < body.length():
			out.append({
				"title": "%s (part %d)" % [title, part + 1],
				"text": body.substr(pos, chunk_size),
			})
			pos += maxi(int(chunk_size * 0.75), 256)
			part += 1
			if part >= 12:
				break
	return out

static func _index_global_script_classes(
	config_manager: RefCounted,
	entries: Array,
	max_entries: int,
	read_text: Callable,
	tokenize: Callable
) -> void:
	var global_classes: Array = ProjectSettings.get_global_class_list()
	for item in global_classes:
		if entries.size() >= max_entries:
			break
		if not item is Dictionary:
			continue
		var cls_name: String = String(item.get("class", ""))
		var script_path: String = String(item.get("path", ""))
		if cls_name.is_empty() or script_path.is_empty():
			continue
		var base: String = String(item.get("base", ""))
		var script_text: String = String(read_text.call(script_path))
		var summary: String = _summarize_script_class(cls_name, base, script_path, script_text)
		entries.append(_make_doc_entry("global_class", script_path, cls_name, summary, tokenize))

static func _summarize_script_class(cls_name: String, base: String, script_path: String, script_text: String) -> String:
	var lines: PackedStringArray = [
		"Project script class %s extends %s" % [cls_name, base if not base.is_empty() else "RefCounted"],
		"Path: %s" % script_path,
	]
	var func_regex := RegEx.new()
	func_regex.compile("(?m)^\\s*func\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var funcs: PackedStringArray = []
	for match_result in func_regex.search_all(script_text):
		if funcs.size() >= 24:
			break
		funcs.append(match_result.get_string(1))
	if not funcs.is_empty():
		lines.append("Functions: %s" % ", ".join(funcs))
	var signal_regex := RegEx.new()
	signal_regex.compile("(?m)^\\s*signal\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var signal_names: PackedStringArray = []
	for match_result in signal_regex.search_all(script_text):
		if signal_names.size() >= 16:
			break
		signal_names.append(match_result.get_string(1))
	if not signal_names.is_empty():
		lines.append("Signals: %s" % ", ".join(signal_names))
	var preview: String = script_text.strip_edges()
	if preview.length() > 900:
		preview = preview.substr(0, 900)
	if not preview.is_empty():
		lines.append("Source preview:\n%s" % preview)
	return "\n".join(lines)

static func _index_godot_engine_classes(
	config_manager: RefCounted,
	built: Dictionary,
	entries: Array,
	max_entries: int,
	tokenize: Callable
) -> void:
	var class_limit: int = clampi(
		int(config_manager.get_setting("docs_godot_class_limit", 350)),
		16,
		2000
	)
	var ordered: PackedStringArray = _ordered_godot_classes(built, class_limit)
	for cls_name in ordered:
		if entries.size() >= max_entries:
			break
		if not ClassDB.class_exists(cls_name):
			continue
		var summary: String = _summarize_godot_class(cls_name)
		if summary.is_empty():
			continue
		entries.append(_make_doc_entry(
			"godot_class",
			"%s%s" % [GODOT_URI_PREFIX, cls_name],
			cls_name,
			summary,
			tokenize
		))

static func _ordered_godot_classes(built: Dictionary, class_limit: int) -> PackedStringArray:
	var ordered: PackedStringArray = []
	var seen: Dictionary = {}
	for cls_name in _collect_project_class_refs(built):
		if seen.has(cls_name):
			continue
		seen[cls_name] = true
		ordered.append(cls_name)
	for cls_name in PRIORITY_GODOT_CLASSES:
		if ordered.size() >= class_limit:
			break
		if seen.has(cls_name):
			continue
		if ClassDB.class_exists(cls_name):
			seen[cls_name] = true
			ordered.append(cls_name)
	for cls_name in ClassDB.get_class_list():
		if ordered.size() >= class_limit:
			break
		if seen.has(cls_name):
			continue
		seen[cls_name] = true
		ordered.append(cls_name)
	return ordered

static func _collect_project_class_refs(built: Dictionary) -> PackedStringArray:
	var refs: PackedStringArray = []
	var seen: Dictionary = {}
	for entry in built.get("files", []):
		if not entry is Dictionary:
			continue
		var path: String = String(entry.get("path", ""))
		if not path.ends_with(".gd"):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text: String = file.get_as_text()
		file.close()
		for cls_name in _extract_class_refs_from_gd(text):
			if not seen.has(cls_name):
				seen[cls_name] = true
				refs.append(cls_name)
	return refs

static func _extract_class_refs_from_gd(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var patterns: PackedStringArray = [
		"(?m)^\\s*extends\\s+([A-Za-z_][A-Za-z0-9_]*)",
		"(?m)\\b([A-Z][A-Za-z0-9_]*)\\s*:\\s",
		"(?m)\\bas\\s+([A-Z][A-Za-z0-9_]*)",
	]
	for pattern in patterns:
		var regex := RegEx.new()
		regex.compile(pattern)
		for match_result in regex.search_all(text):
			var cls_name: String = match_result.get_string(1)
			if cls_name in ["String", "Array", "Dictionary", "Vector2", "Vector3", "bool", "int", "float", "void"]:
				continue
			if ClassDB.class_exists(cls_name) and not out.has(cls_name):
				out.append(cls_name)
	return out

static func _summarize_godot_class(cls_name: String) -> String:
	if not ClassDB.class_exists(cls_name):
		return ""
	var parent: String = String(ClassDB.get_parent_class(cls_name))
	var lines: PackedStringArray = [
		"Godot engine class %s" % cls_name,
	]
	if not parent.is_empty():
		lines.append("Inherits: %s" % parent)
	var methods: PackedStringArray = []
	for method_info in ClassDB.class_get_method_list(cls_name):
		if not method_info is Dictionary:
			continue
		var method_name: String = String(method_info.get("name", ""))
		if method_name.is_empty() or method_name.begins_with("_"):
			continue
		if methods.size() >= 28:
			break
		methods.append(method_name)
	if not methods.is_empty():
		lines.append("Methods: %s" % ", ".join(methods))
	var properties: PackedStringArray = []
	for property_info in ClassDB.class_get_property_list(cls_name):
		if not property_info is Dictionary:
			continue
		var property_name: String = String(property_info.get("name", ""))
		if property_name.is_empty() or property_name.begins_with("_"):
			continue
		if properties.size() >= 24:
			break
		properties.append(property_name)
	if not properties.is_empty():
		lines.append("Properties: %s" % ", ".join(properties))
	var signal_names: PackedStringArray = []
	for signal_info in ClassDB.class_get_signal_list(cls_name):
		if not signal_info is Dictionary:
			continue
		var signal_name: String = String(signal_info.get("name", ""))
		if signal_name.is_empty():
			continue
		if signal_names.size() >= 16:
			break
		signal_names.append(signal_name)
	if not signal_names.is_empty():
		lines.append("Signals: %s" % ", ".join(signal_names))
	lines.append("Help topic: class_name:%s" % cls_name)
	return "\n".join(lines)

static func _make_doc_entry(
	source: String,
	path: String,
	title: String,
	text: String,
	tokenize: Callable
) -> Dictionary:
	var preview: String = text.strip_edges().substr(0, mini(200, text.length()))
	return {
		"kind": "doc",
		"source": source,
		"path": path,
		"title": title,
		"text": text.strip_edges(),
		"preview": preview,
		"tokens": tokenize.call("%s %s %s %s" % [source, title, path, text.substr(0, mini(800, text.length()))]),
	}

static func prompt_needs_docs(lower: String) -> bool:
	var keys: PackedStringArray = [
		"document", "doc", "api", "classdb", "extends", "signal", "property",
		"método", "metodo", "clase", "como funciona", "how does", "how to",
		"godot", "referencia", "reference", "help topic", "readme",
	]
	for key in keys:
		if lower.contains(key):
			return true
	return false
