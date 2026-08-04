@tool
extends Node

@export var editor : SignalGraphEditor;

const COL_MAIN : int = 0;
const COL_BUTTONS : int = 1;

const ACTION_ADD_RULE : int = 0;
const ACTION_EDIT_RULE : int = 1;
const ACTION_MOVE_UP : int = 2;
const ACTION_MOVE_DOWN : int = 3;
const ACTION_REMOVE_RULE : int = 4;

var global_views : Dictionary = {
	"(default)": {
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
		}
	}
}

var local_views : Dictionary = {
	"(blank)": {
		"view_rules": {
			"object_source": [
			],
			"member_source": [
				{
					"id": "scene_signals:members_with_connections",
					"params": {}
				}
			]
		}
	}
}

var _active : Dictionary;
var current_view : Dictionary = {
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
			},
			{
				"id": "scene_signals:members_by_name",
				"params": {
					"signals": [
						"Triggered"
					]
				}
			}
		]
	}
};

func _enter_tree() -> void:
	if is_part_of_edited_scene(): return;
	populate_view_dropdown(%"View Dropdown");

func populate_view_dropdown(dropdown : OptionButton) -> void:
	var theme := EditorInterface.get_editor_theme();
	dropdown.clear();
	for view_name in global_views:
		dropdown.add_icon_item(theme.get_icon("PreviewEnvironment", "EditorIcons"), view_name);
		dropdown.set_item_metadata(dropdown.item_count-1, {
			"view_name": view_name,
			"view_type": "global"
		});
	for view_name in local_views:
		dropdown.add_icon_item(theme.get_icon("PackedScene", "EditorIcons"), view_name);
		dropdown.set_item_metadata(dropdown.item_count-1, {
			"view_name": view_name,
			"view_type": "local"
		});
#		dropdown.add_item(view_name);

func show_dialog():
	_active = create_dialog();
	
	var dialog : AcceptDialog = _active["dialog"];
	var tree : Tree = _active["tree"];
	tree.columns = 2;
	tree.set_column_expand(COL_BUTTONS, false);
	tree.button_clicked.connect(_on_button_clicked);

	_populate_tree();

	dialog.visible = false;
	EditorInterface.popup_dialog_centered(dialog);

func _populate_tree() -> void:
	var tree : Tree = _active["tree"];
	tree.clear();
	
	var root_item := tree.create_item();
	root_item.set_text(COL_MAIN, "Rules");
	populate_rule_type(tree, "object_source")
	populate_rule_type(tree, "member_source")
	tree.set_drag_forwarding(_tree_drag, _tree_can_drop, _tree_drop);

func populate_rule_type(tree : Tree, rule_type : String) -> void:
	var rule_type_item := tree.create_item(tree.get_root());
	rule_type_item.set_text(COL_MAIN, rule_type.capitalize());
	for col in range(tree.columns):
		rule_type_item.set_custom_stylebox(col, _active["header_stylebox"]);
	
	rule_type_item.add_button(COL_BUTTONS, EditorInterface.get_editor_theme().get_icon("Add", "EditorIcons"), ACTION_ADD_RULE, false, "Add Rule");
	rule_type_item.set_metadata(0, {
		"row_type": "rule_type",
		"rule_type": rule_type
	});
	
	var rules : Array = current_view.view_rules.get(rule_type);
	var rule_index := 0;
	if rules:
		for rule_obj in rules:
			var rule_item := tree.create_item(rule_type_item);
			var hook : Object = editor.view.get_view_rule_hook(rule_obj.id, rule_type);
			if hook:
				rule_item.set_text(COL_MAIN, hook.get_view_rule_label(rule_params_from_dict(hook, rule_obj.get("params") as Dictionary)));
			else:
				rule_item.set_text(COL_MAIN, rule_obj.id);
			rule_item.set_icon(COL_MAIN, EditorInterface.get_editor_theme().get_icon("TripleBar", "EditorIcons"));
			
			rule_item.add_button(COL_BUTTONS, EditorInterface.get_editor_theme().get_icon("Edit", "EditorIcons"), ACTION_EDIT_RULE, false, "Edit");
			rule_item.add_button(COL_BUTTONS, EditorInterface.get_editor_theme().get_icon("MoveUp", "EditorIcons"), ACTION_MOVE_UP, rule_index == 0, "Move Up");
			rule_item.add_button(COL_BUTTONS, EditorInterface.get_editor_theme().get_icon("MoveDown", "EditorIcons"), ACTION_MOVE_DOWN, rule_index == rules.size()-1, "Move Down");
			rule_item.add_button(COL_BUTTONS, EditorInterface.get_editor_theme().get_icon("Remove", "EditorIcons"), ACTION_REMOVE_RULE, false, "Remove");
			rule_item.custom_minimum_height = 30;
			
			rule_item.set_metadata(0, {
				"row_type": "rule",
				"rule_type": rule_type,
				"rule_index": rule_index
			});
	
			rule_index += 1;
	else:
		var no_rule_item := tree.create_item(rule_type_item);
		no_rule_item.set_text(0, "(none)");

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
	print(rule_params_to_dict(hook, params));
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

