extends Window

# Configuration dialog for providers and assistant settings / Diálogo de configuración

signal configuration_saved
signal skill_installed(skill_id: String)

const COLOR_BG := Color(0.09, 0.09, 0.1, 1.0)
const COLOR_PANEL := Color(0.12, 0.12, 0.13, 1.0)
const COLOR_PANEL_INNER := Color(0.1, 0.1, 0.11, 1.0)
const COLOR_BORDER := Color(0.24, 0.24, 0.27, 1.0)
const COLOR_TEXT := Color(0.88, 0.88, 0.9, 1.0)
const COLOR_MUTED := Color(0.58, 0.58, 0.62, 1.0)
const COLOR_PRIMARY := Color(0.28, 0.45, 0.95, 1.0)
const COLOR_PRIMARY_HOVER := Color(0.34, 0.52, 1.0, 1.0)
const COLOR_BUTTON := Color(0.18, 0.18, 0.2, 1.0)
const COLOR_BUTTON_HOVER := Color(0.22, 0.22, 0.25, 1.0)
const COLOR_INPUT := Color(0.08, 0.08, 0.09, 1.0)

var config_manager: RefCounted = null
var model_catalog: RefCounted = null
var locale_manager: RefCounted = null
var skills_manager: RefCounted = null
var skills_catalog: RefCounted = null
var project_index: RefCounted = null
var provider_sections: Dictionary = {}
var _skills_list_vbox: VBoxContainer = null
var _skills_installed_vbox: VBoxContainer = null
var _skills_status_label: Label = null
var _skills_search_edit: LineEdit = null
var _skills_search_button: Button = null
var _remote_skill_results: Array = []
var _index_status_label: Label = null
var _index_progress_bar: ProgressBar = null
var _index_sync_button: Button = null
var _index_delete_button: Button = null
var _index_section_grid: GridContainer = null
var _docs_md_checkbox: CheckBox = null
var _docs_godot_checkbox: CheckBox = null
var _docs_global_checkbox: CheckBox = null

func setup(
	config_mgr: RefCounted,
	catalog: RefCounted = null,
	locale_mgr: RefCounted = null,
	skills_mgr: RefCounted = null,
	index_svc: RefCounted = null
) -> void:
	config_manager = config_mgr
	model_catalog = catalog
	locale_manager = locale_mgr
	skills_manager = skills_mgr
	project_index = index_svc
	if project_index:
		if not project_index.sync_started.is_connected(_on_index_sync_started):
			project_index.sync_started.connect(_on_index_sync_started)
		if not project_index.sync_progress.is_connected(_on_index_sync_progress):
			project_index.sync_progress.connect(_on_index_sync_progress)
		if not project_index.sync_finished.is_connected(_on_index_sync_finished):
			project_index.sync_finished.connect(_on_index_sync_finished)
		if not project_index.index_deleted.is_connected(_on_index_deleted):
			project_index.index_deleted.connect(_on_index_deleted)
	if skills_catalog == null:
		skills_catalog = preload("res://addons/ai_assistant_plugin/scripts/skills_catalog_client.gd").new()
		skills_catalog.setup(self)
		skills_catalog.search_completed.connect(_on_skills_search_completed)
		skills_catalog.search_failed.connect(_on_skills_search_failed)
		skills_catalog.download_completed.connect(_on_skill_download_completed)
		skills_catalog.download_failed.connect(_on_skill_download_failed)
	title = _tr("config.title")
	min_size = Vector2i(720, 620)
	size = Vector2i(760, 680)
	unresizable = false
	close_requested.connect(hide)
	_build_ui()

func _build_ui() -> void:
	for child in get_children():
		if child is HTTPRequest:
			continue
		child.queue_free()
	provider_sections.clear()
	
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 14)
	root.add_theme_constant_override("margin_right", 14)
	root.add_theme_constant_override("margin_top", 14)
	root.add_theme_constant_override("margin_bottom", 14)
	add_child(root)
	
	var shell := VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 12)
	root.add_child(shell)
	
	shell.add_child(_make_header())
	
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(tabs)
	
	var general_scroll := ScrollContainer.new()
	general_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	general_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	general_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var general_content := VBoxContainer.new()
	general_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	general_content.add_theme_constant_override("separation", 12)
	general_scroll.add_child(general_content)
	general_content.add_child(_make_section_header(_tr("config.general"), _tr("config.general_hint")))
	general_content.add_child(_make_settings_section())
	tabs.add_child(general_scroll)
	tabs.set_tab_title(general_scroll.get_index(), _tr("config.general"))
	
	tabs.add_child(_make_skills_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, _tr("config.skills"))
	
	tabs.add_child(_make_indexing_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, _tr("config.indexing"))
	
	var providers_scroll := ScrollContainer.new()
	providers_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	providers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	providers_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var providers_content := VBoxContainer.new()
	providers_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	providers_content.add_theme_constant_override("separation", 12)
	providers_scroll.add_child(providers_content)
	providers_content.add_child(_make_section_header(_tr("config.providers"), _tr("config.providers_hint")))
	for provider_id in config_manager.PROVIDER_IDS:
		providers_content.add_child(_make_provider_section(provider_id))
	tabs.add_child(providers_scroll)
	tabs.set_tab_title(providers_scroll.get_index(), _tr("config.providers"))
	
	shell.add_child(_make_footer())

func _make_header() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL, 10))
	
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	
	var title := Label.new()
	title.text = _tr("config.title")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = _tr("config.subtitle")
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(subtitle)
	
	return panel

