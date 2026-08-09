@tool
extends RefCounted

static var SceneObjectGraphNode : Script = preload("res://addons/signal-graphs/editor/elements/scene_object_graph_node.gd");

const OBJECT_TYPE_NODE := "node";

var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	editor.selection_changed_with_script.connect(_on_selection_changed_with_script);
	editor.delete_nodes_request.connect(_on_delete_nodes_request);
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["configure_capabilities","populate_graph_nodes_from_view","drag_and_drop","view_object_serialization"];

### CAPABILITY: configure_capabilities
func configure_capabilities() -> void:
	editor.hooks.register_capability("initialize_object_graph_node", [&"initialize_object_graph_node"] as Array[StringName]);
	editor.hooks.register_capability("create_object_graph_node_slots", [&"create_object_graph_node_slots"] as Array[StringName]);
	editor.hooks.register_capability("draw_object_graph_node_port", [&"draw_object_graph_node_port"] as Array[StringName]);
	
### CAPABILITY: view_object_serialization
func get_supported_view_object_types() -> Array[String]:
	return [OBJECT_TYPE_NODE];

func view_object_to_runtime_key(object_type : String, obj : Object) -> Variant:
	return obj.get_instance_id();

func runtime_key_to_view_object(object_type : String, key : Variant) -> Object:
	return instance_from_id(key as int);

func runtime_key_serialize(object_type : String, key : Variant) -> Variant:
	var node := instance_from_id(key as int) as Node;
	if !node: return null;
	var scene_root := editor.scene_root;
	if scene_root == node || scene_root.is_ancestor_of(node):
		return editor.scene_root.get_path_to(node);
	else:
		return null;

func runtime_key_deserialize(object_type : String, serialized : Variant) -> Variant:
	var path := serialized as NodePath;
	if !path: return null;
	var node := editor.scene_root.get_node_or_null(path);
	if !node: return null;
	return node.get_instance_id();

### CAPABILITY: populate_graph_nodes_from_view

func populate_graph_nodes_from_view() -> void:
	var scene_object_views := editor.current_view.get_scene_object_views(OBJECT_TYPE_NODE);
	for runtime_key in scene_object_views:
		var obj : Object = runtime_key_to_view_object(OBJECT_TYPE_NODE, runtime_key);
		if !obj: continue;
		
		var existing := editor.current_view.get_graph_node_for_object(OBJECT_TYPE_NODE, obj);
		var graph_node : GraphNode;
		if existing:
			graph_node = existing;
			_disconnect_all_for_node(existing.name);
		else:
			graph_node = editor.current_view.instantiate_graph_node_for_object(OBJECT_TYPE_NODE, obj, SceneObjectGraphNode);
			if graph_node:
				editor.add_child(graph_node);
		
		graph_node.update_from_view();
	
	for child : Node in editor.get_children():
		if !is_instance_of(child, SceneObjectGraphNode):
			continue;
		var obj : Object = child.get_object();
		if !editor.current_view.has_object_view(OBJECT_TYPE_NODE, obj):
			editor.remove_child(child);
			child.queue_free();

func _disconnect_all_for_node(name : StringName) -> void:
	for connection in editor.get_connection_list_from_node(name):
		editor.disconnect_node(connection.from_node, connection.from_port, connection.to_node, connection.to_port);

### CAPABILITY: drag_and_drop
func can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var data_dict : Dictionary = data;
	if data_dict["type"] != "nodes": return false;
	return true;
	
func drop_data(at_position: Vector2, data: Variant) -> void:
	var data_dict : Dictionary = data;
	if data_dict["type"] != "nodes": return;

	editor.set_selected(null);
	
	for node_path : NodePath in data_dict["nodes"]:
		var node := editor.get_node_or_null(node_path);
		if !node: continue;
		editor.current_view.transactions.add_object_view(OBJECT_TYPE_NODE, node, editor.local_to_graph_position(at_position));

### DELETING

func _on_delete_nodes_request(graph_nodes : Array[StringName]) -> void:
	for graph_node_name : StringName in graph_nodes:
		var graph_node := editor.get_node_or_null(NodePath(graph_node_name));
		if !is_instance_of(graph_node, SceneObjectGraphNode): continue;
		var obj : Object = graph_node.get_object();
		editor.current_view.transactions.remove_object_view(OBJECT_TYPE_NODE, obj);

### SELECTION

func _on_selection_changed_with_script(script : Script, nodes : Array[Node]) -> void:
	if script == SceneObjectGraphNode:
		select_nodes(nodes.map(func (graph_node : GraphNode):
			return graph_node.get_object();
		));

func select_nodes(nodes : Array) -> void:
	EditorInterface.get_selection().clear();
	for node in nodes:
		if node is not Node: continue;
		if !node.is_inside_tree(): continue;
		EditorInterface.get_selection().add_node(node);
