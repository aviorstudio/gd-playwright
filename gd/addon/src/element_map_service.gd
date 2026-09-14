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
var _wire_entries: Dictionary[String, ElementEntry] = {}
var _wire_views: Dictionary[String, Dictionary] = {}
var _wire_materialization_count: int = 0

## Binds to an owner node for deferred flush scheduling.
func setup(owner: Node) -> void:
	_owner = owner

## Registers an element with the given key and initial position.
func register(key: String, center: Vector2, size: Vector2, visible: bool) -> void:
	if key.is_empty():
		return
	if _owner != null and _owner.has_method("_allows_element_key") and not bool(_owner.call("_allows_element_key", key)):
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
	_wire_entries.erase(key)
	_wire_views.erase(key)
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
	if not _is_web_runtime():
		return
	var elements_dict: Dictionary[String, Variant] = {}
	for key: String in _elements:
		var entry: ElementEntry = _elements[key]
		var wire_view: Dictionary = _wire_views.get(key, {})
		if _wire_entries.get(key) != entry or not _can_reuse_wire_view(wire_view, entry):
			wire_view = entry.to_dict()
			_wire_materialization_count += 1
			_wire_entries[key] = entry
			_wire_views[key] = wire_view
		elements_dict[key] = wire_view
	for cached_key: String in _wire_views.keys():
		if not _elements.has(cached_key):
			_wire_views.erase(cached_key)
			_wire_entries.erase(cached_key)
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
	_publish_payload_json(json_string)

func _wire_view_matches_entry(wire_view: Dictionary, entry: ElementEntry) -> bool:
	return wire_view.size() == 5 \
		and wire_view.get("x") == entry.center_x \
		and wire_view.get("y") == entry.center_y \
		and wire_view.get("w") == entry.width \
		and wire_view.get("h") == entry.height \
		and wire_view.get("visible") == entry.visible

func _can_reuse_wire_view(wire_view: Dictionary, entry: ElementEntry) -> bool:
	return _wire_view_matches_entry(wire_view, entry)

func _is_web_runtime() -> bool:
	return OS.has_feature("web")

func _publish_payload_json(json_string: String) -> void:
	if _owner != null and _owner.has_method("_publish_element_map"):
		_owner.call("_publish_element_map", json_string)
	else:
		JavaScriptBridge.eval("""
			var __payload = %s;
			window.godotElements = __payload.elements;
			window.godotElementsViewport = { width: __payload.viewport_width, height: __payload.viewport_height };
			window.dispatchEvent(new CustomEvent('godot-elements-updated', { detail: __payload }));
		""" % json_string)

## Clears all registered elements.
func clear() -> void:
	_elements.clear()
	_wire_entries.clear()
	_wire_views.clear()
	_mark_dirty()

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
