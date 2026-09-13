## Playwright event bridge for exposing Godot runtime events to browser tests.
##
## Provides event emission to window.godotEvents and an element position map
## for coordinate-free UI testing via set_meta("playwright", "element_key").
class_name PlaywrightServiceModule
extends Node

const ElementMapService = preload("element_map_service.gd")
const PlaywrightTagNode = preload("playwright_tag_node.gd")

const META_KEY := "playwright"
const DIAGNOSTICS_EXPORT_FEATURE := "gd_playwright_diagnostics"

## Explicit production diagnostics allowlist. Empty collections deny every
## game-specific element, event, and state payload in diagnostic release builds.
class PlaywrightPayloadPolicy extends RefCounted:
	const SENSITIVE_KEYS := [
		"access_token", "api_key", "authorization", "cookie", "password",
		"private_key", "refresh_token", "secret", "session", "token"
	]
	var element_keys: PackedStringArray = PackedStringArray()
	var element_prefixes: PackedStringArray = PackedStringArray()
	var event_fields: Dictionary = {}
	var state_fields: Dictionary = {}
	var validation_visit_count: int = 0

	func _init(
		allowed_element_keys: PackedStringArray = PackedStringArray(),
		allowed_element_prefixes: PackedStringArray = PackedStringArray(),
		allowed_event_fields: Dictionary = {},
		allowed_state_fields: Dictionary = {}
	) -> void:
		element_keys = allowed_element_keys.duplicate()
		element_prefixes = allowed_element_prefixes.duplicate()
		event_fields = allowed_event_fields.duplicate(true)
		state_fields = allowed_state_fields.duplicate(true)

	func allows_element(key: String) -> bool:
		if key in element_keys:
			return true
		for prefix: String in element_prefixes:
			if not prefix.is_empty() and key.begins_with(prefix):
				return true
		return false

	func allows_event(event_name: String, payload: Dictionary) -> bool:
		return _allows_dictionary(event_fields, event_name, payload)

	func allows_state(state_namespace: String, state: Dictionary) -> bool:
		return _allows_dictionary(state_fields, state_namespace, state)

	func _allows_dictionary(rules: Dictionary, rule_name: String, payload: Dictionary) -> bool:
		if not rules.has(rule_name):
			return false
		var allowed_fields: PackedStringArray = _as_string_array(rules[rule_name])
		for key: Variant in payload:
			if not (key is String) or str(key) not in allowed_fields:
				return false
		return _is_safe_json_payload(payload)

	## Validates JSON compatibility and sensitive keys in one iterative walk.
	## Active-container tracking rejects cycles without imposing a depth limit on
	## finite JSON payloads.
	func _is_safe_json_payload(root: Variant) -> bool:
		validation_visit_count = 0
		var stack: Array[Dictionary] = [{"value": root, "leaving": false}]
		var active_containers: Array[Variant] = []
		while not stack.is_empty():
			var frame: Dictionary = stack.pop_back()
			if bool(frame["leaving"]):
				active_containers.pop_back()
				continue
			var value: Variant = frame["value"]
			validation_visit_count += 1
			if value == null or value is bool or value is String or value is int:
				continue
			if value is float:
				if not is_finite(value):
					return false
				continue
			if not (value is Array or value is Dictionary):
				return false
			for active: Variant in active_containers:
				if is_same(value, active):
					return false
			active_containers.append(value)
			stack.append({"value": null, "leaving": true})
			if value is Dictionary:
				for key: Variant in value:
					if not (key is String) or str(key).to_snake_case().to_lower() in SENSITIVE_KEYS:
						return false
					stack.append({"value": value[key], "leaving": false})
			else:
				for item: Variant in value:
					stack.append({"value": item, "leaving": false})
		return true

	func _as_string_array(value: Variant) -> PackedStringArray:
		if value is PackedStringArray:
			return value
		var result := PackedStringArray()
		if value is Array:
			for item: Variant in value:
				if item is String:
					result.append(item)
		return result

## Runtime configuration for browser event emission behavior.
class PlaywrightConfig extends RefCounted:
	var enabled: bool = false
	var test_mode: bool = false
	var log_events: bool = true
	var buffer_max: int = 1000
	var buffer_trim: int = 500
	var payload_policy: PlaywrightPayloadPolicy = null

	func _init(
		enabled: bool = false,
		test_mode: bool = false,
		log_events: bool = true,
		buffer_max: int = 1000,
		buffer_trim: int = 500,
		payload_policy: PlaywrightPayloadPolicy = null
	) -> void:
		self.enabled = enabled
		self.test_mode = test_mode
		self.log_events = log_events
		self.buffer_max = buffer_max
		self.buffer_trim = buffer_trim
		self.payload_policy = payload_policy

