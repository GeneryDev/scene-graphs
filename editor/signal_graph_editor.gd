@tool
class_name SignalGraphEditor
extends GraphEdit

const ICON_NAME_SIGNAL := "Signal";
const ICON_NAME_METHOD := "Slot";

signal connections_changed();
signal selection_changed();
signal selection_changed_with_script(script : Script, selected_nodes : Array[Node]);
signal connection_line_cache_invalidated();

var scene_root : Node:
	get: return EditorInterface.get_edited_scene_root();
var selected_nodes : Array[StringName] = [];
var dragging : bool = false;

var interface_signals : InterfaceSignals;
var transactions : Transactions;
var utility : Utility;
var view : View;
var frames : Frames;
var hooks : Hooks;

var connections_layer : Control;

var _port_types_by_name : Dictionary[StringName, int] = {
	&"": -1
};
var _next_port_type_idx := 0;
var _pending_rearrange_after_load := false;

func _init():
	interface_signals = InterfaceSignals.new(self);
	transactions = Transactions.new(self);
	utility = Utility.new(self);
	view = View.new(self);
	frames = Frames.new(self);
	
	connections_layer = get_node(^"_connection_layer");
	hooks = Hooks.new(self);

### CORE

func _ready() -> void:
	if is_part_of_edited_scene():
		return;
	hooks._initialize_hooks();
	interface_signals.subscribe();
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

func load(view_data : Dictionary) -> void:
	if view_data:
		view.view_data = view_data;
		view.update_object_views_with_rules();
		view.update_all_object_member_views_with_rules();
	
		if view_data.has("scene_data") && view_data.scene_data.has("zoom"):
			zoom = view_data.scene_data.zoom;
		if view_data.has("scene_data") && view_data.scene_data.has("scroll_offset"):
			scroll_offset = view_data.scene_data.scroll_offset;
	else:
		view.clear_all_objects();
		view.update_object_views_with_rules();
		view.update_all_object_member_views_with_rules();
	
	view.notify_view_updated();
	
	if is_visible_in_tree():
		call_deferred(&"rearrange_after_load");
	else:
		_pending_rearrange_after_load = true;

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

func notify_selection_changed() -> void:
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

### Editor Settings

