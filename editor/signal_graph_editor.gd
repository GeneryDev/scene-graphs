@tool
class_name SignalGraphEditor
extends GraphEdit

const ICON_NAME_SIGNAL := "Signal";
const ICON_NAME_METHOD := "Slot";

signal connections_changed();
signal selection_changed();
signal view_updated();
signal selection_changed_with_script(script : Script, selected_nodes : Array[Node]);
signal connection_line_cache_invalidated();

var scene_root : Node:
	get: return EditorInterface.get_edited_scene_root();
var selected_nodes : Array[StringName] = [];
var dragging : bool = false;

var interface_signals : InterfaceSignals;
var utility : Utility;
var hooks : Hooks;

var current_view : SignalGraphView:
	get:
		return current_view;
	set(value):
		if current_view:
			current_view.view_updated.disconnect(_on_current_view_updated);
		current_view = value;
		if current_view:
			current_view.view_updated.connect(_on_current_view_updated);
		
var connections_layer : Control;

var _port_types_by_name : Dictionary[StringName, int] = {
	&"": -1
};
var _next_port_type_idx := 0;
var _pending_rearrange_after_load := false;

func _init():
	interface_signals = InterfaceSignals.new(self);
	utility = Utility.new(self);
	
	connections_layer = get_node(^"_connection_layer");
	hooks = Hooks.new(self);

### CORE

func _ready() -> void:
	if is_part_of_edited_scene():
		return;
	hooks._initialize_hooks();
	interface_signals.connect_all();
	for hook in hooks.configure_port_types:
		hook.configure_port_types();

func clear():
	_pending_rearrange_after_load = false;
	clear_connections();
	notify_connections_changed();
	for child in get_children():
		if child is not GraphElement:
			continue;
		remove_child(child);
		child.queue_free();
	selected_nodes.clear();
	notify_selection_changed();

func load(view : SignalGraphView) -> void:
	assert(view != null, "Cannot load a null signal graph view");
	current_view = view;
	if view:
		view.update_object_views_with_rules();
		view.update_all_object_member_views_with_rules();
	
		if view.scene_data.has("zoom"):
			zoom = view.scene_data.zoom;
		if view.scene_data.has("scroll_offset"):
			scroll_offset = view.scene_data.scroll_offset;
	else:
		view.clear_all_objects();
		view.update_object_views_with_rules();
		view.update_all_object_member_views_with_rules();
	
	view.notify_view_updated();
	
	if is_visible_in_tree():
		call_deferred(&"rearrange_after_load");
	else:
		_pending_rearrange_after_load = true;

func _on_current_view_updated():
	for hook in hooks.populate_graph_nodes_from_view:
		hook.populate_graph_nodes_from_view();
	for hook in hooks.populate_graph_node_connections:
		hook.populate_graph_node_connections();
	view_updated.emit();

func rearrange_after_load():
	_pending_rearrange_after_load = false;
#	arrange_nodes();

func port_type(name : StringName) -> int:
	if _port_types_by_name.has(name):
		return _port_types_by_name[name];
	else:
		printerr("No such signal graph port type name '" + str(name) + "'");
		return -2;

func register_port_type(name : StringName) -> int:
	if _port_types_by_name.has(name):
		printerr("Signal graph port type '" + str(name) + "' has already been defined!");
		return _port_types_by_name[name];
	var idx := _next_port_type_idx;
	_next_port_type_idx += 1;
	_port_types_by_name[name] = idx;
	return idx;
	
var _selection_change_queued := false;

func notify_selection_changed(throttled : bool = true) -> void:
	if throttled:
		if _selection_change_queued:
			return;
		else:
			call_deferred(&"notify_selection_changed", false);
			_selection_change_queued = true;
			return;
	_selection_change_queued = false;
	
	var only_script : Script = null;
	var only_script_nodes : Array[Node];
	var script_set := false;
	for node_name in selected_nodes:
		var node := get_node(NodePath(node_name));
		var script : Script = node.get_script();
		if !script_set:
			only_script = script;
			script_set = true;
		elif only_script != script:
			only_script = null;
		
		only_script_nodes.append(node);
	
	selection_changed.emit();
	selection_changed_with_script.emit(only_script, only_script_nodes);

func notify_connections_changed() -> void:
	connections_changed.emit();
	
