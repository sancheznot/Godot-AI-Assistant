extends RefCounted

# Cursor-mode fallback: execute obvious edits when model tool markup fails.
# Fallback local estilo Cursor: ejecutar ediciones obvias cuando falla el parseo del modelo.

var editor_tools: RefCounted = null

func setup(tools: RefCounted) -> void:
	editor_tools = tools

func try_execute(user_prompt: String, model_text: String, unparsed_steps: int) -> Array:
	if editor_tools == null:
		return []
	var combined: String = "%s\n%s" % [user_prompt, model_text]
	var results: Array = []

	if editor_tools.has_method("salvage_tool_calls"):
		results = editor_tools.salvage_tool_calls(combined)
		if _has_ok(results):
			return _tag_fallback(results, "salvage_tools")

	var script_write: Dictionary = _try_gdscript_file_write(user_prompt, model_text)
	if not script_write.is_empty():
		return [script_write]

	if unparsed_steps >= 1 or _looks_like_file_edit_request(user_prompt):
		var plugin_write: Dictionary = _try_plugin_write_script(model_text)
		if not plugin_write.is_empty():
			return [plugin_write]

	if _looks_like_cylinder_player(combined):
		var cylinder: Dictionary = _try_cylinder_mesh()
		if not cylinder.is_empty():
			return [cylinder]

	if unparsed_steps >= 2:
		var inspect: Dictionary = _try_inspect_player(model_text)
		if not inspect.is_empty():
			return [inspect]

	return results

func _has_ok(results: Array) -> bool:
	for entry in results:
		if entry is Dictionary and bool(entry.get("result", {}).get("ok", false)):
			return true
	return false

func _tag_fallback(results: Array, reason: String) -> Array:
	for entry in results:
		if entry is Dictionary:
			entry["fallback"] = reason
	return results

func _looks_like_file_edit_request(prompt: String) -> bool:
	var lower: String = prompt.to_lower()
	var markers: PackedStringArray = [
		".gd", "script", "create_script", "read_script", "write_script",
		"archivo", "fichero", "código", "codigo", "editar", "modifica el script",
	]
	for marker in markers:
		if lower.contains(marker):
			return true
	return false

func _looks_like_cylinder_player(text: String) -> bool:
	var lower: String = text.to_lower()
	var wants_mesh: bool = lower.contains("cilindro") or lower.contains("cylinder") or lower.contains("visible")
	var wants_player: bool = lower.contains("player") or lower.contains("jugador") or lower.contains("personaje")
	return wants_mesh and wants_player

func _extract_gdscript_block(text: String) -> String:
	var xml_code: String = _extract_xml_create_script_content(text)
	if not xml_code.is_empty():
		return xml_code
	var fence := RegEx.new()
	fence.compile("(?is)```(?:gdscript|gd)?\\s*(.*?)```")
	var match_result := fence.search(text)
	if match_result:
		return String(match_result.get_string(1)).strip_edges()
	return _extract_loose_gdscript(text)

func _extract_loose_gdscript(text: String) -> String:
	# ponytail: raw pasted GDScript when the model skips ``` fences
	var stripped: String = text.strip_edges()
	if stripped.begins_with("extends ") or stripped.begins_with("class_name "):
		return stripped
	var anchor := RegEx.new()
	anchor.compile("(?is)(?:^|\\n)((?:extends|class_name)\\s+[\\s\\S]+)")
	var match_result := anchor.search(text)
	if match_result == null:
		return ""
	var code: String = String(match_result.get_string(1)).strip_edges()
	# Trim trailing tool markup / prose after the script body.
	var cut := RegEx.new()
	cut.compile("(?is)\\n\\s*(?:<tool|</tool|tool_call|```|\\*\\*[^*]+\\*\\*)")
	var cut_match := cut.search(code)
	if cut_match:
		code = code.substr(0, cut_match.get_start()).strip_edges()
	return code

