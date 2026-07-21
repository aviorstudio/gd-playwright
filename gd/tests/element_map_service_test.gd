extends SceneTree

const ElementMapService = preload("res://addon/src/element_map_service.gd")
const PlaywrightServiceModule = preload("res://addon/src/playwright_service.gd")

class EnabledPlaywrightService extends PlaywrightServiceModule:
	func _should_emit_events() -> bool:
		return true

func _initialize() -> void:
	var failures: Array[String] = []
	_test_register_and_lookup(failures)
	_test_update_position_skips_unchanged(failures)
	_test_unregister_removes_entry(failures)
	_test_clear_removes_all(failures)
	_test_empty_key_rejected(failures)
	_test_get_all_keys(failures)
	_test_service_register_element_api(failures)

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
