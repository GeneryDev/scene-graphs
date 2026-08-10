@tool
extends RefCounted

static var SceneObjectGraphNode : Script = preload("res://addons/signal-graphs/editor/elements/scene_object_graph_node.gd");
static var ObjectSignalConnectionElement : Script = preload("res://addons/signal-graphs/editor/elements/object_signal_connection_graph_element.gd");
static var SignalConnectionPropertyEdit : Script = preload("res://addons/signal-graphs/editor/inspector/signal_connection_property_edit.gd");

var editor : SignalGraphEditor;
var _connections_with_elements : Array[Dictionary] = [];

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
	editor.connection_line_cache_invalidated.connect(_invalidate_line_end_cache);
	editor.connections_changed.connect(_on_connections_changed);
	editor.connections_layer.draw.connect(_on_connections_draw);
	editor.selection_changed_with_script.connect(_on_selection_changed_with_script);
	editor.begin_node_move.connect(_on_begin_node_move);
	editor.end_node_move.connect(_on_end_node_move);
	editor.visibility_changed.connect(_on_visibility_changed);
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["override_connection_lines"];
	
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
		if !editor.check_connection_port_types(connection, editor.port_type(&"signal"), editor.port_type(&"method")): continue;
		
		var from_graph_node : GraphNode = editor.get_node_or_null(NodePath(connection.from_node));
		var to_graph_node : GraphNode = editor.get_node_or_null(NodePath(connection.to_node));
		
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
	if script == ObjectSignalConnectionElement:
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
