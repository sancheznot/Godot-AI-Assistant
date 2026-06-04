@tool
extends Control

# AI Assistant Plugin UI / UI del plugin asistente AI

const COLOR_USER_ACCENT := Color(0.42, 0.62, 1.0, 1.0)
const COLOR_ASSISTANT_ACCENT := Color(0.62, 0.56, 0.95, 1.0)
const COLOR_STATUS_ACCENT := Color(0.45, 0.78, 0.95, 1.0)
const COLOR_ERROR_ACCENT := Color(0.95, 0.42, 0.42, 1.0)
const COLOR_MUTED_TEXT := Color(0.62, 0.64, 0.7, 1.0)
const COLOR_BODY_TEXT := Color(0.9, 0.91, 0.94, 1.0)

@onready var prompt_text_edit: TextEdit = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/PromptTextEdit
@onready var conversation_title: Label = $RootVBox/MainSplit/ConversationPanel/ConversationVBox/ConversationHeader/ConversationTitle
@onready var conversation_scroll: ScrollContainer = $RootVBox/MainSplit/ConversationPanel/ConversationVBox/ConversationScroll
@onready var messages_container: VBoxContainer = $RootVBox/MainSplit/ConversationPanel/ConversationVBox/ConversationScroll/MessagesVBox
@onready var model_dropdown: OptionButton = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ModelDropdown
@onready var refresh_models_button: Button = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/RefreshModelsButton
@onready var send_button: Button = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/SendButton
@onready var config_button: Button = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ConfigButton
@onready var new_agent_button: Button = $RootVBox/MainSplit/ConversationPanel/ConversationVBox/ConversationHeader/HeaderActions/NewAgentButton
@onready var history_button: Button = $RootVBox/MainSplit/ConversationPanel/ConversationVBox/ConversationHeader/HeaderActions/HistoryButton
@onready var more_button: Button = $RootVBox/MainSplit/ConversationPanel/ConversationVBox/ConversationHeader/HeaderActions/MoreButton
@onready var history_popup: PopupPanel = $HistoryPopup
@onready var history_search: LineEdit = $HistoryPopup/HistoryMargin/HistoryVBox/HistorySearch
@onready var history_list_vbox: VBoxContainer = $HistoryPopup/HistoryMargin/HistoryVBox/HistoryScroll/HistoryListVBox
@onready var archived_toggle: Button = $HistoryPopup/HistoryMargin/HistoryVBox/ArchivedToggle
@onready var archived_section: VBoxContainer = $HistoryPopup/HistoryMargin/HistoryVBox/ArchivedSection
@onready var more_menu: PopupMenu = $MoreMenu
@onready var autocomplete_panel: PanelContainer = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/AutocompletePanel
@onready var suggestions_vbox: VBoxContainer = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/AutocompletePanel/AutocompleteScroll/SuggestionsVBox
@onready var skills_dropdown: OptionButton = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/SkillsDropdown
@onready var context_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ContextCheckBox
@onready var tools_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolsCheckBox
@onready var agent_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/AgentCheckBox
@onready var thinking_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ThinkingCheckBox
@onready var status_label: Label = $RootVBox/StatusBar/StatusHBox/StatusLabel
@onready var harness_label: Label = $RootVBox/StatusBar/StatusHBox/HarnessLabel
@onready var shortcut_hint: Label = $RootVBox/StatusBar/StatusHBox/ShortcutHint
@onready var conversation_panel: PanelContainer = $RootVBox/MainSplit/ConversationPanel
@onready var composer_panel: PanelContainer = $RootVBox/MainSplit/ComposerPanel
@onready var status_bar: PanelContainer = $RootVBox/StatusBar

var editor_plugin: EditorPlugin = null
var config_manager: RefCounted = null
var project_context: RefCounted = null
var editor_tools: RefCounted = null
var skills_manager: RefCounted = null
var ai_handler: RefCounted = null
var model_catalog: RefCounted = null
var config_dialog: Window = null
var chat_history: RefCounted = null
var mention_resolver: RefCounted = null
var composer_commands: RefCounted = null
var composer_autocomplete: RefCounted = null
var locale_manager: RefCounted = null

var _active_assistant_panel: PanelContainer = null
var _active_status_panel: PanelContainer = null
var _active_content_label: RichTextLabel = null
var _active_step_label: Label = null
var _active_summary_label: Label = null
var _active_progress_bar: ProgressBar = null
var _active_status_title: Label = null
var _autocomplete_trigger: Dictionary = {}
var _autocomplete_items: Array = []
var _autocomplete_buttons: Array = []
var _autocomplete_selected: int = 0
var _history_session_menu: PopupMenu = null
var _history_menu_session_id: String = ""
var _history_archived_open: bool = false

func setup(
	plugin: EditorPlugin,
	config_mgr: RefCounted,
	context_builder: RefCounted,
	tools: RefCounted,
	skills: RefCounted,
	locale_mgr: RefCounted = null
) -> void:
	editor_plugin = plugin
	config_manager = config_mgr
	project_context = context_builder
	editor_tools = tools
	skills_manager = skills
	locale_manager = locale_mgr

