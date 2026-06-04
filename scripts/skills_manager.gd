extends RefCounted

# Loads markdown skills for system prompts / Carga skills markdown para prompts

var skills: Dictionary = {}
var active_skill_id: String = ""

func load_skills(skills_path: String, active_skill: String = "") -> void:
	skills.clear()
	var dir := DirAccess.open(skills_path)
	if dir == null:
		push_warning("AI Assistant: skills folder not found at %s" % skills_path)
		return
	
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".md"):
			var skill_id := entry.get_basename()
			var file := FileAccess.open("%s/%s" % [skills_path, entry], FileAccess.READ)
			if file != null:
				skills[skill_id] = {
					"id": skill_id,
					"name": _humanize_skill_name(skill_id),
					"content": file.get_as_text()
				}
				file.close()
		entry = dir.get_next()
	dir.list_dir_end()
	
	if active_skill.is_empty() and not skills.is_empty():
		active_skill_id = skills.keys()[0]
	elif skills.has(active_skill):
		active_skill_id = active_skill
	elif not skills.is_empty():
		active_skill_id = skills.keys()[0]
	else:
		active_skill_id = ""

func get_skills_path_from_config(config_manager: RefCounted) -> String:
	if config_manager:
		return String(config_manager.get_setting("skills_path", "res://addons/ai_assistant_plugin/skills"))
	return "res://addons/ai_assistant_plugin/skills"

func is_skill_installed(skills_path: String, skill_id: String) -> bool:
	return FileAccess.file_exists("%s/%s.md" % [skills_path, skill_id])

func get_installed_skill_ids(skills_path: String) -> Array:
	var ids: Array = []
	var dir := DirAccess.open(skills_path)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".md"):
			ids.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids

func install_skill_file(skills_path: String, skill_id: String, content: String, make_active: bool = false) -> bool:
	var safe_id: String = _sanitize_skill_id(skill_id)
	if safe_id.is_empty() or content.strip_edges().is_empty():
		return false
	_ensure_skills_dir(skills_path)
	var target_path: String = "%s/%s.md" % [skills_path, safe_id]
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		push_warning("AI Assistant: could not write skill to %s" % target_path)
		return false
	file.store_string(content)
	file.close()
	skills[safe_id] = {
		"id": safe_id,
		"name": _humanize_skill_name(safe_id),
		"content": content
	}
	if make_active or active_skill_id.is_empty():
		active_skill_id = safe_id
	return true

func _sanitize_skill_id(raw_id: String) -> String:
	var clean: String = raw_id.strip_edges().to_lower()
	clean = clean.replace(" ", "-").replace("/", "-")
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_-]")
	clean = regex.sub(clean, "-", true)
	while "--" in clean:
		clean = clean.replace("--", "-")
	return clean.trim_prefix("-").trim_suffix("-")

func _ensure_skills_dir(skills_path: String) -> void:
	if DirAccess.dir_exists_absolute(skills_path):
		return
	DirAccess.make_dir_recursive_absolute(skills_path)

func get_skill_ids() -> Array:
	return skills.keys()

func get_skill_label(skill_id: String) -> String:
	if skills.has(skill_id):
		return String(skills[skill_id].name)
	return skill_id

func set_active_skill(skill_id: String) -> void:
	if skills.has(skill_id):
		active_skill_id = skill_id

func get_active_skill_content() -> String:
	if active_skill_id.is_empty() or not skills.has(active_skill_id):
		return ""
	return String(skills[active_skill_id].content)

func get_skill_content(skill_id: String) -> String:
	if not skills.has(skill_id):
		return ""
	return String(skills[skill_id].content)

func get_skills_catalog_prompt() -> String:
	if skills.is_empty():
		return ""
	var lines: PackedStringArray = [
		"## Installed skills",
		"Use `/skill <id>` or the Skills dropdown to activate one.",
		"When a skill is active, follow its instructions strictly."
	]
	for skill_id in skills.keys():
		var preview: String = _get_skill_preview(skill_id)
		var active_marker: String = " (active)" if skill_id == active_skill_id else ""
		lines.append("- %s%s: %s" % [skill_id, active_marker, preview])
	return "\n".join(lines)

func get_skill_preview(skill_id: String) -> String:
	return _get_skill_preview(skill_id)

func _get_skill_preview(skill_id: String) -> String:
	if not skills.has(skill_id):
		return ""
	var content: String = String(skills[skill_id].content)
	for line in content.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue
		if trimmed.length() > 100:
			return trimmed.substr(0, 97) + "..."
		return trimmed
	return String(skills[skill_id].name)

func _humanize_skill_name(skill_id: String) -> String:
	return skill_id.replace("_", " ").capitalize()