func invalidate_connection_line_cache() -> void:
	connection_lines_curvature = connection_lines_curvature;
	connection_line_cache_invalidated.emit();

func connect_node_and_notify(from_node : StringName, from_port : int, to_node : StringName, to_port : int, keep_alive : bool = true) -> Error:
	var err := connect_node(from_node, from_port, to_node, to_port);
	notify_connections_changed();
	return err;

func disconnect_node_and_notify(from_node : StringName, from_port : int, to_node : StringName, to_port : int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port);
	notify_connections_changed();

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	for hook in hooks.drag_and_drop:
		if hook.can_drop_data(at_position, data):
			return true;
	return false;
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	for hook in hooks.drag_and_drop:
		hook.drop_data(at_position, data);

func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	for hook in hooks.override_connection_lines:
		var override = hook.get_connection_line(from_position, to_position);
		if override:
			return override;
	return get_default_connection_line(from_position, to_position);

func get_default_connection_line(from_position: Vector2, to_position: Vector2, curvature : float = -1) -> PackedVector2Array:
	if curvature < 0:
		curvature = connection_lines_curvature;
	var x_diff : float = (to_position.x - from_position.x);
	var cp_offset : float = x_diff * curvature;
	if x_diff < 0:
		cp_offset *= -1;

	var curve := Curve2D.new();
	curve.add_point(from_position);
	curve.set_point_out(0, Vector2(cp_offset, 0));
	curve.add_point(to_position);
	curve.set_point_in(1, Vector2(-cp_offset, 0));

	if curvature > 0:
		return curve.tessellate(5, 2.0);
	else:
		return curve.tessellate(1);
	
func local_to_graph_position(position : Vector2) -> Vector2:
	return (position + scroll_offset) / zoom;

func check_connection_port_types(connection : Dictionary, from_port_type : int, to_port_type : int) -> bool:
	var from_graph_node := get_node(NodePath(connection.from_node));
	var to_graph_node := get_node(NodePath(connection.to_node));
	
	if !from_graph_node: return false;
	if !to_graph_node: return false;
	
	if connection.from_port >= from_graph_node.get_output_port_count(): return false;
	if connection.to_port >= to_graph_node.get_input_port_count(): return false;

	if (from_graph_node as GraphNode).get_output_port_type(connection.from_port) != from_port_type: return false;
	if (to_graph_node as GraphNode).get_input_port_type(connection.to_port) != to_port_type: return false;
	
	return true;

### HOOKS

