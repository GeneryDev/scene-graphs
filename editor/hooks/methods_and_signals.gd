@tool
extends RefCounted

static var SceneObjectGraphNode : Script = preload("res://addons/signal-graphs/editor/elements/scene_object_graph_node.gd");

const OBJECT_TYPE_NODE := "node";
const MEMBER_TYPE_METHOD := "methods";
const MEMBER_TYPE_SIGNAL := "signals";

signal scene_connections_updated();

var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
	scene_connections_updated.connect(_on_scene_connections_updated);
	connect_interface_signals();
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["configure_port_types","populate_graph_node_connections"];
	
### CAPABILITY: configure_ports
func configure_port_types() -> void:
	editor.register_port_type(&"method");
	editor.register_port_type(&"signal");
	editor.register_port_type(&"add_signal");
	editor.register_port_type(&"add_method");
	editor.add_valid_connection_type(editor.port_type(&"signal"), editor.port_type(&"method"));

func _on_scene_connections_updated() -> void:
	populate_graph_node_connections();
	
func notify_scene_connections_updated() -> void:
	scene_connections_updated.emit();
	
func _disconnect_all_for_node(name : StringName) -> void:
	for connection in editor.get_connection_list_from_node(name):
		editor.disconnect_node(connection.from_node, connection.from_port, connection.to_node, connection.to_port);

func populate_graph_node_connections() -> void:
	for child : Node in editor.get_children():
		if !is_instance_of(child, SceneObjectGraphNode):
			continue;
		
		var graph_node : GraphNode = child;
		
		var obj : Object = child.get_object();
		
		# Remove all incoming connections -- we'll re-add them after
		for connection in editor.get_connection_list_from_node(graph_node.name):
			if connection.to_node == graph_node.name:
				editor.disconnect_node(connection.from_node, connection.from_port, connection.to_node, connection.to_port);
		
		for connection in obj.get_incoming_connections():
			var sgnal : Signal = connection["signal"];
			var callable : Callable = connection["callable"];
			
			var flags : ConnectFlags = connection["flags"];
			if(flags & CONNECT_PERSIST) == 0: continue;
			var owner := sgnal.get_object();
			if owner is not Node:
				continue;
				
			var owner_graph_node := editor.current_view.get_graph_node_for_object(OBJECT_TYPE_NODE, owner);
			if !owner_graph_node:
				continue;
			
			var from_port : int = owner_graph_node.get_member_port_id(MEMBER_TYPE_SIGNAL, sgnal.get_name());
			var to_port : int = graph_node.get_member_port_id(MEMBER_TYPE_METHOD, callable.get_method());
		
			if from_port == editor.port_type(&"") || to_port == editor.port_type(&""):
				continue;
			
			editor.connect_node(owner_graph_node.name, from_port, graph_node.name, to_port);
	editor.notify_connections_changed();

### INTERFACE SIGNALS

func connect_interface_signals() -> void:
	editor.connection_drag_started.connect(_on_connection_drag_started);
	editor.connection_request.connect(_on_connection_request);
	editor.disconnection_request.connect(_on_disconnection_request);
	editor.connections_changed.connect(_on_connections_changed);
	
func _on_connection_drag_started(from_node_name : StringName, from_port : int, is_output : bool) -> void:
	var node := editor.get_node_or_null(NodePath(from_node_name));
	if !node: return;
	
	var graph_node : GraphNode = node;
	var slot_type : int;
	if is_output:
		slot_type = graph_node.get_output_port_type(from_port);
	else:
		slot_type = graph_node.get_input_port_type(from_port);
		
	var port_type_add_method := editor.port_type(&"add_method");
	var port_type_add_signal := editor.port_type(&"add_signal");
	
	match slot_type:
		port_type_add_method:
			editor.force_connection_drag_end();
			SignalGraphEditor.Selector.show(graph_node.get_object(), SignalGraphEditor.Selector.TAB_METHODS, Callable(graph_node, &"method_add_requested"), Callable(graph_node, &"signal_add_requested"));
		port_type_add_signal:
			editor.force_connection_drag_end();
			SignalGraphEditor.Selector.show(graph_node.get_object(), SignalGraphEditor.Selector.TAB_SIGNALS, Callable(graph_node, &"method_add_requested"), Callable(graph_node, &"signal_add_requested"));

func _on_connection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	editor.transactions.begin_transaction("Connect signal", UndoRedo.MergeMode.MERGE_ALL, null, false);
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var callable := Callable(to_object, to_graph_node.get_member_from_port_id(MEMBER_TYPE_METHOD, to_port).member_name);
	var signal_name : StringName = from_graph_node.get_member_from_port_id(MEMBER_TYPE_SIGNAL, from_port).member_name;
	editor.transactions.connect_signal(from_object, signal_name, callable, CONNECT_PERSIST, false);
	editor.transactions.undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	editor.transactions.undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	editor.transactions.end_transaction();

func _on_disconnection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	editor.transactions.begin_transaction("Disconnect signal", UndoRedo.MergeMode.MERGE_ALL, null, false);
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var callable := Callable(to_object, to_graph_node.get_member_from_port_id(MEMBER_TYPE_METHOD, to_port).member_name);
	var signal_name : StringName = from_graph_node.get_member_from_port_id(MEMBER_TYPE_SIGNAL, from_port).member_name;
	editor.transactions.disconnect_signal(from_object, signal_name, callable, false);
	editor.transactions.undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	editor.transactions.undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	editor.transactions.end_transaction();

func _on_connections_changed() -> void:
	for child : Node in editor.get_children():
		if !is_instance_of(child, SceneObjectGraphNode):
			continue;
		child.update_connection_cache();
		