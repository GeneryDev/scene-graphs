@tool
extends RefCounted

static var ObjectSignalsNode : Script = preload("res://addons/signal-graphs/editor/elements/object_signals_graph_node.gd");
static var ObjectSignalConnectionElement : Script = preload("res://addons/signal-graphs/editor/elements/object_signal_connection_graph_element.gd");
static var SignalConnectionPropertyEdit : Script = preload("res://addons/signal-graphs/editor/hooks/signal_connection_property_edit.gd");

var editor : SignalGraphEditor;
var _connections_with_elements : Array[Dictionary] = [];

var view_interface : ViewInterface;

func _init(editor : GraphEdit):
	self.editor = editor;
	
	view_interface = ViewInterface.new(editor);
	view_interface.view_updated.connect(_on_view_updated);
	view_interface.scene_connections_updated.connect(_on_scene_connections_updated);
	connect_interface_signals();
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["populate","drag_and_drop","configure_port_types","save","override_connection_lines"];
	
### CAPABILITY: configure_ports
func configure_port_types() -> void:
	editor.register_port_type(&"method");
	editor.register_port_type(&"signal");
	editor.register_port_type(&"add_signal");
	editor.register_port_type(&"add_method");
	editor.add_valid_connection_type(editor.port_type(&"signal"), editor.port_type(&"method"));

### CAPABILITY: populate

func populate_from_scene(scene_root : Node) -> void:
	view_interface.clear_view();
	view_interface.update_node_views_with_rules(scene_root, true, false);
	view_interface.update_all_object_view_members_with_rules();
	
	view_interface.notify_view_updated();
	
func _on_view_updated() -> void:
	_populate_graph_nodes_from_view();
	_populate_graph_node_members_from_view();
	_populate_node_connections();

func _on_scene_connections_updated() -> void:
	_populate_node_connections();

func get_graph_node_for_node(node : Node) -> GraphNode:
	return editor.get_node_or_null(NodePath(str(node.get_instance_id()))) as GraphNode;
	
func _populate_graph_nodes_from_view() -> void:
	var scene_object_views := view_interface.get_scene_object_views();
	for instance_id in scene_object_views:
		if !is_instance_id_valid(instance_id): continue;
		var obj : Object = instance_from_id(instance_id);
		
		var existing := editor.get_node_or_null(NodePath(str(instance_id)));
		var graph_node : GraphNode;
		if existing:
			graph_node = existing;
			_disconnect_all_for_node(existing.name);
		else:
			graph_node = _create_graph_node_for_object_from_view(obj);
			if graph_node:
				editor.add_child(graph_node);
	
	for child : Node in editor.get_children():
		if !is_instance_of(child, ObjectSignalsNode):
			continue;
		var instance_id := int(child.name);
		if !scene_object_views.has(instance_id):
			editor.remove_child(child);
			child.queue_free();
	
func _populate_graph_node_members_from_view() -> void:
	var scene_object_views := view_interface.get_scene_object_views();
	for instance_id in scene_object_views:
		if !is_instance_id_valid(instance_id): continue;
		var obj : Object = instance_from_id(instance_id);
		
		_update_graph_node_for_object_from_view(obj);
	
func _create_graph_node_for_object_from_view(obj : Object) -> GraphNode:
	var obj_view := view_interface.get_object_view(obj);
	if !obj_view: return null;
	var graph_node : GraphNode = ObjectSignalsNode.new(obj, editor, view_interface);
	
	return graph_node;
	
func _update_graph_node_for_object_from_view(obj : Object) -> void:
	var graph_node := editor.get_node_or_null(NodePath(str(obj.get_instance_id())));
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
				
			var owner_graph_node := get_graph_node_for_node(owner);
			if !owner_graph_node:
				continue;
			
			var from_port : int = owner_graph_node.get_signal_port_id(sgnal.get_name());
			var to_port : int = graph_node.get_method_port_id(callable.get_method());
		
			if from_port == editor.port_type(&"") || to_port == editor.port_type(&""):
				continue;
			
			editor.connect_node(owner_graph_node.name, from_port, graph_node.name, to_port);
	editor.notify_connections_changed();
			
### CAPABILITY: save
func save_to_scene(scene_root : Node) -> void:
	for child : Node in editor.get_children():
		if !is_instance_of(child, ObjectSignalsNode):
			continue;
		var represented_object : Object = child.get_object();
		if !represented_object:
			continue;

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
		view_interface.transactions.add_object_view(node, editor.utility.local_to_graph_position(at_position));

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
	editor.transactions.undo_redo.add_do_method(view_interface, &"notify_scene_connections_updated");
	editor.transactions.undo_redo.add_undo_method(view_interface, &"notify_scene_connections_updated");
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
	editor.transactions.undo_redo.add_do_method(view_interface, &"notify_scene_connections_updated");
	editor.transactions.undo_redo.add_undo_method(view_interface, &"notify_scene_connections_updated");
	editor.transactions.end_transaction();