class Hooks extends RefCounted:
	const METHOD_NAME_GET_CAPABILITIES : StringName = &"get_signal_graph_capabilities"
	const META_NAME_GRANTED_CAPABILITIES : StringName = &"_signal_graph_granted_capabilities"
	var _capabilities : Dictionary = {
		"configure_capabilities": {
			"required_methods": [
				&"configure_capabilities"
			],
			"hooks": [] as Array[Object],
			"is_meta": true
		},
		"drag_and_drop": {
			"required_methods": [
				&"can_drop_data",
				&"drop_data"
			],
			"hooks": [] as Array[Object]
		},
		"configure_port_types": {
			"required_methods": [
				&"configure_port_types"
			],
			"hooks": [] as Array[Object]
		},
		"override_connection_lines": {
			"required_methods": [
				&"get_connection_line"
			],
			"hooks": [] as Array[Object]
		},
		"populate_graph_nodes_from_view": {
			"required_methods": [
				&"populate_graph_nodes_from_view"
			],
			"hooks": [] as Array[Object]
		},
		"populate_graph_node_connections": {
			"required_methods": [
				&"populate_graph_node_connections"
			],
			"hooks": [] as Array[Object]
		},
		"view_object_serialization": {
			"required_methods": [
				&"get_supported_view_object_types",
				&"view_object_to_runtime_key",
				&"runtime_key_to_view_object",
				&"runtime_key_serialize",
				&"runtime_key_deserialize",
			],
			"hooks": [] as Array[Object]
		},
		
		"view_rule.object_source": {
			"required_methods": [
				&"get_view_rule_id",
				&"generate_view_objects",
				&"get_view_rule_label"
			],
			"hooks": [] as Array[Object]
		},
		"view_rule.member_source": {
			"required_methods": [
				&"get_view_rule_id",
				&"generate_view_object_members",
				&"get_view_rule_label"
			],
			"hooks": [] as Array[Object]
		}
	};
	
	var editor : SignalGraphEditor;
	var _hooks : Array[Object];
	
	func _init(editor : SignalGraphEditor):
		self.editor = editor;
		
		_add_builtin_hooks();
	
	func _initialize_hooks() -> void:
		# First pass: Meta capabilities
		for hook in _hooks:
			_init_hook_meta(hook);
		
		# Second pass: Regular capabilities
		for hook in _hooks:
			_init_hook(hook);
		
	func _add_builtin_hooks() -> void:
		add_hook(load("res://addons/signal-graphs/editor/hooks/scene_objects.gd"));
		add_hook(load("res://addons/signal-graphs/editor/hooks/methods_and_signals.gd"));
		add_hook(load("res://addons/signal-graphs/editor/hooks/connection_flag_editing.gd"));
		
		add_hook(load("res://addons/signal-graphs/editor/hooks/view_rules/nodes.gd"));
		add_hook(load("res://addons/signal-graphs/editor/hooks/view_rules/members_with_connections.gd"));
		add_hook(load("res://addons/signal-graphs/editor/hooks/view_rules/members_by_name.gd"));
		
	func add_hook(script : Script) -> bool:
		var instance : Object = script.new(editor);
		if !instance:
			printerr("Failed to instantiate script " + script.resource_path + " as a signal graph hook: Requires a constructor that takes 1 argument.");
			return false;
		if !instance.has_method(METHOD_NAME_GET_CAPABILITIES):
			printerr("Could not add script " + script.resource_path + " as a signal graph hook: Does not implement required method '" + str(METHOD_NAME_GET_CAPABILITIES) + "'");
			return false;
		
		_hooks.append(instance);
		
		return true;
	
	# First pass: Meta capabilities
	func _init_hook_meta(instance : Object) -> bool:
		var script : Script = instance.get_script();
		var hook_capabilities : Array[String] = instance.call(METHOD_NAME_GET_CAPABILITIES);
		
		for capability in hook_capabilities:
			if !_is_meta_capability(capability): continue;
			if _get_granted_capabilities(instance).has(capability): continue;
			if _validate_capability(instance, script, capability):
				_grant_capability(instance, script, capability);
				instance.configure_capabilities();
		
		return true;
	
	# Second pass: Regular capabilities
	func _init_hook(instance : Object) -> bool:
		var script : Script = instance.get_script();
		var hook_capabilities : Array[String] = instance.call(METHOD_NAME_GET_CAPABILITIES);
		
		for capability in hook_capabilities:
			if _is_meta_capability(capability): continue;
			if _get_granted_capabilities(instance).has(capability): continue;
			if _validate_capability(instance, script, capability):
				_grant_capability(instance, script, capability);
			
		print("Initialized signal graph hook script: " + script.resource_path + " with capabilities: " + str(_get_granted_capabilities(instance)));
		return true;
	
	func _is_meta_capability(capability : String) -> bool:
		return _capabilities.has(capability) && _capabilities[capability].get("is_meta");
	
	func _validate_capability(instance : Object, script : Script, capability : String) -> bool:
		if !_capabilities.has(capability):
			printerr("Invalid signal graph hook capability '" + capability + "' in script " + script.resource_path);
			return false;
		var list : Array[Object] = _capabilities[capability].hooks;
		if list.has(instance):
			printerr("Duplicate signal graph hook capability '" + capability + "' in script " + script.resource_path);
			return false;
		var required_methods : Array = _capabilities[capability].required_methods;
		var missing_any := false;
		for required_method_name : StringName in required_methods:
			if !instance.has_method(required_method_name):
				printerr("Missing method '" + str(required_method_name) + "', required for signal graph hook capability '" + capability + "' in script " + script.resource_path);
				missing_any = true;
				continue;
		
		if missing_any:
			printerr("Skipping signal graph hook capability '" + capability + "' in script " + script.resource_path + " due to missing required methods.");
			return false;
		
		return true;
	
	func register_capability(name : String, required_methods : Array[StringName]) -> bool:
		if _capabilities.has(name):
			printerr("Failed to register capability '" + name + "': another capability with the same name is already registered!");
			return false;
		
		_capabilities[name] = {
			"required_methods": required_methods,
			"hooks": [] as Array[Object]
		};
		return true;
	
	func _grant_capability(instance : Object, script : Script, capability : String) -> void:
		_get_granted_capabilities(instance).push_back(capability);
		_capabilities[capability].hooks.push_back(instance);
	
	func _get_granted_capabilities(instance : Object) -> Array[String]:
		var granted_capabilities : Array[String] = instance.get_meta(META_NAME_GRANTED_CAPABILITIES, [] as Array[String]) as Array[String];
		instance.set_meta(META_NAME_GRANTED_CAPABILITIES, granted_capabilities);
		return granted_capabilities;
	
	func _get(property: StringName) -> Variant:
		if _capabilities.has(property as String):
			return _capabilities[property as String].hooks;
		return null;
	
