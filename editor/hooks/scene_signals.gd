@tool
extends RefCounted

static var ObjectSignalsNode : Script = preload("res://addons/signal-graphs/editor/elements/object_signals_graph_node.gd");
static var ObjectSignalConnectionElement : Script = preload("res://addons/signal-graphs/editor/elements/object_signal_connection_graph_element.gd");
static var SignalConnectionPropertyEdit : Script = preload("res://addons/signal-graphs/editor/hooks/signal_connection_property_edit.gd");

const OBJECT_TYPE_NODE := "node";

signal scene_connections_updated();

var editor : SignalGraphEditor;
var _connections_with_elements : Array[Dictionary] = [];

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
	editor.view.view_updated.connect(_on_view_updated);
	scene_connections_updated.connect(_on_scene_connections_updated);
	editor.connection_line_cache_invalidated.connect(_invalidate_line_end_cache);
	connect_interface_signals();
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["drag_and_drop","configure_port_types","override_connection_lines","view_object_serialization"];
	
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
	return editor.scene_root.get_path_to(node);

func runtime_key_deserialize(object_type : String, serialized : Variant) -> Variant:
	var path := serialized as NodePath;
	if !path: return null;
	var node := editor.scene_root.get_node_or_null(path);
	if !node: return null;
	return node.get_instance_id();
	
### CAPABILITY: configure_ports
func configure_port_types() -> void:
	editor.register_port_type(&"method");
	editor.register_port_type(&"signal");
	editor.register_port_type(&"add_signal");
	editor.register_port_type(&"add_method");
	editor.add_valid_connection_type(editor.port_type(&"signal"), editor.port_type(&"method"));

func _on_view_updated() -> void:
	_populate_graph_nodes_from_view();
	_populate_graph_node_members_from_view();
	_populate_node_connections();

func _on_scene_connections_updated() -> void:
	_populate_node_connections();
	
func notify_scene_connections_updated() -> void:
	scene_connections_updated.emit();
	
func _populate_graph_nodes_from_view() -> void:
	var scene_object_views := editor.view.get_scene_object_views(OBJECT_TYPE_NODE);
	for runtime_key in scene_object_views:
		var obj : Object = runtime_key_to_view_object(OBJECT_TYPE_NODE, runtime_key);
		if !obj: continue;
		
		var existing := editor.view.get_graph_node_for_object(OBJECT_TYPE_NODE, obj);
		var graph_node : GraphNode;
		if existing:
			graph_node = existing;
			_disconnect_all_for_node(existing.name);
		else:
			graph_node = editor.view.instantiate_graph_node_for_object(OBJECT_TYPE_NODE, obj, ObjectSignalsNode);
			if graph_node:
				editor.add_child(graph_node);
	
	for child : Node in editor.get_children():
		if !is_instance_of(child, ObjectSignalsNode):
			continue;
		var obj : Object = child.get_object();
		if !editor.view.has_object_view(OBJECT_TYPE_NODE, obj):
			editor.remove_child(child);
			child.queue_free();
	
func _populate_graph_node_members_from_view() -> void:
	var scene_object_views := editor.view.get_scene_object_views(OBJECT_TYPE_NODE);
	for runtime_key in scene_object_views:
		var obj : Object = runtime_key_to_view_object(OBJECT_TYPE_NODE, runtime_key);
		if !obj: continue;
		
		_update_graph_node_for_object_from_view(obj);
	
func _update_graph_node_for_object_from_view(obj : Object) -> void:
	var graph_node := editor.view.get_graph_node_for_object(OBJECT_TYPE_NODE, obj);
	if !graph_node: return;
	
	graph_node.update_from_view();

func _disconnect_all_for_node(name : StringName) -> void:
	for connection in editor.get_connection_list_from_node(name):
		editor.disconnect_node(connection.from_node, connection.from_port, connection.to_node, connection.to_port);

func _populate_node_connections() -> void:
	for child : Node in editor.get_children():
		if !is_instance_of(child, ObjectSignalsNode):
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
				
			var owner_graph_node := editor.view.get_graph_node_for_object(OBJECT_TYPE_NODE, owner);
			if !owner_graph_node:
				continue;
			
			var from_port : int = owner_graph_node.get_signal_port_id(sgnal.get_name());
			var to_port : int = graph_node.get_method_port_id(callable.get_method());
		
			if from_port == editor.port_type(&"") || to_port == editor.port_type(&""):
				continue;
			
			editor.connect_node(owner_graph_node.name, from_port, graph_node.name, to_port);
	editor.notify_connections_changed();

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
		editor.view.transactions.add_object_view(OBJECT_TYPE_NODE, node, editor.utility.local_to_graph_position(at_position));

