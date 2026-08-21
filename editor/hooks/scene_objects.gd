@tool
extends RefCounted

const META_NAME_EXTENSION := &"_scene_objects_extension"
const ACTION_MANAGE_MEMBERS: int = 200
const ACTION_MEMBER_REMOVE: int = 210

static var SceneObjectGraphNode: Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd")

var editor: SceneGraphEditor
var _connection_dragging_wildcard := false
var _connection_dragging_wildcard_type := 0
var _connection_dragging_wildcard_graph_node: GraphNode = null
var _connection_dragging_wildcard_cursor_pos := Vector2.ZERO


func _init(editor: SceneGraphEditor):
	self.editor = editor
	editor.connection_drag_started.connect(_on_connection_drag_started)
	editor.connection_drag_ended.connect(_on_connection_drag_ended)


func get_scene_graph_capabilities() -> Array[String]:
	return ["configure_capabilities", "configure_port_types", "populate_popup_menu"]


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


### CAPABILITY: populate_popup_menu
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
