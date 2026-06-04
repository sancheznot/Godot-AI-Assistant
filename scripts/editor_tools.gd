extends RefCounted

# Native Godot editor tools for the AI assistant / Herramientas nativas del editor

signal tool_executed(tool_name: String, result: Dictionary)

const ALLOWED_NODE_TYPES := [
	"Node", "Node2D", "Node3D", "Control", "Sprite2D", "AnimatedSprite2D",
	"MeshInstance3D", "StaticBody3D", "RigidBody3D", "CharacterBody3D",
	"Camera3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D",
	"CollisionShape3D", "CollisionShape2D", "Area3D", "Area2D",
	"Marker3D", "Marker2D", "AnimationPlayer", "Timer", "Label", "Button",
	"TileMap", "TileMapLayer", "CanvasLayer", "SubViewport", "CSGBox3D"
]

var _editor_plugin: EditorPlugin = null

func setup(editor_plugin: EditorPlugin) -> void:
	_editor_plugin = editor_plugin

func get_tools_prompt() -> String:
	return """## Editor tools
When you need to change the Godot editor, append one or more tool calls using this exact format:
<tool_call>{"tool":"TOOL_NAME","params":{...}}</tool_call>

Scene workflow:
- create_scene: params {"scene_path":"res://scenes/new_level.tscn","root_type":"Node3D","root_name":"Level"}
- open_scene: params {"scene_path":"res://..."}
- save_scene: params {}
- instance_scene: params {"scene_path":"res://prefabs/enemy.tscn","parent_node_path":"","node_name":"Enemy1","position":[0,0,0]}

Inspection (use ONE tool max, prefer @ mentions / attached context first):
- get_scene_tree: params {"max_depth":3}
- get_scene_snapshot: params {"max_depth":4}
- get_scene_groups: params {} or {"group":"players"} to list nodes in one group
- get_input_map: params {} for project actions only, or {"action":"action_interact"} for one action
- get_runtime_errors: params {"max_count":20,"clear_after":true} — runtime debugger errors (play mode)
- get_script_errors: params {"script_path":"res://DoorScript.gd","clear_after":true} — GDScript parse errors + debugger errors
- get_selection: params {}
- inspect_node: params {"node_path":"Root/Child"} (includes node groups)
- list_project_files: params {"extension":".tscn","limit":30}
- get_tilemap_cells: params {"node_path":"Root/TileMapLayer","limit":200}

Node editing:
- add_node: params {"node_type":"Node3D","node_name":"MyNode","parent_node_path":""}
- select_node: params {"node_path":"Root/Child"}
- set_node_property: params {"node_path":"Root/Child","property":"position","value":[0,1,0]}
- move_node_3d: params {"node_path":"Root/Child","position":[0,1,0]}
- move_node_2d: params {"node_path":"Root/Child","position":[100,50]}
- scale_node_3d: params {"node_path":"Root/Child","scale":[1,2,1]}
- scale_node_2d: params {"node_path":"Root/Child","scale":[2,2]}
- rotate_node_3d: params {"node_path":"Root/Child","rotation_degrees":[0,90,0]}
- create_box_mesh: params {"parent_node_path":"","node_name":"Crate","size":[1,1,1],"position":[0,0.5,0]}
- set_tilemap_cell: params {"node_path":"Root/TileMapLayer","coords":[3,4],"source_id":0,"atlas_coords":[0,0]}

Scripting (create AND attach a script in ONE call):
- create_script: params {"script_path":"res://scripts/Door.gd","attach_to":"Floor_1_exit/Door_02-n1","content":"extends Node3D\\n\\nfunc _ready():\\n\\tprint(\\"ready\\")\\n"}
  IMPORTANT: put the FULL script code in the "content" param (escape newlines as \\n). Do NOT put code in a separate markdown block. This single call writes the file and attaches it to attach_to (optional). The script is saved automatically — there is no create_script/open_script/save_script split.

Rules:
- ALWAYS wrap tool calls in <tool_call>{"tool":"...","params":{...}}</tool_call>. Never emit bare JSON tool objects or JSON arrays in the user-visible answer — the plugin executes tools and shows results separately.
- NEVER ask the user for InputMap action names, node groups, or debugger errors — call get_input_map, get_scene_groups, get_runtime_errors, or get_script_errors instead and fix with create_script/set_node_property.
- After fixing scripts, call get_script_errors (or get_runtime_errors while the game runs) to verify; errors are cleared on read so the next check is fresh.
- Use res:// paths only. NEVER prefix paths with "@" (write res://... not @res://...).
- node_path / parent_node_path / attach_to are RELATIVE to the edited scene root (e.g. "Floor_1_exit/Ground_05"). Use "" for the root itself.
- There is NO open_script / save_script / create_node tool. To make a script use create_script (it saves and attaches in one step).
- To actually perform the task, EXECUTE the editing tools. Do not stop after only inspecting and do not repeat the same plan.
- Match the script's `extends` to the target node type (inspect_node if unsure).
- Inspect the scene only when you truly need info, then act immediately (create_script, set_node_property, etc.).
- If the user asks for code to paste themselves ("dame el código", "yo lo hago"), reply with a ```gdscript block and do NOT call create_script.
- Use exact node paths from @ mentions and attached context (e.g. Door_02-n1, Floor_1_exit/Door_02-n1).
- Prefer small, safe edits."""

func list_tool_names() -> Array[String]:
	return [
		"create_scene",
		"open_scene",
		"save_scene",
		"instance_scene",
		"get_scene_tree",
		"get_scene_snapshot",
		"get_scene_groups",
		"get_input_map",
		"get_runtime_errors",
		"get_script_errors",
		"get_selection",
		"select_node",
		"add_node",
		"set_node_property",
		"move_node_3d",
		"move_node_2d",
		"scale_node_3d",
		"scale_node_2d",
		"rotate_node_3d",
		"create_box_mesh",
		"get_tilemap_cells",
		"set_tilemap_cell",
		"list_project_files",
		"inspect_node",
		"create_script",
		"open_script",
		"save_script",
	]