func _tree_drag(at_position : Vector2) -> Variant:
	print("drag: " + str(at_position));
	var tree : Tree = _active["tree"];
	var item := tree.get_item_at_position(at_position);
	if !item: return null;
	var metadata = item.get_metadata(0);
	if !metadata: return {};
	return {
		"type": "view_rule",
		"metadata": metadata
	};
func _tree_can_drop(at_position : Vector2, data : Dictionary) -> bool:
	var tree : Tree = _active["tree"];
	
	if data.get("type") != "view_rule": return _cannot_drop();
	var target_item := tree.get_item_at_position(at_position);
	if !target_item: return _cannot_drop();
	var target_item_metadata = target_item.get_metadata(0);
	if !target_item_metadata: return _cannot_drop();
	if target_item_metadata.row_type != "rule": return _cannot_drop();
	if target_item_metadata.rule_type != data.metadata.rule_type: return _cannot_drop();
	tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN;
	return true;
func _cannot_drop() -> bool:
	var tree : Tree = _active["tree"];
	tree.drop_mode_flags = Tree.DROP_MODE_DISABLED;
	return false;
func _tree_drop(at_position : Vector2, data : Dictionary) -> void:
	var tree : Tree = _active["tree"];
	var target_item := tree.get_item_at_position(at_position);
	var target_item_metadata = target_item.get_metadata(0);
	var drop_section := tree.get_drop_section_at_position(at_position);
	
	move_rule(data.metadata, target_item_metadata.rule_index + clampi(drop_section, -1, 0));
	
	pass;

func _on_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	match id:
		ACTION_ADD_RULE:
			add_rule(item.get_metadata(0).rule_type);
		ACTION_EDIT_RULE:
			edit_rule(item.get_metadata(0));
		ACTION_MOVE_UP:
			move_rule(item.get_metadata(0), -1);
		ACTION_MOVE_DOWN:
			move_rule(item.get_metadata(0), +1);
		ACTION_REMOVE_RULE:
			remove_rule(item.get_metadata(0));

func move_rule(metadata : Dictionary, offset : int) -> void:
	var rule_type : String = metadata.rule_type;
	var rule_index : int = metadata.rule_index;
	var rule_arr : Array = current_view.view_rules[rule_type];
	var rule_obj = rule_arr[rule_index];
	rule_arr.remove_at(rule_index);
	rule_arr.insert(rule_index+offset, rule_obj);
	call_deferred(&"_populate_tree");