### INTERFACE SIGNALS

func connect_interface_signals() -> void:
	editor.connection_drag_started.connect(_on_connection_drag_started);
	editor.connection_request.connect(_on_connection_request);
	editor.disconnection_request.connect(_on_disconnection_request);
	editor.connections_changed.connect(_on_connections_changed);
	editor.connections_layer.draw.connect(_on_connections_draw);
	editor.selection_changed_with_script.connect(_on_selection_changed_with_script);
	editor.begin_node_move.connect(_on_begin_node_move);
	editor.delete_nodes_request.connect(_on_delete_nodes_request);
	editor.end_node_move.connect(_on_end_node_move);
	editor.visibility_changed.connect(_on_visibility_changed);
	
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
	if !is_instance_of(from_graph_node, ObjectSignalsNode): return;
	if !is_instance_of(to_graph_node, ObjectSignalsNode): return;
	
	editor.transactions.begin_transaction("Connect signal", UndoRedo.MergeMode.MERGE_ALL, null, false);
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var callable := Callable(to_object, to_graph_node.get_method_port_name(to_port));
	var signal_name : StringName = from_graph_node.get_signal_port_name(from_port);
	editor.transactions.connect_signal(from_object, signal_name, callable, CONNECT_PERSIST, false);
	editor.transactions.undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	editor.transactions.undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	editor.transactions.end_transaction();

func _on_disconnection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, ObjectSignalsNode): return;
	if !is_instance_of(to_graph_node, ObjectSignalsNode): return;
	
	editor.transactions.begin_transaction("Disconnect signal", UndoRedo.MergeMode.MERGE_ALL, null, false);
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var callable := Callable(to_object, to_graph_node.get_method_port_name(to_port));
	var signal_name : StringName = from_graph_node.get_signal_port_name(from_port);
	editor.transactions.disconnect_signal(from_object, signal_name, callable, false);
	editor.transactions.undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	editor.transactions.undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	editor.transactions.end_transaction();

### DELETING

func _on_delete_nodes_request(graph_nodes : Array[StringName]) -> void:
	for graph_node_name : StringName in graph_nodes:
		var graph_node := editor.get_node_or_null(NodePath(graph_node_name));
		if !is_instance_of(graph_node, ObjectSignalsNode): continue;
		var obj : Object = graph_node.get_object();
		editor.view.transactions.remove_object_view(OBJECT_TYPE_NODE, obj);

### CONNECTIONS

func _on_connections_draw() -> void:
	for cached_connection : Dictionary in _connections_with_elements:
		if !is_instance_valid(cached_connection.graph_element): continue;
		
		_reposition_connection_element(cached_connection);

func _on_connections_changed() -> void:
	_refresh_connection_elements();

func _on_visibility_changed() -> void:
	if editor.is_visible_in_tree():
		call_deferred(&"_refresh_connection_elements");

