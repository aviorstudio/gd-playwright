extends SceneTree

const PlaywrightTagNode = preload("res://addon/src/playwright_tag_node.gd")
const ElementMapService = preload("res://addon/src/element_map_service.gd")

func _initialize() -> void:
	var failures: Array[String] = []
	_test_normalize_name_converts_pascal_to_snake(failures)
	_test_normalize_name_preserves_snake_case(failures)
	_test_tag_key_used_when_set(failures)
	_test_no_element_map_disables_processing(failures)
	_test_refresh_registration_restores_cleared_entry(failures)

	if failures.is_empty():
		print("PASS gd-playwright playwright_tag_node_test")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)

func _test_normalize_name_converts_pascal_to_snake(failures: Array[String]) -> void:
	var result: String = PlaywrightTagNode._normalize_name("BattleButton")
	if result != "battle_button":
		failures.append("Expected 'battle_button', got '%s'" % result)

	var result2: String = PlaywrightTagNode._normalize_name("PlayerStatBar")
	if result2 != "player_stat_bar":
		failures.append("Expected 'player_stat_bar', got '%s'" % result2)

	var result3: String = PlaywrightTagNode._normalize_name("VBoxContainer")
	if result3 != "vbox_container":
		failures.append("Expected 'vbox_container', got '%s'" % result3)

func _test_normalize_name_preserves_snake_case(failures: Array[String]) -> void:
	var result: String = PlaywrightTagNode._normalize_name("end_turn_button")
	if result != "end_turn_button":
		failures.append("Expected 'end_turn_button', got '%s'" % result)

	var result2: String = PlaywrightTagNode._normalize_name("home")
	if result2 != "home":
		failures.append("Expected 'home', got '%s'" % result2)

func _test_tag_key_used_when_set(failures: Array[String]) -> void:
	var tag := PlaywrightTagNode.new()
	tag.tag_key = "custom_key"
	if tag.tag_key != "custom_key":
		failures.append("Expected tag_key 'custom_key', got '%s'" % tag.tag_key)
	tag.free()

func _test_no_element_map_disables_processing(failures: Array[String]) -> void:
	var tag := PlaywrightTagNode.new()
	tag.tag_key = "test"
	if tag._element_map != null:
		failures.append("Expected null element map before injection")
	tag.free()

func _test_refresh_registration_restores_cleared_entry(failures: Array[String]) -> void:
	var element_map := ElementMapService.new()
	var control := Control.new()
	control.position = Vector2(10, 20)
	control.size = Vector2(30, 40)
	var tag := PlaywrightTagNode.new()
	tag.tag_key = "moving_target"
	tag.poll_interval = 0.0
	tag.set_element_map(element_map)
	control.add_child(tag)
	get_root().add_child(control)
	tag.refresh_registration()
	if not element_map.has_element("moving_target"):
		failures.append("Expected tag to register its element")
	element_map.clear()
	tag.refresh_registration()
	if not element_map.has_element("moving_target"):
		failures.append("Expected refresh_registration to restore a cleared entry")
	control.free()
