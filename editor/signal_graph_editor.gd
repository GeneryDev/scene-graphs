@tool
class_name SignalGraphEditor
extends GraphEdit

const META_NAME_GRAPH_DATA := "_signal_graph_data";
const ICON_NAME_SIGNAL := "Signal";
const ICON_NAME_METHOD := "Slot";

const PORT_TYPE_NONE := -1;
const PORT_TYPE_SIGNAL := 0;
const PORT_TYPE_ADD_SIGNAL := 9;
const PORT_TYPE_ADD_METHOD := 10;

var scene_root : Node;
var selected_nodes : Array[StringName] = [];

var _use_context_position : bool;
var _context_position : Vector2;

var interface_signals : InterfaceSignals;
var transactions : Transactions;
var utility : Utility;
var populating : Populating;
var frames : Frames;

func _init():
	interface_signals = InterfaceSignals.new(self);
	transactions = Transactions.new(self);
	utility = Utility.new(self);
	populating = Populating.new(self);
	frames = Frames.new(self);

### CORE

func _ready() -> void:
	if is_part_of_edited_scene():
		return;
	interface_signals.subscribe();

func add_one_shot() -> GraphNode:
	var graph_node : GraphNode = GraphNodeTypes.OneShot.new();
	
	position_new_element(graph_node);
		
	transactions.add_child(graph_node, true);
	
	return graph_node;

func clear():
	clear_connections();
	for child in get_children():
		if child is not GraphElement:
			continue;
		remove_child(child);
		child.queue_free();

func save(scene_root : Node):
	scene_root = scene_root;
	
	for child in get_children():
		if child is not GraphNode:
			continue;
		if !child.has_method("get_save_data"):
			continue;
		if !child.has_method("get_represented_object"):
			continue;
		var represented_object : Object = child.get_represented_object();
		if !represented_object:
			continue;
		var save_data = child.get_save_data();
		represented_object.set_meta(META_NAME_GRAPH_DATA, save_data);

func position_new_element(element : GraphElement):
	if _use_context_position:
		element.position_offset = utility.local_to_graph_position(_context_position);
	else:
		element.position_offset = Vector2.ZERO;
		
class GraphNodeTypes:
	static var SignalNode : Script = preload("res://addons/signal-graphs/editor/elements/signal_node_graph_node.gd");
	static var OneShot : Script = preload("res://addons/signal-graphs/editor/elements/signal_one_shot_graph_node.gd");
	
		
### POPULATING
class Populating:
	var editor : SignalGraphEditor;
	
	func _init(editor : GraphEdit):
		self.editor = editor;
	
	func populate_from_scene(scene_root : Node) -> void:
		editor.scene_root = scene_root;
		editor._use_context_position = false;
		add_graph_node_for_node(scene_root, true, true)
		populate_node_connections();
	
	func create_graph_node_for_node(node : Node, require_connections : bool = false) -> GraphNode:
		var graph_node : GraphNode = null;
		
		if node.owner == editor.scene_root || node == editor.scene_root:
			graph_node = GraphNodeTypes.SignalNode.new() as GraphNode;
			var saved_data : Dictionary = node.get_meta(META_NAME_GRAPH_DATA) if node.has_meta(META_NAME_GRAPH_DATA) else {};
			var any_connections : bool = graph_node.setup(node, saved_data, editor);
			if require_connections && !any_connections:
				graph_node.queue_free();
				graph_node = null;
			else:
				editor.position_new_element(graph_node);
		
		return graph_node;
		
	func add_graph_node_for_node(node : Node, recursive : bool = false, require_connections : bool = false) -> GraphNode:
		var graph_node := create_graph_node_for_node(node, require_connections);
		if graph_node:
			editor.add_child(graph_node);
		
		if recursive:
			for child in node.get_children():
				add_graph_node_for_node(child, true, require_connections);
		
		return graph_node;
	
	func populate_node_connections() -> void:
		for child in editor.get_children():
			if child is not GraphNode:
				continue;
			
			var graph_node : GraphNode = child;
			
			if !child.has_method(&"get_object"):
				continue;
			
			var node : Node = child.call(&"get_object");
			if !node:
				continue;
			
			for connection in node.get_incoming_connections():
				var sgnal : Signal = connection["signal"];
				var callable : Callable = connection["callable"];
				
				var flags : ConnectFlags = connection["flags"];
				if(flags & CONNECT_PERSIST) == 0: continue;
				var owner := sgnal.get_object();
				if owner is not Node:
					continue;
					
				var owner_graph_node = editor.utility.get_graph_node_for_node(owner);
				if !owner_graph_node:
					continue;
				
				var from_port : int = owner_graph_node.get_signal_port_id(sgnal.get_name());
				var to_port : int = graph_node.get_method_port_id(callable.get_method());
			
				if from_port == PORT_TYPE_NONE || to_port == PORT_TYPE_NONE:
					continue;
				
				editor.connect_node(owner_graph_node.name, from_port, graph_node.name, to_port);
				
