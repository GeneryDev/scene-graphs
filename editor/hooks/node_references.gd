@tool
extends RefCounted

static var SceneObjectGraphNode : Script = preload("res://addons/signal-graphs/editor/elements/scene_object_graph_node.gd");

const OBJECT_TYPE_NODE := "node";
const MEMBER_TYPE_PROPERTY := "properties";
const MEMBER_TYPE_NODE_REFERENCE_OUT := "node_references_out";
const PORT_COLOR_NODE_REFERENCE := Color(0x0067ffff);

const META_NAME_EXTENSION := &"_node_references_extension";

signal scene_connections_updated();

var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
	scene_connections_updated.connect(_on_scene_connections_updated);
	connect_interface_signals();
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["configure_port_types","configure_hook_options","populate_graph_node_connections","initialize_object_graph_node","create_object_graph_node_slots","draw_object_graph_node_port","claim_object_graph_node_member_slots"];

### CAPABILITY: configure_ports
func configure_port_types() -> void:
	editor.register_port_type(&"node_reference_out");
	editor.register_port_type(&"node_reference");
	editor.add_valid_connection_type(editor.port_type(&"node_reference_out"), editor.port_type(&"node_reference"));

### CAPABILITY: configure_hook_options
func get_hook_options_id() -> String:
	return "signal_graphs:node_references";

func get_hook_options_label(options : Options) -> String:
	if options == null: return "Node References";
	return "Node References: %s" % ["Enabled" if options.enable_node_reference_ports else "Disabled"];

func create_hook_options() -> Options:
	return Options.new();

func get_hook_description() -> String:
	return "Sets up ports and connections corresponding to Node or NodePath properties.\nNote: objects must have property members visible in the view, added either by a Member Source view rule, or manually.";

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
		if obj is not Node: continue;
		var node_obj : Node = obj;
		
		# Remove all incoming connections of our handled type -- we'll re-add them after
		for connection in editor.get_connection_list_from_node(graph_node.name):
			if connection.to_node != graph_node.name: continue;
			if !editor.check_connection_port_types(connection, editor.port_type(&"node_reference_out"), editor.port_type(&"node_reference")): continue;
			editor.disconnect_node(connection.from_node, connection.from_port, connection.to_node, connection.to_port);
		
		for property in obj.get_property_list():
			var property_name : StringName = property.name;
			var referenced_node : Node = null;
			if property.type == TYPE_NODE_PATH:
				var path : NodePath = obj.get(property_name);
				if path.get_subname_count() > 0:
					continue;
				referenced_node = node_obj.get_node_or_null(path);
			elif property.type == TYPE_OBJECT && (property.hint & PROPERTY_HINT_NODE_TYPE) != 0:
				referenced_node = obj.get(property_name);
			else:
				continue;
			
			var referenced_graph_node := editor.current_view.get_graph_node_for_object(OBJECT_TYPE_NODE, referenced_node);
			if !referenced_graph_node:
				continue;
			
			var from_port : int = referenced_graph_node.get_member_port_id(MEMBER_TYPE_NODE_REFERENCE_OUT, &"");
			var to_port : int = graph_node.get_member_port_id(MEMBER_TYPE_PROPERTY, property_name);
		
			if from_port == editor.port_type(&"") || to_port == editor.port_type(&""):
				continue;
			
			editor.connect_node(referenced_graph_node.name, from_port, graph_node.name, to_port);
	editor.notify_connections_changed();

### INTERFACE SIGNALS

func connect_interface_signals() -> void:
	editor.connection_request.connect(_on_connection_request);
	editor.disconnection_request.connect(_on_disconnection_request);
	editor.connections_changed.connect(_on_connections_changed);
	
func _on_connection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	if (from_graph_node as GraphNode).get_output_port_type(from_port) != editor.port_type(&"node_reference_out"): return;
	if (to_graph_node as GraphNode).get_input_port_type(to_port) != editor.port_type(&"node_reference"): return;
	
	var from_object : Object = from_graph_node.get_object();
	var to_object : Object = to_graph_node.get_object();
	
	var property_name : StringName = to_graph_node.get_member_from_port_id(to_port, MEMBER_TYPE_PROPERTY).member_name;
	var property_info := Utility.get_property_info_by_name(to_object, property_name);
	var new_value : Variant = null;
	if property_info.type == TYPE_NODE_PATH:
		new_value = to_object.get_path_to(from_object);
	else:
		new_value = from_object;
	
	var undo_redo := EditorInterface.get_editor_undo_redo();
	undo_redo.create_action("Connect node reference", UndoRedo.MERGE_ALL, editor.scene_root, false);
	undo_redo.add_do_property(to_object, property_name, new_value);
	undo_redo.add_undo_property(to_object, property_name, to_object.get(property_name));
	undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	undo_redo.commit_action();

func _on_disconnection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
	var from_graph_node := editor.get_node(NodePath(from_node_name));
	var to_graph_node := editor.get_node(NodePath(to_node_name));
	if !is_instance_of(from_graph_node, SceneObjectGraphNode): return;
	if !is_instance_of(to_graph_node, SceneObjectGraphNode): return;
	
	if (from_graph_node as GraphNode).get_output_port_type(from_port) != editor.port_type(&"node_reference_out"): return;
	if (to_graph_node as GraphNode).get_input_port_type(to_port) != editor.port_type(&"node_reference"): return;
	
	var to_object : Object = to_graph_node.get_object();
	
	var property_name : StringName = to_graph_node.get_member_from_port_id(to_port, MEMBER_TYPE_PROPERTY).member_name;
	var property_info := Utility.get_property_info_by_name(to_object, property_name);
	var new_value : Variant = null;
	if property_info.type == TYPE_NODE_PATH:
		new_value = NodePath();
	else:
		new_value = null;
	
	var undo_redo := EditorInterface.get_editor_undo_redo();
	undo_redo.create_action("Disconnect node reference", UndoRedo.MERGE_ALL, editor.scene_root, false);
	undo_redo.add_do_property(to_object, property_name, new_value);
	undo_redo.add_undo_property(to_object, property_name, to_object.get(property_name));
	undo_redo.add_do_method(self, &"notify_scene_connections_updated");
	undo_redo.add_undo_method(self, &"notify_scene_connections_updated");
	undo_redo.commit_action();