func _make_section_header(title_text: String, subtitle_text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(subtitle)
	
	return box

func _make_settings_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL_INNER, 8))
	
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	
	grid.add_child(_make_field_label(_tr("config.default_provider")))
	var default_provider := OptionButton.new()
	default_provider.name = "DefaultProvider"
	for provider_id in config_manager.PROVIDER_IDS:
		default_provider.add_item(config_manager.get_provider_label(provider_id))
		default_provider.set_item_metadata(default_provider.item_count - 1, provider_id)
		if provider_id == config_manager.get_default_provider():
			default_provider.select(default_provider.item_count - 1)
	_style_option_button(default_provider)
	grid.add_child(default_provider)
	
	grid.add_child(_make_field_label(_tr("config.ui_language")))
	var ui_language := OptionButton.new()
	ui_language.name = "UiLanguage"
	var language_options: Array = [
		["auto", "config.lang_auto"],
		["en", "config.lang_en"],
		["es", "config.lang_es"]
	]
	var current_language: String = String(config_manager.get_setting("ui_language", "auto"))
	for language_option in language_options:
		ui_language.add_item(_tr(String(language_option[1])))
		ui_language.set_item_metadata(ui_language.item_count - 1, String(language_option[0]))
		if String(language_option[0]) == current_language:
			ui_language.select(ui_language.item_count - 1)
	_style_option_button(ui_language)
	grid.add_child(ui_language)
	
	grid.add_child(_make_field_label(_tr("config.context_depth")))
	var context_depth := OptionButton.new()
	context_depth.name = "ContextDepth"
	for depth_id in ["basic", "intermediate", "full"]:
		context_depth.add_item(depth_id.capitalize())
		context_depth.set_item_metadata(context_depth.item_count - 1, depth_id)
		if depth_id == String(config_manager.get_setting("context_depth", "intermediate")):
			context_depth.select(context_depth.item_count - 1)
	_style_option_button(context_depth)
	grid.add_child(context_depth)
	
	grid.add_child(_make_field_label(_tr("config.temperature")))
	var temperature := SpinBox.new()
	temperature.name = "Temperature"
	temperature.min_value = 0.0
	temperature.max_value = 2.0
	temperature.step = 0.1
	temperature.value = float(config_manager.get_setting("temperature", 0.7))
	temperature.custom_minimum_size = Vector2(120, 28)
	_style_spin_box(temperature)
	grid.add_child(temperature)
	
	grid.add_child(_make_field_label(_tr("config.max_tokens")))
	var max_tokens := SpinBox.new()
	max_tokens.name = "MaxTokens"
	max_tokens.min_value = 256
	max_tokens.max_value = 32768
	max_tokens.step = 256
	max_tokens.value = float(config_manager.get_setting("max_tokens", 4096))
	max_tokens.custom_minimum_size = Vector2(120, 28)
	_style_spin_box(max_tokens)
	grid.add_child(max_tokens)
	
	grid.add_child(_make_field_label(_tr("config.include_context")))
	var include_context := CheckBox.new()
	include_context.name = "IncludeContext"
	include_context.button_pressed = bool(config_manager.get_setting("include_project_context", true))
	include_context.text = _tr("config.include_context_hint")
	_style_checkbox(include_context)
	grid.add_child(include_context)
	
	grid.add_child(_make_field_label(_tr("config.enable_tools")))
	var enable_tools := CheckBox.new()
	enable_tools.name = "EnableTools"
	enable_tools.button_pressed = bool(config_manager.get_setting("enable_editor_tools", true))
	enable_tools.text = _tr("config.enable_tools_hint")
	_style_checkbox(enable_tools)
	grid.add_child(enable_tools)
	
	grid.add_child(_make_field_label(_tr("config.enable_thinking")))
	var enable_thinking := CheckBox.new()
	enable_thinking.name = "EnableThinking"
	enable_thinking.button_pressed = bool(config_manager.get_setting("enable_thinking", true))
	enable_thinking.text = _tr("config.enable_thinking_hint")
	_style_checkbox(enable_thinking)
	grid.add_child(enable_thinking)
	
	grid.add_child(_make_field_label(_tr("config.enable_agent")))
	var enable_agent := CheckBox.new()
	enable_agent.name = "EnableAgentLoop"
	enable_agent.button_pressed = bool(config_manager.get_setting("enable_agent_loop", true))
	enable_agent.text = _tr("config.enable_agent_hint")
	_style_checkbox(enable_agent)
	grid.add_child(enable_agent)
	
	grid.add_child(_make_field_label(_tr("config.agent_max_steps")))
	var agent_steps := SpinBox.new()
	agent_steps.name = "AgentMaxSteps"
	agent_steps.min_value = 1
	agent_steps.max_value = 64
	agent_steps.step = 1
	agent_steps.value = float(config_manager.get_setting("agent_max_steps", 24))
	agent_steps.custom_minimum_size = Vector2(120, 28)
	_style_spin_box(agent_steps)
	grid.add_child(agent_steps)
	
	provider_sections["_settings"] = grid
	return panel

