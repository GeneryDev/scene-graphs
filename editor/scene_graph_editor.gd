@tool
class_name SceneGraphEditor
extends GraphEdit

## Fired when graph connections have changed.
signal connections_changed()
## Fired when the selection has changed.
signal selection_changed()
## Fired when the selection has changed, with the following parameters:
## [param script]: if non-null, it means all selected nodes have the same script.
## [param selected_nodes]: the list of selected nodes (i.e. GraphElement nodes)
signal selection_changed_with_script(script: Script, selected_nodes: Array[Node])
## Fired when the current view's contents has changed, or when the view changes altogether. 
signal view_updated()
## Fired when the connection line cache is invalidated via [method invalidate_connection_line_cache].
signal connection_line_cache_invalidated()

## The edited scene root. Shorthand for [code]EditorInterface.get_edited_scene_root()[/code]
var scene_root: Node:
	get:
		return EditorInterface.get_edited_scene_root()
## The list of selected nodes (or rather, the names of selected GraphElement nodes) 
var selected_nodes: Array[StringName] = []
## Whether a GraphElement is currently being dragged and moved.
var dragging: bool = false
## The [InterfaceSignals] inner class instance.
var interface_signals: InterfaceSignals
## The [SceneGraphMemberSelector] instance for this editor. Use this to show and interact with the member selector.
var member_selector: SceneGraphMemberSelector
## The [Arranger] inner class instance.
var arranger: Arranger
## The [Hooks] inner class instance.
var hooks: Hooks
## The current [SceneGraphView].
var current_view: SceneGraphView:
	get:
		return current_view
	set(value):
		if current_view:
			current_view.view_updated.disconnect(_on_current_view_updated)
		current_view = value
		if current_view:
			current_view.view_updated.connect(_on_current_view_updated)
## The internal "_connection_layer" node. This is the parent of all [Line2D] nodes that correspond to each connection.
var connections_layer: Control
var _port_types_by_name: Dictionary[StringName, int] = {
	&"": -1,
}
var _next_port_type_idx := 0
var _pending_initial_draw := false
var _selection_change_queued := false


func _init():
	interface_signals = InterfaceSignals.new(self)
	member_selector = SceneGraphMemberSelector.new(self)
	arranger = Arranger.new(self)

	connections_layer = get_node(^"_connection_layer")
	hooks = Hooks.new(self)


func _ready() -> void:
	if is_part_of_edited_scene():
		return
	hooks._initialize_hooks()
	interface_signals.connect_all()
	for hook in hooks.configure_port_types:
		hook.configure_port_types()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		arranger.flush_arrange()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	for hook in hooks.drag_and_drop:
		if hook.can_drop_data(at_position, data):
			return true
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	for hook in hooks.drag_and_drop:
		hook.drop_data(at_position, data)


## Clears this graph by removing and freeing all elements, and removing all connections.
## This does not need to be called by hooks, as it is done automatically when constructing the graph from a view.
func clear():
	clear_connections()
	notify_connections_changed()
	for child in get_children():
		if child is not GraphElement:
			continue
		remove_child(child)
		child.queue_free()
	selected_nodes.clear()
	notify_selection_changed()


## Restores the given graph view and sets it as the current view.
## This does not need to be called by hooks, as it is done automatically when switching views or scenes.
func load(view: SceneGraphView) -> void:
	assert(view != null, "Cannot load a null scene graph view")
	current_view = view
	if view:
		view.update_object_views_with_rules()
		view.update_all_object_view_members_with_rules()

		_update_nav_from_view()
	else:
		view.clear_all_objects()
		view.update_object_views_with_rules()
		view.update_all_object_view_members_with_rules()

	view.notify_view_updated()

	if is_visible_in_tree():
		call_deferred(&"_rearrange_after_load")
	else:
		_pending_initial_draw = true


## Queues the given [GraphElement] to be rearranged at the earliest possible opportunity -- that is, next time the .
## All queued nodes will be rearranged together.
func queue_arrange(node: GraphElement) -> void:
	arranger.queue_arrange(node)


