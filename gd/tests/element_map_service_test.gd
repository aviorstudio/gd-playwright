extends SceneTree

const ElementMapService = preload("res://addon/src/element_map_service.gd")
const PlaywrightServiceModule = preload("res://addon/src/playwright_service.gd")

class EnabledPlaywrightService extends PlaywrightServiceModule:
	func _should_emit_events() -> bool:
		return true

class RecordingElementMapService extends ElementMapService:
	var payloads: Array[String] = []

	func _is_web_runtime() -> bool:
		return true

	func _publish_payload_json(json_string: String) -> void:
		payloads.append(json_string)

class WireCacheMutationService extends RecordingElementMapService:
	func _can_reuse_wire_view(_wire_view: Dictionary, _entry: ElementEntry) -> bool:
		return false

func _initialize() -> void:
	var failures: Array[String] = []
	_test_register_and_lookup(failures)
	_test_update_position_skips_unchanged(failures)
	_test_unregister_removes_entry(failures)
	_test_clear_removes_all(failures)
	_test_empty_key_rejected(failures)
	_test_get_all_keys(failures)
	_test_service_register_element_api(failures)
	_test_cached_wire_views_preserve_public_mutation_semantics(failures)

	if failures.is_empty():
		print("PASS gd-playwright element_map_service_test")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)

func _test_register_and_lookup(failures: Array[String]) -> void:
	var service := ElementMapService.new()
	service.register("home/battle_button", Vector2(100, 200), Vector2(80, 40), true)

	if not service.has_element("home/battle_button"):
		failures.append("Expected registered element to be found")
		return

	var entry: ElementMapService.ElementEntry = service.get_entry("home/battle_button")
	if entry == null:
		failures.append("Expected get_entry to return non-null for registered key")
		return

	if entry.center_x != 100:
		failures.append("Expected center_x=100, got %d" % entry.center_x)
	if entry.center_y != 200:
		failures.append("Expected center_y=200, got %d" % entry.center_y)
	if entry.width != 80:
		failures.append("Expected width=80, got %d" % entry.width)
	if entry.height != 40:
		failures.append("Expected height=40, got %d" % entry.height)
	if not entry.visible:
		failures.append("Expected visible=true")
	if service.get_element_count() != 1:
		failures.append("Expected element count=1")
	if not service.is_dirty():
		failures.append("Expected service to be dirty after register")

func _test_update_position_skips_unchanged(failures: Array[String]) -> void:
	var service := ElementMapService.new()
	service.register("btn", Vector2(50, 60), Vector2(20, 10), true)

	# Flush to clear dirty
	service._dirty = false

	# Same position — should not mark dirty
	service.update_position("btn", Vector2(50, 60), Vector2(20, 10), true)
	if service.is_dirty():
		failures.append("Expected service to NOT be dirty when position unchanged")

	# Different position — should mark dirty
	service.update_position("btn", Vector2(51, 60), Vector2(20, 10), true)
	if not service.is_dirty():
		failures.append("Expected service to be dirty when position changed")

	var entry: ElementMapService.ElementEntry = service.get_entry("btn")
	if entry.center_x != 51:
		failures.append("Expected updated center_x=51, got %d" % entry.center_x)

func _test_unregister_removes_entry(failures: Array[String]) -> void:
	var service := ElementMapService.new()
	service.register("a", Vector2(1, 2), Vector2(3, 4), true)
	service.register("b", Vector2(5, 6), Vector2(7, 8), false)

	service.unregister("a")
	if service.has_element("a"):
		failures.append("Expected 'a' to be removed after unregister")
	if not service.has_element("b"):
		failures.append("Expected 'b' to still exist after unregistering 'a'")
	if service.get_element_count() != 1:
		failures.append("Expected element count=1 after unregister")

	# Unregistering non-existent key should not error
	service.unregister("nonexistent")

func _test_clear_removes_all(failures: Array[String]) -> void:
	var service := ElementMapService.new()
	service.register("x", Vector2(1, 2), Vector2(3, 4), true)
	service.register("y", Vector2(5, 6), Vector2(7, 8), true)
	service.clear()

	if service.get_element_count() != 0:
		failures.append("Expected element count=0 after clear")
	if not service.is_dirty():
		failures.append("Expected clear to mark the browser element map dirty")

func _test_empty_key_rejected(failures: Array[String]) -> void:
	var service := ElementMapService.new()
	service.register("", Vector2(1, 2), Vector2(3, 4), true)

	if service.get_element_count() != 0:
		failures.append("Expected empty key to be rejected")

