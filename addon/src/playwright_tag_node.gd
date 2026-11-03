@tool
## Tracks a parent Control or Node2D position in the element map.
##
## Created automatically by PlaywrightServiceModule.scan_scene() for nodes
## that have set_meta("playwright", "some_key"). Prefer adding this node
## directly in scenes so test handles are visible in the editor.
class_name PlaywrightTagNode
extends Node

const ElementMapService = preload("element_map_service.gd")

@export var tag_key: String = "":
	set(value):
		tag_key = value.strip_edges()
		update_configuration_warnings()
@export var include_size: bool = true
@export var service_path: NodePath = NodePath("/root/PlaywrightService")
## Seconds between position samples. Set to 0 for every rendered frame when
## exposing fast-moving gameplay objects.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var poll_interval: float = 0.1

var _resolved_key: String = ""
var _element_map: ElementMapService = null
var _registered: bool = false
var _owned_entry: ElementMapService.ElementEntry = null
var _last_center: Vector2 = Vector2(-99999, -99999)
var _last_size: Vector2 = Vector2(-1, -1)
var _last_visible: bool = false
var _poll_timer: float = 0.0

func set_element_map(element_map: ElementMapService) -> void:
	if _element_map != element_map:
		_release_registration()
	_element_map = element_map

func refresh_registration() -> void:
	_release_registration()
	_resolved_key = get_resolved_key_preview()
	if _element_map == null or _resolved_key.is_empty():
		return
	_last_center = Vector2(-99999, -99999)
	_last_size = Vector2(-1, -1)
	_last_visible = not _last_visible
	_push_position(true)
	_registered = true

func get_resolved_key_preview() -> String:
	if not tag_key.is_empty():
		return tag_key
	return _derive_key_from_meta()

func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	if _element_map == null:
		_element_map = _get_autoload_element_map()
	_resolved_key = get_resolved_key_preview()
	if _resolved_key.is_empty():
		return
	refresh_registration()
	set_process(true)

func _release_registration() -> void:
	# A newer scene can claim this key before the outgoing scene exits. Entry
	# identity is the lease: stale nodes may neither update nor remove it.
	if _owned_entry != null and _element_map != null and _element_map.get_entry(_resolved_key) == _owned_entry:
		_element_map.unregister(_resolved_key)
	_owned_entry = null
	_registered = false

func _exit_tree() -> void:
	_release_registration()
	set_process(false)

func _process(delta: float) -> void:
	if not _registered:
		return
	if is_zero_approx(poll_interval):
		_push_position()
		return
	_poll_timer += delta
	if _poll_timer < poll_interval:
		return
	_poll_timer = 0.0
	_push_position()

func _push_position(claim_registration: bool = false) -> void:
	if _element_map == null or _resolved_key.is_empty():
		return
	var parent_node: Node = get_parent()
	if parent_node == null or not is_instance_valid(parent_node):
		return
	var center: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2.ZERO
	var visible: bool = true
	if parent_node is Control:
		var control: Control = parent_node as Control
		var global_rect: Rect2 = control.get_global_rect()
		center = global_rect.position + global_rect.size * 0.5
		size = global_rect.size if include_size else Vector2.ZERO
		visible = control.is_visible_in_tree()
	elif parent_node is Node2D:
		var node_2d: Node2D = parent_node as Node2D
		center = node_2d.global_position
		visible = node_2d.is_visible_in_tree()
	else:
		return
	if claim_registration:
		_element_map.register(_resolved_key, center, size, visible)
		_owned_entry = _element_map.get_entry(_resolved_key)
	elif _owned_entry == null or _element_map.get_entry(_resolved_key) != _owned_entry:
		return
	elif center == _last_center and size == _last_size and visible == _last_visible:
		return
	_last_center = center
	_last_size = size
	_last_visible = visible
	_element_map.update_position(_resolved_key, center, size, visible)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var parent_node: Node = get_parent()
	if parent_node == null:
		warnings.append("PlaywrightTag must be a child of the Control or Node2D it exposes to tests.")
		return warnings
	if not (parent_node is Control or parent_node is Node2D):
		warnings.append("PlaywrightTag only supports Control and Node2D parents.")
	var resolved_key: String = get_resolved_key_preview()
	if resolved_key.is_empty():
		warnings.append("Set tag_key, or set parent metadata playwright='your_key'.")
	elif _has_duplicate_key(parent_node, resolved_key):
		warnings.append("Another PlaywrightTag or playwright metadata entry uses '%s'. Keys should be unique." % resolved_key)
	return warnings

func _derive_key_from_meta() -> String:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return ""
	if parent_node.has_meta("playwright"):
		return str(parent_node.get_meta("playwright")).strip_edges()
	return ""

func _get_autoload_element_map() -> ElementMapService:
	if not is_inside_tree():
		return null
	var service: Node = get_node_or_null(service_path)
	if service == null and get_tree() != null and get_tree().root != null:
		service = get_tree().root.get_node_or_null("PlaywrightService")
	if service == null or not service.has_method("get_element_map"):
		return null
	return service.call("get_element_map") as ElementMapService

func _has_duplicate_key(parent_node: Node, key: String) -> bool:
	var scene_root: Node = parent_node.get_tree().edited_scene_root if Engine.is_editor_hint() and parent_node.is_inside_tree() else null
	if scene_root == null:
		scene_root = parent_node.get_tree().current_scene if parent_node.is_inside_tree() else parent_node.owner
	if scene_root == null:
		scene_root = parent_node
	return _count_matching_keys(scene_root, key) > 1

func _count_matching_keys(node: Node, key: String) -> int:
	var count: int = 0
	if node != self:
		if node is PlaywrightTagNode:
			var tag: PlaywrightTagNode = node as PlaywrightTagNode
			if tag.get_resolved_key_preview() == key:
				count += 1
		elif node.has_meta("playwright") and str(node.get_meta("playwright")).strip_edges() == key:
			count += 1
	for child: Node in node.get_children():
		count += _count_matching_keys(child, key)
	return count

static func _normalize_name(name: String) -> String:
	var result: String = ""
	for i in range(name.length()):
		var c: String = name[i]
		if c == c.to_upper() and c != c.to_lower() and i > 0:
			var prev: String = name[i - 1]
			if prev != prev.to_upper() or prev == prev.to_lower():
				result += "_"
		result += c.to_lower()
	return result
