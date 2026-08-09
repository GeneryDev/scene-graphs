@tool
extends RefCounted

static var SceneObjectGraphNode : Script = preload("res://addons/signal-graphs/editor/elements/scene_object_graph_node.gd");

const OBJECT_TYPE_NODE := "node";
const OBJECT_TYPE_OTHER := "other"; # temporary placeholder for non-node object types
const MEMBER_TYPE_METHOD := "methods";
const MEMBER_TYPE_SIGNAL := "signals";
const PORT_COLOR_METHOD := Color(0x73f280ff);
const PORT_COLOR_SIGNAL := Color(0xff786bff);

const META_NAME_EXTENSION := &"_methods_and_signals_extension";

signal scene_connections_updated();

var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
	scene_connections_updated.connect(_on_scene_connections_updated);
	connect_interface_signals();
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["configure_port_types","populate_graph_node_connections","initialize_object_graph_node","create_object_graph_node_slots","draw_object_graph_node_port"];
	
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
			SignalGraphEditor.Selector.show(graph_node.get_object(), SignalGraphEditor.Selector.TAB_METHODS, Callable(self, &"method_add_requested").bind(graph_node), Callable(self, &"signal_add_requested").bind(graph_node));
		port_type_add_signal:
			editor.force_connection_drag_end();
			SignalGraphEditor.Selector.show(graph_node.get_object(), SignalGraphEditor.Selector.TAB_SIGNALS, Callable(self, &"method_add_requested").bind(graph_node), Callable(self, &"signal_add_requested").bind(graph_node));

func _on_connection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var callable := Callable(to_object, to_graph_node.get_member_from_port_id(MEMBER_TYPE_METHOD, to_port).member_name);
	var signal_name : StringName = from_graph_node.get_member_from_port_id(MEMBER_TYPE_SIGNAL, from_port).member_name;
	
	var undo_redo := EditorInterface.get_editor_undo_redo();
	undo_redo.create_action("Connect signal", UndoRedo.MERGE_ALL, editor.scene_root, false);
	undo_redo.add_do_method(from_object, &"connect", signal_name, callable, CONNECT_PERSIST);
	undo_redo.add_undo_method(from_object, &"disconnect", signal_name, callable);
	undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	undo_redo.commit_action();

func _on_disconnection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var callable := Callable(to_object, to_graph_node.get_member_from_port_id(MEMBER_TYPE_METHOD, to_port).member_name);
	var signal_name : StringName = from_graph_node.get_member_from_port_id(MEMBER_TYPE_SIGNAL, from_port).member_name;
	var flags := ConnectFlags.CONNECT_PERSIST;
	for connection in from_object.get_signal_connection_list(signal_name):
		var connection_callable := connection["callable"] as Callable;
		if connection_callable == callable:
			flags = connection["flags"];
	
	var undo_redo := EditorInterface.get_editor_undo_redo();
	undo_redo.create_action("Disconnect signal", UndoRedo.MERGE_ALL, editor.scene_root, false);
	undo_redo.add_do_method(from_object, &"disconnect", signal_name, callable);
	undo_redo.add_undo_method(from_object, &"connect", signal_name, callable, flags);
	undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	undo_redo.commit_action();

func method_add_requested(method_info : Dictionary, graph_node : GraphNode) -> void:
	var method_name := method_info["name"] as StringName;
	editor.current_view.transactions.add_object_view_member(graph_node.object_type, graph_node.get_object(), MEMBER_TYPE_METHOD, method_name);

func signal_add_requested(signal_info : Dictionary, graph_node : GraphNode) -> void:
	var signal_name := signal_info["name"] as StringName;
	editor.current_view.transactions.add_object_view_member(graph_node.object_type, graph_node.get_object(), MEMBER_TYPE_SIGNAL, signal_name);

func _on_connections_changed() -> void:
	for child : Node in editor.get_children():
		if !is_instance_of(child, SceneObjectGraphNode):
			continue;
		(child.get_meta(META_NAME_EXTENSION, null) as SceneObjectGraphNodeExtension).update_connection_cache();
		
# CAPABILITY: initialize_object_graph_node
func initialize_object_graph_node(graph_node : GraphNode) -> void:
	graph_node.set_meta(META_NAME_EXTENSION, SceneObjectGraphNodeExtension.new(graph_node, editor, self));
		
# CAPABILITY: create_object_graph_node_slots
func create_object_graph_node_slots(graph_node : GraphNode) -> Array[Dictionary]:
	return (graph_node.get_meta(META_NAME_EXTENSION) as SceneObjectGraphNodeExtension).create_object_graph_node_slots();
		