## Cached bridge interfaces used by one service owner. Dynamic data is parsed
## as JSON, while the publication path itself does not compile JavaScript.
class BrowserReceiver extends RefCounted:
	var _window: JavaScriptObject
	var _json: JavaScriptObject
	var _console: JavaScriptObject
	var _owner: String

	func _init(owner: String) -> void:
		_owner = owner
		_window = JavaScriptBridge.get_interface("window")
		_json = JavaScriptBridge.get_interface("JSON")
		_console = JavaScriptBridge.get_interface("console")

	func claim(owner: String) -> void:
		_window["__gdPlaywrightOwner"] = owner

	func set_state(state_namespace: String, payload_json: String) -> void:
		_restore_owner()
		if _window["godotTestState"] == null:
			_window["godotTestState"] = JavaScriptBridge.create_object("Object")
		_window["godotTestState"][state_namespace] = _json.parse(payload_json)

	func clear_state(state_namespace: String) -> void:
		_restore_owner()
		if _window["godotTestState"] != null:
			JavaScriptBridge.get_interface("Reflect").deleteProperty(_window["godotTestState"], state_namespace)

	func emit_event(event_json: String, log_event: bool, buffer_max: int, buffer_trim: int) -> void:
		_restore_owner()
		var event_data: JavaScriptObject = _json.parse(event_json)
		if log_event:
			_console.log("[GD_PLAYWRIGHT_EVENT]", event_data)
		if buffer_max > 0 and buffer_trim > 0 and _window["godotEvents"] != null and int(_window["godotEvents"].length) >= buffer_max:
			_window["godotEvents"] = _window["godotEvents"].slice(-buffer_trim)
		if _window["godotEvents"] == null:
			_window["godotEvents"] = JavaScriptBridge.create_object("Array")
		_window["godotEvents"].push(event_data)
		_dispatch("godot-event", event_data)

	func publish_elements(payload_json: String) -> void:
		_restore_owner()
		var payload: JavaScriptObject = _json.parse(payload_json)
		_window["godotElements"] = payload.elements
		var viewport: JavaScriptObject = JavaScriptBridge.create_object("Object")
		viewport.width = payload.viewport_width
		viewport.height = payload.viewport_height
		_window["godotElementsViewport"] = viewport
		_dispatch("godot-elements-updated", payload)

	func _dispatch(event_name: String, detail: JavaScriptObject) -> void:
		var options: JavaScriptObject = JavaScriptBridge.create_object("Object")
		options.detail = detail
		_window.dispatchEvent(JavaScriptBridge.create_object("CustomEvent", event_name, options))

	func _restore_owner() -> void:
		_window["__gdPlaywrightOwner"] = _owner

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
var _browser_owner_id: String = ""
var _browser_receiver: Variant = null

func configure(config: PlaywrightConfig) -> void:
	_config = config if config else _config_from_project_settings()
	if not _is_web_runtime():
		return
	if _should_emit_events():
		_claim_browser_bridge()
	else:
		_cleanup_browser_bridge()

func get_config() -> PlaywrightConfig:
	return _config

func _ready() -> void:
	if not _is_web_runtime():
		return
	if not _is_test_mode_enabled():
		return
	_on_test_mode_ready()

func _on_test_mode_ready() -> void:
	_claim_browser_bridge()
	_element_map = ElementMapService.new()
	_element_map.setup(self)
	emit_event("service_ready")

## Returns the element map service for tag registration.
## Returns null when the service is disabled (not in test/debug mode).
func get_element_map() -> ElementMapService:
	if not _should_emit_events():
		return null
	if _element_map == null:
		_element_map = ElementMapService.new()
		_element_map.setup(self)
	return _element_map

## Registers an element position directly without requiring a PlaywrightTag node.
## Use this for runtime-created or non-Node2D/Control test targets.
func register_element(key: String, center: Vector2, element_size: Vector2, visible: bool = true) -> void:
	if not _allows_element_key(key.strip_edges()):
		return
	var element_map_service: ElementMapService = get_element_map()
	if element_map_service == null:
		return
	element_map_service.register(key.strip_edges(), center, element_size, visible)

## Removes a directly registered or tagged element key from the element map.
func unregister_element(key: String) -> void:
	var element_map_service: ElementMapService = get_element_map()
	if element_map_service == null:
		return
	element_map_service.unregister(key.strip_edges())

## Clears all registered element positions.
func clear_elements() -> void:
	var element_map_service: ElementMapService = get_element_map()
	if element_map_service == null:
		return
	element_map_service.clear()

## Alias for set_test_state() with shorter naming for game-facing services.
func set_state(state_namespace_name: String, state: Dictionary) -> void:
	set_test_state(state_namespace_name, state)

## Alias for clear_test_state() with shorter naming for game-facing services.
func clear_state(state_namespace_name: String) -> void:
	clear_test_state(state_namespace_name)

## Emits an event with an optional namespace prefix, e.g. "combat.turn_started".
func emit_namespaced_event(event_namespace: String, event_name: String, payload: Dictionary = {}) -> void:
	var namespace_name: String = event_namespace.strip_edges()
	var resolved_event_name: String = event_name.strip_edges()
	if resolved_event_name.is_empty():
		return
	if not namespace_name.is_empty():
		resolved_event_name = "%s.%s" % [namespace_name, resolved_event_name]
	emit_event(resolved_event_name, payload)

