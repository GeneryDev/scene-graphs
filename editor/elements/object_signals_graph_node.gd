extends GraphNode

const MEMBER_TYPE_METHOD := "methods";
const MEMBER_TYPE_SIGNAL := "signals";

var obj_instance_id : int;

var editor : SignalGraphEditor;
var _method_ports : Dictionary[StringName, int];
var _signal_ports : Dictionary[StringName, int];
var _method_slots : Dictionary[StringName, int];
var _signal_slots : Dictionary[StringName, int];

var _collapsible_panel : Control;
var _connections_not_in_view : Array = [];

func _init(obj : Object, editor : SignalGraphEditor):
	self.editor = editor;
	
	obj_instance_id = obj.get_instance_id();
	name = str(obj_instance_id);
	title = obj.name if obj is Node else (obj.resource_name if obj is Resource else str(obj));
	
	var icon := SignalGraphEditor.Utility.get_object_icon(obj);
	if icon:
		var icon_rect := TextureRect.new();
		icon_rect.texture = icon;
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
		get_titlebar_hbox().add_child(icon_rect, INTERNAL_MODE_FRONT);
		get_titlebar_hbox().move_child(icon_rect, 0);
		get_titlebar_hbox().add_theme_constant_override("separation", 8);
	
	_signal_ports = {};
	_method_ports = {};
	_signal_slots = {};
	_method_slots = {};
	
	# Create collapsible panel
	_collapsible_panel = VBoxContainer.new();
	var add_button := Button.new();
	add_button.text = "+";
	add_button.pressed.connect(_on_add_button_pressed);
	_collapsible_panel.add_child(add_button);
	
	position_offset_changed.connect(_on_position_offset_changed);
	node_selected.connect(_on_node_selected);
	node_deselected.connect(_on_node_deselected);

func get_object() -> Object:
	return instance_from_id(obj_instance_id) as Object;

func _enter_tree() -> void:
	editor.connections_changed.connect(_update_connection_cache);
	_update_connection_cache();
func _exit_tree() -> void:
	editor.connections_changed.disconnect(_update_connection_cache);

func _update_connection_cache() -> void:
	_connections_not_in_view.clear();
	var obj := get_object();

	var incoming_connections := obj.get_incoming_connections();
	var seen_method_names : Array = [];
	
	for method_info in obj.get_method_list():
		var method_name := method_info["name"] as StringName;
		if seen_method_names.has(method_name): continue;
		seen_method_names.append(method_name);
		if !editor.view.has_object_view_member(obj, MEMBER_TYPE_METHOD, method_name): continue;
		
		for method_connection in incoming_connections:
			if(method_connection.flags & CONNECT_PERSIST) == 0: continue;
			if method_connection.callable.get_method() as StringName != method_name: continue;
			var sgnal : Signal = method_connection.signal;
			var source : Object = sgnal.get_object();
			if !editor.view.has_object_view(source):
				_connections_not_in_view.append({
					"port_type": editor.port_type(&"method"),
					"member_name": method_name,
					"other_instance_id": source.get_instance_id()
				});
	
	for signal_info in obj.get_signal_list():
		var signal_name := signal_info["name"] as StringName;
		if !editor.view.has_object_view_member(obj, MEMBER_TYPE_SIGNAL, signal_name): continue;
		
		for signal_connection in obj.get_signal_connection_list(signal_name):
			if(signal_connection.flags & CONNECT_PERSIST) == 0: continue;
			var callable : Callable = signal_connection.callable;
			var target : Object = callable.get_object();
			if !editor.view.has_object_view(target):
				_connections_not_in_view.append({
					"port_type": editor.port_type(&"signal"),
					"member_name": signal_name,
					"other_instance_id": target.get_instance_id()
				});

func update_from_view() -> void:
	var obj := get_object();
	var obj_view = editor.view.get_object_view(obj);
	
	rebuild_contents_from_view();
	
	if obj_view.has("position_offset"):
		position_offset = obj_view["position_offset"] as Vector2;
	
func update_view() -> void:
	var obj := get_object();
	var obj_view = editor.view.get_object_view(obj);
	if !obj_view: return;
	
	obj_view["position_offset"] = position_offset;
	
func rebuild_contents_from_view() -> bool:
	clear_all_slots();
	for child in get_children():
		remove_child(child)
		if child != _collapsible_panel:
			child.queue_free();
	
	return create_and_add_contents();

func create_and_add_contents() -> bool:
	var obj := get_object();
	var any_ports := false;
	if _collapsible_panel != null && self.is_ancestor_of(_collapsible_panel):
		remove_child(_collapsible_panel);
	
	if add_signal_ports(obj):
		any_ports = true;
	if add_method_ports(obj):
		any_ports = true;
	
	_add_collapsible_panel();
	return any_ports;

func _add_collapsible_panel() -> void:
	_update_collapsible_panel_visibility()
	add_child(_collapsible_panel);
	set_slot(_collapsible_panel.get_index(),
	true,
		editor.port_type(&"add_method"),
		Color(0x73f280ff),
		true,
		editor.port_type(&"add_signal"),
		Color(0xff786bff)
	);

