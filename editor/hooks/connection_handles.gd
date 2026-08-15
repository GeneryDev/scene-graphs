@tool
extends RefCounted

static var SceneObjectGraphNode : Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd");
static var ConnectionHandleElement : Script = preload("res://addons/scene-graphs/editor/elements/connection_handle_element.gd");

var editor : SceneGraphEditor;
var _connections_with_elements : Array[Dictionary] = [];

func _init(editor : SceneGraphEditor):
	self.editor = editor;
	
	editor.connection_line_cache_invalidated.connect(_invalidate_line_end_cache);
	editor.connections_changed.connect(_on_connections_changed);
	editor.connections_layer.draw.connect(_on_connections_draw);
	editor.begin_node_move.connect(_on_begin_node_move);
	editor.end_node_move.connect(_on_end_node_move);
	editor.visibility_changed.connect(_on_visibility_changed);
	
func get_scene_graph_capabilities() -> Array[String]:
	return ["configure_capabilities","configure_hook_options","override_connection_lines","view_serialization","populate_popup_menu"];
	
### CAPABILITY: configure_capabilities
func configure_capabilities() -> void:
	editor.hooks.register_capability("initialize_connection_handle", [&"initialize_connection_handle"] as Array[StringName]);
	editor.hooks.register_capability("draw_connection_handle", [&"draw_connection_handle"] as Array[StringName]);

### CAPABILITY: configure_hook_options
func get_hook_options_id() -> String:
	return "scene_graphs:connection_handles";

func get_hook_options_label(options : Options) -> String:
	if options == null: return "Connection Handles";
	return "Connection Handles: %s" % ["Enabled" if options.handles_enabled else "Disabled"];

func create_hook_options() -> Options:
	return Options.new();

func get_hook_description() -> String:
	return "Shows movable handles for all graph connections, allowing you to redirect each individual connection to avoid tangling.\nNote: It's recommended to have this enabled when using Method and Signal connections; handles display connection flags and let you edit them when selected.";
	
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
	if editor.current_view == null: return;
	var intended_index := editor.connections_layer.get_index()+1;
	
	for cached_connection in _connections_with_elements:
		cached_connection.still_valid = false;
		
	var options : Options = editor.current_view.get_hook_options(self);
	
	for graph_connection : Dictionary in editor.connections:
		if !options.handles_enabled: break;
		if !editor.is_connection_ready(graph_connection): continue;
		
		var from_graph_node : GraphNode = editor.get_node_or_null(NodePath(graph_connection.from_node));
		var to_graph_node : GraphNode = editor.get_node_or_null(NodePath(graph_connection.to_node));
		
		if !is_instance_of(from_graph_node, SceneObjectGraphNode): continue;
		if !is_instance_of(to_graph_node, SceneObjectGraphNode): continue;
		
		var from_member : Dictionary = from_graph_node.get_member_from_port_id_and_side(graph_connection.from_port, "right");
		var to_member : Dictionary = to_graph_node.get_member_from_port_id_and_side(graph_connection.to_port, "left");
		
		if !from_member || !to_member: continue;
		
		var member_connection := {
			"from_object_type": from_graph_node.object_type,
			"from_object": from_graph_node.get_object_key(),
			"from_member_type": from_member.member_type,
			"from_member_name": from_member.member_name,
			"to_object_type": to_graph_node.object_type,
			"to_object": to_graph_node.get_object_key(),
			"to_member_type": to_member.member_type,
			"to_member_name": to_member.member_name
		};
		
		var matching_cached_connection : Dictionary;
		
		for cached_connection in _connections_with_elements:
			if cached_connection.member_connection != member_connection: continue;
			if !is_instance_valid(cached_connection.graph_element): continue;
			if cached_connection.graph_element.is_queued_for_deletion(): continue;
			if !is_instance_valid(cached_connection.from_graph_node): continue;
			if cached_connection.from_graph_node.is_queued_for_deletion(): continue;
			if !is_instance_valid(cached_connection.to_graph_node): continue;
			if cached_connection.to_graph_node.is_queued_for_deletion(): continue;
			cached_connection.still_valid = true;
			matching_cached_connection = cached_connection;
			cached_connection.graph_connection = graph_connection;
			cached_connection.graph_element.graph_connection = graph_connection;
		
		if !matching_cached_connection:
			var graph_element : GraphElement = ConnectionHandleElement.new(graph_connection, member_connection, editor);
			editor.connections_layer.add_sibling(graph_element, false);
			matching_cached_connection = {
				"graph_connection": graph_connection,
				"member_connection": member_connection,
				"graph_element": graph_element,
				"from_graph_node": from_graph_node,
				"to_graph_node": to_graph_node,
				"still_valid": true
			};
			_connections_with_elements.append(matching_cached_connection);
			graph_element.update_from_view();
		
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
	
	_invalidate_line_end_cache.call_deferred();

