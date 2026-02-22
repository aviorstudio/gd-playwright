extends SceneTree

const PlaywrightServiceModule = preload("res://src/playwright_service.gd")

class FakePlaywrightService extends PlaywrightServiceModule:
	var captured_event_name: String = ""
	var captured_event_payload: Dictionary = {}
	var emit_count: int = 0

	func emit_event_to_browser(event_name: String, data: Dictionary = {}) -> void:
		captured_event_name = event_name
		captured_event_payload = data.duplicate(true)
		emit_count += 1

func _initialize() -> void:
	var failures: Array[String] = []
	_test_emit_custom_event_alias(failures)
	_test_configure_updates_flags(failures)

	if failures.is_empty():
		print("PASS gd-playwright emitter playwright_service_test")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)

func _test_emit_custom_event_alias(failures: Array[String]) -> void:
	var service := FakePlaywrightService.new()
	service.emit_custom_event("custom_test", {"ok": true})
	if service.emit_count != 1:
		failures.append("Expected emit_custom_event to delegate to emit_event")
	if service.captured_event_name != "custom_test":
		failures.append("Expected captured event name to match")
	if not bool(service.captured_event_payload.get("ok", false)):
		failures.append("Expected captured event payload to match")

func _test_configure_updates_flags(failures: Array[String]) -> void:
	var service := PlaywrightServiceModule.new()
	var config := PlaywrightServiceModule.PlaywrightConfig.new(true, true, false, 20, 10)
	service.configure(config)
	var effective: PlaywrightServiceModule.PlaywrightConfig = service.get_config()
	if not effective.enabled or not effective.test_mode:
		failures.append("Expected configured enabled/test_mode flags to be true")
	if effective.log_events:
		failures.append("Expected configured log_events to be false")
	if effective.buffer_max != 20 or effective.buffer_trim != 10:
		failures.append("Expected configured buffer settings to be retained")
