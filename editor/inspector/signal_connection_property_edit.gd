extends Resource
@export var info : String = "";

const MEMBER_TYPE_METHOD := "method";
const MEMBER_TYPE_SIGNAL := "signal";

var _deferred : Variant;
var _one_shot : Variant;
var _append_source : Variant;
var _unbind_signal_arguments : Variant;
var _bound_signal_arguments : Variant;

var editor : SceneGraphEditor;
var object_connection_pairs : Array[ObjectConnectionPair] = [];
var setup_complete := false;

var multiple : bool:
	get: return object_connection_pairs.size() > 1;

func setup(editor : SceneGraphEditor, graph_connections : Array) -> void:
	self.editor = editor;
	var is_first_entry := true;
	for graph_connection in graph_connections:
		var from_graph_node := editor.get_node(NodePath(graph_connection.from_node));
		var to_graph_node := editor.get_node(NodePath(graph_connection.to_node));
		
		var from_object : Object = from_graph_node.get_object();
		var to_object : Object = to_graph_node.get_object();
		var signal_name : StringName = from_graph_node.get_member_from_port_id_and_type(graph_connection.from_port, MEMBER_TYPE_SIGNAL).member_name;
		var method_name : StringName = to_graph_node.get_member_from_port_id_and_type(graph_connection.to_port, MEMBER_TYPE_METHOD).member_name;
		
		var signal_connection : Dictionary;
		var flags : ConnectFlags;
		for signal_connection_candidate in from_object.get_signal_connection_list(signal_name):
			if !signal_connection_candidate.callable.is_valid(): continue;
			if (signal_connection_candidate.flags & CONNECT_PERSIST) == 0: continue;
			if signal_connection_candidate.callable.get_method() == method_name:
				signal_connection = signal_connection_candidate;
		
		var callable := Callable(to_object, method_name);
		var signal_info : Signal = Signal(from_object, signal_name);
		
		if !signal_connection:
			printerr("Couldn't find existing connection");
			flags = CONNECT_PERSIST;
		else:
			flags = signal_connection.flags;
			callable = signal_connection.callable;
			signal_info = signal_connection.signal;
		
		var entry_deferred := flags & CONNECT_DEFERRED != 0;
		var entry_one_shot := flags & CONNECT_ONE_SHOT != 0;
		var entry_append_source := flags & CONNECT_APPEND_SOURCE_OBJECT != 0;
	
		var entry_unbind_signal_arguments := callable.get_unbound_arguments_count();
		var entry_bound_signal_arguments := callable.get_bound_arguments();
		
		if is_first_entry:
			_deferred = entry_deferred;
			_one_shot = entry_one_shot;
			_append_source = entry_append_source;
			_unbind_signal_arguments = entry_unbind_signal_arguments;
			_bound_signal_arguments = entry_bound_signal_arguments;
		else:
			if _deferred != entry_deferred:
				_deferred = null;
			if _one_shot != entry_one_shot:
				_one_shot = null;
			if _append_source != entry_append_source:
				_append_source = null;
			if _unbind_signal_arguments != entry_unbind_signal_arguments:
				_unbind_signal_arguments = null;
			if _bound_signal_arguments != entry_bound_signal_arguments:
				_bound_signal_arguments = null;
		
		var pair := ObjectConnectionPair.new();
		pair.from_object = from_object;
		pair.to_object = to_object;
		pair.signal_name = signal_name;
		pair.method_name = method_name;
		pair.original_flags = flags;
		pair.original_callable = callable;
		object_connection_pairs.append(pair);
		
		info = "" + str(signal_name) + " -> " + str(callable.get_method());
		
		is_first_entry = false;
		
	if multiple:
		info = "(" + str(object_connection_pairs.size()) + " connections)";
		
	setup_complete = true;
	
func _on_property_updated(property_name : StringName) -> void:
	if !setup_complete: return;
	update_object_connections();

func update_object_connections() -> void:
	for pair in object_connection_pairs:
		update_object_connection(pair);
	if is_instance_valid(editor):
		editor.notify_connections_changed();

