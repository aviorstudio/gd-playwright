extends SceneTree

const PlaywrightServiceModule = preload("res://addon/src/playwright_service.gd")

class FakePlaywrightService extends PlaywrightServiceModule:
	var captured_event_name: String = ""
	var captured_payload: Dictionary = {}
	var call_count: int = 0

	func emit_event_to_browser(event_name: String, data: Dictionary = {}) -> void:
		captured_event_name = event_name
		captured_payload = data.duplicate(true)
		call_count += 1

func _initialize() -> void:
	var failures: Array[String] = []
	_test_emit_event_delegates_to_browser_emitter(failures)
	_test_emit_namespaced_event_delegates_to_browser_emitter(failures)
	_test_configure_retains_buffer_and_flag_settings(failures)
	_test_meta_key_constant(failures)

	if failures.is_empty():
		print("PASS gd-playwright playwright_service_test")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)

func _test_emit_event_delegates_to_browser_emitter(failures: Array[String]) -> void:
	var service := FakePlaywrightService.new()
	service.emit_event("one", {"id": 1})
	service.emit_event("two", {"id": 2})

	if service.call_count != 2:
		failures.append("Expected emit_event to delegate to browser emitter twice")
	if service.captured_event_name != "two":
		failures.append("Expected latest delegated event name to match second call")
	if int(service.captured_payload.get("id", 0)) != 2:
		failures.append("Expected latest delegated payload to match second call")
	service.free()

func _test_emit_namespaced_event_delegates_to_browser_emitter(failures: Array[String]) -> void:
	var service := FakePlaywrightService.new()
	service.emit_namespaced_event("combat", "turn_started", {"turn": 1})

	if service.call_count != 1:
		failures.append("Expected emit_namespaced_event to emit once")
	if service.captured_event_name != "combat.turn_started":
		failures.append("Expected namespaced event combat.turn_started, got '%s'" % service.captured_event_name)
	if int(service.captured_payload.get("turn", 0)) != 1:
		failures.append("Expected namespaced event payload to be retained")
	service.free()

func _test_configure_retains_buffer_and_flag_settings(failures: Array[String]) -> void:
	var service := PlaywrightServiceModule.new()
	var config := PlaywrightServiceModule.PlaywrightConfig.new(true, true, false, 42, 17)
	service.configure(config)
	var effective: PlaywrightServiceModule.PlaywrightConfig = service.get_config()

	if not effective.enabled or not effective.test_mode:
		failures.append("Expected configure to retain enabled and test_mode flags")
	if effective.log_events:
		failures.append("Expected configure to retain log_events=false")
	if effective.buffer_max != 42:
		failures.append("Expected configure to retain buffer_max setting")
	if effective.buffer_trim != 17:
		failures.append("Expected configure to retain buffer_trim setting")
	service.free()

func _test_meta_key_constant(failures: Array[String]) -> void:
	if PlaywrightServiceModule.META_KEY != "playwright":
		failures.append("Expected META_KEY to be 'playwright', got '%s'" % PlaywrightServiceModule.META_KEY)