### DELETING

func _on_delete_nodes_request(graph_nodes : Array[StringName]) -> void:
	for graph_node_name : StringName in graph_nodes:
		var graph_node := editor.get_node_or_null(NodePath(graph_node_name));
		if !is_instance_of(graph_node, ObjectSignalsNode): continue;
		var obj : Object = graph_node.get_object();
		view_interface.transactions.remove_object_view(obj);

### CONNECTIONS

func _on_connections_draw() -> void:
	for cached_connection : Dictionary in _connections_with_elements:
		var connection = cached_connection.connection;
		if !is_instance_valid(cached_connection.graph_element): continue;
		
		_reposition_connection_element(connection, cached_connection.graph_element);

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
		
		var graph_element : GraphElement = null;
		
		for cached_connection in _connections_with_elements:
			if cached_connection.connection != connection: continue;
			if !is_instance_valid(cached_connection.graph_element): continue;
			if cached_connection.graph_element.is_queued_for_deletion(): continue;
			cached_connection.still_valid = true;
			graph_element = cached_connection.graph_element;
		
		if !graph_element:
			graph_element = ObjectSignalConnectionElement.new();
			graph_element.setup(connection, editor);
			editor.connections_layer.add_sibling(graph_element, false);
			_connections_with_elements.push_back({
				"connection": connection,
				"graph_element": graph_element,
				"still_valid": true
			});
		
		editor.move_child(graph_element, intended_index);
		_reposition_connection_element(connection, graph_element);
	
	for i in range(_connections_with_elements.size()-1, -1, -1):
		var cached_connection := _connections_with_elements[i];
		if !cached_connection.still_valid:
			if is_instance_valid(cached_connection.graph_element):
				if cached_connection.graph_element.get_parent():
					editor.remove_child(cached_connection.graph_element);
				cached_connection.graph_element.queue_free();
			_connections_with_elements.remove_at(i);

func _reposition_connection_element(connection : Dictionary, graph_element : GraphElement) -> void:
	var from_graph_node : GraphNode = editor.get_node_or_null(NodePath(connection.from_node));
	var to_graph_node : GraphNode = editor.get_node_or_null(NodePath(connection.to_node));
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

func _find_connection_from_line_ends(from_position: Vector2, to_position: Vector2) -> Dictionary:
	for cached_connection : Dictionary in _connections_with_elements:
		var connection = cached_connection.connection;
		if !is_instance_valid(cached_connection.graph_element): continue;
		
		var from_graph_node : GraphNode = editor.get_node_or_null(NodePath(connection.from_node));
		if !from_graph_node:
			continue;
		if connection.from_port >= from_graph_node.get_output_port_count(): continue;
		if from_position.distance_squared_to((from_graph_node.get_output_port_position(connection.from_port) + from_graph_node.position_offset) * editor.zoom) > 5:
			continue;
		var to_graph_node := editor.get_node_or_null(NodePath(connection.to_node));
		if !to_graph_node:
			continue;
		if connection.to_port >= to_graph_node.get_input_port_count(): continue;
		if to_position.distance_squared_to((to_graph_node.get_input_port_position(connection.to_port) + to_graph_node.position_offset) * editor.zoom) > 5:
			continue;
		
		return cached_connection;
	return {};

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