func execute_tool(tool_name: String, params: Dictionary = {}) -> Dictionary:
	params = _normalize_tool_params(params)
	var result: Dictionary
	match tool_name:
		"create_scene":
			result = _tool_create_scene(params)
		"get_scene_tree":
			result = _tool_get_scene_tree(params)
		"get_scene_snapshot":
			result = _tool_get_scene_snapshot(params)
		"get_scene_groups":
			result = _tool_get_scene_groups(params)
		"get_input_map":
			result = _tool_get_input_map(params)
		"get_runtime_errors":
			result = _tool_get_runtime_errors(params)
		"get_script_errors":
			result = _tool_get_script_errors(params)
		"get_selection":
			result = _tool_get_selection()
		"select_node":
			result = _tool_select_node(params)
		"open_scene":
			result = _tool_open_scene(params)
		"save_scene":
			result = _tool_save_scene()
		"instance_scene":
			result = _tool_instance_scene(params)
		"add_node":
			result = _tool_add_node(params)
		"set_node_property":
			result = _tool_set_node_property(params)
		"move_node_3d":
			result = _tool_move_node_3d(params)
		"move_node_2d":
			result = _tool_move_node_2d(params)
		"scale_node_3d":
			result = _tool_scale_node_3d(params)
		"scale_node_2d":
			result = _tool_scale_node_2d(params)
		"rotate_node_3d":
			result = _tool_rotate_node_3d(params)
		"create_box_mesh":
			result = _tool_create_box_mesh(params)
		"get_tilemap_cells":
			result = _tool_get_tilemap_cells(params)
		"set_tilemap_cell":
			result = _tool_set_tilemap_cell(params)
		"list_project_files":
			result = _tool_list_project_files(params)
		"inspect_node":
			result = _tool_inspect_node(params)
		"create_script", "write_script":
			result = _tool_create_script(params)
		"open_script":
			result = _tool_open_script(params)
		"save_script":
			result = {"ok": true, "status": "scripts are saved automatically by create_script"}
		_:
			result = {"ok": false, "error": "Unknown tool: %s" % tool_name}
	
	tool_executed.emit(tool_name, result)
	return result

func _normalize_tool_params(value: Variant) -> Variant:
	# Models often copy the "@" mention prefix into paths (e.g. "@res://..."),
	# which breaks res:// validation. Strip it everywhere, recursively.
	# Los modelos copian el prefijo "@" de las menciones en las rutas (p. ej. "@res://..."),
	# lo que rompe la validación res://. Quitarlo en todas partes, recursivamente.
	if value is String:
		var s: String = value
		if s.begins_with("@res://"):
			return s.substr(1)
		if s.begins_with("@/"):
			return "res://" + s.substr(2)
		return s
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value:
			out[key] = _normalize_tool_params(value[key])
		return out
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(_normalize_tool_params(item))
		return arr
	return value

func _rel_path(node: Node) -> String:
	# Scene-relative path instead of the huge absolute editor viewport path.
	# Ruta relativa a la escena en lugar de la enorme ruta absoluta del editor.
	var root := _edited_root()
	if root == null or node == null:
		return node.name if node else ""
	if node == root:
		return "."
	if root.is_ancestor_of(node):
		return str(root.get_path_to(node))
	return node.name

