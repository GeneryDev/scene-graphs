@tool
extends RefCounted

static var SceneObjectGraphNode : Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd");
static var ConnectionHandleElement : Script = preload("res://addons/scene-graphs/editor/elements/connection_handle_element.gd");
static var SignalConnectionPropertyEdit : Script = preload("res://addons/scene-graphs/editor/inspector/signal_connection_property_edit.gd");

const OBJECT_TYPE_NODE := "node";
const OBJECT_TYPE_OTHER := "other"; # temporary placeholder for non-node object types
const MEMBER_TYPE_METHOD := "method";
const MEMBER_TYPE_SIGNAL := "signal";
const PORT_COLOR_METHOD := Color(0x73f280ff);
const PORT_COLOR_SIGNAL := Color(0xff786bff);

const ICON_NAME_SIGNAL := "Signal";
const ICON_NAME_METHOD := "Slot";

const META_NAME_EXTENSION := &"_methods_and_signals_extension";

signal scene_connections_updated();

var editor : SceneGraphEditor;

func _init(editor : SceneGraphEditor):
	self.editor = editor;
	
	editor.connection_request.connect(_on_connection_request);
	editor.disconnection_request.connect(_on_disconnection_request);
	editor.connections_changed.connect(_on_connections_changed);
	editor.selection_changed_with_script.connect(_on_selection_changed_with_script);
	
	scene_connections_updated.connect(_on_scene_connections_updated);
	
func get_scene_graph_capabilities() -> Array[String]:
	return ["configure_port_types","configure_hook_options","populate_graph_node_connections","initialize_object_graph_node","create_object_graph_node_slots","draw_object_graph_node_port","configure_member_selector","initialize_connection_handle","draw_connection_handle"];
	
### CAPABILITY: configure_ports
func configure_port_types() -> void:
	editor.register_port_type(&"method");
	editor.register_port_type(&"signal");
	editor.add_valid_connection_type(editor.port_type(&"signal"), editor.port_type(&"method"));
	editor.add_valid_connection_type(editor.port_type(&"signal"), editor.port_type(&"wildcard_in"));
	editor.add_valid_connection_type(editor.port_type(&"wildcard_out"), editor.port_type(&"method"));

### CAPABILITY: configure_hook_options
func get_hook_options_id() -> String:
	return "scene_graphs:methods_and_signals";

func get_hook_options_label(options : Options) -> String:
	if options == null: return "Methods and Signals";
	return "Methods and Signals: %s" % ["Enabled" if options.enable_method_and_signal_ports else "Disabled"];

func create_hook_options() -> Options:
	return Options.new();

func get_hook_description() -> String:
	return "Sets up ports and connections corresponding to methods and signals.\nNote: objects must have method and signal members visible in the view, added either by a Member Source view rule, or manually.";

func _on_scene_connections_updated() -> void:
	populate_graph_node_connections();
	
func notify_scene_connections_updated() -> void:
	scene_connections_updated.emit();
	
func populate_graph_node_connections() -> void:
	for child : Node in editor.get_children():
		if !is_instance_of(child, SceneObjectGraphNode):
			continue;
		
		var graph_node : GraphNode = child;
		
		var obj : Object = child.get_object();
		
		# Remove all incoming connections of our handled type -- we'll re-add them after
		for connection in editor.get_connection_list_from_node(graph_node.name):
			if connection.to_node != graph_node.name: continue;
			if !editor.check_connection_port_types(connection, editor.port_type(&"signal"), editor.port_type(&"method")): continue;
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

### CONNECTING
	
