@tool
extends RefCounted

static var ObjectSignalsNode : Script = preload("res://addons/signal-graphs/editor/elements/object_signals_graph_node.gd");
const META_NAME_GRAPH_DATA := "_signal_graph_data";

var editor : SignalGraphEditor;

func _init(editor : GraphEdit):
	self.editor = editor;
	connect_interface_signals();
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["populate","drag_and_drop","configure_port_types","save"];
	
### CAPABILITY: configure_ports
func configure_port_types() -> void:
	editor.register_port_type(&"method");
	editor.register_port_type(&"signal");
	editor.register_port_type(&"add_signal");
	editor.register_port_type(&"add_method");
	editor.add_valid_connection_type(editor.port_type(&"signal"), editor.port_type(&"method"));

### CAPABILITY: populate

func populate_from_scene(scene_root : Node) -> void:
	editor.scene_root = scene_root;
	editor._use_context_position = false;
	_add_graph_node_for_node(scene_root, true, true)
	_populate_node_connections();

func get_graph_node_for_node(node : Node) -> GraphNode:
	return editor.get_node_or_null(NodePath(str(node.get_instance_id()))) as GraphNode;
	
func _create_graph_node_for_node(node : Node, require_connections : bool = false) -> GraphNode:
	var graph_node : GraphNode = null;
	
	if node.owner == editor.scene_root || node == editor.scene_root:
		graph_node = ObjectSignalsNode.new() as GraphNode;
		var saved_data : Dictionary = node.get_meta(META_NAME_GRAPH_DATA) if node.has_meta(META_NAME_GRAPH_DATA) else {};
		var any_connections : bool = graph_node.setup(node, saved_data, editor);
		if require_connections && !any_connections:
			graph_node.queue_free();
			graph_node = null;
		else:
			editor.position_new_element(graph_node);
	
	return graph_node;
	
func _add_graph_node_for_node(node : Node, recursive : bool = false, require_connections : bool = false) -> GraphNode:
	var graph_node := _create_graph_node_for_node(node, require_connections);
	if graph_node:
		editor.add_child(graph_node);
	
	if recursive:
		for child in node.get_children():
			_add_graph_node_for_node(child, true, require_connections);
	
	return graph_node;

func _populate_node_connections() -> void:
	for child : Node in editor.get_children():
		if child.get_script() != ObjectSignalsNode:
			continue;
		
		var graph_node : GraphNode = child;
		
		if !child.has_method(&"get_object"):
			continue;
		
		var node : Node = child.call(&"get_object");
		if !node:
			continue;
		
		for connection in node.get_incoming_connections():
			var sgnal : Signal = connection["signal"];
			var callable : Callable = connection["callable"];
			
			var flags : ConnectFlags = connection["flags"];
			if(flags & CONNECT_PERSIST) == 0: continue;
			var owner := sgnal.get_object();
			if owner is not Node:
				continue;
				
			var owner_graph_node = get_graph_node_for_node(owner);
			if !owner_graph_node:
				continue;
			
			var from_port : int = owner_graph_node.get_signal_port_id(sgnal.get_name());
			var to_port : int = graph_node.get_method_port_id(callable.get_method());
		
			if from_port == editor.port_type(&"") || to_port == editor.port_type(&""):
				continue;
			
			editor.connect_node(owner_graph_node.name, from_port, graph_node.name, to_port);
			
### CAPABILITY: save
func save_to_scene(scene_root : Node) -> void:
	for child : Node in editor.get_children():
		if child.get_script() != ObjectSignalsNode:
			continue;
		#TODO hooks?
		var represented_object : Object = child.get_object();
		if !represented_object:
			continue;
		var save_data = child.get_save_data();
		represented_object.set_meta(META_NAME_GRAPH_DATA, save_data);

### CAPABILITY: drag_and_drop
func can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var data_dict : Dictionary = data;
	if data_dict["type"] != "nodes": return false;
	return true;
	
