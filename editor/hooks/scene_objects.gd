@tool
extends RefCounted

static var SceneObjectGraphNode: Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd")

const OBJECT_TYPE_NODE := "node"

const META_NAME_EXTENSION := &"_scene_objects_extension"

var editor: SceneGraphEditor


func _init(editor: SceneGraphEditor):
	self.editor = editor
	editor.connection_drag_started.connect(_on_connection_drag_started)
	editor.connection_drag_ended.connect(_on_connection_drag_ended)
	editor.selection_changed_with_script.connect(_on_selection_changed_with_script)
	editor.delete_nodes_request.connect(_on_delete_nodes_request)


func get_scene_graph_capabilities() -> Array[String]:
	return ["configure_capabilities", "configure_port_types", "populate_graph_nodes_from_view", "drag_and_drop", "handle_view_object_types", "populate_popup_menu"]


### CAPABILITY: configure_capabilities
func configure_capabilities() -> void:
	editor.hooks.register_capability("initialize_object_graph_node", [&"initialize_object_graph_node"] as Array[StringName])
	editor.hooks.register_capability("create_object_graph_node_slots", [&"create_object_graph_node_slots"] as Array[StringName])
	editor.hooks.register_capability("claim_object_graph_node_member_slots", [&"get_object_graph_node_member_slot_bid"] as Array[StringName])
	editor.hooks.register_capability("draw_object_graph_node_port", [&"draw_object_graph_node_port"] as Array[StringName])


### CAPABILITY: configure_ports
func configure_port_types() -> void:
	editor.register_port_type(&"wildcard_in")
	editor.register_port_type(&"wildcard_out")


### CAPABILITY: handle_view_object_types
func get_supported_view_object_types() -> Array[String]:
	return [OBJECT_TYPE_NODE]


func view_object_to_object_key(object_type: String, obj: Object) -> Variant:
	return obj.get_instance_id()


func object_key_to_view_object(object_type: String, key: Variant) -> Object:
	if key is not int:
		return null
	return instance_from_id(key as int)


func object_key_serialize(object_type: String, key: Variant) -> Variant:
	if key is not int:
		return null
	var node := instance_from_id(key as int) as Node
	if !node:
		return null
	var scene_root := editor.scene_root
	if scene_root == node || scene_root.is_ancestor_of(node):
		return editor.scene_root.get_path_to(node)
	else:
		return null


func object_key_deserialize(object_type: String, serialized: Variant) -> Variant:
	if serialized is not NodePath:
		return null
	var path := serialized as NodePath
	if !path:
		return null
	var node := editor.scene_root.get_node_or_null(path)
	if !node:
		return null
	return node.get_instance_id()

### CAPABILITY: populate_graph_nodes_from_view


func populate_graph_nodes_from_view() -> void:
	var scene_object_views := editor.current_view.get_scene_object_views(OBJECT_TYPE_NODE)
	for object_key in scene_object_views:
		var obj: Object = object_key_to_view_object(OBJECT_TYPE_NODE, object_key)
		if !obj:
			continue

		var existing := editor.current_view.get_graph_node_for_object(OBJECT_TYPE_NODE, obj)
		var graph_node: GraphNode
		if existing:
			graph_node = existing
			_disconnect_all_for_node(existing.name)
		else:
			graph_node = editor.current_view.instantiate_graph_node_for_object(OBJECT_TYPE_NODE, obj, SceneObjectGraphNode)
			if graph_node:
				editor.add_child(graph_node)

		graph_node.update_from_view()

	for child: Node in editor.get_children():
		if !is_instance_of(child, SceneObjectGraphNode):
			continue
		var obj: Object = child.get_object()
		if !editor.current_view.has_object_view(OBJECT_TYPE_NODE, obj):
			editor.remove_child(child)
			child.queue_free()


func _disconnect_all_for_node(name: StringName) -> void:
	for connection in editor.get_connection_list_from_node(name):
		editor.disconnect_node(connection.from_node, connection.from_port, connection.to_node, connection.to_port)


### CAPABILITY: drag_and_drop
func can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var data_dict: Dictionary = data
	if data_dict["type"] != "nodes":
		return false
	return true


func drop_data(at_position: Vector2, data: Variant) -> void:
	var data_dict: Dictionary = data
	if data_dict["type"] != "nodes":
		return

	editor.set_selected(null)

	for node_path: NodePath in data_dict["nodes"]:
		var node := editor.get_node_or_null(node_path)
		if !node:
			continue
		editor.current_view.transactions.add_object_view(OBJECT_TYPE_NODE, node, editor.local_to_graph_position(at_position))

### DELETING


func _on_delete_nodes_request(graph_nodes: Array[StringName]) -> void:
	for graph_node_name: StringName in graph_nodes:
		var graph_node := editor.get_node_or_null(NodePath(graph_node_name))
		if !is_instance_of(graph_node, SceneObjectGraphNode):
			continue
		var obj: Object = graph_node.get_object()
		editor.current_view.transactions.remove_object_view(OBJECT_TYPE_NODE, obj)

