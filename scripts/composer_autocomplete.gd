extends RefCounted

# Composer autocomplete: triggers, slash commands, helpers / Autocompletado del composer

func detect_trigger(text: String, caret_line: int, caret_col: int) -> Dictionary:
	var lines: PackedStringArray = text.split("\n")
	if caret_line < 0 or caret_line >= lines.size():
		return {"active": false}
	var line: String = lines[caret_line]
	var before: String = line.substr(0, mini(caret_col, line.length()))
	
	var at_index: int = before.rfind("@")
	if at_index >= 0:
		var query: String = before.substr(at_index + 1)
		if " " not in query and "\t" not in query:
			return {
				"active": true,
				"mode": "mention",
				"query": query,
				"start_col": at_index,
				"caret_line": caret_line,
				"caret_col": caret_col
			}
	
	var slash_index: int = before.rfind("/")
	if slash_index >= 0:
		var query_slash: String = before.substr(slash_index + 1)
		if " " not in query_slash and "\t" not in query_slash:
			if slash_index == 0 or before.substr(slash_index - 1, 1) in [" ", "\t"]:
				return {
					"active": true,
					"mode": "command",
					"query": query_slash,
					"start_col": slash_index,
					"caret_line": caret_line,
					"caret_col": caret_col
				}
	return {"active": false}

func insert_selection(text: String, trigger: Dictionary, insert_value: String) -> Dictionary:
	var lines: PackedStringArray = text.split("\n")
	var caret_line: int = int(trigger.get("caret_line", 0))
	var caret_col: int = int(trigger.get("caret_col", 0))
	var start_col: int = int(trigger.get("start_col", 0))
	if caret_line < 0 or caret_line >= lines.size():
		return {"text": text, "caret_line": caret_line, "caret_col": caret_col}
	var line: String = lines[caret_line]
	var prefix: String = line.substr(0, start_col)
	var suffix: String = line.substr(caret_col)
	var spacer: String = " " if not suffix.is_empty() and not suffix.begins_with(" ") else ""
	lines[caret_line] = prefix + insert_value + spacer + suffix
	return {
		"text": "\n".join(lines),
		"caret_line": caret_line,
		"caret_col": prefix.length() + insert_value.length() + spacer.length()
	}

func get_slash_suggestions(query: String, locale_manager: RefCounted, skills_manager: RefCounted) -> Array:
	var normalized: String = query.to_lower().strip_edges()
	var results: Array = []
	var commands: Array = _command_definitions()
	for command_def in commands:
		if command_def is Dictionary:
			if _matches_query(normalized, command_def):
				results.append(_build_entry(command_def, locale_manager))
	
	if skills_manager and (normalized.is_empty() or normalized.begins_with("skill") or normalized == "sk"):
		for skill_id in skills_manager.get_skill_ids():
			var skill_insert: String = "/skill %s" % skill_id
			if normalized.is_empty() or normalized in skill_insert.to_lower() or skill_id.to_lower().begins_with(normalized.replace("skill", "").strip_edges()):
				var preview: String = skill_id
				if skills_manager.has_method("get_skill_preview"):
					preview = String(skills_manager.get_skill_preview(skill_id))
				results.append({
					"category": "skills",
					"insert": skill_insert,
					"title": skill_insert,
					"description": preview,
					"kind": "command"
				})
	return results.slice(0, 24)

func _command_definitions() -> Array:
	return [
		{"category": "chat", "match": "help", "insert": "/help", "desc_key": "ac.cmd.help"},
		{"category": "chat", "match": "clear", "insert": "/clear", "desc_key": "ac.cmd.clear"},
		{"category": "chat", "match": "new", "insert": "/new", "desc_key": "ac.cmd.new"},
		{"category": "chat", "match": "history", "insert": "/history", "desc_key": "ac.cmd.history"},
		{"category": "skills", "match": "skill", "insert": "/skill", "desc_key": "ac.cmd.skill"},
		{"category": "skills", "match": "skills", "insert": "/skills", "desc_key": "ac.cmd.skills"},
		{"category": "context", "match": "context", "insert": "/context", "desc_key": "ac.cmd.context"},
		{"category": "models", "match": "models", "insert": "/models", "desc_key": "ac.cmd.models"},
	]

func _matches_query(normalized: String, command_def: Dictionary) -> bool:
	if normalized.is_empty():
		return true
	var match_key: String = String(command_def.get("match", ""))
	var insert: String = String(command_def.get("insert", "")).to_lower().substr(1)
	return match_key.begins_with(normalized) or normalized.begins_with(match_key) or insert.begins_with(normalized)

func _build_entry(command_def: Dictionary, locale_manager: RefCounted) -> Dictionary:
	var insert: String = String(command_def.get("insert", ""))
	var desc_key: String = String(command_def.get("desc_key", ""))
	var description: String = desc_key
	if locale_manager and locale_manager.has_method("get_text"):
		description = locale_manager.get_text(desc_key)
	return {
		"category": String(command_def.get("category", "commands")),
		"insert": insert,
		"title": insert,
		"description": description,
		"kind": "command"
	}
