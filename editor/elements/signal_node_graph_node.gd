extends GraphNode

var node_instance_id : int;

var _editor : SignalGraphEditor;
var _method_ports : Dictionary[StringName, int];
var _signal_ports : Dictionary[StringName, int];
var _force_shown_methods : Array[StringName];
var _force_shown_signals : Array[StringName];

var _collapsible_panel : Control;

var _stored_input_connections : Array[StoredConnection];
var _stored_output_connections : Array[StoredConnection];

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	node_selected.connect(_on_node_selected);
	node_deselected.connect(_on_node_deselected);
	pass;

func get_object() -> Node:
	return instance_from_id(node_instance_id) as Node;

func setup(node : Node, saved_data : Dictionary, editor : SignalGraphEditor) -> bool:
	_editor = editor;
	
	node_instance_id = node.get_instance_id();
	name = str(node_instance_id);
	title = node.name;
	
	var icon := editor.utility.get_object_icon(node);
	if icon:
		var icon_rect := TextureRect.new();
		icon_rect.texture = icon;
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
		get_titlebar_hbox().add_child(icon_rect, INTERNAL_MODE_FRONT);
	
	_signal_ports = {};
	_method_ports = {};
	
	# Create collapsible panel
	_collapsible_panel = VBoxContainer.new();
	var add_button := Button.new();
	add_button.text = "+";
	add_button.pressed.connect(_on_add_button_pressed);
	_collapsible_panel.add_child(add_button);
	
	# Add ports and any children
	var any_ports := create_and_add_contents(node);
	
	# Deserialize saved data
	if saved_data:
		position_offset = saved_data["position_offset"] as Vector2;
	else:
		position_offset = Vector2.ZERO;
	
	return any_ports;
	
func rebuild_contents() -> bool:
	clear_all_slots();
	for child in get_children():
		remove_child(child)
		if child != _collapsible_panel:
			child.queue_free();
	
	return create_and_add_contents(get_object());

func create_and_add_contents(node : Node) -> bool:
	var any_ports := false;
	if _collapsible_panel != null && self.is_ancestor_of(_collapsible_panel):
		remove_child(_collapsible_panel);
	
	if add_signal_ports(node):
		any_ports = true;
	if add_method_ports(node):
		any_ports = true;
	
	_add_collapsible_panel();
	return any_ports;

func _add_collapsible_panel() -> void:
	_update_collapsible_panel_visibility()
	add_child(_collapsible_panel);
	set_slot(_collapsible_panel.get_index(),
	true,
		SignalGraphEditor.PORT_TYPE_ADD_METHOD,
		Color(0x73f280ff),
		true,
		SignalGraphEditor.PORT_TYPE_ADD_SIGNAL,
		Color(0xff786bff)
	);

func add_signal_ports(node : Node) -> bool:
	var any_ports := false;
	_signal_ports.clear();
	var left_port_index := 0;
	for signal_info in node.get_signal_list():
		var signal_name := signal_info["name"] as StringName;
		
		if !should_show_signal(signal_name, signal_info, node):
			continue;
		
		var row_control := _create_row("", signal_name, SignalGraphEditor.ICON_NAME_SIGNAL);
		row_control.tooltip_text = "Signal: " + SignalGraphEditor.Utility.get_method_signature_text(signal_info);
		add_child(row_control);
		
		set_slot(
			get_child_count()-1,
			false,
			SignalGraphEditor.PORT_TYPE_NONE,
			Color.BLACK,
			true,
			SignalGraphEditor.PORT_TYPE_SIGNAL,
			Color(0xff786bff)
		);
		_signal_ports[signal_name] = left_port_index;
		
		left_port_index += 1;
		any_ports = true;
	
	return any_ports;