func _on_connection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	var from_port_type := (from_graph_node as GraphNode).get_output_port_type(from_port);
	var to_port_type := (to_graph_node as GraphNode).get_input_port_type(to_port);
	var port_pair := [from_port_type, to_port_type];
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	
	if port_pair == [editor.port_type(&"signal"), editor.port_type(&"method")]:
		var callable := Callable(to_object, to_graph_node.get_member_from_port_id(to_port, MEMBER_TYPE_METHOD).member_name);
		var signal_name : StringName = from_graph_node.get_member_from_port_id(from_port, MEMBER_TYPE_SIGNAL).member_name;
		
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Connect signal", UndoRedo.MERGE_ALL, editor.scene_root, false);
		undo_redo.add_do_method(from_object, &"connect", signal_name, callable, CONNECT_PERSIST);
		undo_redo.add_undo_method(from_object, &"disconnect", signal_name, callable);
		undo_redo.add_do_method(self, &"notify_scene_connections_updated");
		undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
		undo_redo.commit_action();
	elif port_pair == [editor.port_type(&"wildcard_out"), editor.port_type(&"method")]:
		var callable := Callable(to_object, to_graph_node.get_member_from_port_id(to_port, MEMBER_TYPE_METHOD).member_name);
		editor.member_selector.show(from_graph_node.object_type, from_object, [MEMBER_TYPE_SIGNAL], func (selected_object_type, selected_object, selected_member_type, selected_member) -> void:
			editor.current_view.transactions.add_object_view_member(selected_object_type, selected_object, selected_member_type, selected_member);
			var signal_name = selected_member;
			
			var undo_redo := EditorInterface.get_editor_undo_redo();
			undo_redo.create_action("Connect signal", UndoRedo.MERGE_ALL, editor.scene_root, false);
			undo_redo.add_do_method(from_object, &"connect", signal_name, callable, CONNECT_PERSIST);
			undo_redo.add_undo_method(from_object, &"disconnect", signal_name, callable);
			undo_redo.add_do_method(self, &"notify_scene_connections_updated");
			undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
			undo_redo.commit_action();
		);
	elif port_pair == [editor.port_type(&"signal"), editor.port_type(&"wildcard_in")]:
		var signal_name : StringName = from_graph_node.get_member_from_port_id(from_port, MEMBER_TYPE_SIGNAL).member_name;
		editor.member_selector.show(to_graph_node.object_type, to_object, [MEMBER_TYPE_METHOD], func (selected_object_type, selected_object, selected_member_type, selected_member) -> void:
			editor.current_view.transactions.add_object_view_member(selected_object_type, selected_object, selected_member_type, selected_member);
			var callable := Callable(to_object, selected_member);
			
			var undo_redo := EditorInterface.get_editor_undo_redo();
			undo_redo.create_action("Connect signal", UndoRedo.MERGE_ALL, editor.scene_root, false);
			undo_redo.add_do_method(from_object, &"connect", signal_name, callable, CONNECT_PERSIST);
			undo_redo.add_undo_method(from_object, &"disconnect", signal_name, callable);
			undo_redo.add_do_method(self, &"notify_scene_connections_updated");
			undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
			undo_redo.commit_action();
		);

func _on_disconnection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	if (from_graph_node as GraphNode).get_output_port_type(from_port) != editor.port_type(&"signal"): return;
	if (to_graph_node as GraphNode).get_input_port_type(to_port) != editor.port_type(&"method"): return;
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	var callable := Callable(to_object, to_graph_node.get_member_from_port_id(to_port, MEMBER_TYPE_METHOD).member_name);
	var signal_name : StringName = from_graph_node.get_member_from_port_id(from_port, MEMBER_TYPE_SIGNAL).member_name;
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

# CAPABILITY: configure_member_selector
func get_member_selector_member_types() -> Array[String]:
	return [MEMBER_TYPE_METHOD, MEMBER_TYPE_SIGNAL];

func get_member_selector_tab_info(member_type : String) -> Dictionary:
	match member_type:
		MEMBER_TYPE_METHOD:
			return {
				"label": "Methods",
				"icon": EditorInterface.get_editor_theme().get_icon(ICON_NAME_METHOD, &"EditorIcons"),
				"is_input": true
			};
		MEMBER_TYPE_SIGNAL:
			return {
				"label": "Signals",
				"icon": EditorInterface.get_editor_theme().get_icon(ICON_NAME_SIGNAL, &"EditorIcons"),
				"is_output": true
			};
	return {};

func get_member_selector_member_list(object_type : String, obj : Object, member_type : String) -> Array[Dictionary]:
	var members : Array = [];
	match member_type:
		MEMBER_TYPE_METHOD:
			members.append_array(_collect_members(obj, &"get_script_method_list", &"class_get_method_list", &"get_method_list"));
			members = members.map(func (method_info : Dictionary) -> Dictionary:
				return {
					"member_type": MEMBER_TYPE_METHOD,
					"member_name": method_info.name,
					"label": Utility.get_method_signature_text(method_info),
					"icon": EditorInterface.get_editor_theme().get_icon(ICON_NAME_METHOD, &"EditorIcons")
				}
			);
		MEMBER_TYPE_SIGNAL:
			members.append_array(_collect_members(obj, &"get_script_signal_list", &"class_get_signal_list", &"get_signal_list"));
			members = members.map(func (signal_info : Dictionary) -> Dictionary:
				return {
					"member_type": MEMBER_TYPE_SIGNAL,
					"member_name": signal_info.name,
					"label": Utility.get_method_signature_text(signal_info),
					"icon": EditorInterface.get_editor_theme().get_icon(ICON_NAME_SIGNAL, &"EditorIcons")
				}
			);
	
	return members;
	