func _ready() -> void:
	if config_manager == null:
		config_manager = preload("res://addons/ai_assistant_plugin/scripts/plugin_config_manager.gd").new()
	if project_context == null:
		project_context = preload("res://addons/ai_assistant_plugin/scripts/project_context.gd").new()
	if editor_plugin and project_context.has_method("setup"):
		project_context.setup(editor_plugin)
	if editor_tools == null and editor_plugin:
		editor_tools = preload("res://addons/ai_assistant_plugin/scripts/editor_tools.gd").new()
		editor_tools.setup(editor_plugin)
	if skills_manager == null:
		skills_manager = preload("res://addons/ai_assistant_plugin/scripts/skills_manager.gd").new()
		skills_manager.load_skills(
			String(config_manager.get_setting("skills_path", "res://addons/ai_assistant_plugin/skills")),
			String(config_manager.get_setting("active_skill", "godot_scene_editing"))
		)
	
	ai_handler = preload("res://addons/ai_assistant_plugin/scripts/ai_model_handler.gd").new()
	ai_handler.setup(self, config_manager, project_context, editor_tools, skills_manager)
	ai_handler.query_started.connect(_on_query_started)
	ai_handler.query_completed.connect(_on_query_completed)
	ai_handler.query_failed.connect(_on_query_failed)
	ai_handler.agent_step_update.connect(_on_agent_step_update)
	
	model_catalog = preload("res://addons/ai_assistant_plugin/scripts/model_catalog.gd").new()
	model_catalog.setup(self, config_manager)
	model_catalog.catalog_updated.connect(_on_model_catalog_updated)
	model_catalog.refresh_started.connect(_on_model_refresh_started)
	model_catalog.refresh_finished.connect(_on_model_refresh_finished)
	
	composer_commands = preload("res://addons/ai_assistant_plugin/scripts/composer_commands.gd").new()
	composer_autocomplete = preload("res://addons/ai_assistant_plugin/scripts/composer_autocomplete.gd").new()
	if locale_manager == null:
		locale_manager = preload("res://addons/ai_assistant_plugin/scripts/locale_manager.gd").new()
		locale_manager.setup(config_manager)
	
	config_dialog = preload("res://addons/ai_assistant_plugin/scripts/config_dialog.gd").new()
	config_dialog.setup(config_manager, model_catalog, locale_manager)
	config_dialog.configuration_saved.connect(_on_configuration_saved)
	add_child(config_dialog)
	
	chat_history = preload("res://addons/ai_assistant_plugin/scripts/chat_history.gd").new()
	chat_history.load_history()
	mention_resolver = preload("res://addons/ai_assistant_plugin/scripts/mention_resolver.gd").new()
	mention_resolver.setup(project_context, skills_manager)
	
	_apply_composer_styles()
	initialize_ui()
	_apply_locale()
	_restore_chat_from_history()
	_refresh_history_ui()
	_setup_history_ui()

func _apply_composer_styles() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.13, 1.0)
	panel_style.border_color = Color(0.24, 0.24, 0.27, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	conversation_panel.add_theme_stylebox_override("panel", panel_style)
	
	var composer_style := panel_style.duplicate()
	composer_style.bg_color = Color(0.1, 0.1, 0.11, 1.0)
	composer_panel.add_theme_stylebox_override("panel", composer_style)
	
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.08, 0.08, 0.09, 1.0)
	status_style.set_corner_radius_all(6)
	status_style.content_margin_left = 8
	status_style.content_margin_right = 8
	status_style.content_margin_top = 4
	status_style.content_margin_bottom = 4
	status_bar.add_theme_stylebox_override("panel", status_style)
	
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.68, 1.0))
	harness_label.add_theme_font_size_override("font_size", 11)
	harness_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62, 1.0))
	
	prompt_text_edit.add_theme_constant_override("line_spacing", 4)
	messages_container.add_theme_constant_override("separation", 10)
	
	_style_toolbar_button(config_button, false)
	_style_toolbar_button(send_button, true)
	_style_toolbar_button(refresh_models_button, false)
	_style_header_icon_button(new_agent_button)
	_style_header_icon_button(history_button)
	_style_header_icon_button(more_button)
	_style_toolbar_option(model_dropdown)
	_style_toolbar_option(skills_dropdown)
	autocomplete_panel.visible = false
	_update_history_popup_styles()

func _tr(key: String, args: Array = []) -> String:
	if locale_manager:
		return locale_manager.get_text(key, args)
	return key

func _apply_locale() -> void:
	if locale_manager == null:
		return
	new_agent_button.tooltip_text = _tr("ui.new_agent_tooltip")
	history_button.tooltip_text = _tr("ui.history_tooltip")
	more_button.tooltip_text = _tr("ui.more_tooltip")
	history_search.placeholder_text = _tr("ui.history_search_placeholder")
	archived_toggle.text = _tr("ui.history_archived_closed")
	context_checkbox.text = _tr("ui.context")
	tools_checkbox.text = _tr("ui.tools")
	agent_checkbox.text = _tr("ui.agent")
	thinking_checkbox.text = _tr("ui.think")
	config_button.text = _tr("ui.config")
	refresh_models_button.tooltip_text = _tr("ui.refresh_models_tooltip")
	send_button.tooltip_text = _tr("ui.send_tooltip")
	shortcut_hint.text = _tr("ui.shortcut_hint")
	prompt_text_edit.placeholder_text = _tr("ui.composer_placeholder")

