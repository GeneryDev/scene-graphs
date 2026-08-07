@tool
extends RefCounted

const OBJECT_TYPE_NODE := "node";


var editor : SignalGraphEditor;

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	
func get_signal_graph_capabilities() -> Array[String]:
	return ["view_rule.object_source"];

func get_view_rule_id() -> String:
	return "scene_signals:nodes_with_connections";

func get_view_rule_label(params : Params) -> String:
	if params == null:
		return "Nodes with connections";
	var label := "";
	if params && params.sub_paths:
		if params.require_connections:
			label += "Connected nodes with path: ";
		else:
			label += "Nodes with path: ";
		label += ", ".join(params.sub_paths);
	elif params.require_connections:
		label = "Nodes with connected methods/signals"
	else:
		label = "All Nodes"
	return label;

func generate_view_objects(params : Params) -> Array:
	var objects := [];
	_update_node_views_with_rules(editor.scene_root, params, objects);
	return objects;

func _update_node_views_with_rules(node : Node, params : Params, objects : Array) -> bool:
	if !node: return false;
	if !(node == editor.scene_root || node.owner == editor.scene_root): return false;
	
	var any_changes := _update_object_view_with_rules(node, params, objects);
	
	for child in node.get_children():
		if _update_node_views_with_rules(child, params, objects):
			any_changes = true;
	
	return any_changes;

func _update_object_view_with_rules(node : Node, params : Params, objects : Array) -> bool:
	if !node: return false;
	
	if _should_include_node(node, params):
		objects.append({
			"object_type": OBJECT_TYPE_NODE,
			"object": node
		});
		return true;
	else:
		return false;

func _should_include_node(node : Node, params : Params) -> bool:
	if !node: return false;
	
	if params.sub_paths:
		var has_subpath := false;
		var path := str(editor.scene_root.get_path_to(node)) if node != editor.scene_root else str(node.name);
		
		for subpath in params.sub_paths:
			if path.containsn(subpath):
				has_subpath = true;
				break;
		
		if !has_subpath: return false;
	
	if params.require_connections:
		var used_methods := SignalGraphEditor.Utility.get_connected_method_names(node);
		var used_signals := SignalGraphEditor.Utility.get_connected_signal_names(node);
		if !used_methods && !used_signals: return false;
	
	return true;

func create_view_rule_params() -> Object:
	return Params.new();

class Params extends RefCounted:
	@export var sub_paths : Array[String];
	@export var require_connections : bool = true;