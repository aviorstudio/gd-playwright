## Playwright event bridge for exposing Godot runtime events to browser tests.
class_name PlaywrightServiceModule
extends Node

## Runtime configuration for browser event emission behavior.
class PlaywrightConfig extends RefCounted:
	## Enables event emission in non-test mode.
	var enabled: bool = false
	## Forces test-mode behavior and startup signal emission.
	var test_mode: bool = false
	## Enables debug console logging for emitted events.
	var log_events: bool = true
	## Console log prefix used when `log_events` is enabled.
	var log_prefix: String = "[GD_PLAYWRIGHT_EVENT]"
	## Maximum buffered events retained in `window.godotEvents`.
	var buffer_max: int = 1000
	## Number of most-recent events retained when trimming buffer.
	var buffer_trim: int = 500

	func _init(
		enabled: bool = false,
		test_mode: bool = false,
		log_events: bool = true,
		log_prefix: String = "[GD_PLAYWRIGHT_EVENT]",
		buffer_max: int = 1000,
		buffer_trim: int = 500
	) -> void:
		self.enabled = enabled
		self.test_mode = test_mode
		self.log_events = log_events
		self.log_prefix = log_prefix
		self.buffer_max = buffer_max
		self.buffer_trim = buffer_trim

const SETTINGS_PREFIX := "gd_playwright/"

const SETTING_ENABLED := SETTINGS_PREFIX + "enabled"
const SETTING_TEST_MODE := SETTINGS_PREFIX + "test_mode"
const SETTING_LOG_EVENTS := SETTINGS_PREFIX + "log_events"
const SETTING_LOG_PREFIX := SETTINGS_PREFIX + "log_prefix"
const SETTING_EVENT_BUFFER_MAX := SETTINGS_PREFIX + "event_buffer_max"
const SETTING_EVENT_BUFFER_TRIM := SETTINGS_PREFIX + "event_buffer_trim"

const DEFAULT_LOG_EVENTS := true
const DEFAULT_LOG_PREFIX := "[GD_PLAYWRIGHT_EVENT]"
const DEFAULT_EVENT_BUFFER_MAX := 1000
const DEFAULT_EVENT_BUFFER_TRIM := 500

var _config: PlaywrightConfig = null

## Applies explicit runtime configuration.
##
## When `config` is null, falls back to project settings.
func configure(config: PlaywrightConfig) -> void:
	_config = config if config else _config_from_project_settings()

## Returns the effective runtime configuration.
func get_config() -> PlaywrightConfig:
	return _resolve_config()

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	if not _is_test_mode_enabled():
		return
	_on_test_mode_ready()

func _on_test_mode_ready() -> void:
	emit_event("service_ready")

## Emits a standard named event.
func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	emit_event_to_browser(event_name, payload)

## Emits a custom event alias.
func emit_custom_event(name: String, data: Dictionary = {}) -> void:
	emit_event(name, data)

## Emits an event payload to browser JavaScript runtime.
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
		JavaScriptBridge.eval("console.log(" + JSON.stringify(config.log_prefix) + ", " + json_string + ")")

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
		str(ProjectSettings.get_setting(SETTING_LOG_PREFIX, DEFAULT_LOG_PREFIX)),
		int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_MAX, DEFAULT_EVENT_BUFFER_MAX)),
		int(ProjectSettings.get_setting(SETTING_EVENT_BUFFER_TRIM, DEFAULT_EVENT_BUFFER_TRIM))
	)
