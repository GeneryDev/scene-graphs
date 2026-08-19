@tool
extends RefCounted

const MEMBER_TYPE_METHOD := "method"
const MEMBER_TYPE_SIGNAL := "signal"

const SCRIPT_MEMBERS_OFF := 0
const SCRIPT_MEMBERS_INDIVIDUAL := 1
const SCRIPT_MEMBERS_REQUIRE_EITHER := 2
const SCRIPT_MEMBERS_REQUIRE_BOTH := 3
const SCRIPT_MEMBERS_REQUIRE_NEITHER := 4

var editor: SceneGraphEditor


func _get_connected_method_names(obj: Object, params : Params) -> Array:
	var script_methods := SceneGraphEditor.Utility.collect_members(obj, &"get_script_method_list", &"", &"").map(func(d): return d.name) if params.script_members_only != SCRIPT_MEMBERS_OFF else []
	
	var connected_methods: Array = []
	for connection in obj.get_incoming_connections():
		if (connection.flags & CONNECT_PERSIST) == 0:
			continue
		var method_name := connection.callable.get_method() as StringName
		var signal_name := connection.signal.get_name() as StringName
		match params.script_members_only:
			SCRIPT_MEMBERS_OFF:
				pass
			SCRIPT_MEMBERS_INDIVIDUAL:
				if !script_methods.has(method_name):
					continue
			SCRIPT_MEMBERS_REQUIRE_EITHER:
				if !script_methods.has(method_name):
					var other_script_signals := SceneGraphEditor.Utility.collect_members(connection.signal.get_object(), &"get_script_signal_list", &"", &"").map(func(d): return d.name)
					if !other_script_signals.has(signal_name):
						continue
			SCRIPT_MEMBERS_REQUIRE_BOTH:
				if !script_methods.has(method_name):
					continue
				var other_script_signals := SceneGraphEditor.Utility.collect_members(connection.signal.get_object(), &"get_script_signal_list", &"", &"").map(func(d): return d.name)
				if !other_script_signals.has(signal_name):
					continue
			SCRIPT_MEMBERS_REQUIRE_NEITHER:
				if script_methods.has(method_name):
					continue
				var other_script_signals := SceneGraphEditor.Utility.collect_members(connection.signal.get_object(), &"get_script_signal_list", &"", &"").map(func(d): return d.name)
				if other_script_signals.has(signal_name):
					continue
		if !connected_methods.has(method_name):
			connected_methods.append(method_name)

	# TODO I'd like the returned methods to be in a consistent order, preferably in the order returned by get_method_list.
	# However, that method appears to be super expensive, so I'd rather not use it in this function.

	return connected_methods


func _get_connected_signal_names(obj: Object, params : Params) -> Array:
	var script_signals := SceneGraphEditor.Utility.collect_members(obj, &"get_script_signal_list", &"", &"").map(func(d): return d.name) if params.script_members_only != SCRIPT_MEMBERS_OFF else []
	
	var list := []
	for signal_info in obj.get_signal_list():
		var signal_name := signal_info["name"] as StringName
		var used := false

		for connection in obj.get_signal_connection_list(signal_name):
			var flags := connection["flags"] as ConnectFlags
			if (flags & ConnectFlags.CONNECT_PERSIST) == 0:
				continue
			
			var method_name = connection.callable.get_method()
				
			match params.script_members_only:
				SCRIPT_MEMBERS_OFF:
					pass
				SCRIPT_MEMBERS_INDIVIDUAL:
					if !script_signals.has(signal_name):
						continue
				SCRIPT_MEMBERS_REQUIRE_EITHER:
					if !script_signals.has(signal_name):
						var other_script_methods := SceneGraphEditor.Utility.collect_members(connection.callable.get_object(), &"get_script_method_list", &"", &"").map(func(d): return d.name)
						if !other_script_methods.has(method_name):
							continue
				SCRIPT_MEMBERS_REQUIRE_BOTH:
					if !script_signals.has(signal_name):
						continue
					var other_script_methods := SceneGraphEditor.Utility.collect_members(connection.callable.get_object(), &"get_script_method_list", &"", &"").map(func(d): return d.name)
					if !other_script_methods.has(method_name):
						continue
				SCRIPT_MEMBERS_REQUIRE_NEITHER:
					if script_signals.has(signal_name):
						continue
					var other_script_methods := SceneGraphEditor.Utility.collect_members(connection.callable.get_object(), &"get_script_method_list", &"", &"").map(func(d): return d.name)
					if other_script_methods.has(method_name):
						continue
			used = true
			break

		if !used:
			continue

		list.append(signal_name)

	return list


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


func generate_view_object_members(object_type: String, obj: Object, params: Params) -> Array:
	var members := []

	var used_methods := _get_connected_method_names(obj, params)
	var used_signals := _get_connected_signal_names(obj, params)

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


func create_view_rule_params() -> Object:
	return Params.new()


class Params extends RefCounted:
	@export_enum("Off","Individual","Require Either","Require Both","Require Neither") var script_members_only: int = 0

	func get_property_description(property: StringName) -> String:
		match property:
			&"script_members_only":
				return "If set, limits added methods/signals based on whether they're script-defined.\nOff: Not limited to script members.\nIndividual: Only script-defined methods and signals are added. Connections to non-script members are not shown.\nRequire Either: Either the member or signal must be script-defined for both to be added.\nRequire Both: Both the connected member and signal must be script-defined for both to be added.\nRequire Neither: Both the connected member and signal must NOT be script-defined for both to be added."
		return ""
