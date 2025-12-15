@tool
extends EditorPlugin

const AUTOLOAD_NAME := "PlaywrightService"
const AUTOLOAD_SCRIPT := "playwright_service.gd"

var _added_autoload: bool = false

func _enter_tree() -> void:
	var key: String = "autoload/" + AUTOLOAD_NAME
	if ProjectSettings.has_setting(key):
		_added_autoload = false
		return

	var self_script: Script = get_script()
	var base_dir: String = str(self_script.resource_path).get_base_dir()
	var autoload_path: String = base_dir.path_join(AUTOLOAD_SCRIPT)
	add_autoload_singleton(AUTOLOAD_NAME, autoload_path)
	_added_autoload = true

func _exit_tree() -> void:
	if _added_autoload:
		remove_autoload_singleton(AUTOLOAD_NAME)
