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
@onready var model_dropdown: OptionButton = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarPrimary/ModelDropdown
@onready var refresh_models_button: Button = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarPrimary/RefreshModelsButton
@onready var send_button: Button = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarPrimary/SendButton
@onready var config_button: Button = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarPrimary/ConfigButton
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
@onready var skills_dropdown: OptionButton = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarPrimary/SkillsDropdown
@onready var context_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarToggles/ContextCheckBox
@onready var tools_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarToggles/ToolsCheckBox
@onready var agent_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarToggles/AgentCheckBox
@onready var thinking_checkbox: CheckBox = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/BottomToolbar/ToolbarToggles/ThinkingCheckBox
@onready var status_label: Label = $RootVBox/StatusBar/StatusHBox/StatusLabel
@onready var harness_label: Label = $RootVBox/StatusBar/StatusHBox/HarnessLabel
@onready var shortcut_hint: Label = $RootVBox/StatusBar/StatusHBox/ShortcutHint
@onready var conversation_panel: PanelContainer = $RootVBox/MainSplit/ConversationPanel
@onready var composer_panel: PanelContainer = $RootVBox/MainSplit/ComposerPanel
@onready var status_bar: PanelContainer = $RootVBox/StatusBar
@onready var autocomplete_scroll: ScrollContainer = $RootVBox/MainSplit/ComposerPanel/ComposerVBox/AutocompletePanel/AutocompleteScroll

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
var _active_content_body: VBoxContainer = null
var _active_step_label: Label = null
var _active_summary_label: Label = null
var _active_progress_bar: ProgressBar = null
var _active_status_title: Label = null
var _active_thinking_dots: HBoxContainer = null
var _thinking_dot_labels: Array = []
var _active_status_stylebox: StyleBoxFlat = null
var _status_activity_timer: Timer = null
var _status_animating: bool = false
var _status_pulse_step: int = 0
var _status_title_base: String = ""
var _status_summary_base: String = ""
var _status_wait_start_ms: int = 0
var _status_indeterminate_bar: bool = true
var _autocomplete_trigger: Dictionary = {}
var _autocomplete_items: Array = []
var _autocomplete_buttons: Array = []
var _autocomplete_selected: int = 0
var _history_session_menu: PopupMenu = null
var _history_menu_session_id: String = ""
var _history_archived_open: bool = false
var _request_busy: bool = false
var _scroll_pending: bool = false
var _scroll_retry_count: int = 0
var _scroll_retry_timer: Timer = null
var _follow_chat_scroll: bool = true
var _scroll_programmatic: bool = false
var _current_agent_log_text: String = ""
var _active_copy_source: String = ""

const AUTOCOMPLETE_MAX_HEIGHT := 120

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
	ai_handler.query_cancelled.connect(_on_query_cancelled)
	ai_handler.queue_updated.connect(_on_queue_updated)
	ai_handler.request_dequeued.connect(_on_request_dequeued)
	ai_handler.agent_step_update.connect(_on_agent_step_update)
	ai_handler.agent_log_updated.connect(_on_agent_log_updated)
	ai_handler.response_retry_attempt.connect(_on_response_retry_attempt)
	
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
	config_dialog.setup(config_manager, model_catalog, locale_manager, skills_manager)
	config_dialog.configuration_saved.connect(_on_configuration_saved)
	config_dialog.skill_installed.connect(_on_skill_installed_from_catalog)
	add_child(config_dialog)
	
	chat_history = preload("res://addons/ai_assistant_plugin/scripts/chat_history.gd").new()
	chat_history.load_history()
	mention_resolver = preload("res://addons/ai_assistant_plugin/scripts/mention_resolver.gd").new()
	mention_resolver.setup(project_context, skills_manager)
	
	_apply_composer_styles()
	_configure_dock_layout()
	_setup_conversation_scroll()
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

func _configure_dock_layout() -> void:
	# Keep the dock UI inside its panel bounds / Mantener la UI dentro del dock
	clip_contents = true
	custom_minimum_size = Vector2.ZERO
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE)
	harness_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shortcut_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	resized.connect(_on_dock_resized)
	call_deferred("_on_dock_resized")

func _setup_conversation_scroll() -> void:
	# Content height = messages only; avoid empty filler below last bubble / Solo altura real del contenido
	messages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	conversation_scroll.follow_focus = false
	if not messages_container.resized.is_connected(_on_messages_container_resized):
		messages_container.resized.connect(_on_messages_container_resized)
	var scroll_bar: VScrollBar = conversation_scroll.get_v_scroll_bar()
	if scroll_bar and not scroll_bar.value_changed.is_connected(_on_conversation_scroll_changed):
		scroll_bar.value_changed.connect(_on_conversation_scroll_changed)
	if _scroll_retry_timer == null:
		_scroll_retry_timer = Timer.new()
		_scroll_retry_timer.wait_time = 0.05
		_scroll_retry_timer.timeout.connect(_on_scroll_retry_tick)
		add_child(_scroll_retry_timer)

