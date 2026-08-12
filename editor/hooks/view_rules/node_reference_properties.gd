@tool
extends RefCounted

const MEMBER_TYPE_NODE_REFERENCE_OUT := "node_reference_out";
const MEMBER_TYPE_PROPERTY := "property";

var editor : SceneGraphEditor;

func _init(editor : SceneGraphEditor):
	self.editor = editor;
	
func get_scene_graph_capabilities() -> Array[String]:
	return ["view_rule.member_source"];

func get_view_rule_id() -> String:
	return "scene_graphs:node_reference_properties";

func get_view_rule_label(params : Variant) -> String:
	return "Node/NodePath properties";

func get_view_rule_description() -> String:
	return "Adds property members to each object in the graph, corresponding to properties of type NodePath, or Node-derived types.";

func generate_view_object_members(object_type : String, obj : Object, params : Variant) -> Array:
	var members := [];
	
	if obj is Node:
		var node_obj : Node = obj;
		for property in obj.get_property_list():
			var property_name : StringName = property.name;
			var referenced_node : Node = null;
			if property.type == TYPE_NODE_PATH:
				var path : NodePath = obj.get(property_name);
				if path.get_subname_count() > 0:
					continue;
				referenced_node = obj.get_node_or_null(path);
			elif property.type == TYPE_OBJECT && (property.hint & PROPERTY_HINT_NODE_TYPE) != 0:
				referenced_node = node_obj.get(property_name);
			else:
				continue;
			if referenced_node:
				members.append({
					"member_type": MEMBER_TYPE_PROPERTY,
					"member_name": property_name
				});
				members.append({
					"member_type": MEMBER_TYPE_NODE_REFERENCE_OUT,
					"member_name": &"",
					"object_type": object_type,
					"object": referenced_node
				});
	
	return members;
