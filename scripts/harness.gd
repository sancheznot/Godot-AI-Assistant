extends RefCounted

# Prompt harness: base + thinking + context + tools + skills + agent / Capas del harness

const DEFAULT_BASE_CONTEXT_PATH := "res://addons/ai_assistant_plugin/harness/base_context.md"
const DEFAULT_THINKING_PATH := "res://addons/ai_assistant_plugin/harness/thinking_instructions.md"

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
	var thinking: String = _extract_tag_block(raw_text, "thinking")
	var content: String = raw_text
	content = _remove_tag_block(content, "thinking")
	return {
		"thinking": thinking.strip_edges(),
		"content": content.strip_edges(),
		"raw": raw_text
	}

func format_for_display(parsed: Dictionary) -> String:
	var thinking: String = String(parsed.get("thinking", ""))
	var content: String = String(parsed.get("content", ""))
	if thinking.is_empty():
		return content
	return "[Thinking]\n%s\n[/Thinking]\n\n%s" % [thinking, content]

func _get_agent_instructions() -> String:
	return (
		"## Agent mode\n"
		+ "You act over multiple steps using editor tools to ACTUALLY perform the user's task.\n"
		+ "Do NOT just inspect the scene or describe a plan: you must execute the tool calls "
		+ "that make the real changes (create_scene, add_node, instance_scene, create_box_mesh, "
		+ "set_node_property, move_node_3d, etc.).\n"
		+ "Inspect only when you truly need information (one quick inspection tool), then immediately act.\n"
		+ "Emit tool calls using exactly: <tool_call>{\"tool\":\"...\",\"params\":{...}}</tool_call>\n"
		+ "After each tool batch you receive results and an updated scene snapshot; use them to continue.\n"
		+ "Only reply with a final summary (and NO <tool_call> blocks) AFTER you have already made the "
		+ "requested changes. Never end the task with only an inspection or a plan."
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