## Given a port type name, returns an int corresponding to that port type, which can be used
## in [GraphNode]-related methods to set up ports and connections between them.
## Please use this instead of hard-coding port type IDs to ensure better cross-hook compatibility; thanks.
func port_type(name: StringName) -> int:
	if _port_types_by_name.has(name):
		return _port_types_by_name[name]
	else:
		printerr("No such scene graph port type name '" + str(name) + "'")
		return -2


## Given a port type name, assigns it a unique integer to be used
## in [GraphNode]-related methods to set up ports and connections between them.
## This method is to be used by hooks that implement the "configure_port_types" capability.
func register_port_type(name: StringName) -> int:
	if _port_types_by_name.has(name):
		printerr("Scene graph port type '" + str(name) + "' has already been defined!")
		return _port_types_by_name[name]
	var idx := _next_port_type_idx
	_next_port_type_idx += 1
	_port_types_by_name[name] = idx
	return idx


## Notifies the graph editor that the [GraphElement] selection has changed, and fires the relevant signals.
## If the [param throttled] parameter is true, the execution of selection change callbacks is deferred to the end of the frame,
## and it will avoid emitting repeated consecutive signals. If false, the callbacks and signals will execute immediately.
func notify_selection_changed(throttled: bool = true) -> void:
	if throttled:
		if _selection_change_queued:
			return
		else:
			call_deferred(&"notify_selection_changed", false)
			_selection_change_queued = true
			return
	_selection_change_queued = false

	var only_script: Script = null
	var only_script_nodes: Array[Node]
	var script_set := false
	for node_name in selected_nodes:
		var node := get_node(NodePath(node_name))
		var script: Script = node.get_script()
		if !script_set:
			only_script = script
			script_set = true
		elif only_script != script:
			only_script = null

		only_script_nodes.append(node)

	selection_changed.emit()
	selection_changed_with_script.emit(only_script, only_script_nodes)


## Notifies the graph editor that graph connections have changed.
func notify_connections_changed() -> void:
	connections_changed.emit()


## Invalidates the connection line cache, forcing connections to be redrawn.
func invalidate_connection_line_cache() -> void:
	connection_lines_curvature = connection_lines_curvature
	connection_line_cache_invalidated.emit()


## Shorthand for calling [method connect_node] and [method notify_connections_changed]
func connect_node_and_notify(from_node: StringName, from_port: int, to_node: StringName, to_port: int, keep_alive: bool = true) -> Error:
	var err := connect_node(from_node, from_port, to_node, to_port)
	notify_connections_changed()
	return err