func parse_and_execute_tool_calls(text: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_json in extract_tool_call_json_strings(text):
		if seen.has(raw_json):
			continue
		seen[raw_json] = true
		var parsed: Variant = _parse_tool_json(raw_json)
		if parsed == null or not parsed is Dictionary:
			results.append({"ok": false, "error": "Invalid tool JSON", "raw": raw_json})
			continue
		var tool_name := String(parsed.get("tool", ""))
		var params: Dictionary = _normalize_tool_params(parsed.get("params", {}))
		var tool_result := execute_tool(tool_name, params)
		results.append({"tool": tool_name, "params": params, "result": tool_result})
	return results

func has_tool_calls(text: String) -> bool:
	return not extract_tool_call_json_strings(text).is_empty()

const READ_ONLY_TOOLS: Array[String] = [
	"get_scene_tree",
	"get_scene_snapshot",
	"get_scene_groups",
	"get_input_map",
	"get_runtime_errors",
	"get_script_errors",
	"inspect_node",
	"get_selection",
	"list_project_files",
	"get_tilemap_cells",
]

const MUTATING_TOOLS: Array[String] = [
	"create_script",
	"add_node",
	"instance_scene",
	"set_node_property",
	"move_node_3d",
	"move_node_2d",
	"scale_node_3d",
	"scale_node_2d",
	"rotate_node_3d",
	"create_box_mesh",
	"set_tilemap_cell",
	"create_scene",
	"save_scene",
]

func is_read_only_tool(tool_name: String) -> bool:
	return tool_name in READ_ONLY_TOOLS

func is_mutating_tool(tool_name: String) -> bool:
	return tool_name in MUTATING_TOOLS

func batch_is_read_only_only(tool_results: Array) -> bool:
	if tool_results.is_empty():
		return false
	for entry in tool_results:
		if not entry is Dictionary:
			return false
		if not bool(entry.get("result", {}).get("ok", false)):
			return false
		if not is_read_only_tool(String(entry.get("tool", ""))):
			return false
	return true

func batch_had_mutation(tool_results: Array) -> bool:
	for entry in tool_results:
		if not entry is Dictionary:
			continue
		var tool_name: String = String(entry.get("tool", ""))
		if is_mutating_tool(tool_name) and bool(entry.get("result", {}).get("ok", false)):
			return true
	return false

func compact_tool_results_for_context(tool_results: Array) -> String:
	var compact: Array = []
	for entry in tool_results:
		if entry is Dictionary:
			compact.append(_compact_tool_entry(entry))
	return JSON.stringify(compact, "\t")

func _compact_tool_entry(entry: Dictionary) -> Dictionary:
	var tool_name: String = String(entry.get("tool", ""))
	var result: Variant = entry.get("result", {})
	if not result is Dictionary:
		return {"tool": tool_name, "ok": false, "error": "invalid result"}
	if not bool(result.get("ok", false)):
		return {"tool": tool_name, "ok": false, "error": String(result.get("error", "failed"))}
	match tool_name:
		"get_scene_snapshot", "get_scene_tree":
			var tree: Dictionary = result.get("snapshot", result.get("tree", {}))
			return {
				"tool": tool_name,
				"ok": true,
				"scene_path": result.get("scene_path", ""),
				"node_index": _index_tree_nodes(tree, 50),
			}
		"inspect_node":
			var node: Dictionary = result.get("node", {})
			var props: Dictionary = node.get("properties", {})
			var slim_props: Dictionary = {}
			for key in ["script", "visible", "position", "rotation", "scale"]:
				if props.has(key):
					slim_props[key] = props[key]
			var slim_node: Dictionary = {
				"path": node.get("path", ""),
				"type": node.get("type", ""),
				"properties": slim_props,
			}
			if node.has("groups"):
				slim_node["groups"] = node.get("groups", [])
			return {
				"tool": tool_name,
				"ok": true,
				"node": slim_node,
			}
		"get_scene_groups":
			if result.has("group"):
				return {
					"tool": tool_name,
					"ok": true,
					"group": result.get("group", ""),
					"nodes": result.get("nodes", []),
				}
			return {
				"tool": tool_name,
				"ok": true,
				"groups": result.get("groups", []),
			}
		"get_input_map":
			if result.has("action"):
				var action_entry: Dictionary = result.get("action", {})
				return {
					"tool": tool_name,
					"ok": true,
					"action": action_entry.get("action", ""),
					"events": action_entry.get("events", []),
				}
			var actions: Array = result.get("actions", [])
			var compact_actions: Array = []
			for action_entry in actions.slice(0, 24):
				if action_entry is Dictionary:
					compact_actions.append({
						"action": action_entry.get("action", ""),
						"events": action_entry.get("events", []),
					})
			return {
				"tool": tool_name,
				"ok": true,
				"actions": compact_actions,
				"truncated": actions.size() > 24,
			}
		"get_runtime_errors":
			return {
				"tool": tool_name,
				"ok": true,
				"count": result.get("count", 0),
				"errors": result.get("errors", []),
				"cleared": bool(result.get("cleared", false)),
			}
		"get_script_errors":
			return {
				"tool": tool_name,
				"ok": true,
				"count": result.get("count", 0),
				"errors": result.get("errors", []),
				"cleared": bool(result.get("cleared", false)),
			}
		"list_project_files":
			var files: Array = result.get("files", [])
			return {
				"tool": tool_name,
				"ok": true,
				"files": files.slice(0, 15),
				"truncated": files.size() > 15,
			}
		_:
			var slim: Dictionary = result.duplicate(true)
			slim.erase("snapshot")
			slim.erase("tree")
			return {"tool": tool_name, "result": slim}

func _index_tree_nodes(tree: Dictionary, limit: int) -> Array:
	var out: Array = []
	_walk_tree_index(tree, out, limit)
	return out

func _walk_tree_index(node: Dictionary, out: Array, limit: int) -> void:
	if out.size() >= limit:
		return
	var item: Dictionary = {
		"name": node.get("name", ""),
		"path": node.get("path", ""),
		"type": node.get("type", ""),
	}
	if node.has("children_count"):
		item["children_count"] = node.get("children_count")
	out.append(item)
	var children: Variant = node.get("children", [])
	if children is Array:
		for child in children:
			if child is Dictionary:
				_walk_tree_index(child, out, limit)
			if out.size() >= limit:
				return

func format_tool_results_for_display(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.begins_with("["):
		var parsed: Variant = JSON.parse_string(trimmed)
		if parsed is Array:
			return summarize_tool_results_for_display(parsed)
	if trimmed.begins_with("{"):
		var parsed_obj: Variant = JSON.parse_string(trimmed)
		if parsed_obj is Dictionary:
			return summarize_tool_results_for_display([parsed_obj])
	if trimmed.length() > 5000:
		return "%s\n\n... (%d chars truncated)" % [trimmed.substr(0, 5000), trimmed.length() - 5000]
	return trimmed

func summarize_tool_results_for_display(entries: Array) -> String:
	var lines: PackedStringArray = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		lines.append(_summarize_tool_result_line(entry))
	if lines.is_empty():
		return "(empty tool results)"
	return "\n".join(lines)

func _summarize_tool_result_line(entry: Dictionary) -> String:
	var tool_name: String = String(entry.get("tool", ""))
	if not tool_name.is_empty():
		if not bool(entry.get("ok", true)):
			return "✗ %s: %s" % [tool_name, String(entry.get("error", "failed"))]
		var result: Variant = entry.get("result", entry)
		if result is Dictionary:
			return "✓ %s: %s" % [tool_name, _summarize_result_dict(result as Dictionary)]
		if entry.has("actions"):
			var actions: Array = entry.get("actions", [])
			var names: PackedStringArray = []
			for action_entry in actions.slice(0, 10):
				if action_entry is Dictionary:
					names.append(String(action_entry.get("action", "")))
			var suffix: String = ""
			if actions.size() > 10:
				suffix = " …+%d" % (actions.size() - 10)
			return "✓ %s: %s%s" % [tool_name, ", ".join(names), suffix]
		if entry.has("errors"):
			var err_list: Array = entry.get("errors", [])
			if err_list.is_empty():
				return "✓ %s: no errors" % tool_name
			var first: Variant = err_list[0]
			if first is Dictionary:
				return "✓ %s: %s" % [tool_name, String(first.get("summary", first.get("error", "error")))]
			return "✓ %s: %d error(s)" % [tool_name, err_list.size()]
		return "✓ %s" % tool_name
	if entry.has("InputMap"):
		var input_actions: Array = entry.get("InputMap", [])
		var input_names: PackedStringArray = []
		for action_entry in input_actions.slice(0, 8):
			if action_entry is Dictionary:
				input_names.append(String(action_entry.get("action", "")))
		return "InputMap: %s" % ", ".join(input_names)
	if entry.has("actions"):
		var actions: Array = entry.get("actions", [])
		var names: PackedStringArray = []
		for action_entry in actions.slice(0, 10):
			if action_entry is Dictionary:
				names.append(String(action_entry.get("action", "")))
		return "InputMap: %s" % ", ".join(names)
	if entry.has("action"):
		var action: Dictionary = entry.get("action", {})
		if action is Dictionary:
			return "action=%s events=%s" % [action.get("action", ""), action.get("events", [])]
		return "action=%s" % action
	return str(entry).substr(0, 240)

func _summarize_result_dict(result: Dictionary) -> String:
	if result.has("attached_to"):
		return "attached_to=%s script=%s" % [result.get("attached_to", ""), result.get("script_path", "")]
	if result.has("script_path"):
		return "script=%s lines=%s" % [result.get("script_path", ""), result.get("lines", "")]
	if result.has("error"):
		return String(result.get("error", ""))
	var keys: Array = result.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys.slice(0, 4):
		parts.append("%s=%s" % [key, result.get(key)])
	return ", ".join(parts)

func find_tool_call_spans(text: String) -> Array:
	var spans: Array = []
	var seen: Dictionary = {}
	var tag_regex := RegEx.new()
	tag_regex.compile("(?s)<tool_call>(.*?)</tool_call>")
	for match_result in tag_regex.search_all(text):
		var inner: String = match_result.get_string(1).strip_edges()
		if inner.is_empty() or seen.has(inner):
			continue
		seen[inner] = true
		spans.append({
			"start": match_result.get_start(1),
			"end": match_result.get_end(1),
			"json": inner,
		})
	var fence_regex := RegEx.new()
	fence_regex.compile("(?s)```(?:json|tool_call)?\\s*(\\{.*?\\})\\s*```")
	for match_result in fence_regex.search_all(text):
		var block: String = extract_balanced_json_object(text, match_result.get_start(1))
		if block.is_empty():
			block = match_result.get_string(1).strip_edges()
		if block.is_empty() or seen.has(block):
			continue
		seen[block] = true
		spans.append({
			"start": match_result.get_start(1),
			"end": match_result.get_start(1) + block.length(),
			"json": block,
		})
	for inline_start in _find_inline_tool_json_starts(text):
		var block: String = extract_balanced_json_object(text, inline_start)
		if block.is_empty() or seen.has(block):
			continue
		seen[block] = true
		spans.append({
			"start": inline_start,
			"end": inline_start + block.length(),
			"json": block,
		})
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("start", 0)) < int(b.get("start", 0))
	)
	return spans

