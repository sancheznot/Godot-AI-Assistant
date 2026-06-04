extends RefCounted

# Prompt harness: base + thinking + context + tools + skills + agent / Capas del harness

const DEFAULT_BASE_CONTEXT_PATH := "res://addons/ai_assistant_plugin/harness/base_context.md"
const DEFAULT_THINKING_PATH := "res://addons/ai_assistant_plugin/harness/thinking_instructions.md"

const ThinkingTags := preload("res://addons/ai_assistant_plugin/scripts/thinking_tags.gd")

var config_manager: RefCounted = null
var project_context: RefCounted = null
var editor_tools: RefCounted = null
var skills_manager: RefCounted = null

func setup(
	config_mgr: RefCounted,
	context_builder: RefCounted,
	tools: RefCounted,
	skills: RefCounted
) -> void:
	config_manager = config_mgr
	project_context = context_builder
	editor_tools = tools
	skills_manager = skills

func build_system_prompt(user_prompt: String, options: Dictionary, agent_mode: bool) -> Dictionary:
	var layers: PackedStringArray = ["base"]
	var sections: PackedStringArray = [_load_base_context()]
	
	if bool(options.get("enable_thinking", config_manager.get_setting("enable_thinking", true))):
		layers.append("thinking")
		sections.append(_load_thinking_instructions())
	
	if skills_manager:
		var catalog_text: String = String(skills_manager.get_skills_catalog_prompt())
		if not catalog_text.is_empty():
			layers.append("skills")
			sections.append(catalog_text)
		var skill_text: String = String(skills_manager.get_active_skill_content())
		if not skill_text.is_empty():
			layers.append("skill")
			sections.append("## Active skill\n%s" % skill_text)
	
	var attached_context: String = String(options.get("attached_context", ""))
	if not attached_context.is_empty():
		layers.append("attachments")
		sections.append(attached_context)
	
	if bool(options.get("include_context", config_manager.get_setting("include_project_context", true))):
		if project_context:
			layers.append("context")
			var depth: String = String(options.get("context_depth", config_manager.get_setting("context_depth", "intermediate")))
			sections.append(String(project_context.build_context(depth)))
	
	if bool(options.get("enable_tools", config_manager.get_setting("enable_editor_tools", true))):
		if editor_tools:
			layers.append("tools")
			sections.append(String(editor_tools.get_tools_prompt()))
	
	if agent_mode:
		layers.append("agent")
		sections.append(_get_agent_instructions())
	
	return {
		"system_prompt": "\n\n".join(sections),
		"layers": layers
	}

func get_active_layers_label(options: Dictionary, agent_mode: bool) -> String:
	var built: Dictionary = build_system_prompt("", options, agent_mode)
	var layers: PackedStringArray = built.get("layers", PackedStringArray())
	if layers.is_empty():
		return "Harness: base"
	return "Harness: %s" % " · ".join(layers)

func parse_model_response(raw_text: String) -> Dictionary:
	var parsed: Dictionary = ThinkingTags.extract_all_thinking(raw_text)
	return {
		"thinking": String(parsed.get("thinking", "")),
		"content": String(parsed.get("content", "")),
		"raw": raw_text
	}

func format_for_display(parsed: Dictionary) -> String:
	var thinking: String = String(parsed.get("thinking", ""))
	var content: String = String(parsed.get("content", ""))
	var combined: String = content
	if not thinking.is_empty():
		combined = "[Thinking]\n%s\n[/Thinking]\n\n%s" % [thinking, content]
	return sanitize_display_text(combined)

func sanitize_display_text(text: String) -> String:
	if text.is_empty():
		return text
	var lines: PackedStringArray = text.split("\n")
	var output: PackedStringArray = []
	var seen_normalized: Dictionary = {}
	var emoji_streak: int = 0
	var skipped_emoji: int = 0
	var skipped_dup: int = 0
	const MAX_LINES := 72
	const MAX_CHARS := 9000
	for line_idx in lines.size():
		var line: String = lines[line_idx]
		var trimmed: String = line.strip_edges()
		if _is_jsonish_line(trimmed):
			skipped_dup += 1
			continue
		if _is_filler_line(trimmed):
			var filler_key: String = _normalize_line_for_dedupe(trimmed)
			if seen_normalized.has(filler_key):
				skipped_dup += 1
				continue
			seen_normalized[filler_key] = true
		if _is_emoji_only_line(trimmed):
			emoji_streak += 1
			if emoji_streak > 0:
				skipped_emoji += 1
				continue
		else:
			emoji_streak = 0
		var normalized: String = _normalize_line_for_dedupe(trimmed)
		if not normalized.is_empty() and normalized.length() < 120 and seen_normalized.has(normalized):
			skipped_dup += 1
			continue
		if not normalized.is_empty():
			seen_normalized[normalized] = true
		output.append(line)
		if output.size() >= MAX_LINES:
			var omitted: int = maxi(0, lines.size() - line_idx - 1)
			output.append("... (%d lines omitted / %d líneas omitidas)" % [omitted, omitted])
			break
	var result: String = "\n".join(output)
	if result.length() > MAX_CHARS:
		result = "%s\n... (truncated / truncado)" % result.substr(0, MAX_CHARS)
	var notes: PackedStringArray = []
	if skipped_emoji > 0:
		notes.append("(%d emoji lines hidden / emojis ocultos)" % skipped_emoji)
	if skipped_dup > 0:
		notes.append("(%d repetitive lines hidden / repeticiones ocultas)" % skipped_dup)
	if not notes.is_empty():
		result += "\n\n" + " ".join(notes)
	return result.strip_edges()