func _reposition_connection_element(cached_connection : Dictionary) -> void:
	var graph_connection : Dictionary = cached_connection.graph_connection;
	var graph_element : GraphElement = cached_connection.graph_element;
	if !is_instance_valid(cached_connection.from_graph_node): return;
	var from_graph_node : GraphNode = cached_connection.from_graph_node;
	var to_graph_node : GraphNode = cached_connection.to_graph_node;
	if !from_graph_node || !to_graph_node: return;
	if graph_connection.from_port >= from_graph_node.get_output_port_count(): return;
	if graph_connection.to_port >= to_graph_node.get_input_port_count(): return;
	var line_from := (from_graph_node.get_output_port_position(graph_connection.from_port) + from_graph_node.position_offset);
	var line_to := (to_graph_node.get_input_port_position(graph_connection.to_port) + to_graph_node.position_offset);
	var line : PackedVector2Array = editor.get_connection_line(line_from, line_to);
	var mid_point_straight := (line_from + line_to) / 2;
	var mid_point := line[line.size()/2] if line.size() % 2 == 1 else (line[line.size()/2-1]+line[line.size()/2])/2;
	var new_position : Vector2;
	var rotation : float = 0;
	if graph_element.get_current_mid_point_offset():
		new_position = mid_point_straight + graph_element.mid_point_offset;
		rotation = (line_to - line_from).angle();
	else:
		new_position = mid_point;
		rotation = (line_to - line_from).angle();
	graph_element.reposition(new_position, rotation);
#	graph_element.update_connection_info();

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
	var cache_entry;
	# Search in view coordinates (w/ zoom)
	cache_entry = _line_end_cache.get(_get_line_end_cache_key(from_position / editor.zoom));
	if cache_entry:
		for cached_connection : Dictionary in cache_entry:
			if match_line_ends(from_position, to_position, 5 * editor.zoom, cached_connection.line_ends_view):
				return cached_connection;
	# Search in absolute coordinates (w/o zoom)
	cache_entry = _line_end_cache.get(_get_line_end_cache_key(from_position));
	if cache_entry:
		for cached_connection : Dictionary in cache_entry:
			if match_line_ends(from_position, to_position, 5, cached_connection.line_ends_absolute):
				return cached_connection;
	return {};

func match_line_ends(from_position : Vector2, to_position : Vector2, tolerance : float, line_ends : Array) -> bool:
	var from_dist_sqr := from_position.distance_squared_to(line_ends[0]);
	if from_dist_sqr > tolerance: return false;
	var to_dist_sqr := to_position.distance_squared_to(line_ends[1]);
	if to_dist_sqr > tolerance: return false;
	return true;

func _get_line_end_cache_key(from_position : Vector2) -> int:
	return int(from_position.y) / 100;

func _invalidate_line_end_cache() -> void:
	_line_end_cache_time = 0;

