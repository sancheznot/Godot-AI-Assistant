extends RefCounted

# Resolves @mentions and project file search / Resuelve menciones @ y búsqueda de archivos

const MAX_ATTACHMENT_CHARS := 6000
const INDEX_EXTENSIONS := [".gd", ".tscn", ".cs", ".md", ".json", ".cfg", ".tres", ".import"]

var project_context: RefCounted = null
var skills_manager: RefCounted = null
var _file_index: Array = []

func setup(context_builder: RefCounted, skills: RefCounted) -> void:
	project_context = context_builder
	skills_manager = skills
	rebuild_index()

func rebuild_index() -> void:
	_file_index.clear()
	_scan_directory("res://")

func search(query: String, locale_manager: RefCounted = null, limit: int = 24) -> Array:
	var normalized: String = query.to_lower().strip_edges()
	var results: Array = []
	if normalized.is_empty() or normalized in ["sc", "scen", "scene", "escena"]:
		results.append_array(_context_mentions(locale_manager))
	if skills_manager and (normalized.is_empty() or normalized.begins_with("skill") or normalized.begins_with("sk")):
		results.append_array(_skill_mentions(normalized))
	for entry in _file_index:
		if results.size() >= limit:
			break
		if entry is Dictionary:
			var path: String = String(entry.get("path", ""))
			var label: String = String(entry.get("label", path))
			if normalized.is_empty() or normalized in path.to_lower() or normalized in label.to_lower():
				results.append(_file_entry(entry, locale_manager))
	return _sort_and_limit(results, limit)

func _context_mentions(locale_manager: RefCounted) -> Array:
	var desc_scene: String = _L(locale_manager, "ac.mention.scene", "Current open scene")
	var desc_selection: String = _L(locale_manager, "ac.mention.selection", "Selected nodes in editor")
	return [
		{"category": "context", "insert": "@scene", "title": "@scene", "description": desc_scene, "kind": "mention"},
		{"category": "context", "insert": "@selection", "title": "@selection", "description": desc_selection, "kind": "mention"},
	]

func _skill_mentions(normalized: String) -> Array:
	var results: Array = []
	for skill_id in skills_manager.get_skill_ids():
		var skill_filter: String = normalized.replace("skill", "").strip_edges()
		if not normalized.is_empty() and not skill_filter.is_empty() and not skill_id.to_lower().contains(skill_filter):
			continue
		results.append({
			"category": "skills",
			"insert": "@skill:%s" % skill_id,
			"title": "@skill:%s" % skill_id,
			"description": skills_manager.get_skill_label(skill_id),
			"kind": "mention"
		})
	return results

func _file_entry(entry: Dictionary, locale_manager: RefCounted) -> Dictionary:
	var path: String = String(entry.get("path", ""))
	var category: String = "files"
	var desc: String = _L(locale_manager, "ac.mention.file", "Attach file content")
	if path.ends_with(".tscn"):
		category = "scenes"
		desc = _L(locale_manager, "ac.mention.scene_file", "Scene file reference")
	elif path.ends_with(".gd") or path.ends_with(".cs"):
		category = "scripts"
		desc = _L(locale_manager, "ac.mention.script_file", "Script file reference")
	elif path.ends_with(".md"):
		desc = _L(locale_manager, "ac.mention.doc_file", "Documentation reference")
	return {
		"category": category,
		"insert": String(entry.get("insert", "@%s" % path)),
		"title": String(entry.get("label", path.replace("res://", ""))),
		"description": desc,
		"kind": "mention",
		"path": path
	}

func _sort_and_limit(results: Array, limit: int) -> Array:
	var order: Dictionary = {"context": 0, "skills": 1, "scenes": 2, "scripts": 3, "files": 4}
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: int = int(order.get(String(a.get("category", "files")), 9))
		var cb: int = int(order.get(String(b.get("category", "files")), 9))
		if ca == cb:
			return String(a.get("title", "")) < String(b.get("title", ""))
		return ca < cb
	)
	return results.slice(0, limit)

func _L(locale_manager: RefCounted, key: String, fallback: String) -> String:
	if locale_manager and locale_manager.has_method("get_text"):
		var text: String = locale_manager.get_text(key)
		if text != key:
			return text
	return fallback

