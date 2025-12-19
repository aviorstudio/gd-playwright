extends Node

const SETTINGS_PREFIX := "gd_playwright/"

const SETTING_ENABLED := SETTINGS_PREFIX + "enabled"
const SETTING_TEST_MODE := SETTINGS_PREFIX + "test_mode"
const SETTING_LOG_EVENTS := SETTINGS_PREFIX + "log_events"
const SETTING_EVENT_BUFFER_MAX := SETTINGS_PREFIX + "event_buffer_max"
const SETTING_EVENT_BUFFER_TRIM := SETTINGS_PREFIX + "event_buffer_trim"

const DEFAULT_LOG_EVENTS := true
const DEFAULT_EVENT_BUFFER_MAX := 1000
const DEFAULT_EVENT_BUFFER_TRIM := 500

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	if not _is_test_mode_enabled():
		return
	_on_test_mode_ready()

func _on_test_mode_ready() -> void:
	emit_event("service_ready")

func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	emit_event_to_browser(event_name, payload)

func emit_event_to_browser(event_name: String, data: Dictionary = {}) -> void:
	if not _should_emit_events():
		return

	var event_data := {
		"event": event_name,
		"timestamp": Time.get_ticks_msec(),
		"data": data
	}

	var json_string := JSON.stringify(event_data)

	var log_events: bool = bool(ProjectSettings.get_setting(SETTING_LOG_EVENTS, DEFAULT_LOG_EVENTS))
	if log_events:
		JavaScriptBridge.eval("console.log('[GD_PLAYWRIGHT_EVENT]', " + json_string + ")")

	var buffer_max: int = int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_MAX, DEFAULT_EVENT_BUFFER_MAX))
	var buffer_trim: int = int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_TRIM, DEFAULT_EVENT_BUFFER_TRIM))

	var js_code := ""
	if buffer_max > 0 and buffer_trim > 0:
		js_code += """
			if (window.godotEvents && window.godotEvents.length >= %d) {
				window.godotEvents = window.godotEvents.slice(-%d);
			}
		""" % [buffer_max, buffer_trim]

	js_code += """
		if (!window.godotEvents) {
			window.godotEvents = [];
		}
		window.godotEvents.push(%s);
		window.dispatchEvent(new CustomEvent('godot-event', { detail: %s }));
	""" % [json_string, json_string]
	JavaScriptBridge.eval(js_code)

func _should_emit_events() -> bool:
	if not OS.has_feature("web"):
		return false

	if _is_test_mode_enabled():
		return true

	var enabled_setting: bool = bool(ProjectSettings.get_setting(SETTING_ENABLED, false))
	if enabled_setting:
		return true

	return OS.is_debug_build()

func _is_test_mode_enabled() -> bool:
	return bool(ProjectSettings.get_setting(SETTING_TEST_MODE, false))

func _get_autoload(name: String) -> Node:
	return get_node_or_null("/root/" + name)