func add_method_ports(node : Node) -> bool:
	var any_ports := false;
	_method_ports.clear();
	var right_port_index := 0;
	var connected_method_names : Array[StringName] = SignalGraphEditor.Utility.get_connected_method_names(node);
	
	for method_info in node.get_method_list():
		var method_name := method_info["name"] as StringName;
		if _method_ports.has(method_name):
			continue; # skip method overloads
		
		if !should_show_method(method_name, method_info, node, connected_method_names):
			continue;
		
		var row_control := _create_row(SignalGraphEditor.ICON_NAME_METHOD, method_name, "");
		row_control.tooltip_text = "Method: " + SignalGraphEditor.Utility.get_method_signature_text(method_info);
		add_child(row_control);
		
		set_slot(
			get_child_count()-1,
			true,
			SignalGraphEditor.PORT_TYPE_SIGNAL,
			Color(0x73f280ff),
			false,
			SignalGraphEditor.PORT_TYPE_NONE,
			Color.BLACK
		);
		_method_ports[method_name] = right_port_index;
		
		right_port_index += 1;
		any_ports = true;
	
	return any_ports;
	
func should_show_method(method_name : String, method_info : Dictionary, node : Node, connected_method_names : Array[StringName]) -> bool:
	if _force_shown_methods.has(method_name):
		return true;
	
	# Check if method has an incoming connection
	if connected_method_names == null:
		connected_method_names = SignalGraphEditor.Utility.get_connected_method_names(node);
	
	var port_connected := connected_method_names.has(method_name);
	
	if port_connected:
		return true;
		
	# TODO user-defined logic
		
	return false;
	
func should_show_signal(signal_name : String, signal_info : Dictionary, node : Node) -> bool:
	if _force_shown_signals.has(signal_name):
		return true;

	for connection in node.get_signal_connection_list(signal_name):
		var flags := connection["flags"] as ConnectFlags;
		if (flags & ConnectFlags.CONNECT_PERSIST) != 0:
			return true;
		
	# TODO user-defined logic
		
	return false;

func _on_add_button_pressed() -> void:
	SignalGraphEditor.Selector.show(get_object(), -1, method_add_requested, signal_add_requested);

func _create_row(icon_left : String, text : String, icon_right : String) -> Control:
	var label := Label.new();
	label.text = text;
	label.size_flags_horizontal = SIZE_EXPAND_FILL;
	var height := label.get_minimum_size().y;
	
	var icon_rect_left := _create_icon_control(icon_left, height);
	var icon_rect_right := _create_icon_control(icon_right, height);
	var max_minimum_size := Vector2(
		max(icon_rect_left.get_minimum_size().x, icon_rect_right.get_minimum_size().x),
		max(icon_rect_left.get_minimum_size().y, icon_rect_right.get_minimum_size().y)
	);
	icon_rect_left.custom_minimum_size = max_minimum_size;
	icon_rect_right.custom_minimum_size = max_minimum_size;
	
	var container := HBoxContainer.new();
	container.add_child(icon_rect_left);
	container.add_child(label);
	container.add_child(icon_rect_right);
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

func _on_node_selected() -> void:
	_update_collapsible_panel_visibility();
	var node := get_object();
	if node:
		EditorInterface.edit_node(node);

func _update_collapsible_panel_visibility():
	_collapsible_panel.visible = selected && get_rect().has_point(_editor.get_local_mouse_position());
	reset_size();

func _on_node_deselected() -> void:
	_collapsible_panel.visible = false;
	reset_size();

func get_signal_port_id(signal_name : StringName) -> int:
	return _signal_ports[signal_name] if _signal_ports.has(signal_name) else -1;

func get_method_port_id(method_name : StringName) -> int:
	return _method_ports[method_name] if _method_ports.has(method_name) else -1;

func get_signal_port_name(port_id : int) -> StringName:
	for key in _signal_ports:
		if _signal_ports[key] == port_id:
			return key;
	return &"";

func get_method_port_name(port_id : int) -> StringName:
	for key in _method_ports:
		if _method_ports[key] == port_id:
			return key;
	return &"";

func get_save_data() -> Dictionary:
	var dict := {};
	dict["position_offset"] = position_offset;
	return dict;

func method_add_requested(method_info : Dictionary) -> void:
	var method_name := method_info["name"] as StringName;
	if !_force_shown_methods.has(method_name):
		_force_shown_methods.push_back(method_name);
	
	_store_connections(true);
	
	rebuild_contents();
	_collapsible_panel.visible = true;
	
	_restore_connections();

func signal_add_requested(signal_info : Dictionary) -> void:
	var signal_name := signal_info["name"] as StringName;
	if !_force_shown_signals.has(signal_name):
		_force_shown_signals.push_back(signal_name);
	
	_store_connections(true);
	
	rebuild_contents();
	_collapsible_panel.visible = true;
	
	_restore_connections();