func _make_bubble_style(bg: Color, accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = accent
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _make_status_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.14, 0.19, 1.0)
	style.border_color = Color(0.24, 0.34, 0.46, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _style_role_label(label: Label, accent: Color, role_text: String) -> void:
	label.text = role_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", accent)

func _style_body_rich_text(label: RichTextLabel) -> void:
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_color_override("default_color", COLOR_BODY_TEXT)

func _append_user_message(text: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		_make_bubble_style(Color(0.14, 0.2, 0.34, 0.55), COLOR_USER_ACCENT)
	)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	
	var role_label := Label.new()
	_style_role_label(role_label, COLOR_USER_ACCENT, _tr("ui.role_you"))
	vbox.add_child(role_label)
	
	var body := RichTextLabel.new()
	_style_body_rich_text(body)
	body.text = _escape_bbcode(text)
	vbox.add_child(body)
	
	messages_container.add_child(panel)
	_scroll_to_bottom()

func _begin_assistant_message() -> void:
	_reset_active_assistant_refs()
	
	_active_assistant_panel = PanelContainer.new()
	_active_assistant_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_assistant_panel.add_theme_stylebox_override(
		"panel",
		_make_bubble_style(Color(0.14, 0.14, 0.16, 1.0), COLOR_ASSISTANT_ACCENT)
	)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_active_assistant_panel.add_child(vbox)
	
	var role_label := Label.new()
	_style_role_label(role_label, COLOR_ASSISTANT_ACCENT, _tr("ui.role_assistant"))
	vbox.add_child(role_label)
	
	_active_status_panel = PanelContainer.new()
	_active_status_panel.add_theme_stylebox_override("panel", _make_status_style())
	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 6)
	_active_status_panel.add_child(status_vbox)
	
	_active_status_title = Label.new()
	_active_status_title.text = _tr("ui.thinking")
	_active_status_title.add_theme_font_size_override("font_size", 12)
	_active_status_title.add_theme_color_override("font_color", COLOR_STATUS_ACCENT)
	status_vbox.add_child(_active_status_title)
	
	_active_step_label = Label.new()
	_active_step_label.add_theme_font_size_override("font_size", 11)
	_active_step_label.add_theme_color_override("font_color", COLOR_MUTED_TEXT)
	status_vbox.add_child(_active_step_label)
	
	_active_progress_bar = ProgressBar.new()
	_active_progress_bar.custom_minimum_size = Vector2(0, 6)
	_active_progress_bar.show_percentage = false
	_active_progress_bar.visible = false
	status_vbox.add_child(_active_progress_bar)
	
	_active_summary_label = Label.new()
	_active_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_active_summary_label.add_theme_font_size_override("font_size", 12)
	_active_summary_label.add_theme_color_override("font_color", COLOR_BODY_TEXT)
	status_vbox.add_child(_active_summary_label)
	
	vbox.add_child(_active_status_panel)
	
	_active_content_label = RichTextLabel.new()
	_style_body_rich_text(_active_content_label)
	_active_content_label.visible = false
	vbox.add_child(_active_content_label)
	
	messages_container.add_child(_active_assistant_panel)
	_scroll_to_bottom()

func _show_assistant_status(title: String, summary: String, step: int = 0, max_steps: int = 0) -> void:
	if _active_status_panel == null:
		return
	_active_status_panel.visible = true
	if _active_status_title:
		_active_status_title.text = title
	if _active_summary_label:
		_active_summary_label.text = summary
	if _active_step_label:
		if step > 0 and max_steps > 0:
			_active_step_label.text = _tr("ui.step_of", [step, max_steps])
			_active_step_label.visible = true
		else:
			_active_step_label.text = ""
			_active_step_label.visible = false
	if _active_progress_bar:
		if step > 0 and max_steps > 0:
			_active_progress_bar.visible = true
			_active_progress_bar.max_value = max_steps
			_active_progress_bar.value = step
		else:
			_active_progress_bar.visible = false
	_scroll_to_bottom()

func _finish_assistant_message(text: String, is_error: bool = false) -> void:
	if _active_status_panel:
		_active_status_panel.visible = false
	if _active_content_label:
		_active_content_label.visible = true
		_active_content_label.text = _format_assistant_bbcode(text, is_error)
	if is_error and _active_assistant_panel:
		_active_assistant_panel.add_theme_stylebox_override(
			"panel",
			_make_bubble_style(Color(0.24, 0.12, 0.12, 1.0), COLOR_ERROR_ACCENT)
		)
	_reset_active_assistant_refs()
	_scroll_to_bottom()

func _reset_active_assistant_refs() -> void:
	_active_assistant_panel = null
	_active_status_panel = null
	_active_content_label = null
	_active_step_label = null
	_active_summary_label = null
	_active_progress_bar = null
	_active_status_title = null

func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")

func _format_assistant_bbcode(text: String, is_error: bool = false) -> String:
	if is_error:
		return "[color=#ff8a8a]%s[/color]" % _escape_bbcode(text)
	
	var lines: PackedStringArray = text.split("\n")
	var output: PackedStringArray = []
	var in_thinking: bool = false
	
	for line in lines:
		if line == "[Thinking]":
			in_thinking = true
			output.append("[bgcolor=#151922][color=#8b93a8][i]%s[/i]" % _escape_bbcode(_tr("ui.thinking_block")))
			continue
		if line == "[/Thinking]":
			in_thinking = false
			output.append("[/color][/bgcolor]")
			output.append("")
			continue
		if line.begins_with("### Step "):
			var step_title: String = line.substr(4).strip_edges()
			output.append("[font_size=13][color=#aeb6c8][b]%s[/b][/color][/font_size]" % _escape_bbcode(step_title))
			continue
		if line.begins_with("### Tool results"):
			output.append("[font_size=12][color=#7ec8ff][b]%s[/b][/color][/font_size]" % _escape_bbcode(line.substr(4).strip_edges()))
			continue
		if line.begins_with("### "):
			output.append("[font_size=13][color=#aeb6c8][b]%s[/b][/color][/font_size]" % _escape_bbcode(line.substr(4)))
			continue
		if line.begins_with("---"):
			output.append("[color=#3a3f4a]────────────────[/color]")
			continue
		if in_thinking:
			output.append("[color=#8b93a8]%s[/color]" % _escape_bbcode(line))
		else:
			output.append(_escape_bbcode(line))
	
	return "\n".join(output)

func _append_assistant_message_static(text: String, is_error: bool = false) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent: Color = COLOR_ERROR_ACCENT if is_error else COLOR_ASSISTANT_ACCENT
	var bg: Color = Color(0.24, 0.12, 0.12, 1.0) if is_error else Color(0.14, 0.14, 0.16, 1.0)
	panel.add_theme_stylebox_override("panel", _make_bubble_style(bg, accent))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var role_label := Label.new()
	_style_role_label(role_label, accent, _tr("ui.role_assistant"))
	vbox.add_child(role_label)
	var body := RichTextLabel.new()
	_style_body_rich_text(body)
	body.text = _format_assistant_bbcode(text, is_error)
	vbox.add_child(body)
	messages_container.add_child(panel)