func _refresh_connection_elements() -> void:
	var intended_index := editor.connections_layer.get_index()+1;
	
	for cached_connection in _connections_with_elements:
		cached_connection.still_valid = false;
	
	for connection : Dictionary in editor.connections:
		var from_graph_node : GraphNode = editor.get_node_or_null(NodePath(connection.from_node));
		var to_graph_node : GraphNode = editor.get_node_or_null(NodePath(connection.to_node));
		if !is_instance_of(from_graph_node, ObjectSignalsNode): continue;
		if !is_instance_of(to_graph_node, ObjectSignalsNode): continue;
		if connection.from_port >= from_graph_node.get_output_port_count(): continue;
		if connection.to_port >= to_graph_node.get_input_port_count(): continue;
		if from_graph_node.get_output_port_type(connection.from_port) != editor.port_type(&"signal"): continue;
		if to_graph_node.get_input_port_type(connection.to_port) != editor.port_type(&"method"): continue;
		
		var matching_cached_connection : Dictionary;
		
		for cached_connection in _connections_with_elements:
			if cached_connection.connection != connection: continue;
			if !is_instance_valid(cached_connection.graph_element): continue;
			if cached_connection.graph_element.is_queued_for_deletion(): continue;
			cached_connection.still_valid = true;
			matching_cached_connection = cached_connection;
		
		if !matching_cached_connection:
			var graph_element : GraphElement = ObjectSignalConnectionElement.new();
			graph_element.setup(connection, editor);
			editor.connections_layer.add_sibling(graph_element, false);
			matching_cached_connection = {
				"connection": connection,
				"graph_element": graph_element,
				"still_valid": true,
				"from_graph_node": from_graph_node,
				"to_graph_node": to_graph_node
			};
			_connections_with_elements.push_back(matching_cached_connection);
		
		editor.move_child(matching_cached_connection.graph_element, intended_index);
		_reposition_connection_element(matching_cached_connection);
	
	for i in range(_connections_with_elements.size()-1, -1, -1):
		var cached_connection := _connections_with_elements[i];
		if !cached_connection.still_valid:
			if is_instance_valid(cached_connection.graph_element):
				if cached_connection.graph_element.get_parent():
					editor.remove_child(cached_connection.graph_element);
				cached_connection.graph_element.queue_free();
			_connections_with_elements.remove_at(i);

func _reposition_connection_element(cached_connection : Dictionary) -> void:
	var connection : Dictionary = cached_connection.connection;
	var graph_element : GraphElement = cached_connection.graph_element;
	var from_graph_node : GraphNode = cached_connection.from_graph_node;
	var to_graph_node : GraphNode = cached_connection.to_graph_node;
	if !from_graph_node || !to_graph_node: return;
	var line_from := (from_graph_node.get_output_port_position(connection.from_port) + from_graph_node.position_offset);
	var line_to := (to_graph_node.get_input_port_position(connection.to_port) + to_graph_node.position_offset);
	var line : PackedVector2Array = editor.get_connection_line(line_from, line_to);
	var mid_point_straight := (line_from + line_to) / 2;
	var mid_point := line[line.size()/2] if line.size() % 2 == 1 else (line[line.size()/2-1]+line[line.size()/2])/2;
	
	var before_mid_point := line[line.size()/2-1] if line.size() % 2 == 1 else line[line.size()/2-1];
	var after_mid_point := line[line.size()/2] if line.size() % 2 == 1 else line[line.size()/2];
	var new_position : Vector2;
	var rotation : float = 0;
	if graph_element.get_current_mid_point_offset():
		new_position = mid_point_straight + graph_element.mid_point_offset;
		rotation = before_mid_point.angle_to_point(after_mid_point);
	else:
		new_position = mid_point;
		rotation = (line_to - line_from).angle();
	graph_element.reposition(new_position, rotation);
	graph_element.update_connection_info();

### SELECTION

func _on_selection_changed_with_script(script : Script, nodes : Array[Node]) -> void:
	if script == ObjectSignalsNode:
		select_nodes(nodes.map(func (graph_node : GraphNode):
			return graph_node.get_object();
		));
	elif script == ObjectSignalConnectionElement:
		select_connections(nodes.map(func (n : Node):
			for cached_connection : Dictionary in _connections_with_elements:
				if cached_connection.graph_element == n:
					return cached_connection.connection;
			return null;
		).filter(func (c : Dictionary) -> bool:
			var from_graph_node := editor.get_node_or_null(NodePath(c.from_node));
			var to_graph_node := editor.get_node_or_null(NodePath(c.to_node));
			return from_graph_node != null && to_graph_node != null;
		));
	elif script == null:
		if is_instance_of(EditorInterface.get_inspector().get_edited_object(), SignalConnectionPropertyEdit):
			EditorInterface.get_inspector().edit(null);

func select_nodes(nodes : Array) -> void:
	EditorInterface.get_selection().clear();
	for node in nodes:
		if node is not Node: continue;
		if !node.is_inside_tree(): continue;
		EditorInterface.get_selection().add_node(node);

func select_connections(connections : Array) -> void:
	EditorInterface.get_selection().clear();
	var edit_resource : Resource = SignalConnectionPropertyEdit.new();
	edit_resource.setup(editor, connections);
	EditorInterface.inspect_object(edit_resource);

### CAPABILITY: override_connection_lines

func get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var cached_connection := _find_connection_from_line_ends(from_position, to_position);
	if cached_connection:
		if cached_connection.graph_element.get_current_mid_point_offset() != Vector2.ZERO:
			return get_adjusted_connection_line(from_position, to_position, cached_connection.graph_element);
	return [];

