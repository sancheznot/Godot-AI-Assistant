@tool
extends EditorPlugin

# AI Assistant Plugin for Godot Editor / Plugin asistente AI para el editor

var plugin_control: Control
var config_manager: RefCounted
var project_context: RefCounted
var editor_tools: RefCounted
var skills_manager: RefCounted
var locale_manager: RefCounted

func _enter_tree() -> void:
	config_manager = preload("res://addons/ai_assistant_plugin/scripts/plugin_config_manager.gd").new()
	locale_manager = preload("res://addons/ai_assistant_plugin/scripts/locale_manager.gd").new()
	locale_manager.setup(config_manager)
	project_context = preload("res://addons/ai_assistant_plugin/scripts/project_context.gd").new()
	project_context.setup(self)
	editor_tools = preload("res://addons/ai_assistant_plugin/scripts/editor_tools.gd").new()
	editor_tools.setup(self)
	skills_manager = preload("res://addons/ai_assistant_plugin/scripts/skills_manager.gd").new()
	skills_manager.load_skills(
		String(config_manager.get_setting("skills_path", "res://addons/ai_assistant_plugin/skills")),
		String(config_manager.get_setting("active_skill", "godot_scene_editing"))
	)
	
	var ui_scene := load("res://addons/ai_assistant_plugin/scenes/plugin_ui.tscn")
	if ui_scene == null:
		push_error("AI Assistant Plugin: Failed to load UI scene")
		return
	
	plugin_control = ui_scene.instantiate()
	if plugin_control.has_method("setup"):
		plugin_control.setup(self, config_manager, project_context, editor_tools, skills_manager, locale_manager)
	plugin_control.custom_minimum_size = Vector2.ZERO
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, plugin_control)
	print("AI Assistant Plugin added to editor")

func _exit_tree() -> void:
	if plugin_control:
		remove_control_from_docks(plugin_control)
		plugin_control.queue_free()
		plugin_control = null
	print("AI Assistant Plugin removed from editor")

func _has_main_screen() -> bool:
	return false