## Sets arbitrary test state on window.godotTestState[namespace] for CLI consumption.
## Call this from game code whenever test-observable state changes.
## The data is game-specific; gd-playwright only ferries it to the browser.
## No-op when the service is disabled.
func set_test_state(state_namespace_name: String, state: Dictionary) -> void:
	if not _should_emit_events():
		return
	var state_namespace: String = state_namespace_name.strip_edges()
	if state_namespace.is_empty():
		return
	if _requires_payload_policy() and not _resolve_payload_policy().allows_state(state_namespace, state):
		return
	_claim_browser_bridge()
	_get_browser_receiver().set_state(state_namespace, JSON.stringify(state))

## Clears one window.godotTestState namespace.
## No-op when the service is disabled.
func clear_test_state(state_namespace_name: String) -> void:
	if not _should_emit_events():
		return
	var state_namespace: String = state_namespace_name.strip_edges()
	if state_namespace.is_empty():
		return
	_claim_browser_bridge()
	_get_browser_receiver().clear_state(state_namespace)

## Called by ElementMapService via deferred call when the map is dirty.
## No-op when the service is disabled.
func _on_element_map_flush_requested() -> void:
	if not _should_emit_events():
		return
	if _element_map != null:
		_claim_browser_bridge()
		_element_map.flush_to_browser()

## Scans the current scene tree for nodes with set_meta("playwright", "key")
## and registers them in the element map. No-op when the service is disabled.
func scan_scene(clear_existing: bool = false) -> void:
	if not _should_emit_events():
		return
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
					child.set_element_map(element_map_service)
					child.refresh_registration()
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
	if _requires_payload_policy() and not _resolve_payload_policy().allows_event(event_name, data):
		return

	var event_data := {
		"event": event_name,
		"timestamp": Time.get_ticks_msec(),
		"data": data
	}

	var config: PlaywrightConfig = _resolve_config()
	var buffer_max: int = maxi(config.buffer_max, 0)
	var buffer_trim: int = maxi(config.buffer_trim, 0)
	_claim_browser_bridge()
	_get_browser_receiver().emit_event(JSON.stringify(event_data), config.log_events, buffer_max, buffer_trim)

func _should_emit_events() -> bool:
	if not _is_web_runtime():
		return false
	var config: PlaywrightConfig = _resolve_config()
	if _is_debug_runtime():
		return true
	if not _has_diagnostics_export_feature():
		return false
	return _is_test_mode_enabled() or config.enabled

func _exit_tree() -> void:
	_cleanup_browser_bridge()

func _claim_browser_bridge() -> void:
	if not _is_web_runtime():
		return
	if _browser_owner_id.is_empty():
		_browser_receiver = null
		_browser_owner_id = "%s:%s" % [str(get_instance_id()), str(Time.get_ticks_usec())]
		_get_browser_receiver().claim(_browser_owner_id)

func _cleanup_browser_bridge() -> void:
	if not _is_web_runtime() or _browser_owner_id.is_empty():
		return
	var owner_json := JSON.stringify(_browser_owner_id)
	_browser_eval("""
		if (window.__gdPlaywrightOwner === %s) {
			var __waiters = window.__gdPlaywrightEventWaiters;
			if (__waiters instanceof Map) {
				for (var __waiter of __waiters.values()) {
					if (__waiter && typeof __waiter.cancel === 'function') { __waiter.cancel(); }
				}
			}
			delete window.__gdPlaywrightEventWaiters;
			delete window.godotElements;
			delete window.godotElementsViewport;
			delete window.godotEvents;
			delete window.godotTestState;
			delete window.__gdPlaywrightOwner;
			window.dispatchEvent(new CustomEvent('gd-playwright-cleanup', { detail: { owner: %s } }));
		}
	""" % [owner_json, owner_json])
	_browser_owner_id = ""
	_browser_receiver = null

func _publish_element_map(payload_json: String) -> void:
	_get_browser_receiver().publish_elements(payload_json)

func _get_browser_receiver() -> Variant:
	if _browser_receiver == null:
		_browser_receiver = _create_browser_receiver()
	return _browser_receiver

func _create_browser_receiver() -> Variant:
	return BrowserReceiver.new(_browser_owner_id)

func _browser_eval(code: String) -> Variant:
	return JavaScriptBridge.eval(code)

func _is_web_runtime() -> bool:
	return OS.has_feature("web")

func _is_debug_runtime() -> bool:
	return OS.is_debug_build()

func _has_diagnostics_export_feature() -> bool:
	return OS.has_feature(DIAGNOSTICS_EXPORT_FEATURE)

func _requires_payload_policy() -> bool:
	return _is_web_runtime() and not _is_debug_runtime() and _has_diagnostics_export_feature()

func _resolve_payload_policy() -> PlaywrightPayloadPolicy:
	var config := _resolve_config()
	if config.payload_policy == null:
		config.payload_policy = PlaywrightPayloadPolicy.new()
	return config.payload_policy

func _allows_element_key(key: String) -> bool:
	return not _requires_payload_policy() or _resolve_payload_policy().allows_element(key)

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