func _make_indexing_tab() -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	root.add_child(_make_section_header(_tr("config.indexing"), _tr("config.indexing_hint")))
	
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL_INNER, 8))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	_index_section_grid = grid
	
	grid.add_child(_make_field_label(_tr("config.enable_project_index")))
	var enable_index := CheckBox.new()
	enable_index.name = "EnableProjectIndex"
	enable_index.button_pressed = bool(config_manager.get_setting("enable_project_index", true))
	enable_index.text = _tr("config.enable_project_index_hint")
	_style_checkbox(enable_index)
	grid.add_child(enable_index)
	
	grid.add_child(_make_field_label(_tr("config.index_on_startup")))
	var index_startup := CheckBox.new()
	index_startup.name = "IndexOnStartup"
	index_startup.button_pressed = bool(config_manager.get_setting("index_on_startup", true))
	index_startup.text = _tr("config.index_on_startup_hint")
	_style_checkbox(index_startup)
	grid.add_child(index_startup)
	
	grid.add_child(_make_field_label(_tr("config.index_auto_sync")))
	var index_auto := CheckBox.new()
	index_auto.name = "IndexAutoSync"
	index_auto.button_pressed = bool(config_manager.get_setting("index_auto_sync", true))
	index_auto.text = _tr("config.index_auto_sync_hint")
	_style_checkbox(index_auto)
	grid.add_child(index_auto)
	
	grid.add_child(_make_field_label(_tr("config.index_max_age_hours")))
	var index_age := SpinBox.new()
	index_age.name = "IndexMaxAgeHours"
	index_age.min_value = 0
	index_age.max_value = 720
	index_age.step = 1
	index_age.value = float(config_manager.get_setting("index_max_age_hours", 24))
	index_age.custom_minimum_size = Vector2(120, 28)
	_style_spin_box(index_age)
	grid.add_child(index_age)
	
	grid.add_child(_make_field_label(_tr("config.enable_semantic_index")))
	var enable_semantic := CheckBox.new()
	enable_semantic.name = "EnableSemanticIndex"
	enable_semantic.button_pressed = bool(config_manager.get_setting("enable_semantic_index", true))
	enable_semantic.text = _tr("config.enable_semantic_index_hint")
	_style_checkbox(enable_semantic)
	grid.add_child(enable_semantic)
	
	grid.add_child(_make_field_label(_tr("config.embedding_model")))
	var embedding_model := LineEdit.new()
	embedding_model.name = "EmbeddingModel"
	embedding_model.text = String(config_manager.get_setting("embedding_model", "nomic-embed-text"))
	embedding_model.placeholder_text = "nomic-embed-text"
	embedding_model.custom_minimum_size = Vector2(220, 28)
	_style_line_edit(embedding_model)
	grid.add_child(embedding_model)
	
	grid.add_child(_make_field_label(_tr("config.embedding_provider")))
	var embedding_provider := OptionButton.new()
	embedding_provider.name = "EmbeddingProvider"
	for provider_option in [["ollama", "Ollama"], ["lmstudio", "LM Studio"]]:
		embedding_provider.add_item(String(provider_option[1]))
		embedding_provider.set_item_metadata(embedding_provider.item_count - 1, String(provider_option[0]))
		if String(provider_option[0]) == String(config_manager.get_setting("embedding_provider", "ollama")):
			embedding_provider.select(embedding_provider.item_count - 1)
	_style_option_button(embedding_provider)
	grid.add_child(embedding_provider)
	
	grid.add_child(_make_field_label(_tr("config.semantic_max_chunks")))
	var semantic_chunks := SpinBox.new()
	semantic_chunks.name = "SemanticMaxChunks"
	semantic_chunks.min_value = 32
	semantic_chunks.max_value = 2000
	semantic_chunks.step = 32
	semantic_chunks.value = float(config_manager.get_setting("semantic_max_chunks", 400))
	semantic_chunks.custom_minimum_size = Vector2(120, 28)
	_style_spin_box(semantic_chunks)
	grid.add_child(semantic_chunks)
	
	grid.add_child(_make_field_label(_tr("config.enable_docs_index")))
	var enable_docs := CheckBox.new()
	enable_docs.name = "EnableDocsIndex"
	enable_docs.button_pressed = bool(config_manager.get_setting("enable_docs_index", true))
	enable_docs.text = _tr("config.enable_docs_index_hint")
	_style_checkbox(enable_docs)
	grid.add_child(enable_docs)
	
	grid.add_child(_make_field_label(_tr("config.docs_sources")))
	var docs_sources := VBoxContainer.new()
	docs_sources.name = "DocsSources"
	docs_sources.add_theme_constant_override("separation", 4)
	_docs_md_checkbox = CheckBox.new()
	_docs_md_checkbox.name = "DocsIncludeProjectMd"
	_docs_md_checkbox.button_pressed = bool(config_manager.get_setting("docs_include_project_md", true))
	_docs_md_checkbox.text = _tr("config.docs_include_project_md")
	_style_checkbox(_docs_md_checkbox)
	docs_sources.add_child(_docs_md_checkbox)
	_docs_godot_checkbox = CheckBox.new()
	_docs_godot_checkbox.name = "DocsIncludeGodotClasses"
	_docs_godot_checkbox.button_pressed = bool(config_manager.get_setting("docs_include_godot_classes", true))
	_docs_godot_checkbox.text = _tr("config.docs_include_godot_classes")
	_style_checkbox(_docs_godot_checkbox)
	docs_sources.add_child(_docs_godot_checkbox)
	_docs_global_checkbox = CheckBox.new()
	_docs_global_checkbox.name = "DocsIncludeGlobalClasses"
	_docs_global_checkbox.button_pressed = bool(config_manager.get_setting("docs_include_global_classes", true))
	_docs_global_checkbox.text = _tr("config.docs_include_global_classes")
	_style_checkbox(_docs_global_checkbox)
	docs_sources.add_child(_docs_global_checkbox)
	grid.add_child(docs_sources)
	
	root.add_child(panel)
	
	_index_status_label = Label.new()
	_index_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_index_status_label.add_theme_font_size_override("font_size", 11)
	_index_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(_index_status_label)
	
	_index_progress_bar = ProgressBar.new()
	_index_progress_bar.custom_minimum_size = Vector2(0, 8)
	_index_progress_bar.show_percentage = false
	_index_progress_bar.value = 0
	root.add_child(_index_progress_bar)
	
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	_index_sync_button = Button.new()
	_index_sync_button.text = _tr("config.index_sync_now")
	_index_sync_button.custom_minimum_size = Vector2(120, 30)
	_style_button(_index_sync_button, true)
	_index_sync_button.pressed.connect(_on_index_sync_pressed)
	button_row.add_child(_index_sync_button)
	_index_delete_button = Button.new()
	_index_delete_button.text = _tr("config.index_delete")
	_index_delete_button.custom_minimum_size = Vector2(120, 30)
	_style_button(_index_delete_button, false)
	_index_delete_button.pressed.connect(_on_index_delete_pressed)
	button_row.add_child(_index_delete_button)
	root.add_child(button_row)
	
	_refresh_index_status_label()
	return root