func drop_data(at_position: Vector2, data: Variant) -> void:
	var data_dict : Dictionary = data;
	if data_dict["type"] != "nodes": return;

	editor._context_position = at_position;
	editor._use_context_position = true;
	
	editor.set_selected(null);
	
	for node_path : NodePath in data_dict["nodes"]:
		var node := editor.get_node(node_path);
		if !node: continue;
		
		var instance_id := node.get_instance_id();
		var existing_graph_node : GraphNode = get_graph_node_for_node(node);
		
		if existing_graph_node:
			existing_graph_node.set_selected(true);
		else:
			var graph_node := _create_graph_node_for_node(node, false);
			graph_node.set_selected(true);
			editor.transactions.add_child(graph_node, true, true);

### INTERFACE SIGNALS

func connect_interface_signals() -> void:
	editor.connection_drag_started.connect(_on_connection_drag_started);
	editor.connection_request.connect(_on_connection_request);
	editor.disconnection_request.connect(_on_disconnection_request);
	
func _on_connection_drag_started(from_node_name : StringName, from_port : int, is_output : bool) -> void:
	var node := editor.get_node(NodePath(from_node_name));
	
	var graph_node : GraphNode = node;
	var slot : int;
	var slot_type : int;
	if is_output:
		slot = graph_node.get_output_port_slot(from_port);
		slot_type = graph_node.get_slot_type_right(slot);
	else:
		slot = graph_node.get_input_port_slot(from_port);
		slot_type = graph_node.get_slot_type_left(slot);
		
	var port_type_add_method = editor.port_type(&"add_method");
	var port_type_add_signal = editor.port_type(&"add_signal");
	
	match slot_type:
		port_type_add_method:
			editor.force_connection_drag_end();
			SignalGraphEditor.Selector.show(graph_node.get_object(), SignalGraphEditor.Selector.TAB_METHODS, Callable(graph_node, &"method_add_requested"), Callable(graph_node, &"signal_add_requested"));
		port_type_add_signal:
			editor.force_connection_drag_end();
			SignalGraphEditor.Selector.show(graph_node.get_object(), SignalGraphEditor.Selector.TAB_SIGNALS, Callable(graph_node, &"method_add_requested"), Callable(graph_node, &"signal_add_requested"));

func _on_connection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	editor.transactions.begin_transaction("Connect graph nodes", UndoRedo.MergeMode.MERGE_ALL, null, true);
	var from_node := editor.get_node(NodePath(from_node_name));
	var to_node := editor.get_node(NodePath(to_node_name));
	
	# TODO VERY HARDCODED, check graph node types
	var from_object : Object = from_node.get_object();
	var to_object : Object = to_node.get_object();
	var callable := Callable(to_object, to_node.get_method_port_name(to_port));
	var signal_name : StringName = from_node.get_signal_port_name(from_port);
	var undo_redo := EditorInterface.get_editor_undo_redo();
	editor.transactions.connect_signal(from_object, signal_name, callable, CONNECT_PERSIST, false);
	
	editor.transactions.connect_node(from_node_name, from_port, to_node_name, to_port, false);
	editor.transactions.end_transaction();

func _on_disconnection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	editor.transactions.begin_transaction("Disconnect graph nodes", UndoRedo.MergeMode.MERGE_ALL, null, true);
	var from_node := editor.get_node(NodePath(from_node_name));
	var to_node := editor.get_node(NodePath(to_node_name));
	
	# TODO VERY HARDCODED, check graph node types
	var from_object : Object = from_node.get_object();
	var to_object : Object = to_node.get_object();
	var callable := Callable(to_object, to_node.get_method_port_name(to_port));
	var signal_name : StringName = from_node.get_signal_port_name(from_port);
	var undo_redo := EditorInterface.get_editor_undo_redo();
	editor.transactions.disconnect_signal(from_object, signal_name, callable, false);
	
	editor.transactions.disconnect_node(from_node_name, from_port, to_node_name, to_port, false);
	editor.transactions.end_transaction();