### SELECTION


func _on_selection_changed_with_script(script: Script, nodes: Array[Node]) -> void:
	if script == SceneObjectGraphNode:
		select_nodes(nodes.map(_map_graph_node_to_object))


func _map_graph_node_to_object(graph_node: GraphNode) -> Object:
	return graph_node.get_object()


func select_nodes(nodes: Array) -> void:
	EditorInterface.get_selection().clear()
	for node in nodes:
		if node is not Node:
			continue
		if !node.is_inside_tree():
			continue
		EditorInterface.get_selection().add_node(node)


var _connection_dragging_wildcard := false
var _connection_dragging_wildcard_type := 0
var _connection_dragging_wildcard_graph_node: GraphNode = null
var _connection_dragging_wildcard_cursor_pos := Vector2.ZERO


func _on_connection_drag_started(from_node_name: StringName, from_port: int, is_output: bool) -> void:
	var node := editor.get_node_or_null(NodePath(from_node_name))
	if !node:
		return

	var graph_node: GraphNode = node
	var slot_type: int = graph_node.get_output_port_type(from_port) if is_output else graph_node.get_input_port_type(from_port)

	if slot_type == editor.port_type(&"wildcard_in") || slot_type == editor.port_type(&"wildcard_out"):
		_connection_dragging_wildcard = true
		_connection_dragging_wildcard_type = slot_type
		_connection_dragging_wildcard_graph_node = graph_node
		_connection_dragging_wildcard_cursor_pos = editor.get_local_mouse_position()
	else:
		_connection_dragging_wildcard = false
		_connection_dragging_wildcard_graph_node = null


func _on_connection_drag_ended() -> void:
	if _connection_dragging_wildcard:
		var graph_node := _connection_dragging_wildcard_graph_node
		_connection_dragging_wildcard = false
		_connection_dragging_wildcard_graph_node = null
		var cursor_distance := editor.get_local_mouse_position().distance_to(_connection_dragging_wildcard_cursor_pos)
		if cursor_distance <= ProjectSettings.get_setting("gui/common/drag_threshold"):
			editor.member_selector.show_single_select(
				graph_node.object_type,
				graph_node.get_object(),
				editor.member_selector.get_all_input_member_types() if _connection_dragging_wildcard_type == editor.port_type(&"wildcard_in") else editor.member_selector.get_all_output_member_types(),
				editor.current_view.transactions.add_object_view_member,
			)

### CAPABILITY: populate_popup_menu
const ACTION_MANAGE_MEMBERS: int = 200
const ACTION_MEMBER_REMOVE: int = 210


func populate_popup_menu(at_position: Vector2, menu: PopupMenu, actions: Dictionary[int, Callable]) -> void:
	var hovered_element := editor.get_graph_element_at_position(at_position)
	if !is_instance_of(hovered_element, SceneObjectGraphNode):
		return
	var graph_node: GraphNode = hovered_element

	menu.add_separator("Scene Object")
	menu.add_icon_item(EditorInterface.get_editor_theme().get_icon(&"Edit", &"EditorIcons"), "Manage Members", ACTION_MANAGE_MEMBERS)
	actions[ACTION_MANAGE_MEMBERS] = _action_manage_members.bind(graph_node)
	menu.add_separator("Object Members")
	for member_type in graph_node._member_cache:
		for member_name in graph_node._member_cache[member_type]:
			var member: Dictionary = graph_node._member_cache[member_type][member_name]
			var submenu_label: String = member_type.capitalize() + " " + member_name
			var submenu := PopupMenu.new()
			menu.add_child(submenu)
			menu.add_submenu_node_item(submenu_label, submenu)

			submenu.add_item("Remove Member from View", ACTION_MEMBER_REMOVE)
			submenu.id_pressed.connect(_member_submenu_id_pressed.bind(member))


func _action_manage_members(graph_node: GraphNode) -> void:
	var selected_nodes := []

	for name in editor.selected_nodes:
		var node := editor.get_node_or_null(NodePath(name))
		if !is_instance_of(node, SceneObjectGraphNode):
			continue
		selected_nodes.append(node)
	if selected_nodes.size() == 1:
		graph_node.manage_members()
	else:
		EditorInterface.get_editor_toaster().push_toast("Managing members of multiple nodes is not currently supported.\nOnly editing '%s'" % [graph_node.get_object_name()], EditorToaster.SEVERITY_INFO)
		graph_node.manage_members()


func _member_submenu_id_pressed(id: int, member: Dictionary) -> void:
	for name in editor.selected_nodes:
		var node := editor.get_node_or_null(NodePath(name))
		if !is_instance_of(node, SceneObjectGraphNode):
			continue
		var graph_node: GraphNode = node
		match id:
			ACTION_MEMBER_REMOVE:
				editor.current_view.transactions.remove_object_view_member(graph_node.object_type, graph_node.get_object(), member.member_type, member.member_name)