func _refresh_index_status_label() -> void:
	if _index_status_label == null:
		return
	if project_index == null:
		_index_status_label.text = _tr("config.index_unavailable")
		return
	var status: Dictionary = project_index.get_status()
	if project_index.is_syncing():
		_index_status_label.text = _tr("config.index_syncing")
		return
	if bool(status.get("ready", false)):
		var semantic_line: String = ""
		if bool(status.get("semantic_ready", false)):
			semantic_line = _tr("config.index_semantic_ready", [int(status.get("embedding_chunks", 0))])
		else:
			semantic_line = _tr("config.index_semantic_pending")
		_index_status_label.text = "%s\n%s" % [
			_tr("config.index_status_ready", [
				int(status.get("indexed_files", 0)),
				int(status.get("scenebuilder_items", 0)),
				int(status.get("scene_summaries", 0)),
				int(status.get("symbols", 0)),
			]) + " · " + _tr("config.index_docs_count", [int(status.get("docs", 0))]),
			semantic_line,
		]
	else:
		_index_status_label.text = _tr("config.index_status_empty")

func _on_index_sync_pressed() -> void:
	if project_index == null:
		return
	if _index_sync_button:
		_index_sync_button.disabled = true
	if _index_delete_button:
		_index_delete_button.disabled = true
	project_index.sync_index()

func _on_index_delete_pressed() -> void:
	if project_index == null:
		return
	project_index.delete_index()

func _on_index_sync_started() -> void:
	if _index_progress_bar:
		_index_progress_bar.value = 0
	if _index_status_label:
		_index_status_label.text = _tr("config.index_syncing")

func _on_index_sync_progress(ratio: float, _message: String) -> void:
	if _index_progress_bar:
		_index_progress_bar.value = clampf(ratio * 100.0, 0.0, 100.0)

func _on_index_sync_finished(_success: bool, _summary: Dictionary) -> void:
	if _index_sync_button:
		_index_sync_button.disabled = false
	if _index_delete_button:
		_index_delete_button.disabled = false
	if _index_progress_bar:
		_index_progress_bar.value = 100.0
	_refresh_index_status_label()

func _on_index_deleted() -> void:
	if _index_progress_bar:
		_index_progress_bar.value = 0
	_refresh_index_status_label()

func _make_skills_tab() -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	
	root.add_child(_make_section_header(_tr("config.skills"), _tr("config.skills_hint")))
	
	var installed_panel := PanelContainer.new()
	installed_panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL_INNER, 8))
	var installed_box := VBoxContainer.new()
	installed_box.add_theme_constant_override("separation", 6)
	installed_panel.add_child(installed_box)
	var installed_title := Label.new()
	installed_title.text = _tr("config.skills_installed")
	installed_title.add_theme_font_size_override("font_size", 13)
	installed_title.add_theme_color_override("font_color", COLOR_TEXT)
	installed_box.add_child(installed_title)
	_skills_installed_vbox = VBoxContainer.new()
	_skills_installed_vbox.add_theme_constant_override("separation", 4)
	installed_box.add_child(_skills_installed_vbox)
	root.add_child(installed_panel)
	
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	_skills_search_edit = LineEdit.new()
	_skills_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_search_edit.custom_minimum_size = Vector2(0, 30)
	_skills_search_edit.placeholder_text = _tr("config.skills_search_placeholder")
	_skills_search_edit.text = "godot"
	_style_line_edit(_skills_search_edit)
	_skills_search_edit.text_submitted.connect(func(_text: String) -> void: _run_skills_search())
	search_row.add_child(_skills_search_edit)
	_skills_search_button = Button.new()
	_skills_search_button.text = _tr("config.skills_search")
	_skills_search_button.custom_minimum_size = Vector2(96, 30)
	_style_button(_skills_search_button, true)
	_skills_search_button.pressed.connect(_run_skills_search)
	search_row.add_child(_skills_search_button)
	root.add_child(search_row)
	
	_skills_status_label = Label.new()
	_skills_status_label.text = _tr("config.skills_search_hint")
	_skills_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skills_status_label.add_theme_font_size_override("font_size", 11)
	_skills_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(_skills_status_label)
	
	var catalog_scroll := ScrollContainer.new()
	catalog_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_skills_list_vbox = VBoxContainer.new()
	_skills_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_list_vbox.add_theme_constant_override("separation", 6)
	catalog_scroll.add_child(_skills_list_vbox)
	root.add_child(catalog_scroll)
	
	_refresh_installed_skills_list()
	call_deferred("_run_skills_search")
	return root

