class_name GameInterface
extends CanvasLayer

signal command(action: String, value: Variant)

const GameSession = preload("res://scripts/data/game_session.gd")

const NAVY := Color("081522")
const NAVY_PANEL := Color("122638e8")
const NAVY_RAISED := Color("1b3548")
const MINT := Color("74e2c0")
const MINT_DARK := Color("347f72")
const BRASS := Color("d5ad62")
const TEXT := Color("eef7f4")
const MUTED := Color("91a9ad")
const DANGER := Color("df806f")

var current_screen := ""

var _built := false
var _ui_theme: Theme
var _locale := "en"
var _screen_root: Control
var _transition: Control
var _transition_bar: ProgressBar
var _transition_label: Label
var _toast_label: Label
var _toast_serial := 0

var _selected_profile := 0
var _profiles: Array = []
var _profile_buttons: Array[Button] = []
var _continue_button: Button
var _cached_session: RefCounted
var _cached_settings: Dictionary = {}
var _cached_puzzle: Dictionary = {}
var _cached_hud: Dictionary = {}
var _hud_health: ProgressBar
var _hud_counts: Label
var _hud_objective: Label
var _hud_prompt: Label
var _hud_ability: Label


func _ready() -> void:
	_ensure_built()


func show_main(profiles: Array) -> void:
	_ensure_built()
	current_screen = "main"
	_profiles = profiles.duplicate(true)
	_selected_profile = clampi(_selected_profile, 0, 2)
	_clear_screen()

	var layout := _centered_layout(780.0)
	layout.add_child(_title("GAME_TITLE", 40, MINT))
	layout.add_child(_label("MAIN_TAGLINE", 19, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	layout.add_child(_spacer(14.0))
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 14)
	_profile_buttons.clear()
	for index in 3:
		var card := _button("", _on_profile_selected.bind(index), true)
		card.custom_minimum_size = Vector2(230.0, 132.0)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		profile_row.add_child(card)
		_profile_buttons.append(card)
	layout.add_child(profile_row)
	_update_profile_cards()

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_continue_button = _button("MENU_CONTINUE", _on_continue_pressed)
	actions.add_child(_continue_button)
	actions.add_child(_button("MENU_NEW_GAME", _on_new_game_pressed))
	actions.add_child(_button("MENU_SETTINGS", _emit_command.bind("settings", null)))
	actions.add_child(_button("MENU_EXIT", _emit_command.bind("quit", null), false, true))
	layout.add_child(actions)
	_update_continue_button()


func show_pause() -> void:
	_ensure_built()
	current_screen = "pause"
	_clear_screen()
	var layout := _centered_layout(440.0)
	layout.add_child(_title("PAUSE_TITLE", 34, MINT))
	layout.add_child(_button("PAUSE_RESUME", _emit_command.bind("resume", null)))
	layout.add_child(_button("PAUSE_COLLECTION", _emit_command.bind("collection", null)))
	layout.add_child(_button("MENU_SETTINGS", _emit_command.bind("settings", null)))
	layout.add_child(_button("PAUSE_HUB", _emit_command.bind("hub", null)))
	layout.add_child(_button("PAUSE_QUIT_MENU", _emit_command.bind("quit_to_menu", null), false, true))


func show_hud() -> void:
	_ensure_built()
	current_screen = "hud"
	_clear_screen(true)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28.0
	top.offset_top = 24.0
	top.offset_right = -28.0
	top.offset_bottom = 104.0
	top.add_theme_constant_override("separation", 18)
	_screen_root.add_child(top)

	var health_panel := _panel(Vector2(250.0, 72.0))
	var health_box := VBoxContainer.new()
	health_box.add_child(_label("HUD_HEALTH", 15, MUTED))
	_hud_health = ProgressBar.new()
	_hud_health.max_value = GameSession.MAX_HEALTH
	_hud_health.show_percentage = false
	_hud_health.custom_minimum_size = Vector2(210.0, 16.0)
	_style_progress(_hud_health)
	health_box.add_child(_hud_health)
	health_panel.add_child(health_box)
	top.add_child(health_panel)

	var objective_panel := _panel(Vector2(520.0, 72.0))
	_hud_objective = _label("", 18, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hud_objective.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	objective_panel.add_child(_hud_objective)
	top.add_child(objective_panel)
	objective_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_panel.size_flags_stretch_ratio = 1.0

	var counts_panel := _panel(Vector2(280.0, 72.0))
	_hud_counts = _label("", 16, BRASS, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud_counts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	counts_panel.add_child(_hud_counts)
	top.add_child(counts_panel)

	var ability_panel := _panel(Vector2(300.0, 62.0))
	ability_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ability_panel.offset_left = 28.0
	ability_panel.offset_top = -90.0
	ability_panel.offset_right = 328.0
	ability_panel.offset_bottom = -28.0
	_hud_ability = _label("", 16, MINT)
	ability_panel.add_child(_hud_ability)
	_screen_root.add_child(ability_panel)

	_hud_prompt = _label("", 17, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hud_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud_prompt.offset_left = 350.0
	_hud_prompt.offset_top = -74.0
	_hud_prompt.offset_right = -650.0
	_hud_prompt.offset_bottom = -30.0
	_screen_root.add_child(_hud_prompt)
	var controls_panel := _panel(Vector2(620.0, 64.0))
	controls_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	controls_panel.offset_left = -648.0
	controls_panel.offset_top = -98.0
	controls_panel.offset_right = -28.0
	controls_panel.offset_bottom = -28.0
	var controls := _label("HUD_CONTROLS", 18, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls_panel.add_child(controls)
	_screen_root.add_child(controls_panel)
	_apply_cached_hud()


func show_collection(session: GameSession) -> void:
	_ensure_built()
	current_screen = "collection"
	_cached_session = session
	_clear_screen()
	var layout := _centered_layout(700.0)
	layout.add_child(_title("COLLECTION_TITLE", 34, MINT))
	layout.add_child(_section("COLLECTION_ARTIFACTS", _owned_line(session.artifact_collected, "ARTIFACT_PHASE_GAUNTLET")))
	layout.add_child(_section("COLLECTION_CRYSTALS", _owned_line(session.crystal_collected, "CRYSTAL_FOREST_MEMORY")))
	var shard_text := tr("COLLECTION_EMPTY")
	if not session.memory_shards.is_empty():
		var localized_shards: Array[String] = []
		for shard_id: String in session.memory_shards:
			localized_shards.append(tr("MEMORY_FOREST_SHARD") if shard_id == GameSession.MEMORY_SHARD_ID else tr("MEMORY_UNKNOWN"))
		shard_text = "\n".join(localized_shards)
	layout.add_child(_section("COLLECTION_MEMORIES", shard_text))
	layout.add_child(_button("COMMON_BACK", _emit_command.bind("collection_back", null)))


func show_settings(settings: Dictionary) -> void:
	_ensure_built()
	current_screen = "settings"
	_cached_settings = _settings_with_defaults(settings)
	_clear_screen()
	var layout := _centered_layout(720.0)
	layout.add_child(_title("SETTINGS_TITLE", 34, MINT))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 12)
	_add_slider_setting(grid, "SETTINGS_FOV", "fov", 60.0, 70.0, 1.0, _cached_settings.fov)
	_add_slider_setting(grid, "SETTINGS_SENSITIVITY", "sensitivity", 0.001, 0.01, 0.0005, _cached_settings.sensitivity)
	_add_toggle_setting(grid, "SETTINGS_INVERT_Y", "invert_y", _cached_settings.invert_y)
	_add_toggle_setting(grid, "SETTINGS_INTERACTION", "interaction_hold", _cached_settings.interaction_hold)
	_add_option_setting(grid, "SETTINGS_LAYOUT", "layout", ["wasd", "arrows"], ["SETTINGS_WASD", "SETTINGS_ARROWS"], _cached_settings.layout)
	_add_option_setting(grid, "SETTINGS_LANGUAGE", "locale", ["en", "ru"], ["LANGUAGE_EN", "LANGUAGE_RU"], _cached_settings.locale)
	_add_slider_setting(grid, "SETTINGS_MASTER", "master", 0.0, 1.0, 0.05, _cached_settings.master)
	_add_slider_setting(grid, "SETTINGS_MUSIC", "music", 0.0, 1.0, 0.05, _cached_settings.music)
	_add_slider_setting(grid, "SETTINGS_EFFECTS", "effects", 0.0, 1.0, 0.05, _cached_settings.effects)
	_add_toggle_setting(grid, "SETTINGS_FULLSCREEN", "fullscreen", _cached_settings.fullscreen)
	_add_option_setting(grid, "SETTINGS_QUALITY", "quality", ["low", "medium", "high"], ["QUALITY_LOW", "QUALITY_MEDIUM", "QUALITY_HIGH"], _cached_settings.quality)
	layout.add_child(grid)
	layout.add_child(_button("COMMON_BACK", _emit_command.bind("settings_back", null)))


func show_puzzle(orientations: Array, hint_available: bool, hint_level: int) -> void:
	_ensure_built()
	current_screen = "puzzle"
	_cached_puzzle = {
		"orientations": orientations.duplicate(),
		"hint_available": hint_available,
		"hint_level": clampi(hint_level, 0, 3),
	}
	_clear_screen(true)

	var panel := _panel(Vector2(430.0, 0.0))
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -474.0
	panel.offset_top = 24.0
	panel.offset_right = -24.0
	panel.offset_bottom = -24.0
	_screen_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_title("PUZZLE_TITLE", 28, MINT))
	var instruction := _label("PUZZLE_INSTRUCTION", 18, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.custom_minimum_size = Vector2(0.0, 58.0)
	box.add_child(instruction)
	for index in 3:
		var orientation := 0
		if index < orientations.size() and (typeof(orientations[index]) == TYPE_INT or typeof(orientations[index]) == TYPE_FLOAT):
			orientation = int(orientations[index]) % 4
		var key := "PUZZLE_PRISM_%d" % (index + 1)
		var rotate := _button("%s  ·  %s" % [tr(key), tr("DIRECTION_%d" % orientation)], _emit_command.bind("rotate", index))
		box.add_child(rotate)
	box.add_child(_button("PUZZLE_RESET", _emit_command.bind("reset_puzzle", null), true))
	var hint := _button("PUZZLE_HINT", _emit_command.bind("hint", null))
	hint.visible = hint_available
	box.add_child(hint)
	var hint_text := _label(_hint_text_key(hint_level), 16, BRASS, HORIZONTAL_ALIGNMENT_CENTER)
	hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_text.custom_minimum_size.y = 110.0
	box.add_child(hint_text)
	box.add_child(_button("PUZZLE_CLOSE", _emit_command.bind("close_puzzle", null)))


func update_hud(session: GameSession, cooldown: float, objective: String, prompt: String) -> void:
	_cached_hud = {
		"session": session,
		"cooldown": maxf(0.0, cooldown),
		"objective": objective,
		"prompt": prompt,
	}
	if current_screen == "hud" and is_instance_valid(_hud_health):
		_apply_cached_hud()


func toast(text: String) -> void:
	_ensure_built()
	_toast_serial += 1
	var serial := _toast_serial
	_toast_label.text = text
	_toast_label.visible = not text.is_empty()
	if not text.is_empty() and is_inside_tree():
		get_tree().create_timer(2.4).timeout.connect(_hide_toast.bind(serial))


func set_locale(locale: String) -> void:
	_ensure_built()
	var resolved := "ru" if locale.begins_with("ru") else "en"
	if _locale == resolved:
		return
	_locale = resolved
	TranslationServer.set_locale(resolved)
	if not _cached_settings.is_empty():
		_cached_settings.locale = resolved
	_refresh_current_screen()


func show_transition(progress: float) -> void:
	_ensure_built()
	_transition.visible = true
	_transition.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_bar.value = clampf(progress, 0.0, 1.0) * 100.0
	_transition_label.text = tr("TRANSITION_LOADING")


func hide_transition() -> void:
	_ensure_built()
	_transition.visible = false
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	TranslationServer.set_locale("en")
	_ui_theme = Theme.new()
	_ui_theme.default_font_size = 18
	if ResourceLoader.exists("res://assets/fonts/DejaVuSans.ttf"):
		_ui_theme.default_font = load("res://assets/fonts/DejaVuSans.ttf")
	_screen_root = Control.new()
	_screen_root.name = "Screen"
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.theme = _ui_theme
	add_child(_screen_root)

	_transition = ColorRect.new()
	_transition.name = "Transition"
	_transition.color = Color("050d17f2")
	_transition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition.theme = _ui_theme
	_transition.visible = false
	add_child(_transition)
	var transition_box := VBoxContainer.new()
	transition_box.set_anchors_preset(Control.PRESET_CENTER)
	transition_box.position = Vector2(-210.0, -45.0)
	transition_box.size = Vector2(420.0, 90.0)
	_transition.add_child(transition_box)
	_transition_label = _label("TRANSITION_LOADING", 20, MINT, HORIZONTAL_ALIGNMENT_CENTER)
	transition_box.add_child(_transition_label)
	_transition_bar = ProgressBar.new()
	_transition_bar.show_percentage = false
	_transition_bar.custom_minimum_size.y = 12.0
	_style_progress(_transition_bar)
	transition_box.add_child(_transition_bar)

	_toast_label = _label("", 17, NAVY, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.offset_left = -260.0
	_toast_label.offset_top = 128.0
	_toast_label.offset_right = 260.0
	_toast_label.offset_bottom = 176.0
	_toast_label.add_theme_stylebox_override("normal", _style_box(MINT, 10, 14))
	_toast_label.visible = false
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.theme = _ui_theme
	add_child(_toast_label)


func _clear_screen(transparent := false) -> void:
	for child in _screen_root.get_children():
		_screen_root.remove_child(child)
		child.queue_free()
	var background := ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.0) if transparent else NAVY
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE if transparent else Control.MOUSE_FILTER_STOP
	_screen_root.add_child(background)


func _centered_layout(width: float) -> VBoxContainer:
	var panel := _panel(Vector2(width, 0.0))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-width * 0.5, -350.0)
	panel.size = Vector2(width, 700.0)
	_screen_root.add_child(panel)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	return layout


func _panel(minimum_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.add_theme_stylebox_override("panel", _style_box(NAVY_PANEL, 14, 22, MINT_DARK))
	return panel


func _style_box(color: Color, radius: int, margin: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	if border.a > 0.0:
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = border
	return style


func _title(key: String, size: int, color: Color) -> Label:
	return _label(key, size, color, HORIZONTAL_ALIGNMENT_CENTER)


func _label(key_or_text: String, size := 18, color := TEXT, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = tr(key_or_text)
	label.add_theme_font_size_override("font_size", maxi(18, size))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	return label


func _button(key_or_text: String, callback: Callable, secondary := false, danger := false) -> Button:
	var button := Button.new()
	button.text = tr(key_or_text)
	button.custom_minimum_size.y = 48.0
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", DANGER if danger else TEXT)
	var normal_color := NAVY if secondary else NAVY_RAISED
	button.add_theme_stylebox_override("normal", _style_box(normal_color, 9, 12, MINT_DARK))
	button.add_theme_stylebox_override("hover", _style_box(MINT_DARK, 9, 12, MINT))
	button.add_theme_stylebox_override("pressed", _style_box(Color("285f59"), 9, 12, MINT))
	button.add_theme_stylebox_override("disabled", _style_box(Color("182532"), 9, 12))
	button.pressed.connect(callback)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


func _section(title_key: String, content: String) -> PanelContainer:
	var panel := _panel(Vector2(0.0, 112.0))
	var box := VBoxContainer.new()
	box.add_child(_label(title_key, 17, BRASS))
	var body := _label(content, 18, TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	panel.add_child(box)
	return panel


func _owned_line(owned: bool, item_key: String) -> String:
	return "%s  %s" % [tr("COLLECTION_OWNED") if owned else tr("COLLECTION_LOCKED"), tr(item_key)]


func _style_progress(progress: ProgressBar) -> void:
	progress.add_theme_stylebox_override("background", _style_box(Color("1b2d3b"), 6, 0))
	progress.add_theme_stylebox_override("fill", _style_box(MINT, 6, 0))


func _update_profile_cards() -> void:
	for index in _profile_buttons.size():
		var summary: Dictionary = _profile_at(index)
		var state := tr("PROFILE_EMPTY")
		if bool(summary.get("ok", false)):
			var scene_key := "SCENE_%s" % String(summary.get("scene_id", "forest")).to_upper()
			state = tr("PROFILE_PROGRESS") % [tr(scene_key), int(summary.get("artifact_collected", false)), int(summary.get("crystal_collected", false))]
			if bool(summary.get("recovered", false)):
				state += "\n" + tr("PROFILE_RECOVERED")
		elif bool(summary.get("exists", false)):
			state = tr("PROFILE_UNAVAILABLE")
		var marker := "◆ " if index == _selected_profile else ""
		_profile_buttons[index].text = "%s%s %d\n%s" % [marker, tr("PROFILE_TITLE"), index + 1, state]


func _profile_at(index: int) -> Dictionary:
	if index >= 0 and index < _profiles.size() and typeof(_profiles[index]) == TYPE_DICTIONARY:
		return _profiles[index]
	return {}


func _update_continue_button() -> void:
	if is_instance_valid(_continue_button):
		_continue_button.disabled = not bool(_profile_at(_selected_profile).get("ok", false))


func _on_profile_selected(index: int) -> void:
	_selected_profile = index
	_update_profile_cards()
	_update_continue_button()
	command.emit("select_profile", index)


func _on_continue_pressed() -> void:
	command.emit("continue", _selected_profile)


func _on_new_game_pressed() -> void:
	command.emit("new_game", _selected_profile)


func _emit_command(action: String, value: Variant) -> void:
	command.emit(action, value)


func _add_slider_setting(grid: GridContainer, label_key: String, key: String, minimum: float, maximum: float, step: float, value: float) -> void:
	grid.add_child(_label(label_key, 17, TEXT))
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(340.0, 34.0)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = clampf(value, minimum, maximum)
	slider.value_changed.connect(_on_setting_changed.bind(key))
	grid.add_child(slider)


func _add_toggle_setting(grid: GridContainer, label_key: String, key: String, value: bool) -> void:
	grid.add_child(_label(label_key, 17, TEXT))
	var toggle := CheckButton.new()
	toggle.text = tr("COMMON_ON") if value else tr("COMMON_OFF")
	toggle.button_pressed = value
	toggle.toggled.connect(_on_toggle_changed.bind(key, toggle))
	grid.add_child(toggle)


func _add_option_setting(grid: GridContainer, label_key: String, key: String, values: Array, labels: Array, current: String) -> void:
	grid.add_child(_label(label_key, 17, TEXT))
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(340.0, 42.0)
	for label_key_item: String in labels:
		option.add_item(tr(label_key_item))
	var selected := values.find(current)
	option.select(maxi(0, selected))
	option.item_selected.connect(_on_option_selected.bind(key, values))
	grid.add_child(option)


func _on_setting_changed(value: float, key: String) -> void:
	_cached_settings[key] = value
	command.emit("setting", {"key": key, "value": value})


func _on_toggle_changed(value: bool, key: String, toggle: CheckButton) -> void:
	_cached_settings[key] = value
	toggle.text = tr("COMMON_ON") if value else tr("COMMON_OFF")
	command.emit("setting", {"key": key, "value": value})


func _on_option_selected(index: int, key: String, values: Array) -> void:
	if index < 0 or index >= values.size():
		return
	var value: Variant = values[index]
	_cached_settings[key] = value
	command.emit("setting", {"key": key, "value": value})


func _settings_with_defaults(settings: Dictionary) -> Dictionary:
	var defaults := {
		"fov": 65.0,
		"sensitivity": 0.003,
		"invert_y": false,
		"interaction_hold": false,
		"layout": "wasd",
		"locale": "en",
		"master": 0.8,
		"music": 0.45,
		"effects": 0.75,
		"fullscreen": false,
		"quality": "high",
	}
	for key: String in defaults:
		if settings.has(key) and typeof(settings[key]) == typeof(defaults[key]):
			defaults[key] = settings[key]
	return defaults


func _apply_cached_hud() -> void:
	if _cached_hud.is_empty() or not is_instance_valid(_hud_health):
		return
	var session: GameSession = _cached_hud.session
	_hud_health.value = clampf(session.health, 0.0, GameSession.MAX_HEALTH)
	# In this slice each completed authored dimension grants one key crystal;
	# the station hub is a destination, not an additional depth level.
	var completed_dimensions := int(session.crystal_collected)
	_hud_counts.text = tr("HUD_COUNTS") % [int(session.crystal_collected), int(session.artifact_collected), completed_dimensions]
	_hud_objective.text = _cached_hud.objective
	_hud_prompt.text = _cached_hud.prompt
	var ability_state := tr("ABILITY_READY")
	if not session.artifact_collected:
		ability_state = tr("ABILITY_LOCKED")
	elif _cached_hud.cooldown > 0.0:
		ability_state = tr("ABILITY_COOLDOWN") % _cached_hud.cooldown
	_hud_ability.text = "[1] %s · %s\n[2] %s  [3] %s  [4] %s" % [tr("ABILITY_PHASE"), ability_state, tr("ABILITY_LOCKED"), tr("ABILITY_LOCKED"), tr("ABILITY_LOCKED")]


func _hint_text_key(level: int) -> String:
	match clampi(level, 0, 3):
		1:
			return "PUZZLE_HINT_1"
		2:
			return "PUZZLE_HINT_2"
		3:
			return "PUZZLE_HINT_3"
	return "PUZZLE_HINT_WAIT"


func _refresh_current_screen() -> void:
	match current_screen:
		"main":
			show_main(_profiles)
		"pause":
			show_pause()
		"hud":
			show_hud()
		"collection":
			if is_instance_valid(_cached_session):
				show_collection(_cached_session)
		"settings":
			show_settings(_cached_settings)
		"puzzle":
			show_puzzle(_cached_puzzle.orientations, _cached_puzzle.hint_available, _cached_puzzle.hint_level)


func _hide_toast(serial: int) -> void:
	if serial == _toast_serial and is_instance_valid(_toast_label):
		_toast_label.visible = false