func _on_dock_resized() -> void:
	var compact: bool = size.x < 360
	shortcut_hint.visible = not compact
	harness_label.visible = size.x >= 280
	prompt_text_edit.custom_minimum_size.y = 56 if compact else 64
	_update_autocomplete_height()

func _update_autocomplete_height() -> void:
	if not autocomplete_panel.visible:
		autocomplete_scroll.custom_minimum_size = Vector2.ZERO
		return
	var max_h: float = mini(float(AUTOCOMPLETE_MAX_HEIGHT), maxf(size.y * 0.28, 72.0))
	autocomplete_scroll.custom_minimum_size = Vector2(0, max_h)

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

func _style_status_progress_bar(bar: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.14, 1.0)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_STATUS_ACCENT
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)

func _make_thinking_dots_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_thinking_dot_labels.clear()
	for _i in 3:
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 9)
		dot.add_theme_color_override("font_color", COLOR_STATUS_ACCENT)
		row.add_child(dot)
		_thinking_dot_labels.append(dot)
	return row

func _style_role_label(label: Label, accent: Color, role_text: String) -> void:
	label.text = role_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", accent)

func _make_copy_button(get_text: Callable) -> Button:
	var button := Button.new()
	button.text = _tr("ui.copy")
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = _tr("ui.copy_tooltip")
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", COLOR_MUTED_TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.9, 0.92, 0.96, 1.0))
	button.pressed.connect(func() -> void:
		var text: String = String(get_text.call())
		if not text.is_empty():
			DisplayServer.clipboard_set(text)
			button.text = _tr("ui.copied")
			var t := get_tree().create_timer(1.2)
			t.timeout.connect(func() -> void:
				if is_instance_valid(button):
					button.text = _tr("ui.copy")
			)
	)
	return button

func _style_body_rich_text(label: RichTextLabel) -> void:
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.context_menu_enabled = true
	label.focus_mode = Control.FOCUS_CLICK
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
	_follow_chat_scroll = true
	_scroll_to_bottom(true)

func _begin_assistant_message() -> void:
	_reset_active_assistant_refs()
	_current_agent_log_text = ""
	_active_copy_source = ""
	
	_active_assistant_panel = PanelContainer.new()
	_active_assistant_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_assistant_panel.add_theme_stylebox_override(
		"panel",
		_make_bubble_style(Color(0.14, 0.14, 0.16, 1.0), COLOR_ASSISTANT_ACCENT)
	)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_active_assistant_panel.add_child(vbox)
	
	var role_row := HBoxContainer.new()
	role_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(role_row)
	var role_label := Label.new()
	_style_role_label(role_label, COLOR_ASSISTANT_ACCENT, _tr("ui.role_assistant"))
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_row.add_child(role_label)
	role_row.add_child(_make_copy_button(func() -> String: return _active_copy_source))
	
	_active_status_panel = PanelContainer.new()
	_active_status_stylebox = _make_status_style()
	_active_status_panel.add_theme_stylebox_override("panel", _active_status_stylebox)
	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 6)
	_active_status_panel.add_child(status_vbox)
	
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	status_vbox.add_child(title_row)
	
	_active_status_title = Label.new()
	_active_status_title.text = _tr("ui.thinking")
	_active_status_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_status_title.add_theme_font_size_override("font_size", 12)
	_active_status_title.add_theme_color_override("font_color", COLOR_STATUS_ACCENT)
	title_row.add_child(_active_status_title)
	
	_active_thinking_dots = _make_thinking_dots_row()
	title_row.add_child(_active_thinking_dots)
	
	_active_step_label = Label.new()
	_active_step_label.add_theme_font_size_override("font_size", 11)
	_active_step_label.add_theme_color_override("font_color", COLOR_MUTED_TEXT)
	status_vbox.add_child(_active_step_label)
	
	_active_progress_bar = ProgressBar.new()
	_active_progress_bar.custom_minimum_size = Vector2(0, 6)
	_active_progress_bar.show_percentage = false
	_active_progress_bar.max_value = 100.0
	_active_progress_bar.value = 0.0
	_style_status_progress_bar(_active_progress_bar)
	status_vbox.add_child(_active_progress_bar)
	
	_active_summary_label = Label.new()
	_active_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_active_summary_label.add_theme_font_size_override("font_size", 12)
	_active_summary_label.add_theme_color_override("font_color", COLOR_BODY_TEXT)
	status_vbox.add_child(_active_summary_label)
	
	vbox.add_child(_active_status_panel)
	
	_active_content_body = VBoxContainer.new()
	_active_content_body.visible = false
	_active_content_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_content_body.add_theme_constant_override("separation", 8)
	vbox.add_child(_active_content_body)
	
	messages_container.add_child(_active_assistant_panel)
	_follow_chat_scroll = true
	_scroll_to_bottom(true)