func _get_skills_path() -> String:
	if skills_manager:
		return skills_manager.get_skills_path_from_config(config_manager)
	return String(config_manager.get_setting("skills_path", "res://addons/ai_assistant_plugin/skills"))

func _refresh_installed_skills_list() -> void:
	if _skills_installed_vbox == null or skills_manager == null:
		return
	var skills_path: String = _get_skills_path()
	skills_manager.load_skills(skills_path, skills_manager.active_skill_id)
	for child in _skills_installed_vbox.get_children():
		child.queue_free()
	var installed_ids: Array = skills_manager.get_installed_skill_ids(_get_skills_path())
	if installed_ids.is_empty():
		var empty := Label.new()
		empty.text = _tr("config.skills_installed_empty")
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		_skills_installed_vbox.add_child(empty)
		return
	for skill_id in installed_ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = skills_manager.get_skill_label(String(skill_id))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", COLOR_TEXT)
		row.add_child(label)
		if String(skill_id) == skills_manager.active_skill_id:
			var active_badge := Label.new()
			active_badge.text = _tr("config.skills_active")
			active_badge.add_theme_font_size_override("font_size", 11)
			active_badge.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55, 1.0))
			row.add_child(active_badge)
		_skills_installed_vbox.add_child(row)

func _run_skills_search() -> void:
	if skills_catalog == null or _skills_search_edit == null:
		return
	var query: String = _skills_search_edit.text.strip_edges()
	if query.length() < 2:
		_skills_status_label.text = _tr("config.skills_query_short")
		return
	_skills_status_label.text = _tr("config.skills_searching")
	_skills_search_button.disabled = true
	skills_catalog.search(query, 40)

func _render_remote_skills(results: Array) -> void:
	if _skills_list_vbox == null:
		return
	for child in _skills_list_vbox.get_children():
		child.queue_free()
	_remote_skill_results = results
	if results.is_empty():
		var empty := Label.new()
		empty.text = _tr("config.skills_no_results")
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		_skills_list_vbox.add_child(empty)
		return
	var skills_path: String = _get_skills_path()
	for index in results.size():
		var skill: Dictionary = results[index] if results[index] is Dictionary else {}
		if skill.is_empty():
			continue
		var skill_id: String = String(skill.get("skillId", skill.get("slug", skill.get("name", ""))))
		var source: String = String(skill.get("source", ""))
		var installs: int = int(skill.get("installs", 0))
		var display_name: String = String(skill.get("name", skill_id))
		var installed: bool = skills_manager.is_skill_installed(skills_path, skill_id)
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL_INNER, 6))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row_panel.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		var title := Label.new()
		title.text = display_name
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", COLOR_TEXT)
		info.add_child(title)
		var meta := Label.new()
		meta.text = "%s · %s" % [source, _tr("config.skills_installs", [installs])]
		meta.add_theme_font_size_override("font_size", 11)
		meta.add_theme_color_override("font_color", COLOR_MUTED)
		info.add_child(meta)
		if installed:
			var badge := Label.new()
			badge.text = _tr("config.skills_installed_badge")
			badge.add_theme_font_size_override("font_size", 11)
			badge.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55, 1.0))
			row.add_child(badge)
		else:
			var install_btn := Button.new()
			install_btn.text = _tr("config.skills_install")
			install_btn.custom_minimum_size = Vector2(88, 28)
			_style_button(install_btn, true)
			install_btn.pressed.connect(_on_install_skill_pressed.bind(index))
			row.add_child(install_btn)
		_skills_list_vbox.add_child(row_panel)

func _on_install_skill_pressed(result_index: int) -> void:
	if skills_catalog == null or skills_manager == null:
		return
	if result_index < 0 or result_index >= _remote_skill_results.size():
		return
	var skill: Dictionary = _remote_skill_results[result_index]
	var skill_id: String = String(skill.get("skillId", skill.get("slug", skill.get("name", ""))))
	var source: String = String(skill.get("source", ""))
	if skill_id.is_empty() or source.is_empty():
		return
	_skills_status_label.text = _tr("config.skills_downloading", [skill_id])
	skills_catalog.download_skill(source, skill_id)

func _on_skills_search_completed(results: Array, _query: String) -> void:
	if _skills_search_button:
		_skills_search_button.disabled = false
	if _skills_status_label:
		_skills_status_label.text = _tr("config.skills_results", [results.size()])
	_render_remote_skills(results)

func _on_skills_search_failed(error_message: String) -> void:
	if _skills_search_button:
		_skills_search_button.disabled = false
	if _skills_status_label:
		if error_message == "query_too_short":
			_skills_status_label.text = _tr("config.skills_query_short")
		elif error_message == "busy":
			_skills_status_label.text = _tr("config.skills_busy")
		else:
			_skills_status_label.text = _tr("config.skills_search_failed", [error_message])