func _restore_chat_from_history() -> void:
	if chat_history == null:
		return
	_clear_conversation()
	for message in chat_history.get_active_messages():
		if message is Dictionary:
			var role: String = String(message.get("role", ""))
			var content: String = String(message.get("content", ""))
			if role == "user":
				_append_user_message(content)
			elif role == "assistant":
				_append_assistant_message_static(content, bool(message.get("is_error", false)))
	_scroll_to_bottom()

func _refresh_history_ui() -> void:
	if chat_history == null:
		return
	var title: String = chat_history.get_active_session_title()
	conversation_title.text = title
	conversation_title.tooltip_text = title
	if history_popup.visible:
		_render_history_panel()
	prompt_text_edit.placeholder_text = _tr("ui.composer_placeholder")
	_update_autocomplete_styles()

func _setup_history_ui() -> void:
	_history_session_menu = PopupMenu.new()
	_history_session_menu.add_item(_tr("ui.history_menu_clear"), 0)
	_history_session_menu.add_item(_tr("ui.history_menu_delete"), 1)
	add_child(_history_session_menu)
	_history_session_menu.id_pressed.connect(_on_history_session_menu_id)
	
	more_menu.clear()
	more_menu.add_item(_tr("ui.clear"), 0)
	more_menu.add_item(_tr("ui.config"), 1)
	more_menu.id_pressed.connect(_on_more_menu_id)
	
	var shortcut := Shortcut.new()
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_N
	key_event.ctrl_pressed = true
	shortcut.events.append(key_event)
	new_agent_button.shortcut = shortcut
	
	history_search.text_changed.connect(_on_history_search_changed)
	archived_toggle.pressed.connect(_on_archived_toggle_pressed)
	history_popup.popup_hide.connect(_on_history_popup_hide)

func _update_history_popup_styles() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.11, 0.12, 1.0)
	panel_style.border_color = Color(0.28, 0.28, 0.32, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_bottom = 0
	history_popup.add_theme_stylebox_override("panel", panel_style)
	
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = Color(0.08, 0.08, 0.09, 1.0)
	search_style.border_color = Color(0.22, 0.22, 0.26, 1.0)
	search_style.set_border_width_all(1)
	search_style.set_corner_radius_all(8)
	search_style.content_margin_left = 10
	search_style.content_margin_right = 10
	search_style.content_margin_top = 6
	search_style.content_margin_bottom = 6
	history_search.add_theme_stylebox_override("normal", search_style)
	history_search.add_theme_font_size_override("font_size", 12)

func _style_header_icon_button(button: Button) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := normal.duplicate()
	hover.bg_color = Color(0.2, 0.2, 0.24, 1.0)
	button.add_theme_color_override("font_color", Color(0.78, 0.8, 0.86, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.95, 0.96, 0.98, 1.0))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)

func _toggle_history_popup() -> void:
	if history_popup.visible:
		history_popup.hide()
		return
	_render_history_panel()
	var anchor_pos: Vector2 = history_button.global_position
	var popup_width: int = 320
	var popup_height: int = 380
	history_popup.size = Vector2i(popup_width, popup_height)
	history_popup.position = Vector2i(
		int(anchor_pos.x + history_button.size.x - popup_width),
		int(anchor_pos.y + history_button.size.y + 4)
	)
	history_popup.popup()

func _render_history_panel() -> void:
	for child in history_list_vbox.get_children():
		child.queue_free()
	for child in archived_section.get_children():
		child.queue_free()
	if chat_history == null:
		return
	var filter_text: String = history_search.text
	var summaries: Array = chat_history.get_session_summaries(filter_text, false)
	var now_ts: int = Time.get_unix_time_from_system()
	var today_items: Array = []
	var older_items: Array = []
	for summary in summaries:
		if summary is Dictionary:
			if _is_same_day(int(summary.get("updated_at", 0)), now_ts):
				today_items.append(summary)
			else:
				older_items.append(summary)
	if today_items.is_empty() and older_items.is_empty():
		_add_history_empty_label(history_list_vbox, _tr("ui.history_empty"))
	else:
		if not today_items.is_empty():
			_add_history_section_header(history_list_vbox, _tr("ui.history_today"))
			for summary in today_items:
				history_list_vbox.add_child(_make_history_row(summary))
		if not older_items.is_empty():
			_add_history_section_header(history_list_vbox, _tr("ui.history_older"))
			for summary in older_items:
				history_list_vbox.add_child(_make_history_row(summary))
	var archived_items: Array = chat_history.get_archived_summaries(filter_text)
	archived_section.visible = _history_archived_open
	archived_toggle.text = _tr("ui.history_archived_open") if _history_archived_open else _tr("ui.history_archived_closed")
	if _history_archived_open:
		if archived_items.is_empty():
			_add_history_empty_label(archived_section, _tr("ui.history_archived_empty"))
		else:
			for summary in archived_items:
				archived_section.add_child(_make_history_row(summary))

func _add_history_section_header(parent: VBoxContainer, text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.5, 0.56, 0.66, 1.0))
	parent.add_child(header)

func _add_history_empty_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64, 1.0))
	parent.add_child(label)

