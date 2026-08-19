@tool
extends RefCounted

const OBJECT_TYPE_NODE := "node"
const MEMBER_TYPE_PROPERTY := "property"
const ICON_NAME_PROPERTY := &"MemberProperty"
const META_NAME_EXTENSION := &"_property_inspectors_extension"

static var SceneObjectGraphNode: Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd")

var editor: SceneGraphEditor


func _init(editor: SceneGraphEditor):
	self.editor = editor


func get_scene_graph_capabilities() -> Array[String]:
	return ["initialize_object_graph_node", "configure_hook_options", "create_object_graph_node_slots", "configure_member_selector", "claim_object_graph_node_member_slots"]


### CAPABILITY: configure_hook_options
func get_hook_options_id() -> String:
	return "scene_graphs:property_inspectors"


func get_hook_options_label(options: Options) -> String:
	if options == null:
		return "Property Inspectors"
	return "Property Inspectors: %s" % ["Enabled" if options.enable_property_inspectors else "Disabled"]


func create_hook_options() -> Options:
	return Options.new()


func get_hook_description() -> String:
	return "Sets up inspectors for selected object properties within the graph itself.\nNote: objects must have property members visible in the view, added either by a Member Source view rule, or manually."


# CAPABILITY: configure_member_selector
func get_member_selector_member_types() -> Array[String]:
	return [MEMBER_TYPE_PROPERTY]


func get_member_selector_tab_info(member_type: String) -> Dictionary:
	match member_type:
		MEMBER_TYPE_PROPERTY:
			return {
				"label": "Properties",
				"icon": EditorInterface.get_editor_theme().get_icon(ICON_NAME_PROPERTY, &"EditorIcons"),
			}
	return { }


func get_member_selector_member_list(object_type: String, obj: Object, member_type: String) -> Array[Dictionary]:
	var members: Array = []
	match member_type:
		MEMBER_TYPE_PROPERTY:
			members.append_array(SceneGraphEditor.Utility.collect_members(obj, &"get_script_property_list", &"class_get_property_list", &"get_property_list"))
			members = members.filter(_filter_properties_usable)
			members = members.map(
				func(property_info: Dictionary) -> Dictionary:
					return {
						"member_type": MEMBER_TYPE_PROPERTY,
						"member_name": property_info.name,
						"label": property_info.name,
						"icon": EditorInterface.get_editor_theme().get_icon(type_string(property_info.type), &"EditorIcons"),
					}
			)

	return members


func is_enabled() -> bool:
	return editor.current_view.get_hook_options(self).enable_property_inspectors


# CAPABILITY: initialize_object_graph_node
func initialize_object_graph_node(graph_node: GraphNode) -> void:
	graph_node.set_meta(META_NAME_EXTENSION, SceneObjectGraphNodeExtension.new(graph_node, editor, self))


# CAPABILITY: create_object_graph_node_slots
func create_object_graph_node_slots(graph_node: GraphNode) -> Array[Dictionary]:
	if !is_enabled():
		return []
	return (graph_node.get_meta(META_NAME_EXTENSION) as SceneObjectGraphNodeExtension).create_object_graph_node_slots()


### CAPABILITY: claim_object_graph_node_member_slots
func get_object_graph_node_member_slot_bid(object_type: String, object: Object, member_type: String, member_name: StringName) -> float:
	if !is_enabled():
		return 0
	if member_type == MEMBER_TYPE_PROPERTY:
		return 1
	return 0


func _filter_properties_usable(property: Dictionary) -> bool:
	if (property.usage & PROPERTY_USAGE_EDITOR) == 0:
		return false
	if (property.usage & PROPERTY_USAGE_GROUP) != 0:
		return false
	if (property.usage & PROPERTY_USAGE_CATEGORY) != 0:
		return false
	if (property.usage & PROPERTY_USAGE_SUBGROUP) != 0:
		return false
	return true