class Selector:
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
		
		dialog.window_input.connect(_on_window_input);
		
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
		var search_bar : LineEdit = _active["search_bar"];
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
		
	static func _on_window_input(evt : InputEvent) -> void:
		#idk if this is needed?
		pass;
#		var dialog : ConfirmationDialog = _active["dialog"];
#		var tree : Tree = _active["tree"];
#		if !dialog || !tree:
#			return;
#		if evt.is_action(&"ui_cancel"):
#			dialog.set_input_as_handled();
#			dialog.queue_free();
#		if evt.is_action(&"ui_accept") && !dialog.is_input_handled():
#			dialog.set_input_as_handled();
#		if !dialog.get_ok_button().disabled:
#			_on_submitted();
		
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
		
		var dialog := ConfirmationDialog.new();
		output["dialog"] = dialog;
		dialog.title = "Select Method/Signal";
		dialog.borderless = false;
		dialog.size = Vector2i(500, 400);
		dialog.theme = theme;
		dialog.transient = true;
		dialog.exclusive = true;
		
		var content := VBoxContainer.new();
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL;
		dialog.add_child(content);
		
		# Tabs
		
		var tab_row := HBoxContainer.new();
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
		content.add_child(tab_row);
		
		# Search Bar
		
		var search_bar := LineEdit.new();
		output["search_bar"] = search_bar;
		search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
		search_bar.placeholder_text = "Filter";
		search_bar.right_icon = theme.get_icon("Search", "EditorIcons");
		content.add_child(search_bar);
		
		# Tree
		var tree := Tree.new();
		output["tree"] = tree;
		tree.size_flags_vertical = Control.SIZE_EXPAND_FILL;
		tree.hide_root = true;
		content.add_child(tree);
		
		# Buttons
		dialog.ok_button_text = "Add";
		dialog.cancel_button_text = "Cancel";
		
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
class Utility:
	const VARIANT_TYPE_NAMES : Array = ["Nil","bool","int","float","String","Vector2","Vector2i","Rect2","Rect2i","Vector3","Vector3i","Transform2D","Vector4","Vector4i","Plane","Quaternion","AABB","Basis","Transform3D","Projection","Color","StringName","NodePath","RID","Object","Callable","Signal","Dictionary","Array","PackedByteArray","PackedInt32Array","PackedInt64Array","PackedFloat32Array","PackedFloat64Array","PackedStringArray","PackedVector2Array","PackedVector3Array","PackedColorArray","PackedVector4Array"];

	var editor : SignalGraphEditor;
	
	func _init(editor : GraphEdit):
		self.editor = editor;
	
	func local_to_graph_position(position : Vector2) -> Vector2:
		return (position + editor.scroll_offset) / editor.zoom;
		
	func get_graph_node_for_node(node : Node) -> GraphNode:
		return editor.get_node_or_null(NodePath(str(node.get_instance_id()))) as GraphNode;
		
	static func get_connected_method_names(obj : Object) -> Array[StringName]:
		var connected_methods : Array[StringName] = [];
		for connection in obj.get_incoming_connections():
			if(connection.flags & CONNECT_PERSIST) == 0: continue;
			var method_name := connection.callable.get_method() as StringName; 
			if !connected_methods.has(method_name):
				connected_methods.push_back(method_name);
		return connected_methods;
	
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
				s += str(VARIANT_TYPE_NAMES[type]);
			
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
		var name := ""
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
class Transactions:
	var editor : SignalGraphEditor;
	var undo_redo : EditorUndoRedoManager;
	
	func _init(editor : GraphEdit):
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
	
	func connect_node(from_node : StringName, from_port : int, to_node : StringName, to_port : int, create_and_commit : bool = true):
		if create_and_commit:
			begin_transaction("Connect graph nodes", UndoRedo.MergeMode.MERGE_ALL, null, true);
		undo_redo.add_do_method(editor, &"connect_node", from_node, from_port, to_node, to_port);
		undo_redo.add_undo_method(editor, &"disconnect_node", from_node, from_port, to_node, to_port);
		if create_and_commit:
			end_transaction();
	
	func disconnect_node(from_node : StringName, from_port : int, to_node : StringName, to_port : int, create_and_commit : bool = true):
		if create_and_commit:
			begin_transaction("Disconnect graph nodes", UndoRedo.MergeMode.MERGE_ALL, null, true);
		undo_redo.add_do_method(editor, &"disconnect_node", from_node, from_port, to_node, to_port);
		undo_redo.add_undo_method(editor, &"connect_node", from_node, from_port, to_node, to_port);
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
	
	func delete_nodes(nodes : Array[StringName], create_and_commit : bool = true):
		if create_and_commit:
			begin_transaction("Delete graph nodes", UndoRedo.MergeMode.MERGE_ALL, null, true);
		
		# First, remove connections
		var connection_list := editor.get_connection_list();
		for node_name in nodes:
			for i in range(connection_list.size()):
				var connection := connection_list[i];
				var from_node := connection["from_node"] as StringName;
				var to_node := connection["to_node"] as StringName;
				if from_node == node_name || to_node == node_name:
					var from_port := connection["from_port"] as int;
					var to_port := connection["to_port"] as int;
					disconnect_node(from_node, from_port, to_node, to_port, false);
					
					connection_list.remove_at(i);
					i -= 1;
		
		# Then, remove frame attachments
		for node_name in nodes:
			# If inside a frame, remove that attachment
			attach_to_frame(node_name, &"", false);
			
			var node := editor.get_node(NodePath(node_name));
			if node is GraphFrame:
				# If *a* frame, remove attachments with other nodes
				var attached_nodes := editor.get_attached_nodes_of_frame(node_name);
				for attached_node in attached_nodes:
					attach_to_frame(attached_node, &"", false);
		
		# Lastly, remove nodes from graph
		for node_name in nodes:
			var node := editor.get_node(NodePath(node_name));
			if !node:
				continue;
			remove_child(node, true, false);
		
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