func _on_connections_changed() -> void:
	pass;
#	for child : Node in editor.get_children():
#		if !is_instance_of(child, SceneObjectGraphNode):
#			continue;
		
# CAPABILITY: initialize_object_graph_node
func initialize_object_graph_node(graph_node : GraphNode) -> void:
	graph_node.set_meta(META_NAME_EXTENSION, SceneObjectGraphNodeExtension.new(graph_node, editor, self));
		
# CAPABILITY: create_object_graph_node_slots
func create_object_graph_node_slots(graph_node : GraphNode) -> Array[Dictionary]:
	if !editor.current_view.get_hook_options(self).enable_node_reference_ports: return [];
	return (graph_node.get_meta(META_NAME_EXTENSION) as SceneObjectGraphNodeExtension).create_object_graph_node_slots();
		
# CAPABILITY: create_object_graph_node_slots
func draw_object_graph_node_port(graph_node : GraphNode, slot_index: int, position: Vector2i, left: bool, color: Color) -> bool:
	return (graph_node.get_meta(META_NAME_EXTENSION) as SceneObjectGraphNodeExtension).draw_port(slot_index, position, left, color);

### CAPABILITY: claim_object_graph_node_member_slots
func get_object_graph_node_member_slot_bid(object_type : String, object : Object, member_type : String, member_name : StringName) -> float:
	if member_type == MEMBER_TYPE_PROPERTY && Utility.is_property_node_reference(Utility.get_property_info_by_name(object, member_name)):
		return 2;
	return 0;

class Utility extends RefCounted:
	static func get_property_info_by_name(obj : Object, property_name : StringName) -> Dictionary:
		for property_info in obj.get_property_list():
			if property_info["name"] != property_name: continue;
			return property_info;
		return {};
	
	static func is_property_node_reference(property : Dictionary) -> bool:
		if property.type == TYPE_NODE_PATH:
			return true;
		elif property.type == TYPE_OBJECT && (property.hint & PROPERTY_HINT_NODE_TYPE) != 0:
			return true;
		return false;

class SceneObjectGraphNodeExtension extends RefCounted:
	var graph_node : GraphNode;
	var editor : SignalGraphEditor;
	var hook : Object;
	
	func _init(graph_node : GraphNode, editor : SignalGraphEditor, hook : Object) -> void:
		self.graph_node = graph_node;
		self.editor = editor;
		self.hook = hook;
		
	func create_object_graph_node_slots() -> Array[Dictionary]:
		var created : Array[Dictionary] = [];
		if graph_node.object_type != OBJECT_TYPE_NODE: return created;
		
		if editor.current_view.has_object_view_member(graph_node.object_type, graph_node.get_object(), MEMBER_TYPE_NODE_REFERENCE_OUT, &""):
			created.append(create_path_header_slot());
		
		var property_slots := create_property_slots();
		created.append_array(property_slots);
		
		return created;
	
	func create_path_header_slot() -> Dictionary:
		var header_control := _create_row("", &"NodePath", HORIZONTAL_ALIGNMENT_RIGHT);
		return {
			"control": header_control,
			"sort_key": -100,
			"right_port": {
				"port_type": editor.port_type(&"node_reference_out"),
				"port_color": PORT_COLOR_NODE_REFERENCE,
				"member": {
					"member_type": MEMBER_TYPE_NODE_REFERENCE_OUT,
					"member_name": &""
				}
			}
		};
	
	func create_property_slots() -> Array[Dictionary]:
		var created : Array[Dictionary] = [];
		var obj : Object = graph_node.get_object();
		for property_name in editor.current_view.get_object_view_members(graph_node.object_type, obj, MEMBER_TYPE_PROPERTY):
			var property_info := Utility.get_property_info_by_name(obj, property_name);
			if !Utility.is_property_node_reference(property_info): continue;
			if !graph_node.claim_object_graph_node_member_slot(hook, MEMBER_TYPE_PROPERTY, property_name): continue;
			if !property_info:
				print("No property found for name '" + property_name + "' in object " + str(obj));
				continue;
			
			var row_control := _create_row(property_name.capitalize(), "NodePath", HORIZONTAL_ALIGNMENT_LEFT);
			row_control.tooltip_text = "Property: " + property_name + ": " + type_string(property_info.type);
			
			created.append({
				"control": row_control,
				"sort_key": 0,
				"left_port": {
					"port_type": editor.port_type(&"node_reference"),
					"port_color": PORT_COLOR_NODE_REFERENCE,
					"member": {
						"member_type": MEMBER_TYPE_PROPERTY,
						"member_name": property_name
					}
				}
			});
		return created;
	
	func _create_row(text : String, icon : String, alignment : HorizontalAlignment) -> Control:
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
		return false;
	
class Options extends RefCounted:
	@export var enable_node_reference_ports : bool = false;