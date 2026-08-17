@tool
class_name SceneGraphMemberSelector
extends RefCounted

enum SelectorMode {
	SINGLE,
	MULTIPLE,
}

var _last_selected_member_type := ""

var all_member_types
var all_input_member_types
var all_output_member_types

var _active: ActiveDialog

var editor: SceneGraphEditor


func _init(editor: SceneGraphEditor):
	self.editor = editor


func get_all_member_types() -> Array[String]:
	if all_member_types:
		return all_member_types
	all_member_types = [] as Array[String]

	for hook in editor.hooks.configure_member_selector:
		for member_type in hook.get_member_selector_member_types():
			if !all_member_types.has(member_type):
				all_member_types.append(member_type)

	return all_member_types


func get_all_input_member_types() -> Array[String]:
	if all_input_member_types:
		return all_input_member_types
	all_input_member_types = [] as Array[String]

	for hook in editor.hooks.configure_member_selector:
		for member_type in hook.get_member_selector_member_types():
			if hook.get_member_selector_tab_info(member_type).get("is_input", false):
				if !all_input_member_types.has(member_type):
					all_input_member_types.append(member_type)

	return all_input_member_types


func get_all_output_member_types() -> Array[String]:
	if all_output_member_types:
		return all_output_member_types
	all_output_member_types = [] as Array[String]

	for hook in editor.hooks.configure_member_selector:
		for member_type in hook.get_member_selector_member_types():
			if hook.get_member_selector_tab_info(member_type).get("is_output", false):
				if !all_output_member_types.has(member_type):
					all_output_member_types.append(member_type)

	return all_output_member_types


func _get_tab_info(member_type: String) -> Dictionary:
	for hook in editor.hooks.configure_member_selector:
		if hook.get_member_selector_member_types().has(member_type):
			var tab_info: Dictionary = hook.get_member_selector_tab_info(member_type)
			if tab_info:
				return tab_info
	return { }


func _filter_valid_member_types(member_types: Array[String]) -> bool:
	if !member_types:
		return false
	var filtered := member_types.filter(
		func(member_type: String) -> bool:
			for hook in editor.hooks.configure_member_selector:
				if hook.get_member_selector_member_types().has(member_type):
					return true
			printerr("No hook is capable of configuring member type '" + member_type + "' for the member selector.")
			return false
	)
	member_types.clear()
	member_types.append_array(filtered)
	if !member_types:
		return false
	return true


func show_single_select(object_type: String, obj: Object, member_types: Array[String], member_callback: Callable) -> void:
	if !obj:
		return
	if !_filter_valid_member_types(member_types):
		return
	_active = _create_member_selector(SelectorMode.SINGLE, member_types)

	_active.object_type = object_type
	_active.obj = obj
	_active.member_types = member_types
	_active.member_callback = member_callback

	for member_type in member_types:
		for hook in editor.hooks.configure_member_selector:
			if hook.get_member_selector_member_types().has(member_type):
				_active.member_lists_by_type[member_type] = hook.get_member_selector_member_list(object_type, obj, member_type) as Array
				break

	_populate_tree("")

	EditorInterface.popup_dialog_centered(_active.dialog)


func show_multi_select(object_type: String, obj: Object, member_types: Array[String], active_members: Dictionary, member_callback: Callable) -> void:
	if !obj:
		return
	if !_filter_valid_member_types(member_types):
		return
	_active = _create_member_selector(SelectorMode.MULTIPLE, member_types)

	_active.object_type = object_type
	_active.obj = obj
	_active.member_types = member_types
	_active.member_callback = member_callback

	for member_type in member_types:
		_active.checked_members_by_type[member_type] = (active_members.get(member_type, []) as Array).duplicate()
		for hook in editor.hooks.configure_member_selector:
			if hook.get_member_selector_member_types().has(member_type):
				_active.member_lists_by_type[member_type] = hook.get_member_selector_member_list(object_type, obj, member_type) as Array
				break

	_populate_tree("")

	EditorInterface.popup_dialog_centered(_active.dialog)


func _populate_tree(filter: String) -> void:
	var tree := _active.tree
	var tab_group := _active.tab_group

	# Handles are Dictionaries with:
	# member_type (String)
	# member_name (StringName)
	# They're used in tree item metadata to keep a reference to where they came from

	# Grab the handle of the last selected entry, before we clear it and reapply the filter, so we can reselect it later.
	var selected_handle: Dictionary = tree.get_selected().get_metadata(0) if tree.get_selected() else { }

	tree.clear()

	var root := tree.create_item()

	var selected_member_type: String = tab_group.get_pressed_button().get_meta(&"member_type", _active.member_types[0])
	var member_list: Array = _active.member_lists_by_type.get(selected_member_type)
	var list_root := tree.create_item(root)
	list_root.set_text(0, tab_group.get_pressed_button().text)

	for member_index in range(member_list.size()):
		var member_info: Dictionary = member_list[member_index]
		var handle := {
			"member_type": selected_member_type,
			"member_name": member_info.member_name as StringName,
		}

		var label: String = member_info.label

		if filter && !filter.is_subsequence_ofn(label):
			continue

		var item := tree.create_item(list_root)
		match _active.mode:
			SelectorMode.SINGLE:
				pass
			SelectorMode.MULTIPLE:
				item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
				item.set_editable(0, true)
				item.set_checked(0, _active.checked_members_by_type[selected_member_type].has(member_info.member_name as StringName))
		item.set_icon(0, member_info.get("icon"))
		item.set_text(0, member_info.get("label"))
		item.set_metadata(0, handle)
		if selected_handle == handle:
			item.select(0)

	_on_selection_changed()