# CAPABILITY: create_object_graph_node_slots
func draw_object_graph_node_port(graph_node : GraphNode, slot_index: int, position: Vector2i, left: bool, color: Color) -> bool:
	return (graph_node.get_meta(META_NAME_EXTENSION) as SceneObjectGraphNodeExtension).draw_port(slot_index, position, left, color);

class SceneObjectGraphNodeExtension extends RefCounted:
	var graph_node : GraphNode;
	var editor : SignalGraphEditor;
	var hook : Object;
	
	var _collapsible_panel : Control;
	
	func _init(graph_node : GraphNode, editor : SignalGraphEditor, hook : Object) -> void:
		self.graph_node = graph_node;
		self.editor = editor;
		self.hook = hook;
		
		graph_node.node_selected.connect(_on_node_selected);
		graph_node.node_deselected.connect(_on_node_deselected);
	
	func _on_node_selected() -> void:
		_collapsible_panel.visible = graph_node.selected && graph_node.get_rect().has_point(editor.get_local_mouse_position());
		graph_node.reset_size();
	
	func _update_collapsible_panel_visibility():
		_collapsible_panel.visible = graph_node.selected;
		graph_node.reset_size();
	
	func _on_node_deselected() -> void:
		_collapsible_panel.visible = false;
		graph_node.reset_size();
	
	func create_object_graph_node_slots() -> Array[Dictionary]:
		var created : Array[Dictionary] = [];
		
		var method_cells := create_method_cells();
		var signal_cells := create_signal_cells();
		var row_count = max(method_cells.size(), signal_cells.size());
		var col_count := int(!method_cells.is_empty()) + int(!signal_cells.is_empty());
		for row_index in range(row_count):
			var row_control := EqualDistributionHBoxContainer.new();
			row_control.add_theme_constant_override("separation",16);
			var method_cell : Dictionary = method_cells[row_index] if row_index < method_cells.size() else {};
			var signal_cell : Dictionary = signal_cells[row_index] if row_index < signal_cells.size() else {};
			
			var slot := {
				"control": row_control,
				"sort_key": 1
			};
			
			if method_cell:
				method_cell.control.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
				row_control.add_child(method_cell.control);
				slot.left_port = method_cell.left_port;
			elif col_count > 1:
				var padding_control := Control.new();
				padding_control.mouse_filter = Control.MOUSE_FILTER_IGNORE;
				padding_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
				row_control.add_child(padding_control);
			
			if signal_cell:
				signal_cell.control.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
				row_control.add_child(signal_cell.control);
				slot.right_port = signal_cell.right_port;
			
			created.append(slot);
		
		created.append(create_collapsible_panel());
		
		return created;
	
	static func get_signal_info_by_name(obj : Object, signal_name : StringName) -> Dictionary:
		for signal_info in obj.get_signal_list():
			if signal_info["name"] != signal_name: continue;
			return signal_info;
		return {};
	
	static func get_method_info_by_name(obj : Object, method_name : StringName) -> Dictionary:
		for method_info in obj.get_method_list():
			if method_info["name"] != method_name: continue;
			return method_info;
		return {};
	
	func create_method_cells() -> Array[Dictionary]:
		var created : Array[Dictionary] = [];
		var obj : Object = graph_node.get_object();
		var seen_method_names : Array[StringName] = [];
		for method_name in editor.current_view.get_object_view_members(graph_node.object_type, obj, MEMBER_TYPE_METHOD):
			var method_info := get_method_info_by_name(obj, method_name);
			if seen_method_names.has(method_name):
				continue; # avoid duplicate ports, skip method overloads
			if !method_info:
				print("No method found for name '" + method_name + "' in object " + str(obj));
				continue;
			seen_method_names.append(method_name);
			
			var cell_control := _create_cell(method_name, SignalGraphEditor.ICON_NAME_METHOD, HORIZONTAL_ALIGNMENT_LEFT);
			cell_control.tooltip_text = "Method: " + SignalGraphEditor.Utility.get_method_signature_text(method_info);
			
			created.append({
				"control": cell_control,
				"sort_key": 1,
				"left_port": {
					"port_type": editor.port_type(&"method"),
					"port_color": PORT_COLOR_METHOD,
					"member": {
						"member_type": MEMBER_TYPE_METHOD,
						"member_name": method_name
					}
				}
			});
		return created;
	
	func create_signal_cells() -> Array[Dictionary]:
		var created : Array[Dictionary] = [];
		var obj : Object = graph_node.get_object();
		for signal_name in editor.current_view.get_object_view_members(graph_node.object_type, obj, MEMBER_TYPE_SIGNAL):
			var signal_info := get_signal_info_by_name(obj, signal_name);
			if !signal_info:
				print("No signal found for name '" + signal_name + "' in object " + str(obj));
				continue;
			
			var cell_control := _create_cell(signal_name, SignalGraphEditor.ICON_NAME_SIGNAL, HORIZONTAL_ALIGNMENT_RIGHT);
			cell_control.tooltip_text = "Signal: " + SignalGraphEditor.Utility.get_method_signature_text(signal_info);
			
			created.append({
				"control": cell_control,
				"sort_key": 1,
				"right_port": {
					"port_type": editor.port_type(&"signal"),
					"port_color": PORT_COLOR_SIGNAL,
					"member": {
						"member_type": MEMBER_TYPE_SIGNAL,
						"member_name": signal_name
					}
				}
			});
		return created;

	func _create_cell(text : String, icon : String, alignment : HorizontalAlignment) -> Control:
		var label := Label.new();
		label.text = text;
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
		label.horizontal_alignment = alignment;
		var height := label.get_minimum_size().y;
		
		var icon_rect := _create_icon_control(icon, int(height));
		
		var container := HBoxContainer.new();
		if alignment == HORIZONTAL_ALIGNMENT_LEFT:
			container.add_child(icon_rect);
		container.add_child(label);
		if alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			container.add_child(icon_rect);
		return container;
	
	func _create_icon_control(icon_name : String, height : int) -> Control:
		if icon_name:
			var texture_rect := TextureRect.new();
			texture_rect.texture = EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons");
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
			return texture_rect;
		else:
			var control := Control.new();
			control.custom_minimum_size = Vector2(height, height);
			return control;
	
	func create_collapsible_panel() -> Dictionary:
		if is_instance_valid(_collapsible_panel):
			_collapsible_panel.queue_free();
			_collapsible_panel = null;
		
		_collapsible_panel = VBoxContainer.new();
		var add_button := Button.new();
		add_button.text = "+";
		add_button.pressed.connect(_on_add_button_pressed);
		_collapsible_panel.add_child(add_button);
		
		_update_collapsible_panel_visibility();
		
		return {
			"control": _collapsible_panel,
			"sort_key": INT32_MAX,
			"left_port": {
				"port_type": editor.port_type(&"add_method"),
				"port_color": PORT_COLOR_METHOD
			},
			"right_port": {
				"port_type": editor.port_type(&"add_signal"),
				"port_color": PORT_COLOR_SIGNAL
			}
		};
	
	func _on_add_button_pressed() -> void:
		SignalGraphEditor.Selector.show(graph_node.get_object(), -1, hook.method_add_requested.bind(graph_node), hook.signal_add_requested.bind(graph_node));
	
	func draw_port(slot_index: int, position: Vector2i, left: bool, color: Color) -> bool:
		# Draw connection line not in view
		var searching_member_type := MEMBER_TYPE_METHOD if left else MEMBER_TYPE_SIGNAL;
		var searching_port_type := editor.port_type(&"method") if left else editor.port_type(&"signal");
		var searching_slot_member_name : StringName = graph_node.get_member_from_slot_id(searching_member_type,slot_index).get("member_name",&"");
		var found_connection_index : int = _connections_not_in_view.find_custom(func (c : Dictionary) -> bool:
			return c.port_type == searching_port_type && c.member_name == searching_slot_member_name;
		);
		if found_connection_index != -1:
			var line_dir := Vector2(-1, 0) if left else Vector2(1, 0);
			var line_length := 40;
			graph_node.draw_polyline_colors([Vector2(position), Vector2(position) + line_dir * line_length], [color, color * Color(1,1,1,0)], 4, true);
		
		return false;
	
	var _connections_not_in_view : Array = [];
	func update_connection_cache() -> void:
		_connections_not_in_view.clear();
		var obj : Object = graph_node.get_object();
		var object_type : String = graph_node.object_type;
	
		var incoming_connections := obj.get_incoming_connections();
		var seen_method_names : Array = [];
		
		for method_connection in incoming_connections:
			if(method_connection.flags & CONNECT_PERSIST) == 0: continue;
			var method_name := method_connection.callable.get_method() as StringName;
			if !editor.current_view.has_object_view_member(object_type, obj, MEMBER_TYPE_METHOD, method_name): continue;
			if seen_method_names.has(method_name): continue;
			seen_method_names.append(method_name);
			var sgnal : Signal = method_connection.signal;
			var source : Object = sgnal.get_object();
			if source is Node && !(editor.scene_root != null && (source == editor.scene_root || editor.scene_root.is_ancestor_of(source))):
				# connected to orphan node, skip;
				continue;
			if !editor.current_view.has_object_view(OBJECT_TYPE_NODE if source is Node else OBJECT_TYPE_OTHER, source):
				_connections_not_in_view.append({
					"port_type": editor.port_type(&"method"),
					"member_name": method_name,
					"other_instance_id": source.get_instance_id()
				});
		
		for signal_info in obj.get_signal_list():
			var signal_name := signal_info["name"] as StringName;
			if !editor.current_view.has_object_view_member(object_type, obj, MEMBER_TYPE_SIGNAL, signal_name): continue;
			
			for signal_connection in obj.get_signal_connection_list(signal_name):
				if(signal_connection.flags & CONNECT_PERSIST) == 0: continue;
				var callable : Callable = signal_connection.callable;
				var target : Object = callable.get_object();
				if !editor.current_view.has_object_view(OBJECT_TYPE_NODE if target is Node else OBJECT_TYPE_OTHER, target):
					_connections_not_in_view.append({
						"port_type": editor.port_type(&"signal"),
						"member_name": signal_name,
						"other_instance_id": target.get_instance_id()
					});
		
		graph_node.queue_redraw();