func _update_line_end_cache() -> void:
	_line_end_cache.clear();
	for cached_connection : Dictionary in _connections_with_elements:
		var graph_connection = cached_connection.graph_connection;
		cached_connection.line_ends_absolute = [Vector2(0,0),Vector2(0,0)];
		cached_connection.line_ends_view = [Vector2(0,0),Vector2(0,0)];
		
		if !is_instance_valid(cached_connection.graph_element): continue;
		if !is_instance_valid(cached_connection.from_graph_node): continue;
		if !is_instance_valid(cached_connection.to_graph_node): continue;

		var from_graph_node : GraphNode = cached_connection.from_graph_node;
		var to_graph_node : GraphNode = cached_connection.to_graph_node;
		if !from_graph_node || !to_graph_node:
			continue;
		if graph_connection.from_port >= from_graph_node.get_output_port_count(): continue;
		if graph_connection.to_port >= to_graph_node.get_input_port_count(): continue;
		var from_absolute := from_graph_node.get_output_port_position(graph_connection.from_port) + from_graph_node.position_offset;
		var to_absolute := to_graph_node.get_input_port_position(graph_connection.to_port) + to_graph_node.position_offset;
		var from_view := from_absolute * editor.zoom;
		var to_view := to_absolute * editor.zoom;
		cached_connection.line_ends_absolute[0] = from_absolute;
		cached_connection.line_ends_absolute[1] = to_absolute;
		cached_connection.line_ends_view[0] = from_view;
		cached_connection.line_ends_view[1] = to_view;
		
		var cache_key := _get_line_end_cache_key(from_absolute);

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

### CAPABILITY: view_serialization
func edit_serialized_view(serialized : Dictionary) -> void:
	for object_type in serialized.scene_objects:
		var objects_for_type : Dictionary = serialized.scene_objects[object_type];
		for object_key in objects_for_type:
			var object_view : Dictionary = objects_for_type[object_key];
			if !object_view.has("connection_handles"): continue;
			var handles : Array = object_view["connection_handles"];
			var handle_index := 0;
			while handle_index < handles.size():
				var handle_data : Dictionary = handles[handle_index];
				if handle_data.has("member_connection"):
					var member_connection := handle_data.get("member_connection") as Dictionary;
					if member_connection.has("from_object") && member_connection.has("to_object"):
						var serialized_key_from = editor.current_view.object_key_serialize(member_connection.from_object_type, member_connection.from_object);
						var serialized_key_to = editor.current_view.object_key_serialize(member_connection.to_object_type, member_connection.to_object);
						
						if serialized_key_from != null && serialized_key_to != null:
							member_connection.from_object = serialized_key_from;
							member_connection.to_object = serialized_key_to;
							handle_index += 1;
							continue;
				# invalid
				handles.remove_at(handle_index);
func edit_deserialized_view(view : SceneGraphView) -> void:
	for object_type in view.scene_objects:
		var objects_for_type : Dictionary = view.scene_objects[object_type];
		for object_key in objects_for_type:
			var object_view : Dictionary = objects_for_type[object_key];
			if !object_view.has("connection_handles"): continue;
			var handles : Array = object_view["connection_handles"];
			var handle_index := 0;
			while handle_index < handles.size():
				var handle_data : Dictionary = handles[handle_index];
				if handle_data.has("member_connection"):
					var member_connection := handle_data.get("member_connection") as Dictionary;
					if member_connection.has("from_object") && member_connection.has("to_object"):
						var deserialized_key_from = view.object_key_deserialize(member_connection.from_object_type, member_connection.from_object);
						var deserialized_key_to = view.object_key_deserialize(member_connection.to_object_type, member_connection.to_object);
						
						if deserialized_key_from != null && deserialized_key_to != null:
							member_connection.from_object = deserialized_key_from;
							member_connection.to_object = deserialized_key_to;
							handle_index += 1;
							continue;
				# invalid
				handles.remove_at(handle_index);

### CAPABILITY: populate_popup_menu
const ACTION_RESET_HANDLE_POSITION : int = 100;

func populate_popup_menu(at_position : Vector2, menu : PopupMenu, actions : Dictionary[int, Callable]) -> void:
	var any := false;
	for name in editor.selected_nodes:
		var node := editor.get_node_or_null(NodePath(name));
		if is_instance_of(node, ConnectionHandleElement):
			any = true;
			break;
	if !any: return;
	menu.add_separator("Connection Handle");
	menu.add_item("Reset Handle Position", ACTION_RESET_HANDLE_POSITION);
	actions[ACTION_RESET_HANDLE_POSITION] = _action_reset_handle_position;

func _action_reset_handle_position() -> void:
	for name in editor.selected_nodes:
		var node := editor.get_node_or_null(NodePath(name));
		if is_instance_of(node, ConnectionHandleElement):
			var handle : GraphElement = node;
			handle.reset_mid_point_offset();

class Options extends RefCounted:
	@export var handles_enabled : bool = true;