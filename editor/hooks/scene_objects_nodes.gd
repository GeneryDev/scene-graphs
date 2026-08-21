@tool
extends RefCounted

const OBJECT_TYPE_NODE := "node"

static var SceneObjectGraphNode: Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd")

var editor: SceneGraphEditor


func _init(editor: SceneGraphEditor):
	self.editor = editor
	editor.selection_changed_with_script.connect(_on_selection_changed_with_script)
	editor.delete_nodes_request.connect(_on_delete_nodes_request)


func get_scene_graph_capabilities() -> Array[String]:
	return ["populate_graph_nodes_from_view", "drag_and_drop", "handle_view_object_types"]


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
			graph_node = editor.current_view.create_graph_node_for_object(OBJECT_TYPE_NODE, obj, SceneObjectGraphNode)

		graph_node.update_from_view()

	for child: Node in editor.get_children():
		if !is_instance_of(child, SceneObjectGraphNode):
			continue
		if child.object_type != OBJECT_TYPE_NODE:
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


func select_nodes(nodes: Array) -> void:
	EditorInterface.get_selection().clear()
	for node in nodes:
		if node is not Node:
			continue
		if !node.is_inside_tree():
			continue
		EditorInterface.get_selection().add_node(node)


### DELETING
func _on_delete_nodes_request(graph_nodes: Array[StringName]) -> void:
	for graph_node_name: StringName in graph_nodes:
		var graph_node := editor.get_node_or_null(NodePath(graph_node_name))
		if !is_instance_of(graph_node, SceneObjectGraphNode):
			continue
		if !graph_node.object_type != OBJECT_TYPE_NODE:
			continue
		var obj: Object = graph_node.get_object()
		editor.current_view.transactions.remove_object_view(OBJECT_TYPE_NODE, obj)


### SELECTION
func _on_selection_changed_with_script(script: Script, nodes: Array[Node]) -> void:
	if script == SceneObjectGraphNode:
		select_nodes(nodes.map(_map_graph_node_to_object))


func _map_graph_node_to_object(graph_node: GraphNode) -> Object:
	return graph_node.get_object()