func _store_connections(disconnect : bool) -> void:
	_stored_input_connections.clear();
	_stored_output_connections.clear();
	
	for connection in _editor.get_connection_list():
		var from_node := connection["from_node"] as StringName;
		var to_node := connection["to_node"] as StringName;
		var from_port := connection["from_port"] as int;
		var to_port := connection["to_port"] as int;
		if to_node == name:
			_stored_input_connections.push_back(StoredConnection.create_from_input(from_node, to_node, from_port, to_port, self));
		elif from_node == name:
			_stored_output_connections.push_back(StoredConnection.create_from_output(from_node, to_node, from_port, to_port, self));
		else:
			continue;
			
		if disconnect:
			_editor.disconnect_node(from_node, from_port, to_node, to_port);

func _restore_connections():
	for stored_connection in _stored_input_connections:
		print("Restoring input connection: " + str(stored_connection));
		stored_connection.restore_input(self, _editor);
	for stored_connection in _stored_output_connections:
		print("Restoring output connection: " + str(stored_connection));
		stored_connection.restore_output(self, _editor);
		

class StoredConnection:
	### The name of the method/signal that this connection was made with, in this node.
	var this_port_name : StringName;
	### The name of the other graph node this connection was made with.
	var other_node_name : StringName;
	### The index of the port via which the other graph node was connected.
	var other_node_port : int;
	
	# NOTE: If OtherNodePort is -1, it has a special meaning: this connection represents a connection between this node and itself.
	# In which case, the OtherNodeName field will instead store the name of the method it was connected to, and ThisPortName will store the signal.
	
	func is_self_connection() -> bool:
		return other_node_port == -1;
		
	func _init(this_port_name : StringName, other_node_name : StringName, other_node_port : int):
		self.this_port_name = this_port_name;
		self.other_node_name = other_node_name;
		self.other_node_port = other_node_port;
	
	static func create_from_self(from_node : StringName, to_node : StringName, from_port : int, to_port : int, graph_node: GraphNode) -> StoredConnection:
		var signal_name : StringName = graph_node.get_signal_port_name(from_port);
		var method_name : StringName = graph_node.get_method_port_name(to_port);
		return StoredConnection.new(signal_name, method_name, -1);
	
	static func create_from_input(from_node : StringName, to_node : StringName, from_port : int, to_port : int, graph_node: GraphNode) -> StoredConnection:
		if from_node == to_node:
			# self connection
			return create_from_self(from_node, to_node, from_port, to_port, graph_node);
			
		var method_name : StringName = graph_node.get_method_port_name(to_port);
	
		return StoredConnection.new(method_name, from_node, from_port);
	
	static func create_from_output(from_node : StringName, to_node : StringName, from_port : int, to_port : int, graph_node: GraphNode) -> StoredConnection:
		if from_node == to_node:
			# self connection
			return create_from_self(from_node, to_node, from_port, to_port, graph_node);
		
		var signal_name : StringName = graph_node.get_signal_port_name(from_port);
	
		return StoredConnection.new(signal_name, to_node, to_port);
	
	func restore_self(graph_node : GraphNode, editor : SignalGraphEditor) -> void:
		var from_port : int = graph_node.get_signal_port_id(this_port_name);
		var to_port : int = graph_node.get_method_port_id(other_node_name);
		editor.connect_node(graph_node.name, from_port, graph_node.name, to_port);
		
	func restore_input(graph_node : GraphNode, editor : SignalGraphEditor) -> void:
		if is_self_connection():
			restore_self(graph_node, editor);
			return;
		
		var to_port : int = graph_node.get_method_port_id(other_node_name);
		editor.connect_node(other_node_name, other_node_port, graph_node.name, to_port);
	
	func restore_output(graph_node : GraphNode, editor : SignalGraphEditor) -> void:
		if is_self_connection():
			restore_self(graph_node, editor);
			return;
			
		var from_port : int = graph_node.get_signal_port_id(this_port_name);
		editor.connect_node(graph_node.name, from_port, other_node_name, other_node_port);
	
	func _to_string() -> String:
		return "this_port_name: " + str(this_port_name) + ", other_node_name: " + str(other_node_name) + ", other_node_port: " + str(other_node_port);