func extract_tool_call_json_strings(text: String) -> Array[String]:
	var found: Array[String] = []
	var seen: Dictionary = {}
	var tag_regex := RegEx.new()
	tag_regex.compile("<tool_call>(.*?)</tool_call>")
	for match_result in tag_regex.search_all(text):
		_collect_tool_json_candidate(match_result.get_string(1), found, seen)
	var fence_regex := RegEx.new()
	fence_regex.compile("(?s)```(?:json)?\\s*(\\{.*?\\})\\s*```")
	for match_result in fence_regex.search_all(text):
		var block: String = extract_balanced_json_object(text, match_result.get_start(1))
		if not block.is_empty():
			_collect_tool_json_candidate(block, found, seen)
		else:
			_collect_tool_json_candidate(match_result.get_string(1), found, seen)
	for inline_start in _find_inline_tool_json_starts(text):
		var block: String = extract_balanced_json_object(text, inline_start)
		_collect_tool_json_candidate(block, found, seen)
	return found

func _find_inline_tool_json_starts(text: String) -> Array[int]:
	var starts: Array[int] = []
	var search_from: int = 0
	while search_from < text.length():
		var idx: int = text.find("{\"tool\"", search_from)
		if idx < 0:
			idx = text.find("{ \"tool\"", search_from)
		if idx < 0:
			break
		starts.append(idx)
		search_from = idx + 1
	return starts

func find_tool_result_json_spans(text: String) -> Array:
	var decoded: String = text.replace("[lb]", "[").replace("[rb]", "]")
	var spans: Array = []
	var seen: Dictionary = {}
	var search_from: int = 0
	while search_from < decoded.length():
		var idx: int = decoded.find("[", search_from)
		if idx < 0:
			break
		var block: String = extract_balanced_json_array(decoded, idx)
		if block.is_empty() or seen.has(block):
			search_from = idx + 1
			continue
		if not looks_like_tool_results_json(block):
			search_from = idx + 1
			continue
		seen[block] = true
		spans.append({
			"start": idx,
			"end": idx + block.length(),
			"json": block,
		})
		search_from = idx + block.length()
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("start", 0)) < int(b.get("start", 0))
	)
	return spans

func looks_like_tool_results_json(block: String) -> bool:
	var parsed: Variant = JSON.parse_string(block.strip_edges())
	if not parsed is Array or parsed.is_empty():
		return false
	for item in parsed:
		if not item is Dictionary:
			continue
		if item.has("tool") or item.has("result") or item.has("InputMap") or item.has("actions"):
			return true
		if item.has("errors") or item.has("groups") or item.has("ok"):
			return true
	return false

func extract_balanced_json_array(text: String, start: int) -> String:
	if start < 0 or start >= text.length() or text[start] != "[":
		return ""
	var depth: int = 0
	var in_string: bool = false
	var escape: bool = false
	for i in range(start, text.length()):
		var ch: String = text[i]
		if in_string:
			if escape:
				escape = false
			elif ch == "\\":
				escape = true
			elif ch == "\"":
				in_string = false
			continue
		match ch:
			"\"":
				in_string = true
			"[":
				depth += 1
			"]":
				depth -= 1
				if depth == 0:
					return text.substr(start, i - start + 1)
	return ""

func extract_balanced_json_object(text: String, start: int) -> String:
	if start < 0 or start >= text.length() or text[start] != "{":
		return ""
	var depth: int = 0
	var in_string: bool = false
	var escape: bool = false
	for i in range(start, text.length()):
		var ch: String = text[i]
		if in_string:
			if escape:
				escape = false
			elif ch == "\\":
				escape = true
			elif ch == "\"":
				in_string = false
			continue
		match ch:
			"\"":
				in_string = true
			"{":
				depth += 1
			"}":
				depth -= 1
				if depth == 0:
					return text.substr(start, i - start + 1)
	return ""

func _collect_tool_json_candidate(raw: String, found: Array[String], seen: Dictionary) -> void:
	var cleaned: String = raw.strip_edges()
	if cleaned.is_empty() or seen.has(cleaned):
		return
	if not cleaned.contains("\"tool\""):
		return
	seen[cleaned] = true
	found.append(cleaned)

func _parse_tool_json(raw_json: String) -> Variant:
	var cleaned: String = raw_json.strip_edges()
	var parsed: Variant = JSON.parse_string(cleaned)
	if parsed != null:
		return parsed
	var repaired: String = cleaned
	repaired = repaired.replace("\"params\":{}", "\"params\": {}")
	repaired = repaired.replace("\"params:{\"", "\"params\": {}")
	repaired = repaired.replace("\"params:{", "\"params\": {")
	if repaired != cleaned:
		return JSON.parse_string(repaired)
	return null

func _editor_interface() -> EditorInterface:
	if _editor_plugin:
		return _editor_plugin.get_editor_interface()
	return null

func _debugger_error_bridge() -> EditorDebuggerPlugin:
	if _editor_plugin != null and _editor_plugin.has_method("get_debugger_error_bridge"):
		return _editor_plugin.get_debugger_error_bridge()
	return null

func _edited_root() -> Node:
	var ei := _editor_interface()
	return ei.get_edited_scene_root() if ei else null

func _mark_unsaved() -> void:
	var ei := _editor_interface()
	if ei:
		ei.mark_scene_as_unsaved()

func _tool_create_scene(params: Dictionary) -> Dictionary:
	var scene_path := String(params.get("scene_path", ""))
	var root_type := String(params.get("root_type", "Node3D"))
	var root_name := String(params.get("root_name", "Root"))
	
	if scene_path.is_empty() or not scene_path.begins_with("res://") or not scene_path.ends_with(".tscn"):
		return {"ok": false, "error": "scene_path must be res://.../*.tscn"}
	if FileAccess.file_exists(scene_path):
		return {"ok": false, "error": "Scene already exists: %s" % scene_path}
	if not _is_allowed_node_type(root_type):
		return {"ok": false, "error": "Invalid root type: %s" % root_type}
	
	var dir_path := scene_path.get_base_dir()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		var make_dir := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		if make_dir != OK:
			return {"ok": false, "error": "Could not create folder: %s" % dir_path}
	
	var root_node: Node = ClassDB.instantiate(root_type)
	if root_node == null:
		return {"ok": false, "error": "Cannot instantiate %s" % root_type}
	root_node.name = root_name
	
	var packed := PackedScene.new()
	if packed.pack(root_node) != OK:
		root_node.free()
		return {"ok": false, "error": "Failed to pack scene"}
	if ResourceSaver.save(packed, scene_path) != OK:
		return {"ok": false, "error": "Failed to save scene"}
	
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "EditorInterface unavailable"}
	ei.open_scene_from_path(scene_path)
	return {"ok": true, "scene_path": scene_path, "root_type": root_type, "root_name": root_name}

func _tool_get_scene_tree(params: Dictionary = {}) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	var max_depth := int(params.get("max_depth", 5))
	return {"ok": true, "scene_path": root.scene_file_path, "tree": _serialize_tree(root, 0, max_depth)}

