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

const SpatialBoundsUtil := preload("res://addons/ai_assistant_plugin/scripts/spatial_bounds_util.gd")

var _editor_plugin: EditorPlugin = null
var _project_index: RefCounted = null
var _conversation_messages: Array = []

func setup(editor_plugin: EditorPlugin, project_index: RefCounted = null) -> void:
	_editor_plugin = editor_plugin
	_project_index = project_index

func set_project_index(project_index: RefCounted) -> void:
	_project_index = project_index

func set_conversation_context(messages: Array) -> void:
	_conversation_messages = messages.duplicate(true)

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
- get_scene_spatial_profile: params {"max_nodes":60} — world sizes, scales, floor Y levels of placed 3D objects (mapping intelligence)
- get_asset_bounds: params {"scene_path":"res://assets/stairs.tscn"} OR {"node_path":"Floor_1/Ground_05"} — local/world AABB size in meters (NOT scale); use before placing props
- get_scene_groups: params {} or {"group":"players"} to list nodes in one group
- get_input_map: params {} for project actions only, or {"action":"action_interact"} for one action
- get_runtime_errors: params {"max_count":20,"clear_after":false} — runtime debugger errors (requires F5 play mode first)
- get_script_errors: params {"script_path":"res://DoorScript.gd","clear_after":false} — GDScript parse errors + debugger buffer
- read_script: params {"script_path":"res://MainMenu/MainMenu.gd","max_chars":12000} — read .gd file content (use before editing)
- get_selection: params {}
- inspect_node: params {"node_path":"Root/Child"} (includes node groups)
- list_project_files: params {"path":"res://Data/SceneBuilder","extension":".tscn","limit":50}
- find_project_paths: params {"query":"Wall","path":"res://Data/SceneBuilder","extensions":[".tscn",".tres"],"limit":80}
- search_project_index: params {"query":"Wall Floor_2","kinds":["scenebuilder","scene","file"],"limit":24,"mode":"hybrid"} — hybrid lexical+semantic local search (modes: hybrid, semantic, lexical)
- search_conversation_context: params {"query":"settings UI bottom left","limit":5} — search prior chat messages when the user refers to something said earlier
- search_project_docs: params {"query":"CharacterBody3D move_and_slide","limit":12,"mode":"hybrid"} — project README/markdown + Godot ClassDB + global class_name docs (all local)
- resolve_project_path: params {"path":"res://data/SceneBuilder"} — fixes @ prefix and Linux case (Data vs data)
- list_scene_builder_catalog: params {"path":"res://Data/SceneBuilder"} — categories + sample asset paths
- get_tilemap_cells: params {"node_path":"Root/TileMapLayer","limit":200}

Asset placement:
- place_scene_builder_item: params {"item_path":"res://Data/SceneBuilder/Floor/Ground_05.tres","parent_node_path":"Floor_2","node_name":"Ground_05-n1","position":[-3.97,4,15.98],"scale":[100,100,100]}
  SceneBuilder only (optional plugin). parent_node_path MUST be a string (e.g. "Floor_2"). Alias parent_path also works. Floor_* containers are auto-created if missing.
- create_mesh_from_file: params {"mesh_path":"res://models/prop.glb","parent_node_path":"","node_name":"Prop","position":[0,0,0],"collision":true}
- instance_scene: params {"scene_path":"res://assets/stairs/stairs_022.tscn","parent_node_path":"","node_name":"Stairs1","position":[0,0,0],"scale":[100,100,100],"rotation_degrees":[0,90,0]}
  Use for ANY .tscn prefab (SceneBuilder or custom asset folders). BEFORE placing, call get_scene_spatial_profile + get_asset_bounds to match existing tile scale.

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
- ask_user: params {"question":"¿Altura de piso 3.5m o 4m?","choices":["3.5","4.0"]} — pauses agent until the user replies (does NOT consume a step)
- set_tilemap_cell: params {"node_path":"Root/TileMapLayer","coords":[3,4],"source_id":0,"atlas_coords":[0,0]}

Scripting (create AND attach a script in ONE call):
- create_script: params {"script_path":"res://scripts/Door.gd","attach_to":"Floor_1_exit/Door_02-n1","content":"extends Node3D\\n\\nfunc _ready():\\n\\tprint(\\"ready\\")\\n"}
  IMPORTANT: put the FULL script code in the "content" param (escape newlines as \\n). Do NOT put code in a separate markdown block. This single call writes the file and attaches it to attach_to (optional). The script is saved automatically.
- read_script: params {"script_path":"res://DoorScript.gd"} — returns file content; call BEFORE editing an existing script.
  attach_to paths: use "." for the scene ROOT node; use exact paths like "MainMenu/MenuPanel" for children. "MainMenu" alone may hit a child Control, not the root Node3D.
  create_script REFUSES attaching a DIFFERENT script file to a node that already has one — use read_script + create_script with the SAME script_path to edit it.

External plugin interaction:
- list_plugins: params {} — lists all enabled editor plugins and autoloads in the project
- inspect_plugin: params {"node_path":"Terrain3D"} OR {"class_name":"Terrain3D"} — lists public methods, properties and signals of any node or class (works for ANY plugin)
- call_node_method: params {"node_path":"Terrain3D","method":"set_brush_size","args":[5.0]} — calls any method on any node in the scene tree; use inspect_plugin first to discover available methods

