class_name GameResultOverlay
extends CanvasLayer

var _background: ColorRect
var _message_label: Label
var _reload_requested: bool = false
var _clear_rules_on_reload: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_background.gui_input.connect(_on_background_gui_input)
	add_child(_background)

	_message_label = Label.new()
	_message_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_font_size_override("font_size", 56)
	_message_label.add_theme_color_override("font_color", Color.WHITE)
	_message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_message_label.add_theme_constant_override("shadow_offset_x", 3)
	_message_label.add_theme_constant_override("shadow_offset_y", 3)
	_background.add_child(_message_label)


func show_result(message: String, background_color: Color, clear_rules_on_reload: bool = false) -> void:
	_clear_rules_on_reload = clear_rules_on_reload
	_background.color = background_color
	_message_label.text = "%s\n\n点击任意位置重新开始" % message


func _on_background_gui_input(event: InputEvent) -> void:
	if _reload_requested:
		return

	var is_pressed: bool = false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		is_pressed = mouse_event.pressed
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		is_pressed = touch_event.pressed
	else:
		return

	if not is_pressed:
		return

	_reload_requested = true
	get_viewport().set_input_as_handled()
	if _clear_rules_on_reload:
		RuleSystem.clear_rules_and_restart()
	else:
		get_tree().paused = false
		get_tree().call_deferred("reload_current_scene")
