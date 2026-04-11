## Manages a registry of tagged UI element positions for Playwright test consumption.
##
## Collects position data from PlaywrightTagNode instances and emits the full
## element map to the browser via JavaScriptBridge when running in test mode.
class_name ElementMapService
extends RefCounted

## Position and size data for a single tagged element.
class ElementEntry extends RefCounted:
	var key: String
	var center_x: int
	var center_y: int
	var width: int
	var height: int
	var visible: bool

	func _init(
		p_key: String = "",
		p_center_x: int = 0,
		p_center_y: int = 0,
		p_width: int = 0,
		p_height: int = 0,
		p_visible: bool = true
	) -> void:
		key = p_key
		center_x = p_center_x
		center_y = p_center_y
		width = p_width
		height = p_height
		visible = p_visible

	func to_dict() -> Dictionary[String, Variant]:
		return {
			"x": center_x,
			"y": center_y,
			"w": width,
			"h": height,
			"visible": visible
		}

var _elements: Dictionary[String, ElementEntry] = {}
var _dirty: bool = false
var _flush_scheduled: bool = false
var _owner: Node = null

## Binds to an owner node for deferred flush scheduling.
func setup(owner: Node) -> void:
	_owner = owner

## Registers an element with the given key and initial position.
func register(key: String, center: Vector2, size: Vector2, visible: bool) -> void:
	if key.is_empty():
		return
	var entry := ElementEntry.new(
		key,
		int(center.x),
		int(center.y),
		int(size.x),
		int(size.y),
		visible
	)
	_elements[key] = entry
	_mark_dirty()

## Removes a previously registered element.
func unregister(key: String) -> void:
	if not _elements.has(key):
		return
	_elements.erase(key)
	_mark_dirty()

## Updates the position and visibility of an existing element.
func update_position(key: String, center: Vector2, size: Vector2, visible: bool) -> void:
	var entry: ElementEntry = _elements.get(key, null)
	if entry == null:
		register(key, center, size, visible)
		return
	var new_cx: int = int(center.x)
	var new_cy: int = int(center.y)
	var new_w: int = int(size.x)
	var new_h: int = int(size.y)
	if entry.center_x == new_cx and entry.center_y == new_cy and entry.width == new_w and entry.height == new_h and entry.visible == visible:
		return
	entry.center_x = new_cx
	entry.center_y = new_cy
	entry.width = new_w
	entry.height = new_h
	entry.visible = visible
	_mark_dirty()

## Returns true when the given key is registered.
func has_element(key: String) -> bool:
	return _elements.has(key)

## Returns the entry for the given key, or null.
func get_entry(key: String) -> ElementEntry:
	return _elements.get(key, null)

## Returns all registered entries.
func get_all_entries() -> Dictionary[String, ElementEntry]:
	return _elements

## Returns all registered keys.
func get_all_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: String in _elements:
		keys.append(key)
	return keys

## Returns the number of registered elements.
func get_element_count() -> int:
	return _elements.size()

## Returns true when there are pending changes not yet flushed.
func is_dirty() -> bool:
	return _dirty

## Flushes all element positions to the browser via JavaScriptBridge.
func flush_to_browser() -> void:
	_flush_scheduled = false
	_dirty = false
	if not OS.has_feature("web"):
		return
	var elements_dict: Dictionary[String, Variant] = {}
	for key: String in _elements:
		var entry: ElementEntry = _elements[key]
		elements_dict[key] = entry.to_dict()
	var viewport_size: Vector2 = Vector2.ZERO
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		viewport_size = tree.root.get_visible_rect().size
	var payload: Dictionary[String, Variant] = {
		"elements": elements_dict,
		"viewport_width": int(viewport_size.x),
		"viewport_height": int(viewport_size.y)
	}
	var json_string: String = JSON.stringify(payload)
	var js_code: String = """
		var __payload = %s;
		window.godotElements = __payload.elements;
		window.godotElementsViewport = {
			width: __payload.viewport_width,
			height: __payload.viewport_height
		};
		window.dispatchEvent(new CustomEvent('godot-elements-updated', { detail: __payload }));
	""" % json_string
	JavaScriptBridge.eval(js_code)

## Clears all registered elements.
func clear() -> void:
	_elements.clear()
	_dirty = false
	_flush_scheduled = false

func _mark_dirty() -> void:
	_dirty = true
	if _flush_scheduled:
		return
	_flush_scheduled = true
	if _owner and is_instance_valid(_owner) and _owner.is_inside_tree():
		_owner.call_deferred("_on_element_map_flush_requested")
	else:
		# No owner — flush will happen on next explicit call
		pass
