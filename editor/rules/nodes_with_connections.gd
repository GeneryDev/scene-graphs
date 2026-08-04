@tool
extends RefCounted




var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["view_rule.object_source"];

func get_view_rule_id() -> String:
	return "scene_signals:nodes_with_connections";

func get_view_rule_label(params : Variant) -> String:
	return "(nodes with connected methods/signals)";

func populate_view_objects(params : Variant) -> bool:
	return _update_node_views_with_rules(editor.scene_root);

func _update_node_views_with_rules(node : Node) -> bool:
	if !(node == editor.scene_root || node.owner == editor.scene_root): return false;
	
	var any_changes := _update_object_view_with_rules(node);
	
	for child in node.get_children():
		if _update_node_views_with_rules(child):
			any_changes = true;
	
	return any_changes;

func _update_object_view_with_rules(obj : Object) -> bool:
	if !obj: return false;
	
	var used_methods := SignalGraphEditor.Utility.get_connected_method_names(obj);
	var used_signals := SignalGraphEditor.Utility.get_connected_signal_names(obj);
	
	if used_methods || used_signals:
		return editor.view.add_object_view(obj);
	elif false:
		return editor.view.remove_object_view(obj);
	else:
		return false;