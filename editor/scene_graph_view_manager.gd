@tool
extends Node

const COL_MAIN: int = 0
const COL_BUTTONS: int = 1
const default_views: Dictionary = {
	"Default: Signals": {
		"hook_options": {
			"scene_graphs:methods_and_signals": {
				"enable_method_and_signal_ports": true,
			},
			"scene_graphs:property_inspectors": {
				"enable_property_inspectors": false,
			},
			"scene_graphs:node_references": {
				"enable_node_reference_ports": true,
			},
		},
		"view_rules": {
			"member_source": [
				{
					"id": "scene_graphs:connected_methods_and_signals",
					"params": { },
				},
			],
			"object_source": [
				{
					"id": "scene_graphs:nodes",
					"params": {
						"require_connections": true,
					},
				},
			],
		},
	},
	"Default: Node References": {
		"hook_options": {
			"scene_graphs:methods_and_signals": {
				"enable_method_and_signal_ports": false,
			},
			"scene_graphs:property_inspectors": {
				"enable_property_inspectors": false,
			},
			"scene_graphs:node_references": {
				"enable_node_reference_ports": true,
			},
		},
		"view_rules": {
			"member_source": [
				{
					"id": "scene_graphs:node_reference_properties",
					"params": { },
				},
			],
			"object_source": [
				{
					"id": "scene_graphs:nodes",
					"params": {
						"require_connections": true,
					},
				},
			],
		},
	},
}

@export var editor: SceneGraphEditor

var interface_memory: Dictionary = {
	"view_copy_preferences": {
		"view_rules": {
		},
	},
}
var global_views: Dictionary = { }
var local_views: Dictionary = { }
var active_local_view_metadata: Dictionary = { }
var active_local_view: SceneGraphView
var edit_views_dialog: EditViewsDialog
var _pending_local_view_activation: Dictionary = { }
var _editor_state_fully_loaded := false


### MAIN SCREEN
func _enter_tree() -> void:
	if is_part_of_edited_scene():
		return
	edit_views_dialog = EditViewsDialog.new(editor, self)
	var view_dropdown: OptionButton = %"View Dropdown"
	populate_view_dropdown(view_dropdown)
	view_dropdown.item_selected.connect(
		func(selected_index: int) -> void:
			var metadata = view_dropdown.get_item_metadata(selected_index)
			activate_view(metadata)
	)


func store_scene_state() -> Dictionary:
	var serialized_scene_state := {
		"active_view": active_local_view_metadata,
		"local_views": { },
	}
	var runtime_scene_state := {
		"active_view": active_local_view_metadata,
		"local_views": { },
	}
	for view_name in local_views:
		serialized_scene_state.local_views[view_name] = local_views[view_name].serialize()
		runtime_scene_state.local_views[view_name] = local_views[view_name]
	return {
		"serialized": serialized_scene_state,
		"runtime": runtime_scene_state,
	}


func restore_scene_state(scene_states: Dictionary) -> void:
	var scene_state = scene_states["runtime"] if scene_states.get("runtime", null) else scene_states["serialized"]
	local_views.clear()
	if scene_state.has("local_views"):
		for view_name in scene_state.local_views:
			var view_value = scene_state.local_views[view_name]
			local_views[view_name] = view_value if view_value is SceneGraphView else SceneGraphView.new(editor).deserialize(scene_state.local_views[view_name])

	repopulate_view_dropdown()

	if scene_state.has("active_view"):
		activate_view(scene_state["active_view"])
		ensure_valid_view_active()
	else:
		activate_view(get_fallback_local_view_metadata())


func serialize_editor_state() -> Dictionary:
	var serialized_editor_state := {
		"global_views": { },
	}
	for view_name in global_views:
		serialized_editor_state.global_views[view_name] = (global_views[view_name] as SceneGraphView).serialize()
	return serialized_editor_state


func deserialize_editor_state(serialized_editor_state: Dictionary) -> void:
	global_views.clear()
	if serialized_editor_state.has("global_views"):
		for view_name in serialized_editor_state.global_views:
			global_views[view_name] = SceneGraphView.new(editor).deserialize(serialized_editor_state.global_views[view_name])

	repopulate_view_dropdown()

	_editor_state_fully_loaded = true

	if _pending_local_view_activation:
		activate_view(_pending_local_view_activation)
		_pending_local_view_activation = { }
		ensure_valid_view_active()


func ensure_valid_view_active() -> void:
	if !active_local_view_metadata || !get_view(active_local_view_metadata):
		activate_view(get_fallback_local_view_metadata())