func _on_selection_changed() -> void:
	_update_dialog_buttons()


func _update_dialog_buttons() -> void:
	var dialog := _active.dialog
	var tree: Tree = _active.tree
	if !dialog || !tree:
		return
	match _active.mode:
		SelectorMode.SINGLE:
			dialog.get_ok_button().disabled = tree.get_selected() == null
		SelectorMode.MULTIPLE:
			dialog.get_ok_button().disabled = false
			_update_tab_titles()


func _update_tab_titles() -> void:
	for button: Button in _active.tab_group.get_buttons():
		var member_type: String = button.get_meta(&"member_type", "")
		var tab_info: Dictionary = _get_tab_info(member_type)
		if !tab_info:
			continue
		match _active.mode:
			SelectorMode.SINGLE:
				button.text = tab_info.label
			SelectorMode.MULTIPLE:
				var count := (_active.checked_members_by_type.get(member_type, []) as Array).size()
				if count == 0:
					button.text = tab_info.label
				else:
					button.text = "%s (%s)" % [tab_info.label, count]


func _tree_on_item_activated() -> void:
	if _active.mode == SelectorMode.SINGLE:
		var dialog := _active.dialog
		var tree := _active.tree
		if !dialog || !tree:
			return
		tree.accept_event()
		if !dialog.get_ok_button().disabled:
			_on_submitted()


func _tree_on_item_edited() -> void:
	var tree := _active.tree
	var item := _active.tree.get_edited()
	if _active.mode == SelectorMode.MULTIPLE:
		var handle: Dictionary = item.get_metadata(0)
		if handle.has("member_type") && handle.has("member_name"):
			var member_type: String = handle.member_type
			var member_name: StringName = handle.member_name
			var checked := item.is_checked(0)
			var list: Array = _active.checked_members_by_type.get_or_add(member_type, [])
			if checked:
				if !list.has(member_name):
					list.append(member_name)
			else:
				var index := list.find(member_name)
				if index >= 0:
					list.remove_at(index)
	_update_dialog_buttons()


func _on_tab_group_pressed(btn: BaseButton) -> void:
	_last_selected_member_type = btn.get_meta(&"member_type", "")
	_populate_tree(_active.search_bar.text)


func _on_submitted() -> void:
	var tree := _active.tree

	var member_callback := _active.member_callback

	if member_callback.is_valid():
		match _active.mode:
			SelectorMode.SINGLE:
				var selected_handle: Dictionary = tree.get_selected().get_metadata(0) if tree.get_selected() else { }
				var member_type: String = selected_handle.member_type
				var member_name: StringName = selected_handle.member_name
				member_callback.call(_active.object_type, _active.obj, member_type, member_name)
			SelectorMode.MULTIPLE:
				member_callback.call(_active.object_type, _active.obj, _active.checked_members_by_type)

	_active.dialog.queue_free()


func _create_member_selector(mode: SelectorMode, member_types: Array[String]) -> ActiveDialog:
	var output: ActiveDialog = ActiveDialog.new()
	output.mode = mode

	var theme := EditorInterface.get_editor_theme()

	var dialog: ConfirmationDialog = load("res://addons/scene-graphs/scenes/scene_graph_member_selector_dialog.tscn").instantiate()
	output.dialog = dialog
	dialog.theme = theme
	match mode:
		SelectorMode.SINGLE:
			dialog.title = "Select Member"
			dialog.ok_button_text = "Select"
		SelectorMode.MULTIPLE:
			dialog.title = "Select Members"
			dialog.ok_button_text = "Select"

	# Tabs

	var force_start_tab := _last_selected_member_type if member_types.has(_last_selected_member_type) else member_types[0]

	var tab_row: Container = dialog.get_node("%Tab Row")
	var tab_group := ButtonGroup.new()
	output.tab_group = tab_group
	for member_type in member_types:
		var tab_info: Dictionary = _get_tab_info(member_type)
		if !tab_info:
			continue
		var tab_button := Button.new()
		tab_button.text = tab_info.label
		tab_button.button_group = tab_group
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.icon = tab_info.icon
		tab_button.toggle_mode = true
		tab_button.button_pressed = member_type == force_start_tab
		tab_button.theme_type_variation = "FlatMenuButton"
		tab_button.set_meta(&"member_type", member_type)
		tab_row.add_child(tab_button)
	tab_group.pressed.connect(_on_tab_group_pressed)

	# Search Bar

	var search_bar: LineEdit = dialog.get_node("%Search Bar")
	output.search_bar = search_bar
	search_bar.right_icon = theme.get_icon(&"Search", &"EditorIcons")
	search_bar.text_changed.connect(_populate_tree)

	# Tree
	var tree: Tree = dialog.get_node("%Tree")
	output.tree = tree
	tree.item_selected.connect(_on_selection_changed)
	tree.item_activated.connect(_tree_on_item_activated)
	tree.item_edited.connect(_tree_on_item_edited)

	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(_on_submitted)

	return output


class ActiveDialog extends RefCounted:
	var mode: SelectorMode
	var dialog: ConfirmationDialog
	var tree: Tree
	var tab_group: ButtonGroup
	var search_bar: LineEdit

	var object_type: String
	var obj: Object
	var member_types: Array[String]
	var member_callback: Callable

	var member_lists_by_type: Dictionary
	var checked_members_by_type: Dictionary
