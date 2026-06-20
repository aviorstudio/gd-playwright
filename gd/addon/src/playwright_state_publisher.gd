@tool
## Publishes namespaced test state to window.godotTestState through PlaywrightService.
class_name PlaywrightStatePublisher
extends Node

@export var state_namespace: String = "":
	set(value):
		state_namespace = value.strip_edges()
		update_configuration_warnings()
@export var publish_on_ready: bool = true
@export var clear_on_exit: bool = false
@export var state: Dictionary = {}
@export var service_path: NodePath = NodePath("/root/PlaywrightService")

func _ready() -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	if publish_on_ready:
		publish()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if clear_on_exit:
		clear()

func publish(extra_state: Dictionary = {}) -> void:
	var service: Node = _get_playwright_service()
	var namespace_name: String = state_namespace.strip_edges()
	if service == null or namespace_name.is_empty():
		return
	var payload: Dictionary = state.duplicate(true)
	for key: Variant in extra_state:
		payload[key] = extra_state[key]
	service.call("set_test_state", namespace_name, payload)

func set_value(key: String, value: Variant, publish_now: bool = true) -> void:
	if key.strip_edges().is_empty():
		return
	state[key] = value
	if publish_now:
		publish()

func erase_value(key: String, publish_now: bool = true) -> void:
	if not state.has(key):
		return
	state.erase(key)
	if publish_now:
		publish()

func clear() -> void:
	var service: Node = _get_playwright_service()
	var namespace_name: String = state_namespace.strip_edges()
	if service == null or namespace_name.is_empty():
		return
	service.call("clear_test_state", namespace_name)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if state_namespace.strip_edges().is_empty():
		warnings.append("Set state_namespace so tests can read this state from window.godotTestState.")
	return warnings

func _get_playwright_service() -> Node:
	if not is_inside_tree():
		return null
	var service: Node = get_node_or_null(service_path)
	if service == null and get_tree() != null and get_tree().root != null:
		service = get_tree().root.get_node_or_null("PlaywrightService")
	if service == null:
		return null
	if not service.has_method("set_test_state") or not service.has_method("clear_test_state"):
		return null
	return service