func _is_jsonish_line(line: String) -> bool:
	var trimmed: String = line.strip_edges().replace("[lb]", "[").replace("[rb]", "]")
	if trimmed.is_empty():
		return false
	if trimmed in ["]", "}", "{", "[", "},"]:
		return true
	if trimmed.begins_with("[") or trimmed.begins_with("{") or trimmed.begins_with("}"):
		return true
	if trimmed.contains("\"tool\"") or trimmed.contains("\"ok\"") or trimmed.contains("\"InputMap\""):
		return true
	return false

func _is_filler_line(line: String) -> bool:
	var lower: String = _normalize_line_for_dedupe(line)
	if lower.is_empty() or lower.length() > 90:
		return false
	var markers: PackedStringArray = [
		"listo", "pruébalo", "pruebalo", "avísame", "avísame", "esperando",
		"script actualizado", "tarea completada", "problemas resueltos",
		"ready", "try it", "waiting for", "task complete",
	]
	for marker in markers:
		if lower.contains(marker):
			return true
	return false

func has_degenerate_repetition(text: String) -> bool:
	var lines: PackedStringArray = text.split("\n")
	if lines.size() < 12:
		return false
	var emoji_only: int = 0
	var normalized_counts: Dictionary = {}
	for line in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty():
			continue
		if _is_toolish_line(trimmed):
			continue
		if _is_emoji_only_line(trimmed):
			emoji_only += 1
			continue
		var key: String = _normalize_line_for_dedupe(trimmed)
		if key.is_empty():
			continue
		normalized_counts[key] = int(normalized_counts.get(key, 0)) + 1
	if emoji_only >= 6:
		return true
	for count in normalized_counts.values():
		if int(count) >= 6:
			return true
	return false

func _is_toolish_line(line: String) -> bool:
	var lower: String = line.to_lower()
	if lower.begins_with("{") or lower.begins_with("["):
		return true
	var markers: PackedStringArray = [
		"node_name", "parent_node_path", "parent_path", "position", "rotation",
		"scale", "item_path", "scene_path", "ground_", "wall_", "floor_",
		"tool_call", "validation error", "renombro", "mismo problema",
	]
	for marker in markers:
		if lower.contains(marker):
			return true
	return false

func _is_emoji_only_line(line: String) -> bool:
	if line.is_empty():
		return false
	var stripped: String = line
	for token in ["🎮", "✅", "❌", "⚠️", "✨", "🔧", "💭", "•", "—", "-"]:
		stripped = stripped.replace(token, "")
	return stripped.strip_edges().is_empty()

func _normalize_line_for_dedupe(line: String) -> String:
	var normalized: String = line.to_lower()
	for token in ["🎮", "✅", "❌", "*", "#", "`", "—"]:
		normalized = normalized.replace(token, "")
	var regex := RegEx.new()
	regex.compile("\\s+")
	return regex.sub(normalized, " ", true).strip_edges()

func _get_agent_instructions() -> String:
	return (
		"## Agent mode\n"
		+ "You act over multiple steps using editor tools to ACTUALLY perform the user's task.\n"
		+ "Every step that needs data or edits MUST include at least one valid "
		+ "<tool_call>{\"tool\":\"...\",\"params\":{...}}</tool_call> with JSON inside — NEVER empty <tool_call></tool_call> tags.\n"
		+ "Do NOT narrate plans ('I will explore…', 'Voy a…') without tool calls in the SAME message.\n"
		+ "SceneBuilder assets live under res://Data/SceneBuilder (capital D). "
		+ "Bootstrap context may already include catalog + snapshot — do NOT re-list res:// from scratch.\n"
		+ "Discovery: search_project_index (hybrid local), search_project_docs (Godot API + README), find_project_paths, list_scene_builder_catalog.\n"
		+ "Placement: place_scene_builder_item or instance_scene, then save_scene when done.\n"
		+ "Design choices: ask_user tool (pauses until user replies).\n"
		+ "Scripts: create_script in ONE step. Read-only inspect tools do NOT consume edit steps.\n"
		+ "Only reply with a final summary AFTER the task is done (max 8 lines, no emoji spam)."
	)

func _load_base_context() -> String:
	var path: String = String(config_manager.get_setting("harness_base_context_path", DEFAULT_BASE_CONTEXT_PATH))
	var text: String = _read_text_file(path)
	if text.is_empty():
		return (
			"You are an AI assistant embedded in Godot 4 editor. "
			+ "The harness executes tools and context; you provide reasoning and plans."
		)
	return text

func _load_thinking_instructions() -> String:
	var path: String = String(config_manager.get_setting("harness_thinking_path", DEFAULT_THINKING_PATH))
	var text: String = _read_text_file(path)
	if text.is_empty():
		return "Use <thinking>...</thinking> for brief internal reasoning before your answer."
	return text

func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text

func _extract_tag_block(text: String, tag_name: String) -> String:
	var regex := RegEx.new()
	# (?s) = dot matches newlines / (?s) = el punto incluye saltos de línea
	regex.compile("(?i)(?s)<%s>(.*?)</%s>" % [tag_name, tag_name])
	var match_result := regex.search(text)
	if match_result:
		return match_result.get_string(1)
	return ""

func _remove_tag_block(text: String, tag_name: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?i)(?s)<%s>.*?</%s>" % [tag_name, tag_name])
	return regex.sub(text, "", true)