func _show_assistant_status(title: String, summary: String, step: int = 0, max_steps: int = 0) -> void:
	if _active_status_panel == null:
		return
	_active_status_panel.visible = true
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
		_active_progress_bar.visible = true
		if step > 0 and max_steps > 0:
			_active_progress_bar.max_value = float(max_steps)
			_active_progress_bar.value = float(step)
			_start_status_animation(title, summary, false)
		else:
			_active_progress_bar.max_value = 100.0
			_active_progress_bar.value = 12.0
			_start_status_animation(title, summary, true)

func _start_status_animation(title: String, summary: String, indeterminate: bool) -> void:
	_status_title_base = title.trim_suffix("…").trim_suffix("...").strip_edges()
	_status_summary_base = summary.trim_suffix("…").trim_suffix("...").strip_edges()
	_status_indeterminate_bar = indeterminate
	_status_wait_start_ms = Time.get_ticks_msec()
	_status_animating = true
	_status_pulse_step = 0
	if _status_activity_timer == null:
		_status_activity_timer = Timer.new()
		_status_activity_timer.wait_time = 0.4
		_status_activity_timer.timeout.connect(_on_status_activity_tick)
		add_child(_status_activity_timer)
	_status_activity_timer.start()
	_on_status_activity_tick()

func _stop_status_animation() -> void:
	_status_animating = false
	if _status_activity_timer:
		_status_activity_timer.stop()

func _on_status_activity_tick() -> void:
	if not _status_animating:
		return
	_status_pulse_step += 1
	var dot_phase: int = _status_pulse_step % 3
	var title_dots: String = ".".repeat(_status_pulse_step % 4)
	if _active_status_title:
		_active_status_title.text = "%s%s" % [_status_title_base, title_dots]
	for index in _thinking_dot_labels.size():
		var dot: Label = _thinking_dot_labels[index]
		if dot:
			dot.modulate.a = 1.0 if index == dot_phase else 0.28
	if _active_status_stylebox:
		var pulse: float = 0.5 + 0.5 * sin(float(_status_pulse_step) * PI * 0.5)
		_active_status_stylebox.border_color = Color(
			0.22,
			0.34 + 0.18 * pulse,
			0.46 + 0.22 * pulse,
			1.0
		)
	if _active_progress_bar and _status_indeterminate_bar:
		var bar_positions: Array = [12.0, 38.0, 72.0, 55.0, 28.0]
		_active_progress_bar.value = float(bar_positions[_status_pulse_step % bar_positions.size()])
	if _active_summary_label and not _status_summary_base.is_empty():
		var elapsed_sec: int = maxi(0, (Time.get_ticks_msec() - _status_wait_start_ms) / 1000)
		_active_summary_label.text = _tr("ui.waiting_elapsed", [_status_summary_base, elapsed_sec])

func _finish_assistant_message(text: String, is_error: bool = false) -> void:
	_stop_status_animation()
	_active_copy_source = text
	if _active_status_panel:
		_active_status_panel.visible = false
	if _active_content_body:
		_active_content_body.visible = true
		_populate_assistant_content(_active_content_body, text, is_error)
	if is_error and _active_assistant_panel:
		_active_assistant_panel.add_theme_stylebox_override(
			"panel",
			_make_bubble_style(Color(0.24, 0.12, 0.12, 1.0), COLOR_ERROR_ACCENT)
		)
	_reset_active_assistant_refs()
	_scroll_to_bottom(false)

func _reset_active_assistant_refs() -> void:
	_stop_status_animation()
	_active_assistant_panel = null
	_active_status_panel = null
	_active_content_body = null
	_active_step_label = null
	_active_summary_label = null
	_active_progress_bar = null
	_active_status_title = null
	_active_thinking_dots = null
	_thinking_dot_labels.clear()
	_active_status_stylebox = null

func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")

func _normalize_thinking_tags(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?i)(?s)<thinking>(.*?)</thinking>")
	var result: String = text
	while true:
		var match_result := regex.search(result)
		if match_result == null:
			break
		var inner: String = match_result.get_string(1).strip_edges()
		var block: String = "[Thinking]\n%s\n[/Thinking]" % inner
		result = result.substr(0, match_result.get_start()) + block + result.substr(match_result.get_end())
	return result

