@tool
extends EditorPlugin

const AUTOLOAD_NAME := "PlaywrightService"
const AUTOLOAD_SCRIPT := "autoload.gd"
const PlaywrightTagNodeScript = preload("src/playwright_tag_node.gd")
const PlaywrightStatePublisherScript = preload("src/playwright_state_publisher.gd")
const PlaywrightEventEmitterScript = preload("src/playwright_event_emitter.gd")

const MENU_SCAN_METADATA := "GD Playwright: Scan Scene For Metadata"
const MENU_CONVERT_METADATA := "GD Playwright: Convert Metadata To Tags"

var _added_autoload: bool = false

func _enter_tree() -> void:
	_register_project_settings()
	add_custom_type("PlaywrightTag", "Node", PlaywrightTagNodeScript, _editor_icon("Tag", "Node"))
	add_custom_type("PlaywrightStatePublisher", "Node", PlaywrightStatePublisherScript, _editor_icon("Dictionary", "Node"))
	add_custom_type("PlaywrightEventEmitter", "Node", PlaywrightEventEmitterScript, _editor_icon("Signal", "Node"))
	add_tool_menu_item(MENU_SCAN_METADATA, Callable(self, "_scan_scene_for_metadata"))
	add_tool_menu_item(MENU_CONVERT_METADATA, Callable(self, "_convert_metadata_to_tags"))

	var key: String = "autoload/" + AUTOLOAD_NAME
	if ProjectSettings.has_setting(key):
		_added_autoload = false
		return

	var base_dir: String = str(get_script().resource_path).get_base_dir()
	add_autoload_singleton(AUTOLOAD_NAME, base_dir.path_join(AUTOLOAD_SCRIPT))
	_added_autoload = true

func _exit_tree() -> void:
	remove_tool_menu_item(MENU_CONVERT_METADATA)
	remove_tool_menu_item(MENU_SCAN_METADATA)
	remove_custom_type("PlaywrightEventEmitter")
	remove_custom_type("PlaywrightStatePublisher")
	remove_custom_type("PlaywrightTag")
	if _added_autoload:
		remove_autoload_singleton(AUTOLOAD_NAME)

func _register_project_settings() -> void:
	_ensure_setting("gd_playwright/enabled", TYPE_BOOL, false)
	_ensure_setting("gd_playwright/test_mode", TYPE_BOOL, false)
	_ensure_setting("gd_playwright/log_events", TYPE_BOOL, true)
	_ensure_setting("gd_playwright/event_buffer_max", TYPE_INT, 1000)
	_ensure_setting("gd_playwright/event_buffer_trim", TYPE_INT, 500)

func _ensure_setting(setting_name: String, type: int, default_value: Variant) -> void:
	if not ProjectSettings.has_setting(setting_name):
		ProjectSettings.set_setting(setting_name, default_value)
	ProjectSettings.set_initial_value(setting_name, default_value)
	ProjectSettings.add_property_info({
		"name": setting_name,
		"type": type
	})

func _editor_icon(preferred_name: String, fallback_name: String) -> Texture2D:
	var editor_interface: EditorInterface = get_editor_interface()
	if editor_interface == null:
		return null
	var base_control: Control = editor_interface.get_base_control()
	if base_control == null:
		return null
	if base_control.has_theme_icon(preferred_name, "EditorIcons"):
		return base_control.get_theme_icon(preferred_name, "EditorIcons")
	if base_control.has_theme_icon(fallback_name, "EditorIcons"):
		return base_control.get_theme_icon(fallback_name, "EditorIcons")
	return null

func _scan_scene_for_metadata() -> void:
	var root: Node = _get_edited_scene_root()
	if root == null:
		push_warning("GD Playwright: open a scene before scanning metadata.")
		return
	var result: Dictionary = _scan_metadata_recursive(root)
	print("GD Playwright: found %d playwright metadata entries and %d PlaywrightTag nodes." % [int(result.get("metadata", 0)), int(result.get("tags", 0))])

func _convert_metadata_to_tags() -> void:
	var root: Node = _get_edited_scene_root()
	if root == null:
		push_warning("GD Playwright: open a scene before converting metadata.")
		return
	var converted: int = _convert_metadata_recursive(root, root)
	if converted > 0:
		var editor_interface: EditorInterface = get_editor_interface()
		if editor_interface != null and editor_interface.has_method("mark_scene_as_unsaved"):
			editor_interface.call("mark_scene_as_unsaved")
	print("GD Playwright: converted %d playwright metadata entries to PlaywrightTag nodes and removed converted metadata." % converted)

func _get_edited_scene_root() -> Node:
	var editor_interface: EditorInterface = get_editor_interface()
	if editor_interface == null:
		return null
	return editor_interface.get_edited_scene_root()

func _scan_metadata_recursive(node: Node) -> Dictionary:
	var metadata_count: int = 1 if node.has_meta("playwright") else 0
	var tag_count: int = 1 if node is PlaywrightTagNode else 0
	for child: Node in node.get_children():
		var child_result: Dictionary = _scan_metadata_recursive(child)
		metadata_count += int(child_result.get("metadata", 0))
		tag_count += int(child_result.get("tags", 0))
	return {
		"metadata": metadata_count,
		"tags": tag_count
	}

func _convert_metadata_recursive(node: Node, scene_root: Node) -> int:
	var converted: int = 0
	if node.has_meta("playwright") and (node is Control or node is Node2D) and not _has_playwright_tag_child(node):
		var tag: PlaywrightTagNode = PlaywrightTagNodeScript.new()
		tag.name = "PlaywrightTag"
		tag.tag_key = str(node.get_meta("playwright")).strip_edges()
		node.add_child(tag)
		tag.owner = scene_root
		node.remove_meta("playwright")
		converted += 1
	for child: Node in node.get_children():
		converted += _convert_metadata_recursive(child, scene_root)
	return converted

func _has_playwright_tag_child(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is PlaywrightTagNode:
			return true
	return false
