@tool
extends GraphElement

static var ICON_ARGUMENTS : Texture2D = preload("res://addons/signal-graphs/icons/bound_arguments.svg");

const INTERACTION_RADIUS := 16;
const VISUAL_RADIUS := 8;

var editor : SignalGraphEditor;
var graph_connection : Dictionary;
var bg_color := Color.BLACK;
var connection_rotation : float = 0;

var connection_flags : ConnectFlags;
var connection_callable : Callable;

func _init() -> void:
	resizable = false;
	draggable = false;
	selectable = true;

func setup(connection : Dictionary, editor : SignalGraphEditor) -> bool:
	self.editor = editor;
	var bg_panel := editor.get_theme_stylebox("panel");
	if bg_panel is StyleBoxFlat:
		bg_color = bg_panel.get_bg_color();
	graph_connection = connection;
	return true;

func get_save_data() -> Dictionary:
	var dict := {};
	dict["position_offset"] = position_offset;
	return dict;
	
func _draw() -> void:
	var center := size / 2;
	var arrow_poly := PackedVector2Array([
			Vector2(-VISUAL_RADIUS, -VISUAL_RADIUS*1.5),
			Vector2(VISUAL_RADIUS, 0),
			Vector2(-VISUAL_RADIUS, VISUAL_RADIUS*1.5),
			Vector2(-VISUAL_RADIUS/2, 0)
		]);
	var arrow_poly_closed := arrow_poly.duplicate();
	arrow_poly_closed.append(arrow_poly[0]);
	
	var outline_color := bg_color if !selected else Color.WHITE;
	var fill_color := Color(0xaac278ff) if !selected else Color(0xaac278ff);
	
	draw_set_transform(center, connection_rotation);
	draw_polygon(arrow_poly,PackedColorArray([fill_color,fill_color,fill_color,fill_color]))
	draw_polyline(arrow_poly_closed,outline_color, 2, true)
#	draw_texture()
	var theme := EditorInterface.get_editor_theme();
	if connection_flags & CONNECT_ONE_SHOT != 0:
		var icon := theme.get_icon("ZoomReset", "EditorIcons") as Texture2D;
		draw_set_transform(center, connection_rotation);
		draw_texture(icon, Vector2(VISUAL_RADIUS*1.5,VISUAL_RADIUS*1.5) - icon.get_size() / 2);
	if connection_flags & CONNECT_DEFERRED != 0:
		var icon := theme.get_icon("Timer", "EditorIcons") as Texture2D;
		draw_set_transform(center, connection_rotation);
		draw_texture(icon, Vector2(VISUAL_RADIUS*1.5,-VISUAL_RADIUS*1.5) - icon.get_size() / 2);
	if connection_flags & CONNECT_APPEND_SOURCE_OBJECT != 0 || connection_callable.get_bound_arguments_count() > 0 || connection_callable.get_unbound_arguments_count() > 0:
		var icon := ICON_ARGUMENTS;
		draw_set_transform(center, connection_rotation);
		draw_texture(icon, Vector2(-VISUAL_RADIUS*3,0) - icon.get_size() / 2);
#		draw_circle(size / 2, VISUAL_RADIUS+2, outline_color, true, -1, true);
#		draw_circle(size / 2, VISUAL_RADIUS, fill_color, true, -1, true);
	
func reposition(position_offset : Vector2, rotation : float = 0) -> void:
	self.position_offset = position_offset - Vector2(INTERACTION_RADIUS, INTERACTION_RADIUS);
	size = Vector2(INTERACTION_RADIUS, INTERACTION_RADIUS)*2;
	self.rotation = 0;
	connection_rotation = rotation;

func update_connection_info() -> void:
	var from_graph_node := editor.get_node(NodePath(graph_connection.from_node));
	var to_graph_node := editor.get_node(NodePath(graph_connection.to_node));
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var signal_name : StringName = from_graph_node.get_signal_port_name(graph_connection.from_port);
	var method_name : StringName = to_graph_node.get_method_port_name(graph_connection.to_port);
	
	var signal_connection : Dictionary;
	for signal_connection_candidate in from_object.get_signal_connection_list(signal_name):
		if !signal_connection_candidate.callable.is_valid(): continue;
		if (signal_connection_candidate.flags & CONNECT_PERSIST) == 0: continue;
		if signal_connection_candidate.callable.get_method() == method_name:
			signal_connection = signal_connection_candidate;
	
	var callable := Callable(to_object, method_name);
	
	if signal_connection:
		_update_connection_info(signal_connection.flags, signal_connection.callable);
		
func _update_connection_info(flags : ConnectFlags, callable : Callable) -> void:
	var updated := false;
	if connection_flags != flags: updated = true;
	if connection_callable != callable: updated = true;
	connection_flags = flags;
	connection_callable = callable;
	if updated: queue_redraw();
		