@tool
class_name SignalGraphMemberSelector
extends RefCounted

var _last_selected_member_type := "";

var all_member_types;
var all_input_member_types;
var all_output_member_types;

var _active : Dictionary;
var _member_lists_by_type : Dictionary;

var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;

func get_all_member_types() -> Array[String]:
	if all_member_types: return all_member_types;
	all_member_types = [] as Array[String];
	
	for hook in editor.hooks.configure_member_selector:
		for member_type in hook.get_member_selector_member_types():
			if !all_member_types.has(member_type): all_member_types.append(member_type);
			
	return all_member_types;

func get_all_input_member_types() -> Array[String]:
	if all_input_member_types: return all_input_member_types;
	all_input_member_types = [] as Array[String];
	
	for hook in editor.hooks.configure_member_selector:
		for member_type in hook.get_member_selector_member_types():
			if hook.get_member_selector_tab_info(member_type).get("is_input", false):
				if !all_input_member_types.has(member_type): all_input_member_types.append(member_type);
			
	return all_input_member_types;

func get_all_output_member_types() -> Array[String]:
	if all_output_member_types: return all_output_member_types;
	all_output_member_types = [] as Array[String];
	
	for hook in editor.hooks.configure_member_selector:
		for member_type in hook.get_member_selector_member_types():
			if hook.get_member_selector_tab_info(member_type).get("is_output", false):
				if !all_output_member_types.has(member_type): all_output_member_types.append(member_type);
			
	return all_output_member_types;

func show(object_type : String, obj : Object, member_types : Array[String], member_callback : Callable) -> void:
	if !obj:
		return;
		
	if !member_types: return;
	member_types = member_types.filter(func (member_type : String) -> bool:
		for hook in editor.hooks.configure_member_selector:
			if hook.get_member_selector_member_types().has(member_type):
				return true;
		printerr("No hook is capable of configuring member type '" + member_type + "' for the member selector.");
		return false;
	);
	if !member_types: return;
	
	var force_start_tab := _last_selected_member_type if member_types.has(_last_selected_member_type) else member_types[0];
	
	_active = _create_member_selector(member_types, force_start_tab);
	var dialog : ConfirmationDialog = _active["dialog"];
	var search_bar : LineEdit = _active["search_bar"];
	var tree : Tree = _active["tree"];
	var tab_group : ButtonGroup = _active["tab_group"];
	
	_active["object_type"] = object_type;
	_active["obj"] = obj;
	_active["member_types"] = member_types;
	_active["member_callback"] = member_callback;
	
	_member_lists_by_type.clear()
	for member_type in member_types:
		for hook in editor.hooks.configure_member_selector:
			if hook.get_member_selector_member_types().has(member_type):
				_member_lists_by_type[member_type] = hook.get_member_selector_member_list(object_type, obj, member_type) as Array;
				break;
	
	tree.item_selected.connect(_on_selection_changed);
	tree.item_activated.connect(_tree_on_item_activated);
	
	dialog.confirmed.connect(_on_submitted);
	
	tab_group.pressed.connect(_on_tab_group_pressed);
	search_bar.text_changed.connect(_populate_tree);
	
	_populate_tree("");
	
	dialog.visible = false;
	EditorInterface.popup_dialog_centered(dialog);

func _populate_tree(filter : String) -> void:
	var tree : Tree = _active["tree"];
	var tab_group : ButtonGroup = _active["tab_group"];
	
	# Handles are Dictionaries with:
	# member_type (String)
	# member_name (StringName)
	# They're used in tree item metadata to keep a reference to where they came from
	
	# Grab the handle of the last selected entry, before we clear it and reapply the filter, so we can reselect it later.
	var selected_handle : Dictionary = tree.get_selected().get_metadata(0) if tree.get_selected() else {};
	
	tree.clear();
	
	var root := tree.create_item();
	
	var selected_member_type : String = tab_group.get_pressed_button().get_meta(&"member_type",_active["member_types"][0]);
	var member_list : Array = _member_lists_by_type.get(selected_member_type);
	var list_root := tree.create_item(root);
	list_root.set_text(0, tab_group.get_pressed_button().text);
	
	for member_index in range(member_list.size()):
		var member_info : Dictionary = member_list[member_index];
		var handle := {
			"member_type": selected_member_type,
			"member_name": member_info.member_name as StringName
		};
		
		var label : String = member_info.label;
		
		if filter && !filter.is_subsequence_ofn(label):
			continue;
		
		var item := tree.create_item(list_root);
		item.set_icon(0, member_info.get("icon"));
		item.set_text(0, member_info.get("label"));
		item.set_metadata(0, handle);
		if selected_handle == handle:
			item.select(0);
	
	_on_selection_changed();
	
func _on_selection_changed() -> void:
	var dialog : ConfirmationDialog = _active["dialog"];
	var tree : Tree = _active["tree"];
	if !dialog || !tree:
		return;
	dialog.get_ok_button().disabled = tree.get_selected() == null;

func _tree_on_item_activated() -> void:
	var dialog : ConfirmationDialog = _active["dialog"];
	var tree : Tree = _active["tree"];
	if !dialog || !tree:
		return;
	tree.accept_event();
	if !dialog.get_ok_button().disabled:
		_on_submitted();

func _on_tab_group_pressed(btn : BaseButton) -> void:
	var search_bar : LineEdit = _active["search_bar"];
	_last_selected_member_type = btn.get_meta(&"member_type",&"");
	_populate_tree(search_bar.text);
	
func _on_submitted() -> void:
	var dialog : ConfirmationDialog = _active["dialog"];
	var tree : Tree = _active["tree"];
	
	var selected_handle : Dictionary = tree.get_selected().get_metadata(0) if tree.get_selected() else {};
	var member_type : String = selected_handle.member_type;
	var member_name : StringName = selected_handle.member_name;
	
	var member_callback : Callable = _active["member_callback"];
	
	if member_callback.is_valid():
		member_callback.call(_active["object_type"], _active["obj"], member_type, member_name);
	
	dialog.queue_free();
	
func _create_member_selector(member_types : Array[String], force_start_tab : String) -> Dictionary:
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
	for member_type in member_types:
		var tab_info : Dictionary;
		for hook in editor.hooks.configure_member_selector:
			if hook.get_member_selector_member_types().has(member_type):
				tab_info = hook.get_member_selector_tab_info(member_type);
				if tab_info: break;
		if !tab_info: continue;
		var tab_button := Button.new();
		tab_button.text = tab_info.label;
		tab_button.button_group = tab_group;
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
		tab_button.icon = tab_info.icon;
		tab_button.toggle_mode = true;
		tab_button.button_pressed = member_type == force_start_tab;
		tab_button.theme_type_variation = "FlatMenuButton";
		tab_button.set_meta(&"member_type", member_type);
		tab_row.add_child(tab_button);
	
	# Search Bar
	
	var search_bar : LineEdit = dialog.get_node("%Search Bar");
	output["search_bar"] = search_bar;
	search_bar.right_icon = theme.get_icon("Search", "EditorIcons");
	
	# Tree
	var tree : Tree = dialog.get_node("%Tree");
	output["tree"] = tree;
	
	dialog.close_requested.connect(dialog.queue_free);
	
	return output;