const PROJECT_SETTING_NAME_HOOKS := &"signal_graphs/hooks/hook_scripts";

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
				&"populate_view_objects",
				&"get_view_rule_label"
			],
			"hooks": [] as Array[Object]
		},
		"view_rule.member_source": {
			"required_methods": [
				&"get_view_rule_id",
				&"populate_view_object_members",
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
		add_hook(load("res://addons/signal-graphs/editor/hooks/scene_signals.gd"));
		add_hook(load("res://addons/signal-graphs/editor/hooks/view_rules/nodes_with_connections.gd"));
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
	
	func local_to_graph_position(position : Vector2) -> Vector2:
		return (position + editor.scroll_offset) / editor.zoom;
	
	static func get_connected_method_names(obj : Object) -> Array:
		var list := [];
		
		var connected_methods : Array[StringName] = [];
		for connection in obj.get_incoming_connections():
			if(connection.flags & CONNECT_PERSIST) == 0: continue;
			var method_name := connection.callable.get_method() as StringName; 
			if !connected_methods.has(method_name):
				connected_methods.push_back(method_name);
		
		# doing two passes because we want the returned list to be in a consistent order (by method definition)
		# rather than the order of connections :(
		
		for method_info in obj.get_method_list():
			var method_name := method_info["name"] as StringName;
			if list.has(method_name): continue;
			var used := connected_methods.has(method_name);
			
			if used: list.append(method_name);
		
		return list;
	
	static func get_connected_signal_names(obj : Object) -> Array:
		var list := [];
		for signal_info in obj.get_signal_list():
			var signal_name := signal_info["name"] as StringName;
			var used := false;
			
			for connection in obj.get_signal_connection_list(signal_name):
				var flags := connection["flags"] as ConnectFlags;
				if (flags & ConnectFlags.CONNECT_PERSIST) != 0:
					used = true;
					break;
			
			if !used: continue;
			
			list.append(signal_name);
		
		return list;
	
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
		
	func get_common_ancestor(a : Node, b : Node) -> Node:
		var common_ancestor : Node = a;
		while common_ancestor != null && common_ancestor != editor.scene_root && !common_ancestor.is_ancestor_of(b):
			common_ancestor = common_ancestor.get_parent();
		return common_ancestor;

### TRANSACTIONS
class Transactions extends RefCounted:
	var editor : SignalGraphEditor;
	var undo_redo : EditorUndoRedoManager;
	
	func _init(editor : SignalGraphEditor):
		self.editor = editor;
		undo_redo = EditorInterface.get_editor_undo_redo();
	
	func begin_transaction(name : String, merge_mode : UndoRedo.MergeMode = UndoRedo.MergeMode.MERGE_ALL, custom_context : Object = null, backward_undo_ops : bool = false) -> void:
		if custom_context == null:
			custom_context = editor.scene_root;
		undo_redo.create_action(name, merge_mode, custom_context, backward_undo_ops);
		
	func end_transaction(execute : bool = true):
		undo_redo.commit_action(execute);
	
	func add_child(child : Node, do_reference : bool, create_and_commit : bool = true):
		if create_and_commit:
			begin_transaction("Create graph element", UndoRedo.MergeMode.MERGE_ALL, null, true);
		undo_redo.add_do_method(editor, &"add_child", child);
		undo_redo.add_undo_method(editor, &"remove_child", child);
		if do_reference:
			undo_redo.add_do_reference(child);
		if create_and_commit:
			end_transaction();
	
	func remove_child(child : Node, undo_reference : bool, create_and_commit : bool = true):
		if create_and_commit:
			begin_transaction("Remove graph element", UndoRedo.MergeMode.MERGE_ALL, null, true);
		undo_redo.add_do_method(editor, &"remove_child", child);
		undo_redo.add_undo_method(editor, &"add_child", child);
		if undo_reference:
			undo_redo.add_undo_reference(child);
		if create_and_commit:
			end_transaction();
	
	func attach_to_frame(node_name : StringName, frame_name : StringName, create_and_commit : bool = true):
		var prev_frame := editor.get_element_frame(node_name)
		var prev_frame_name : StringName = prev_frame.name if prev_frame != null else &"";
	
		if create_and_commit:
			begin_transaction("Add graph nodes to frame", UndoRedo.MergeMode.MERGE_ALL, null, true);
		
		if prev_frame_name:
			undo_redo.add_do_method(editor, &"detach_graph_element_from_frame", node_name);
		if frame_name:
			undo_redo.add_do_method(editor, &"attach_graph_element_to_frame", node_name, frame_name);
		
		if prev_frame_name:
			undo_redo.add_undo_method(editor, &"attach_graph_element_to_frame", node_name, prev_frame_name);
		if frame_name:
			undo_redo.add_undo_method(editor, &"detach_graph_element_to_frame", node_name);
		
		if create_and_commit:
			end_transaction();
	
	func connect_signal(from_node : Node, signal_name : StringName, callable : Callable, flags : ConnectFlags = ConnectFlags.CONNECT_PERSIST, create_and_commit : bool = true):
		if create_and_commit:
			begin_transaction("Connect signal", UndoRedo.MergeMode.MERGE_ALL, null, true);
		undo_redo.add_do_method(from_node, &"connect", signal_name, callable, flags);
		undo_redo.add_undo_method(from_node, &"disconnect", signal_name, callable);
		if create_and_commit:
			end_transaction();
	
	func disconnect_signal(from_node : Node, signal_name : StringName, callable : Callable, create_and_commit : bool = true):
		if create_and_commit:
			begin_transaction("Disconnect signal", UndoRedo.MergeMode.MERGE_ALL, null, true);
		
		var flags := ConnectFlags.CONNECT_PERSIST;
		for connection in from_node.get_signal_connection_list(signal_name):
			var connectionCallable := connection["callable"] as Callable;
			if connectionCallable == callable:
				flags = connection["flags"];
		
		undo_redo.add_do_method(from_node, &"disconnect", signal_name, callable);
		undo_redo.add_undo_method(from_node, &"connect", signal_name, callable, flags);
		if create_and_commit:
			end_transaction();
			
### INTERFACE SIGNALS

class InterfaceSignals extends RefCounted:
	var editor : SignalGraphEditor;
	
	var _dragging_across_frames := false;
	
	func _init(editor : SignalGraphEditor):
		self.editor = editor;

	func subscribe() -> void:
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
		menu.add_item("New Frame");
		menu.add_item("New: One Shot");
		menu.add_item("four");
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
		for i in range(editor.selected_nodes.size()-1, -1, -1):
			if editor.selected_nodes[i] == node.name:
				editor.selected_nodes.remove_at(i);
		editor.notify_selection_changed();
	func _on_begin_node_move() -> void:
		editor.dragging = true;
		_dragging_across_frames = Input.is_key_pressed(Key.KEY_SHIFT);
		if _dragging_across_frames:
			for node_name in editor.selected_nodes:
				editor.detach_graph_element_from_frame(node_name);
		
	func _on_end_node_move() -> void:
		editor.dragging = false;
		_dragging_across_frames = Input.is_key_pressed(Key.KEY_SHIFT);
		if _dragging_across_frames:
			var mouse_pos := editor.get_local_mouse_position();
			var hovered_frame : GraphFrame = null;
			for child in editor.get_children():
				if child is GraphFrame && !editor.selected_nodes.has(child.name) && (child as GraphFrame).get_rect().has_point(mouse_pos):
					hovered_frame = child;
			
			for node_name in editor.selected_nodes:
				editor.transactions.attach_to_frame(node_name, hovered_frame.name if hovered_frame else &"");
				
	func _on_node_removed(node : Node) -> void:
		_deselect_node(node);
		
	func _on_visibility_changed() -> void:
		if editor._pending_rearrange_after_load:
			editor.call_deferred(&"rearrange_after_load");
	
	func _on_scroll_offset_changed(offset : Vector2) -> void:
		var scene_data : Dictionary = editor.view.view_data.get_or_add("scene_data", {});
		scene_data.scroll_offset = editor.scroll_offset;
		scene_data.zoom = editor.zoom;

### FRAMES
class Frames extends RefCounted:
	var editor : SignalGraphEditor;
	
	func _init(editor : SignalGraphEditor):
		self.editor = editor;
	
	func add_frame(group_selected : bool = true):
		editor.transactions.begin_transaction("Add frame", UndoRedo.MergeMode.MERGE_ALL, null, true);
		var frame := GraphFrame.new();
		frame.title = "New Frame";
		editor.transactions.add_child(frame, true, true);
		editor.transactions.end_transaction();
		
		if !group_selected || editor.selected_nodes.is_empty():
			return;
		
		editor.transactions.begin_transaction("Add frame", UndoRedo.MergeMode.MERGE_ALL, null, true);
		var common_ancestor : Node = null;
		var common_ancestor_set := false;
		var common_frame_name : StringName;
		var common_frame_name_set := false;
		for node_name in editor.selected_nodes:	
			# Take old node frame, try to find a common frame
			if !common_frame_name && !common_frame_name_set:
				var common_frame := editor.get_element_frame(node_name);
				common_frame_name = common_frame.name if common_frame else &"";
				common_frame_name_set = true;
			else:
				var common_frame := editor.get_element_frame(node_name);
				if common_frame_name != (common_frame.name if common_frame else &""):
					common_frame_name = &"";
			
			# Attach selected nodes to new frame
				
			editor.transactions.attach_to_frame(node_name, frame.name, false);
			
			var graph_node : GraphNode = editor.get_node(NodePath(node_name)) as GraphNode;
			if !graph_node.has_method(&"get_object"): continue;
			var node : Object = graph_node.get_object();
			if node is not Node: continue;
			
			# Look for a common ancestor among all the selected graph nodes' nodes.
			if !common_ancestor && !common_ancestor_set:
				common_ancestor = node as Node;
				common_ancestor_set = true;
			else:
				common_ancestor = editor.utility.get_common_ancestor(common_ancestor, node);
		
		if common_ancestor:
			frame.title = common_ancestor.name;
		
		if common_frame_name:
			editor.transactions.attach_to_frame(frame.name, common_frame_name, false);
			
		editor.transactions.end_transaction();

class View extends RefCounted:
	signal view_updated();
	
	var editor : SignalGraphEditor;
	var transactions : Transactions;
	
	var view_data : Dictionary = {
		"view_rules": {
			"object_source": [
				{
					"id": "scene_signals:nodes_with_connections",
					"params": {}
				}
			],
			"member_source": [
				{
					"id": "scene_signals:members_with_connections",
					"params": {}
				}
			]
		},
		"scene_data": {
			"objects": {}
		}
	};
	
	func _init(editor : SignalGraphEditor):
		self.editor = editor;
		transactions = Transactions.new(editor, self);
	
	func notify_view_updated() -> void:
		view_updated.emit();
	
	func get_all_scene_object_views() -> Dictionary:
		var all_scene_object_views : Dictionary = view_data.get_or_add("scene_data", {}).get_or_add("objects", {});
		return all_scene_object_views;
	
	func get_scene_object_views(object_type : String) -> Dictionary:
		return get_all_scene_object_views().get_or_add(object_type, {});
		
	func add_object_view(object_type : String, obj : Object) -> bool:
		if !obj: return false;
		var runtime_key = view_object_to_runtime_key(object_type, obj);
		if runtime_key == null: return false;
		var scene_object_views := get_scene_object_views(object_type);
		if scene_object_views.has(runtime_key):
			# already added
			return false;
		var obj_view := {
			"members": {}
		};
		scene_object_views[runtime_key] = obj_view;
		return true;
		
	func set_object_view(object_type : String, obj : Object, obj_view : Dictionary) -> bool:
		if !obj: return false;
		var runtime_key = view_object_to_runtime_key(object_type, obj);
		if runtime_key == null: return false;
		var scene_object_views := get_scene_object_views(object_type);
		scene_object_views[runtime_key] = obj_view;
		return true;
		
	func get_object_view(object_type : String, obj : Object) -> Dictionary:
		if !obj: return {};
		var runtime_key = view_object_to_runtime_key(object_type, obj);
		if runtime_key == null: return {};
		var scene_object_views := get_scene_object_views(object_type);
		if !scene_object_views.has(runtime_key): return {};
		return scene_object_views[runtime_key];
		
	func has_object_view(object_type : String, obj : Object) -> bool:
		if get_object_view(object_type, obj):
			return true;
		return false;
		
	func remove_object_view(object_type : String, obj : Object) -> bool:
		if !obj: return false;
		var runtime_key = view_object_to_runtime_key(object_type, obj);
		if runtime_key == null: return false;
		var scene_object_views := get_scene_object_views(object_type);
		if !scene_object_views.has(runtime_key): return false;
		var removed = scene_object_views[runtime_key];
		scene_object_views.erase(runtime_key);
		return true;
	
	func add_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> bool:
		var obj_view := get_object_view(object_type, obj);
		if !obj_view:
			printerr("Failed to add object view member; no object view for " + object_type + " " + str(obj));
			return false;
		var list : Array = obj_view.members[member_type] if obj_view.members.has(member_type) else [];
		obj_view.members[member_type] = list;
		if list.has(member_name): return false;
		list.append(member_name);
		return true;
		
	func has_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> bool:
		var obj_view := get_object_view(object_type, obj);
		if !obj_view:
			return false;
		return get_object_view_members(object_type, obj, member_type).has(member_name);
	
	func get_object_view_members(object_type : String, obj : Object, member_type : String) -> Array:
		var obj_view := get_object_view(object_type, obj);
		if !obj_view:
			printerr("Failed to get object view members; no object view for " + object_type + " " + str(obj));
			return [];
		var list : Array = obj_view.members[member_type] if obj_view.members.has(member_type) else [];
		obj_view.members[member_type] = list;
		return list;
	
	func remove_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> bool:
		var obj_view := get_object_view(object_type, obj);
		if !obj_view:
			printerr("Failed to remove object view member; no object view for " + object_type + " " + str(obj));
			return false;
		var list : Array = get_object_view_members(object_type, obj, member_type);
		if !list.has(member_name): return false;
		list.remove_at(list.find(member_name));
		return true;
	
	func clear_all_objects() -> void:
		view_data.get_or_add("scene_data",{})["objects"] = {};
	
	func clear_objects(object_type : String) -> void:
		view_data.get_or_add("scene_data",{}).get_or_add("objects",{})[object_type] = {};
		
	func _print_unsupported_object_type(object_type : String) -> void:
		printerr("Graph view object type '" + object_type + "' is not supported by any of the active signal graph editor hooks. Some data may be lost.");
	
	func view_object_to_runtime_key(object_type : String, obj : Object) -> Variant:
		if !obj: return null;
		for hook in editor.hooks.view_object_serialization:
			if !hook.get_supported_view_object_types().has(object_type): continue;
			return hook.view_object_to_runtime_key(object_type, obj);
		
		_print_unsupported_object_type(object_type);
		return null;
	
	func runtime_key_to_view_object(object_type : String, key : Variant) -> Object:
		if key == null: return null;
		for hook in editor.hooks.view_object_serialization:
			if !hook.get_supported_view_object_types().has(object_type): continue;
			return hook.runtime_key_to_view_object(object_type, key);
		
		_print_unsupported_object_type(object_type);
		return null;
	
	func runtime_key_serialize(object_type : String, key : Variant) -> Variant:
		if key == null: return null;
		for hook in editor.hooks.view_object_serialization:
			if !hook.get_supported_view_object_types().has(object_type): continue;
			return hook.runtime_key_serialize(object_type, key);
		
		_print_unsupported_object_type(object_type);
		return null;
	
	func runtime_key_deserialize(object_type : String, serialized : Variant) -> Variant:
		if serialized == null: return null;
		for hook in editor.hooks.view_object_serialization:
			if !hook.get_supported_view_object_types().has(object_type): continue;
			return hook.runtime_key_deserialize(object_type, serialized);
		
		_print_unsupported_object_type(object_type);
		return null;
	
	func instantiate_graph_node_for_object(object_type : String, obj : Object, graph_node_script : Script) -> GraphNode:
		if !obj: return null;
		var graph_node : GraphNode = graph_node_script.new(object_type, obj, editor);
		graph_node.name = _object_to_graph_node_name(object_type, obj);
		return graph_node;
	
	func _object_to_graph_node_name(object_type : String, obj : Object) -> StringName:
		if !obj: return &"";
		var runtime_key = view_object_to_runtime_key(object_type, obj);
		if !runtime_key: return &"";
		var node_name := StringName(object_type + "_" + str(runtime_key));
		return node_name;
	
	func get_graph_node_for_object(object_type : String, obj : Object) -> GraphNode:
		return editor.get_node_or_null(NodePath(_object_to_graph_node_name(object_type, obj))) as GraphNode;
	
	func select_object(object_type : String, obj : Object) -> void:
		var existing_graph_node : GraphNode = get_graph_node_for_object(object_type, obj);
		if existing_graph_node:
			existing_graph_node.set_selected(true);
		
	func get_view_rule_hooks(type : String) -> Array[Object]:
		return editor.hooks.get("view_rule." + type);
		
	func get_view_rule_hook(id : String, type : String) -> Object:
		for hook in get_view_rule_hooks(type):
			if hook.get_view_rule_id() == id:
				return hook;
		
		printerr("Invalid view rule id '" + id + "'");
		return null;

	func rule_params_from_dict(hook : Object, raw_params : Dictionary) -> Variant:
		if !hook.has_method(&"create_view_rule_params"): return null;
		var params : Object = hook.create_view_rule_params();
		
		for key in raw_params:
			var raw_value = raw_params[key];
			var default_value = params.get(key);
			if default_value == null: continue;
			if default_value is Array:
				default_value.assign(raw_value);
			elif default_value is Dictionary:
				default_value.assign(raw_value);
			else:
				params.set(key, raw_value);
		return params;
	
	func rule_params_to_dict(hook : Object, params : Variant) -> Dictionary:
		if !params: return {};
		var raw_params : Dictionary = {};
		for property in params.get_property_list():
			if property.name == &"script": continue;
			var value = params.get(property.name);
			if value == null: continue;
			raw_params[property.name] = value;
		return raw_params;
	
	func update_object_views_with_rules() -> void:
		for rule_entry in view_data.view_rules["object_source"]:
			var id : String = rule_entry.id;
			var raw_params : Dictionary = rule_entry.get("params");
			var rule_hook := get_view_rule_hook(id, "object_source");
			if !rule_hook: continue;
			rule_hook.populate_view_objects(rule_params_from_dict(rule_hook, raw_params));
	
	func update_object_member_views_with_rules(object_type : String, obj : Object) -> void:
		for rule_entry in view_data.view_rules["member_source"]:
			var id : String = rule_entry.id;
			var raw_params : Dictionary = rule_entry.get("params");
			var rule_hook := get_view_rule_hook(id, "member_source");
			if !rule_hook: continue;
			rule_hook.populate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params));
	
	func update_all_object_member_views_with_rules() -> void:
		for object_type in get_all_scene_object_views():
			var object_views : Dictionary = get_scene_object_views(object_type);
			
			for rule_entry in view_data.view_rules["member_source"]:
				var id : String = rule_entry.id;
				var raw_params : Dictionary = rule_entry.get("params");
				var rule_hook := get_view_rule_hook(id, "member_source");
				if !rule_hook: continue;
				for runtime_key in object_views:
					var obj : Object = runtime_key_to_view_object(object_type, runtime_key);
					if !obj: continue;
					rule_hook.populate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params));
	
	class Transactions extends RefCounted:
		var editor : SignalGraphEditor;
		var view : View;
		
		func _init(editor : SignalGraphEditor, view : View):
			self.editor = editor;
			self.view = view;
			
		func add_object_view(object_type : String, obj : Object, position_offset : Vector2) -> void:
			if view.has_object_view(object_type, obj):
				view.select_object(object_type, obj);
			else:
				view.add_object_view(object_type, obj);
				var obj_view := view.get_object_view(object_type, obj);
				obj_view["position_offset"] = position_offset;
				view.update_object_member_views_with_rules(object_type, obj);
				view.notify_view_updated();
				view.select_object(object_type, obj);
				
				editor.transactions.begin_transaction("Add object view", UndoRedo.MERGE_ALL, null, false);
				var undo_redo := editor.transactions.undo_redo;
				undo_redo.add_do_method(view, &"set_object_view", object_type, obj, obj_view);
				undo_redo.add_do_method(view, &"notify_view_updated");
				undo_redo.add_do_method(view, &"select_object", object_type, obj);
				undo_redo.add_undo_method(view, &"remove_object_view", object_type, obj);
				undo_redo.add_undo_method(view, &"notify_view_updated");
				editor.transactions.end_transaction(false);
		
		func remove_object_view(object_type : String, obj : Object) -> void:
			if !view.has_object_view(object_type, obj):
				return;
			var obj_view := view.get_object_view(object_type, obj);
			
			editor.transactions.begin_transaction("Remove object view", UndoRedo.MERGE_ALL, null, false);
			var undo_redo := editor.transactions.undo_redo;
			undo_redo.add_do_method(view, &"remove_object_view", object_type, obj);
			undo_redo.add_do_method(view, &"notify_view_updated");
			undo_redo.add_undo_method(view, &"set_object_view", object_type, obj, obj_view);
			undo_redo.add_undo_method(view, &"notify_view_updated");
			undo_redo.add_undo_method(view, &"select_object", object_type, obj);
			editor.transactions.end_transaction();
		
		func add_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> void:
			if !view.add_object_view_member(object_type, obj, member_type, member_name):
				return;
			view.notify_view_updated();
			
			editor.transactions.begin_transaction("Add node view member", UndoRedo.MERGE_ALL, null, false);
			var undo_redo := editor.transactions.undo_redo;
			undo_redo.add_do_method(view, &"add_object_view_member", object_type, obj, member_type, member_name);
			undo_redo.add_undo_method(view, &"remove_object_view_member", object_type, obj, member_type, member_name);
			undo_redo.add_do_method(view, &"notify_view_updated");
			undo_redo.add_undo_method(view, &"notify_view_updated");
			editor.transactions.end_transaction(false);