func _tool_get_scene_snapshot(params: Dictionary = {}) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	var max_depth := int(params.get("max_depth", 6))
	return {
		"ok": true,
		"scene_path": root.scene_file_path,
		"snapshot": _serialize_tree_detailed(root, 0, max_depth)
	}

func _tool_get_scene_groups(params: Dictionary = {}) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	var groups_map: Dictionary = {}
	_collect_scene_groups(root, groups_map)
	var group_filter: String = String(params.get("group", "")).strip_edges()
	if not group_filter.is_empty():
		return {
			"ok": true,
			"group": group_filter,
			"nodes": groups_map.get(group_filter, []),
		}
	var summary: Array = []
	for group_name in groups_map.keys():
		var nodes: Array = groups_map[group_name]
		summary.append({
			"group": group_name,
			"node_count": nodes.size(),
			"nodes": nodes.slice(0, 12),
		})
	summary.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("group", "")) < String(b.get("group", ""))
	)
	return {"ok": true, "groups": summary}

func _tool_get_input_map(params: Dictionary = {}) -> Dictionary:
	var action_filter: String = String(params.get("action", "")).strip_edges()
	var include_editor: bool = bool(params.get("include_editor", false))
	var action_names: PackedStringArray = _get_project_input_action_names()
	if action_names.is_empty() and not include_editor:
		action_names = _filter_input_actions(InputMap.get_actions(), false)
	elif include_editor:
		action_names = InputMap.get_actions()
	var output: Array = []
	for action_name in action_names:
		if not action_filter.is_empty() and String(action_name) != action_filter:
			continue
		if not InputMap.has_action(action_name):
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action_name):
			var summary: String = _summarize_input_event(event)
			if not summary.is_empty():
				events.append(summary)
		output.append({
			"action": String(action_name),
			"deadzone": InputMap.action_get_deadzone(action_name),
			"events": events,
		})
	if not action_filter.is_empty():
		if output.is_empty():
			return {"ok": false, "error": "InputMap action not found: %s" % action_filter}
		return {"ok": true, "action": output[0]}
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("action", "")) < String(b.get("action", ""))
	)
	return {"ok": true, "actions": output, "project_only": not include_editor}

func _is_editor_input_action(action_name: String) -> bool:
	var name: String = action_name.strip_edges()
	if name.begins_with("ui_"):
		return true
	if name.begins_with("spatial_editor/"):
		return true
	if name.begins_with("godot/"):
		return true
	if name.begins_with("editor/"):
		return true
	return false

func _filter_input_actions(actions: PackedStringArray, include_editor: bool) -> PackedStringArray:
	var filtered: PackedStringArray = []
	for action_name in actions:
		if include_editor or not _is_editor_input_action(String(action_name)):
			filtered.append(String(action_name))
	return filtered

func _get_project_input_action_names() -> PackedStringArray:
	var seen: Dictionary = {}
	var names: PackedStringArray = []
	for prop in ProjectSettings.get_property_list():
		var full_name: String = String(prop.get("name", ""))
		if not full_name.begins_with("input/"):
			continue
		var parts: PackedStringArray = full_name.split("/")
		if parts.size() < 2:
			continue
		var action_name: String = parts[1]
		if action_name.is_empty() or seen.has(action_name) or _is_editor_input_action(action_name):
			continue
		seen[action_name] = true
		names.append(action_name)
	for action_name in InputMap.get_actions():
		var name: String = String(action_name)
		if name.is_empty() or seen.has(name) or _is_editor_input_action(name):
			continue
		seen[name] = true
		names.append(name)
	names.sort()
	return names

func _summarize_input_event(event: InputEvent) -> String:
	if event == null:
		return ""
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return "key:%s physical:%s" % [
			OS.get_keycode_string(key_event.keycode),
			OS.get_keycode_string(key_event.physical_keycode),
		]
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return "mouse_button:%d" % mouse_event.button_index
	if event is InputEventJoypadButton:
		var pad_event := event as InputEventJoypadButton
		return "joypad_button:%d" % pad_event.button_index
	if event is InputEventJoypadMotion:
		var motion_event := event as InputEventJoypadMotion
		return "joypad_axis:%d" % motion_event.axis
	return event.as_text()

func _tool_get_runtime_errors(params: Dictionary = {}) -> Dictionary:
	var max_count: int = clampi(int(params.get("max_count", 20)), 1, 50)
	var clear_after: bool = bool(params.get("clear_after", true))
	var bridge: EditorDebuggerPlugin = _debugger_error_bridge()
	var errors: Array = []
	if bridge != null and bridge.has_method("fetch_errors"):
		errors = bridge.fetch_errors(clear_after, max_count)
	return {
		"ok": true,
		"count": errors.size(),
		"errors": errors,
		"cleared": clear_after,
	}

func _tool_get_script_errors(params: Dictionary = {}) -> Dictionary:
	var script_path: String = String(params.get("script_path", "")).strip_edges()
	var clear_after: bool = bool(params.get("clear_after", true))
	var max_count: int = clampi(int(params.get("max_count", 20)), 1, 50)
	var errors: Array = []
	if script_path.is_empty():
		var open_paths: PackedStringArray = _get_open_script_paths()
		for path in open_paths:
			var parsed: Dictionary = _validate_gdscript_file(path)
			if not parsed.is_empty():
				errors.append(parsed)
	else:
		var parsed_one: Dictionary = _validate_gdscript_file(script_path)
		if not parsed_one.is_empty():
			errors.append(parsed_one)
	var runtime: Dictionary = _tool_get_runtime_errors({
		"max_count": max_count,
		"clear_after": clear_after,
	})
	for item in runtime.get("errors", []):
		if item is Dictionary:
			errors.append(item)
	errors = errors.slice(0, max_count)
	return {
		"ok": true,
		"count": errors.size(),
		"errors": errors,
		"cleared": clear_after,
	}

func _get_open_script_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	var ei := _editor_interface()
	if ei == null:
		return paths
	var script_editor: Node = ei.get_script_editor()
	if script_editor == null or not script_editor.has_method("get_open_script_editors"):
		return paths
	for editor in script_editor.get_open_script_editors():
		if editor != null and editor.has_method("get_edited_resource"):
			var resource: Resource = editor.get_edited_resource()
			if resource is Script and String(resource.resource_path).ends_with(".gd"):
				paths.append(String(resource.resource_path))
	return paths

func _validate_gdscript_file(script_path: String) -> Dictionary:
	if script_path.is_empty() or not script_path.ends_with(".gd"):
		return {}
	if not FileAccess.file_exists(script_path):
		return {
			"summary": "Script not found: %s" % script_path,
			"source_file": script_path,
			"source": "script_validator",
			"warning": false,
		}
	var source: String = FileAccess.get_file_as_string(script_path)
	var script := GDScript.new()
	script.source_code = source
	var err: Error = script.reload()
	if err == OK:
		return {}
	var detail: String = _extract_gdscript_error_detail(source, err)
	return {
		"summary": "GDScript error in %s: %s" % [script_path, detail],
		"source_file": script_path,
		"error": detail,
		"source": "script_validator",
		"warning": false,
	}

