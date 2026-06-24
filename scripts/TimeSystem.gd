extends Node

signal time_changed(total_seconds: float)

const CLOCK_JUMP_TOLERANCE_SECONDS: float = 0.5

var total_seconds: float = 0.0

var _last_ticks_msec: int = 0
var _last_system_seconds: float = 0.0
var _initialized: bool = false


func _ready() -> void:
	_rebase_clock_samples()
	_initialized = true


func _process(_delta: float) -> void:
	var current_ticks_msec := Time.get_ticks_msec()
	var current_system_seconds := Time.get_unix_time_from_system()
	var monotonic_delta := maxf(
		float(current_ticks_msec - _last_ticks_msec) / 1000.0,
		0.0
	)
	var system_delta := current_system_seconds - _last_system_seconds

	_last_ticks_msec = current_ticks_msec
	_last_system_seconds = current_system_seconds

	var elapsed_seconds := monotonic_delta
	if system_delta > monotonic_delta + CLOCK_JUMP_TOLERANCE_SECONDS:
		elapsed_seconds = system_delta

	if elapsed_seconds > 0.0:
		total_seconds += elapsed_seconds
		time_changed.emit(total_seconds)


func _notification(what: int) -> void:
	if not _initialized:
		return

	if what == NOTIFICATION_UNPAUSED:
		_rebase_clock_samples()


func get_total_seconds() -> float:
	return total_seconds


func _rebase_clock_samples() -> void:
	_last_ticks_msec = Time.get_ticks_msec()
	_last_system_seconds = Time.get_unix_time_from_system()
