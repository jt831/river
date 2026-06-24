class_name RuleBookOverlay
extends CanvasLayer

const PANEL_WIDTH := 360.0
const PANEL_HEIGHT := 420.0
const EXPOSED_WIDTH := 34.0
const TOP_OFFSET := 92.0

var _panel: PanelContainer
var _title_label: Label
var _list: VBoxContainer
var _hint_label: Label
var _expanded: bool = false
var _violated_rule: StringName = &""
var _reload_on_click: bool = false
var _tween: Tween


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not RuleSystem.rules_changed.is_connected(_refresh_rules):
		RuleSystem.rules_changed.connect(_refresh_rules)
	_build_ui()
	_refresh_rules()
	_set_expanded(false, true)


func show_violation(rule_id: StringName) -> void:
	_violated_rule = rule_id
	_reload_on_click = true
	_refresh_rules()
	_set_expanded(true)


func clear_violation() -> void:
	_violated_rule = &""
	_reload_on_click = false
	_refresh_rules()
	_set_expanded(false, true)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.offset_top = TOP_OFFSET
	_panel.offset_bottom = TOP_OFFSET + PANEL_HEIGHT
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_gui_input)
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.86, 0.68, 0.96)
	style.border_color = Color(0.38, 0.25, 0.12, 1.0)
	style.set_border_width_all(3)
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	_title_label = Label.new()
	_title_label.text = "规则书"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.2, 0.12, 0.05, 1.0))
	layout.add_child(_title_label)

	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	layout.add_child(_list)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(0.28, 0.17, 0.08, 0.9))
	layout.add_child(_hint_label)


func _refresh_rules() -> void:
	if not is_instance_valid(_list):
		return

	for child in _list.get_children():
		child.queue_free()

	var rule_ids := RuleSystem.get_added_rule_ids()
	if rule_ids.is_empty():
		var empty_label := _make_rule_label("暂无规则")
		empty_label.add_theme_color_override("font_color", Color(0.38, 0.29, 0.18, 0.75))
		_list.add_child(empty_label)
	else:
		for index in range(rule_ids.size()):
			var rule_id := rule_ids[index]
			var text := "%d. %s" % [index + 1, RuleSystem.get_rule_text(rule_id)]
			var label := _make_rule_label(text)
			if rule_id == _violated_rule:
				label.add_theme_color_override("font_color", Color(0.9, 0.05, 0.04, 1.0))
			_list.add_child(label)

	_hint_label.text = "点击规则书重新开始" if _reload_on_click else "点击规则书收起或展开"


func _make_rule_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.18, 0.1, 0.04, 1.0))
	return label


func _on_panel_gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		pressed = mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed

	if not pressed:
		return

	get_viewport().set_input_as_handled()
	if _reload_on_click:
		RuleSystem.restart_after_violation()
	else:
		_set_expanded(not _expanded)


func _set_expanded(expanded: bool, immediate: bool = false) -> void:
	_expanded = expanded
	var target_x := 0.0 if _expanded else -PANEL_WIDTH + EXPOSED_WIDTH
	if immediate:
		_panel.offset_left = target_x
		_panel.offset_right = target_x + PANEL_WIDTH
		return

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_panel, "offset_left", target_x, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_panel, "offset_right", target_x + PANEL_WIDTH, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