class SceneObjectGraphNodeExtension extends RefCounted:
	var graph_node: GraphNode
	var editor: SceneGraphEditor
	var hook: Object


	func _init(graph_node: GraphNode, editor: SceneGraphEditor, hook: Object) -> void:
		self.graph_node = graph_node
		self.editor = editor
		self.hook = hook


	func create_object_graph_node_slots() -> Array[Dictionary]:
		var created: Array[Dictionary] = []
		if graph_node.object_type != OBJECT_TYPE_NODE:
			return created

		var property_slots := create_property_slots()
		created.append_array(property_slots)

		return created


	static func get_property_info_by_name(obj: Object, property_name: StringName) -> Dictionary:
		for property_info in obj.get_property_list():
			if property_info["name"] != property_name:
				continue
			return property_info
		return { }


	func create_property_slots() -> Array[Dictionary]:
		var created: Array[Dictionary] = []
		var obj: Object = graph_node.get_object()
		for property_name in editor.current_view.get_object_view_members(graph_node.object_type, obj, MEMBER_TYPE_PROPERTY):
			if !graph_node.claim_object_graph_node_member_slot(hook, MEMBER_TYPE_PROPERTY, property_name):
				continue
			var property_info := get_property_info_by_name(obj, property_name)
			if !property_info:
				print("No property found for name '" + property_name + "' in object " + str(obj))
				continue

			var row_control := _create_inspector_field(obj, property_info)
			row_control.tooltip_text = "Property: " + property_name + ": " + type_string(property_info.type)

			created.append(
				{
					"control": row_control,
					"sort_key": 0,
					"member": {
						"member_type": MEMBER_TYPE_PROPERTY,
						"member_name": property_name,
					},
				},
			)
		return created


	func _create_inspector_field(obj: Object, property: Dictionary) -> Control:
		var container := VBoxContainer.new()
		container.add_theme_constant_override(&"separation", 0)
		container.custom_minimum_size = Vector2(200, 20)

		var label := Label.new()
		label.text = property.name.capitalize()
		container.add_child(label)

		var property_container := MarginContainer.new()
		property_container.add_theme_constant_override(&"margin_left", 16)
		property_container.add_theme_constant_override(&"margin_right", 16)
		property_container.add_theme_constant_override(&"margin_top", 0)
		property_container.add_theme_constant_override(&"margin_bottom", 0)
		container.add_child(property_container)

		var property_editor := EditorInspector.instantiate_property_editor(obj, property.type, "", property.hint, property.hint_string, property.usage)
		property_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		property_editor.draw_label = false
		property_editor.set_object_and_property(obj, property.name)
		property_editor.selectable = false
		property_editor.update_property()
		property_container.add_child(property_editor)
		property_editor.property_changed.connect(_on_property_changed.bind(obj))
		if (property.usage & PROPERTY_USAGE_ARRAY):
			property_editor.property_changed.connect(
				func(_property: StringName, _value: Variant, _field: StringName, _changing: bool) -> void:
					property_editor.update_property()
			)
		if property.hint == PROPERTY_HINT_MULTILINE_TEXT:
			property_container.add_theme_constant_override(&"margin_top", -28)

		var padding := Control.new()
		padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
		padding.custom_minimum_size = Vector2(0, 8)
		container.add_child(padding)

		return container


	func _on_property_changed(property: StringName, value: Variant, field: StringName, changing: bool, obj: Object) -> void:
		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Set " + property, UndoRedo.MERGE_ALL, obj, true)
		undo_redo.add_do_property(obj, property, value)
		undo_redo.add_undo_property(obj, property, obj.get(property))
		undo_redo.commit_action(true)


	func _create_icon_control(icon_name: String, height: int) -> Control:
		if icon_name:
			var texture_rect := TextureRect.new()
			texture_rect.texture = EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons")
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return texture_rect
		else:
			var control := Control.new()
			control.custom_minimum_size = Vector2(height, height)
			return control


class Options extends RefCounted:
	@export var enable_property_inspectors: bool = true