class ViewInterface extends RefCounted:
	signal view_updated();
	signal scene_connections_updated();
	
	var editor : SignalGraphEditor;
	var transactions : Transactions;
	
	func _init(editor : GraphEdit):
		self.editor = editor;
		transactions = Transactions.new(editor, self);
	
	func notify_view_updated() -> void:
		view_updated.emit();
	
	func notify_scene_connections_updated() -> void:
		scene_connections_updated.emit();
	
	func get_scene_object_views() -> Dictionary:
		var view := editor.view;
		if !view.has("scene_objects"):
			view["scene_objects"] = {};
		var scene_object_views : Dictionary = view["scene_objects"];
		return scene_object_views;
		
	func add_object_view(obj : Object) -> bool:
		if !obj: return false;
		var instance_id := obj.get_instance_id();
		var scene_object_views := get_scene_object_views();
		if scene_object_views.has(instance_id):
			# already added
			return false;
		var obj_view := {
			"methods": [],
			"signals": [],
		};
		scene_object_views[instance_id] = obj_view;
		return true;
		
	func set_object_view(obj : Object, obj_view : Dictionary) -> bool:
		if !obj: return false;
		var instance_id := obj.get_instance_id();
		var scene_object_views := get_scene_object_views();
		scene_object_views[instance_id] = obj_view;
		return true;
		
	func get_object_view(obj : Object) -> Dictionary:
		if !obj: return {};
		var instance_id := obj.get_instance_id();
		var scene_object_views := get_scene_object_views();
		if !scene_object_views.has(instance_id): return {};
		return scene_object_views[instance_id];
		
	func has_object_view(obj : Object) -> bool:
		if get_object_view(obj):
			return true;
		return false;
		
	func remove_object_view(obj : Object) -> bool:
		if !obj: return false;
		var instance_id := obj.get_instance_id();
		var scene_object_views := get_scene_object_views();
		if !scene_object_views.has(instance_id): return false;
		var removed = scene_object_views[instance_id];
		scene_object_views.erase(instance_id);
		return true;
	
	func add_object_view_method(obj : Object, method_name : StringName) -> bool:
		var obj_view := get_object_view(obj);
		if !obj_view:
			printerr("Failed to add object view method; no object view for " + str(obj));
			return false;
		var list : Array = obj_view.methods;
		if list.has(method_name): return false;
		list.append(method_name);
		return true;
		
	func has_object_view_method(obj : Object, method_name : StringName) -> bool:
		var obj_view := get_object_view(obj);
		if !obj_view:
			return false;
		var list : Array = obj_view.methods;
		return list.has(method_name);
	
	func remove_object_view_method(obj : Object, method_name : StringName) -> bool:
		var obj_view := get_object_view(obj);
		if !obj_view:
			printerr("Failed to remove object view method; no object view for " + str(obj));
			return false;
		var list : Array = obj_view.methods;
		if !list.has(method_name): return false;
		list.remove_at(list.find(method_name));
		return true;
	
	func add_object_view_signal(obj : Object, signal_name : StringName) -> bool:
		var obj_view := get_object_view(obj);
		if !obj_view:
			printerr("Failed to add object view signal; no object view for " + str(obj));
			return false;
		var list : Array = obj_view.signals;
		if list.has(signal_name): return false;
		list.append(signal_name);
		return true;
		
	func has_object_view_signal(obj : Object, signal_name : StringName) -> bool:
		var obj_view := get_object_view(obj);
		if !obj_view:
			return false;
		var list : Array = obj_view.signals;
		return list.has(signal_name);
	
	func remove_object_view_signal(obj : Object, signal_name : StringName) -> bool:
		var obj_view := get_object_view(obj);
		if !obj_view:
			printerr("Failed to remove object view signal; no object view for " + str(obj));
			return false;
		var list : Array = obj_view.signals;
		if !list.has(signal_name): return false;
		list.remove_at(list.find(signal_name));
		return true;
	
	func clear_view() -> void:
		var view := editor.view;
		view["scene_objects"] = {};
	
	func update_node_views_with_rules(node : Node, require_connections : bool = false, remove_unused : bool = false) -> bool:
		if !(node == editor.scene_root || node.owner == editor.scene_root): return false;
		
		var any_changes := update_object_view_with_rules(node, require_connections, remove_unused);
		
		for child in node.get_children():
			if update_node_views_with_rules(child, require_connections, remove_unused):
				any_changes = true;
		
		return any_changes;
	
	func update_object_view_with_rules(obj : Object, require_connections : bool = false, remove_unused : bool = false) -> bool:
		if !obj: return false;
		
		var used_methods := get_used_method_names(obj);
		var used_signals := get_used_signal_names(obj);
		
		if !(require_connections && !used_methods && !used_signals):
			return add_object_view(obj);
		elif remove_unused:
			return remove_object_view(obj);
		else:
			return false;
	
	func update_all_object_view_members_with_rules() -> bool:
		var object_views : Dictionary = get_scene_object_views();
		var any_changes := false;
		for instance_id in object_views:
			if !is_instance_id_valid(instance_id): continue;
			var obj : Object = instance_from_id(instance_id);
			
			var used_methods := get_used_method_names(obj);
			var used_signals := get_used_signal_names(obj);
			
			for method_name in used_methods:
				add_object_view_method(obj, method_name);
			for signal_name in used_signals:
				add_object_view_signal(obj, signal_name);
			
		
		return any_changes;
	
	func update_object_view_members_with_rules(obj : Object) -> bool:
		var any_changes := false;
		
		var used_methods := get_used_method_names(obj);
		var used_signals := get_used_signal_names(obj);
		
		for method_name in used_methods:
			if add_object_view_method(obj, method_name):
				any_changes = true;
		for signal_name in used_signals:
			if add_object_view_signal(obj, signal_name):
				any_changes = true;
		return any_changes;
	
	func get_used_method_names(obj : Object) -> Array:
		var list := [];
		
		var connected_method_names := SignalGraphEditor.Utility.get_connected_method_names(obj);
		
		for method_info in obj.get_method_list():
			var method_name := method_info["name"] as StringName;
			if list.has(method_name): continue;
			var used := connected_method_names.has(method_name);
			
			if !used: continue;
			
			list.append(method_name);
		
		return list;
	
	func get_used_signal_names(obj : Object) -> Array:
		var list := [];
		for signal_info in obj.get_signal_list():
			var signal_name := signal_info["name"] as StringName;
			var used := false;
			
			for connection in obj.get_signal_connection_list(signal_name):
				var flags := connection["flags"] as ConnectFlags;
				if (flags & ConnectFlags.CONNECT_PERSIST) != 0:
					used = true;
					break;
			
			if !used: continue;
			
			list.append(signal_name);
		
		return list;
	
	func get_graph_node_for_object(obj : Object) -> GraphNode:
		return editor.get_node_or_null(NodePath(str(obj.get_instance_id()))) as GraphNode;
	
	func select_object(obj : Object) -> void:
		var existing_graph_node : GraphNode = get_graph_node_for_object(obj);
		if existing_graph_node:
			existing_graph_node.set_selected(true);
	
	class Transactions extends RefCounted:
		
		var editor : SignalGraphEditor;
		var view_interface : ViewInterface;
		
		func _init(editor : GraphEdit, view_interface : ViewInterface):
			self.editor = editor;
			self.view_interface = view_interface;
			
		func add_object_view(obj : Object, position_offset : Vector2) -> void:
			if view_interface.has_object_view(obj):
				view_interface.select_object(obj);
			else:
				view_interface.add_object_view(obj);
				var obj_view := view_interface.get_object_view(obj);
				obj_view["position_offset"] = position_offset;
				view_interface.update_object_view_members_with_rules(obj);
				view_interface.notify_view_updated();
				view_interface.select_object(obj);
				
				editor.transactions.begin_transaction("Add node view", UndoRedo.MERGE_ALL, null, false);
				var undo_redo := editor.transactions.undo_redo;
				undo_redo.add_do_method(view_interface, &"set_object_view", obj, obj_view);
				undo_redo.add_do_method(view_interface, &"notify_view_updated");
				undo_redo.add_do_method(view_interface, &"select_object", obj);
				undo_redo.add_undo_method(view_interface, &"remove_object_view", obj);
				undo_redo.add_undo_method(view_interface, &"notify_view_updated");
				editor.transactions.end_transaction(false);
		
		func remove_object_view(obj : Object) -> void:
			if !view_interface.has_object_view(obj):
				return;
			var obj_view := view_interface.get_object_view(obj);
			
			editor.transactions.begin_transaction("Remove node view", UndoRedo.MERGE_ALL, null, false);
			var undo_redo := editor.transactions.undo_redo;
			undo_redo.add_do_method(view_interface, &"remove_object_view", obj);
			undo_redo.add_do_method(view_interface, &"notify_view_updated");
			undo_redo.add_undo_method(view_interface, &"set_object_view", obj, obj_view);
			undo_redo.add_undo_method(view_interface, &"notify_view_updated");
			undo_redo.add_undo_method(view_interface, &"select_object", obj);
			editor.transactions.end_transaction();
		
		func add_object_view_method(obj : Object, method_name : StringName) -> void:
			if !view_interface.add_object_view_method(obj, method_name):
				return;
			view_interface.notify_view_updated();
			
			editor.transactions.begin_transaction("Add node view method", UndoRedo.MERGE_ALL, null, false);
			var undo_redo := editor.transactions.undo_redo;
			undo_redo.add_do_method(view_interface, &"add_object_view_method", obj, method_name);
			undo_redo.add_undo_method(view_interface, &"remove_object_view_method", obj, method_name);
			undo_redo.add_do_method(view_interface, &"notify_view_updated");
			undo_redo.add_undo_method(view_interface, &"notify_view_updated");
			editor.transactions.end_transaction(false);
		
		func add_object_view_signal(obj : Object, signal_name : StringName) -> void:
			if !view_interface.add_object_view_signal(obj, signal_name):
				return;
			view_interface.notify_view_updated();
			
			editor.transactions.begin_transaction("Add node view signal", UndoRedo.MERGE_ALL, null, false);
			var undo_redo := editor.transactions.undo_redo;
			undo_redo.add_do_method(view_interface, &"add_object_view_signal", obj, signal_name);
			undo_redo.add_undo_method(view_interface, &"remove_object_view_signal", obj, signal_name);
			undo_redo.add_do_method(view_interface, &"notify_view_updated");
			undo_redo.add_undo_method(view_interface, &"notify_view_updated");
			editor.transactions.end_transaction(false);