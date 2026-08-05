@tool
extends RefCounted

const MEMBER_TYPE_METHOD := "methods";
const MEMBER_TYPE_SIGNAL := "signals";

var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["view_rule.member_source"];

func get_view_rule_id() -> String:
	return "scene_signals:members_by_name";

func get_view_rule_label(params : Params) -> String:
	var label := "";
	if params && params.methods:
		label += "Methods: ";
		label += ", ".join(params.methods);
	if params && params.signals:
		if !label.is_empty():
			label += " | ";
		label += "Signals: ";
		label += ", ".join(params.signals);
	if label.is_empty():
		label = "(members by name)"
	return label;

func populate_view_object_members(object_type : String, obj : Object, params : Params) -> bool:
	var any_changes := false;
	
	for method_name in params.methods:
		if !obj.has_method(method_name): continue;
		if editor.view.add_object_view_member(object_type, obj, MEMBER_TYPE_METHOD, method_name):
			any_changes = true;
	for signal_name in params.signals:
		if !(obj.has_signal(signal_name) || obj.has_user_signal(signal_name)): continue;
		if editor.view.add_object_view_member(object_type, obj, MEMBER_TYPE_SIGNAL, signal_name):
			any_changes = true;
	return any_changes;

func create_view_rule_params() -> Object:
	return Params.new();

class Params extends RefCounted:
	@export var methods : Array[StringName];
	@export var signals : Array[StringName];