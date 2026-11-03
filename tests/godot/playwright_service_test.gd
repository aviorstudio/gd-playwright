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
	class RecordingReceiver extends RefCounted:
		var operations: Array[Dictionary] = []

		func claim(owner: String) -> void:
			operations.append({"kind": "claim", "owner": owner})

		func set_state(state_namespace: String, payload_json: String) -> void:
			operations.append({"kind": "state", "namespace": state_namespace, "payload": payload_json})

		func clear_state(state_namespace: String) -> void:
			operations.append({"kind": "clear_state", "namespace": state_namespace})

		func emit_event(event_json: String, log_event: bool, buffer_max: int, buffer_trim: int) -> void:
			operations.append({"kind": "event", "payload": event_json, "log": log_event, "max": buffer_max, "trim": buffer_trim})

		func publish_elements(payload_json: String) -> void:
			operations.append({"kind": "elements", "payload": payload_json})

	var scripts: Array[String] = []
	var receivers: Array[RecordingReceiver] = []

	func _is_web_runtime() -> bool:
		return true

	func _is_debug_runtime() -> bool:
		return false

	func _has_diagnostics_export_feature() -> bool:
		return true

	func _browser_eval(code: String) -> Variant:
		scripts.append(code)
		return null

	func _create_browser_receiver() -> Variant:
		var receiver := RecordingReceiver.new()
		receivers.append(receiver)
		return receiver

	func operation_count() -> int:
		var count := 0
		for receiver: RecordingReceiver in receivers:
			count += receiver.operations.size()
		return count

class OrdinaryWebService extends RecordingWebService:
	func _has_diagnostics_export_feature() -> bool:
		return false

class PrimitiveFrameMutationPolicy extends PlaywrightServiceModule.PlaywrightPayloadPolicy:
	func _uses_primitive_leaf_fast_path() -> bool:
		return false

class KeyCacheMutationPolicy extends PlaywrightServiceModule.PlaywrightPayloadPolicy:
	func _uses_key_classification_cache() -> bool:
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
	_test_payload_policy_differential_corpus_and_single_traversal(failures)
	_test_payload_policy_work_controls(failures)
	_test_browser_receiver_is_cached_per_owner(failures)
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
	if service.operation_count() != 1 or service.scripts.size() != 1:
		failures.append("Expected one cached-receiver claim and one cleanup script")
		service.free()
		return
	var cleanup := service.scripts[0]
	if not cleanup.contains("window.__gdPlaywrightOwner ===") or not cleanup.contains(owner_id):
		failures.append("Expected cleanup to require the current service owner identity")
	if not service._browser_owner_id.is_empty():
		failures.append("Expected local browser owner identity to clear after cleanup")
	if service._browser_receiver != null:
		failures.append("Expected cleanup to invalidate the cached browser receiver")
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
	var claim_count := service.operation_count()
	service.emit_event("route_loaded", {"route": "game"})
	service.set_test_state("game", {"route": "game"})
	service.register_element("play_button", Vector2.ZERO, Vector2.ONE)
	if service.operation_count() != claim_count:
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
	var after_allowed_event := service.operation_count()
	service.emit_event("route_loaded", {"route": "game", "token": "must-not-publish"})
	if service.operation_count() != after_allowed_event:
		failures.append("Expected sensitive event payload to be rejected before browser publication")
	service.set_test_state("game", {"route": "game", "units": [{"id": 1}]})
	var after_allowed_state := service.operation_count()
	service.set_test_state("game", {"route": "game", "units": [{"session": "must-not-publish"}]})
	if service.operation_count() != after_allowed_state:
		failures.append("Expected nested sensitive state key to be rejected before publication")
	service.register_element("play_button", Vector2.ZERO, Vector2.ONE)
	service.register_element("enemy_7", Vector2.ZERO, Vector2.ONE)
	service.register_element("private_admin", Vector2.ZERO, Vector2.ONE)
	if service.get_element_map().get_element_count() != 2:
		failures.append("Expected only exact/prefix allowlisted element keys")
	service._cleanup_browser_bridge()
	service.free()

func _test_payload_policy_differential_corpus_and_single_traversal(failures: Array[String]) -> void:
	var policy := PlaywrightServiceModule.PlaywrightPayloadPolicy.new(
		PackedStringArray(), PackedStringArray(), {},
		{"game": PackedStringArray(["route", "units", "value"])}
	)
	var unsupported := Node.new()
	var deep: Variant = "leaf"
	for _index in range(128):
		deep = [deep]
	var shared_container := {"id": 7, "stats": {"hp": 9}}
	var corpus: Array[Dictionary] = [
		{"name": "valid", "payload": {"route": "battle", "units": [{"id": 1, "stats": {"hp": 7}}]}, "allowed": true},
		{"name": "shared-container-dag", "payload": {"units": [shared_container, shared_container]}, "allowed": true},
		{"name": "deep-valid", "payload": {"value": deep}, "allowed": true},
		{"name": "nested-secret", "payload": {"units": [{"profile": {"refreshToken": "reject"}}]}, "allowed": false},
		{"name": "non-string-key", "payload": {"units": [{1: "reject"}]}, "allowed": false},
		{"name": "nan", "payload": {"value": NAN}, "allowed": false},
		{"name": "infinity", "payload": {"value": INF}, "allowed": false},
		{"name": "unsupported-object", "payload": {"value": unsupported}, "allowed": false},
	]
	for sample: Dictionary in corpus:
		var actual := policy.allows_state("game", sample["payload"])
		var legacy_visits_for_sample: Array[int] = [0]
		var legacy := _legacy_allows_dictionary(
			sample["payload"], PackedStringArray(["route", "units", "value"]), legacy_visits_for_sample
		)
		if actual != legacy:
			failures.append("Old/new payload decision differs for %s" % sample["name"])
		if actual != bool(sample["allowed"]):
			failures.append("Differential payload result changed for %s" % sample["name"])
	var cyclic: Dictionary = {"route": "cycle"}
	cyclic["units"] = [cyclic]
	if policy.allows_state("game", cyclic):
		failures.append("Expected cyclic payload to be rejected")
	if policy.validation_visit_count > 4:
		failures.append("Expected cycle rejection to remain bounded")
	var legacy_visits: Array[int] = [0]
	var nested_valid := {"units": [{"stats": {"hp": 7, "armor": 2}}]}
	var legacy_allowed := _legacy_contains_no_sensitive_key(nested_valid, legacy_visits) and _legacy_is_json_safe(nested_valid["units"], legacy_visits)
	var optimized_allowed := policy.allows_state("game", nested_valid)
	if legacy_allowed != optimized_allowed:
		failures.append("Expected old and new validators to agree on nested valid JSON")
	if policy.validation_visit_count >= int(legacy_visits[0]):
		failures.append("Expected merged validator visit count below duplicate legacy traversals")
	unsupported.free()

