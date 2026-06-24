extends Node

signal rules_changed

const RULE_BRIDGE_PLAYER: StringName = &"bridge_player"
const RULE_BRIDGE_OBJECT: StringName = &"bridge_object"
const RULE_BRIDGE_SIDE: StringName = &"bridge_side"

const RESULT_CLEAR: StringName = &"clear"
const RESULT_FAILURE: StringName = &"failure"

const RULE_TEXTS := {
	RULE_BRIDGE_PLAYER: "玩家不能踩在桥上",
	RULE_BRIDGE_OBJECT: "桥上不能放任何东西",
	RULE_BRIDGE_SIDE: "桥的侧面不能接触任何东西（水体除外）",
}

const DEFAULT_CLEAR_TEXT := "游戏成功"
const DEFAULT_FAILURE_TEXT := "游戏失败"
const FINAL_WIN_TEXT := "我不知道该如何阻止你了，你赢了"

var _added_rules: Array[StringName] = []
var _triggered_this_round: Array[StringName] = []
var _round_finished: bool = false
var _last_scene_id: int = 0
var _rule_book: RuleBookOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_rule_book()


func _process(_delta: float) -> void:
	_track_scene_reload()
	_ensure_rule_book()


func report_rule_trigger(rule_id: StringName) -> void:
	if _round_finished or not RULE_TEXTS.has(rule_id):
		return

	if _added_rules.has(rule_id):
		_start_rule_violation(rule_id)
		return

	_triggered_this_round.append(rule_id)


func handle_result(result_kind: StringName, result_text: String, background_color: Color) -> void:
	if _round_finished:
		return

	_round_finished = true
	if result_kind == RESULT_CLEAR:
		_handle_clear(result_text, background_color)
	else:
		_show_result_overlay(_fallback_text(result_text, DEFAULT_FAILURE_TEXT), background_color)


func get_added_rule_ids() -> Array[StringName]:
	return _added_rules.duplicate()


func get_rule_text(rule_id: StringName) -> String:
	return RULE_TEXTS.get(rule_id, "")


func clear_rules_and_restart() -> void:
	_added_rules.clear()
	_triggered_this_round.clear()
	rules_changed.emit()
	_restart_current_scene()


func restart_after_violation() -> void:
	_restart_current_scene()


func _handle_clear(result_text: String, background_color: Color) -> void:
	if _triggered_this_round.is_empty():
		_show_final_win_overlay()
		return

	var last_rule: StringName = _triggered_this_round.back()
	if not _added_rules.has(last_rule):
		_added_rules.append(last_rule)
		rules_changed.emit()
	_show_result_overlay(_fallback_text(result_text, DEFAULT_CLEAR_TEXT), background_color)


func _start_rule_violation(rule_id: StringName) -> void:
	_round_finished = true
	get_tree().paused = true
	_ensure_rule_book()
	if _rule_book:
		_rule_book.show_violation(rule_id)


func _show_result_overlay(message: String, background_color: Color) -> void:
	var scene_tree := get_tree()
	var overlay_parent: Node = scene_tree.current_scene if scene_tree.current_scene else scene_tree.root
	if overlay_parent.get_node_or_null(NodePath(GameResultZone.OVERLAY_NAME)) != null:
		return

	var overlay := GameResultOverlay.new()
	overlay.name = GameResultZone.OVERLAY_NAME
	overlay_parent.add_child(overlay)
	overlay.show_result(message, background_color)
	scene_tree.paused = true


func _show_final_win_overlay() -> void:
	var scene_tree := get_tree()
	var overlay_parent: Node = scene_tree.current_scene if scene_tree.current_scene else scene_tree.root
	if overlay_parent.get_node_or_null(NodePath(GameResultZone.OVERLAY_NAME)) != null:
		return

	var overlay := GameResultOverlay.new()
	overlay.name = GameResultZone.OVERLAY_NAME
	overlay_parent.add_child(overlay)
	overlay.show_result(FINAL_WIN_TEXT, Color(0.08, 0.08, 0.12, 0.96), true)
	scene_tree.paused = true


func _restart_current_scene() -> void:
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


func _track_scene_reload() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var scene_id := current_scene.get_instance_id()
	if scene_id == _last_scene_id:
		return

	_last_scene_id = scene_id
	_triggered_this_round.clear()
	_round_finished = false
	if _rule_book:
		_rule_book.clear_violation()


func _ensure_rule_book() -> void:
	if is_instance_valid(_rule_book):
		return

	_rule_book = RuleBookOverlay.new()
	_rule_book.name = "RuleBookOverlay"
	add_child(_rule_book)
	rules_changed.emit()


func _fallback_text(text: String, fallback: String) -> String:
	return fallback if text.strip_edges().is_empty() else text