func _on_skill_download_completed(skill_id: String, content: String, _metadata: Dictionary) -> void:
	if skills_manager == null:
		return
	var skills_path: String = _get_skills_path()
	if skills_manager.install_skill_file(skills_path, skill_id, content, true):
		config_manager.set_setting("active_skill", skills_manager.active_skill_id)
		config_manager.set_setting("skills_path", skills_path)
		config_manager.save_config()
		_refresh_installed_skills_list()
		_render_remote_skills(_remote_skill_results)
		_skills_status_label.text = _tr("config.skills_installed_ok", [skill_id])
		skill_installed.emit(skills_manager.active_skill_id)
	else:
		_skills_status_label.text = _tr("config.skills_install_failed", [skill_id])

func _on_skill_download_failed(skill_id: String, error_message: String) -> void:
	if _skills_status_label:
		_skills_status_label.text = _tr("config.skills_download_failed", [skill_id, error_message])

func _make_provider_section(provider_id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL_INNER, 8))
	
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	
	var title := Label.new()
	title.text = config_manager.get_provider_label(provider_id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title)
	
	var provider_cfg: Dictionary = config_manager.get_provider_config(provider_id)
	var badge := Label.new()
	badge.text = _tr("config.enabled") if bool(provider_cfg.get("enabled", false)) else _tr("config.disabled")
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override(
		"font_color",
		Color(0.45, 0.85, 0.55, 1.0) if bool(provider_cfg.get("enabled", false)) else COLOR_MUTED
	)
	header.add_child(badge)
	
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	
	grid.add_child(_make_field_label(_tr("config.enabled")))
	var enabled := CheckBox.new()
	enabled.name = "Enabled"
	enabled.button_pressed = bool(provider_cfg.get("enabled", false))
	enabled.text = _tr("config.use_provider")
	_style_checkbox(enabled)
	grid.add_child(enabled)
	
	grid.add_child(_make_field_label(_tr("config.endpoint")))
	var endpoint := LineEdit.new()
	endpoint.name = "Endpoint"
	endpoint.text = String(provider_cfg.get("api_endpoint", ""))
	endpoint.placeholder_text = "http://localhost:11434"
	endpoint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	endpoint.custom_minimum_size = Vector2(260, 28)
	_style_line_edit(endpoint)
	grid.add_child(endpoint)
	
	grid.add_child(_make_field_label(_tr("config.default_model")))
	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 6)
	var model_option := OptionButton.new()
	model_option.name = "ModelOption"
	model_option.custom_minimum_size = Vector2(220, 28)
	model_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_button(model_option)
	_populate_provider_models(provider_id, model_option, String(provider_cfg.get("model", "")))
	var refresh_models_btn := Button.new()
	refresh_models_btn.text = "↻"
	refresh_models_btn.custom_minimum_size = Vector2(32, 28)
	_style_button(refresh_models_btn, false)
	refresh_models_btn.pressed.connect(func() -> void:
		_refresh_provider_models(provider_id, model_option)
	)
	model_row.add_child(model_option)
	model_row.add_child(refresh_models_btn)
	grid.add_child(model_row)
	
	if provider_id in ["openai", "anthropic", "lmstudio", "cursor", "gemini", "openrouter", "kimi", "minimax"]:
		grid.add_child(_make_field_label(_tr("config.api_key")))
		var api_key := LineEdit.new()
		api_key.name = "ApiKey"
		var from_env: bool = config_manager.is_provider_api_key_from_env(provider_id)
		if from_env:
			api_key.text = "••••••••"
			api_key.editable = false
			api_key.placeholder_text = config_manager.get_provider_api_key_env_var(provider_id)
		else:
			api_key.text = String(provider_cfg.get("api_key", ""))
			api_key.placeholder_text = _tr("config.api_key_placeholder")
		api_key.secret = not from_env
		api_key.custom_minimum_size = Vector2(260, 28)
		_style_line_edit(api_key)
		grid.add_child(api_key)
		if from_env:
			var env_hint := Label.new()
			env_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			env_hint.text = _tr("config.api_key_env_hint", [config_manager.get_provider_api_key_env_var(provider_id)])
			env_hint.add_theme_font_size_override("font_size", 11)
			env_hint.add_theme_color_override("font_color", COLOR_MUTED)
			box.add_child(env_hint)
	
	if provider_id == "cursor":
		grid.add_child(_make_field_label(_tr("config.api_mode")))
		var cursor_mode := OptionButton.new()
		cursor_mode.name = "ApiMode"
		cursor_mode.add_item("local_proxy")
		cursor_mode.add_item("cloud_agents")
		var cursor_current_mode: String = String(provider_cfg.get("api_mode", "local_proxy"))
		cursor_mode.select(0 if cursor_current_mode == "local_proxy" else 1)
		_style_option_button(cursor_mode)
		grid.add_child(cursor_mode)
		
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = _tr("config.cursor_hint")
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", COLOR_MUTED)
		box.add_child(hint)
	elif provider_id == "openrouter":
		var openrouter_hint := Label.new()
		openrouter_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		openrouter_hint.text = _tr("config.openrouter_hint")
		openrouter_hint.add_theme_font_size_override("font_size", 11)
		openrouter_hint.add_theme_color_override("font_color", COLOR_MUTED)
		box.add_child(openrouter_hint)
	elif provider_id == "kimi":
		var kimi_hint := Label.new()
		kimi_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		kimi_hint.text = _tr("config.kimi_hint")
		kimi_hint.add_theme_font_size_override("font_size", 11)
		kimi_hint.add_theme_color_override("font_color", COLOR_MUTED)
		box.add_child(kimi_hint)
	elif provider_id == "minimax":
		var minimax_hint := Label.new()
		minimax_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		minimax_hint.text = _tr("config.minimax_hint")
		minimax_hint.add_theme_font_size_override("font_size", 11)
		minimax_hint.add_theme_color_override("font_color", COLOR_MUTED)
		box.add_child(minimax_hint)
	
	provider_sections[provider_id] = grid
	return panel