func insert_mention(current_text: String, caret_line: int, caret_col: int, mention_value: String) -> Dictionary:
	var lines: PackedStringArray = current_text.split("\n", false)
	if caret_line < 0 or caret_line >= lines.size():
		return {"text": current_text, "caret": caret_col}
	var line: String = lines[caret_line]
	var before: String = line.substr(0, caret_col)
	var after: String = line.substr(caret_col)
	var at_index: int = before.rfind("@")
	if at_index == -1:
		lines[caret_line] = before + mention_value + " " + after
		return {
			"text": "\n".join(lines),
			"caret_line": caret_line,
			"caret_col": before.length() + mention_value.length() + 1
		}
	var prefix: String = before.substr(0, at_index)
	lines[caret_line] = prefix + mention_value + " " + after
	return {
		"text": "\n".join(lines),
		"caret_line": caret_line,
		"caret_col": prefix.length() + mention_value.length() + 1
	}

func get_active_mention_query(text: String, caret_line: int, caret_col: int) -> Dictionary:
	var lines: PackedStringArray = text.split("\n", false)
	if caret_line < 0 or caret_line >= lines.size():
		return {"active": false}
	var line: String = lines[caret_line]
	var before: String = line.substr(0, mini(caret_col, line.length()))
	var at_index: int = before.rfind("@")
	if at_index == -1:
		return {"active": false}
	var query: String = before.substr(at_index + 1)
	if " " in query or "\t" in query:
		return {"active": false}
	return {"active": true, "query": query, "start_col": at_index}

func build_attached_context(prompt: String) -> String:
	var sections: PackedStringArray = []
	for token in _extract_mention_tokens(prompt):
		var section: String = _resolve_token(token)
		if not section.is_empty():
			sections.append(section)
	return "\n\n".join(sections)

func _extract_mention_tokens(text: String) -> PackedStringArray:
	var tokens: PackedStringArray = []
	var regex := RegEx.new()
	regex.compile("@[A-Za-z0-9_./:-]+")
	for match_result in regex.search_all(text):
		var token: String = match_result.get_string()
		if not tokens.has(token):
			tokens.append(token)
	return tokens

func _resolve_token(token: String) -> String:
	match token:
		"@scene", "@escena":
			return _resolve_current_scene()
		"@selection", "@seleccion":
			return _resolve_selection()
		_:
			if token.begins_with("@skill:"):
				return _resolve_skill(token.substr(7))
			if token.begins_with("@res://"):
				return _resolve_file(token.substr(1))
			if token.begins_with("@"):
				return _resolve_file("res://" + token.substr(1))
	return ""

func _resolve_current_scene() -> String:
	if project_context == null or not project_context.has_method("get_current_scene_summary"):
		return ""
	return "## @scene\n%s" % String(project_context.get_current_scene_summary())

func _resolve_selection() -> String:
	if project_context == null or not project_context.has_method("get_selection_summary"):
		return ""
	return "## @selection\n%s" % String(project_context.get_selection_summary())

func _resolve_skill(skill_id: String) -> String:
	if skills_manager == null:
		return ""
	if skills_manager.has_method("get_skill_content"):
		var content: String = String(skills_manager.get_skill_content(skill_id))
		if content.is_empty():
			return "## @skill:%s\nSkill not found." % skill_id
		return "## @skill:%s\n%s" % [skill_id, content]
	return ""

func _resolve_file(path: String) -> String:
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return "## %s\nFile not found." % path
	var text: String = _read_text_file(path)
	if text.is_empty() and not path.ends_with(".tscn"):
		return "## %s\n(empty or unreadable)" % path
	if path.ends_with(".gd") or path.ends_with(".cs"):
		return "## Attached script: %s\n```gdscript\n%s\n```" % [path, text.substr(0, MAX_ATTACHMENT_CHARS)]
	if path.ends_with(".md"):
		return "## Attached doc: %s\n%s" % [path, text.substr(0, MAX_ATTACHMENT_CHARS)]
	if path.ends_with(".tscn"):
		return "## Attached scene: %s\nUse editor tools to inspect nodes. Path: %s" % [path, path]
	return "## Attached file: %s\n%s" % [path, text.substr(0, MAX_ATTACHMENT_CHARS)]

func _scan_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path: String = path.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					_scan_directory(full_path)
			else:
				for ext in INDEX_EXTENSIONS:
					if entry.ends_with(ext):
						_file_index.append({
							"kind": "file",
							"path": full_path,
							"label": full_path.replace("res://", ""),
							"insert": "@%s" % full_path
						})
						break
		entry = dir.get_next()
	dir.list_dir_end()

func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