func populate_view_dropdown(dropdown: OptionButton, clear: bool = true) -> void:
	var theme := EditorInterface.get_editor_theme()
	if clear:
		dropdown.clear()
	for view_name in global_views:
		dropdown.add_icon_item(theme.get_icon("PreviewEnvironment", "EditorIcons"), view_name)
		dropdown.set_item_metadata(
			dropdown.item_count - 1,
			{
				"view_name": view_name,
				"view_type": "global",
			},
		)
	for view_name in local_views:
		if global_views.has(view_name):
			continue
		dropdown.add_icon_item(theme.get_icon("PackedScene", "EditorIcons"), view_name)
		dropdown.set_item_metadata(
			dropdown.item_count - 1,
			{
				"view_name": view_name,
				"view_type": "local",
			},
		)


func set_view_dropdown(dropdown: OptionButton, metadata: Dictionary) -> void:
	for item_idx in range(dropdown.item_count):
		if dropdown.get_item_metadata(item_idx) == metadata:
			if dropdown.selected != item_idx:
				dropdown.select(item_idx)
			break


func get_localized_view(view_name: String) -> SceneGraphView:
	if local_views.has(view_name):
		return local_views[view_name]
	else:
		return null


func localize_global_view(view_name: String) -> SceneGraphView:
	var global_view: SceneGraphView = global_views[view_name]
	var existing_local_view: SceneGraphView
	if local_views.has(view_name):
		existing_local_view = local_views[view_name]
	else:
		existing_local_view = SceneGraphView.new(editor)
	existing_local_view.copy_non_scene_data_from(global_view)
	local_views[view_name] = existing_local_view
	return existing_local_view


func globalize_local_view(view_name: String) -> SceneGraphView:
	var local_view: SceneGraphView = local_views[view_name]
	var globalized_view := SceneGraphView.new(editor)
	globalized_view.copy_non_scene_data_from(local_view)
	global_views[view_name] = globalized_view
	return globalized_view


func view_name_exists(name: String) -> bool:
	return global_views.has(name) || local_views.has(name)


func activate_view(metadata: Dictionary) -> void:
	if !metadata:
		return
	var view_name: String = metadata.view_name
	match metadata.view_type:
		"global":
			if !global_views.has(view_name):
				if !_editor_state_fully_loaded:
					_pending_local_view_activation = metadata
				else:
					printerr("Failed to activate global view '" + view_name + "': No such view exists")
				return
			active_local_view = localize_global_view(view_name)
		"local":
			if !local_views.has(view_name):
				printerr("Failed to activate local view '" + view_name + "': No such view exists")
				return
			active_local_view = local_views[view_name]
	active_local_view_metadata = metadata

	editor.load(active_local_view)
	set_view_dropdown(%"View Dropdown", metadata)


func get_view(metadata: Dictionary) -> SceneGraphView:
	match metadata.view_type:
		"global":
			return global_views[metadata.view_name]
		"local":
			return local_views[metadata.view_name]
	printerr("Invalid view metadata '" + str(metadata) + "'")
	return null


func change_view_type(metadata: Dictionary, new_type: String) -> Dictionary:
	if metadata.view_type == new_type:
		return metadata
	var view_name: String = metadata.view_name
	var new_metadata := metadata.duplicate()
	new_metadata.view_type = new_type
	match new_type:
		"local":
			# assuming existing type is global
			localize_global_view(view_name)
			global_views.erase(view_name)
		"global":
			# assuming existing type is local
			globalize_local_view(view_name)
	if active_local_view_metadata.view_name == view_name:
		active_local_view_metadata = new_metadata

	repopulate_view_dropdown()
	return new_metadata


func repopulate_view_dropdown() -> void:
	var view_dropdown: OptionButton = %"View Dropdown"
	populate_view_dropdown(view_dropdown)
	set_view_dropdown(view_dropdown, active_local_view_metadata)


func create_view(metadata: Dictionary, from_existing_view: SceneGraphView = null) -> Dictionary:
	var view_name: String = metadata.view_name
	if view_name_exists(view_name):
		EditorInterface.get_editor_toaster().push_toast("Cannot create view: name '" + view_name + "' is already taken.", EditorToaster.SEVERITY_ERROR)
		return metadata
	var view_type: String = metadata.view_type
	var new_view := SceneGraphView.new(editor)
	if from_existing_view:
		new_view.copy_non_scene_data_from(from_existing_view, true)
	sanitize_view_rules(new_view)
	match view_type:
		"local":
			local_views[view_name] = new_view
		"global":
			global_views[view_name] = new_view
			localize_global_view(view_name)
	repopulate_view_dropdown()
	return metadata


func rename_view(metadata: Dictionary, new_view_name: String) -> Dictionary:
	if metadata.view_type == "global":
		EditorInterface.get_editor_toaster().push_toast("Cannot rename a global view. Please make it local first.", EditorToaster.SEVERITY_ERROR)
		return metadata
	if local_views.has(new_view_name):
		EditorInterface.get_editor_toaster().push_toast("Cannot rename view: name '" + new_view_name + "' is already taken.", EditorToaster.SEVERITY_ERROR)
		return metadata

	var new_metadata := metadata.duplicate()
	new_metadata.view_name = new_view_name

	local_views[new_view_name] = local_views[metadata.view_name]
	local_views.erase(metadata.view_name)
	if active_local_view_metadata.view_name == metadata.view_name:
		active_local_view_metadata = new_metadata
	repopulate_view_dropdown()

	return new_metadata