func _make_history_row(summary: Dictionary) -> PanelContainer:
	var session_id: String = String(summary.get("id", ""))
	var is_active: bool = chat_history.active_session_id == session_id
	var is_pinned: bool = bool(summary.get("pinned", false))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row_style := StyleBoxFlat.new()
	row_style.set_corner_radius_all(8)
	row_style.content_margin_left = 8
	row_style.content_margin_right = 6
	row_style.content_margin_top = 6
	row_style.content_margin_bottom = 6
	if is_active:
		row_style.bg_color = Color(0.18, 0.24, 0.36, 1.0)
		row_style.border_color = Color(0.32, 0.42, 0.58, 1.0)
		row_style.set_border_width_all(1)
	else:
		row_style.bg_color = Color(0.13, 0.13, 0.15, 1.0)
	panel.add_theme_stylebox_override("panel", row_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var active_icon := Label.new()
	active_icon.custom_minimum_size = Vector2(16, 0)
	active_icon.text = "✓" if is_active else ""
	active_icon.add_theme_font_size_override("font_size", 12)
	active_icon.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0, 1.0))
	row.add_child(active_icon)
	var title_button := Button.new()
	title_button.flat = true
	title_button.focus_mode = Control.FOCUS_NONE
	title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_button.text = _truncate_history_title(String(summary.get("title", "Chat")))
	title_button.add_theme_font_size_override("font_size", 12)
	title_button.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96, 1.0))
	title_button.pressed.connect(_activate_session.bind(session_id))
	row.add_child(title_button)
	var menu_button := _make_history_action_button("⋯", _tr("ui.history_row_menu"))
	menu_button.pressed.connect(_open_history_session_menu.bind(session_id, menu_button))
	row.add_child(menu_button)
	var pin_button := _make_history_action_button("📌" if is_pinned else "⌁", _tr("ui.history_row_pin"))
	pin_button.pressed.connect(_toggle_session_pin.bind(session_id, not is_pinned))
	row.add_child(pin_button)
	var archive_button := _make_history_action_button("⊡", _tr("ui.history_row_archive"))
	archive_button.pressed.connect(_toggle_session_archive.bind(session_id, not bool(summary.get("archived", false))))
	row.add_child(archive_button)
	return panel

func _make_history_action_button(label_text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(24, 24)
	button.text = label_text
	button.tooltip_text = tooltip
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74, 1.0))
	return button

func _truncate_history_title(title: String) -> String:
	if title.length() <= 34:
		return title
	return title.substr(0, 31) + "..."

func _is_same_day(timestamp: int, reference_timestamp: int) -> bool:
	var a: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp)
	var b: Dictionary = Time.get_datetime_dict_from_unix_time(reference_timestamp)
	return int(a.get("year", 0)) == int(b.get("year", 0)) \
		and int(a.get("month", 0)) == int(b.get("month", 0)) \
		and int(a.get("day", 0)) == int(b.get("day", 0))

func _activate_session(session_id: String) -> void:
	if chat_history.set_active_session(session_id):
		_restore_chat_from_history()
		_refresh_history_ui()
		status_label.text = _tr("ui.status_chat_loaded")
		history_popup.hide()

func _toggle_session_pin(session_id: String, pinned: bool) -> void:
	if chat_history.pin_session(session_id, pinned):
		_render_history_panel()

func _toggle_session_archive(session_id: String, archived: bool) -> void:
	if chat_history.archive_session(session_id, archived):
		if chat_history.active_session_id != session_id:
			_restore_chat_from_history()
		_refresh_history_ui()

func _open_history_session_menu(session_id: String, anchor: Control) -> void:
	_history_menu_session_id = session_id
	var menu_pos: Vector2 = anchor.global_position
	_history_session_menu.position = Vector2i(int(menu_pos.x), int(menu_pos.y + anchor.size.y))
	_history_session_menu.popup()

func _on_history_session_menu_id(menu_id: int) -> void:
	if _history_menu_session_id.is_empty():
		return
	match menu_id:
		0:
			if chat_history.clear_session_messages(_history_menu_session_id):
				if chat_history.active_session_id == _history_menu_session_id:
					_clear_conversation()
					status_label.text = _tr("ui.status_chat_cleared")
		1:
			if chat_history.delete_session(_history_menu_session_id):
				_restore_chat_from_history()
				status_label.text = _tr("ui.status_chat_deleted")
	_refresh_history_ui()

func _on_history_search_changed(_new_text: String) -> void:
	if history_popup.visible:
		_render_history_panel()

func _on_archived_toggle_pressed() -> void:
	_history_archived_open = not _history_archived_open
	_render_history_panel()

func _on_history_popup_hide() -> void:
	_history_archived_open = false
	archived_section.visible = false
	archived_toggle.text = _tr("ui.history_archived_closed")

func _on_new_agent_pressed() -> void:
	var replace: bool = Input.is_key_pressed(KEY_ALT)
	if replace:
		chat_history.replace_active_session(_tr("ui.new_chat_session"))
	else:
		chat_history.create_session(_tr("ui.new_chat_session"))
	_clear_conversation()
	prompt_text_edit.clear()
	_hide_autocomplete()
	_refresh_history_ui()
	status_label.text = _tr("ui.status_agent_replaced") if replace else _tr("ui.status_new_chat")
	history_popup.hide()

func _on_more_menu_id(menu_id: int) -> void:
	match menu_id:
		0:
			_on_clear_current_chat()
		1:
			config_dialog.open_dialog()

func _on_clear_current_chat() -> void:
	chat_history.clear_active_session()
	_clear_conversation()
	_refresh_history_ui()
	status_label.text = _tr("ui.status_chat_cleared")