class Selector extends RefCounted:
	const TAB_METHODS := 0;
	const TAB_SIGNALS := 1;
	static var _last_selected_tab_index := TAB_METHODS;
	
	static var _active : Dictionary;
	
	static func show(obj : Object, force_start_tab : int, method_callback : Callable, signal_callback : Callable) -> void:
		if !obj:
			return;
			
		if force_start_tab < 0:
			force_start_tab = _last_selected_tab_index;
		_last_selected_tab_index = force_start_tab;
		
		_active = create_signal_method_selector(force_start_tab);
		var dialog : ConfirmationDialog = _active["dialog"];
		var search_bar : LineEdit = _active["search_bar"];
		var tree : Tree = _active["tree"];
		var tab_group : ButtonGroup = _active["tab_group"];
		
		_active["method_list"] = collect_members(obj, &"get_script_method_list", &"class_get_method_list", &"get_method_list");
		_active["signal_list"] = collect_members(obj, &"get_script_signal_list", &"class_get_signal_list", &"get_signal_list");
		
		_active["method_callback"] = method_callback;
		_active["signal_callback"] = signal_callback;
		
		tree.item_selected.connect(_on_selection_changed);
		tree.item_activated.connect(_tree_on_item_activated);
		
		dialog.confirmed.connect(_on_submitted);
		
		tab_group.pressed.connect(_on_tab_group_pressed);
		search_bar.text_changed.connect(_populate_tree);
		
		_populate_tree("");
		
		dialog.visible = false;
		EditorInterface.popup_dialog_centered(dialog);
	
	static func _populate_tree(filter : String) -> void:
		var dialog : ConfirmationDialog = _active["dialog"];
		var tree : Tree = _active["tree"];
		var tab_group : ButtonGroup = _active["tab_group"];
		var method_list : Array[Dictionary] = _active["method_list"];
		var signal_list : Array[Dictionary] = _active["signal_list"];
		var theme := dialog.theme;
		
		# Handles are Vector2is where:
		# x is tab index (0/1 for methods/signals)
		# y is method or signal index within the list
		# They're used in tree item metadata to keep a reference to where they came from
		
		# Grab the handle of the last selected entry, before we clear it and reapply the filter, so we can reselect it later.
		var selected_handle : Vector2i = tree.get_selected().get_metadata(0) if tree.get_selected() else Vector2i(-1, 0);
		
		tree.clear();
		
		var root := tree.create_item();
		
		var selected_tab := tab_group.get_pressed_button().get_index();
		
		match selected_tab:
			TAB_METHODS:
				var method_root := tree.create_item(root);
				method_root.set_text(0, "Methods");
				
				for method_index in range(method_list.size()):
					var handle := Vector2i(TAB_METHODS, method_index);
					
					var method_info := method_list[method_index];
					var text := Utility.get_method_signature_text(method_info);
					
					if filter && !filter.is_subsequence_ofn(text):
						continue;
					
					var item := tree.create_item(method_root);
					item.set_icon(0, theme.get_icon(ICON_NAME_METHOD, "EditorIcons"));
					item.set_text(0, text);
					item.set_metadata(0, handle);
					if selected_handle == handle:
						item.select(0);
				pass;
			TAB_SIGNALS:
				var signal_root := tree.create_item(root);
				signal_root.set_text(0, "Signals");
				
				for signal_index in range(signal_list.size()):
					var handle := Vector2i(TAB_SIGNALS, signal_index);
					
					var signal_info := signal_list[signal_index];
					var text := Utility.get_method_signature_text(signal_info);
					
					if filter && !filter.is_subsequence_ofn(text):
						continue;
					
					var item := tree.create_item(signal_root);
					item.set_icon(0, theme.get_icon(ICON_NAME_SIGNAL, "EditorIcons"));
					item.set_text(0, text);
					item.set_metadata(0, handle);
					if selected_handle == handle:
						item.select(0);
				pass;
				
		_on_selection_changed();
		
	static func _on_selection_changed() -> void:
		var dialog : ConfirmationDialog = _active["dialog"];
		var tree : Tree = _active["tree"];
		if !dialog || !tree:
			return;
		dialog.get_ok_button().disabled = tree.get_selected() == null;
	
	static func _tree_on_item_activated() -> void:
		var dialog : ConfirmationDialog = _active["dialog"];
		var tree : Tree = _active["tree"];
		if !dialog || !tree:
			return;
		tree.accept_event();
		if !dialog.get_ok_button().disabled:
			_on_submitted();
	
	static func _on_tab_group_pressed(btn : BaseButton) -> void:
		var search_bar : LineEdit = _active["search_bar"];
		_last_selected_tab_index = btn.get_index();
		_populate_tree(search_bar.text);
		
	static func _on_submitted() -> void:
		var dialog : ConfirmationDialog = _active["dialog"];
		var tree : Tree = _active["tree"];
		
		var method_list : Array[Dictionary] = _active["method_list"];
		var signal_list : Array[Dictionary] = _active["signal_list"];
		
		var selected_handle : Vector2i = tree.get_selected().get_metadata(0) if tree.get_selected() else Vector2i(-1, 0);
		var selected_tab : int = selected_handle.x;
		var selected_index : int = selected_handle.y;
		
		var method_callback : Callable = _active["method_callback"];
		var signal_callback : Callable = _active["signal_callback"];
		
		match selected_tab:
			TAB_METHODS:
				var method_info := method_list[selected_index];
				if method_callback.is_valid():
					method_callback.call(method_info);
			TAB_SIGNALS:
				var signal_info := signal_list[selected_index];
				if signal_callback.is_valid():
					signal_callback.call(signal_info);
		
		dialog.queue_free();
		
	static func create_signal_method_selector(force_start_tab : int) -> Dictionary:
		var output : Dictionary = {
			"dialog": null,
			"search_bar": null,
			"tree": null,
			"tab_group": null
		};
		
		var theme := EditorInterface.get_editor_theme();
		
		var dialog : ConfirmationDialog = load("res://addons/signal-graphs/scenes/signal_graph_member_selector_dialog.tscn").instantiate();
		output["dialog"] = dialog;
		dialog.theme = theme;
		
		# Tabs
		
		var tab_row : Container = dialog.get_node("%Tab Row");
		var tab_group := ButtonGroup.new();
		output["tab_group"] = tab_group;
		var methods_button := Button.new();
		methods_button.text = "Methods";
		methods_button.button_group = tab_group;
		methods_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
		methods_button.icon = theme.get_icon(ICON_NAME_METHOD, "EditorIcons");
		methods_button.toggle_mode = true;
		methods_button.button_pressed = force_start_tab == TAB_METHODS;
		methods_button.theme_type_variation = "FlatMenuButton";
		var signals_button := Button.new();
		signals_button.text = "Signals";
		signals_button.button_group = tab_group;
		signals_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
		signals_button.icon = theme.get_icon(ICON_NAME_SIGNAL, "EditorIcons");
		signals_button.toggle_mode = true;
		signals_button.button_pressed = force_start_tab == TAB_SIGNALS;
		signals_button.theme_type_variation = "FlatMenuButton";
		
		tab_row.add_child(methods_button);
		tab_row.add_child(signals_button);
		
		# Search Bar
		
		var search_bar : LineEdit = dialog.get_node("%Search Bar");
		output["search_bar"] = search_bar;
		search_bar.right_icon = theme.get_icon("Search", "EditorIcons");
		
		# Tree
		var tree : Tree = dialog.get_node("%Tree");
		output["tree"] = tree;
		
		dialog.close_requested.connect(dialog.queue_free);
		
		return output;
	
	static func collect_members(obj : Object, script_getter : StringName, class_getter : StringName, instance_getter : StringName) -> Array[Dictionary]:
		var list : Array[Dictionary] = [];
		var name_list : Array[StringName] = [];
		
		# Add members by script
		var script : Script = obj.get_script();
		while script != null && script_getter != null:
			if script.has_method(script_getter):
				for def in script.call(script_getter):
					var name : StringName = def["name"];
					if name_list.has(name):
						continue;
					name_list.push_back(name);
					list.push_back(def);
			script = script.get_base_script();
		
		# Add members by class
		var cls_name := obj.get_class();
		while cls_name && class_getter != null:
			if ClassDB.has_method(class_getter):
				for def in ClassDB.call(class_getter, cls_name):
					var name : StringName = def["name"];
					if name_list.has(name):
						continue;
					name_list.push_back(name);
					list.push_back(def);
			cls_name = ClassDB.get_parent_class(cls_name);
		
		# Add dynamic signals and methods for this specific node
		if instance_getter && obj.has_method(instance_getter):
			var insertion_index := 0;
			for def in obj.call(instance_getter):
				var name : StringName = def["name"];
				if name_list.has(name):
					continue;
				name_list.push_back(name);
				list.insert(insertion_index, def);
				insertion_index += 1;
		
		return list;