func remove_view(metadata: Dictionary) -> void:
	var view_name: String = metadata.view_name

	global_views.erase(view_name)
	local_views.erase(view_name)
	repopulate_view_dropdown()
	if active_local_view_metadata.view_name == metadata.view_name:
		activate_view(get_fallback_local_view_metadata())


func clear_local_view_data(metadata: Dictionary) -> void:
	var view_name: String = metadata.view_name
	var view_type: String = metadata.view_type

	match view_type:
		"local":
			local_views[view_name].clear_scene_data()
		"global":
			local_views.erase(view_name)
			localize_global_view(view_name)


func get_fallback_local_view_metadata() -> Dictionary:
	for name in global_views:
		return {
			"view_name": name,
			"view_type": "global",
		}
	for name in local_views:
		return {
			"view_name": name,
			"view_type": "local",
		}
	# uhh... no more views? Add one?
	return _help_no_views_available()


func create_default_views() -> Dictionary:
	var first_metadata: Dictionary
	for name in default_views:
		var metadata := {
			"view_name": name,
			"view_type": "global",
		}
		var serialized_view_data: Dictionary = default_views[name]
		metadata = create_view(metadata, SceneGraphView.new(editor).deserialize(serialized_view_data))
		if !first_metadata:
			first_metadata = metadata
	return first_metadata


func sanitize_view_rules(view: SceneGraphView) -> void:
	if !view:
		return
	view.view_rules.get_or_add("object_source", [])
	view.view_rules.get_or_add("member_source", [])


func reapply_rules() -> void:
	activate_view(active_local_view_metadata)


### EDIT VIEWS DIALOG
func show_dialog():
	edit_views_dialog.show()


func _help_no_views_available() -> Dictionary:
	return create_default_views()