func _extract_xml_create_script_content(text: String) -> String:
	var block := RegEx.new()
	block.compile(
		"(?is)<tool\\s+name\\s*=\\s*(?:\"create_script\"|'create_script'|create_script)\\s*>\\s*<content\\s*>(.*?)(?:</content\\s*>|(?=<tool\\s|</tool_call>|$))"
	)
	var match_result := block.search(text)
	if match_result == null:
		return ""
	var code: String = String(match_result.get_string(1)).strip_edges()
	if code.begins_with("@tool"):
		var nl: int = code.find("\n")
		code = code.substr(nl + 1).strip_edges() if nl >= 0 else ""
	return code

func _extract_script_path(user_prompt: String, model_text: String, code: String) -> String:
	var combined: String = "%s\n%s\n%s" % [user_prompt, model_text, code]
	if editor_tools != null and editor_tools.has_method("infer_script_path"):
		var inferred: String = editor_tools.infer_script_path(combined, code)
		if not inferred.is_empty():
			return inferred
	var path_regex := RegEx.new()
	path_regex.compile("res://[\\w/.\\-_]+\\.gd")
	for source in [user_prompt, model_text, code]:
		var match_result := path_regex.search(source)
		if match_result:
			return String(match_result.get_string()).strip_edges()
	var lower_prompt: String = user_prompt.to_lower()
	if "player" in lower_prompt or "jugador" in lower_prompt:
		if FileAccess.file_exists("res://scripts/player.gd"):
			return "res://scripts/player.gd"
	if "orbit" in lower_prompt or "camera" in lower_prompt or "cámara" in lower_prompt:
		if FileAccess.file_exists("res://scripts/orbit_camera.gd"):
			return "res://scripts/orbit_camera.gd"
	return ""

func _try_gdscript_file_write(user_prompt: String, model_text: String) -> Dictionary:
	var code: String = _extract_gdscript_block(model_text)
	if code.is_empty():
		return {}
	var script_path: String = _extract_script_path(user_prompt, model_text, code)
	if script_path.is_empty():
		return {}
	var params: Dictionary = {"script_path": script_path, "content": code}
	var result: Dictionary = editor_tools.execute_tool("create_script", params)
	return {
		"tool": "create_script",
		"params": params,
		"result": result,
		"fallback": "local_gdscript_block",
	}

func _try_plugin_write_script(model_text: String) -> Dictionary:
	var path_regex := RegEx.new()
	path_regex.compile("(?is)(?:write_script_file|create_script)[^\\n]*?(res://[\\w/.\\-_]+\\.gd)")
	var match_result := path_regex.search(model_text)
	if match_result == null:
		return {}
	var script_path: String = String(match_result.get_string(1)).strip_edges()
	var code: String = _extract_gdscript_block(model_text)
	if code.is_empty():
		return {}
	var result: Dictionary = editor_tools.execute_tool("create_script", {
		"script_path": script_path,
		"content": code,
	})
	return {
		"tool": "create_script",
		"params": {"script_path": script_path, "content": code},
		"result": result,
		"fallback": "local_plugin_write",
	}

func _try_cylinder_mesh() -> Dictionary:
	var params: Dictionary = {
		"parent_node_path": "Player",
		"node_name": "Body",
		"radius": 0.4,
		"height": 1.8,
		"color": [0.4, 0.7, 1.0],
	}
	var result: Dictionary = editor_tools.execute_tool("create_cylinder_mesh", params)
	return {
		"tool": "create_cylinder_mesh",
		"params": params,
		"result": result,
		"fallback": "local_cylinder_player",
	}

func _try_inspect_player(model_text: String) -> Dictionary:
	if not model_text.to_lower().contains("inspect"):
		return {}
	var params: Dictionary = {"node_path": "Player"}
	var result: Dictionary = editor_tools.execute_tool("inspect_node", params)
	if not bool(result.get("ok", false)):
		return {}
	return {
		"tool": "inspect_node",
		"params": params,
		"result": result,
		"fallback": "local_inspect_player",
	}
