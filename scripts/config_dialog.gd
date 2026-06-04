extends Window

# Configuration dialog for providers and assistant settings / Diálogo de configuración

signal configuration_saved

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
var provider_sections: Dictionary = {}

func setup(config_mgr: RefCounted, catalog: RefCounted = null, locale_mgr: RefCounted = null) -> void:
	config_manager = config_mgr
	model_catalog = catalog
	locale_manager = locale_mgr
	title = _tr("config.title")
	min_size = Vector2i(680, 560)
	size = Vector2i(720, 620)
	unresizable = false
	close_requested.connect(hide)
	_build_ui()

func _build_ui() -> void:
	for child in get_children():
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
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	
	content.add_child(_make_section_header(_tr("config.general"), _tr("config.general_hint")))
	content.add_child(_make_settings_section())
	content.add_child(_make_section_header(_tr("config.providers"), _tr("config.providers_hint")))
	
	for provider_id in config_manager.PROVIDER_IDS:
		content.add_child(_make_provider_section(provider_id))
	
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
	agent_steps.max_value = 20
	agent_steps.step = 1
	agent_steps.value = float(config_manager.get_setting("agent_max_steps", 8))
	agent_steps.custom_minimum_size = Vector2(120, 28)
	_style_spin_box(agent_steps)
	grid.add_child(agent_steps)
	
	provider_sections["_settings"] = grid
	return panel

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
	
	if provider_id in ["openai", "anthropic", "lmstudio", "cursor", "gemini"]:
		grid.add_child(_make_field_label(_tr("config.api_key")))
		var api_key := LineEdit.new()
		api_key.name = "ApiKey"
		api_key.text = String(provider_cfg.get("api_key", ""))
		api_key.placeholder_text = _tr("config.api_key_placeholder")
		api_key.secret = true
		api_key.custom_minimum_size = Vector2(260, 28)
		_style_line_edit(api_key)
		grid.add_child(api_key)
	
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

func _on_save_pressed() -> void:
	var settings_grid: GridContainer = provider_sections.get("_settings")
	if settings_grid:
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
		
		if grid.has_node("ApiKey"):
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

func _tr(key: String, args: Array = []) -> String:
	if locale_manager:
		return locale_manager.get_text(key, args)
	return key
