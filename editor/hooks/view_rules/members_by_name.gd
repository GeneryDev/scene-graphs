@tool
extends RefCounted

const MEMBER_TYPE_PROPERTY := "properties";
const MEMBER_TYPE_METHOD := "methods";
const MEMBER_TYPE_SIGNAL := "signals";

var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["view_rule.member_source"];

func get_view_rule_id() -> String:
	return "signal_graphs:members_by_name";

func get_view_rule_label(params : Params) -> String:
	var label := "";
	if params && params.properties:
		if !label.is_empty():
			label += " | ";
		label += "Properties: ";
		label += ", ".join(params.properties);
	if params && params.methods:
		if !label.is_empty():
			label += " | ";
		label += "Methods: ";
		label += ", ".join(params.methods);
	if params && params.signals:
		if !label.is_empty():
			label += " | ";
		label += "Signals: ";
		label += ", ".join(params.signals);
	if label.is_empty():
		label = "Members by name"
	return label;

func generate_view_object_members(object_type : String, obj : Object, params : Params) -> Array:
	var members := [];
	
	for property_name in params.properties:
		if !(property_name in obj): continue;
		for property in obj.get_property_list():
			if (property.usage & PROPERTY_USAGE_EDITOR) == 0: continue;
			if (property.usage & PROPERTY_USAGE_GROUP) != 0: continue;
			if (property.usage & PROPERTY_USAGE_CATEGORY) != 0: continue;
			if (property.usage & PROPERTY_USAGE_SUBGROUP) != 0: continue;
			if property.name == property_name:
				members.append({
					"member_type": MEMBER_TYPE_PROPERTY,
					"member_name": property_name
				});
	for method_name in params.methods:
		if !obj.has_method(method_name): continue;
		members.append({
			"member_type": MEMBER_TYPE_METHOD,
			"member_name": method_name
		});
	for signal_name in params.signals:
		if !(obj.has_signal(signal_name) || obj.has_user_signal(signal_name)): continue;
		members.append({
			"member_type": MEMBER_TYPE_SIGNAL,
			"member_name": signal_name
		});
	
	return members;

func create_view_rule_params() -> Object:
	return Params.new();

func get_view_rule_description() -> String:
	return "Adds members to each object in the graph by name.";

class Params extends RefCounted:
	@export var properties : Array[StringName];
	@export var methods : Array[StringName];
	@export var signals : Array[StringName];
	
	func get_property_description(property : StringName) -> String:
		match property:
			&"properties":
				return "A list of properties that will automatically get added,\nif they exist on the target object.\nMust match the exact name they were defined with.";
			&"methods":
				return "A list of methods that will automatically get added,\nif they exist on the target object.\nMust match the exact name they were defined with.";
			&"signals":
				return "A list of signals that will automatically get added,\nif they exist on the target object.\nMust match the exact name they were defined with.";
		return "";