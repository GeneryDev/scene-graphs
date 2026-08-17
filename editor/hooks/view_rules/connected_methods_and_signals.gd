@tool
extends RefCounted

const MEMBER_TYPE_METHOD := "method"
const MEMBER_TYPE_SIGNAL := "signal"

var editor: SceneGraphEditor


func _init(editor: SceneGraphEditor):
	self.editor = editor


func get_scene_graph_capabilities() -> Array[String]:
	return ["view_rule.member_source"]


func get_view_rule_id() -> String:
	return "scene_graphs:connected_methods_and_signals"


func get_view_rule_label(params: Variant) -> String:
	return "Connected methods/signals"


func get_view_rule_description() -> String:
	return "Adds method and signal members to each object in the graph, corresponding to existing signal-method connections."


func generate_view_object_members(object_type: String, obj: Object, params: Variant) -> Array:
	var members := []

	var used_methods := get_connected_method_names(obj)
	var used_signals := get_connected_signal_names(obj)

	for method_name in used_methods:
		members.append(
			{
				"member_type": MEMBER_TYPE_METHOD,
				"member_name": method_name,
			},
		)
	for signal_name in used_signals:
		members.append(
			{
				"member_type": MEMBER_TYPE_SIGNAL,
				"member_name": signal_name,
			},
		)

	return members


static func get_connected_method_names(obj: Object) -> Array:
	var connected_methods: Array = []
	for connection in obj.get_incoming_connections():
		if (connection.flags & CONNECT_PERSIST) == 0:
			continue
		var method_name := connection.callable.get_method() as StringName
		if !connected_methods.has(method_name):
			connected_methods.append(method_name)

	# TODO I'd like the returned methods to be in a consistent order, preferably in the order returned by get_method_list.
	# However, that method appears to be super expensive, so I'd rather not use it in this function.

	return connected_methods


static func get_connected_signal_names(obj: Object) -> Array:
	var list := []
	for signal_info in obj.get_signal_list():
		var signal_name := signal_info["name"] as StringName
		var used := false

		for connection in obj.get_signal_connection_list(signal_name):
			var flags := connection["flags"] as ConnectFlags
			if (flags & ConnectFlags.CONNECT_PERSIST) != 0:
				used = true
				break

		if !used:
			continue

		list.append(signal_name)

	return list
