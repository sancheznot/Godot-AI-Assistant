extends RefCounted

# Builds project/editor context for the LLM / Construye contexto del proyecto para el LLM

const MAX_SCRIPT_CHARS := 4000
const MAX_TREE_DEPTH := 6
const MAX_TREE_NODES := 120

var _editor_plugin: EditorPlugin = null

func setup(editor_plugin: EditorPlugin) -> void:
	_editor_plugin = editor_plugin

func build_context(depth: String = "intermediate") -> String:
	var sections: PackedStringArray = []
	sections.append(_build_editor_state())
	sections.append(_build_selection_context())
	
	match depth:
		"basic":
			sections.append(_build_project_summary())
		"intermediate":
			sections.append(_build_project_summary())
			sections.append(_build_codebase_overview())
			sections.append(_build_scene_tree_summary())
			sections.append(_build_open_scripts_summary())
		"full":
			sections.append(_build_project_summary())
			sections.append(_build_codebase_overview())
			sections.append(_build_base_scenes_index())
			sections.append(_build_scene_tree_summary(MAX_TREE_DEPTH))
			sections.append(_build_open_scripts_summary(true))
			sections.append(_build_recent_files_summary())
	
	return "\n\n".join(sections)

func get_current_scene_summary() -> String:
	var ei := _editor_interface()
	if ei == null:
		return "EditorInterface not available."
	var root := ei.get_edited_scene_root()
	if root == null:
		return "No scene loaded."
	return "Scene: %s | Root: %s (%s)" % [root.scene_file_path, root.name, root.get_class()]

func get_selection_summary() -> String:
	return _build_selection_context()

func _build_editor_state() -> String:
	var ei := _editor_interface()
	if ei == null:
		return "## Editor\nEditorInterface not available."
	
	var lines: PackedStringArray = ["## Editor state"]
	var current_scene := ei.get_edited_scene_root()
	if current_scene:
		lines.append("- Current scene: %s (%s)" % [current_scene.scene_file_path, current_scene.name])
	else:
		lines.append("- Current scene: none")
	
	var open_scenes := ei.get_open_scenes()
	if open_scenes.size() > 0:
		lines.append("- Open scenes: %s" % ", ".join(open_scenes))
	
	return "\n".join(lines)

func _build_selection_context() -> String:
	var ei := _editor_interface()
	if ei == null:
		return ""
	
	var selection := ei.get_selection()
	var nodes := selection.get_selected_nodes()
	if nodes.is_empty():
		return "## Selection\nNo nodes selected."
	
	var root := ei.get_edited_scene_root()
	var lines: PackedStringArray = ["## Selection"]
	for node in nodes:
		lines.append("- %s (%s)" % [_rel_path(root, node), node.get_class()])
		var props := _serialize_node_properties(node, 8)
		for prop_line in props:
			lines.append("  - %s" % prop_line)
	
	return "\n".join(lines)

func _rel_path(root: Node, node: Node) -> String:
	if root == null or node == null:
		return node.name if node else ""
	if node == root:
		return "."
	if root.is_ancestor_of(node):
		return str(root.get_path_to(node))
	return node.name

func _build_project_summary() -> String:
	var lines: PackedStringArray = ["## Project summary"]
	var project_name := ProjectSettings.get_setting("application/config/name", "Untitled")
	lines.append("- Project: %s" % project_name)
	lines.append("- Main scene: %s" % ProjectSettings.get_setting("application/run/main_scene", ""))
	
	var top_dirs := ["scenes", "scripts", "addons", "assets", "resources"]
	var found_dirs: PackedStringArray = []
	for dir_name in top_dirs:
		var dir_path := "res://%s" % dir_name
		if DirAccess.open(dir_path) != null:
			found_dirs.append("%s (%d items)" % [dir_name, _count_dir_entries(dir_path)])
	if not found_dirs.is_empty():
		lines.append("- Top folders: %s" % ", ".join(found_dirs))
	
	return "\n".join(lines)

func _build_codebase_overview() -> String:
	var lines: PackedStringArray = ["## Codebase overview"]
	var autoload_names: PackedStringArray = _get_autoload_names()
	if autoload_names.size() > 0:
		lines.append("- Autoloads: %s" % ", ".join(autoload_names))
	
	var scene_roots: PackedStringArray = ["res://scenes", "res://levels", "res://world", "res://maps"]
	var scene_paths: PackedStringArray = []
	for root_path in scene_roots:
		scene_paths.append_array(_collect_files(root_path, 20))
	if scene_paths.is_empty():
		var all_files: PackedStringArray = _collect_files("res://", 40)
		for file_path in all_files:
			if file_path.ends_with(".tscn"):
				scene_paths.append(file_path)
	if not scene_paths.is_empty():
		lines.append("- Key scenes:")
		for scene_path in scene_paths.slice(0, 16):
			lines.append("  - %s" % scene_path)
	
	var all_scripts: PackedStringArray = _collect_files("res://", 9999)
	var script_count: int = 0
	for file_path in all_scripts:
		if file_path.ends_with(".gd"):
			script_count += 1
	lines.append("- GDScript files indexed: %d" % script_count)
	return "\n".join(lines)

