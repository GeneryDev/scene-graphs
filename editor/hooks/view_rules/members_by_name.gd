@tool
extends RefCounted

const MEMBER_TYPE_PROPERTY := "property"
const MEMBER_TYPE_METHOD := "method"
const MEMBER_TYPE_SIGNAL := "signal"

var editor: SceneGraphEditor


func _init(editor: SceneGraphEditor):
	self.editor = editor


func get_scene_graph_capabilities() -> Array[String]:
	return ["view_rule.member_source"]


func get_view_rule_id() -> String:
	return "scene_graphs:members_by_name"


func get_view_rule_label(params: Params) -> String:
	var label := ""
	if params && params.properties:
		if !label.is_empty():
			label += " | "
		label += "Properties: "
		label += ", ".join(params.properties)
	if params && params.methods:
		if !label.is_empty():
			label += " | "
		label += "Methods: "
		label += ", ".join(params.methods)
	if params && params.signals:
		if !label.is_empty():
			label += " | "
		label += "Signals: "
		label += ", ".join(params.signals)
	if label.is_empty():
		label = "Members by name"
	return label


func generate_view_object_members(object_type: String, obj: Object, params: Params) -> Array:
	var members := []

	var script_properties := SceneGraphEditor.Utility.collect_members(obj, &"get_script_property_list", &"", &"").map(func(d): return d.name) if params.script_members_only && !params.properties.is_empty() else []
	for property_name in params.properties:
		if !(property_name in obj):
			continue
		if params.script_members_only && !script_properties.has(property_name):
			continue
		for property in obj.get_property_list():
			if (property.usage & PROPERTY_USAGE_EDITOR) == 0:
				continue
			if (property.usage & PROPERTY_USAGE_GROUP) != 0:
				continue
			if (property.usage & PROPERTY_USAGE_CATEGORY) != 0:
				continue
			if (property.usage & PROPERTY_USAGE_SUBGROUP) != 0:
				continue
			if property.name == property_name:
				members.append(
					{
						"member_type": MEMBER_TYPE_PROPERTY,
						"member_name": property_name,
					},
				)

	var script_methods := SceneGraphEditor.Utility.collect_members(obj, &"get_script_method_list", &"", &"").map(func(d): return d.name) if params.script_members_only && !params.methods.is_empty() else []
	for method_name in params.methods:
		if !obj.has_method(method_name):
			continue
		if params.script_members_only && !script_methods.has(method_name):
			continue
		members.append(
			{
				"member_type": MEMBER_TYPE_METHOD,
				"member_name": method_name,
			},
		)

	var script_signals := SceneGraphEditor.Utility.collect_members(obj, &"get_script_signal_list", &"", &"").map(func(d): return d.name) if params.script_members_only && !params.signals.is_empty() else []
	for signal_name in params.signals:
		if !(obj.has_signal(signal_name) || obj.has_user_signal(signal_name)):
			continue
		if params.script_members_only && !script_signals.has(signal_name):
			continue
		members.append(
			{
				"member_type": MEMBER_TYPE_SIGNAL,
				"member_name": signal_name,
			},
		)

	return members


func create_view_rule_params() -> Object:
	return Params.new()


func get_view_rule_description() -> String:
	return "Adds members to each object in the graph by name."


class Params extends RefCounted:
	@export var properties: Array[StringName]
	@export var methods: Array[StringName]
	@export var signals: Array[StringName]

	@export var script_members_only: bool = false

	func get_property_description(property: StringName) -> String:
		match property:
			&"properties":
				return "A list of properties that will automatically get added,\nif they exist on the target object.\nMust match the exact name they were defined with."
			&"methods":
				return "A list of methods that will automatically get added,\nif they exist on the target object.\nMust match the exact name they were defined with."
			&"signals":
				return "A list of signals that will automatically get added,\nif they exist on the target object.\nMust match the exact name they were defined with."
			&"script_members_only":
				return "If set, only script-defined members will be added. Otherwise, all applicable members, including from the base class, will be added."
		return ""