func get_signal_info_by_name(obj : Object, signal_name : StringName) -> Dictionary:
	for signal_info in obj.get_signal_list():
		if signal_info["name"] != signal_name: continue;
		return signal_info;
	return {};

func get_method_info_by_name(obj : Object, method_name : StringName) -> Dictionary:
	for method_info in obj.get_method_list():
		if method_info["name"] != method_name: continue;
		return method_info;
	return {};

func add_signal_ports(obj : Object) -> bool:
	var any_ports := false;
	_signal_ports.clear();
	var left_port_index := 0;
	for signal_name in editor.view.get_object_view_members(obj, MEMBER_TYPE_SIGNAL):
		var signal_info := get_signal_info_by_name(obj, signal_name);
		
		var row_control := _create_row("", signal_name, SignalGraphEditor.ICON_NAME_SIGNAL);
		row_control.tooltip_text = "Signal: " + SignalGraphEditor.Utility.get_method_signature_text(signal_info);
		add_child(row_control);
		
		var slot_index := get_child_count()-1;
		set_slot(
			slot_index,
			false,
			editor.port_type(&""),
			Color.BLACK,
			true,
			editor.port_type(&"signal"),
			Color(0xff786bff)
		);
		_signal_ports[signal_name] = left_port_index;
		_signal_slots[signal_name] = slot_index;
		
		left_port_index += 1;
		any_ports = true;
	
	return any_ports;

func add_method_ports(obj : Object) -> bool:
	var any_ports := false;
	_method_ports.clear();
	var right_port_index := 0;
	
	for method_name in editor.view.get_object_view_members(obj, MEMBER_TYPE_METHOD):
		var method_info := get_method_info_by_name(obj, method_name);
		if _method_ports.has(method_name):
			continue; # skip method overloads
		
		var row_control := _create_row(SignalGraphEditor.ICON_NAME_METHOD, method_name, "");
		row_control.tooltip_text = "Method: " + SignalGraphEditor.Utility.get_method_signature_text(method_info);
		add_child(row_control);
		
		var slot_index := get_child_count()-1;
		set_slot(
			slot_index,
			true,
			editor.port_type(&"method"),
			Color(0x73f280ff),
			false,
			editor.port_type(&""),
			Color.BLACK
		);
		_method_ports[method_name] = right_port_index;
		_method_slots[method_name] = slot_index;
		
		right_port_index += 1;
		any_ports = true;
	
	return any_ports;
	
func _on_add_button_pressed() -> void:
	SignalGraphEditor.Selector.show(get_object(), -1, method_add_requested, signal_add_requested);

func _create_row(icon_left : String, text : String, icon_right : String) -> Control:
	var label := Label.new();
	label.text = text;
	label.size_flags_horizontal = SIZE_EXPAND_FILL;
	var height := label.get_minimum_size().y;
	
	var icon_rect_left := _create_icon_control(icon_left, int(height));
	var icon_rect_right := _create_icon_control(icon_right, int(height));
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
	_collapsible_panel.visible = selected && get_rect().has_point(editor.get_local_mouse_position());
	reset_size();

func _update_collapsible_panel_visibility():
	_collapsible_panel.visible = selected;
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

func get_signal_slot_name(slot_index : int) -> StringName:
	for key in _signal_slots:
		if _signal_slots[key] == slot_index:
			return key;
	return &"";

func get_method_slot_name(slot_index : int) -> StringName:
	for key in _method_slots:
		if _method_slots[key] == slot_index:
			return key;
	return &"";

func method_add_requested(method_info : Dictionary) -> void:
	var method_name := method_info["name"] as StringName;
	editor.view.transactions.add_object_view_member(get_object(), MEMBER_TYPE_METHOD, method_name);

func signal_add_requested(signal_info : Dictionary) -> void:
	var signal_name := signal_info["name"] as StringName;
	editor.view.transactions.add_object_view_signal(get_object(), MEMBER_TYPE_SIGNAL, signal_name);

func _on_position_offset_changed() -> void:
	update_view();
	
func _draw_port(slot_index: int, position: Vector2i, left: bool, color: Color) -> void:
	# default drawing
	var port_icon := get_slot_custom_icon_left(slot_index) if left else get_slot_custom_icon_right(slot_index);
	if !port_icon:
		port_icon = get_theme_icon("port");
		
	if !port_icon:
		return;

	var icon_offset : Vector2;
	icon_offset = -port_icon.get_size() * 0.5;
	draw_texture(port_icon, Vector2(position) + icon_offset, color);
	
	# connection line not in view
	var searching_port_type := editor.port_type(&"method") if left else editor.port_type(&"signal");
	var searching_slot_member_name := get_method_slot_name(slot_index) if left else get_signal_slot_name(slot_index);
	var found_connection_index := _connections_not_in_view.find_custom(func (c : Dictionary) -> bool:
		return c.port_type == searching_port_type && c.member_name == searching_slot_member_name;
	);
	if found_connection_index != -1:
		var line_dir := Vector2(-1, 0) if left else Vector2(1, 0);
		var line_length := 40;
		draw_polyline_colors([Vector2(position), Vector2(position) + line_dir * line_length], [color, color * Color(1,1,1,0)], 4, true);