func get_adjusted_connection_line(from_position: Vector2, to_position: Vector2, connection_graph_element : GraphElement) -> PackedVector2Array:
	var x_diff : float = (to_position.x - from_position.x);
	var cp_offset : float = x_diff * 0.3;
	if x_diff < 0:
		cp_offset *= -1;
		
	var mid_point := (from_position + to_position) / 2;

	var curve := Curve2D.new();
	curve.add_point(from_position);
	curve.set_point_out(0, Vector2(cp_offset, 0));
	curve.add_point(mid_point + connection_graph_element.get_current_mid_point_offset() * editor.zoom);
	curve.set_point_in(1, -(to_position - from_position) * 0.25);
	curve.set_point_out(1, (to_position - from_position) * 0.25);
	curve.add_point(to_position);
	curve.set_point_in(2, Vector2(-cp_offset, 0));

	return curve.tessellate(5, 2.0);

var _line_end_cache_time : int;
var _line_end_cache : Dictionary;

func _find_connection_from_line_ends(from_position: Vector2, to_position: Vector2) -> Dictionary:
	var now := Engine.get_process_frames();
	if _line_end_cache_time != now:
		_line_end_cache_time = now;
		_update_line_end_cache();
	var cache_entry = _line_end_cache.get(_get_line_end_cache_key(from_position));
	if cache_entry:
		for cached_connection : Dictionary in cache_entry:
			var line_end_cache : Array = cached_connection.line_ends;
			if from_position.distance_squared_to(line_end_cache[0]) > 5:
				continue;
			if to_position.distance_squared_to(line_end_cache[1]) > 5:
				continue;
	
			return cached_connection;
	return {};

func _get_line_end_cache_key(from_position : Vector2) -> int:
	return int(from_position.y) / 100;

func _invalidate_line_end_cache() -> void:
	_line_end_cache_time = 0;

func _update_line_end_cache() -> void:
	_line_end_cache.clear();
	for cached_connection : Dictionary in _connections_with_elements:
		var connection = cached_connection.connection;
		cached_connection.line_ends = [Vector2(0,0),Vector2(0,0)];
		
		if !is_instance_valid(cached_connection.graph_element): continue;

		var from_graph_node : GraphNode = cached_connection.from_graph_node;
		var to_graph_node : GraphNode = cached_connection.to_graph_node;
		if !from_graph_node || !to_graph_node:
			continue;
		if connection.from_port >= from_graph_node.get_output_port_count(): continue;
		if connection.to_port >= to_graph_node.get_input_port_count(): continue;
		var from := (from_graph_node.get_output_port_position(connection.from_port) + from_graph_node.position_offset) * editor.zoom;
		var to := (to_graph_node.get_input_port_position(connection.to_port) + to_graph_node.position_offset) * editor.zoom;
		cached_connection.line_ends[0] = from;
		cached_connection.line_ends[1] = to;
		
		var cache_key := _get_line_end_cache_key(from);

		if !_line_end_cache.has(cache_key):
			_line_end_cache[cache_key] = [cached_connection];
		else:
			_line_end_cache[cache_key].append(cached_connection);

func _on_begin_node_move() -> void:
	for cached_connection : Dictionary in _connections_with_elements:
		if !is_instance_valid(cached_connection.graph_element): continue;
		if cached_connection.graph_element.selected:
			cached_connection.graph_element.dragging_reference_mid_point = cached_connection.graph_element.position_offset - cached_connection.graph_element.mid_point_offset;
			
			var neighbor_selected_count := 0;
			if cached_connection.graph_element.get_from_graph_node() && cached_connection.graph_element.get_from_graph_node().selected: neighbor_selected_count += 1;
			if cached_connection.graph_element.get_to_graph_node() && cached_connection.graph_element.get_to_graph_node().selected: neighbor_selected_count += 1;
			
			cached_connection.graph_element.dragging_mid_point_influence = 1 - neighbor_selected_count * 0.5;

func _on_end_node_move() -> void:
	for cached_connection : Dictionary in _connections_with_elements:
		if !is_instance_valid(cached_connection.graph_element): continue;
		if cached_connection.graph_element.selected:
			cached_connection.graph_element.apply_mid_point_offset_change();