func _extract_gdscript_error_detail(source: String, err: Error) -> String:
	var base: String = error_string(err)
	if err != ERR_PARSE_ERROR and err != ERR_COMPILATION_FAILED:
		return base
	# Heuristic scan for common parse errors when Godot only returns ERR_PARSE_ERROR.
	# Escaneo heurístico de errores comunes cuando Godot solo devuelve ERR_PARSE_ERROR.
	var lines: PackedStringArray = source.split("\n")
	for line_idx in lines.size():
		var line: String = lines[line_idx]
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("else:") or trimmed.begins_with("elif "):
			var prev_idx: int = line_idx - 1
			while prev_idx >= 0 and lines[prev_idx].strip_edges().is_empty():
				prev_idx -= 1
			if prev_idx >= 0:
				var prev_line: String = lines[prev_idx].strip_edges()
				if prev_line.begins_with("if ") and prev_line.contains("var "):
					return "%s (line %d): variable declared in if-branch may be out of scope in else" % [base, line_idx + 1]
	return base

func _collect_scene_groups(node: Node, groups_map: Dictionary) -> void:
	for group_name in node.get_groups():
		if not groups_map.has(group_name):
			groups_map[group_name] = []
		groups_map[group_name].append(_rel_path(node))
	for child in node.get_children():
		_collect_scene_groups(child, groups_map)

func _tool_get_selection() -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "EditorInterface unavailable"}
	var nodes := ei.get_selection().get_selected_nodes()
	var selected: Array = []
	for node in nodes:
		selected.append(_serialize_node_summary(node))
	return {"ok": true, "selection": selected}

func _tool_select_node(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "EditorInterface unavailable"}
	ei.get_selection().clear()
	ei.get_selection().add_node(node)
	if ei.has_method("inspect_object"):
		ei.inspect_object(node)
	return {"ok": true, "selected": _rel_path(node), "type": node.get_class()}

func _tool_open_scene(params: Dictionary) -> Dictionary:
	var scene_path := String(params.get("scene_path", ""))
	if scene_path.is_empty() or not scene_path.begins_with("res://"):
		return {"ok": false, "error": "scene_path must start with res://"}
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "EditorInterface unavailable"}
	ei.open_scene_from_path(scene_path)
	return {"ok": true, "opened": scene_path}

func _tool_save_scene() -> Dictionary:
	var ei := _editor_interface()
	if ei == null:
		return {"ok": false, "error": "EditorInterface unavailable"}
	ei.save_scene()
	return {"ok": true, "status": "saved"}

func _tool_instance_scene(params: Dictionary) -> Dictionary:
	var scene_path := String(params.get("scene_path", ""))
	var parent_path := String(params.get("parent_node_path", ""))
	var node_name := String(params.get("node_name", ""))
	var position: Array = params.get("position", [])
	
	if scene_path.is_empty() or not scene_path.begins_with("res://"):
		return {"ok": false, "error": "scene_path must start with res://"}
	
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return {"ok": false, "error": "Could not load scene: %s" % scene_path}
	
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	
	var parent_node: Node = root
	if not parent_path.is_empty():
		parent_node = root.get_node_or_null(NodePath(parent_path))
		if parent_node == null:
			return {"ok": false, "error": "Parent not found: %s" % parent_path}
	
	var instance: Node = packed.instantiate()
	if not node_name.is_empty():
		instance.name = _make_unique_name(parent_node, node_name)
	parent_node.add_child(instance)
	instance.owner = root
	
	if not position.is_empty():
		if instance is Node3D and position.size() >= 3:
			(instance as Node3D).position = Vector3(float(position[0]), float(position[1]), float(position[2]))
		elif instance is Node2D and position.size() >= 2:
			(instance as Node2D).position = Vector2(float(position[0]), float(position[1]))
	
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(instance), "instance_of": scene_path}

func _tool_add_node(params: Dictionary) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	
	var node_type := String(params.get("node_type", "Node"))
	var node_name := String(params.get("node_name", "NewNode"))
	var parent_path := String(params.get("parent_node_path", ""))
	
	if not _is_allowed_node_type(node_type):
		return {"ok": false, "error": "Blocked node type: %s" % node_type}
	
	var parent_node: Node = root
	if not parent_path.is_empty():
		parent_node = root.get_node_or_null(NodePath(parent_path))
		if parent_node == null:
			return {"ok": false, "error": "Parent not found: %s" % parent_path}
	
	var new_node: Node = ClassDB.instantiate(node_type)
	if new_node == null:
		return {"ok": false, "error": "Cannot instantiate %s" % node_type}
	new_node.name = _make_unique_name(parent_node, node_name)
	parent_node.add_child(new_node)
	new_node.set_owner(root)
	
	var position: Array = params.get("position", [])
	if not position.is_empty():
		if new_node is Node3D and position.size() >= 3:
			(new_node as Node3D).position = Vector3(float(position[0]), float(position[1]), float(position[2]))
		elif new_node is Node2D and position.size() >= 2:
			(new_node as Node2D).position = Vector2(float(position[0]), float(position[1]))
	
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(new_node), "type": node_type}

func _tool_set_node_property(params: Dictionary) -> Dictionary:
	var node_path := String(params.get("node_path", ""))
	var property_name := String(params.get("property", ""))
	if node_path.is_empty() or property_name.is_empty():
		return {"ok": false, "error": "node_path and property are required"}
	
	var node := _get_node_by_path(node_path)
	if node == null:
		return {"ok": false, "error": "Node not found: %s" % node_path}
	
	# Special-case "script": load the .gd resource instead of assigning a raw string.
	# Caso especial "script": cargar el recurso .gd en vez de asignar un string crudo.
	if property_name == "script":
		var script_path := String(params.get("value", ""))
		if not script_path.ends_with(".gd") or not FileAccess.file_exists(script_path):
			return {"ok": false, "error": "script value must be an existing res://.../*.gd path"}
		var script_res: Script = load(script_path)
		if script_res == null:
			return {"ok": false, "error": "Could not load script: %s" % script_path}
		node.set_script(script_res)
		_mark_unsaved()
		return {"ok": true, "node_path": node_path, "property": "script", "value": script_path}
	
	if not _property_exists(node, property_name):
		return {"ok": false, "error": "Property not found: %s" % property_name}
	
	node.set(property_name, _coerce_value(params.get("value")))
	_mark_unsaved()
	return {"ok": true, "node_path": node_path, "property": property_name, "value": node.get(property_name)}