func _apply_inline_markdown(line: String) -> String:
	var formatted: String = _escape_bbcode(line)
	var bold_regex := RegEx.new()
	bold_regex.compile("\\*\\*(.+?)\\*\\*")
	formatted = bold_regex.sub(formatted, "[b]$1[/b]", true)
	var code_regex := RegEx.new()
	code_regex.compile("`([^`]+)`")
	formatted = code_regex.sub(formatted, "[color=#9cdcfe]$1[/color]", true)
	var italic_regex := RegEx.new()
	italic_regex.compile("\\*([^*\\n]+?)\\*")
	formatted = italic_regex.sub(formatted, "[i]$1[/i]", true)
	return formatted

func _split_assistant_segments(text: String) -> Array:
	var normalized: String = _normalize_thinking_tags(text)
	var segments: Array = []
	var thinking_regex := RegEx.new()
	thinking_regex.compile("(?s)\\[Thinking\\](.*?)\\[/Thinking\\]")
	var last_end: int = 0
	for match_result in thinking_regex.search_all(normalized):
		var before: String = normalized.substr(last_end, match_result.get_start() - last_end)
		segments.append_array(_split_tool_and_body_sections(before))
		var thinking_text: String = match_result.get_string(1).strip_edges()
		if not thinking_text.is_empty():
			segments.append({"type": "thinking", "content": thinking_text})
		last_end = match_result.get_end()
	var tail: String = normalized.substr(last_end)
	segments.append_array(_split_tool_and_body_sections(tail))
	if segments.is_empty():
		segments.append_array(_split_tool_and_body_sections(normalized.strip_edges()))
	return segments

func _split_tool_and_body_sections(text: String) -> Array:
	var segments: Array = []
	var trimmed_text: String = text.strip_edges()
	if trimmed_text.is_empty():
		return segments
	var lines: PackedStringArray = trimmed_text.split("\n")
	var body_lines: PackedStringArray = []
	var i: int = 0
	while i < lines.size():
		var line: String = lines[i]
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("### Tool results") or trimmed.begins_with("### Tool parse warning"):
			_flush_body_segment(segments, body_lines)
			body_lines.clear()
			var title: String = trimmed
			i += 1
			var tool_lines: PackedStringArray = []
			while i < lines.size() and not lines[i].strip_edges().begins_with("### "):
				tool_lines.append(lines[i])
				i += 1
			segments.append({
				"type": "tool_results",
				"title": title,
				"content": "\n".join(tool_lines).strip_edges()
			})
			continue
		body_lines.append(line)
		i += 1
	_flush_body_segment(segments, body_lines)
	return segments

func _flush_body_segment(segments: Array, body_lines: PackedStringArray) -> void:
	var content: String = "\n".join(body_lines).strip_edges()
	if content.is_empty():
		return
	for sub in _split_body_code_blocks(content):
		segments.append(sub)

func _split_body_code_blocks(text: String) -> Array:
	var segments: Array = []
	var fence_regex := RegEx.new()
	fence_regex.compile("(?s)```(?:json|gdscript|tool_call)?\\s*(.*?)```")
	var last_end: int = 0
	for match_result in fence_regex.search_all(text):
		var before: String = text.substr(last_end, match_result.get_start() - last_end).strip_edges()
		if not before.is_empty():
			segments.append({"type": "body", "content": before})
		var inner: String = match_result.get_string(1).strip_edges()
		if inner.is_empty():
			last_end = match_result.get_end()
			continue
		if inner.contains("\"tool\""):
			segments.append({"type": "tool_calls", "content": inner})
		else:
			segments.append({"type": "code", "content": inner})
		last_end = match_result.get_end()
	var tail: String = text.substr(last_end).strip_edges()
	if not tail.is_empty():
		for sub in _split_inline_tool_json(tail):
			if sub is Dictionary:
				segments.append(sub)
	if segments.is_empty():
		segments.append({"type": "body", "content": text.strip_edges()})
	return segments

func _split_inline_tool_json(text: String) -> Array:
	# Inline `{"tool":"..."}` blocks (common in model numbered lists).
	# Bloques inline `{"tool":"..."}` (comunes en listas numeradas del modelo).
	var segments: Array = []
	var inline_regex := RegEx.new()
	inline_regex.compile("`(\\{[^`]*\"tool\"[^`]*\\})`")
	var last_end: int = 0
	for match_result in inline_regex.search_all(text):
		var before: String = text.substr(last_end, match_result.get_start() - last_end).strip_edges()
		if not before.is_empty():
			segments.append({"type": "body", "content": before})
		segments.append({"type": "tool_calls", "content": match_result.get_string(1).strip_edges()})
		last_end = match_result.get_end()
	var tail: String = text.substr(last_end).strip_edges()
	if not tail.is_empty():
		segments.append({"type": "body", "content": tail})
	if segments.is_empty():
		segments.append({"type": "body", "content": text.strip_edges()})
	return segments

