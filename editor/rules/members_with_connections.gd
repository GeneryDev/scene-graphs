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
	return "scene_signals:members_with_connections";

func get_view_rule_label(params : Variant) -> String:
	return "Connected methods/signals";

func populate_view_object_members(object_type : String, obj : Object, params : Variant) -> bool:
	var any_changes := false;
	
	var used_methods := SignalGraphEditor.Utility.get_connected_method_names(obj);
	var used_signals := SignalGraphEditor.Utility.get_connected_signal_names(obj);
	
	for method_name in used_methods:
		if editor.view.add_object_view_member(object_type, obj, MEMBER_TYPE_METHOD, method_name):
			any_changes = true;
	for signal_name in used_signals:
		if editor.view.add_object_view_member(object_type, obj, MEMBER_TYPE_SIGNAL, signal_name):
			any_changes = true;
	return any_changes;
