extends GraphNode

var obj_instance_id : int;

var editor : SignalGraphEditor;
var view_interface;
var _method_ports : Dictionary[StringName, int];
var _signal_ports : Dictionary[StringName, int];

var _collapsible_panel : Control;

func _init(obj : Object, editor : SignalGraphEditor, view_interface):
	self.editor = editor;
	self.view_interface = view_interface;
	
	obj_instance_id = obj.get_instance_id();
	name = str(obj_instance_id);
	title = obj.name if obj is Node else (obj.resource_name if obj is Resource else str(obj));
	
	var icon := editor.utility.get_object_icon(obj);
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
	
	position_offset_changed.connect(_on_position_offset_changed);
	node_selected.connect(_on_node_selected);
	node_deselected.connect(_on_node_deselected);

func get_object() -> Object:
	return instance_from_id(obj_instance_id) as Object;

func update_from_view() -> void:
	var obj := get_object();
	var obj_view = view_interface.get_object_view(obj);
	
	rebuild_contents_from_view(obj_view);
	
	if obj_view.has("position_offset"):
		position_offset = obj_view["position_offset"] as Vector2;
	
func update_view() -> void:
	var obj := get_object();
	var obj_view = view_interface.get_object_view(obj);
	if !obj_view: return;
	
	obj_view["position_offset"] = position_offset;
	
func rebuild_contents_from_view(obj_view : Dictionary) -> bool:
	clear_all_slots();
	for child in get_children():
		remove_child(child)
		if child != _collapsible_panel:
			child.queue_free();
	
	return create_and_add_contents(obj_view);

func create_and_add_contents(obj_view : Dictionary) -> bool:
	var obj := get_object();
	var any_ports := false;
	if _collapsible_panel != null && self.is_ancestor_of(_collapsible_panel):
		remove_child(_collapsible_panel);
	
	if add_signal_ports(obj, obj_view):
		any_ports = true;
	if add_method_ports(obj, obj_view):
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

func add_signal_ports(obj : Object, obj_view : Dictionary) -> bool:
	var any_ports := false;
	_signal_ports.clear();
	var left_port_index := 0;
	for signal_name in obj_view.signals:
		var signal_info := get_signal_info_by_name(obj, signal_name);
		
		var row_control := _create_row("", signal_name, SignalGraphEditor.ICON_NAME_SIGNAL);
		row_control.tooltip_text = "Signal: " + SignalGraphEditor.Utility.get_method_signature_text(signal_info);
		add_child(row_control);
		
		set_slot(
			get_child_count()-1,
			false,
			editor.port_type(&""),
			Color.BLACK,
			true,
			editor.port_type(&"signal"),
			Color(0xff786bff)
		);
		_signal_ports[signal_name] = left_port_index;
		
		left_port_index += 1;
		any_ports = true;
	
	return any_ports;

func add_method_ports(obj : Object, obj_view : Dictionary) -> bool:
	var any_ports := false;
	_method_ports.clear();
	var right_port_index := 0;
	
	for method_name in obj_view.methods:
		var method_info := get_method_info_by_name(obj, method_name);
		if _method_ports.has(method_name):
			continue; # skip method overloads
		
		var row_control := _create_row(SignalGraphEditor.ICON_NAME_METHOD, method_name, "");
		row_control.tooltip_text = "Method: " + SignalGraphEditor.Utility.get_method_signature_text(method_info);
		add_child(row_control);
		
		set_slot(
			get_child_count()-1,
			true,
			editor.port_type(&"method"),
			Color(0x73f280ff),
			false,
			editor.port_type(&""),
			Color.BLACK
		);
		_method_ports[method_name] = right_port_index;
		
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

func method_add_requested(method_info : Dictionary) -> void:
	var method_name := method_info["name"] as StringName;
	view_interface.transactions.add_object_view_method(get_object(), method_name);

func signal_add_requested(signal_info : Dictionary) -> void:
	var signal_name := signal_info["name"] as StringName;
	view_interface.transactions.add_object_view_signal(get_object(), signal_name);

func _on_position_offset_changed() -> void:
	update_view();