func _collect_members(obj : Object, script_getter : StringName, class_getter : StringName, instance_getter : StringName) -> Array:
	var list : Array = [];
	var name_list : Array[StringName] = [];
	
	# Add members by script
	var script : Script = obj.get_script();
	while script != null && script_getter != null:
		if script.has_method(script_getter):
			for def in script.call(script_getter):
				var name : StringName = def["name"];
				if name_list.has(name):
					continue;
				name_list.append(name);
				list.append(def);
		script = script.get_base_script();
	
	# Add members by class
	var cls_name := obj.get_class();
	while cls_name && class_getter != null:
		if ClassDB.has_method(class_getter):
			for def in ClassDB.call(class_getter, cls_name):
				var name : StringName = def["name"];
				if name_list.has(name):
					continue;
				name_list.append(name);
				list.append(def);
		cls_name = ClassDB.get_parent_class(cls_name);
	
	# Add dynamic signals and methods for this specific node
	if instance_getter && obj.has_method(instance_getter):
		var insertion_index := 0;
		for def in obj.call(instance_getter):
			var name : StringName = def["name"];
			if name_list.has(name):
				continue;
			name_list.append(name);
			list.insert(insertion_index, def);
			insertion_index += 1;
	
	return list;
		
# CAPABILITY: initialize_object_graph_node
func initialize_object_graph_node(graph_node : GraphNode) -> void:
	graph_node.set_meta(META_NAME_EXTENSION, SceneObjectGraphNodeExtension.new(graph_node, editor, self));
		
# CAPABILITY: create_object_graph_node_slots
func create_object_graph_node_slots(graph_node : GraphNode) -> Array[Dictionary]:
	if !editor.current_view.get_hook_options(self).enable_method_and_signal_ports: return [];
	return (graph_node.get_meta(META_NAME_EXTENSION) as SceneObjectGraphNodeExtension).create_object_graph_node_slots();
		
# CAPABILITY: create_object_graph_node_slots
func draw_object_graph_node_port(graph_node : GraphNode, slot_index: int, position: Vector2i, left: bool, color: Color) -> bool:
	return (graph_node.get_meta(META_NAME_EXTENSION) as SceneObjectGraphNodeExtension).draw_port(slot_index, position, left, color);

class Utility extends RefCounted:
	static func get_method_signature_text(info : Dictionary) -> String:
		var args : Array = info["args"];
		var raw_defaults = info["default_args"];
		var defaults : Array = raw_defaults as Array if raw_defaults != null else [];
		var s := "";
		s += info["name"] as String;
		s += "(";
		for i in range(args.size()):
			var arg : Dictionary = args[i];
			if i != 0:
				s += ", ";
			
			s += arg["name"] as String;
			s += ": ";
			var type : Variant.Type = arg["type"];
			if type == TYPE_OBJECT:
				s += arg["class_name"] as String;
			elif type == TYPE_NIL:
				s += "Variant";
			else:
				s += type_string(type);
			
			if defaults:
				var arg_index := i - (args.size() - defaults.size());
				var default_value = defaults[arg_index] if arg_index >= 0 && arg_index < defaults.size() else null;
				if default_value != null:
					s += " = ";
					s += str(default_value);
		
		s += ")"; 
		return s;

class SceneObjectGraphNodeExtension extends RefCounted:
	var graph_node : GraphNode;
	var editor : SceneGraphEditor;
	var hook : Object;
	
	func _init(graph_node : GraphNode, editor : SceneGraphEditor, hook : Object) -> void:
		self.graph_node = graph_node;
		self.editor = editor;
		self.hook = hook;
	
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
			
			var cell_control := _create_cell(method_name, ICON_NAME_METHOD, HORIZONTAL_ALIGNMENT_LEFT);
			cell_control.tooltip_text = "Method: " + Utility.get_method_signature_text(method_info);
			
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
			
			var cell_control := _create_cell(signal_name, ICON_NAME_SIGNAL, HORIZONTAL_ALIGNMENT_RIGHT);
			cell_control.tooltip_text = "Signal: " + Utility.get_method_signature_text(signal_info);
			
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
	
	func draw_port(slot_index: int, position: Vector2i, left: bool, color: Color) -> bool:
		# Draw connection line not in view
		var searching_member_type := MEMBER_TYPE_METHOD if left else MEMBER_TYPE_SIGNAL;
		var searching_port_type := editor.port_type(&"method") if left else editor.port_type(&"signal");
		var searching_slot_member_name : StringName = graph_node.get_member_from_slot_id(slot_index, searching_member_type).get("member_name",&"");
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