func _test_payload_policy_work_controls(failures: Array[String]) -> void:
	var allowed := {"game": PackedStringArray(["units"])}
	var payload := {"units": [{"unitId": 1, "stats": {"unitId": 2}}, {"unitId": 3}]}
	var policy := PlaywrightServiceModule.PlaywrightPayloadPolicy.new(PackedStringArray(), PackedStringArray(), {}, allowed)
	var primitive_mutation := PrimitiveFrameMutationPolicy.new(PackedStringArray(), PackedStringArray(), {}, allowed)
	var cache_mutation := KeyCacheMutationPolicy.new(PackedStringArray(), PackedStringArray(), {}, allowed)
	if not policy.allows_state("game", payload) or not primitive_mutation.allows_state("game", payload) or not cache_mutation.allows_state("game", payload):
		failures.append("Expected work-control policies to retain the accepted payload decision")
	if policy.validation_visit_count != primitive_mutation.validation_visit_count:
		failures.append("Expected primitive fast path to retain public completed-call visit count")
	if policy._validation_value_frame_count >= primitive_mutation._validation_value_frame_count:
		failures.append("Expected disabling primitive fast path to fail the value-frame work invariant")
	if policy._validation_key_normalization_count >= cache_mutation._validation_key_normalization_count:
		failures.append("Expected disabling publication-local key cache to fail the normalization work invariant")
	var sensitive := {"units": [{"refreshToken": "reject"}]}
	if policy.allows_state("game", sensitive):
		failures.append("Expected normalized sensitive key to remain rejected")
	if policy.validation_visit_count != 3:
		failures.append("Expected early rejection to publish one completed-call visit count")

func _legacy_allows_dictionary(payload: Dictionary, allowed_fields: PackedStringArray, visits: Array[int]) -> bool:
	if not _legacy_contains_no_sensitive_key(payload, visits):
		return false
	for key: Variant in payload:
		if str(key) not in allowed_fields or not _legacy_is_json_safe(payload[key], visits):
			return false
	return true

func _legacy_contains_no_sensitive_key(value: Variant, visits: Array[int]) -> bool:
	visits[0] += 1
	if value is Dictionary:
		for key: Variant in value:
			if str(key).to_snake_case().to_lower() in PlaywrightServiceModule.PlaywrightPayloadPolicy.SENSITIVE_KEYS:
				return false
			if not _legacy_contains_no_sensitive_key(value[key], visits):
				return false
	elif value is Array:
		for item: Variant in value:
			if not _legacy_contains_no_sensitive_key(item, visits):
				return false
	return true

func _legacy_is_json_safe(value: Variant, visits: Array[int]) -> bool:
	visits[0] += 1
	if value == null or value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item: Variant in value:
			if not _legacy_is_json_safe(item, visits):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String) or not _legacy_is_json_safe(value[key], visits):
				return false
		return true
	return false

func _test_browser_receiver_is_cached_per_owner(failures: Array[String]) -> void:
	var service := RecordingWebService.new()
	var policy := PlaywrightServiceModule.PlaywrightPayloadPolicy.new(
		PackedStringArray(), PackedStringArray(),
		{"route_loaded": PackedStringArray(["route"])},
		{"game": PackedStringArray(["route"])}
	)
	var config := PlaywrightServiceModule.PlaywrightConfig.new(true, false, true, 100, 50, policy)
	service.configure(config)
	service.emit_event("route_loaded", {"route": "one"})
	service.set_test_state("game", {"route": "one"})
	if service.receivers.size() != 1:
		failures.append("Expected one fixed receiver compilation for one owner")
	if service.operation_count() != 3:
		failures.append("Expected claim, synchronous event, and synchronous state backend calls")
	service._cleanup_browser_bridge()
	service.configure(config)
	if service.receivers.size() != 2:
		failures.append("Expected a new owner to invalidate and rebuild the receiver once")
	service._cleanup_browser_bridge()
	service.free()

func _test_ordinary_release_cannot_enable_bridge_by_setting(failures: Array[String]) -> void:
	var service := OrdinaryWebService.new()
	service.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, true, false))
	service.emit_event("route_loaded", {"route": "game"})
	if service.operation_count() != 0:
		failures.append("Expected ordinary release artifact to ignore enabled/test_mode settings")
	service.free()
