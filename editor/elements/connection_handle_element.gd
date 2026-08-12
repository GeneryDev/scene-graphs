@tool
extends GraphElement

signal repositioned();

const INTERACTION_RADIUS := 16;
const VISUAL_RADIUS : float = 6;

var editor : SignalGraphEditor;
var graph_connection : Dictionary;
var member_connection : Dictionary;
var bg_color := Color.BLACK;
var arrow_color := Color.BLACK;
var connection_rotation : float = 0;

var mid_point_offset : Vector2 = Vector2(0,0);
var dragging_reference_mid_point : Vector2;
var dragging_mid_point_influence : float = 1;
var _building_from_view := false;

func _init(graph_connection : Dictionary, member_connection : Dictionary, editor : SignalGraphEditor) -> void:
	self.editor = editor;
	resizable = false;
	draggable = true;
	selectable = true;
	position_offset_changed.connect(_on_position_offset_changed);
	
	var bg_panel := editor.get_theme_stylebox("panel");
	if bg_panel is StyleBoxFlat:
		bg_color = bg_panel.get_bg_color();
	self.graph_connection = graph_connection;
	self.member_connection = member_connection;
	
	for hook in editor.hooks.initialize_connection_handle:
		hook.initialize_connection_handle(self);

func get_handle_view_data() -> Dictionary:
	var from_graph_node := get_from_graph_node();
	if !from_graph_node: return {};
	var from_obj_view : Dictionary = from_graph_node.get_object_view();
	if !from_obj_view: return {};
	var connection_handles_list := from_obj_view.get("connection_handles",[]) as Array;
	if !connection_handles_list: return {};
	for entry in connection_handles_list:
		if entry is not Dictionary: continue;
		if !entry.has("member_connection"): continue;
		if entry.member_connection == member_connection:
			return entry;
	return {};

func get_or_add_handle_view_data() -> Dictionary:
	var existing : Dictionary = get_handle_view_data();
	if existing: return existing;
	var from_graph_node := get_from_graph_node();
	if !from_graph_node: return {};
	var from_obj_view : Dictionary = from_graph_node.get_object_view();
	if !from_obj_view: return {};
	var connection_handles_list := from_obj_view.get_or_add("connection_handles",[]) as Array;
	var new_entry := {
		"member_connection": member_connection
	};
	connection_handles_list.append(new_entry);
	return new_entry;

func update_from_view() -> void:
	var connection_handle_data : Dictionary = get_handle_view_data();
	if !connection_handle_data: return;
	_building_from_view = true;
	
	if connection_handle_data.has("mid_point_offset"):
		mid_point_offset = connection_handle_data["mid_point_offset"] as Vector2;
	else:
		mid_point_offset = Vector2.ZERO;
	_building_from_view = false;
	
func update_view() -> void:
	if _building_from_view: return;
	var connection_handle_data := get_or_add_handle_view_data();
	connection_handle_data["mid_point_offset"] = mid_point_offset;
	
func _draw() -> void:
	var center := size / 2;
	var drawn := false;
	for hook in editor.hooks.draw_connection_handle:
		if hook.draw_connection_handle(self, center, connection_rotation, VISUAL_RADIUS):
			drawn = true;
			break;
	if !drawn: 
		draw_dot_handle(center, connection_rotation, VISUAL_RADIUS);
	
#	draw_arrow_handle(center, connection_rotation, VISUAL_RADIUS);
#	draw_string(get_theme_default_font(), center, str(get_handle_view_data()));

func draw_arrow_handle(center : Vector2, rotation : float, size : float) -> void:
	var arrow_poly := PackedVector2Array([
			Vector2(-size*1.25, -size*1.25),
			Vector2(-size*1.2, -size*1.4),
			Vector2(-size*1.1, -size*1.5),
			Vector2(-size, -size*1.5),
			Vector2(size, -size*0.1),
			Vector2(size, size*0.1),
			Vector2(-size, size*1.5),
			Vector2(-size*1.1, size*1.5),
			Vector2(-size*1.2, size*1.4),
			Vector2(-size*1.25, size*1.25),
			Vector2(-size*0.75, 0)
		]);
	var arrow_poly_closed := arrow_poly.duplicate();
	arrow_poly_closed.append(arrow_poly[0]);
	
	var outline_color := bg_color if !selected else Color.WHITE;
	var fill_color := arrow_color;
	
	var arrow_colors := [];
	arrow_colors.resize(arrow_poly.size());
	arrow_colors.fill(fill_color);
	
	draw_set_transform(center, rotation);
	draw_polygon(arrow_poly,PackedColorArray(arrow_colors));
	draw_polyline(arrow_poly_closed,outline_color, 2, true);

func draw_dot_handle(center : Vector2, rotation : float, size : float) -> void:
	var outline_color := bg_color if !selected else Color.WHITE;
	var fill_color := arrow_color;
	
	draw_set_transform(center);
	draw_circle(Vector2.ZERO, size, fill_color, true, -1);
	draw_circle(Vector2.ZERO, size, outline_color, false, 2, true);
	
func reposition(position_offset : Vector2, rotation : float = 0) -> void:
	if editor.dragging && selected:
		return;
	self.position_offset = position_offset - Vector2(INTERACTION_RADIUS, INTERACTION_RADIUS);
	size = Vector2(INTERACTION_RADIUS, INTERACTION_RADIUS)*2;
	self.rotation = 0;
	connection_rotation = rotation;
	
	var from_color : Color = get_from_graph_node().get_output_port_color(graph_connection.from_port);
	var to_color : Color = get_to_graph_node().get_input_port_color(graph_connection.to_port);
	arrow_color = from_color.lerp(to_color, 0.5);
	
	repositioned.emit();

func get_from_graph_node() -> GraphNode:
	return editor.get_node_or_null(NodePath(graph_connection.from_node));
func get_to_graph_node() -> GraphNode:
	return editor.get_node_or_null(NodePath(graph_connection.to_node));

func get_current_mid_point_offset() -> Vector2:
	if selected && editor.dragging:
		return lerp(mid_point_offset, position_offset - dragging_reference_mid_point, dragging_mid_point_influence);
	return mid_point_offset;

func apply_mid_point_offset_change() -> void:
	mid_point_offset = get_current_mid_point_offset();
	update_view();
	
func _on_position_offset_changed() -> void:
	if editor.dragging:
		editor.connections_layer.queue_redraw();
		for child in editor.connections_layer.get_children():
			if child is not Line2D: continue;
			editor.invalidate_connection_line_cache();
		update_view();