### CONNECTION SELECTION

func _on_selection_changed_with_script(script : Script, nodes : Array[Node]) -> void:
	if script == ConnectionHandleElement && nodes.all(func (n : Node) -> bool:
			return n.has_meta(META_NAME_EXTENSION);
	):
		select_connections(nodes.map(func (handle : Node):
			return handle.graph_connection;
		).filter(func (c : Dictionary) -> bool:
			var from_graph_node := editor.get_node_or_null(NodePath(c.from_node));
			var to_graph_node := editor.get_node_or_null(NodePath(c.to_node));
			return from_graph_node != null && to_graph_node != null;
		));
	else:
		_stop_editing_connection_properties()

func select_connections(connections : Array) -> void:
	EditorInterface.get_selection().clear();
	var edit_resource : Resource = SignalConnectionPropertyEdit.new();
	edit_resource.setup(editor, connections);
	EditorInterface.inspect_object(edit_resource);

func _stop_editing_connection_properties() -> void:
		if is_instance_of(EditorInterface.get_inspector().get_edited_object(), SignalConnectionPropertyEdit):
			EditorInterface.get_inspector().edit(null);

### CAPABILITY: initialize_connection_handle
func initialize_connection_handle(element : GraphElement) -> void:
	if element.member_connection.from_member_type == MEMBER_TYPE_SIGNAL && element.member_connection.to_member_type == MEMBER_TYPE_METHOD:
		element.set_meta(META_NAME_EXTENSION, ConnectionHandleExtension.new(element, editor, self));

# CAPABILITY: draw_connection_handle
func draw_connection_handle(element : GraphElement, center : Vector2, connection_rotation: float, handle_size : float) -> bool:
	if !element.has_meta(META_NAME_EXTENSION): return false;
	return (element.get_meta(META_NAME_EXTENSION) as ConnectionHandleExtension).draw_connection_handle(center, connection_rotation, handle_size);

class ConnectionHandleExtension extends RefCounted:
	static var ICON_ARGUMENTS : Texture2D = preload("res://addons/scene-graphs/icons/bound_arguments.svg");

	var element : GraphElement;
	var editor : SceneGraphEditor;
	var hook : Object;

	var connection_flags : ConnectFlags = CONNECT_PERSIST;
	var connection_callable : Callable;
	
	func _init(element : GraphElement, editor : SceneGraphEditor, hook : Object) -> void:
		self.element = element;
		self.editor = editor;
		self.hook = hook;
		
		element.repositioned.connect(update_connection_info);
	
	func draw_connection_handle(center : Vector2, connection_rotation : float, handle_size : float) -> bool:
		var theme := EditorInterface.get_editor_theme();
		if (connection_flags & CONNECT_ONE_SHOT) != 0:
			var icon := theme.get_icon("ZoomReset", "EditorIcons") as Texture2D;
			element.draw_set_transform(center, connection_rotation);
			element.draw_texture(icon, Vector2(handle_size*1.5,handle_size*1.5) - icon.get_size() / 2);
		if (connection_flags & CONNECT_DEFERRED) != 0:
			var icon := theme.get_icon("Timer", "EditorIcons") as Texture2D;
			element.draw_set_transform(center, connection_rotation);
			element.draw_texture(icon, Vector2(handle_size*1.5,-handle_size*1.5) - icon.get_size() / 2);
		if (connection_flags & CONNECT_APPEND_SOURCE_OBJECT) != 0 || connection_callable.get_bound_arguments_count() > 0 || connection_callable.get_unbound_arguments_count() > 0:
			var icon := ICON_ARGUMENTS;
			element.draw_set_transform(center, connection_rotation);
			element.draw_texture(icon, Vector2(-handle_size*4.5,0) - icon.get_size() / 2);
		
		element.draw_arrow_handle(center, connection_rotation, handle_size * 1.25);
			
		return true;
	
	func update_connection_info() -> void:
		var from_graph_node : GraphNode = element.get_from_graph_node();
		var to_graph_node : GraphNode = element.get_to_graph_node();
		if !from_graph_node || !to_graph_node: return;
		
		var from_object : Object = from_graph_node.get_object();
		var to_object : Object = to_graph_node.get_object();
		var signal_name : StringName = element.member_connection.from_member_name;
		var method_name : StringName = element.member_connection.to_member_name;
		
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
		if updated: element.queue_redraw();

class Options extends RefCounted:
	@export var enable_method_and_signal_ports : bool = true;