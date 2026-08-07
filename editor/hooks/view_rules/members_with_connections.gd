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

func generate_view_object_members(object_type : String, obj : Object, params : Variant) -> Array:
	var members := [];
	
	var used_methods := get_connected_method_names(obj);
	var used_signals := get_connected_signal_names(obj);
	
	for method_name in used_methods:
		members.append({
			"member_type": MEMBER_TYPE_METHOD,
			"member_name": method_name
		});
	for signal_name in used_signals:
		members.append({
			"member_type": MEMBER_TYPE_SIGNAL,
			"member_name": signal_name
		});
	
	return members;

static func get_connected_method_names(obj : Object) -> Array:
	var list := [];
	
	var connected_methods : Array[StringName] = [];
	for connection in obj.get_incoming_connections():
		if(connection.flags & CONNECT_PERSIST) == 0: continue;
		var method_name := connection.callable.get_method() as StringName; 
		if !connected_methods.has(method_name):
			connected_methods.push_back(method_name);
	
	# doing two passes because we want the returned list to be in a consistent order (by method definition)
	# rather than the order of connections :(
	
	for method_info in obj.get_method_list():
		var method_name := method_info["name"] as StringName;
		if list.has(method_name): continue;
		var used := connected_methods.has(method_name);
		
		if used: list.append(method_name);
	
	return list;

static func get_connected_signal_names(obj : Object) -> Array:
	var list := [];
	for signal_info in obj.get_signal_list():
		var signal_name := signal_info["name"] as StringName;
		var used := false;
		
		for connection in obj.get_signal_connection_list(signal_name):
			var flags := connection["flags"] as ConnectFlags;
			if (flags & ConnectFlags.CONNECT_PERSIST) != 0:
				used = true;
				break;
		
		if !used: continue;
		
		list.append(signal_name);
	
	return list;