func _tool_move_node_3d(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	if not node is Node3D:
		return {"ok": false, "error": "Node is not Node3D"}
	var pos_array: Array = params.get("position", [])
	if pos_array.size() < 3:
		return {"ok": false, "error": "position requires [x,y,z]"}
	(node as Node3D).position = Vector3(float(pos_array[0]), float(pos_array[1]), float(pos_array[2]))
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(node), "position": _vector3_to_array((node as Node3D).position)}

func _tool_move_node_2d(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	if not node is Node2D:
		return {"ok": false, "error": "Node is not Node2D"}
	var pos_array: Array = params.get("position", [])
	if pos_array.size() < 2:
		return {"ok": false, "error": "position requires [x,y]"}
	(node as Node2D).position = Vector2(float(pos_array[0]), float(pos_array[1]))
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(node), "position": _vector2_to_array((node as Node2D).position)}

func _tool_scale_node_3d(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	if not node is Node3D:
		return {"ok": false, "error": "Node is not Node3D"}
	var scale_array: Array = params.get("scale", [])
	if scale_array.size() < 3:
		return {"ok": false, "error": "scale requires [x,y,z]"}
	(node as Node3D).scale = Vector3(float(scale_array[0]), float(scale_array[1]), float(scale_array[2]))
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(node), "scale": _vector3_to_array((node as Node3D).scale)}

func _tool_scale_node_2d(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	if not node is Node2D:
		return {"ok": false, "error": "Node is not Node2D"}
	var scale_array: Array = params.get("scale", [])
	if scale_array.size() < 2:
		return {"ok": false, "error": "scale requires [x,y]"}
	(node as Node2D).scale = Vector2(float(scale_array[0]), float(scale_array[1]))
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(node), "scale": _vector2_to_array((node as Node2D).scale)}

func _tool_rotate_node_3d(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	if not node is Node3D:
		return {"ok": false, "error": "Node is not Node3D"}
	var rotation_array: Array = params.get("rotation_degrees", params.get("rotation", []))
	if rotation_array.size() < 3:
		return {"ok": false, "error": "rotation_degrees requires [x,y,z]"}
	(node as Node3D).rotation_degrees = Vector3(float(rotation_array[0]), float(rotation_array[1]), float(rotation_array[2]))
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(node), "rotation_degrees": _vector3_to_array((node as Node3D).rotation_degrees)}

func _tool_create_box_mesh(params: Dictionary) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	
	var parent_path := String(params.get("parent_node_path", ""))
	var node_name := String(params.get("node_name", "BoxMesh"))
	var size_array: Array = params.get("size", [1, 1, 1])
	if size_array.size() < 3:
		return {"ok": false, "error": "size requires [x,y,z]"}
	
	var parent_node: Node = root
	if not parent_path.is_empty():
		parent_node = root.get_node_or_null(NodePath(parent_path))
		if parent_node == null:
			return {"ok": false, "error": "Parent not found: %s" % parent_path}
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = _make_unique_name(parent_node, node_name)
	var box := BoxMesh.new()
	box.size = Vector3(float(size_array[0]), float(size_array[1]), float(size_array[2]))
	mesh_instance.mesh = box
	parent_node.add_child(mesh_instance)
	mesh_instance.owner = root
	
	var position: Array = params.get("position", [])
	if position.size() >= 3:
		mesh_instance.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	
	_mark_unsaved()
	return {
		"ok": true,
		"node_path": _rel_path(mesh_instance),
		"size": size_array,
		"position": _vector3_to_array(mesh_instance.position)
	}