func _populate_assistant_content(container: VBoxContainer, text: String, is_error: bool = false) -> void:
	for child in container.get_children():
		child.queue_free()
	if is_error:
		container.add_child(_make_body_rich_label("[color=#ff8a8a]%s[/color]" % _escape_bbcode(text)))
		return
	for segment in _split_assistant_segments(text):
		if not segment is Dictionary:
			continue
		var segment_type: String = String(segment.get("type", "body"))
		var content: String = String(segment.get("content", ""))
		if content.is_empty():
			continue
		if segment_type == "thinking":
			container.add_child(_make_collapsible_thinking_block(content))
		elif segment_type == "tool_results":
			var title: String = String(segment.get("title", _tr("ui.tool_results_block")))
			container.add_child(_make_collapsible_detail_block(
				title,
				content,
				_tr("ui.tool_results_show"),
				_tr("ui.tool_results_hide"),
				_format_tool_detail_bbcode,
				Color(0.1, 0.14, 0.12, 1.0),
				Color(0.22, 0.38, 0.3, 1.0)
			))
		elif segment_type == "tool_calls":
			container.add_child(_make_collapsible_detail_block(
				_tr("ui.tool_calls_block"),
				content,
				_tr("ui.tool_calls_show"),
				_tr("ui.tool_calls_hide"),
				_format_tool_detail_bbcode,
				Color(0.1, 0.12, 0.16, 1.0),
				Color(0.28, 0.34, 0.46, 1.0)
			))
		elif segment_type == "code":
			container.add_child(_make_collapsible_detail_block(
				_tr("ui.code_block_label"),
				content,
				_tr("ui.code_block_show"),
				_tr("ui.code_block_hide"),
				_format_tool_detail_bbcode,
				Color(0.12, 0.11, 0.15, 1.0),
				Color(0.34, 0.3, 0.42, 1.0)
			))
		else:
			container.add_child(_make_body_rich_label(_format_body_bbcode(content)))

func _make_body_rich_label(bbcode: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	_style_body_rich_text(label)
	label.text = bbcode
	return label

func _make_collapsible_thinking_block(thinking_text: String) -> PanelContainer:
	return _make_collapsible_detail_block(
		_tr("ui.thinking_block"),
		thinking_text,
		_tr("ui.thinking_show"),
		_tr("ui.thinking_hide"),
		_format_thinking_bbcode,
		Color(0.11, 0.13, 0.18, 1.0),
		Color(0.28, 0.32, 0.42, 1.0)
	)

func _make_collapsible_detail_block(
	block_label: String,
	detail_text: String,
	show_key: String,
	hide_key: String,
	format_fn: Callable,
	bg_color: Color,
	border_color: Color
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = bg_color
	panel_style.border_color = border_color
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var line_count: int = maxi(1, detail_text.split("\n", false).size())
	var toggle := Button.new()
	toggle.text = _tr(show_key, [line_count])
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 12)
	toggle.add_theme_color_override("font_color", Color(0.72, 0.76, 0.86, 1.0))
	toggle.add_theme_color_override("font_hover_color", Color(0.9, 0.92, 0.96, 1.0))
	vbox.add_child(toggle)
	var body := RichTextLabel.new()
	_style_body_rich_text(body)
	body.visible = false
	body.text = format_fn.call(detail_text)
	vbox.add_child(body)
	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		toggle.text = _tr(hide_key) if body.visible else _tr(show_key, [line_count])
		if body.visible and _follow_chat_scroll:
			call_deferred("_scroll_to_bottom", false)
	)
	return panel