func _update_autocomplete_styles() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.11, 0.12, 1.0)
	panel_style.border_color = Color(0.32, 0.42, 0.58, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	autocomplete_panel.add_theme_stylebox_override("panel", panel_style)

func _category_label(category: String) -> String:
	var key: String = "ac.cat.%s" % category
	var text: String = _tr(key)
	return text if text != key else category.capitalize()

func _hide_autocomplete() -> void:
	autocomplete_panel.visible = false
	_autocomplete_items.clear()
	_autocomplete_buttons.clear()
	_autocomplete_trigger = {}
	_autocomplete_selected = 0

func _update_autocomplete() -> void:
	if composer_autocomplete == null:
		return
	var caret_line: int = prompt_text_edit.get_caret_line()
	var caret_col: int = prompt_text_edit.get_caret_column()
	_autocomplete_trigger = composer_autocomplete.detect_trigger(prompt_text_edit.text, caret_line, caret_col)
	if not bool(_autocomplete_trigger.get("active", false)):
		_hide_autocomplete()
		return
	var query: String = String(_autocomplete_trigger.get("query", ""))
	var mode: String = String(_autocomplete_trigger.get("mode", ""))
	if mode == "mention" and mention_resolver:
		_autocomplete_items = mention_resolver.search(query, locale_manager, 24)
	elif mode == "command":
		_autocomplete_items = composer_autocomplete.get_slash_suggestions(query, locale_manager, skills_manager)
	else:
		_autocomplete_items = []
	_render_autocomplete_items()

func _render_autocomplete_items() -> void:
	for child in suggestions_vbox.get_children():
		child.queue_free()
	_autocomplete_buttons.clear()
	if _autocomplete_items.is_empty():
		autocomplete_panel.visible = false
		return
	var last_category: String = ""
	for item_index in _autocomplete_items.size():
		var item: Dictionary = _autocomplete_items[item_index]
		if item is Dictionary:
			var category: String = String(item.get("category", ""))
			if category != last_category:
				var header := Label.new()
				header.text = _category_label(category)
				header.add_theme_font_size_override("font_size", 11)
				header.add_theme_color_override("font_color", Color(0.5, 0.56, 0.66, 1.0))
				suggestions_vbox.add_child(header)
				last_category = category
			var row := Button.new()
			row.flat = true
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.focus_mode = Control.FOCUS_NONE
			row.text = "%s   %s" % [String(item.get("title", item.get("insert", ""))), String(item.get("description", ""))]
			row.add_theme_font_size_override("font_size", 12)
			row.pressed.connect(_apply_autocomplete_selection.bind(item_index))
			suggestions_vbox.add_child(row)
			_autocomplete_buttons.append(row)
	var hint := Label.new()
	hint.text = _tr("ac.hint")
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55, 1.0))
	suggestions_vbox.add_child(hint)
	_autocomplete_selected = 0
	_highlight_autocomplete_selection()
	autocomplete_panel.visible = true

func _highlight_autocomplete_selection() -> void:
	for index in _autocomplete_buttons.size():
		var button: Button = _autocomplete_buttons[index]
		var normal := StyleBoxFlat.new()
		normal.set_corner_radius_all(4)
		normal.content_margin_left = 8
		normal.content_margin_right = 8
		normal.content_margin_top = 3
		normal.content_margin_bottom = 3
		if index == _autocomplete_selected:
			normal.bg_color = Color(0.2, 0.28, 0.42, 1.0)
			button.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98, 1.0))
		else:
			normal.bg_color = Color(0, 0, 0, 0)
			button.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88, 1.0))
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", normal)
		button.add_theme_stylebox_override("pressed", normal)

func _apply_autocomplete_selection(item_index: int = -1) -> void:
	var selected: int = item_index if item_index >= 0 else _autocomplete_selected
	if selected < 0 or selected >= _autocomplete_items.size():
		return
	var item: Dictionary = _autocomplete_items[selected]
	var insert_text: String = String(item.get("insert", ""))
	var result: Dictionary = composer_autocomplete.insert_selection(
		prompt_text_edit.text,
		_autocomplete_trigger,
		insert_text
	)
	prompt_text_edit.text = String(result.get("text", prompt_text_edit.text))
	prompt_text_edit.set_caret_line(int(result.get("caret_line", 0)))
	prompt_text_edit.set_caret_column(int(result.get("caret_col", 0)))
	_hide_autocomplete()
	prompt_text_edit.grab_focus()

func _on_prompt_text_changed() -> void:
	_update_autocomplete()

func _handle_slash_command(prompt: String) -> bool:
	var parsed: Dictionary = composer_commands.try_parse(prompt)
	if not bool(parsed.get("handled", false)):
		return false
	var command: String = String(parsed.get("command", ""))
	var args: PackedStringArray = parsed.get("args", PackedStringArray())
	match command:
		"help":
			_show_system_message(_tr("cmd.help"))
		"clear":
			chat_history.clear_active_session()
			clear_inputs()
			status_label.text = _tr("ui.status_chat_cleared")
		"new":
			chat_history.create_session(_tr("ui.new_chat_session"))
			clear_inputs()
			_refresh_history_ui()
			status_label.text = _tr("ui.status_new_chat")
		"history":
			var lines: PackedStringArray = [_tr("ui.saved_chats")]
			for summary in chat_history.get_session_summaries():
				if summary is Dictionary:
					lines.append(_tr("ui.chat_entry", [summary.get("title", ""), summary.get("message_count", 0)]))
			_show_system_message("\n".join(lines))
		"skill":
			if args.is_empty():
				_show_system_message(skills_manager.get_skills_catalog_prompt())
			else:
				var skill_id: String = String(args[0])
				skills_manager.set_active_skill(skill_id)
				if skills_manager.active_skill_id == skill_id:
					config_manager.set_setting("active_skill", skill_id)
					setup_skills_dropdown()
					_update_harness_label()
					_show_system_message(_tr("ui.skill_active", [skill_id]))
				else:
					_show_system_message(_tr("ui.skill_not_found", [skill_id]))
		"skills":
			var skills_path: String = String(config_manager.get_setting("skills_path", "res://addons/ai_assistant_plugin/skills"))
			_show_system_message(_tr("ui.skills_path", [skills_path]))
		"context":
			if args.is_empty():
				_show_system_message(_tr("ui.context_depth_usage"))
			else:
				var depth: String = String(args[0]).to_lower()
				if depth in ["basic", "intermediate", "full"]:
					config_manager.set_setting("context_depth", depth)
					_show_system_message(_tr("ui.context_depth_set", [depth]))
				else:
					_show_system_message(_tr("ui.context_depth_invalid"))
		"models":
			model_catalog.refresh_all()
			_show_system_message(_tr("ui.status_refreshing_models"))
		_:
			_show_system_message(_tr("ui.unknown_command"))
	return true

func _show_system_message(text: String) -> void:
	_append_assistant_message_static(text, false)
	chat_history.add_message("assistant", text)