func _build_base_scenes_index() -> String:
	var lines: PackedStringArray = ["## Base scenes index"]
	var all_files: PackedStringArray = _collect_files("res://", 80)
	for file_path in all_files:
		if file_path.ends_with(".tscn"):
			lines.append("- %s" % file_path)
	return "\n".join(lines)

func _get_autoload_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for info in ProjectSettings.get_property_list():
		var prop_name: String = String(info.name)
		if prop_name.begins_with("autoload/") and not prop_name.ends_with("/path"):
			names.append(prop_name.get_file())
	return names

func _build_scene_tree_summary(max_depth: int = 4) -> String:
	var ei := _editor_interface()
	if ei == null:
		return ""
	
	var root := ei.get_edited_scene_root()
	if root == null:
		return "## Scene tree\nNo scene loaded."
	
	var lines: PackedStringArray = ["## Scene tree"]
	var counter: Array = [0]
	_serialize_tree(root, 0, max_depth, lines, "  ", counter)
	if counter[0] >= MAX_TREE_NODES:
		lines.append("  … (árbol truncado en %d nodos / tree truncated at %d nodes)" % [MAX_TREE_NODES, MAX_TREE_NODES])
	return "\n".join(lines)

func _build_open_scripts_summary(include_content: bool = false) -> String:
	var ei := _editor_interface()
	if ei == null:
		return ""
	
	var lines: PackedStringArray = ["## Open scripts"]
	if ei.has_method("get_open_script_editors"):
		var open_scripts: Array = ei.get_open_script_editors()
		if open_scripts.is_empty():
			return "## Open scripts\nNone."
		for script_editor in open_scripts:
			if script_editor == null or not script_editor.has_method("get_edited_resource"):
				continue
			var script: Script = script_editor.get_edited_resource()
			if script == null:
				continue
			var path := script.resource_path
			lines.append("- %s" % path)
			if include_content and path.ends_with(".gd"):
				var text := _read_text_file(path)
				if not text.is_empty():
					lines.append("```gdscript\n%s\n```" % text.substr(0, MAX_SCRIPT_CHARS))
		return "\n".join(lines)
	
	if ei.has_method("get_current_script"):
		var current_script: Script = ei.get_current_script()
		if current_script:
			lines.append("- %s" % current_script.resource_path)
			return "\n".join(lines)
	
	return "## Open scripts\nNone."

func _build_recent_files_summary() -> String:
	var lines: PackedStringArray = ["## Project files (sample)"]
	var files := _collect_files("res://", 40)
	for file_path in files:
		lines.append("- %s" % file_path)
	return "\n".join(lines)

func _serialize_tree(node: Node, depth: int, max_depth: int, lines: PackedStringArray, indent: String, counter: Array) -> void:
	if depth > max_depth or counter[0] >= MAX_TREE_NODES:
		return
	counter[0] += 1
	# Only show pos/scale when they differ from defaults (keeps the tree compact).
	# Mostrar pos/scale solo cuando difieren de los valores por defecto (árbol compacto).
	var suffix := ""
	if node is Node3D:
		var n3d := node as Node3D
		if n3d.position != Vector3.ZERO:
			suffix += " pos=%s" % str(n3d.position)
		if n3d.scale != Vector3.ONE:
			suffix += " scale=%s" % str(n3d.scale)
	elif node is Node2D:
		var n2d := node as Node2D
		if n2d.position != Vector2.ZERO:
			suffix += " pos=%s" % str(n2d.position)
		if n2d.scale != Vector2.ONE:
			suffix += " scale=%s" % str(n2d.scale)
	lines.append("%s- %s (%s)%s" % [indent, node.name, node.get_class(), suffix])
	for child in node.get_children():
		_serialize_tree(child, depth + 1, max_depth, lines, indent + "  ", counter)

func _serialize_node_properties(node: Node, max_props: int) -> PackedStringArray:
	var result: PackedStringArray = []
	var property_list := node.get_property_list()
	var count := 0
	for prop in property_list:
		if count >= max_props:
			break
		if prop.usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if prop.name.begins_with("_"):
			continue
		var value = node.get(prop.name)
		if value is Object:
			continue
		result.append("%s = %s" % [prop.name, str(value)])
		count += 1
	return result

func _collect_files(path: String, limit: int) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := DirAccess.open(path)
	if dir == null:
		return result
	
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "" and result.size() < limit:
		if entry != "." and entry != "..":
			var full_path := path.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					result.append_array(_collect_files(full_path, limit - result.size()))
			elif entry.ends_with(".gd") or entry.ends_with(".tscn") or entry.ends_with(".cs"):
				result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return result

func _count_dir_entries(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count

func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func _editor_interface() -> EditorInterface:
	if _editor_plugin:
		return _editor_plugin.get_editor_interface()
	return null