## Shorthand for calling [method disconnect_node] and [method notify_connections_changed]
func disconnect_node_and_notify(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	notify_connections_changed()


## Provides the default implementation of [method _get_connection_line], creating a sequence of points that make up a
## curved line between two port positions. An optional curvature parameter is included to set the curvature of the line,
## which if not set, defaults to the [member connection_lines_curvature] property.
func get_default_connection_line(from_position: Vector2, to_position: Vector2, curvature: float = -1) -> PackedVector2Array:
	if curvature < 0:
		curvature = connection_lines_curvature
	var x_diff: float = (to_position.x - from_position.x)
	var cp_offset: float = x_diff * curvature
	if x_diff < 0:
		cp_offset *= -1

	var curve := Curve2D.new()
	curve.add_point(from_position)
	curve.set_point_out(0, Vector2(cp_offset, 0))
	curve.add_point(to_position)
	curve.set_point_in(1, Vector2(-cp_offset, 0))

	if curvature > 0:
		return curve.tessellate(5, 2.0)
	else:
		return curve.tessellate(1)


## Converts a set of coordinates from the GraphEdit's Control coordinate space (Vector2.ZERO to [size]) to the
## coordinate space of elements inside the graph (useful for [member GraphElement.position_offset], for example).
func local_to_graph_position(position: Vector2) -> Vector2:
	return (position + scroll_offset) / zoom


## Given a dictionary representing a graph connection (with from_node, from_port, to_node, to_port),
## checks whether all these conditions match:
## 1. The connection represents valid graph nodes still in the editor.
## 2. The ports refer to valid ports on the corresponding graph nodes.
## 3. Native code has had a chance to build its "port cache", enabling [code]get_input_port_*()[/code] and [code]get_output_port_*()[/code] methods.
## Returns true if and only if all the above conditions are met.
func is_connection_ready(connection: Dictionary) -> bool:
	var from_graph_node := get_node_or_null(NodePath(connection.from_node))
	var to_graph_node := get_node_or_null(NodePath(connection.to_node))

	if !from_graph_node:
		return false
	if !to_graph_node:
		return false

	if connection.from_port >= from_graph_node.get_output_port_count():
		return false
	if connection.to_port >= to_graph_node.get_input_port_count():
		return false

	return true


## Given a dictionary representing a graph connection (with from_node, from_port, to_node, to_port),
## and two port types, checks whether all these conditions match:
## 1. The connection represents valid graph nodes still in the editor.
## 2. The ports refer to valid ports on the corresponding graph nodes.
## 3. Native code has had a chance to build its "port cache", enabling `get_input_port_*()` and `get_output_port_*()` methods.
## 4. The port types of the corresponding ports match the port types given as parameters.
## Returns true if and only if all the above conditions are met.
func check_connection_port_types(connection: Dictionary, from_port_type: int, to_port_type: int) -> bool:
	var from_graph_node := get_node_or_null(NodePath(connection.from_node))
	var to_graph_node := get_node_or_null(NodePath(connection.to_node))

	if !from_graph_node:
		return false
	if !to_graph_node:
		return false

	if connection.from_port >= from_graph_node.get_output_port_count():
		return false
	if connection.to_port >= to_graph_node.get_input_port_count():
		return false

	if (from_graph_node as GraphNode).get_output_port_type(connection.from_port) != from_port_type:
		return false
	if (to_graph_node as GraphNode).get_input_port_type(connection.to_port) != to_port_type:
		return false

	return true


## Given a position (such as mouse position from [popup_request]), returns the graph element at that location, if any.
func get_graph_element_at_position(at_position: Vector2) -> GraphElement:
	var children := get_children()
	for i in range(children.size() - 1, -1, -1):
		var child := children[i]
		if child is not GraphElement:
			continue
		var element: GraphElement = child
		if !element.is_visible_in_tree():
			continue
		var graph_node_rect := Rect2(element.position, element.size * zoom)
		if graph_node_rect.has_point(at_position):
			return element
	return null


func _update_nav_from_view() -> void:
	if !current_view:
		return
	if current_view.scene_data.has("zoom"):
		zoom = current_view.scene_data.zoom
	if current_view.scene_data.has("scroll_offset"):
		scroll_offset = current_view.scene_data.scroll_offset


func _update_nav_view() -> void:
	if !current_view:
		return
	if _pending_initial_draw:
		return
	current_view.scene_data.scroll_offset = scroll_offset
	current_view.scene_data.zoom = zoom


func _rearrange_after_load():
	_pending_initial_draw = false
	arranger.flush_arrange()
	_update_nav_from_view()


func _on_current_view_updated():
	for hook in hooks.populate_graph_nodes_from_view:
		hook.populate_graph_nodes_from_view()
	for hook in hooks.populate_graph_node_connections:
		hook.populate_graph_node_connections()
	view_updated.emit()
	if is_visible_in_tree():
		arranger.flush_arrange()


func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	for hook in hooks.override_connection_lines:
		var override = hook.get_connection_line(from_position, to_position)
		if override:
			return override
	return get_default_connection_line(from_position, to_position)


## Inner class handling all hook and capability related logic for an instance of [SceneGraphEditor]
## 
## This class implements a custom property getter; to access all hooks that implement a particular capability,
## you can use either dot notation or the [method get] method, with the capability name as the property name.
## This will return an array of hooks that implement the requested capability.
class Hooks extends RefCounted:
	const METHOD_NAME_GET_CAPABILITIES: StringName = &"get_scene_graph_capabilities"
	const META_NAME_GRANTED_CAPABILITIES: StringName = &"_scene_graph_granted_capabilities"
	var _capabilities: Dictionary = {
		"configure_capabilities": {
			"required_methods": [
				&"configure_capabilities",
			],
			"hooks": [] as Array[Object],
			"is_meta": true,
		},
		"drag_and_drop": {
			"required_methods": [
				&"can_drop_data",
				&"drop_data",
			],
			"hooks": [] as Array[Object],
		},
		"configure_port_types": {
			"required_methods": [
				&"configure_port_types",
			],
			"hooks": [] as Array[Object],
		},
		"override_connection_lines": {
			"required_methods": [
				&"get_connection_line",
			],
			"hooks": [] as Array[Object],
		},
		"populate_graph_nodes_from_view": {
			"required_methods": [
				&"populate_graph_nodes_from_view",
			],
			"hooks": [] as Array[Object],
		},
		"populate_graph_node_connections": {
			"required_methods": [
				&"populate_graph_node_connections",
			],
			"hooks": [] as Array[Object],
		},
		"handle_view_object_types": {
			"required_methods": [
				&"get_supported_view_object_types",
				&"view_object_to_object_key",
				&"object_key_to_view_object",
				&"object_key_serialize",
				&"object_key_deserialize",
			],
			"hooks": [] as Array[Object],
		},
		"view_serialization": {
			"required_methods": [
				&"edit_serialized_view",
				&"edit_deserialized_view",
			],
			"hooks": [] as Array[Object],
		},
		"configure_member_selector": {
			"required_methods": [
				&"get_member_selector_member_types",
				&"get_member_selector_tab_info",
				&"get_member_selector_member_list",
			],
			"hooks": [] as Array[Object],
		},
		"configure_hook_options": {
			"required_methods": [
				&"get_hook_options_id",
				&"get_hook_options_label",
				&"create_hook_options",
			],
			"optional_methods": [
				&"get_hook_description",
			],
			"hooks": [] as Array[Object],
		},
		"populate_popup_menu": {
			"required_methods": [
				&"populate_popup_menu",
			],
			"hooks": [] as Array[Object],
		},
		"view_rule.object_source": {
			"required_methods": [
				&"get_view_rule_id",
				&"generate_view_objects",
				&"get_view_rule_label",
			],
			"optional_methods": [
				&"create_view_rule_params",
				&"get_view_rule_description",
			],
			"hooks": [] as Array[Object],
		},
		"view_rule.member_source": {
			"required_methods": [
				&"get_view_rule_id",
				&"generate_view_object_members",
				&"get_view_rule_label",
			],
			"optional_methods": [
				&"create_view_rule_params",
				&"get_view_rule_description",
			],
			"hooks": [] as Array[Object],
		},
	}

	var editor: SceneGraphEditor
	var _hooks: Array[Object]


	func _init(editor: SceneGraphEditor):
		self.editor = editor

		_add_builtin_hooks()


	func _initialize_hooks() -> void:
		# First pass: Meta capabilities
		for hook in _hooks:
			_init_hook_meta(hook)

		# Second pass: Regular capabilities
		for hook in _hooks:
			_init_hook(hook)


	func _add_builtin_hooks() -> void:
		add_hook(load("res://addons/scene-graphs/editor/hooks/scene_objects.gd"))
		add_hook(load("res://addons/scene-graphs/editor/hooks/methods_and_signals.gd"))
		add_hook(load("res://addons/scene-graphs/editor/hooks/node_references.gd"))
		add_hook(load("res://addons/scene-graphs/editor/hooks/property_inspectors.gd"))
		add_hook(load("res://addons/scene-graphs/editor/hooks/connection_handles.gd"))

		add_hook(load("res://addons/scene-graphs/editor/hooks/view_rules/nodes.gd"))
		add_hook(load("res://addons/scene-graphs/editor/hooks/view_rules/connected_methods_and_signals.gd"))
		add_hook(load("res://addons/scene-graphs/editor/hooks/view_rules/node_reference_properties.gd"))
		add_hook(load("res://addons/scene-graphs/editor/hooks/view_rules/members_by_name.gd"))


	## Adds a script as a hook.
	## Returns true if and only if instantiation was successful and the minimum required methods were implemented.
	func add_hook(script: Script) -> bool:
		var instance: Object = script.new(editor)
		if !instance:
			printerr("Failed to instantiate script " + script.resource_path + " as a scene graph hook: Requires a constructor that takes 1 argument.")
			return false
		if !instance.has_method(METHOD_NAME_GET_CAPABILITIES):
			printerr("Could not add script " + script.resource_path + " as a scene graph hook: Does not implement required method '" + str(METHOD_NAME_GET_CAPABILITIES) + "'")
			return false

		_hooks.append(instance)

		return true


	## Registers a new capability, given a capability name
	## and a list of required methods for hooks implementing such capability.
	## Returns true if this was successful, or false if another capability with that name had already been registered.
	## This should be called by hooks with the "configure_capabilities" capability.
	func register_capability(name: String, required_methods: Array[StringName]) -> bool:
		if _capabilities.has(name):
			printerr("Failed to register capability '" + name + "': another capability with the same name is already registered!")
			return false

		_capabilities[name] = {
			"required_methods": required_methods,
			"hooks": [] as Array[Object],
		}
		return true


	# First pass: Meta capabilities
	func _init_hook_meta(instance: Object) -> bool:
		var script: Script = instance.get_script()
		var hook_capabilities: Array[String] = instance.call(METHOD_NAME_GET_CAPABILITIES)

		for capability in hook_capabilities:
			if !_is_meta_capability(capability):
				continue
			if _get_granted_capabilities(instance).has(capability):
				continue
			if _validate_capability(instance, script, capability):
				_grant_capability(instance, script, capability)
				instance.configure_capabilities()

		return true


	# Second pass: Regular capabilities
	func _init_hook(instance: Object) -> bool:
		var script: Script = instance.get_script()
		var hook_capabilities: Array[String] = instance.call(METHOD_NAME_GET_CAPABILITIES)

		for capability in hook_capabilities:
			if _is_meta_capability(capability):
				continue
			if _get_granted_capabilities(instance).has(capability):
				continue
			if _validate_capability(instance, script, capability):
				_grant_capability(instance, script, capability)

		print("Initialized scene graph hook script: " + script.resource_path + " with capabilities: " + str(_get_granted_capabilities(instance)))
		return true


	func _is_meta_capability(capability: String) -> bool:
		return _capabilities.has(capability) && _capabilities[capability].get("is_meta")


	func _validate_capability(instance: Object, script: Script, capability: String) -> bool:
		if !_capabilities.has(capability):
			printerr("Invalid scene graph hook capability '" + capability + "' in script " + script.resource_path)
			return false
		var list: Array[Object] = _capabilities[capability].hooks
		if list.has(instance):
			printerr("Duplicate scene graph hook capability '" + capability + "' in script " + script.resource_path)
			return false
		var required_methods: Array = _capabilities[capability].required_methods
		var missing_any := false
		for required_method_name: StringName in required_methods:
			if !instance.has_method(required_method_name):
				printerr("Missing method '" + str(required_method_name) + "', required for scene graph hook capability '" + capability + "' in script " + script.resource_path)
				missing_any = true
				continue

		if missing_any:
			printerr("Skipping scene graph hook capability '" + capability + "' in script " + script.resource_path + " due to missing required methods.")
			return false

		return true


	func _grant_capability(instance: Object, script: Script, capability: String) -> void:
		_get_granted_capabilities(instance).append(capability)
		_capabilities[capability].hooks.append(instance)


	func _get_granted_capabilities(instance: Object) -> Array[String]:
		var granted_capabilities: Array[String] = instance.get_meta(META_NAME_GRANTED_CAPABILITIES, [] as Array[String]) as Array[String]
		instance.set_meta(META_NAME_GRANTED_CAPABILITIES, granted_capabilities)
		return granted_capabilities


	func _get(property: StringName) -> Variant:
		if _capabilities.has(property as String):
			return _capabilities[property as String].hooks
		return null


## Provides static utility methods
class Utility extends RefCounted:
	## Given an object, returns its Texture2D editor icon, either by its script or built-in class or type icon.
	static func get_object_icon(obj: Object) -> Texture2D:
		if obj == null:
			return null
		var script = obj.get_script()
		if script:
			var script_icon := get_script_icon(script)
			if script_icon:
				return script_icon

		var cls_name := obj.get_class()
		var theme := EditorInterface.get_editor_theme()
		if theme.has_icon(cls_name, "EditorIcons"):
			return theme.get_icon(cls_name, "EditorIcons")

		return null


	## Given a script, returns its Texture2D editor icon, if set via @icon. Returns null if none is set.
	static func get_script_icon(script: Script) -> Texture2D:
		var filepath := script.resource_path
		var script_classes := ProjectSettings.get_global_class_list() as Array
		for a_class in script_classes:
			if a_class.path == filepath:
				if a_class.icon:
					return load(a_class.icon)
				return null
		return null


## Inner class that handles general [GraphEdit] interface signals
class InterfaceSignals extends RefCounted:
	var editor: SceneGraphEditor


	func _init(editor: SceneGraphEditor):
		self.editor = editor


	func connect_all() -> void:
		editor.popup_request.connect(_on_popup_request)
		editor.node_selected.connect(_on_node_selected)
		editor.node_deselected.connect(_on_node_deselected)
		editor.begin_node_move.connect(_on_begin_node_move)
		editor.end_node_move.connect(_on_end_node_move)
		editor.child_exiting_tree.connect(_on_node_removed)
		editor.visibility_changed.connect(_on_visibility_changed)
		editor.scroll_offset_changed.connect(_on_scroll_offset_changed)


	func _on_popup_request(at_position: Vector2) -> void:
		var elem_at_position := editor.get_graph_element_at_position(at_position)
		if elem_at_position:
			if !elem_at_position.selected:
				editor.set_selected(elem_at_position)

		var menu := PopupMenu.new()
		var actions: Dictionary[int, Callable] = { }

		for hook in editor.hooks.populate_popup_menu:
			hook.populate_popup_menu(at_position, menu, actions)

		if menu.item_count == 0:
			menu.queue_free()
			return

		editor.add_child(menu)
		menu.position = editor.get_screen_position() + at_position

		menu.show()
		menu.reset_size()
		menu.close_requested.connect(menu.queue_free)
		menu.id_pressed.connect(_on_popup_item_pressed.bind(actions))


	func _on_popup_item_pressed(id: int, actions: Dictionary[int, Callable]) -> void:
		if actions.has(id):
			actions[id].call()


	func _on_node_selected(node: Node) -> void:
		editor.selected_nodes.append(node.name)
		editor.notify_selection_changed()


	func _on_node_deselected(node: Node) -> void:
		_deselect_node(node)


	func _deselect_node(node: Node) -> void:
		var changed := false
		for i in range(editor.selected_nodes.size() - 1, -1, -1):
			if editor.selected_nodes[i] == node.name:
				changed = true
				editor.selected_nodes.remove_at(i)
		if changed:
			editor.notify_selection_changed()


	func _on_begin_node_move() -> void:
		editor.dragging = true


	func _on_end_node_move() -> void:
		editor.dragging = false


	func _on_node_removed(node: Node) -> void:
		_deselect_node(node)


	func _on_visibility_changed() -> void:
		if editor._pending_initial_draw:
			editor.call_deferred(&"_rearrange_after_load")


	func _on_scroll_offset_changed(offset: Vector2) -> void:
		editor._update_nav_view()


## Inner class that handles logic for arranging [GraphElement] elements in a graph.
## (hope to have custom arranging code at some point because the built-in logic is dogwater)
class Arranger extends RefCounted:
	var editor: SceneGraphEditor

	var _queued_for_arrange: Array = []


	func _init(editor: SceneGraphEditor):
		self.editor = editor


	func queue_arrange(node: GraphElement) -> void:
		if _queued_for_arrange.has(node):
			return
		_queued_for_arrange.append(node)


	func flush_arrange() -> void:
		if !_queued_for_arrange:
			return
		_queued_for_arrange = _queued_for_arrange.filter(_is_still_valid)
		if !_queued_for_arrange:
			return
		editor.set_selected(null)
		for elem: GraphElement in _queued_for_arrange:
			elem.selected = true
		editor.arrange_nodes()
		editor.set_selected(null)


	func _is_still_valid(node) -> bool:
		return node != null && node is GraphElement && is_instance_valid(node) && node.get_parent() == editor
