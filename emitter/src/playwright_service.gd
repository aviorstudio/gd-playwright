class_name PlaywrightServiceModule
extends Node

class PlaywrightConfig extends RefCounted:
	var enabled: bool = false
	var test_mode: bool = false
	var log_events: bool = true
	var buffer_max: int = 1000
	var buffer_trim: int = 500

	func _init(
		enabled: bool = false,
		test_mode: bool = false,
		log_events: bool = true,
		buffer_max: int = 1000,
		buffer_trim: int = 500
	) -> void:
		self.enabled = enabled
		self.test_mode = test_mode
		self.log_events = log_events
		self.buffer_max = buffer_max
		self.buffer_trim = buffer_trim

const SETTINGS_PREFIX := "gd_playwright/"

const SETTING_ENABLED := SETTINGS_PREFIX + "enabled"
const SETTING_TEST_MODE := SETTINGS_PREFIX + "test_mode"
const SETTING_LOG_EVENTS := SETTINGS_PREFIX + "log_events"
const SETTING_EVENT_BUFFER_MAX := SETTINGS_PREFIX + "event_buffer_max"
const SETTING_EVENT_BUFFER_TRIM := SETTINGS_PREFIX + "event_buffer_trim"

const DEFAULT_LOG_EVENTS := true
const DEFAULT_EVENT_BUFFER_MAX := 1000
const DEFAULT_EVENT_BUFFER_TRIM := 500

var _config: PlaywrightConfig = null

func configure(config: PlaywrightConfig) -> void:
	_config = config if config else _config_from_project_settings()

func get_config() -> PlaywrightConfig:
	return _config

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

func emit_custom_event(name: String, data: Dictionary = {}) -> void:
	emit_event(name, data)

func emit_event_to_browser(event_name: String, data: Dictionary = {}) -> void:
	if not _should_emit_events():
		return

	var event_data := {
		"event": event_name,
		"timestamp": Time.get_ticks_msec(),
		"data": data
	}

	var json_string := JSON.stringify(event_data)

	var config: PlaywrightConfig = _resolve_config()
	if config.log_events:
		JavaScriptBridge.eval("console.log('[GD_PLAYWRIGHT_EVENT]', " + json_string + ")")

	var buffer_max: int = maxi(config.buffer_max, 0)
	var buffer_trim: int = maxi(config.buffer_trim, 0)

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
	var config: PlaywrightConfig = _resolve_config()

	if _is_test_mode_enabled():
		return true

	if config.enabled:
		return true

	return OS.is_debug_build()

func _is_test_mode_enabled() -> bool:
	var config: PlaywrightConfig = _resolve_config()
	return config.test_mode

func _get_autoload(name: String) -> Node:
	return get_node_or_null("/root/" + name)

func _resolve_config() -> PlaywrightConfig:
	if _config == null:
		_config = _config_from_project_settings()
	return _config

func _config_from_project_settings() -> PlaywrightConfig:
	return PlaywrightConfig.new(
		bool(ProjectSettings.get_setting(SETTING_ENABLED, false)),
		bool(ProjectSettings.get_setting(SETTING_TEST_MODE, false)),
		bool(ProjectSettings.get_setting(SETTING_LOG_EVENTS, DEFAULT_LOG_EVENTS)),
		int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_MAX, DEFAULT_EVENT_BUFFER_MAX)),
		int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_TRIM, DEFAULT_EVENT_BUFFER_TRIM))
	)