### UTILITY
class Utility extends RefCounted:
	var editor : SignalGraphEditor;
	
	func _init(editor : SignalGraphEditor):
		self.editor = editor;
	
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
	
	static func get_object_icon(obj: Object) -> Texture2D:
		if obj == null:
			return null;
		var script = obj.get_script();
		if script:
			var script_icon := get_script_icon(script);
			if script_icon:
				return script_icon;
		
		var cls_name := obj.get_class();
		var theme := EditorInterface.get_editor_theme();
		if theme.has_icon(cls_name, "EditorIcons"):
			return theme.get_icon(cls_name, "EditorIcons");
		
		return null;
	
	static func get_script_icon(script : Script) -> Texture2D:
		var filepath := script.resource_path;
		var script_classes := ProjectSettings.get_global_class_list() as Array
		for a_class in script_classes:
			if a_class.path == filepath:
				if a_class.icon:
					return load(a_class.icon);
				return null;
		return null;

### INTERFACE SIGNALS

class InterfaceSignals extends RefCounted:
	var editor : SignalGraphEditor;
	
	func _init(editor : SignalGraphEditor):
		self.editor = editor;

	func connect_all() -> void:
		editor.popup_request.connect(_on_popup_request);
		editor.node_selected.connect(_on_node_selected);
		editor.node_deselected.connect(_on_node_deselected);
		editor.begin_node_move.connect(_on_begin_node_move);
		editor.end_node_move.connect(_on_end_node_move);
		editor.child_exiting_tree.connect(_on_node_removed);
		editor.visibility_changed.connect(_on_visibility_changed);
		editor.scroll_offset_changed.connect(_on_scroll_offset_changed);
	
	func _on_popup_request(at_position : Vector2) -> void:
		var menu := PopupMenu.new();
		menu.add_item("Menu WIP");
		editor.add_child(menu);
		menu.position = editor.get_screen_position() + at_position;
		
		menu.show();
		menu.close_requested.connect(menu.queue_free);
		menu.index_pressed.connect(_on_popup_item_pressed);
	
	func _on_popup_item_pressed(index : int) -> void:
		print(index);
		
	func _on_node_selected(node : Node) -> void:
		editor.selected_nodes.push_back(node.name);
		editor.notify_selection_changed();
	func _on_node_deselected(node : Node) -> void:
		_deselect_node(node);
	func _deselect_node(node : Node) -> void:
		var changed := false;
		for i in range(editor.selected_nodes.size()-1, -1, -1):
			if editor.selected_nodes[i] == node.name:
				changed = true;
				editor.selected_nodes.remove_at(i);
		if changed:
			editor.notify_selection_changed();
	func _on_begin_node_move() -> void:
		editor.dragging = true;
		
	func _on_end_node_move() -> void:
		editor.dragging = false;
	
	func _on_node_removed(node : Node) -> void:
		_deselect_node(node);
		
	func _on_visibility_changed() -> void:
		if editor._pending_rearrange_after_load:
			editor.call_deferred(&"rearrange_after_load");
	
	func _on_scroll_offset_changed(offset : Vector2) -> void:
		if !editor.current_view: return;
		editor.current_view.scene_data.scroll_offset = editor.scroll_offset;
		editor.current_view.scene_data.zoom = editor.zoom;