func _test_get_all_keys(failures: Array[String]) -> void:
	var service := ElementMapService.new()
	service.register("alpha", Vector2(1, 2), Vector2(3, 4), true)
	service.register("beta", Vector2(5, 6), Vector2(7, 8), true)

	var keys: Array[String] = service.get_all_keys()
	if keys.size() != 2:
		failures.append("Expected 2 keys, got %d" % keys.size())
		return

	if not ("alpha" in keys):
		failures.append("Expected 'alpha' in keys")
	if not ("beta" in keys):
		failures.append("Expected 'beta' in keys")

	# Test to_dict on entry
	var entry: ElementMapService.ElementEntry = service.get_entry("alpha")
	var dict: Dictionary[String, Variant] = entry.to_dict()
	if int(dict.get("x", 0)) != 1:
		failures.append("Expected to_dict x=1")
	if int(dict.get("y", 0)) != 2:
		failures.append("Expected to_dict y=2")
	if int(dict.get("w", 0)) != 3:
		failures.append("Expected to_dict w=3")
	if int(dict.get("h", 0)) != 4:
		failures.append("Expected to_dict h=4")
	if not bool(dict.get("visible", false)):
		failures.append("Expected to_dict visible=true")

func _test_service_register_element_api(failures: Array[String]) -> void:
	var service := EnabledPlaywrightService.new()
	service.register_element("direct_button", Vector2(12, 34), Vector2(56, 78), true)
	var element_map = service.get_element_map()
	if element_map == null or not element_map.has_element("direct_button"):
		failures.append("Expected register_element to write to the element map")
	else:
		var entry: ElementMapService.ElementEntry = element_map.get_entry("direct_button")
		if entry.width != 56 or entry.height != 78:
			failures.append("Expected register_element to retain size")
	service.unregister_element("direct_button")
	if element_map != null and element_map.has_element("direct_button"):
		failures.append("Expected unregister_element to remove key")
	service.register_element("another_button", Vector2.ZERO, Vector2.ONE, true)
	service.clear_elements()
	if element_map != null and element_map.get_element_count() != 0:
		failures.append("Expected clear_elements to remove all keys")
	service.free()

func _test_cached_wire_views_preserve_public_mutation_semantics(failures: Array[String]) -> void:
	var service := RecordingElementMapService.new()
	service.register("outer", Vector2(1, 2), Vector2(3, 4), true)
	var original: ElementMapService.ElementEntry = service.get_entry("outer")
	var first_copy := original.to_dict()
	service.flush_to_browser()
	var first_json := service.payloads[-1]
	var first_wire: Dictionary = service._wire_views["outer"]
	service.flush_to_browser()
	if not is_same(service._wire_views["outer"], first_wire) or service._wire_materialization_count != 1:
		failures.append("Expected unchanged entry to reuse its internal wire view")
	var cache_mutation := WireCacheMutationService.new()
	cache_mutation.register("outer", Vector2(1, 2), Vector2(3, 4), true)
	cache_mutation.flush_to_browser()
	cache_mutation.flush_to_browser()
	if cache_mutation._wire_materialization_count <= service._wire_materialization_count:
		failures.append("Expected disabling wire-view reuse to fail the materialization work invariant")
	original.center_x = 9
	original.key = "inner-does-not-replace-outer"
	service.flush_to_browser()
	var mutated_payload: Dictionary = JSON.parse_string(service.payloads[-1])
	if int(mutated_payload["elements"]["outer"]["x"]) != 9 or mutated_payload["elements"].has(original.key):
		failures.append("Expected direct entry mutation on the existing outer map key in the next explicit flush")
	if int(first_copy["x"]) != 1 or first_json != service.payloads[0]:
		failures.append("Expected fresh to_dict copies and retained published JSON snapshots to remain independent")
	var replacement := ElementMapService.ElementEntry.new("different-inner", 11, 12, 13, 14, false)
	service.get_all_entries()["outer"] = replacement
	service.flush_to_browser()
	var replacement_payload: Dictionary = JSON.parse_string(service.payloads[-1])
	if int(replacement_payload["elements"]["outer"]["x"]) != 11 or bool(replacement_payload["elements"]["outer"]["visible"]):
		failures.append("Expected direct replacement to refresh the outer-key wire view")
	service.get_all_entries().erase("outer")
	service.flush_to_browser()
	var removed_payload: Dictionary = JSON.parse_string(service.payloads[-1])
	if removed_payload["elements"].has("outer") or service._wire_views.has("outer") or service._wire_entries.has("outer"):
		failures.append("Expected direct removal to publish and evict bounded internal cache state")