func _format_tool_detail_bbcode(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var output: PackedStringArray = []
	for line in lines:
		output.append("[color=#9aa3b2]%s[/color]" % _escape_bbcode(line))
	return "\n".join(output)

func _format_thinking_bbcode(thinking_text: String) -> String:
	var lines: PackedStringArray = thinking_text.split("\n")
	var output: PackedStringArray = []
	for line in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty():
			output.append("")
			continue
		if trimmed.begins_with("- ") or trimmed.begins_with("* "):
			output.append("[color=#8b93a8]  • %s[/color]" % _apply_inline_markdown(trimmed.substr(2)))
		else:
			output.append("[color=#8b93a8]%s[/color]" % _apply_inline_markdown(line))
	return "\n".join(output)

func _format_body_bbcode(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var output: PackedStringArray = []
	var list_number_regex := RegEx.new()
	list_number_regex.compile("^(\\d+)\\.\\s+(.*)$")
	for line in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("### Step "):
			var step_title: String = trimmed.substr(3).strip_edges()
			output.append("")
			output.append("[font_size=14][color=#9cdcfe][b]%s[/b][/color][/font_size]" % _escape_bbcode(step_title))
			output.append("[color=#3a3f4a]────────────────[/color]")
			continue
		if trimmed.begins_with("### Tool results") or trimmed.begins_with("### Tool parse warning"):
			continue
		if trimmed.begins_with("### "):
			output.append("[font_size=13][color=#aeb6c8][b]%s[/b][/color][/font_size]" % _escape_bbcode(trimmed.substr(4)))
			continue
		if trimmed.begins_with("---"):
			output.append("[color=#3a3f4a]────────────────[/color]")
			continue
		if trimmed.is_empty():
			output.append("")
			continue
		var list_match := list_number_regex.search(trimmed)
		if list_match:
			output.append(
				"[color=#7a8294]%s.[/color] %s" % [
					list_match.get_string(1),
					_apply_inline_markdown(list_match.get_string(2))
				]
			)
			continue
		if trimmed.begins_with("- ") or trimmed.begins_with("* "):
			output.append("  [color=#7a8294]•[/color] %s" % _apply_inline_markdown(trimmed.substr(2)))
			continue
		output.append(_apply_inline_markdown(line))
	return "\n".join(output)

func _format_assistant_bbcode(text: String, is_error: bool = false) -> String:
	if is_error:
		return "[color=#ff8a8a]%s[/color]" % _escape_bbcode(text)
	var parts: PackedStringArray = []
	for segment in _split_assistant_segments(text):
		if not segment is Dictionary:
			continue
		var segment_type: String = String(segment.get("type", "body"))
		var content: String = String(segment.get("content", ""))
		if content.is_empty():
			continue
		if segment_type == "thinking":
			parts.append("[bgcolor=#151922][color=#8b93a8][b]%s[/b][/color]\n%s[/bgcolor]" % [
				_escape_bbcode(_tr("ui.thinking_block")),
				_format_thinking_bbcode(content)
			])
		else:
			parts.append(_format_body_bbcode(content))
	return "\n\n".join(parts)

func _append_assistant_message_static(text: String, is_error: bool = false) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent: Color = COLOR_ERROR_ACCENT if is_error else COLOR_ASSISTANT_ACCENT
	var bg: Color = Color(0.24, 0.12, 0.12, 1.0) if is_error else Color(0.14, 0.14, 0.16, 1.0)
	panel.add_theme_stylebox_override("panel", _make_bubble_style(bg, accent))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var role_row := HBoxContainer.new()
	role_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(role_row)
	var role_label := Label.new()
	_style_role_label(role_label, accent, _tr("ui.role_assistant"))
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_row.add_child(role_label)
	var copy_text: String = text
	role_row.add_child(_make_copy_button(func() -> String: return copy_text))
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	vbox.add_child(body)
	_populate_assistant_content(body, text, is_error)
	messages_container.add_child(panel)
	_scroll_to_bottom(false)

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
	_scroll_to_bottom(false)

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
	autocomplete_scroll.custom_minimum_size = Vector2.ZERO
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
	_update_autocomplete_height()

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

func _scroll_to_bottom(force: bool = false) -> void:
	if not force and not _follow_chat_scroll:
		return
	_scroll_pending = true
	_scroll_retry_count = 0
	call_deferred("_apply_scroll_position")
	if _scroll_retry_timer:
		_scroll_retry_timer.start()

func _on_conversation_scroll_changed(_value: float) -> void:
	if _scroll_programmatic:
		return
	_follow_chat_scroll = _is_scrolled_to_bottom()

func _on_messages_container_resized() -> void:
	if _scroll_pending and _follow_chat_scroll:
		_apply_scroll_position()

func _on_scroll_retry_tick() -> void:
	if not _scroll_pending:
		if _scroll_retry_timer:
			_scroll_retry_timer.stop()
		return
	_apply_scroll_position()
	_scroll_retry_count += 1
	if _is_scrolled_to_bottom() or _scroll_retry_count >= 16:
		_scroll_pending = false
		if _scroll_retry_timer:
			_scroll_retry_timer.stop()

func _is_scrolled_to_bottom(threshold: float = 4.0) -> bool:
	var scroll_bar: VScrollBar = conversation_scroll.get_v_scroll_bar()
	if scroll_bar == null:
		return true
	return scroll_bar.max_value <= threshold or scroll_bar.value >= scroll_bar.max_value - threshold

func _apply_scroll_position() -> void:
	var children := messages_container.get_children()
	if children.is_empty():
		return
	_scroll_programmatic = true
	var last_child: Control = children[children.size() - 1] as Control
	if last_child:
		conversation_scroll.ensure_control_visible(last_child)
	var scroll_bar: VScrollBar = conversation_scroll.get_v_scroll_bar()
	if scroll_bar:
		scroll_bar.value = scroll_bar.max_value
		conversation_scroll.scroll_vertical = int(scroll_bar.max_value)
	_scroll_programmatic = false
	_follow_chat_scroll = _is_scrolled_to_bottom()

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
	_style_option_popup(option.get_popup())

func _style_option_popup(popup: PopupMenu) -> void:
	popup.add_theme_font_size_override("font_separator_size", 11)
	popup.add_theme_color_override("font_separator_color", Color(0.58, 0.64, 0.78, 1.0))
	popup.add_theme_constant_override("separator_height", 26)
	popup.add_theme_color_override("font_color", Color(0.88, 0.9, 0.94, 1.0))
	popup.add_theme_color_override("font_hover_color", Color(0.96, 0.97, 0.99, 1.0))
	popup.add_theme_color_override("font_accelerator_color", Color(0.58, 0.64, 0.78, 1.0))

func _get_provider_dropdown_header(provider_id: String) -> String:
	var header_key: String = "ui.provider_header.%s" % provider_id
	var translated: String = _tr(header_key)
	if translated != header_key:
		return translated
	return config_manager.get_provider_label(provider_id)

func _get_model_dropdown_label(entry: Dictionary) -> String:
	var model_id: String = String(entry.get("model_id", ""))
	var label: String = String(entry.get("label", model_id if not model_id.is_empty() else "model"))
	if label.contains(" · ") and not model_id.is_empty():
		var provider_label: String = config_manager.get_provider_label(String(entry.get("provider_id", "")))
		if label.get_slice(" · ", 1) == provider_label:
			return model_id
	return label

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
	_update_request_ui_state()

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
	
	# Group models by provider with labeled separators in the popup.
	# Agrupar modelos por proveedor con separadores etiquetados en el popup.
	var grouped: Dictionary = {}
	for entry in catalog_entries:
		if not entry is Dictionary:
			continue
		var provider_id: String = String(entry.get("provider_id", ""))
		if provider_id.is_empty():
			continue
		if not grouped.has(provider_id):
			grouped[provider_id] = []
		grouped[provider_id].append(entry)
	
	for provider_id in config_manager.PROVIDER_IDS:
		if not grouped.has(provider_id):
			continue
		var provider_entries: Array = grouped[provider_id]
		if provider_entries.is_empty():
			continue
		model_dropdown.add_separator(_get_provider_dropdown_header(provider_id))
		for entry in provider_entries:
			model_dropdown.add_item(_get_model_dropdown_label(entry))
			var index: int = model_dropdown.item_count - 1
			model_dropdown.set_item_metadata(index, entry)
			if String(entry.get("provider_id", "")) == default_provider and String(entry.get("model_id", "")) == default_model:
				selected_index = index
	
	model_dropdown.select(selected_index)
	_style_option_popup(model_dropdown.get_popup())

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
	if _request_busy and prompt.is_empty():
		_cancel_current_request()
		return
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
	prompt_text_edit.clear()
	_hide_autocomplete()
	var options: Dictionary = _get_query_options()
	options["model_id"] = model_id
	options["provider_id"] = provider_id
	if mention_resolver:
		options["attached_context"] = mention_resolver.build_attached_context(prompt)
	if chat_history:
		options["conversation_messages"] = chat_history.get_active_messages()
	_update_harness_label()
	_refresh_history_ui()
	
	if _request_busy:
		ai_handler.query_provider(provider_id, prompt, options)
		_update_queue_status()
		return
	
	_begin_assistant_message()
	_show_assistant_status(_tr("ui.thinking"), _tr("ui.generating"))
	_set_request_busy(true)
	ai_handler.query_provider(provider_id, prompt, options)

func _cancel_current_request() -> void:
	if ai_handler:
		ai_handler.cancel_current_request()
	_sync_request_ui_state()

func _sync_request_ui_state() -> void:
	var handler_busy: bool = ai_handler.is_busy() if ai_handler else false
	_set_request_busy(handler_busy)
	if not handler_busy:
		status_label.text = _tr("ui.ready")

func _set_request_busy(busy: bool) -> void:
	_request_busy = busy
	_update_request_ui_state()

func _update_request_ui_state() -> void:
	if _request_busy:
		send_button.text = "■"
		send_button.tooltip_text = _tr("ui.stop_tooltip")
	else:
		send_button.text = "↑"
		send_button.tooltip_text = _tr("ui.send_tooltip")
	send_button.disabled = false
	_update_queue_status()

func _update_queue_status() -> void:
	var queue_size: int = ai_handler.get_queue_size() if ai_handler else 0
	if queue_size > 0:
		status_label.text = _tr("ui.status_queued", [queue_size])
	elif _request_busy:
		pass
	else:
		status_label.text = _tr("ui.ready")

func _dispatch_queued_request(_user_prompt: String, _options: Dictionary) -> void:
	_begin_assistant_message()
	_show_assistant_status(_tr("ui.thinking"), _tr("ui.generating"))
	_set_request_busy(true)

func _on_request_dequeued(user_prompt: String, options: Dictionary) -> void:
	_dispatch_queued_request(user_prompt, options)

func _on_more_button_pressed() -> void:
	var menu_pos: Vector2 = more_button.global_position
	more_menu.position = Vector2i(int(menu_pos.x - 80), int(menu_pos.y + more_button.size.y))
	more_menu.popup()

func _on_config_button_pressed() -> void:
	config_dialog.open_dialog()

func _on_skill_installed_from_catalog(_skill_id: String) -> void:
	skills_manager.load_skills(
		String(config_manager.get_setting("skills_path", "res://addons/ai_assistant_plugin/skills")),
		String(config_manager.get_setting("active_skill", ""))
	)
	if mention_resolver:
		mention_resolver.setup(project_context, skills_manager)
		mention_resolver.rebuild_index()
	setup_skills_dropdown()
	_update_harness_label()

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
	_set_request_busy(true)
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

func _on_agent_log_updated(text: String, step: int, max_steps: int) -> void:
	_current_agent_log_text = text
	_active_copy_source = text
	if _active_content_body == null:
		return
	_active_content_body.visible = true
	if _active_status_panel and _request_busy:
		_active_status_panel.visible = true
		if _active_step_label and step > 0 and max_steps > 0:
			_active_step_label.text = _tr("ui.step_of", [step, max_steps])
		if _active_summary_label:
			_active_summary_label.text = _tr("ui.agent_step_updated", [step, max_steps])
	_populate_assistant_content(_active_content_body, text, false)
	_scroll_to_bottom(false)

func _on_response_retry_attempt(attempt: int, max_attempts: int, reason: String) -> void:
	var reason_key: String = "ui.retry_reason_%s" % reason
	var reason_text: String = _tr(reason_key)
	if reason_text == reason_key:
		reason_text = reason
	status_label.text = _tr("ui.status_retry", [attempt, max_attempts, reason_text])
	_show_assistant_status(_tr("ui.retrying"), _tr("ui.status_retry", [attempt, max_attempts, reason_text]))
	_set_request_busy(true)

func _on_query_completed(_success: bool, text: String) -> void:
	_stop_status_animation()
	_current_agent_log_text = ""
	_finish_assistant_message(text)
	chat_history.add_message("assistant", text)
	_refresh_history_ui()
	_release_ui_after_terminal_event(_tr("ui.status_done"))
	_sync_request_ui_state()

func _on_query_failed(error_message: String) -> void:
	_stop_status_animation()
	_current_agent_log_text = ""
	_finish_assistant_message(error_message, true)
	chat_history.add_message("assistant", error_message, true)
	_refresh_history_ui()
	_release_ui_after_terminal_event(_tr("ui.status_error"))
	_sync_request_ui_state()

func _on_query_cancelled() -> void:
	_stop_status_animation()
	# Keep any partial agent output already shown; just append a cancelled note.
	# Conservar lo que el agente ya mostró; solo añadir una nota de cancelado.
	var existing: String = _current_agent_log_text.strip_edges()
	if not existing.is_empty():
		var combined: String = "%s\n\n---\n%s" % [existing, _tr("ui.request_cancelled")]
		_finish_assistant_message(combined, false)
		chat_history.add_message("assistant", combined, false)
	else:
		_finish_assistant_message(_tr("ui.request_cancelled"), false)
		chat_history.add_message("assistant", _tr("ui.request_cancelled"), false)
	_current_agent_log_text = ""
	_refresh_history_ui()
	_release_ui_after_terminal_event(_tr("ui.ready"))
	_sync_request_ui_state()

func _release_ui_after_terminal_event(idle_status: String) -> void:
	var queue_size: int = ai_handler.get_queue_size() if ai_handler else 0
	var handler_busy: bool = ai_handler.is_busy() if ai_handler else false
	_set_request_busy(queue_size > 0 or handler_busy)
	if not _request_busy:
		status_label.text = idle_status
	_update_queue_status()

func _on_queue_updated(_queue_size: int) -> void:
	_update_queue_status()

func update_ui_with_response(response: String) -> void:
	_finish_assistant_message(response)

func clear_inputs() -> void:
	prompt_text_edit.clear()
	_clear_conversation()