func _tool_get_tilemap_cells(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	if not (node is TileMapLayer or node is TileMap):
		return {"ok": false, "error": "Node is not TileMap or TileMapLayer"}
	
	var limit := int(params.get("limit", 200))
	var cells: Array = []
	var used_cells: Array = []
	
	if node is TileMapLayer:
		used_cells = (node as TileMapLayer).get_used_cells()
	elif node.has_method("get_used_cells"):
		used_cells = node.call("get_used_cells")
	
	for coords in used_cells:
		if cells.size() >= limit:
			break
		var cell_data := _serialize_tile_cell(node, coords)
		if not cell_data.is_empty():
			cells.append(cell_data)
	
	return {
		"ok": true,
		"node_path": _rel_path(node),
		"type": node.get_class(),
		"cell_count": cells.size(),
		"cells": cells
	}

func _tool_set_tilemap_cell(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	if not (node is TileMapLayer or node is TileMap):
		return {"ok": false, "error": "Node is not TileMap or TileMapLayer"}
	
	var coords_array: Array = params.get("coords", [])
	if coords_array.size() < 2:
		return {"ok": false, "error": "coords requires [x,y]"}
	var coords := Vector2i(int(coords_array[0]), int(coords_array[1]))
	var source_id := int(params.get("source_id", 0))
	var atlas_array: Array = params.get("atlas_coords", [0, 0])
	var atlas_coords := Vector2i(int(atlas_array[0]), int(atlas_array[1]))
	var alternative_tile := int(params.get("alternative_tile", 0))
	
	if node is TileMapLayer:
		(node as TileMapLayer).set_cell(coords, source_id, atlas_coords, alternative_tile)
	elif node.has_method("set_cell"):
		node.call("set_cell", coords, source_id, atlas_coords, alternative_tile)
	else:
		return {"ok": false, "error": "TileMap node does not support set_cell"}
	
	_mark_unsaved()
	return {"ok": true, "node_path": _rel_path(node), "coords": coords_array, "source_id": source_id, "atlas_coords": atlas_array}

func _tool_list_project_files(params: Dictionary) -> Dictionary:
	var extension := String(params.get("extension", ".gd"))
	var limit := int(params.get("limit", 30))
	var files: Array[String] = []
	_collect_files("res://", extension, limit, files)
	return {"ok": true, "files": files}

func _tool_inspect_node(params: Dictionary) -> Dictionary:
	var node := _get_node_by_path(String(params.get("node_path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found"}
	return {"ok": true, "node": _serialize_node_summary(node, true)}

func _tool_create_script(params: Dictionary) -> Dictionary:
	# Accept both script_path and file_path (models use either).
	# Aceptar script_path y file_path (los modelos usan cualquiera).
	var script_path := String(params.get("script_path", params.get("file_path", "")))
	if script_path.is_empty() or not script_path.begins_with("res://") or not script_path.ends_with(".gd"):
		return {"ok": false, "error": "script_path must be res://.../*.gd"}
	
	var attach_to := String(params.get("attach_to", params.get("node_path", "")))
	var content := String(params.get("content", params.get("code", "")))
	if content.strip_edges().is_empty():
		# Sensible default based on the target node type, if any.
		# Plantilla por defecto según el tipo del nodo objetivo, si lo hay.
		var base_type := "Node"
		if not attach_to.is_empty():
			var target := _get_node_by_path(attach_to)
			if target:
				base_type = target.get_class()
		content = "extends %s\n\nfunc _ready() -> void:\n\tpass\n" % base_type
	
	var dir_path := script_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		var make_dir := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		if make_dir != OK:
			return {"ok": false, "error": "Could not create folder: %s" % dir_path}
	
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not write script: %s" % script_path}
	file.store_string(content)
	file.close()
	
	var ei := _editor_interface()
	if ei:
		ei.get_resource_filesystem().scan()
	
	var result := {"ok": true, "script_path": script_path, "lines": content.split("\n").size()}
	
	if not attach_to.is_empty():
		var node := _get_node_by_path(attach_to)
		if node == null:
			result["attach_warning"] = "Script created but node not found: %s" % attach_to
		else:
			var script_res: Script = load(script_path)
			if script_res == null:
				result["attach_warning"] = "Script created but failed to load for attach"
			else:
				node.set_script(script_res)
				result["attached_to"] = _rel_path(node)
				_mark_unsaved()
	
	if ei and ei.has_method("edit_script"):
		var opened: Script = load(script_path)
		if opened:
			ei.edit_script(opened)
	return result

func _tool_open_script(params: Dictionary) -> Dictionary:
	var script_path := String(params.get("script_path", params.get("file_path", "")))
	if script_path.is_empty() or not script_path.ends_with(".gd"):
		return {"ok": false, "error": "script_path must be res://.../*.gd"}
	if not FileAccess.file_exists(script_path):
		return {"ok": false, "error": "Script does not exist: %s" % script_path}
	var ei := _editor_interface()
	if ei and ei.has_method("edit_script"):
		var script_res: Script = load(script_path)
		if script_res:
			ei.edit_script(script_res)
	return {"ok": true, "opened": script_path}

func _serialize_tile_cell(node: Node, coords: Vector2i) -> Dictionary:
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		return {
			"coords": [coords.x, coords.y],
			"source_id": layer.get_cell_source_id(coords),
			"atlas_coords": [layer.get_cell_atlas_coords(coords).x, layer.get_cell_atlas_coords(coords).y],
			"alternative_tile": layer.get_cell_alternative_tile(coords)
		}
	if node.has_method("get_cell_source_id"):
		var atlas: Vector2i = node.call("get_cell_atlas_coords", coords)
		return {
			"coords": [coords.x, coords.y],
			"source_id": int(node.call("get_cell_source_id", coords)),
			"atlas_coords": [atlas.x, atlas.y]
		}
	return {}

func _serialize_node_summary(node: Node, include_properties: bool = false) -> Dictionary:
	var data := {
		"path": _rel_path(node),
		"type": node.get_class(),
		"name": node.name
	}
	# Only include transform fields when they differ from defaults (keeps context compact).
	# Incluir transform solo cuando difiere de los valores por defecto (mantiene el contexto compacto).
	if node is Node3D:
		var n3d := node as Node3D
		if n3d.position != Vector3.ZERO:
			data["position"] = _vector3_to_array(n3d.position)
		if n3d.rotation_degrees != Vector3.ZERO:
			data["rotation_degrees"] = _vector3_to_array(n3d.rotation_degrees)
		if n3d.scale != Vector3.ONE:
			data["scale"] = _vector3_to_array(n3d.scale)
	elif node is Node2D:
		var n2d := node as Node2D
		if n2d.position != Vector2.ZERO:
			data["position"] = _vector2_to_array(n2d.position)
		if not is_zero_approx(n2d.rotation_degrees):
			data["rotation_degrees"] = n2d.rotation_degrees
		if n2d.scale != Vector2.ONE:
			data["scale"] = _vector2_to_array(n2d.scale)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		data["mesh_size"] = _vector3_to_array(((node as MeshInstance3D).mesh as BoxMesh).size)
	var node_groups: PackedStringArray = node.get_groups()
	if not node_groups.is_empty():
		data["groups"] = Array(node_groups)
	if include_properties:
		var props: Dictionary = {}
		for prop_info in node.get_property_list():
			if prop_info.usage & PROPERTY_USAGE_EDITOR == 0:
				continue
			var prop_name := String(prop_info.name)
			if prop_name.begins_with("_"):
				continue
			var value = node.get(prop_name)
			if value is Object:
				continue
			props[prop_name] = value
		data["properties"] = props
	return data

func _serialize_tree_detailed(node: Node, depth: int, max_depth: int) -> Dictionary:
	var data := _serialize_node_summary(node, false)
	if depth >= max_depth:
		var child_count: int = node.get_child_count()
		if child_count > 0:
			data["children_count"] = child_count
		return data
	var children: Array = []
	for child in node.get_children():
		children.append(_serialize_tree_detailed(child, depth + 1, max_depth))
	if not children.is_empty():
		data["children"] = children
	return data

func _get_node_by_path(node_path: String) -> Node:
	var root := _edited_root()
	if root == null or node_path.is_empty():
		return null
	return root.get_node_or_null(NodePath(node_path))

func _serialize_tree(node: Node, depth: int, max_depth: int) -> Dictionary:
	var data := {
		"name": node.name,
		"type": node.get_class(),
		"path": _rel_path(node)
	}
	if node is Node3D and (node as Node3D).position != Vector3.ZERO:
		data["position"] = _vector3_to_array((node as Node3D).position)
	elif node is Node2D and (node as Node2D).position != Vector2.ZERO:
		data["position"] = _vector2_to_array((node as Node2D).position)
	if depth >= max_depth:
		return data
	var children: Array = []
	for child in node.get_children():
		children.append(_serialize_tree(child, depth + 1, max_depth))
	if not children.is_empty():
		data["children"] = children
	return data

func _vector2_to_array(value: Vector2) -> Array:
	return [value.x, value.y]

func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _is_allowed_node_type(node_type: String) -> bool:
	if node_type in ALLOWED_NODE_TYPES:
		return true
	if not ClassDB.class_exists(node_type):
		return false
	for allowed in ALLOWED_NODE_TYPES:
		if ClassDB.is_parent_class(node_type, allowed):
			return true
	return false

func _make_unique_name(parent: Node, base_name: String) -> String:
	if parent.get_node_or_null(base_name) == null:
		return base_name
	var index := 2
	while parent.get_node_or_null("%s_%d" % [base_name, index]) != null:
		index += 1
	return "%s_%d" % [base_name, index]

func _property_exists(node: Node, property_name: String) -> bool:
	for prop_info in node.get_property_list():
		if String(prop_info.name) == property_name:
			return true
	return false

func _coerce_value(value):
	if value is Array:
		match value.size():
			2:
				return Vector2(float(value[0]), float(value[1]))
			3:
				return Vector3(float(value[0]), float(value[1]), float(value[2]))
			4:
				return Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return value

func _collect_files(path: String, extension: String, limit: int, result: Array[String]) -> void:
	if result.size() >= limit:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "" and result.size() < limit:
		if entry != "." and entry != "..":
			var full_path := path.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					_collect_files(full_path, extension, limit, result)
			elif extension.is_empty() or entry.ends_with(extension):
				result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