func update_object_connection(pair : ObjectConnectionPair) -> void:
	if !is_instance_valid(pair.from_object) || !is_instance_valid(pair.to_object):
		printerr("Cannot update signal connection properties on freed objects.");
		return;
		
	var old_signal_connection : Dictionary;
	
	for old_signal_connection_candidate in pair.from_object.get_signal_connection_list(pair.signal_name):
		if !old_signal_connection_candidate.callable.is_valid(): continue;
		if (old_signal_connection_candidate.flags & CONNECT_PERSIST) == 0: continue;
		if old_signal_connection_candidate.callable.get_method() == pair.method_name:
			old_signal_connection = old_signal_connection_candidate;
			
	if old_signal_connection:
		pair.from_object.disconnect(pair.signal_name, old_signal_connection.callable);
	else:
		printerr("Couldn't find existing connection, re-connecting anyway");
		
	var new_flags : ConnectFlags = pair.original_flags;
	if _deferred != null:
		if _deferred: new_flags |= CONNECT_DEFERRED;
		else: new_flags &= ~CONNECT_DEFERRED;
	if _one_shot != null:
		if _one_shot: new_flags |= CONNECT_ONE_SHOT;
		else: new_flags &= ~CONNECT_ONE_SHOT;
	if _append_source != null:
		if _append_source: new_flags |= CONNECT_APPEND_SOURCE_OBJECT;
		else: new_flags &= ~CONNECT_APPEND_SOURCE_OBJECT;
	
	var new_callable : Callable = Callable(pair.to_object, pair.method_name);
	if _bound_signal_arguments != null || _unbind_signal_arguments != null:
		if _bound_signal_arguments:
			new_callable = new_callable.bindv(_bound_signal_arguments);
		if _unbind_signal_arguments != null && _unbind_signal_arguments > 0:
			new_callable = new_callable.unbind(_unbind_signal_arguments);
	else:
		new_callable = pair.original_callable;
	
	pair.from_object.connect(pair.signal_name, new_callable, new_flags);

func _validate_property(property: Dictionary) -> void:
	var prop_name := property["name"] as StringName;
	match prop_name:
		&"info":
			property["usage"] = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_INTERNAL | PROPERTY_USAGE_READ_ONLY;
		&"resource_local_to_scene":
			property["usage"] &= ~PROPERTY_USAGE_EDITOR;
		&"resource_path":
			property["usage"] &= ~PROPERTY_USAGE_EDITOR;
		&"resource_name":
			property["usage"] &= ~PROPERTY_USAGE_EDITOR;
		&"script":
			property["usage"] &= ~PROPERTY_USAGE_EDITOR;
	pass;
	
func _get_property_list() -> Array[Dictionary]:
	return [
		{
			"name": &"deferred",
			"type": TYPE_BOOL,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_INTERNAL | (PROPERTY_USAGE_CHECKABLE if multiple else 0),
		},
		{
			"name": &"one_shot",
			"type": TYPE_BOOL,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_INTERNAL | (PROPERTY_USAGE_CHECKABLE if multiple else 0),
		},
		{
			"name": &"append_source",
			"type": TYPE_BOOL,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_INTERNAL | (PROPERTY_USAGE_CHECKABLE if multiple else 0),
		},
		{
			"name": &"unbind_signal_arguments",
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "0,16,1",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_INTERNAL | (PROPERTY_USAGE_CHECKABLE if multiple else 0),
		},
		{
			"name": &"bound_signal_arguments",
			"type": TYPE_ARRAY,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": "",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_INTERNAL | (PROPERTY_USAGE_CHECKABLE if multiple else 0),
		}
	];

func _get(property: StringName) -> Variant:
	match property:
		&"deferred": return _deferred;
		&"one_shot": return _one_shot;
		&"append_source": return _append_source;
		&"unbind_signal_arguments": return _unbind_signal_arguments;
		&"bound_signal_arguments": return _bound_signal_arguments;
	return null;

func _set(property: StringName, value : Variant) -> bool:
	match property:
		&"deferred": 
			_deferred = value;
			_on_property_updated(&"deferred");
			return true;
		&"one_shot": 
			_one_shot = value;
			_on_property_updated(&"one_shot");
			return true;
		&"append_source": 
			_append_source = value;
			_on_property_updated(&"append_source");
			return true;
		&"unbind_signal_arguments": 
			_unbind_signal_arguments = value;
			_on_property_updated(&"unbind_signal_arguments");
			return true;
		&"bound_signal_arguments": 
			_bound_signal_arguments = value;
			_on_property_updated(&"bound_signal_arguments");
			return true;
	return false;
	
class ObjectConnectionPair extends RefCounted:
	var from_object : Object;
	var to_object : Object;
	var signal_name : StringName;
	var method_name : StringName;
	
	var original_flags : ConnectFlags;
	var original_callable : Callable;