func _make_footer() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(COLOR_PANEL, 8))
	
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	
	var hint := Label.new()
	hint.text = _tr("config.save_hint")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(hint)
	
	var cancel_button := Button.new()
	cancel_button.text = _tr("config.cancel")
	cancel_button.custom_minimum_size = Vector2(88, 32)
	cancel_button.pressed.connect(hide)
	_style_button(cancel_button, false)
	row.add_child(cancel_button)
	
	var save_button := Button.new()
	save_button.text = _tr("config.save")
	save_button.custom_minimum_size = Vector2(96, 32)
	save_button.pressed.connect(_on_save_pressed)
	_style_button(save_button, true)
	row.add_child(save_button)
	
	return panel

func _make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	return label

func _make_panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _style_line_edit(line_edit: LineEdit) -> void:
	line_edit.add_theme_font_size_override("font_size", 12)
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_INPUT
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("focus", normal.duplicate())
	line_edit.add_theme_color_override("font_color", COLOR_TEXT)
	line_edit.add_theme_color_override("font_placeholder_color", COLOR_MUTED)

func _style_spin_box(spin_box: SpinBox) -> void:
	var line_edit := spin_box.get_line_edit()
	if line_edit:
		line_edit.text_submitted.connect(func(text: String) -> void:
			_commit_spin_box(spin_box, text)
		)
	spin_box.add_theme_font_size_override("font_size", 12)
	if spin_box.get_line_edit():
		_style_line_edit(spin_box.get_line_edit())

func _style_option_button(option: OptionButton) -> void:
	option.custom_minimum_size = Vector2(180, 28)
	option.focus_mode = Control.FOCUS_NONE
	option.add_theme_font_size_override("font_size", 12)
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_INPUT
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	option.add_theme_stylebox_override("normal", normal)
	option.add_theme_color_override("font_color", COLOR_TEXT)

func _style_checkbox(checkbox: CheckBox) -> void:
	checkbox.add_theme_font_size_override("font_size", 12)
	checkbox.add_theme_color_override("font_color", COLOR_TEXT)
	checkbox.add_theme_color_override("font_hover_color", COLOR_TEXT)

func _style_button(button: Button, primary: bool) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	
	if primary:
		normal.bg_color = COLOR_PRIMARY
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
	else:
		normal.bg_color = COLOR_BUTTON
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
	
	var hover := normal.duplicate()
	hover.bg_color = COLOR_PRIMARY_HOVER if primary else COLOR_BUTTON_HOVER
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)

func _commit_spin_box(spin_box: SpinBox, text_override: String = "") -> void:
	# SpinBox.value is not updated until focus leaves the LineEdit; apply typed text on save.
	# SpinBox.value no se actualiza hasta que el LineEdit pierde foco; aplicar texto al guardar.
	var line_edit := spin_box.get_line_edit()
	var text := text_override.strip_edges()
	if text.is_empty() and line_edit != null:
		text = line_edit.text.strip_edges()
	if text.is_empty():
		return
	if not text.is_valid_float():
		return
	spin_box.value = clampf(float(text), spin_box.min_value, spin_box.max_value)

