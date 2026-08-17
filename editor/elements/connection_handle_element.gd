@tool
extends GraphElement
## The standard Connection Handle GraphElement in Scene Graphs.
## Enables the user to redirect connection lines to untangle them.
## Persistent data about the handle is stored in the scene view of the "from" object (left side of the connection)

## Fired when the handle is reposition or otherwise had its data updated.
signal repositioned()

const INTERACTION_RADIUS := 16
const VISUAL_RADIUS: float = 6

## The [SceneGraphEditor] instance this graph element is in.
var editor: SceneGraphEditor
## The connection dictionary this connection handle represents (with from_node, from_port, to_node, to_port).
## This data may change over the lifetime of a connection handle, as ports are added or removed.
var graph_connection: Dictionary
## A dictionary containing member information about both ends of the connection:
## "from_object_type", "from_object", "from_member_type", "from_member_name",
## "to_object_type", "to_object", "to_member_type", "to_member_name"
## This data is final and will [b]not[/b] change over the lifetime of this Connection Handle object.
var member_connection: Dictionary
## The background color of the graph
var bg_color := Color.BLACK
## The fill color of the handle. Automatically set to be the middle color between the two connected ports' colors.
var fill_color := Color.BLACK
## The rotation of the connection handle, in radians.
var connection_rotation: float = 0
## This handle's offset from the middle point of the connection.
## This is the value controlled by the user when dragging the handle around.
var mid_point_offset: Vector2 = Vector2(0, 0)
var dragging_reference_mid_point: Vector2
var dragging_mid_point_influence: float = 1
var _building_from_view := false


func _init(graph_connection: Dictionary, member_connection: Dictionary, editor: SceneGraphEditor) -> void:
	self.editor = editor
	resizable = false
	draggable = true
	selectable = true
	position_offset_changed.connect(_on_position_offset_changed)

	var bg_panel := editor.get_theme_stylebox("panel")
	if bg_panel is StyleBoxFlat:
		bg_color = bg_panel.get_bg_color()
	self.graph_connection = graph_connection
	self.member_connection = member_connection

	for hook in editor.hooks.initialize_connection_handle:
		hook.initialize_connection_handle(self)


func _draw() -> void:
	var center := size / 2
	var drawn := false
	for hook in editor.hooks.draw_connection_handle:
		if hook.draw_connection_handle(self, center, connection_rotation, VISUAL_RADIUS):
			drawn = true
			break
	if !drawn:
		draw_dot_handle(center, connection_rotation, VISUAL_RADIUS)


## Retrieves the data about this handle stored in the current view. Returns empty if it doesn't exist.
func get_handle_view_data() -> Dictionary:
	var from_graph_node := get_from_graph_node()
	if !from_graph_node:
		return { }
	var from_obj_view: Dictionary = from_graph_node.get_object_view()
	if !from_obj_view:
		return { }
	var connection_handles_list := from_obj_view.get("connection_handles", []) as Array
	if !connection_handles_list:
		return { }
	for entry in connection_handles_list:
		if entry is not Dictionary:
			continue
		if !entry.has("member_connection"):
			continue
		if entry.member_connection == member_connection:
			return entry
	return { }


## Retrieves the data about this handle stored in the current view. Adds it if it doesn't already exist.
func get_or_add_handle_view_data() -> Dictionary:
	var existing: Dictionary = get_handle_view_data()
	if existing:
		return existing
	var from_graph_node := get_from_graph_node()
	if !from_graph_node:
		return { }
	var from_obj_view: Dictionary = from_graph_node.get_object_view()
	if !from_obj_view:
		return { }
	var connection_handles_list := from_obj_view.get_or_add("connection_handles", []) as Array
	var new_entry := {
		"member_connection": member_connection,
	}
	connection_handles_list.append(new_entry)
	return new_entry


## Updates the state of this handle to match the data about it stored in the current scene graph view.
func update_from_view() -> void:
	var connection_handle_data: Dictionary = get_handle_view_data()
	if !connection_handle_data:
		return
	_building_from_view = true

	if connection_handle_data.has("mid_point_offset"):
		mid_point_offset = connection_handle_data["mid_point_offset"] as Vector2
	else:
		mid_point_offset = Vector2.ZERO
	_building_from_view = false