class EditViewsDialog extends RefCounted:
	const RULE_TYPE_CONSTANTS: = {
		"object_source": {
			"label": "Node Sources",
			"tooltip": "Controls which scene objects get added automatically to the graph",
			"copy_by_default": false,
		},
		"member_source": {
			"label": "Member Sources",
			"tooltip": "Controls which object members (methods/signals) get added automatically to nodes in the graph",
			"copy_by_default": true,
		},
	}

	const ACTION_NEW_VIEW: int = 0
	const ACTION_RENAME_VIEW: int = 2
	const ACTION_REMOVE_VIEW: int = 3

	const ACTION_ADD_RULE: int = 0
	const ACTION_EDIT_RULE: int = 1
	const ACTION_MOVE_UP: int = 2
	const ACTION_MOVE_DOWN: int = 3
	const ACTION_REMOVE_RULE: int = 4

	const ACTION_EDIT_HOOK: int = 5

	var _active: Dictionary

	var editor: SceneGraphEditor
	var view_manager: Object

	var editing_view: SceneGraphView
	var editing_view_metadata: Dictionary


	func _init(editor: SceneGraphEditor, view_manager: Object):
		self.editor = editor
		self.view_manager = view_manager


	func show():
		_active = create_dialog()

		var dialog: AcceptDialog = _active["dialog"]
		dialog.confirmed.connect(view_manager.reapply_rules)

		edit_view(view_manager.active_local_view_metadata)

		dialog.visible = false
		EditorInterface.popup_dialog_centered(dialog)


	func repopulate_view_dropdown() -> void:
		var view_dropdown: OptionButton = _active["view_dropdown"]
		view_manager.populate_view_dropdown(view_dropdown)


	func edit_view(metadata: Dictionary) -> void:
		editing_view_metadata = metadata
		editing_view = view_manager.get_view(editing_view_metadata)

		_populate_tree()
		_populate_toolbar(editing_view_metadata)
		_populate_scene_info(editing_view_metadata)


	func _populate_tree() -> void:
		var tree: Tree = _active["tree"]
		tree.clear()

		var root_item := tree.create_item()

		var options_root_item := tree.create_item(root_item)
		options_root_item.set_text(COL_MAIN, "Options")
		for hook in editor.hooks.configure_hook_options:
			_populate_hook_option(tree, options_root_item, hook)

		var rules_root_item := tree.create_item(root_item)
		rules_root_item.set_text(COL_MAIN, "Rules")
		for rule_type in RULE_TYPE_CONSTANTS:
			_populate_rule_type(tree, rules_root_item, rule_type)


	func _populate_toolbar(metadata: Dictionary) -> void:
		var view_button: MenuButton = _active["view_button"]
		var popup := view_button.get_popup()
		var theme := EditorInterface.get_editor_theme()
		popup.clear()
		popup.add_icon_item(theme.get_icon("New", "EditorIcons"), "New...", ACTION_NEW_VIEW)
		popup.add_icon_item(theme.get_icon("Rename", "EditorIcons"), "Rename...", ACTION_RENAME_VIEW)
		popup.set_item_disabled(popup.item_count - 1, metadata.view_type == "global")
		popup.set_item_tooltip(popup.item_count - 1, "Cannot rename a global view" if (metadata.view_type == "global") else "")
		popup.set_item_accelerator(popup.item_count - 1, Key.KEY_F2)
		popup.add_icon_item(theme.get_icon("Remove", "EditorIcons"), "Remove", ACTION_REMOVE_VIEW)
		popup.set_item_accelerator(popup.item_count - 1, Key.KEY_DELETE)

		var view_dropdown: OptionButton = _active["view_dropdown"]
		view_manager.set_view_dropdown(view_dropdown, metadata)

		var global_toggle: CheckButton = _active["global_toggle"]
		global_toggle.set_pressed_no_signal(metadata.view_type == "global")


	func _populate_scene_info(metadata: Dictionary) -> void:
		var scene_name_label: Label = _active["scene_name_label"]
		scene_name_label.text = "This Scene (" + editor.scene_root.scene_file_path.get_file() + ")"

		var localized_view: SceneGraphView = view_manager.get_localized_view(metadata.view_name)

		_active["graph_node_count_label"].text = str(localized_view.get_scene_object_count()) if localized_view && localized_view.has_any_scene_data() else "Unknown"


	func _make_global(global: bool) -> void:
		var new_metadata: Dictionary = view_manager.change_view_type(editing_view_metadata, "global" if global else "local")
		repopulate_view_dropdown()
		edit_view(new_metadata)


	func _populate_rule_type(tree: Tree, rules_root_item: TreeItem, rule_type: String) -> void:
		var rule_type_item := tree.create_item(rules_root_item)
		rule_type_item.set_text(COL_MAIN, RULE_TYPE_CONSTANTS[rule_type].label)
		rule_type_item.set_tooltip_text(COL_MAIN, RULE_TYPE_CONSTANTS[rule_type].tooltip)
		for col in range(tree.columns):
			rule_type_item.set_custom_stylebox(col, _active["header_stylebox"])
		var theme := EditorInterface.get_editor_theme()

		rule_type_item.add_button(COL_BUTTONS, theme.get_icon("Add", "EditorIcons"), ACTION_ADD_RULE, false, "Add Rule")
		rule_type_item.set_metadata(
			0,
			{
				"row_type": "rule_type",
				"rule_type": rule_type,
			},
		)

		var rules: Array = editing_view.view_rules.get(rule_type)
		var rule_index := 0
		if rules:
			for rule_obj in rules:
				var rule_item := tree.create_item(rule_type_item)
				var hook: Object = editor.current_view.get_view_rule_hook(rule_obj.id, rule_type)
				if hook:
					rule_item.set_text(COL_MAIN, hook.get_view_rule_label(editor.current_view.rule_params_from_dict(hook, rule_obj.get("params") as Dictionary)))
				else:
					rule_item.set_text(COL_MAIN, rule_obj.id)
				rule_item.set_icon(COL_MAIN, theme.get_icon("TripleBar", "EditorIcons"))

				rule_item.add_button(COL_BUTTONS, theme.get_icon("Edit", "EditorIcons"), ACTION_EDIT_RULE, false, "Edit")
				rule_item.add_button(COL_BUTTONS, theme.get_icon("MoveUp", "EditorIcons"), ACTION_MOVE_UP, rule_index == 0, "Move Up")
				rule_item.add_button(COL_BUTTONS, theme.get_icon("MoveDown", "EditorIcons"), ACTION_MOVE_DOWN, rule_index == rules.size() - 1, "Move Down")
				rule_item.add_button(COL_BUTTONS, theme.get_icon("Remove", "EditorIcons"), ACTION_REMOVE_RULE, false, "Remove")
				rule_item.custom_minimum_height = 30

				rule_item.set_metadata(
					0,
					{
						"row_type": "rule",
						"rule_type": rule_type,
						"rule_index": rule_index,
					},
				)

				rule_index += 1
		else:
			var no_rule_item := tree.create_item(rule_type_item)
			no_rule_item.set_text(0, "(none)")


	func _populate_hook_option(tree: Tree, options_root_item: TreeItem, hook: Object) -> void:
		var theme := EditorInterface.get_editor_theme()
		if !hook:
			return
		var hook_item := tree.create_item(options_root_item)
		hook_item.set_text(COL_MAIN, hook.get_hook_options_label(editing_view.get_hook_options(hook)))
		hook_item.set_icon(COL_MAIN, theme.get_icon("Script", "EditorIcons"))

		hook_item.add_button(COL_BUTTONS, theme.get_icon("Edit", "EditorIcons"), ACTION_EDIT_HOOK, false, "Edit")

		hook_item.set_metadata(
			0,
			{
				"row_type": "hook",
				"hook": hook,
			},
		)
		pass


	func _tree_drag(at_position: Vector2) -> Variant:
		var tree: Tree = _active["tree"]
		var item := tree.get_item_at_position(at_position)
		if !item:
			return null
		var metadata = item.get_metadata(0)
		if !metadata:
			return { }
		match metadata.get("row_type"):
			"rule":
				return {
					"type": "view_rule",
					"metadata": metadata,
				}
		return null


	func _tree_can_drop(at_position: Vector2, data: Dictionary) -> bool:
		var tree: Tree = _active["tree"]

		if data.get("type") != "view_rule":
			return _cannot_drop()
		var target_item := tree.get_item_at_position(at_position)
		if !target_item:
			return _cannot_drop()
		var target_item_metadata = target_item.get_metadata(0)
		if !target_item_metadata:
			return _cannot_drop()
		if target_item_metadata.get("row_type") != "rule":
			return _cannot_drop()
		if target_item_metadata.rule_type != data.metadata.rule_type:
			return _cannot_drop()
		tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
		return true


	func _cannot_drop() -> bool:
		var tree: Tree = _active["tree"]
		tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
		return false


	func _tree_drop(at_position: Vector2, data: Dictionary) -> void:
		var tree: Tree = _active["tree"]
		var target_item := tree.get_item_at_position(at_position)
		var target_item_metadata = target_item.get_metadata(0)
		var drop_section := tree.get_drop_section_at_position(at_position)

		move_rule(data.metadata, target_item_metadata.rule_index + clampi(drop_section, -1, 0))


	func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
		match id:
			ACTION_ADD_RULE:
				add_rule(item.get_metadata(0).rule_type)
			ACTION_EDIT_RULE:
				edit_rule(item.get_metadata(0))
			ACTION_MOVE_UP:
				move_rule(item.get_metadata(0), -1)
			ACTION_MOVE_DOWN:
				move_rule(item.get_metadata(0), +1)
			ACTION_REMOVE_RULE:
				remove_rule(item.get_metadata(0))
			ACTION_EDIT_HOOK:
				edit_hook_options(item.get_metadata(0))


	func move_rule(metadata: Dictionary, offset: int) -> void:
		var rule_type: String = metadata.rule_type
		var rule_index: int = metadata.rule_index
		var rule_arr: Array = editing_view.view_rules[rule_type]
		var rule_obj = rule_arr[rule_index]
		rule_arr.remove_at(rule_index)
		rule_arr.insert(rule_index + offset, rule_obj)
		call_deferred(&"_populate_tree")


	func edit_rule(metadata: Dictionary) -> void:
		var rule_type: String = metadata.rule_type
		var rule_index: int = metadata.rule_index
		var rule_arr: Array = editing_view.view_rules[rule_type]
		var rule_obj = rule_arr[rule_index]
		var dialog: Window = load("res://addons/scene-graphs/scenes/scene_graph_view_rule_edit_dialog.tscn").instantiate()
		var hook: Object = editor.current_view.get_view_rule_hook(rule_obj.id, rule_type)
		dialog.setup(rule_type, editor.current_view.get_view_rule_hooks(rule_type), hook, editor.current_view.rule_params_from_dict(hook, rule_obj.get("params") as Dictionary))
		dialog.rule_selected.connect(
			func(selected_hook: Object, selected_params: Variant) -> void:
				rule_arr[rule_index] = {
					"id": selected_hook.get_view_rule_id(),
					"params": editor.current_view.rule_params_to_dict(selected_hook, selected_params),
				}
				call_deferred(&"_populate_tree")
		)
		EditorInterface.popup_dialog_centered(dialog)


	func add_rule(rule_type: String) -> void:
		var rule_arr: Array = editing_view.view_rules[rule_type]
		var dialog: Window = load("res://addons/scene-graphs/scenes/scene_graph_view_rule_edit_dialog.tscn").instantiate()
		dialog.setup(rule_type, editor.current_view.get_view_rule_hooks(rule_type), null, null)
		dialog.rule_selected.connect(
			func(selected_hook: Object, selected_params: Variant) -> void:
				rule_arr.append(
					{
						"id": selected_hook.get_view_rule_id(),
						"params": editor.current_view.rule_params_to_dict(selected_hook, selected_params),
					},
				)
				call_deferred(&"_populate_tree")
		)
		EditorInterface.popup_dialog_centered(dialog)


	func remove_rule(metadata: Dictionary) -> void:
		var rule_type: String = metadata.rule_type
		var rule_index: int = metadata.rule_index
		var rule_arr: Array = editing_view.view_rules[rule_type]
		rule_arr.remove_at(rule_index)
		call_deferred(&"_populate_tree")


	func edit_hook_options(metadata: Dictionary) -> void:
		var hook: Object = metadata.hook
		var dialog: Window = load("res://addons/scene-graphs/scenes/scene_graph_hook_option_edit_dialog.tscn").instantiate()
		dialog.setup(hook, editing_view.get_hook_options(hook))
		dialog.finished.connect(
			func(selected_hook: Object, selected_options: Variant) -> void:
				var id: String = hook.get_hook_options_id()
				editing_view.hook_options[id] = editor.current_view.hook_options_to_dict(selected_hook, selected_options)
				call_deferred(&"_populate_tree")
		)
		EditorInterface.popup_dialog_centered(dialog)


	func create_dialog() -> Dictionary:
		var output: Dictionary = {
			"dialog": null,
			"view_button": null,
			"view_dropdown": null,
			"tree": null,
		}
		var theme := EditorInterface.get_editor_theme()

		var dialog: AcceptDialog = load("res://addons/scene-graphs/scenes/scene_graph_view_manager_dialog.tscn").instantiate()
		output["dialog"] = dialog
		dialog.theme = theme

		# View Button
		var view_button: MenuButton = dialog.get_node("%View Button")
		output["view_button"] = view_button
		view_button.get_popup().id_pressed.connect(_perform_view_action, CONNECT_DEFERRED)

		# Global Toggle
		var global_toggle: CheckButton = dialog.get_node("%Global Toggle")
		output["global_toggle"] = global_toggle
		global_toggle.toggled.connect(_make_global)

		# View Dropdown

		var view_dropdown: OptionButton = dialog.get_node("%View Dropdown")
		output["view_dropdown"] = view_dropdown
		view_manager.populate_view_dropdown(view_dropdown)
		view_dropdown.item_selected.connect(
			func(selected_index: int) -> void:
				var metadata = view_dropdown.get_item_metadata(selected_index)
				call_deferred(&"edit_view", metadata)
		)

		# Tree
		var tree: Tree = dialog.get_node("%Tree")
		output["tree"] = tree
		tree.columns = 2
		tree.hide_root = true
		tree.set_column_expand(COL_BUTTONS, false)
		tree.set_drag_forwarding(_tree_drag, _tree_can_drop, _tree_drop)
		tree.button_clicked.connect(_on_tree_button_clicked)

		dialog.close_requested.connect(dialog.queue_free)

		# Scene Name
		var scene_name_label: Label = dialog.get_node("%Scene Name")
		output["scene_name_label"] = scene_name_label
		var graph_node_count_label: Label = dialog.get_node("%Graph Node Count")
		output["graph_node_count_label"] = graph_node_count_label
		var clear_button: Button = dialog.get_node("%Clear Button")
		output["clear_button"] = clear_button
		clear_button.pressed.connect(_clear_local_view_data, CONNECT_DEFERRED)

		# Styles
		var rule_header_stylebox := StyleBoxFlat.new()
		rule_header_stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.25)
		output["header_stylebox"] = rule_header_stylebox

		return output


	func _perform_view_action(action: int) -> void:
		var metadata := editing_view_metadata
		match action:
			ACTION_NEW_VIEW:
				popup_view_new_dialog("", metadata, _validate_view_name, _new_view)
			ACTION_RENAME_VIEW:
				popup_view_rename_dialog(metadata.view_name, _validate_view_name, func(new_name: String) -> void: _rename_view(metadata, new_name))
			ACTION_REMOVE_VIEW:
				var dialog := ConfirmationDialog.new()
				dialog.title = "Please confirm..."
				dialog.dialog_text = "Delete " + metadata.view_type + " view '" + metadata.view_name + "'?"
				if metadata.view_type == "global":
					dialog.dialog_text += "\nLocal copies of this view may still remain in some scenes."
				dialog.confirmed.connect(_remove_view.bind(metadata), CONNECT_DEFERRED)
				dialog.confirmed.connect(dialog.queue_free, CONNECT_DEFERRED)
				dialog.canceled.connect(dialog.queue_free, CONNECT_DEFERRED)
				dialog.close_requested.connect(dialog.queue_free, CONNECT_DEFERRED)
				EditorInterface.popup_dialog_centered(dialog)


	func _validate_view_name(name: String) -> Array:
		if name.is_empty() || name.strip_edges().is_empty():
			return [false, "View name cannot be empty."]
		if view_manager.view_name_exists(name):
			return [false, "View name already exists."]
		return [true, "View name is valid."]


	func _new_view(new_metadata: Dictionary, based_on_metadata: Dictionary, copy_flags_per_rule_type: Dictionary) -> void:
		var base_view: SceneGraphView
		if based_on_metadata:
			var based_on_view: SceneGraphView = view_manager.get_view(based_on_metadata)
			base_view = SceneGraphView.new(editor)

			base_view.hook_options = based_on_view.hook_options.duplicate(true)
			for rule_type in copy_flags_per_rule_type:
				if !copy_flags_per_rule_type[rule_type]:
					continue
				base_view.view_rules[rule_type] = based_on_view.view_rules.get(rule_type, { }).duplicate(true)
		new_metadata = view_manager.create_view(new_metadata, base_view)
		repopulate_view_dropdown()
		edit_view(new_metadata)
		view_manager.activate_view(new_metadata)


	func _rename_view(existing_metadata: Dictionary, new_name: String) -> void:
		var new_metadata = view_manager.rename_view(existing_metadata, new_name)
		repopulate_view_dropdown()
		edit_view(new_metadata)


	func _remove_view(metadata: Dictionary) -> void:
		view_manager.remove_view(metadata)
		repopulate_view_dropdown()
		edit_view(view_manager.active_local_view_metadata)


	func _clear_local_view_data() -> void:
		var metadata := editing_view_metadata
		view_manager.clear_local_view_data(metadata)
		view_manager.activate_view(metadata)
		_active["dialog"].queue_free()


	func popup_view_new_dialog(preset_text: String, preset_based_on_metadata: Dictionary, validation_callback: Callable, finished_callback: Callable) -> void:
		var dialog := ConfirmationDialog.new()
		var theme := EditorInterface.get_editor_theme()
		dialog.title = "Create New View"
		dialog.size = Vector2(420, 320)
		dialog.ok_button_text = "Create"
		var content := VBoxContainer.new()
		dialog.add_child(content)

		# Name Row (+ global toggle)
		var name_row := HBoxContainer.new()
		content.add_child(name_row)
		var name_label := Label.new()
		name_label.text = "Name: "
		name_row.add_child(name_label)
		var name_field := LineEdit.new()
		name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if preset_text:
			name_field.text = preset_text
		dialog.ready.connect(name_field.grab_focus, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		dialog.ready.connect(name_field.select_all, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		name_field.keep_editing_on_text_submit = true
		name_field.text_submitted.connect(
			func(_text: String) -> void:
				if !dialog.get_ok_button().disabled:
					dialog.get_ok_button().pressed.emit()
		)
		name_row.add_child(name_field)
		var global_toggle := CheckButton.new()
		global_toggle.text = "Global"
		name_row.add_child(global_toggle)

		# Based-on Row
		var based_on_row := HBoxContainer.new()
		content.add_child(based_on_row)
		var based_on_label := Label.new()
		based_on_label.text = "Based on: "
		based_on_row.add_child(based_on_label)
		var based_on_dropdown := OptionButton.new()
		based_on_row.add_child(based_on_dropdown)
		based_on_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		based_on_dropdown.add_item("(Empty)")
		based_on_dropdown.set_item_metadata(based_on_dropdown.item_count - 1, { })
		view_manager.populate_view_dropdown(based_on_dropdown, false)
		view_manager.set_view_dropdown(based_on_dropdown, preset_based_on_metadata)

		# Copy Options
		var copy_options_tree := Tree.new()
		copy_options_tree.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		copy_options_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(copy_options_tree)

		var copy_flags_per_rule_type := { }

		var update_tree := func() -> void:
			copy_options_tree.clear()
			var tree_root := copy_options_tree.create_item()
			copy_options_tree.hide_root = true
			var rules_root := copy_options_tree.create_item(tree_root)
			rules_root.set_text(0, "Copy Rules")

			var based_on_metadata: Dictionary = based_on_dropdown.get_selected_metadata() as Dictionary

			for rule_type in RULE_TYPE_CONSTANTS:
				var rule_type_info: Dictionary = RULE_TYPE_CONSTANTS[rule_type]
				var view: SceneGraphView = view_manager.get_view(based_on_metadata) if based_on_metadata else null

				var rule_type_item := copy_options_tree.create_item(rules_root)
				copy_flags_per_rule_type[rule_type] = view_manager.interface_memory.view_copy_preferences.view_rules.get_or_add(rule_type, rule_type_info.copy_by_default)
				var checked: bool = copy_flags_per_rule_type[rule_type]
				var rule_count: int = view.view_rules.get(rule_type).size() if view != null && view.view_rules.has(rule_type) else 0
				rule_type_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
				rule_type_item.set_editable(0, rule_count > 0)
				rule_type_item.set_text(0, "%s (%s)" % [rule_type_info.label, rule_count])
				rule_type_item.set_checked(0, checked && rule_count > 0)
				rule_type_item.set_metadata(
					0,
					{
						"rule_type": rule_type,
					},
				)
				if view:
					var rules: Array = view.view_rules.get(rule_type)
					if rules:
						for rule_obj in rules:
							var rule_item := copy_options_tree.create_item(rule_type_item)
							var hook: Object = view.get_view_rule_hook(rule_obj.id, rule_type)
							if hook:
								rule_item.set_text(0, hook.get_view_rule_label(view.rule_params_from_dict(hook, rule_obj.get("params") as Dictionary)))
							else:
								rule_item.set_text(0, rule_obj.id)
							rule_item.set_icon(0, theme.get_icon(&"GuiScrollGrabber", &"EditorIcons"))
					else:
						var no_rule_item := copy_options_tree.create_item(rule_type_item)
						no_rule_item.set_text(0, "(none)")

		update_tree.call()
		copy_options_tree.item_edited.connect(
			func() -> void:
				var edited_item := copy_options_tree.get_edited()
				var metadata: Dictionary = edited_item.get_metadata(0)
				if metadata.has("rule_type"):
					var rule_type: String = metadata.rule_type
					var checked := edited_item.is_checked(0)
					copy_flags_per_rule_type[rule_type] = checked
					view_manager.interface_memory.view_copy_preferences.view_rules[rule_type] = checked
		)
		based_on_dropdown.item_selected.connect(
			func(_index: int) -> void:
				update_tree.call()
		)

		# Status
		var status_container := PanelContainer.new()
		status_container.custom_minimum_size = Vector2(10, 33)
		status_container.add_theme_stylebox_override("panel", status_container.get_theme_stylebox("panel", "EditorValidationPanel"))
		content.add_child(status_container)
		var status_label := Label.new()
		status_label.text = " •  Name can't be empty"
		status_container.add_child(status_label)

		var validate: Callable = func() -> void:
			var result: Array = validation_callback.call(name_field.text)
			var valid: bool = result[0]
			var status_msg: String = result[1]
			dialog.get_ok_button().disabled = !valid
			status_label.text = " •  " + status_msg
			status_label.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"success_color" if valid else &"error_color", &"Editor"))

		name_field.text_changed.connect(validate.unbind(1))
		validate.call()

		dialog.confirmed.connect(
			func() -> void:
				var new_metadata := {
					"view_name": name_field.text,
					"view_type": "global" if global_toggle.button_pressed else "local",
				}
				var based_on_metadata: Dictionary = based_on_dropdown.get_selected_metadata() as Dictionary
				finished_callback.call(new_metadata, based_on_metadata, copy_flags_per_rule_type)
		)
		dialog.confirmed.connect(dialog.queue_free, CONNECT_DEFERRED)
		dialog.canceled.connect(dialog.queue_free, CONNECT_DEFERRED)
		dialog.close_requested.connect(dialog.queue_free, CONNECT_DEFERRED)

		EditorInterface.popup_dialog_centered(dialog)


	func popup_view_rename_dialog(preset_text: String, validation_callback: Callable, finished_callback: Callable) -> void:
		var dialog := ConfirmationDialog.new()
		dialog.title = "Rename View"
		dialog.size = Vector2(420, 130)
		dialog.ok_button_text = "Rename"
		var content := VBoxContainer.new()
		dialog.add_child(content)
		var name_row := HBoxContainer.new()
		content.add_child(name_row)
		var name_label := Label.new()
		name_label.text = "Name: "
		name_row.add_child(name_label)
		var name_field := LineEdit.new()
		name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if preset_text:
			name_field.text = preset_text
		dialog.ready.connect(name_field.grab_focus, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		dialog.ready.connect(name_field.select_all, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		name_field.keep_editing_on_text_submit = true
		name_field.text_submitted.connect(
			func(_text: String) -> void:
				if !dialog.get_ok_button().disabled:
					dialog.get_ok_button().pressed.emit()
		)
		name_row.add_child(name_field)

		var status_container := PanelContainer.new()
		status_container.custom_minimum_size = Vector2(10, 33)
		status_container.add_theme_stylebox_override("panel", status_container.get_theme_stylebox("panel", "EditorValidationPanel"))
		content.add_child(status_container)
		var status_label := Label.new()
		status_label.text = " •  Name can't be empty"
		status_container.add_child(status_label)

		var validate: Callable = func() -> void:
			var result: Array = validation_callback.call(name_field.text)
			var valid: bool = result[0]
			var status_msg: String = result[1]
			dialog.get_ok_button().disabled = !valid
			status_label.text = " •  " + status_msg
			status_label.add_theme_color_override(&"font_color", EditorInterface.get_editor_theme().get_color(&"success_color" if valid else &"error_color", &"Editor"))

		name_field.text_changed.connect(validate.unbind(1))
		validate.call()

		dialog.confirmed.connect(
			func() -> void:
				finished_callback.call(name_field.text)
		)
		dialog.confirmed.connect(dialog.queue_free, CONNECT_DEFERRED)
		dialog.canceled.connect(dialog.queue_free, CONNECT_DEFERRED)
		dialog.close_requested.connect(dialog.queue_free, CONNECT_DEFERRED)

		EditorInterface.popup_dialog_centered(dialog)