func _on_save_pressed() -> void:
	var settings_grid: GridContainer = provider_sections.get("_settings")
	if settings_grid:
		for spin_name in ["Temperature", "MaxTokens", "AgentMaxSteps"]:
			var spin_node := settings_grid.get_node_or_null(spin_name)
			if spin_node is SpinBox:
				_commit_spin_box(spin_node as SpinBox)
		if _index_section_grid:
			var age_spin := _index_section_grid.get_node_or_null("IndexMaxAgeHours")
			if age_spin is SpinBox:
				_commit_spin_box(age_spin as SpinBox)
			var chunks_spin := _index_section_grid.get_node_or_null("SemanticMaxChunks")
			if chunks_spin is SpinBox:
				_commit_spin_box(chunks_spin as SpinBox)
		var default_provider: OptionButton = settings_grid.get_node("DefaultProvider") as OptionButton
		var context_depth_node: OptionButton = settings_grid.get_node("ContextDepth") as OptionButton
		var ui_language_node: OptionButton = settings_grid.get_node("UiLanguage") as OptionButton
		config_manager.set_default_provider(String(default_provider.get_item_metadata(default_provider.selected)))
		config_manager.set_setting("ui_language", String(ui_language_node.get_item_metadata(ui_language_node.selected)))
		config_manager.set_setting("context_depth", String(context_depth_node.get_item_metadata(context_depth_node.selected)))
		config_manager.set_setting("temperature", float(settings_grid.get_node("Temperature").value))
		config_manager.set_setting("max_tokens", int(settings_grid.get_node("MaxTokens").value))
		config_manager.set_setting("include_project_context", settings_grid.get_node("IncludeContext").button_pressed)
		config_manager.set_setting("enable_editor_tools", settings_grid.get_node("EnableTools").button_pressed)
		config_manager.set_setting("enable_thinking", settings_grid.get_node("EnableThinking").button_pressed)
		config_manager.set_setting("enable_agent_loop", settings_grid.get_node("EnableAgentLoop").button_pressed)
		config_manager.set_setting("agent_max_steps", int(settings_grid.get_node("AgentMaxSteps").value))
	
	if _index_section_grid:
		config_manager.set_setting(
			"enable_project_index",
			_index_checkbox_pressed("EnableProjectIndex", true)
		)
		config_manager.set_setting(
			"index_on_startup",
			_index_checkbox_pressed("IndexOnStartup", true)
		)
		config_manager.set_setting(
			"index_auto_sync",
			_index_checkbox_pressed("IndexAutoSync", true)
		)
		var age_spin := _index_section_grid.get_node_or_null("IndexMaxAgeHours")
		if age_spin is SpinBox:
			config_manager.set_setting("index_max_age_hours", int((age_spin as SpinBox).value))
		config_manager.set_setting(
			"enable_semantic_index",
			_index_checkbox_pressed("EnableSemanticIndex", true)
		)
		var model_edit := _index_section_grid.get_node_or_null("EmbeddingModel")
		if model_edit is LineEdit:
			config_manager.set_setting("embedding_model", (model_edit as LineEdit).text.strip_edges())
		var embed_provider := _index_section_grid.get_node_or_null("EmbeddingProvider") as OptionButton
		if embed_provider:
			config_manager.set_setting(
				"embedding_provider",
				String(embed_provider.get_item_metadata(embed_provider.selected))
			)
		var chunks_spin := _index_section_grid.get_node_or_null("SemanticMaxChunks")
		if chunks_spin is SpinBox:
			config_manager.set_setting("semantic_max_chunks", int((chunks_spin as SpinBox).value))
		config_manager.set_setting(
			"enable_docs_index",
			_index_checkbox_pressed("EnableDocsIndex", true)
		)
		config_manager.set_setting(
			"docs_include_project_md",
			_docs_md_checkbox.button_pressed if _docs_md_checkbox else true
		)
		config_manager.set_setting(
			"docs_include_godot_classes",
			_docs_godot_checkbox.button_pressed if _docs_godot_checkbox else true
		)
		config_manager.set_setting(
			"docs_include_global_classes",
			_docs_global_checkbox.button_pressed if _docs_global_checkbox else true
		)
		config_manager.set_setting("semantic_index_on_sync", true)
	
	for provider_id in config_manager.PROVIDER_IDS:
		var grid: GridContainer = provider_sections.get(provider_id)
		if grid == null:
			continue
		
		var provider_cfg: Dictionary = config_manager.get_provider_config(provider_id).duplicate(true)
		provider_cfg["enabled"] = grid.get_node("Enabled").button_pressed
		provider_cfg["api_endpoint"] = grid.get_node("Endpoint").text.strip_edges()
		
		if grid.has_node("ModelOption"):
			var model_option: OptionButton = grid.get_node("ModelOption") as OptionButton
			var model_meta: Variant = model_option.get_item_metadata(model_option.selected)
			if model_meta is Dictionary:
				provider_cfg["model"] = String(model_meta.get("model_id", ""))
			elif model_option.item_count > 0:
				provider_cfg["model"] = model_option.get_item_text(model_option.selected)
		
		if grid.has_node("ApiKey") and not config_manager.is_provider_api_key_from_env(provider_id):
			provider_cfg["api_key"] = grid.get_node("ApiKey").text
		if grid.has_node("ApiMode"):
			provider_cfg["api_mode"] = grid.get_node("ApiMode").get_item_text(grid.get_node("ApiMode").selected)
		
		config_manager.set_provider_config(provider_id, provider_cfg)
	
	configuration_saved.emit()
	hide()

func open_dialog() -> void:
	if config_manager:
		_build_ui()
		if model_catalog:
			model_catalog.refresh_all()
		_refresh_index_status_label()
	popup_centered()

func _populate_provider_models(provider_id: String, option: OptionButton, selected_model: String) -> void:
	option.clear()
	var entries: Array = []
	if model_catalog:
		entries = model_catalog.get_entries_for_provider(provider_id)
	
	if entries.is_empty():
		var fallback: String = selected_model if not selected_model.is_empty() else "default"
		option.add_item(fallback)
		option.set_item_metadata(0, {"provider_id": provider_id, "model_id": fallback})
		return
	
	var selected_index: int = 0
	for entry in entries:
		if entry is Dictionary:
			option.add_item(String(entry.get("label", entry.get("model_id", "model"))))
			var index: int = option.item_count - 1
			option.set_item_metadata(index, entry)
			if String(entry.get("model_id", "")) == selected_model:
				selected_index = index
	option.select(selected_index)

func _refresh_provider_models(provider_id: String, option: OptionButton) -> void:
	if model_catalog == null:
		return
	var selected_model: String = ""
	if option.item_count > 0:
		var meta: Variant = option.get_item_metadata(option.selected)
		if meta is Dictionary:
			selected_model = String(meta.get("model_id", ""))
	var on_models_updated := func(updated_provider_id: String, _entries: Array) -> void:
		if updated_provider_id == provider_id:
			_populate_provider_models(provider_id, option, selected_model)
	model_catalog.provider_models_updated.connect(on_models_updated, CONNECT_ONE_SHOT)
	model_catalog.refresh_provider(provider_id)

func _index_find_control(name: String) -> Node:
	if _index_section_grid == null:
		return null
	return _index_section_grid.find_child(name, true, false)

func _index_checkbox_pressed(name: String, default_value: bool = false) -> bool:
	var node := _index_find_control(name)
	if node is CheckBox:
		return (node as CheckBox).button_pressed
	return default_value

func _tr(key: String, args: Array = []) -> String:
	if locale_manager:
		return locale_manager.get_text(key, args)
	return key
