@tool
## Emits named test events to window.godotEvents through PlaywrightService.
class_name PlaywrightEventEmitter
extends Node

@export var event_name: String = "":
	set(value):
		event_name = value.strip_edges()
		update_configuration_warnings()
@export var emit_on_ready: bool = false
@export var payload: Dictionary = {}
@export var service_path: NodePath = NodePath("/root/PlaywrightService")

func _ready() -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	if emit_on_ready:
		emit_playwright_event()

func emit_playwright_event(extra_payload: Dictionary = {}) -> void:
	var service: Node = _get_playwright_service()
	var resolved_event_name: String = event_name.strip_edges()
	if service == null or resolved_event_name.is_empty():
		return
	var event_payload: Dictionary = payload.duplicate(true)
	for key: Variant in extra_payload:
		event_payload[key] = extra_payload[key]
	service.call("emit_event", resolved_event_name, event_payload)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if event_name.strip_edges().is_empty():
		warnings.append("Set event_name so tests can wait for this event.")
	return warnings

func _get_playwright_service() -> Node:
	if not is_inside_tree():
		return null
	var service: Node = get_node_or_null(service_path)
	if service == null and get_tree() != null and get_tree().root != null:
		service = get_tree().root.get_node_or_null("PlaywrightService")
	if service == null or not service.has_method("emit_event"):
		return null
	return service