Rules:
- ALWAYS wrap tool calls in <tool_call>{"tool":"...","params":{...}}</tool_call>. Never emit bare JSON tool objects or JSON arrays in the user-visible answer — the plugin executes tools and shows results separately.
- NEVER ask the user for InputMap action names, node groups, or debugger errors — call get_input_map, get_scene_groups, get_runtime_errors, or get_script_errors instead and fix with create_script/set_node_property.
- To discover assets, use search_project_index or find_project_paths anywhere under res:// (assets folders, SceneBuilder, etc.) — do NOT call list_project_files repeatedly from res:// (results truncate).
- SceneBuilder (res://Data/SceneBuilder) is OPTIONAL. Many projects use plain .tscn/.glb under res://assets/ — use instance_scene or create_mesh_from_file.
- For level building / map layout: call get_scene_spatial_profile first (reference sizes + floor heights), then get_asset_bounds on the prefab, then place with matching scale (often 1 or 100 — check world size, not scale alone).
- For Godot API / README / class_name docs, use search_project_docs (local ClassDB + project markdown).
- For design choices (floor height, layout), call ask_user with a clear question instead of guessing or stopping.
- After fixing scripts, call get_script_errors (or get_runtime_errors while the game runs) to verify; errors are cleared on read so the next check is fresh.
- Use res:// paths only. NEVER prefix paths with "@" (write res://... not @res://...).
- node_path / parent_node_path / attach_to are RELATIVE to the edited scene root (e.g. "Floor_1_exit/Ground_05"). Use "" for the root itself.
- There is NO save_script / create_node tool. Use read_script to read, create_script to write/attach, open_script to open in the editor.
- To actually perform the task, EXECUTE the editing tools. Do not stop after only inspecting and do not repeat the same plan.
- Match the script's `extends` to the target node type (inspect_node if unsure).
- Inspect the scene only when you truly need info, then act immediately (create_script, set_node_property, etc.).
- If the user asks for code to paste themselves ("dame el código", "yo lo hago"), reply with a ```gdscript block and do NOT call create_script.
- Before editing a script: read_script first, then create_script with the SAME script_path. Do NOT attach a different script file to a node that already has logic (breaks signals/buttons).
- For UI/menu styling: edit the EXISTING script (read_script → create_script same path) or use set_node_property for theme overrides. Do NOT create a separate "styler" script on the same node.
- Do NOT repeat save_scene + get_script_errors in a loop. Verify once after edits, then reply with a final summary.
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
		"get_scene_spatial_profile",
		"get_asset_bounds",
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
		"find_project_paths",
		"search_project_index",
		"search_conversation_context",
		"search_project_docs",
		"resolve_project_path",
		"list_scene_builder_catalog",
		"place_scene_builder_item",
		"create_mesh_from_file",
		"ask_user",
		"get_tilemap_cells",
		"set_tilemap_cell",
		"list_project_files",
		"inspect_node",
		"create_script",
		"open_script",
		"read_script",
		"save_script",
		"list_plugins",
		"inspect_plugin",
		"call_node_method",
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
		"get_scene_spatial_profile":
			result = _tool_get_scene_spatial_profile(params)
		"get_asset_bounds":
			result = _tool_get_asset_bounds(params)
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
		"find_project_paths":
			result = _tool_find_project_paths(params)
		"search_project_index":
			result = _tool_search_project_index(params)
		"search_conversation_context":
			result = _tool_search_conversation_context(params)
		"search_project_docs":
			result = _tool_search_project_docs(params)
		"resolve_project_path":
			result = _tool_resolve_project_path(params)
		"list_scene_builder_catalog":
			result = _tool_list_scene_builder_catalog(params)
		"place_scene_builder_item":
			result = _tool_place_scene_builder_item(params)
		"create_mesh_from_file":
			result = _tool_create_mesh_from_file(params)
		"ask_user":
			result = _tool_ask_user(params)
		"inspect_node":
			result = _tool_inspect_node(params)
		"create_script", "write_script":
			result = _tool_create_script(params)
		"open_script":
			result = _tool_open_script(params)
		"read_script":
			result = _tool_read_script(params)
		"save_script":
			result = {"ok": true, "status": "scripts are saved automatically by create_script"}
		"list_plugins":
			result = _tool_list_plugins()
		"inspect_plugin":
			result = _tool_inspect_plugin(params)
		"call_node_method":
			result = _tool_call_node_method(params)
		_:
			result = {"ok": false, "error": "Unknown tool: %s" % tool_name}
	
	tool_executed.emit(tool_name, result)
	return result

func _normalize_tool_params(value: Variant) -> Variant:
	# Models often copy the "@" mention prefix into paths (e.g. "@res://..."),
	# which breaks res:// validation. Strip it everywhere, recursively.
	# Los modelos copian el prefijo "@" de las menciones en las rutas (p. ej. "@res://..."),
	# lo que rompe la validación res://. Quitarlo en todas partes, recursivamente.
	if value == null:
		return ""
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
		if out.has("parent_path") and not out.has("parent_node_path"):
			out["parent_node_path"] = out["parent_path"]
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

func has_empty_tool_call_tags(text: String) -> bool:
	var tag_regex := RegEx.new()
	tag_regex.compile("(?is)<tool_call>\\s*</tool_call>")
	if tag_regex.search(text) == null:
		return false
	# Only "empty" if we also failed to extract any valid tool JSON
	# (the tag might contain multiline JSON that the parser now handles).
	# Solo "vacío" si tampoco pudimos extraer JSON válido
	# (el tag podría tener JSON multilínea que el parser ahora maneja).
	return extract_tool_call_json_strings(text).is_empty()

const READ_ONLY_TOOLS: Array[String] = [
	"get_scene_tree",
	"get_scene_snapshot",
	"get_scene_spatial_profile",
	"get_asset_bounds",
	"get_scene_groups",
	"get_input_map",
	"get_runtime_errors",
	"get_script_errors",
	"inspect_node",
	"get_selection",
	"list_project_files",
	"find_project_paths",
	"search_project_index",
	"search_conversation_context",
	"search_project_docs",
	"resolve_project_path",
	"list_scene_builder_catalog",
	"read_script",
	"ask_user",
	"get_tilemap_cells",
	"list_plugins",
	"inspect_plugin",
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
	"place_scene_builder_item",
	"create_mesh_from_file",
	"set_tilemap_cell",
	"create_scene",
	"call_node_method",
]

const VERIFY_ONLY_TOOLS: Array[String] = [
	"save_scene",
	"get_script_errors",
	"get_runtime_errors",
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
		if tool_name in VERIFY_ONLY_TOOLS:
			continue
		if is_mutating_tool(tool_name) and bool(entry.get("result", {}).get("ok", false)):
			return true
	return false

func batch_is_verify_only(tool_results: Array) -> bool:
	if tool_results.is_empty():
		return false
	for entry in tool_results:
		if not entry is Dictionary:
			return false
		if not bool(entry.get("result", {}).get("ok", false)):
			return false
		var tool_name: String = String(entry.get("tool", ""))
		if tool_name not in VERIFY_ONLY_TOOLS:
			return false
	return true

func batch_has_clean_script_check(tool_results: Array) -> bool:
	for entry in tool_results:
		if not entry is Dictionary:
			continue
		if String(entry.get("tool", "")) != "get_script_errors":
			continue
		var result: Dictionary = entry.get("result", {})
		if not bool(result.get("ok", false)):
			return false
		return int(result.get("count", 1)) == 0
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
		"get_scene_spatial_profile":
			return {
				"tool": tool_name,
				"ok": true,
				"scene_path": result.get("scene_path", ""),
				"floor_y_levels": result.get("floor_y_levels", []),
				"reference_ground": result.get("reference_ground", {}),
				"mapping_summary": result.get("mapping_summary", ""),
			}
		"get_asset_bounds":
			return {
				"tool": tool_name,
				"ok": true,
				"scene_path": result.get("scene_path", ""),
				"node_path": result.get("node_path", ""),
				"local_bounds_size": result.get("local_bounds_size", []),
				"world_bounds_size": result.get("world_bounds_size", []),
				"scale_hint": result.get("scale_hint", {}),
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
			if node.has("script"):
				slim_node["script"] = node.get("script", "")
			if node.has("script_missing"):
				slim_node["script_missing"] = true
			if node.has("groups"):
				slim_node["groups"] = node.get("groups", [])
			return {
				"tool": tool_name,
				"ok": true,
				"node": slim_node,
			}
		"read_script":
			var content: String = String(result.get("content", ""))
			return {
				"tool": tool_name,
				"ok": true,
				"script_path": result.get("script_path", ""),
				"lines": result.get("lines", 0),
				"truncated": bool(result.get("truncated", false)),
				"content": content if content.length() <= 4000 else content.substr(0, 4000) + "\n... (truncated)",
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
		"list_project_files", "find_project_paths", "search_project_index", "search_conversation_context", "search_project_docs", "list_scene_builder_catalog", "resolve_project_path":
			var files: Array = result.get("files", result.get("matches", result.get("categories", [])))
			var slim_result: Dictionary = {
				"tool": tool_name,
				"ok": true,
			}
			if result.has("path"):
				slim_result["path"] = result.get("path", "")
			if result.has("resolved"):
				slim_result["resolved"] = result.get("resolved", "")
			if result.has("query"):
				slim_result["query"] = result.get("query", "")
			if files is Array:
				slim_result["count"] = files.size()
				slim_result["items"] = files.slice(0, 20)
				slim_result["truncated"] = files.size() > 20
			elif result.has("categories"):
				slim_result["categories"] = result.get("categories", [])
			return slim_result
		"ask_user":
			return {
				"tool": tool_name,
				"ok": true,
				"awaiting_user": true,
				"question": result.get("question", ""),
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
		var parsed: Variant = _try_parse_json(trimmed)
		if parsed is Array:
			return summarize_tool_results_for_display(parsed)
	if trimmed.begins_with("{"):
		var parsed_obj: Variant = _try_parse_json(trimmed)
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
	# (?s) makes . match newlines so multiline JSON inside tags is captured
	# (?s) hace que . coincida con saltos de línea para capturar JSON multilínea
	tag_regex.compile("(?s)<tool_call>(.*?)</tool_call>")
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
	var parsed: Variant = _try_parse_json(block.strip_edges())
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
	var parsed: Variant = _try_parse_json(cleaned)
	if parsed != null:
		return parsed
	var repaired: String = cleaned
	repaired = repaired.replace("\"params\":{}", "\"params\": {}")
	repaired = repaired.replace("\"params:{\"", "\"params\": {}")
	repaired = repaired.replace("\"params:{", "\"params\": {")
	if repaired != cleaned:
		return _try_parse_json(repaired)
	return null

func _try_parse_json(text: String) -> Variant:
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.get_data()

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

func _tool_get_scene_spatial_profile(params: Dictionary = {}) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	var max_nodes := clampi(int(params.get("max_nodes", 60)), 8, 200)
	var name_filter: String = String(params.get("name_filter", "")).strip_edges().to_lower()
	var samples: Array = []
	_collect_spatial_samples(root, samples, max_nodes, name_filter)
	if samples.is_empty():
		return {
			"ok": true,
			"scene_path": root.scene_file_path,
			"samples": [],
			"mapping_summary": "No measurable 3D objects in the open scene yet.",
		}
	var floor_y_levels: Array = _cluster_y_levels(samples)
	var ground_stats: Dictionary = _aggregate_spatial_stats(samples, "ground")
	var wall_stats: Dictionary = _aggregate_spatial_stats(samples, "wall")
	var stair_stats: Dictionary = _aggregate_spatial_stats(samples, "stair")
	var mapping_summary: String = _build_mapping_summary(floor_y_levels, ground_stats, wall_stats, stair_stats)
	return {
		"ok": true,
		"scene_path": root.scene_file_path,
		"floor_y_levels": floor_y_levels,
		"reference_ground": ground_stats,
		"reference_wall": wall_stats,
		"reference_stairs": stair_stats,
		"samples": samples.slice(0, mini(samples.size(), 24)),
		"sample_count": samples.size(),
		"mapping_summary": mapping_summary,
	}

func _tool_get_asset_bounds(params: Dictionary) -> Dictionary:
	var scene_path := _resolve_res_path(String(params.get("scene_path", "")))
	var node_path := String(params.get("node_path", "")).strip_edges()
	var compare_to_scene: bool = bool(params.get("compare_to_scene", true))
	if not node_path.is_empty():
		var node := _get_node_by_path(node_path)
		if node == null:
			return {"ok": false, "error": "Node not found: %s" % node_path}
		if not node is Node3D:
			return {"ok": false, "error": "Node is not Node3D: %s" % node_path}
		var n3d := node as Node3D
		var local_aabb := SpatialBoundsUtil.compute_subtree_local_aabb(n3d)
		var world_aabb := SpatialBoundsUtil.compute_subtree_world_aabb(n3d)
		if not SpatialBoundsUtil.has_volume(local_aabb) and not SpatialBoundsUtil.has_volume(world_aabb):
			return {"ok": false, "error": "No mesh/collision bounds found on node: %s" % node_path}
		var out := {
			"ok": true,
			"node_path": _rel_path(n3d),
			"scale": _vector3_to_array(n3d.scale),
			"local_bounds_size": _vector3_to_array(local_aabb.size),
			"local_bounds_center": _vector3_to_array(local_aabb.get_center()),
			"world_bounds_size": _vector3_to_array(world_aabb.size),
			"world_bounds_center": _vector3_to_array(world_aabb.get_center()),
		}
		if compare_to_scene:
			out["scale_hint"] = _suggest_scale_for_asset(local_aabb.size)
		return out
	if scene_path.is_empty():
		return {"ok": false, "error": "Provide scene_path or node_path"}
	if not scene_path.begins_with("res://"):
		return {"ok": false, "error": "scene_path must start with res://"}
	if _project_index != null and _project_index.has_method("get_cached_scene_bounds"):
		var cached: Dictionary = _project_index.get_cached_scene_bounds(scene_path)
		if not cached.is_empty():
			var size_arr: Array = cached.get("local_bounds_size", [])
			var local_size := Vector3(
				float(size_arr[0]) if size_arr.size() > 0 else 0.0,
				float(size_arr[1]) if size_arr.size() > 1 else 0.0,
				float(size_arr[2]) if size_arr.size() > 2 else 0.0
			)
			var cached_result := {
				"ok": true,
				"scene_path": scene_path,
				"local_bounds_size": size_arr,
				"local_bounds_center": cached.get("local_bounds_center", []),
				"source": "index_cache",
				"note": "Cached at index sync (local AABB at scale 1,1,1 in meters).",
			}
			if compare_to_scene:
				cached_result["scale_hint"] = _suggest_scale_for_asset(local_size)
			return cached_result
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return {"ok": false, "error": "Could not load scene: %s" % scene_path}
	var temp: Node = packed.instantiate()
	var local_aabb := SpatialBoundsUtil.compute_subtree_local_aabb(temp)
	temp.free()
	if not SpatialBoundsUtil.has_volume(local_aabb):
		return {"ok": false, "error": "No mesh/collision bounds found in scene: %s" % scene_path}
	var result := {
		"ok": true,
		"scene_path": scene_path,
		"local_bounds_size": _vector3_to_array(local_aabb.size),
		"local_bounds_center": _vector3_to_array(local_aabb.get_center()),
		"note": "Sizes are at scale (1,1,1) — local mesh/collision AABB in meters.",
	}
	if compare_to_scene:
		result["scale_hint"] = _suggest_scale_for_asset(local_aabb.size)
	return result

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
	var clear_after: bool = bool(params.get("clear_after", false))
	var bridge: EditorDebuggerPlugin = _debugger_error_bridge()
	var errors: Array = []
	if bridge != null and bridge.has_method("fetch_errors"):
		errors = bridge.fetch_errors(clear_after, max_count)
	var hint: String = ""
	if errors.is_empty():
		hint = (
			"No runtime errors captured. Run the game (F5) to reproduce, then call this tool again. "
			+ "Parse-only checks use get_script_errors; runtime node errors appear here after play."
		)
	return {
		"ok": true,
		"count": errors.size(),
		"errors": errors,
		"cleared": clear_after,
		"hint": hint,
	}

func _tool_get_script_errors(params: Dictionary = {}) -> Dictionary:
	var script_path: String = String(params.get("script_path", "")).strip_edges()
	var clear_after: bool = bool(params.get("clear_after", false))
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
	var hint: String = ""
	if errors.is_empty():
		hint = (
			"No errors found. Note: get_script_errors checks parse errors + debugger buffer. "
			+ "Runtime errors (Node not found, etc.) require running the game (F5) first, "
			+ "then call get_runtime_errors or pass script_path explicitly."
		)
	return {
		"ok": true,
		"count": errors.size(),
		"errors": errors,
		"cleared": clear_after,
		"hint": hint,
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
	var scene_path := _resolve_res_path(String(params.get("scene_path", "")))
	var parent_path := String(params.get("parent_node_path", params.get("parent_path", "")))
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
	
	var parent_resolved: Dictionary = _resolve_or_create_parent(parent_path)
	if not bool(parent_resolved.get("ok", false)):
		return parent_resolved
	var parent_node: Node = parent_resolved.get("node")
	
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
	var rotation_array: Array = params.get("rotation_degrees", params.get("rotation", []))
	if instance is Node3D and rotation_array.size() >= 3:
		(instance as Node3D).rotation_degrees = Vector3(
			float(rotation_array[0]), float(rotation_array[1]), float(rotation_array[2])
		)
	var scale_array: Array = params.get("scale", [])
	if instance is Node3D and scale_array.size() >= 3:
		(instance as Node3D).scale = Vector3(float(scale_array[0]), float(scale_array[1]), float(scale_array[2]))
	
	_mark_unsaved()
	var result := {"ok": true, "node_path": _rel_path(instance), "instance_of": scene_path}
	if instance is Node3D:
		var world_aabb := SpatialBoundsUtil.compute_subtree_world_aabb(instance as Node3D)
		if SpatialBoundsUtil.has_volume(world_aabb):
			result["world_bounds_size"] = _vector3_to_array(world_aabb.size)
			result["world_bounds_center"] = _vector3_to_array(world_aabb.get_center())
		result["scale"] = _vector3_to_array((instance as Node3D).scale)
	if bool(parent_resolved.get("created", false)):
		result["parent_created"] = _rel_path(parent_node)
	return result

func _resolve_or_create_parent(parent_path: String) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	if parent_path.is_empty():
		return {"ok": true, "node": root}
	var existing: Node = root.get_node_or_null(NodePath(parent_path))
	if existing != null:
		return {"ok": true, "node": existing}
	if not _looks_like_floor_container_name(parent_path):
		return {"ok": false, "error": "Parent not found: %s" % parent_path}
	var segments: PackedStringArray = parent_path.split("/", false)
	var attach_parent: Node = root
	for i in segments.size():
		var partial := "/".join(segments.slice(0, i + 1))
		var node: Node = root.get_node_or_null(NodePath(partial))
		if node == null:
			var container := Node3D.new()
			container.name = segments[i]
			attach_parent.add_child(container)
			container.owner = root
			node = container
			_mark_unsaved()
		attach_parent = node
	return {"ok": true, "node": attach_parent, "created": true}

func _looks_like_floor_container_name(parent_path: String) -> bool:
	var leaf: String = parent_path.get_file()
	return leaf.begins_with("Floor_") or leaf.begins_with("floor_") or leaf.begins_with("Level_")

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
	var root_path := _resolve_res_path(String(params.get("path", "res://")))
	if root_path.is_empty():
		return {"ok": false, "error": "Invalid or missing path (use res://...)"}
	var extension := String(params.get("extension", ""))
	var limit := clampi(int(params.get("limit", 50)), 1, 200)
	var pattern := String(params.get("pattern", "")).to_lower()
	var files: Array[String] = []
	_collect_files(root_path, extension, pattern, limit, files)
	return {
		"ok": true,
		"path": root_path,
		"files": files,
		"count": files.size(),
		"truncated": files.size() >= limit,
	}

func _tool_find_project_paths(params: Dictionary) -> Dictionary:
	var root_path := _resolve_res_path(String(params.get("path", "res://")))
	if root_path.is_empty():
		return {"ok": false, "error": "Invalid or missing path (use res://...)"}
	var query := String(params.get("query", params.get("pattern", ""))).strip_edges().to_lower()
	if query.is_empty():
		return {"ok": false, "error": "query is required (e.g. Wall, Door, Ground)"}
	var extensions: Array = params.get("extensions", [".tscn", ".tres", ".glb", ".gltf"])
	var limit := clampi(int(params.get("limit", 80)), 1, 200)
	if _project_index != null and _project_index.has_method("is_ready") and _project_index.is_ready():
		var kinds: Array = ["scenebuilder", "file"]
		if root_path == "res://" or "scenebuilder" in root_path.to_lower():
			kinds = ["scenebuilder", "file", "scene"]
		var hits: Array = _project_index.search(query, kinds, limit * 2)
		var matches: Array[String] = []
		for hit in hits:
			if not hit is Dictionary:
				continue
			var entry: Dictionary = hit.get("entry", {})
			var candidate: String = String(entry.get("path", entry.get("tres", entry.get("scene", ""))))
			if candidate.is_empty():
				candidate = String(entry.get("scene", ""))
			if candidate.is_empty():
				continue
			if root_path != "res://" and not candidate.begins_with(root_path):
				continue
			for ext in extensions:
				if candidate.ends_with(String(ext)):
					if not matches.has(candidate):
						matches.append(candidate)
					break
			if matches.size() >= limit:
				break
		if not matches.is_empty():
			return {
				"ok": true,
				"path": root_path,
				"query": query,
				"matches": matches,
				"count": matches.size(),
				"truncated": matches.size() >= limit,
				"source": "project_index",
			}
	var matches_fs: Array[String] = []
	_find_matching_files(root_path, query, extensions, limit, matches_fs)
	return {
		"ok": true,
		"path": root_path,
		"query": query,
		"matches": matches_fs,
		"count": matches_fs.size(),
		"truncated": matches_fs.size() >= limit,
	}

func _tool_search_project_index(params: Dictionary) -> Dictionary:
	if _project_index == null or not _project_index.has_method("is_ready") or not _project_index.is_ready():
		return {
			"ok": false,
			"error": "Project index not ready. Open Config → Indexing and run Sync Now.",
		}
	var query := String(params.get("query", "")).strip_edges()
	if query.is_empty():
		return {"ok": false, "error": "query is required (e.g. Wall Floor_2 DoorScript)"}
	var kinds: Array = params.get("kinds", [])
	var mode := String(params.get("mode", "hybrid")).strip_edges().to_lower()
	if mode.is_empty():
		mode = "hybrid"
	var limit := clampi(int(params.get("limit", 24)), 1, 100)
	var hits: Array = _project_index.search(query, kinds, limit, mode)
	var matches: Array = []
	for hit in hits:
		if not hit is Dictionary:
			continue
		var entry: Dictionary = hit.get("entry", {})
		matches.append({
			"kind": hit.get("kind", ""),
			"score": hit.get("score", 0.0),
			"source": hit.get("source", mode),
			"path": entry.get("path", entry.get("tres", entry.get("scene", ""))),
			"item": entry.get("item", entry.get("name", "")),
			"category": entry.get("category", ""),
			"preview": entry.get("preview", ""),
			"local_bounds_size": entry.get("local_bounds_size", []),
		})
	return {
		"ok": true,
		"query": query,
		"mode": mode,
		"semantic_ready": _project_index.is_semantic_ready() if _project_index.has_method("is_semantic_ready") else false,
		"matches": matches,
		"count": matches.size(),
	}

func _tool_search_conversation_context(params: Dictionary) -> Dictionary:
	var query := String(params.get("query", "")).strip_edges()
	if query.is_empty():
		return {"ok": false, "error": "query is required (e.g. settings UI, bottom left menu)"}
	var limit := clampi(int(params.get("limit", 5)), 1, 20)
	if _conversation_messages.is_empty():
		return {
			"ok": true,
			"query": query,
			"matches": [],
			"count": 0,
			"hint": "No conversation history loaded for this request.",
		}
	var terms: PackedStringArray = PackedStringArray()
	for raw_term in query.split(" ", false):
		var term: String = raw_term.strip_edges().to_lower()
		if term.length() >= 2:
			terms.append(term)
	var lower_q: String = query.to_lower()
	var scored: Array = []
	for item in _conversation_messages:
		if not item is Dictionary:
			continue
		var content: String = String(item.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		var lower_c: String = content.to_lower()
		var score: float = 0.0
		if lower_q.length() >= 3 and lower_c.contains(lower_q):
			score += 4.0
		for term in terms:
			if lower_c.contains(term):
				score += 1.0
		if score <= 0.0:
			continue
		var excerpt: String = content
		if excerpt.length() > 900:
			excerpt = excerpt.substr(0, 900) + "\n...(truncated)"
		scored.append({
			"role": String(item.get("role", "")),
			"score": score,
			"excerpt": excerpt,
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	var matches: Array = scored.slice(0, limit)
	return {
		"ok": true,
		"query": query,
		"matches": matches,
		"count": matches.size(),
	}

func _tool_search_project_docs(params: Dictionary) -> Dictionary:
	if _project_index == null or not _project_index.has_method("is_ready") or not _project_index.is_ready():
		return {
			"ok": false,
			"error": "Project index not ready. Open Config → Indexing and run Sync Now.",
		}
	var query := String(params.get("query", "")).strip_edges()
	if query.is_empty():
		return {"ok": false, "error": "query is required (e.g. CharacterBody3D, move_and_slide, README)"}
	var mode := String(params.get("mode", "hybrid")).strip_edges().to_lower()
	if mode.is_empty():
		mode = "hybrid"
	var limit := clampi(int(params.get("limit", 12)), 1, 50)
	var hits: Array = []
	if _project_index.has_method("search_docs"):
		hits = _project_index.search_docs(query, limit, mode)
	else:
		hits = _project_index.search(query, ["doc"], limit, mode)
	var matches: Array = []
	for hit in hits:
		if not hit is Dictionary:
			continue
		var entry: Dictionary = hit.get("entry", {})
		matches.append({
			"kind": "doc",
			"score": hit.get("score", 0.0),
			"source": entry.get("source", hit.get("source", "")),
			"title": entry.get("title", ""),
			"path": entry.get("path", ""),
			"preview": entry.get("preview", ""),
		})
	return {
		"ok": true,
		"query": query,
		"mode": mode,
		"matches": matches,
		"count": matches.size(),
	}

func _tool_resolve_project_path(params: Dictionary) -> Dictionary:
	var raw := String(params.get("path", "")).strip_edges()
	if raw.is_empty():
		return {"ok": false, "error": "path is required"}
	var resolved := _resolve_res_path(raw)
	if resolved.is_empty():
		return {"ok": false, "error": "Path not found: %s" % raw, "tried": raw}
	var exists_as_dir := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(resolved))
	var exists_as_file := FileAccess.file_exists(resolved)
	return {
		"ok": true,
		"requested": raw,
		"resolved": resolved,
		"is_dir": exists_as_dir,
		"is_file": exists_as_file,
	}

func _tool_list_scene_builder_catalog(params: Dictionary) -> Dictionary:
	var root_path := _resolve_res_path(String(params.get("path", "res://Data/SceneBuilder")))
	if root_path.is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root_path)):
		root_path = _resolve_res_path("res://Data/SceneBuilder")
	if root_path.is_empty():
		return {"ok": false, "error": "SceneBuilder folder not found (expected res://Data/SceneBuilder)"}
	var categories: Array = []
	var dir := DirAccess.open(root_path)
	if dir == null:
		return {"ok": false, "error": "Cannot open %s" % root_path}
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != ".." and dir.current_is_dir():
			var category_path := root_path.path_join(entry)
			var sample_paths: Array[String] = []
			var category_files: Array[String] = []
			_find_matching_files(category_path, "", [".tres", ".tscn"], 500, category_files)
			for i in mini(6, category_files.size()):
				sample_paths.append(category_files[i])
			categories.append({
				"category": entry,
				"path": category_path,
				"file_count": category_files.size(),
				"samples": sample_paths,
				"scenes_folder": category_path.path_join("scenes"),
			})
		entry = dir.get_next()
	dir.list_dir_end()
	categories.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("category", "")) < String(b.get("category", ""))
	)
	return {"ok": true, "path": root_path, "categories": categories}

func _tool_ask_user(params: Dictionary) -> Dictionary:
	var question := String(params.get("question", params.get("message", ""))).strip_edges()
	if question.is_empty():
		return {"ok": false, "error": "question is required"}
	var choices: Array = params.get("choices", [])
	var payload := {
		"ok": true,
		"awaiting_user": true,
		"question": question,
	}
	if choices is Array and not choices.is_empty():
		payload["choices"] = choices
	return payload

func _tool_place_scene_builder_item(params: Dictionary) -> Dictionary:
	var item_path := _resolve_res_path(String(params.get("item_path", params.get("scene_path", ""))))
	if item_path.is_empty():
		return {"ok": false, "error": "item_path must be res://.../*.tres or *.tscn"}
	var scene_path := _scene_path_from_scene_builder_item(item_path)
	if scene_path.is_empty():
		return {"ok": false, "error": "Could not resolve SceneBuilder scene for: %s" % item_path}
	var instance_params: Dictionary = {
		"scene_path": scene_path,
		"parent_node_path": String(params.get("parent_node_path", params.get("parent_path", ""))),
		"node_name": String(params.get("node_name", "")),
		"position": params.get("position", []),
	}
	var result := _tool_instance_scene(instance_params)
	if not bool(result.get("ok", false)):
		return result
	var node := _get_node_by_path(String(result.get("node_path", "")))
	if node == null or not node is Node3D:
		return result
	var node3d := node as Node3D
	var rotation_array: Array = params.get("rotation_degrees", params.get("rotation", []))
	if rotation_array.size() >= 3:
		node3d.rotation_degrees = Vector3(
			float(rotation_array[0]), float(rotation_array[1]), float(rotation_array[2])
		)
	var scale_array: Array = params.get("scale", [])
	if scale_array.size() >= 3:
		node3d.scale = Vector3(float(scale_array[0]), float(scale_array[1]), float(scale_array[2]))
	_mark_unsaved()
	result["item_path"] = item_path
	result["scene_path"] = scene_path
	result["rotation_degrees"] = _vector3_to_array(node3d.rotation_degrees)
	result["scale"] = _vector3_to_array(node3d.scale)
	return result

func _tool_create_mesh_from_file(params: Dictionary) -> Dictionary:
	var root := _edited_root()
	if root == null:
		return {"ok": false, "error": "No scene loaded"}
	var mesh_path := _resolve_res_path(String(params.get("mesh_path", params.get("path", ""))))
	if mesh_path.is_empty():
		return {"ok": false, "error": "mesh_path must be res://... (glb, gltf, tscn, mesh, obj)"}
	var parent_path := String(params.get("parent_node_path", ""))
	var node_name := String(params.get("node_name", mesh_path.get_file().get_basename()))
	var parent_node: Node = root
	if not parent_path.is_empty():
		parent_node = root.get_node_or_null(NodePath(parent_path))
		if parent_node == null:
			return {"ok": false, "error": "Parent not found: %s" % parent_path}
	var resource: Variant = load(mesh_path)
	if resource == null:
		return {"ok": false, "error": "Could not load: %s" % mesh_path}
	var created_node: Node3D = null
	var use_collision: bool = bool(params.get("collision", false))
	if resource is PackedScene:
		var packed := resource as PackedScene
		var instance: Node = packed.instantiate()
		if instance is Node3D:
			created_node = instance as Node3D
		else:
			return {"ok": false, "error": "Scene root is not Node3D: %s" % mesh_path}
	elif resource is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = resource as Mesh
		created_node = mesh_instance
	else:
		return {"ok": false, "error": "Unsupported resource type for %s" % mesh_path}
	created_node.name = _make_unique_name(parent_node, node_name)
	if use_collision and created_node is MeshInstance3D:
		var body := StaticBody3D.new()
		body.name = _make_unique_name(parent_node, node_name + "Body")
		var collision_shape := CollisionShape3D.new()
		var source_mesh: Mesh = (created_node as MeshInstance3D).mesh
		if source_mesh:
			collision_shape.shape = source_mesh.create_trimesh_shape()
		body.add_child(collision_shape)
		collision_shape.owner = root
		parent_node.add_child(body)
		body.owner = root
		body.add_child(created_node)
		created_node.owner = root
		created_node = body
	else:
		parent_node.add_child(created_node)
		created_node.owner = root
	var position: Array = params.get("position", [])
	if position.size() >= 3:
		created_node.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	var rotation_array: Array = params.get("rotation_degrees", params.get("rotation", []))
	if rotation_array.size() >= 3:
		created_node.rotation_degrees = Vector3(
			float(rotation_array[0]), float(rotation_array[1]), float(rotation_array[2])
		)
	var scale_array: Array = params.get("scale", [])
	if scale_array.size() >= 3:
		created_node.scale = Vector3(float(scale_array[0]), float(scale_array[1]), float(scale_array[2]))
	_mark_unsaved()
	return {
		"ok": true,
		"node_path": _rel_path(created_node),
		"mesh_path": mesh_path,
		"collision": use_collision,
		"position": _vector3_to_array(created_node.position),
	}

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
	
	if not attach_to.is_empty():
		var target := _get_node_by_path(attach_to)
		if target and target.get_script() != null:
			var existing_path: String = ""
			if target.get_script() is Script:
				existing_path = (target.get_script() as Script).resource_path
			var broken_ref: bool = (
				not existing_path.is_empty()
				and not FileAccess.file_exists(existing_path)
			)
			if (
				not existing_path.is_empty()
				and existing_path != script_path
				and not broken_ref
				and not bool(params.get("replace_script", false))
			):
				return {
					"ok": false,
					"error": (
						"Node '%s' already has script '%s'. "
						+ "Use read_script + create_script with the SAME script_path to edit it, "
						+ "or attach_to '.' if you meant the scene root (not a child named MainMenu)."
					) % [attach_to, existing_path],
					"existing_script": existing_path,
					"hint": "Call read_script first, then create_script with the same script_path.",
				}
	
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

func _tool_read_script(params: Dictionary) -> Dictionary:
	var script_path := String(params.get("script_path", params.get("file_path", "")))
	if script_path.is_empty() or not script_path.ends_with(".gd"):
		return {"ok": false, "error": "script_path must be res://.../*.gd"}
	if not FileAccess.file_exists(script_path):
		return {"ok": false, "error": "Script does not exist: %s" % script_path}
	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not read script: %s" % script_path}
	var content: String = file.get_as_text()
	file.close()
	var max_chars: int = clampi(int(params.get("max_chars", 12000)), 500, 32000)
	var truncated: bool = content.length() > max_chars
	if truncated:
		content = content.substr(0, max_chars)
	return {
		"ok": true,
		"script_path": script_path,
		"content": content,
		"lines": content.split("\n").size(),
		"truncated": truncated,
	}

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
	if node.get_script() != null and node.get_script() is Script:
		var script_path: String = (node.get_script() as Script).resource_path
		if not script_path.is_empty():
			data["script"] = script_path
			if not FileAccess.file_exists(script_path):
				data["script_missing"] = true
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
				if prop_name == "script" and node.get_script() is Script:
					props[prop_name] = (node.get_script() as Script).resource_path
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
	if root == null:
		return null
	var trimmed := node_path.strip_edges()
	if trimmed.is_empty() or trimmed == ".":
		return root
	return root.get_node_or_null(NodePath(trimmed))

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

func _collect_files(path: String, extension: String, pattern: String, limit: int, result: Array[String]) -> void:
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
					_collect_files(full_path, extension, pattern, limit, result)
			elif _file_matches_query(full_path, entry, extension, pattern):
				result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()

func _find_matching_files(
	path: String,
	query: String,
	extensions: Array,
	limit: int,
	result: Array[String]
) -> void:
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
					_find_matching_files(full_path, query, extensions, limit, result)
			elif _file_matches_extensions(entry, extensions):
				var haystack := full_path.to_lower()
				if query.is_empty() or query in haystack or query in entry.to_lower():
					result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()

func _file_matches_extensions(file_name: String, extensions: Array) -> bool:
	if extensions.is_empty():
		return true
	for ext in extensions:
		if file_name.ends_with(String(ext)):
			return true
	return false

func _file_matches_query(full_path: String, file_name: String, extension: String, pattern: String) -> bool:
	if not extension.is_empty() and not file_name.ends_with(extension):
		return false
	if pattern.is_empty():
		return true
	var lower_path := full_path.to_lower()
	var lower_name := file_name.to_lower()
	return pattern in lower_path or pattern in lower_name

func _resolve_res_path(raw: String) -> String:
	var path := raw.strip_edges()
	if path.is_empty():
		return ""
	if path.begins_with("@res://"):
		path = path.substr(1)
	elif path.begins_with("@/"):
		path = "res://" + path.substr(2)
	elif not path.begins_with("res://"):
		if path.begins_with("/"):
			path = "res:/" + path
		else:
			path = "res://" + path.trim_prefix("/")
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return path
	return _case_insensitive_res_path(path)

func _case_insensitive_res_path(path: String) -> String:
	if not path.begins_with("res://"):
		return ""
	var relative := path.substr(6)
	if relative.is_empty():
		return "res://"
	var segments: PackedStringArray = relative.split("/", false)
	var current := "res://"
	for segment in segments:
		if segment.is_empty():
			continue
		var resolved := _match_dir_entry(current, segment)
		if resolved.is_empty():
			return ""
		current = current.path_join(resolved)
	if FileAccess.file_exists(current) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(current)):
		return current
	return ""

func _match_dir_entry(parent_res_path: String, wanted: String) -> String:
	if FileAccess.file_exists(parent_res_path.path_join(wanted)):
		return wanted
	var dir := DirAccess.open(parent_res_path)
	if dir == null:
		return ""
	var wanted_lower := wanted.to_lower()
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if entry.to_lower() == wanted_lower:
				dir.list_dir_end()
				return entry
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _scene_path_from_scene_builder_item(item_path: String) -> String:
	if item_path.ends_with(".tscn"):
		return item_path if FileAccess.file_exists(item_path) else ""
	var resource: Variant = load(item_path)
	if resource != null:
		var uid_str := ""
		if resource.get("uid"):
			uid_str = String(resource.get("uid"))
		if not uid_str.is_empty() and ResourceUID.has_id(ResourceUID.text_to_id(uid_str)):
			return ResourceUID.get_id_path(ResourceUID.text_to_id(uid_str))
	var base_name := item_path.get_file().get_basename()
	var scenes_candidate := item_path.get_base_dir().path_join("scenes").path_join(base_name + ".tscn")
	if FileAccess.file_exists(scenes_candidate):
		return scenes_candidate
	return ""

# --- Spatial mapping / mapeo espacial (AABB world size, not scale) ---

func _spatial_name_category(node_name: String) -> String:
	var lower := node_name.to_lower()
	if lower.contains("ground") or lower.contains("floor") or lower.contains("tile"):
		return "ground"
	if lower.contains("wall"):
		return "wall"
	if lower.contains("stair") or lower.contains("step") or lower.contains("ramp"):
		return "stair"
	if lower.contains("door"):
		return "door"
	return "other"

func _collect_spatial_samples(node: Node, samples: Array, max_nodes: int, name_filter: String) -> void:
	if samples.size() >= max_nodes:
		return
	if node is Node3D:
		var n3d := node as Node3D
		var category := _spatial_name_category(String(node.name))
		if name_filter.is_empty() or String(node.name).to_lower().contains(name_filter) or category.contains(name_filter):
			var world_aabb := SpatialBoundsUtil.compute_subtree_world_aabb(n3d)
			if SpatialBoundsUtil.has_volume(world_aabb):
				var local_aabb := SpatialBoundsUtil.compute_subtree_local_aabb(n3d)
				samples.append({
					"path": _rel_path(n3d),
					"name": String(node.name),
					"category": category,
					"position": _vector3_to_array(n3d.global_position),
					"scale": _vector3_to_array(n3d.scale),
					"local_bounds_size": _vector3_to_array(local_aabb.size),
					"world_bounds_size": _vector3_to_array(world_aabb.size),
				})
	for child in node.get_children():
		_collect_spatial_samples(child, samples, max_nodes, name_filter)

func _cluster_y_levels(samples: Array) -> Array:
	var y_values: Array = []
	for sample in samples:
		if not sample is Dictionary:
			continue
		var category: String = String(sample.get("category", ""))
		if category != "ground" and category != "stair" and category != "door":
			continue
		var pos: Array = sample.get("position", [])
		if pos.size() >= 2:
			y_values.append(snappedf(float(pos[1]), 0.25))
	y_values.sort()
	var levels: Array = []
	var last_y: float = -99999.0
	for y in y_values:
		var yf: float = float(y)
		if levels.is_empty() or absf(yf - last_y) > 0.35:
			levels.append(yf)
			last_y = yf
	return levels

func _aggregate_spatial_stats(samples: Array, category: String) -> Dictionary:
	var matched: Array = []
	for sample in samples:
		if sample is Dictionary and String(sample.get("category", "")) == category:
			matched.append(sample)
	if matched.is_empty():
		return {"count": 0}
	var scales_x: Array = []
	var world_x: Array = []
	var world_y: Array = []
	var world_z: Array = []
	for sample in matched:
		var scale_arr: Array = sample.get("scale", [])
		var world_arr: Array = sample.get("world_bounds_size", [])
		if scale_arr.size() >= 1:
			scales_x.append(float(scale_arr[0]))
		if world_arr.size() >= 3:
			world_x.append(float(world_arr[0]))
			world_y.append(float(world_arr[1]))
			world_z.append(float(world_arr[2]))
	return {
		"count": matched.size(),
		"median_scale_x": _median_float(scales_x),
		"median_world_size": [
			_median_float(world_x),
			_median_float(world_y),
			_median_float(world_z),
		],
		"examples": matched.slice(0, 3),
	}

func _median_float(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5

func _build_mapping_summary(
	floor_y_levels: Array,
	ground_stats: Dictionary,
	wall_stats: Dictionary,
	stair_stats: Dictionary
) -> String:
	var parts: PackedStringArray = []
	if not floor_y_levels.is_empty():
		var level_strings: PackedStringArray = []
		for y in floor_y_levels:
			level_strings.append(str(y))
		parts.append("Floor Y levels (m): %s" % ", ".join(level_strings))
	if int(ground_stats.get("count", 0)) > 0:
		var gsize: Array = ground_stats.get("median_world_size", [])
		parts.append(
			"Reference floor tile world size ~%.2f x %.2f m (median), typical scale.x=%.1f"
			% [float(gsize[0]) if gsize.size() > 0 else 0.0, float(gsize[2]) if gsize.size() > 2 else 0.0, ground_stats.get("median_scale_x", 1.0)]
		)
	if int(wall_stats.get("count", 0)) > 0:
		var wsize: Array = wall_stats.get("median_world_size", [])
		parts.append(
			"Reference wall world height ~%.2f m, typical scale.x=%.1f"
			% [float(wsize[1]) if wsize.size() > 1 else 0.0, wall_stats.get("median_scale_x", 1.0)]
		)
	if int(stair_stats.get("count", 0)) > 0:
		var ssize: Array = stair_stats.get("median_world_size", [])
		parts.append(
			"Existing stairs world size ~%.2f x %.2f x %.2f m"
			% [
				float(ssize[0]) if ssize.size() > 0 else 0.0,
				float(ssize[1]) if ssize.size() > 1 else 0.0,
				float(ssize[2]) if ssize.size() > 2 else 0.0,
			]
		)
	parts.append(
		"Before placing a new prefab: get_asset_bounds(scene_path) and scale so world size matches references (scale 1 vs 100 depends on mesh import, not uniform across projects)."
	)
	return " | ".join(parts)

func _suggest_scale_for_asset(local_size: Vector3) -> Dictionary:
	var root := _edited_root()
	if root == null or local_size.length_squared() <= 0.000001:
		return {}
	var profile := _tool_get_scene_spatial_profile({"max_nodes": 80})
	if not bool(profile.get("ok", false)):
		return {}
	var ground_stats: Dictionary = profile.get("reference_ground", {})
	var ref_size: Array = ground_stats.get("median_world_size", [])
	if ref_size.size() < 3 or int(ground_stats.get("count", 0)) <= 0:
		return {"note": "No ground reference in scene — inspect nearby nodes manually."}
	var ref_x: float = maxf(float(ref_size[0]), 0.01)
	var ref_z: float = maxf(float(ref_size[2]), 0.01)
	var asset_x: float = maxf(local_size.x, 0.0001)
	var asset_z: float = maxf(local_size.z, 0.0001)
	var uniform: float = maxf(ref_x / asset_x, ref_z / asset_z)
	var median_scale: float = float(ground_stats.get("median_scale_x", 1.0))
	return {
		"suggested_uniform_scale": snappedf(uniform, 0.01),
		"reference_ground_world_size": ref_size,
		"asset_local_size_at_scale_1": _vector3_to_array(local_size),
		"note": "Multiply prefab scale by suggested_uniform_scale so footprint matches existing floor tiles.",
		"nearby_typical_scale": median_scale,
	}

# ── External plugin tools / Herramientas para plugins externos ──

func _tool_list_plugins() -> Dictionary:
	# Lists all enabled editor plugins and autoloads in the project.
	# Lista todos los plugins de editor y autoloads activos.
	var result: Dictionary = {"ok": true, "editor_plugins": [], "autoloads": []}

	# Enabled editor plugins from project settings
	# Plugins de editor habilitados desde project settings
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	for entry in enabled:
		var clean: String = entry.strip_edges()
		if clean.begins_with("res://"):
			result["editor_plugins"].append(clean)

	# Autoloads (singletons) — often how gameplay plugins register
	# Autoloads (singletons) — así se registran muchos plugins de gameplay
	for prop in ProjectSettings.get_property_list():
		var pname: String = prop.get("name", "")
		if pname.begins_with("autoload/"):
			var autoload_name: String = pname.trim_prefix("autoload/")
			var autoload_path: String = String(ProjectSettings.get_setting(pname, ""))
			result["autoloads"].append({"name": autoload_name, "path": autoload_path})

	return result

func _tool_inspect_plugin(params: Dictionary) -> Dictionary:
	# Inspects a node or class: lists public methods, properties and signals.
	# Works for any node in the tree or any class registered in ClassDB.
	# Inspecciona un nodo o clase: lista métodos, propiedades y señales públicas.
	var node_path: String = String(params.get("node_path", "")).strip_edges()
	var class_name_param: String = String(params.get("class_name", "")).strip_edges()
	var limit: int = int(params.get("limit", 40))

	var target_class: String = ""
	var target_node: Node = null

	if not node_path.is_empty():
		target_node = _get_node_by_path(node_path)
		if target_node == null:
			# ponytail: also try scene tree root children by name
			var tree := Engine.get_main_loop() as SceneTree
			if tree and tree.root:
				target_node = tree.root.find_child(node_path, true, false)
		if target_node == null:
			return {"ok": false, "error": "Node '%s' not found in scene tree" % node_path}
		target_class = target_node.get_class()
	elif not class_name_param.is_empty():
		if ClassDB.class_exists(class_name_param):
			target_class = class_name_param
		else:
			return {"ok": false, "error": "Class '%s' not found in ClassDB" % class_name_param}
	else:
		return {"ok": false, "error": "Provide node_path or class_name"}

	var info: Dictionary = {
		"ok": true,
		"class": target_class,
		"methods": [],
		"properties": [],
		"signals": [],
	}

	# Methods / Métodos
	var methods: Array = []
	if target_node:
		methods = target_node.get_method_list()
	elif ClassDB.class_exists(target_class):
		methods = ClassDB.class_get_method_list(target_class, true)
	var method_count: int = 0
	for m in methods:
		var mname: String = m.get("name", "")
		if mname.begins_with("_") or mname.is_empty():
			continue
		var args_list: Array = []
		for arg in m.get("args", []):
			args_list.append(arg.get("name", "?"))
		info["methods"].append({"name": mname, "args": args_list})
		method_count += 1
		if method_count >= limit:
			break

	# Properties / Propiedades
	var props: Array = []
	if target_node:
		props = target_node.get_property_list()
	elif ClassDB.class_exists(target_class):
		props = ClassDB.class_get_property_list(target_class, true)
	var prop_count: int = 0
	for p in props:
		var pname: String = p.get("name", "")
		if pname.begins_with("_") or pname.is_empty():
			continue
		var entry: Dictionary = {"name": pname, "type": type_string(p.get("type", 0))}
		if target_node:
			var val = target_node.get(pname)
			if val != null and not (val is Object):
				entry["value"] = var_to_str(val).substr(0, 80)
		info["properties"].append(entry)
		prop_count += 1
		if prop_count >= limit:
			break

	# Signals / Señales
	var sigs: Array = []
	if target_node:
		sigs = target_node.get_signal_list()
	elif ClassDB.class_exists(target_class):
		sigs = ClassDB.class_get_signal_list(target_class, true)
	for s in sigs:
		var sname: String = s.get("name", "")
		if sname.begins_with("_") or sname.is_empty():
			continue
		info["signals"].append(sname)

	# Script methods (GDScript custom methods not in ClassDB)
	# Métodos de script (métodos custom de GDScript no en ClassDB)
	if target_node and target_node.get_script():
		var script: Script = target_node.get_script()
		info["script_path"] = script.resource_path
		var script_methods: Array = script.get_script_method_list()
		for sm in script_methods:
			var smname: String = sm.get("name", "")
			if smname.begins_with("_") or smname.is_empty():
				continue
			var already := false
			for existing in info["methods"]:
				if existing["name"] == smname:
					already = true
					break
			if already:
				continue
			var args_list: Array = []
			for arg in sm.get("args", []):
				args_list.append(arg.get("name", "?"))
			info["methods"].append({"name": smname, "args": args_list, "source": "script"})

	return info

# ponytail: one generic tool to call any method on any node — covers all plugins
func _tool_call_node_method(params: Dictionary) -> Dictionary:
	# Calls a method on any node in the scene tree.
	# Use inspect_plugin first to discover available methods.
	# Llama un método en cualquier nodo del scene tree.
	var node_path: String = String(params.get("node_path", "")).strip_edges()
	var method_name: String = String(params.get("method", "")).strip_edges()
	var args: Array = params.get("args", [])

	if node_path.is_empty() or method_name.is_empty():
		return {"ok": false, "error": "node_path and method are required"}

	# Blocked methods — prevent destructive operations
	# Métodos bloqueados — prevenir operaciones destructivas
	var blocked: PackedStringArray = [
		"free", "queue_free", "set_script", "remove_child",
		"queue_redraw", "notification", "propagate_notification",
	]
	if method_name in blocked:
		return {"ok": false, "error": "Method '%s' is blocked for safety" % method_name}

	var target_node: Node = _get_node_by_path(node_path)
	if target_node == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.root:
			target_node = tree.root.find_child(node_path, true, false)
	if target_node == null:
		return {"ok": false, "error": "Node '%s' not found" % node_path}

	if not target_node.has_method(method_name):
		return {"ok": false, "error": "Node '%s' (%s) has no method '%s'" % [node_path, target_node.get_class(), method_name]}

	var result = target_node.callv(method_name, args)
	var output: Dictionary = {
		"ok": true,
		"node": node_path,
		"class": target_node.get_class(),
		"method": method_name,
	}
	if result != null:
		if result is Object:
			output["return"] = str(result)
		else:
			output["return"] = result
	return output