func _scroll_to_bottom() -> void:
	call_deferred("_do_scroll_to_bottom")

func _do_scroll_to_bottom() -> void:
	var scroll_bar: VScrollBar = conversation_scroll.get_v_scroll_bar()
	if scroll_bar:
		scroll_bar.value = scroll_bar.max_value

func _clear_conversation() -> void:
	for child in messages_container.get_children():
		child.queue_free()
	_reset_active_assistant_refs()

func _style_toolbar_button(button: Button, primary: bool) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	
	if primary:
		normal.bg_color = Color(0.28, 0.45, 0.95, 1.0)
		button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		button.tooltip_text = _tr("ui.send_tooltip")
	else:
		normal.bg_color = Color(0.18, 0.18, 0.2, 1.0)
		button.add_theme_color_override("font_color", Color(0.82, 0.82, 0.86, 1.0))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	
	var hover := normal.duplicate()
	if primary:
		hover.bg_color = Color(0.34, 0.52, 1.0, 1.0)
	else:
		hover.bg_color = Color(0.22, 0.22, 0.25, 1.0)
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)

func _style_toolbar_option(option: OptionButton) -> void:
	option.focus_mode = Control.FOCUS_NONE
	option.add_theme_font_size_override("font_size", 12)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.16, 0.18, 1.0)
	normal.border_color = Color(0.28, 0.28, 0.32, 1.0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	option.add_theme_stylebox_override("normal", normal)
	option.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))

func initialize_ui() -> void:
	setup_skills_dropdown()
	context_checkbox.button_pressed = bool(config_manager.get_setting("include_project_context", true))
	tools_checkbox.button_pressed = bool(config_manager.get_setting("enable_editor_tools", true))
	agent_checkbox.button_pressed = bool(config_manager.get_setting("enable_agent_loop", true))
	thinking_checkbox.button_pressed = bool(config_manager.get_setting("enable_thinking", true))
	_update_harness_label()
	status_label.text = _tr("ui.status_loading_models")
	
	send_button.pressed.connect(_on_send_button_pressed)
	config_button.pressed.connect(_on_config_button_pressed)
	new_agent_button.pressed.connect(_on_new_agent_pressed)
	history_button.pressed.connect(_toggle_history_popup)
	more_button.pressed.connect(_on_more_button_pressed)
	refresh_models_button.pressed.connect(_on_refresh_models_pressed)
	skills_dropdown.item_selected.connect(_on_skill_selected)
	context_checkbox.toggled.connect(_on_context_toggled)
	tools_checkbox.toggled.connect(_on_tools_toggled)
	agent_checkbox.toggled.connect(_on_agent_toggled)
	thinking_checkbox.toggled.connect(_on_thinking_toggled)
	prompt_text_edit.gui_input.connect(_on_prompt_gui_input)
	prompt_text_edit.text_changed.connect(_on_prompt_text_changed)
	prompt_text_edit.caret_changed.connect(_update_autocomplete)
	
	model_catalog.refresh_all()

func _on_prompt_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if autocomplete_panel.visible and not _autocomplete_items.is_empty():
			if key_event.keycode in [KEY_UP, KEY_DOWN]:
				if key_event.keycode == KEY_UP:
					_autocomplete_selected = maxi(_autocomplete_selected - 1, 0)
				else:
					_autocomplete_selected = mini(_autocomplete_selected + 1, _autocomplete_buttons.size() - 1)
				_highlight_autocomplete_selection()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_TAB]:
				_apply_autocomplete_selection()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_ESCAPE:
				_hide_autocomplete()
				get_viewport().set_input_as_handled()
				return
		if key_event.keycode != KEY_ENTER and key_event.keycode != KEY_KP_ENTER:
			return
		if key_event.shift_pressed:
			return
		_on_send_button_pressed()
		get_viewport().set_input_as_handled()

func _get_query_options() -> Dictionary:
	return {
		"include_context": context_checkbox.button_pressed,
		"enable_tools": tools_checkbox.button_pressed,
		"enable_thinking": thinking_checkbox.button_pressed,
		"enable_agent_loop": agent_checkbox.button_pressed,
		"max_agent_steps": config_manager.get_setting("agent_max_steps", 8),
		"context_depth": config_manager.get_setting("context_depth", "intermediate")
	}

func _update_harness_label() -> void:
	if ai_handler == null:
		harness_label.text = "Harness: base"
		return
	var options: Dictionary = _get_query_options()
	harness_label.text = ai_handler.get_harness_layers_label(options, agent_checkbox.button_pressed)

func setup_model_dropdown() -> void:
	model_dropdown.clear()
	var catalog_entries: Array = model_catalog.get_entries()
	if catalog_entries.is_empty():
		model_dropdown.add_item("No models found")
		model_dropdown.set_item_metadata(0, {})
		send_button.disabled = true
		return
	
	send_button.disabled = false
	var default_provider: String = config_manager.get_default_provider()
	var default_model: String = String(config_manager.get_provider_config(default_provider).get("model", ""))
	var selected_index: int = 0
	
	for entry in catalog_entries:
		if entry is Dictionary:
			model_dropdown.add_item(String(entry.get("label", entry.get("model_id", "model"))))
			var index: int = model_dropdown.item_count - 1
			model_dropdown.set_item_metadata(index, entry)
			if String(entry.get("provider_id", "")) == default_provider and String(entry.get("model_id", "")) == default_model:
				selected_index = index
	
	model_dropdown.select(selected_index)

func _get_selected_model_entry() -> Dictionary:
	if model_dropdown.item_count == 0:
		return {}
	var metadata: Variant = model_dropdown.get_item_metadata(model_dropdown.selected)
	return metadata if metadata is Dictionary else {}

func _on_refresh_models_pressed() -> void:
	model_catalog.refresh_all()