## Updates the scene graph view data to reflect the state of this handle.
func update_view() -> void:
	if _building_from_view:
		return
	var connection_handle_data := get_or_add_handle_view_data()
	connection_handle_data["mid_point_offset"] = mid_point_offset


## Preset draw function to be used in draw callbacks. Draws an arrow head.
func draw_arrow_handle(center: Vector2, rotation: float, size: float) -> void:
	var arrow_poly := PackedVector2Array(
		[
			Vector2(-size * 1.25, -size * 1.25),
			Vector2(-size * 1.2, -size * 1.4),
			Vector2(-size * 1.1, -size * 1.5),
			Vector2(-size, -size * 1.5),
			Vector2(size, -size * 0.1),
			Vector2(size, size * 0.1),
			Vector2(-size, size * 1.5),
			Vector2(-size * 1.1, size * 1.5),
			Vector2(-size * 1.2, size * 1.4),
			Vector2(-size * 1.25, size * 1.25),
			Vector2(-size * 0.75, 0),
		],
	)
	var arrow_poly_closed := arrow_poly.duplicate()
	arrow_poly_closed.append(arrow_poly[0])

	var outline_color := bg_color if !selected else Color.WHITE

	var arrow_colors := []
	arrow_colors.resize(arrow_poly.size())
	arrow_colors.fill(fill_color)

	draw_set_transform(center, rotation)
	draw_polygon(arrow_poly, PackedColorArray(arrow_colors))
	draw_polyline(arrow_poly_closed, outline_color, 2, true)


## Preset draw function to be used in draw callbacks. Draws a dot.
func draw_dot_handle(center: Vector2, rotation: float, size: float) -> void:
	var outline_color := bg_color if !selected else Color.WHITE

	draw_set_transform(center)
	draw_circle(Vector2.ZERO, size, fill_color, true, -1)
	draw_circle(Vector2.ZERO, size, outline_color, false, 2, true)


## Repositions this handle to be at the given location in the graph, with the given rotation.
func reposition(position_offset: Vector2, rotation: float = 0) -> void:
	if editor.dragging && selected:
		return
	self.position_offset = position_offset - Vector2(INTERACTION_RADIUS, INTERACTION_RADIUS)
	size = Vector2(INTERACTION_RADIUS, INTERACTION_RADIUS) * 2
	self.rotation = 0
	connection_rotation = rotation

	var from_color: Color = get_from_graph_node().get_output_port_color(graph_connection.from_port)
	var to_color: Color = get_to_graph_node().get_input_port_color(graph_connection.to_port)
	fill_color = from_color.lerp(to_color, 0.5)

	repositioned.emit()


## Retrieves the GraphNode this connection handle is connected to on the left side.
func get_from_graph_node() -> GraphNode:
	return editor.get_node_or_null(NodePath(graph_connection.from_node))


## Retrieves the GraphNode this connection handle is connected to on the right side.
func get_to_graph_node() -> GraphNode:
	return editor.get_node_or_null(NodePath(graph_connection.to_node))


## Returns the current mid point offset, taking into account any ongoing dragging operations.
func get_current_mid_point_offset() -> Vector2:
	if selected && editor.dragging:
		return lerp(mid_point_offset, position_offset - dragging_reference_mid_point, dragging_mid_point_influence)
	return mid_point_offset


## Applies changes to the mid point offset by ongoing dragging operations.
func apply_mid_point_offset_change() -> void:
	mid_point_offset = get_current_mid_point_offset()
	update_view()


## Resets the mid point offset of this handle, reverting the curve to its default look.
func reset_mid_point_offset() -> void:
	mid_point_offset = Vector2.ZERO
	update_view()
	editor.invalidate_connection_line_cache()


func _on_position_offset_changed() -> void:
	if editor.dragging:
		editor.connections_layer.queue_redraw()
		for child in editor.connections_layer.get_children():
			if child is not Line2D:
				continue
			editor.invalidate_connection_line_cache()
		update_view()