class InterfaceSignals:
	var editor : SignalGraphEditor;
	
	var _dragging_across_frames := false;
	
	func _init(editor : GraphEdit):
		self.editor = editor;

	func subscribe() -> void:
		editor.popup_request.connect(_on_popup_request);
		editor.connection_request.connect(_on_connection_request);
		editor.disconnection_request.connect(_on_disconnection_request);
		editor.connection_drag_started.connect(_on_connection_drag_started);
		editor.node_selected.connect(_on_node_selected);
		editor.node_deselected.connect(_on_node_deselected);
		editor.begin_node_move.connect(_on_begin_node_move);
		editor.end_node_move.connect(_on_end_node_move);
		editor.child_exiting_tree.connect(_on_node_removed);
		editor.delete_nodes_request.connect(_on_delete_nodes_request);
	
	func _on_popup_request(at_position : Vector2) -> void:
		var menu := PopupMenu.new();
		menu.add_item("New Frame");
		menu.add_item("New: One Shot");
		menu.add_item("four");
		editor.add_child(menu);
		menu.position = editor.get_screen_position() + at_position;
		editor._use_context_position = true;
		editor._context_position = at_position;
		
		menu.show();
		menu.close_requested.connect(menu.queue_free);
		menu.index_pressed.connect(_on_popup_item_pressed);
	
	func _on_popup_item_pressed(index : int) -> void:
		print(index);
		
	func _on_connection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
		print("connection request")
		editor.transactions.begin_transaction("Connect graph nodes", UndoRedo.MergeMode.MERGE_ALL, null, true);
		var from_node := editor.get_node(NodePath(from_node_name));
		var to_node := editor.get_node(NodePath(to_node_name));
		
		# TODO VERY HARDCODED, check graph node types
		var from_object : Object = from_node.get_object();
		var to_object : Object = to_node.get_object();
		var callable := Callable(to_object, to_node.get_method_port_name(to_port))
		var signal_name : StringName = from_node.get_signal_port_name(from_port);
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.add_undo_method(self, &"_update_scene_tree");
		editor.transactions.connect_signal(from_object, signal_name, callable, CONNECT_PERSIST, false);
		undo_redo.add_do_method(self, &"_update_scene_tree");
		
		editor.transactions.connect_node(from_node_name, from_port, to_node_name, to_port, false);
		editor.transactions.end_transaction();
	
	func _on_disconnection_request(from_node_name : StringName, from_port : int, to_node_name : StringName, to_port : int) -> void:
		print("disconnection request")
		editor.transactions.begin_transaction("Disconnect graph nodes", UndoRedo.MergeMode.MERGE_ALL, null, true);
		var from_node := editor.get_node(NodePath(from_node_name));
		var to_node := editor.get_node(NodePath(to_node_name));
		
		# TODO VERY HARDCODED, check graph node types
		var from_object : Object = from_node.get_object();
		var to_object : Object = to_node.get_object();
		var callable := Callable(to_object, to_node.get_method_port_name(to_port))
		var signal_name : StringName = from_node.get_signal_port_name(from_port);
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.add_undo_method(self, &"_update_scene_tree");
		editor.transactions.disconnect_signal(from_object, signal_name, callable, false);
		undo_redo.add_do_method(self, &"_update_scene_tree");
		
		editor.transactions.disconnect_node(from_node_name, from_port, to_node_name, to_port, false);
		editor.transactions.end_transaction();
		
	func _on_connection_drag_started(from_node_name : StringName, from_port : int, is_output : bool) -> void:
		print("connection drag started")
		var node := editor.get_node(NodePath(from_node_name));
		
		# TODO VERY HARDCODED, check graph node types
		var graph_node : GraphNode = node;
		var slot : int;
		var slot_type : int;
		if is_output:
			slot = graph_node.get_output_port_slot(from_port);
			slot_type = graph_node.get_slot_type_right(slot);
		else:
			slot = graph_node.get_input_port_slot(from_port);
			slot_type = graph_node.get_slot_type_left(slot);
		
		match slot_type:
			PORT_TYPE_ADD_METHOD:
				editor.force_connection_drag_end();
				Selector.show(graph_node.get_object(), Selector.TAB_METHODS, Callable(graph_node, &"method_add_requested"), Callable(graph_node, &"signal_add_requested"));
		
	func _on_node_selected(node : Node) -> void:
		print("node selected");
		editor.selected_nodes.push_back(node.name);
	func _on_node_deselected(node : Node) -> void:
		print("node deselected");
		_deselect_node(node);
	func _deselect_node(node : Node) -> void:
		for i in range(editor.selected_nodes.size()):
			if editor.selected_nodes[i] == node.name:
				editor.selected_nodes.remove_at(i);
				i -= 1;
	func _on_begin_node_move() -> void:
		print("begin node move");
		_dragging_across_frames = Input.is_key_pressed(Key.KEY_SHIFT);
		if _dragging_across_frames:
			for node_name in editor.selected_nodes:
				editor.detach_graph_element_from_frame(node_name);
		
	func _on_end_node_move() -> void:
		print("end node move");
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
		print("node removed");
		_deselect_node(node);
	func _on_delete_nodes_request(nodes : Array[StringName]) -> void:
		print("delete nodes request");
		editor.transactions.delete_nodes(nodes);
		
	func _update_scene_tree():
		# Force refresh the scene tree view to reflect new connections
		if editor.scene_root:
			editor.scene_root.name = editor.scene_root.name;

