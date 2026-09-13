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

class RecordingWebService extends PlaywrightServiceModule:
	var scripts: Array[String] = []

	func _is_web_runtime() -> bool:
		return true

	func _is_debug_runtime() -> bool:
		return false

	func _has_diagnostics_export_feature() -> bool:
		return true

	func _browser_eval(code: String) -> Variant:
		scripts.append(code)
		return null

class OrdinaryWebService extends RecordingWebService:
	func _has_diagnostics_export_feature() -> bool:
		return false

func _initialize() -> void:
	var failures: Array[String] = []
	_test_emit_event_delegates_to_browser_emitter(failures)
	_test_emit_namespaced_event_delegates_to_browser_emitter(failures)
	_test_configure_retains_buffer_and_flag_settings(failures)
	_test_meta_key_constant(failures)
	_test_cleanup_is_owner_guarded_and_complete(failures)
	_test_stale_instance_cleanup_cannot_claim_another_owner(failures)
	_test_production_payload_policy_is_default_deny(failures)
	_test_production_payload_policy_allows_only_declared_safe_fields(failures)
	_test_ordinary_release_cannot_enable_bridge_by_setting(failures)

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

func _test_cleanup_is_owner_guarded_and_complete(failures: Array[String]) -> void:
	var service := RecordingWebService.new()
	service.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, false, false))
	var owner_id := service._browser_owner_id
	service._cleanup_browser_bridge()
	if service.scripts.size() != 2:
		failures.append("Expected one bridge claim and one cleanup script")
		service.free()
		return
	var cleanup := service.scripts[1]
	if not cleanup.contains("window.__gdPlaywrightOwner ===") or not cleanup.contains(owner_id):
		failures.append("Expected cleanup to require the current service owner identity")
	for global_name: String in ["godotElements", "godotElementsViewport", "godotEvents", "godotTestState", "__gdPlaywrightEventWaiters"]:
		if not cleanup.contains("delete window." + global_name):
			failures.append("Expected cleanup to remove owned global " + global_name)
	if not cleanup.contains("__waiter.cancel()"):
		failures.append("Expected cleanup to cancel helper listeners before deleting their registry")
	if not service._browser_owner_id.is_empty():
		failures.append("Expected local browser owner identity to clear after cleanup")
	service.free()

func _test_stale_instance_cleanup_cannot_claim_another_owner(failures: Array[String]) -> void:
	var first := RecordingWebService.new()
	var second := RecordingWebService.new()
	first.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, false, false))
	second.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, false, false))
	var first_owner := first._browser_owner_id
	var second_owner := second._browser_owner_id
	if first_owner == second_owner:
		failures.append("Expected independent service instances to use unique browser owners")
	first._cleanup_browser_bridge()
	var stale_cleanup := first.scripts[-1]
	if not stale_cleanup.contains(first_owner) or stale_cleanup.contains(second_owner):
		failures.append("Expected stale cleanup to be scoped only to the stale owner")
	second._cleanup_browser_bridge()
	first.free()
	second.free()

func _test_production_payload_policy_is_default_deny(failures: Array[String]) -> void:
	var service := RecordingWebService.new()
	service.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, false, false))
	var claim_count := service.scripts.size()
	service.emit_event("route_loaded", {"route": "game"})
	service.set_test_state("game", {"route": "game"})
	service.register_element("play_button", Vector2.ZERO, Vector2.ONE)
	if service.scripts.size() != claim_count:
		failures.append("Expected diagnostic release payloads to default deny without a policy")
	if service.get_element_map().get_element_count() != 0:
		failures.append("Expected diagnostic release element keys to default deny")
	service._cleanup_browser_bridge()
	service.free()

func _test_production_payload_policy_allows_only_declared_safe_fields(failures: Array[String]) -> void:
	var policy := PlaywrightServiceModule.PlaywrightPayloadPolicy.new(
		PackedStringArray(["play_button"]),
		PackedStringArray(["enemy_"]),
		{"route_loaded": PackedStringArray(["route"])},
		{"game": PackedStringArray(["route", "units"])}
	)
	var service := RecordingWebService.new()
	service.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, false, false, 1000, 500, policy))
	service.emit_event("route_loaded", {"route": "game"})
	var after_allowed_event := service.scripts.size()
	service.emit_event("route_loaded", {"route": "game", "token": "must-not-publish"})
	if service.scripts.size() != after_allowed_event:
		failures.append("Expected sensitive event payload to be rejected before browser publication")
	service.set_test_state("game", {"route": "game", "units": [{"id": 1}]})
	var after_allowed_state := service.scripts.size()
	service.set_test_state("game", {"route": "game", "units": [{"session": "must-not-publish"}]})
	if service.scripts.size() != after_allowed_state:
		failures.append("Expected nested sensitive state key to be rejected before publication")
	service.register_element("play_button", Vector2.ZERO, Vector2.ONE)
	service.register_element("enemy_7", Vector2.ZERO, Vector2.ONE)
	service.register_element("private_admin", Vector2.ZERO, Vector2.ONE)
	if service.get_element_map().get_element_count() != 2:
		failures.append("Expected only exact/prefix allowlisted element keys")
	service._cleanup_browser_bridge()
	service.free()

func _test_ordinary_release_cannot_enable_bridge_by_setting(failures: Array[String]) -> void:
	var service := OrdinaryWebService.new()
	service.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, true, false))
	service.emit_event("route_loaded", {"route": "game"})
	if not service.scripts.is_empty():
		failures.append("Expected ordinary release artifact to ignore enabled/test_mode settings")
	service.free()
