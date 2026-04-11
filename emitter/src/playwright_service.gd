## Playwright event bridge for exposing Godot runtime events to browser tests.
##
## Provides event emission to window.godotEvents and an element position map
## for coordinate-free UI testing via set_meta("playwright", "element_key").
class_name PlaywrightServiceModule
extends Node

const ElementMapService = preload("element_map_service.gd")
const PlaywrightTagNode = preload("playwright_tag_node.gd")

const META_KEY := "playwright"

## Runtime configuration for browser event emission behavior.
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
var _element_map: ElementMapService = null

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
	_element_map = ElementMapService.new()
	_element_map.setup(self)
	emit_event("service_ready")

## Returns the element map service for tag registration.
func get_element_map() -> ElementMapService:
	if _element_map == null:
		_element_map = ElementMapService.new()
		_element_map.setup(self)
	return _element_map

## Called by ElementMapService via deferred call when the map is dirty.
func _on_element_map_flush_requested() -> void:
	if _element_map != null:
		_element_map.flush_to_browser()

func scan_scene(clear_existing: bool = false) -> void:
	if clear_existing:
		call_deferred("_clear_and_scan_scene")
	else:
		call_deferred("_scan_and_tag_scene")

func _clear_and_scan_scene() -> void:
	var element_map_service: ElementMapService = get_element_map()
	if element_map_service != null:
		element_map_service.clear()
	_scan_and_tag_scene()

func _scan_and_tag_scene() -> void:
	var element_map_service: ElementMapService = get_element_map()
	if element_map_service == null:
		return
	var scene_tree: SceneTree = get_tree()
	if not scene_tree or not scene_tree.current_scene:
		return
	_scan_node_recursive(scene_tree.current_scene, element_map_service)
	call_deferred("_on_element_map_flush_requested")

func _scan_node_recursive(node: Node, element_map_service: ElementMapService) -> void:
	if node.has_meta(META_KEY):
		var tag_key: String = str(node.get_meta(META_KEY))
		if not tag_key.is_empty() and (node is Control or node is Node2D):
			var already_tagged: bool = false
			for child in node.get_children():
				if child is PlaywrightTagNode:
					already_tagged = true
					break
			if not already_tagged:
				var tag := PlaywrightTagNode.new()
				tag.tag_key = tag_key
				tag.set_element_map(element_map_service)
				node.add_child(tag)
	for child in node.get_children():
		_scan_node_recursive(child, element_map_service)

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