func edit_rule(metadata : Dictionary) -> void:
	var rule_type : String = metadata.rule_type;
	var rule_index : int = metadata.rule_index;
	var rule_arr : Array = current_view.view_rules[rule_type];
	var rule_obj = rule_arr[rule_index];
	var dialog : Window = load("res://addons/signal-graphs/scenes/signal_graph_view_rule_edit_dialog.tscn").instantiate();
	var hook : Object = editor.view.get_view_rule_hook(rule_obj.id, rule_type);
	dialog.setup(rule_type, editor.view.get_view_rule_hooks(rule_type), hook, rule_params_from_dict(hook, rule_obj.get("params") as Dictionary));
	dialog.rule_selected.connect(func (selected_hook : Object, selected_params : Variant) -> void:
		rule_arr[rule_index] = {
			"id": selected_hook.get_view_rule_id(),
			"params": rule_params_to_dict(selected_hook, selected_params)
		};
		call_deferred(&"_populate_tree");
	);
	EditorInterface.popup_dialog_centered(dialog);

func add_rule(rule_type : String) -> void:
	var rule_arr : Array = current_view.view_rules[rule_type];
	var dialog : Window = load("res://addons/signal-graphs/scenes/signal_graph_view_rule_edit_dialog.tscn").instantiate();
	dialog.setup(rule_type, editor.view.get_view_rule_hooks(rule_type), null, null);
	dialog.rule_selected.connect(func (selected_hook : Object, selected_params : Variant) -> void:
		rule_arr.append({
			"id": selected_hook.get_view_rule_id(),
			"params": rule_params_to_dict(selected_hook, selected_params)
		});
		call_deferred(&"_populate_tree");
	);
	EditorInterface.popup_dialog_centered(dialog);

func remove_rule(metadata : Dictionary) -> void:
	var rule_type : String = metadata.rule_type;
	var rule_index : int = metadata.rule_index;
	var rule_arr : Array = current_view.view_rules[rule_type];
	rule_arr.remove_at(rule_index);
	call_deferred(&"_populate_tree");

func create_dialog() -> Dictionary:
	var output : Dictionary = {
		"dialog": null,
		"view_dropdown": null,
		"tree": null
	};
	var theme := EditorInterface.get_editor_theme();
	
	var dialog : AcceptDialog = load("res://addons/signal-graphs/scenes/signal_graph_view_manager_dialog.tscn").instantiate();
	output["dialog"] = dialog;
	dialog.theme = theme;
	
	# View Dropdown
	
	var view_dropdown : OptionButton = dialog.get_node("%View Dropdown");
	output["view_dropdown"] = view_dropdown;
	view_dropdown.add_item("(default)");
	populate_view_dropdown(view_dropdown);
	view_dropdown.item_selected.connect(func (selected_index : int) -> void:
		var metadata = view_dropdown.get_item_metadata(selected_index);
		_on_dialog_view_dropdown_selected(metadata);
	);
	
	# Tree
	var tree : Tree = dialog.get_node("%Tree");
	output["tree"] = tree;
	
	dialog.close_requested.connect(dialog.queue_free);
	
	# Styles
	var rule_header_stylebox := StyleBoxFlat.new();
	rule_header_stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.25);
	output["header_stylebox"] = rule_header_stylebox;
	
	return output;

func create_rule_edit_dialog() -> Dictionary:
	var output : Dictionary = {
		"dialog": null,
		"view_dropdown": null,
		"tree": null
	};
	var theme := EditorInterface.get_editor_theme();
	
	var dialog : AcceptDialog = load("res://addons/signal-graphs/scenes/signal_graph_view_rule_edit_dialog.tscn").instantiate();
	output["dialog"] = dialog;
	dialog.theme = theme;
	
	# View Dropdown
	
	var view_dropdown : OptionButton = dialog.get_node("%View Dropdown");
	output["view_dropdown"] = view_dropdown;
	view_dropdown.add_item("(default)");
	
	# Tree
	var tree : Tree = dialog.get_node("%Tree");
	output["tree"] = tree;
	
	dialog.close_requested.connect(dialog.queue_free);
	
	# Styles
	var rule_header_stylebox := StyleBoxFlat.new();
	rule_header_stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.25);
	output["header_stylebox"] = rule_header_stylebox;
	
	return output;

func _on_dialog_view_dropdown_selected(metadata : Dictionary) -> void:
	match metadata.view_type:
		"global":
			current_view = global_views[metadata.view_name];
		"local":
			current_view = local_views[metadata.view_name];
	call_deferred(&"_populate_tree");