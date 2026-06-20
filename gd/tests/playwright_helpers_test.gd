extends SceneTree

const ElementMapService = preload("res://addon/src/element_map_service.gd")
const PlaywrightEventEmitter = preload("res://addon/src/playwright_event_emitter.gd")
const PlaywrightStatePublisher = preload("res://addon/src/playwright_state_publisher.gd")
const PlaywrightTagNode = preload("res://addon/src/playwright_tag_node.gd")

class FakePlaywrightService extends Node:
	var events: Array[Dictionary] = []
	var states: Dictionary = {}
	var cleared_namespaces: Array[String] = []
	var element_map := ElementMapService.new()

	func _ready() -> void:
		element_map.setup(self)

	func emit_event(event_name: String, payload: Dictionary = {}) -> void:
		events.append({
			"event": event_name,
			"payload": payload.duplicate(true)
		})

	func set_test_state(state_namespace_name: String, state: Dictionary) -> void:
		states[state_namespace_name] = state.duplicate(true)

	func clear_test_state(state_namespace_name: String) -> void:
		cleared_namespaces.append(state_namespace_name)
		states.erase(state_namespace_name)

	func get_element_map() -> ElementMapService:
		return element_map

	func _on_element_map_flush_requested() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var failures: Array[String] = []
	_test_event_emitter_uses_autoload(failures)
	_test_event_emitter_uses_custom_service_path(failures)
	_test_state_publisher_uses_autoload(failures)
	_test_tag_node_uses_autoload_element_map(failures)
	_test_tag_node_warnings(failures)

	if failures.is_empty():
		print("PASS gd-playwright playwright_helpers_test")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)

func _test_event_emitter_uses_autoload(failures: Array[String]) -> void:
	var service := _add_fake_service()
	var emitter := PlaywrightEventEmitter.new()
	emitter.event_name = "route_loaded"
	emitter.payload = {"route": "home"}
	root.add_child(emitter)
	emitter.emit_playwright_event({"screen": "HomeScreen"})

	if service.events.size() != 1:
		failures.append("Expected event emitter to call PlaywrightService.emit_event once")
	else:
		var event: Dictionary = service.events[0]
		if str(event.get("event", "")) != "route_loaded":
			failures.append("Expected emitted event name route_loaded")
		var payload: Dictionary = event.get("payload", {})
		if str(payload.get("route", "")) != "home" or str(payload.get("screen", "")) != "HomeScreen":
			failures.append("Expected event payload to merge base and extra payload")

	emitter.free()
	_remove_fake_service(service)

func _test_event_emitter_uses_custom_service_path(failures: Array[String]) -> void:
	var service := _add_fake_service("GdPlaywrightService")
	var emitter := PlaywrightEventEmitter.new()
	emitter.event_name = "custom_service_event"
	emitter.service_path = NodePath("/root/GdPlaywrightService")
	root.add_child(emitter)
	emitter.emit_playwright_event()

	if service.events.size() != 1:
		failures.append("Expected event emitter to use custom service_path")

	emitter.free()
	_remove_fake_service(service)

func _test_state_publisher_uses_autoload(failures: Array[String]) -> void:
	var service := _add_fake_service()
	var publisher := PlaywrightStatePublisher.new()
	publisher.state_namespace = "game"
	publisher.state = {"level": "level_01"}
	root.add_child(publisher)
	publisher.publish({"solved": false})
	publisher.set_value("moves", 3)
	publisher.clear()

	if not ("game" in service.cleared_namespaces):
		failures.append("Expected state publisher to clear namespace through PlaywrightService")
	if service.states.has("game"):
		failures.append("Expected clear to remove game namespace from fake service")

	publisher.free()
	_remove_fake_service(service)

func _test_tag_node_uses_autoload_element_map(failures: Array[String]) -> void:
	var service := _add_fake_service()
	var button := Button.new()
	button.name = "PlayButton"
	button.position = Vector2(10, 20)
	button.size = Vector2(100, 40)
	var tag := PlaywrightTagNode.new()
	tag.tag_key = "play_button"
	button.add_child(tag)
	root.add_child(button)

	if not service.element_map.has_element("play_button"):
		failures.append("Expected editor-authored PlaywrightTag to register through PlaywrightService autoload")

	button.free()
	_remove_fake_service(service)

func _test_tag_node_warnings(failures: Array[String]) -> void:
	var unsupported_parent := Node.new()
	var tag := PlaywrightTagNode.new()
	unsupported_parent.add_child(tag)
	var warnings: PackedStringArray = tag._get_configuration_warnings()
	if warnings.is_empty():
		failures.append("Expected PlaywrightTag warnings when parent is unsupported and key is empty")
	unsupported_parent.free()

func _add_fake_service(service_name: String = "PlaywrightService") -> FakePlaywrightService:
	var existing: Node = root.get_node_or_null(service_name)
	if existing != null:
		existing.free()
	var service := FakePlaywrightService.new()
	service.name = service_name
	root.add_child(service)
	return service

func _remove_fake_service(service: FakePlaywrightService) -> void:
	if service != null and is_instance_valid(service):
		service.free()