### DRAG AND DROP
# ( no class )

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var data_dict : Dictionary = data;
	if data_dict["type"] != "nodes": return false;
	return true;
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	var data_dict : Dictionary = data;
	if data_dict["type"] != "nodes": return;

	_context_position = at_position;
	_use_context_position = true;
	
	set_selected(null);
	
	for node_path : NodePath in data_dict["nodes"]:
		var node := get_node(node_path);
		if !node: continue;
		
		var instance_id := node.get_instance_id();
		var existing_graph_node : GraphNode = utility.get_graph_node_for_node(node);
		
		if existing_graph_node:
			existing_graph_node.set_selected(true);
		else:
			var graph_node := populating.create_graph_node_for_node(node, false);
			graph_node.set_selected(true);
			transactions.add_child(graph_node, true, true);
			
### FRAMES
class Frames:
	var editor : SignalGraphEditor;
	
	func _init(editor : GraphEdit):
		self.editor = editor;
	
	func add_frame(group_selected : bool = true):
		editor.transactions.begin_transaction("Add frame", UndoRedo.MergeMode.MERGE_ALL, null, true);
		var frame := GraphFrame.new();
		editor.position_new_element(frame);
		frame.title = "New Frame";
		editor.transactions.add_child(frame, true, true);
		editor.transactions.end_transaction();
		
		if !group_selected || editor.selected_nodes.is_empty():
			return;
		
		editor.transactions.begin_transaction("Add frame", UndoRedo.MergeMode.MERGE_ALL, null, true);
		var common_ancestor : Node;
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
				if common_frame_name != common_frame.name if common_frame else &"":
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