func _on_model_refresh_started() -> void:
	refresh_models_button.disabled = true
	status_label.text = _tr("ui.status_loading_models")

func _on_model_refresh_finished() -> void:
	refresh_models_button.disabled = false
	if status_label.text == _tr("ui.status_loading_models"):
		status_label.text = _tr("ui.ready")

func _on_model_catalog_updated(_entries: Array) -> void:
	setup_model_dropdown()
	if model_catalog.get_entries().size() > 0 and status_label.text == _tr("ui.status_loading_models"):
		status_label.text = _tr("ui.ready")
	_update_harness_label()

func setup_skills_dropdown() -> void:
	skills_dropdown.clear()
	for skill_id in skills_manager.get_skill_ids():
		skills_dropdown.add_item(skills_manager.get_skill_label(skill_id))
		skills_dropdown.set_item_metadata(skills_dropdown.item_count - 1, skill_id)
		if skill_id == skills_manager.active_skill_id:
			skills_dropdown.select(skills_dropdown.item_count - 1)

func _on_send_button_pressed() -> void:
	var prompt: String = prompt_text_edit.text.strip_edges()
	if prompt.is_empty():
		status_label.text = _tr("ui.status_write_prompt")
		return
	
	if _handle_slash_command(prompt):
		prompt_text_edit.clear()
		return
	
	var model_entry: Dictionary = _get_selected_model_entry()
	var provider_id: String = String(model_entry.get("provider_id", ""))
	var model_id: String = String(model_entry.get("model_id", ""))
	if provider_id.is_empty() or model_id.is_empty():
		status_label.text = _tr("ui.status_enable_provider")
		return
	
	chat_history.add_message("user", prompt)
	_append_user_message(prompt)
	_begin_assistant_message()
	_show_assistant_status(_tr("ui.thinking"), _tr("ui.generating"))
	prompt_text_edit.clear()
	_hide_autocomplete()
	send_button.disabled = true
	var options: Dictionary = _get_query_options()
	options["model_id"] = model_id
	if mention_resolver:
		options["attached_context"] = mention_resolver.build_attached_context(prompt)
	_update_harness_label()
	_refresh_history_ui()
	ai_handler.query_provider(provider_id, prompt, options)

func _on_more_button_pressed() -> void:
	var menu_pos: Vector2 = more_button.global_position
	more_menu.position = Vector2i(int(menu_pos.x - 80), int(menu_pos.y + more_button.size.y))
	more_menu.popup()

func _on_config_button_pressed() -> void:
	config_dialog.open_dialog()

func _on_configuration_saved() -> void:
	ai_handler.reload_from_config()
	model_catalog.refresh_all()
	skills_manager.load_skills(
		String(config_manager.get_setting("skills_path", "res://addons/ai_assistant_plugin/skills")),
		String(config_manager.get_setting("active_skill", "godot_scene_editing"))
	)
	if mention_resolver:
		mention_resolver.setup(project_context, skills_manager)
		mention_resolver.rebuild_index()
	setup_skills_dropdown()
	context_checkbox.button_pressed = bool(config_manager.get_setting("include_project_context", true))
	tools_checkbox.button_pressed = bool(config_manager.get_setting("enable_editor_tools", true))
	agent_checkbox.button_pressed = bool(config_manager.get_setting("enable_agent_loop", true))
	thinking_checkbox.button_pressed = bool(config_manager.get_setting("enable_thinking", true))
	_update_harness_label()
	if locale_manager:
		locale_manager.reload_locale()
	_apply_locale()
	_update_history_popup_styles()
	status_label.text = _tr("ui.status_config_saved")

func _on_skill_selected(index: int) -> void:
	var skill_id: String = String(skills_dropdown.get_item_metadata(index))
	skills_manager.set_active_skill(skill_id)
	config_manager.set_setting("active_skill", skill_id)
	_update_harness_label()

func _on_context_toggled(enabled: bool) -> void:
	config_manager.set_setting("include_project_context", enabled)
	_update_harness_label()

func _on_tools_toggled(enabled: bool) -> void:
	config_manager.set_setting("enable_editor_tools", enabled)
	if not enabled:
		agent_checkbox.button_pressed = false
	_update_harness_label()

func _on_agent_toggled(enabled: bool) -> void:
	config_manager.set_setting("enable_agent_loop", enabled)
	if enabled:
		tools_checkbox.button_pressed = true
	_update_harness_label()

func _on_thinking_toggled(enabled: bool) -> void:
	config_manager.set_setting("enable_thinking", enabled)
	_update_harness_label()

func _on_query_started(provider_id: String) -> void:
	var model_entry: Dictionary = _get_selected_model_entry()
	var model_id: String = String(model_entry.get("model_id", ""))
	if model_id.is_empty():
		status_label.text = _tr("ui.status_querying", [config_manager.get_provider_label(provider_id)])
	else:
		status_label.text = _tr("ui.status_querying_model", [config_manager.get_provider_label(provider_id), model_id])
	_show_assistant_status(_tr("ui.querying_model"), _tr("ui.waiting_provider"))

func _on_agent_step_update(step: int, max_steps: int, summary: String) -> void:
	status_label.text = _tr("ui.status_agent_step", [step, max_steps, summary])
	_show_assistant_status(_tr("ui.agent_working"), summary, step, max_steps)

func _on_query_completed(_success: bool, text: String) -> void:
	_finish_assistant_message(text)
	chat_history.add_message("assistant", text)
	_refresh_history_ui()
	send_button.disabled = false
	status_label.text = _tr("ui.status_done")

func _on_query_failed(error_message: String) -> void:
	_finish_assistant_message(error_message, true)
	chat_history.add_message("assistant", error_message, true)
	_refresh_history_ui()
	send_button.disabled = false
	status_label.text = _tr("ui.status_error")

func update_ui_with_response(response: String) -> void:
	_finish_assistant_message(response)

func clear_inputs() -> void:
	prompt_text_edit.clear()
	_clear_conversation()