# HBoxContainer designed to be used inside a VBoxContainer when you need to transpose the layout orientation,
# so that it behaves like a VBoxContainer inside a HBoxContainer parent.
# When multiple of these are placed inside the same container, each child index (column) will inherit the maximum width
# of the same child index across all siblings.
class EqualDistributionHBoxContainer extends Container:
	var gap : int = 4;
	var _last_computed_minimum_size : Vector2;
	var _last_computed_child_widths : Array[float];
	var _last_computed_total_child_width : float;

	func _get_minimum_size() -> Vector2:
		if !get_parent(): return _last_computed_minimum_size;
		var new_minimum_size := _compute_minimum_size();
		if new_minimum_size != _last_computed_minimum_size:
			_last_computed_minimum_size = new_minimum_size;
			update_minimum_size();
		return new_minimum_size;
	
	func _compute_minimum_size() -> Vector2:
		if !get_parent(): return _last_computed_minimum_size;
		var max_child_widths := _last_computed_child_widths;
		var max_child_height := 0;
		max_child_widths.clear();
		var siblings := get_parent().get_children().filter(is_same_class);
		var is_first_sibling := true;
		for sibling : EqualDistributionHBoxContainer in siblings:
			if is_first_sibling && sibling != self:
				# skip all the expensive computations if the first sibling has already done them.
				_last_computed_child_widths = sibling._last_computed_child_widths.duplicate();
				_last_computed_total_child_width = sibling._last_computed_total_child_width;
				return sibling._last_computed_minimum_size;
			var child_controls := sibling.get_children().filter(_is_control);
			for child_index in range(child_controls.size()):
				if max_child_widths.size() <= child_index: max_child_widths.append(0);
				var child_min_size := (child_controls[child_index] as Control).get_combined_minimum_size();
				max_child_height = max(child_min_size.y, max_child_height);
				max_child_widths[child_index] = max(max_child_widths[child_index], child_min_size.x);
			is_first_sibling = false;
		
		var total_max_width := 0.0;
		var total_child_width := 0.0;
		for child_index in range(max_child_widths.size()):
			total_max_width += max_child_widths[child_index];
			total_child_width += max_child_widths[child_index];
			if child_index > 0: total_max_width += gap;
		
		_last_computed_total_child_width = total_child_width;
		return Vector2(total_max_width, max_child_height);
	
	func _is_control(node : Node) -> bool:
		return node is Control; 
	
	func is_same_class(node : Node) -> bool:
		return node is EqualDistributionHBoxContainer; 
		
	func _sort_children() -> void:
		var children := get_children().filter(_is_control);
		
		if children.is_empty(): return;
		var child_count := children.size();
		
		var current_pos := Vector2.ZERO;
		var child_index := 0;
		var container_size := size;
		for child : Control in children:
			if child_index >= _last_computed_child_widths.size():
				# how???
				break;
			var child_size := Vector2(
				(_last_computed_child_widths[child_index] / _last_computed_total_child_width) * (container_size.x - gap * (child_count - 1)),
				container_size.y
			);
			child.position = current_pos;
			child.size = child_size;
			current_pos.x += child_size.x + gap;
			
			child_index += 1;
				
	func _notification(what):
		match what:
			NOTIFICATION_SORT_CHILDREN:
				_sort_children();