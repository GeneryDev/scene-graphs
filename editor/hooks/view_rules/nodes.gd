@tool
extends RefCounted

const OBJECT_TYPE_NODE := "node"

var editor: SceneGraphEditor


func _init(editor: SceneGraphEditor):
	self.editor = editor


func get_scene_graph_capabilities() -> Array[String]:
	return ["view_rule.object_source", "populate_popup_menu"]


func get_view_rule_id() -> String:
	return "scene_graphs:nodes"


func get_view_rule_label(params: Params) -> String:
	if params == null:
		return "Nodes"
	var label := ""
	if params && params.sub_paths:
		if params.require_shown_members:
			label += "Nodes with path: "
		else:
			label += "All nodes with path: "
		label += ", ".join(params.sub_paths)
	elif params.require_shown_members:
		label = "Nodes"
	else:
		label = "All Nodes"
	return label


func generate_view_objects(params: Params) -> Array:
	var objects := []
	_update_node_views_with_rules(editor.scene_root, params, objects)
	return objects


func _update_node_views_with_rules(node: Node, params: Params, objects: Array) -> bool:
	if !node:
		return false
	if !(node == editor.scene_root || node.owner == editor.scene_root):
		return false

	var any_changes := _update_object_view_with_rules(node, params, objects)

	for child in node.get_children():
		if _update_node_views_with_rules(child, params, objects):
			any_changes = true

	return any_changes


func _update_object_view_with_rules(node: Node, params: Params, objects: Array) -> bool:
	if !node:
		return false

	if _should_include_node(node, params):
		objects.append(
			{
				"object_type": OBJECT_TYPE_NODE,
				"object": node,
			},
		)
		return true
	else:
		return false


func _should_include_node(node: Node, params: Params) -> bool:
	if !node:
		return false

	if params.sub_paths:
		var has_subpath := false
		var path := str(editor.scene_root.get_path_to(node)) if node != editor.scene_root else str(node.name)

		for subpath in params.sub_paths:
			if subpath.is_empty():
				continue
			if path.containsn(subpath):
				has_subpath = true
				break

		if !has_subpath:
			return false

	if params.require_shown_members:
		var members: Array
		if params._force_member_source != null:
			var rule_entry = params._force_member_source
			members = editor.current_view.generate_object_member_list_with_rule(OBJECT_TYPE_NODE, node, rule_entry)
		else:
			members = editor.current_view.generate_object_member_list_with_rules(OBJECT_TYPE_NODE, node)
		if members.is_empty():
			return false

	return true


func create_view_rule_params() -> Object:
	return Params.new()


func get_view_rule_description() -> String:
	return "Adds graph objects corresponding to each node in the scene, based on certain criteria."

### CAPABILITY: populate_popup_menu
const ACTION_ADD_NODES_BY_MEMBER_SOURCE: int = 1000


func populate_popup_menu(at_position: Vector2, menu: PopupMenu, actions: Dictionary[int, Callable]) -> void:
	var hovered_element := editor.get_graph_element_at_position(at_position)
	if hovered_element != null:
		return

	menu.add_separator("Graph View")
	var submenu := PopupMenu.new()
	menu.add_child(submenu)
	menu.add_submenu_node_item("Add Nodes by Member Source", submenu)

	for rule_entry in editor.current_view.get_view_rules_of_type("member_source"):
		var id: String = rule_entry.id
		var raw_params: Dictionary = rule_entry.get("params")
		var rule_hook := editor.current_view.get_view_rule_hook(id, "member_source")
		if !rule_hook:
			continue
		var params = editor.current_view.rule_params_from_dict(rule_hook, raw_params)
		var label = rule_hook.get_view_rule_label(params)
		submenu.add_item(label)
		submenu.set_item_metadata(submenu.item_count - 1, rule_entry)

	submenu.add_item("Custom...")
	submenu.set_item_metadata(submenu.item_count - 1, { })

	submenu.index_pressed.connect(_member_source_submenu_index_pressed.bind(submenu))


func _member_source_submenu_index_pressed(index: int, submenu: PopupMenu) -> void:
	var rule_entry: Dictionary = submenu.get_item_metadata(index)
	if rule_entry:
		_add_nodes_by_member_source(rule_entry)
	else:
		# Custom
		var dialog: Window = load("res://addons/scene-graphs/scenes/scene_graph_view_rule_edit_dialog.tscn").instantiate()
		dialog.setup("member_source", editor.current_view.get_view_rule_hooks("member_source"), null, null)
		dialog.title = "Add Nodes by Member Source"
		dialog.rule_selected.connect(
			func(selected_hook: Object, selected_params: Variant) -> void:
				_add_nodes_by_member_source(
					{
						"id": selected_hook.get_view_rule_id(),
						"params": editor.current_view.rule_params_to_dict(selected_hook, selected_params),
					},
				)
		)
		EditorInterface.popup_dialog_centered(dialog)


func _add_nodes_by_member_source(rule_entry: Dictionary) -> void:
	if !rule_entry:
		return
	var params := Params.new()
	params._force_member_source = rule_entry

	var objects := generate_view_objects(params)
	editor.current_view.transactions.add_object_views(objects)
	for object in objects:
		var members := editor.current_view.generate_object_member_list_with_rule(object.object_type, object.object, rule_entry)
		editor.current_view.transactions.add_object_view_members(members, object.object_type, object.object)


class Params extends RefCounted:
	@export var sub_paths: Array[String]
	@export var require_shown_members: bool = true

	var _force_member_source = null


	func get_property_description(property: StringName) -> String:
		match property:
			&"sub_paths":
				return "If non-empty, restricts the added nodes to only those\nwhose node path contains at least one of the substrings listed in this array.\nFor example, if sub_paths is [&\"Area\", &\"Zone\"], only nodes with \"Area\" or \"Zone\" in their path\n(either their name, or one of their ancestors' names) will be added.\nThis search is case-insensitive."
			&"require_shown_members":
				return "If checked, this rule will use rules under 'Member Sources'\nto determine whether a node should be added, requiring at least one member.\nIn other words, this excludes nodes which would otherwise show up empty\non the graph (i.e. with no connections or members)."
		return ""
