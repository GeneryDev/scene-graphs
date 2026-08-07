class_name SignalGraphView 
extends RefCounted

signal view_updated();

var editor : SignalGraphEditor;
var transactions : Transactions;

var view_rules : Dictionary = {};
var scene_data : Dictionary = {};
var scene_objects : Dictionary = {};

#var view_data : Dictionary = {
#	"view_rules": {
#		"object_source": [
#			{
#				"id": "scene_signals:nodes_with_connections",
#				"params": {}
#			}
#		],
#		"member_source": [
#			{
#				"id": "scene_signals:members_with_connections",
#				"params": {}
#			}
#		]
#	},
#	"scene_data": {
#		"objects": {}
#	}
#};

func _init(editor : SignalGraphEditor):
	self.editor = editor;
	transactions = Transactions.new(editor, self);

func notify_view_updated() -> void:
	view_updated.emit();

func get_all_scene_object_views() -> Dictionary:
	var all_scene_object_views : Dictionary = scene_objects;
	return all_scene_object_views;

func get_scene_object_views(object_type : String) -> Dictionary:
	return get_all_scene_object_views().get_or_add(object_type, {});
	
func add_object_view(object_type : String, obj : Object) -> bool:
	if !obj: return false;
	var runtime_key = view_object_to_runtime_key(object_type, obj);
	if runtime_key == null: return false;
	var scene_object_views := get_scene_object_views(object_type);
	if scene_object_views.has(runtime_key):
		# already added
		return false;
	var obj_view := {
		"members": {}
	};
	scene_object_views[runtime_key] = obj_view;
	return true;
	
func set_object_view(object_type : String, obj : Object, obj_view : Dictionary) -> bool:
	if !obj: return false;
	var runtime_key = view_object_to_runtime_key(object_type, obj);
	if runtime_key == null: return false;
	var scene_object_views := get_scene_object_views(object_type);
	scene_object_views[runtime_key] = obj_view;
	return true;
	
func get_object_view(object_type : String, obj : Object) -> Dictionary:
	if !obj: return {};
	var runtime_key = view_object_to_runtime_key(object_type, obj);
	if runtime_key == null: return {};
	var scene_object_views := get_scene_object_views(object_type);
	if !scene_object_views.has(runtime_key): return {};
	return scene_object_views[runtime_key];
	
func has_object_view(object_type : String, obj : Object) -> bool:
	if get_object_view(object_type, obj):
		return true;
	return false;
	
func remove_object_view(object_type : String, obj : Object) -> bool:
	if !obj: return false;
	var runtime_key = view_object_to_runtime_key(object_type, obj);
	if runtime_key == null: return false;
	var scene_object_views := get_scene_object_views(object_type);
	if !scene_object_views.has(runtime_key): return false;
	var removed = scene_object_views[runtime_key];
	scene_object_views.erase(runtime_key);
	return true;

func add_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> bool:
	var obj_view := get_object_view(object_type, obj);
	if !obj_view:
		printerr("Failed to add object view member; no object view for " + object_type + " " + str(obj));
		return false;
	var list : Array = obj_view.members[member_type] if obj_view.members.has(member_type) else [];
	obj_view.members[member_type] = list;
	if list.has(member_name): return false;
	list.append(member_name);
	return true;
	
func has_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> bool:
	var obj_view := get_object_view(object_type, obj);
	if !obj_view:
		return false;
	return get_object_view_members(object_type, obj, member_type).has(member_name);

func get_object_view_members(object_type : String, obj : Object, member_type : String) -> Array:
	var obj_view := get_object_view(object_type, obj);
	if !obj_view:
		printerr("Failed to get object view members; no object view for " + object_type + " " + str(obj));
		return [];
	var list : Array = obj_view.members[member_type] if obj_view.members.has(member_type) else [];
	obj_view.members[member_type] = list;
	return list;

func remove_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> bool:
	var obj_view := get_object_view(object_type, obj);
	if !obj_view:
		printerr("Failed to remove object view member; no object view for " + object_type + " " + str(obj));
		return false;
	var list : Array = get_object_view_members(object_type, obj, member_type);
	if !list.has(member_name): return false;
	list.remove_at(list.find(member_name));
	return true;

func clear_all_objects() -> void:
	scene_objects = {};

func clear_objects(object_type : String) -> void:
	scene_objects[object_type] = {};
	
func _print_unsupported_object_type(object_type : String) -> void:
	printerr("Graph view object type '" + object_type + "' is not supported by any of the active signal graph editor hooks. Some data may be lost.");

func view_object_to_runtime_key(object_type : String, obj : Object) -> Variant:
	if !obj: return null;
	for hook in editor.hooks.view_object_serialization:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.view_object_to_runtime_key(object_type, obj);
	
	_print_unsupported_object_type(object_type);
	return null;

func runtime_key_to_view_object(object_type : String, key : Variant) -> Object:
	if key == null: return null;
	for hook in editor.hooks.view_object_serialization:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.runtime_key_to_view_object(object_type, key);
	
	_print_unsupported_object_type(object_type);
	return null;

func runtime_key_serialize(object_type : String, key : Variant) -> Variant:
	if key == null: return null;
	for hook in editor.hooks.view_object_serialization:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.runtime_key_serialize(object_type, key);
	
	_print_unsupported_object_type(object_type);
	return null;

func runtime_key_deserialize(object_type : String, serialized : Variant) -> Variant:
	if serialized == null: return null;
	for hook in editor.hooks.view_object_serialization:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.runtime_key_deserialize(object_type, serialized);
	
	_print_unsupported_object_type(object_type);
	return null;

func instantiate_graph_node_for_object(object_type : String, obj : Object, graph_node_script : Script) -> GraphNode:
	if !obj: return null;
	var graph_node : GraphNode = graph_node_script.new(object_type, obj, editor);
	graph_node.name = _object_to_graph_node_name(object_type, obj);
	return graph_node;

func _object_to_graph_node_name(object_type : String, obj : Object) -> StringName:
	if !obj: return &"";
	var runtime_key = view_object_to_runtime_key(object_type, obj);
	if !runtime_key: return &"";
	var node_name := StringName(object_type + "_" + str(runtime_key));
	return node_name;

func get_graph_node_for_object(object_type : String, obj : Object) -> GraphNode:
	return editor.get_node_or_null(NodePath(_object_to_graph_node_name(object_type, obj))) as GraphNode;

func select_object(object_type : String, obj : Object) -> void:
	if editor.current_view != self: return;
	var existing_graph_node : GraphNode = get_graph_node_for_object(object_type, obj);
	if existing_graph_node:
		existing_graph_node.set_selected(true);
	
func get_view_rule_hooks(type : String) -> Array[Object]:
	return editor.hooks.get("view_rule." + type);
	
func get_view_rule_hook(id : String, type : String) -> Object:
	for hook in get_view_rule_hooks(type):
		if hook.get_view_rule_id() == id:
			return hook;
	
	printerr("Invalid view rule id '" + id + "'");
	return null;

func rule_params_from_dict(hook : Object, raw_params : Dictionary) -> Variant:
	if !hook.has_method(&"create_view_rule_params"): return null;
	var params : Object = hook.create_view_rule_params();
	
	for key in raw_params:
		var raw_value = raw_params[key];
		var default_value = params.get(key);
		if default_value == null: continue;
		if default_value is Array:
			default_value.assign(raw_value);
		elif default_value is Dictionary:
			default_value.assign(raw_value);
		else:
			params.set(key, raw_value);
	return params;

func rule_params_to_dict(hook : Object, params : Variant) -> Dictionary:
	if !params: return {};
	var raw_params : Dictionary = {};
	for property in params.get_property_list():
		if property.name == &"script": continue;
		var value = params.get(property.name);
		if value == null: continue;
		raw_params[property.name] = value;
	return raw_params;

func get_view_rules_of_type(rule_type : String) -> Array:
	return view_rules.get_or_add(rule_type, {});

func update_object_views_with_rules() -> void:
	for rule_entry in get_view_rules_of_type("object_source"):
		var id : String = rule_entry.id;
		var raw_params : Dictionary = rule_entry.get("params");
		var rule_hook := get_view_rule_hook(id, "object_source");
		if !rule_hook: continue;
		rule_hook.populate_view_objects(rule_params_from_dict(rule_hook, raw_params));

func update_object_member_views_with_rules(object_type : String, obj : Object) -> void:
	for rule_entry in get_view_rules_of_type("member_source"):
		var id : String = rule_entry.id;
		var raw_params : Dictionary = rule_entry.get("params");
		var rule_hook := get_view_rule_hook(id, "member_source");
		if !rule_hook: continue;
		rule_hook.populate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params));

func update_all_object_member_views_with_rules() -> void:
	for object_type in get_all_scene_object_views():
		var object_views : Dictionary = get_scene_object_views(object_type);
		
		for rule_entry in get_view_rules_of_type("member_source"):
			var id : String = rule_entry.id;
			var raw_params : Dictionary = rule_entry.get("params");
			var rule_hook := get_view_rule_hook(id, "member_source");
			if !rule_hook: continue;
			for runtime_key in object_views:
				var obj : Object = runtime_key_to_view_object(object_type, runtime_key);
				if !obj: continue;
				rule_hook.populate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params));

func get_scene_object_count() -> int:
	var total := 0;
	for object_type in scene_objects:
		total += scene_objects[object_type].size();
	return total;

func has_any_scene_data() -> bool:
	return !scene_data.is_empty() || !scene_objects.is_empty();

func serialize() -> Dictionary:
	var serialized := {
		"view_rules": view_rules,
		"scene_data": scene_data.duplicate(false)
	};
	var serialized_objects : Dictionary = {};
	serialized.scene_data.objects = serialized_objects;
	
	for object_type in scene_objects:
		var serialized_objects_of_type := {};
		serialized_objects[object_type] = serialized_objects_of_type;
		var runtime_objects_of_type = scene_objects[object_type];
		for runtime_key in runtime_objects_of_type:
			var serialized_key = runtime_key_serialize(object_type, runtime_key);
			if serialized_key == null: continue;
			serialized_objects_of_type[serialized_key] = runtime_objects_of_type[runtime_key];
	
	return serialized;

func deserialize(serialized_view : Dictionary) -> SignalGraphView:
	view_rules = serialized_view.get("view_rules",{}).duplicate(false);
	scene_data = serialized_view.get("scene_data",{}).duplicate(false);
	scene_objects = {};
	if scene_data.has("objects"):
		var serialized_objects : Dictionary = scene_data.objects;
		scene_data.erase("objects");
		for object_type in serialized_objects:
			var runtime_objects_of_type := {};
			scene_objects[object_type] = runtime_objects_of_type;
			var serialized_objects_of_type = serialized_objects[object_type];
			for serialized_key in serialized_objects_of_type:
				var runtime_key = runtime_key_deserialize(object_type, serialized_key);
				runtime_objects_of_type[runtime_key] = serialized_objects_of_type[serialized_key];
	return self;

func copy_non_scene_data_from(other : SignalGraphView, duplicate_deep : bool = false) -> void:
	if !other: return;
	if duplicate_deep:
		view_rules = other.view_rules.duplicate(true);
	else:
		view_rules = other.view_rules;

func clear_scene_data() -> void:
	scene_data.clear();
	scene_objects.clear();

class Transactions extends RefCounted:
	var editor : SignalGraphEditor;
	var view : SignalGraphView;
	
	func _init(editor : SignalGraphEditor, view : SignalGraphView):
		self.editor = editor;
		self.view = view;
		
	func add_object_view(object_type : String, obj : Object, position_offset : Vector2) -> void:
		if view.has_object_view(object_type, obj):
			view.select_object(object_type, obj);
		else:
			view.add_object_view(object_type, obj);
			var obj_view := view.get_object_view(object_type, obj);
			obj_view["position_offset"] = position_offset;
			view.update_object_member_views_with_rules(object_type, obj);
			view.notify_view_updated();
			view.select_object(object_type, obj);
			
			editor.transactions.begin_transaction("Add object view", UndoRedo.MERGE_ALL, null, false);
			var undo_redo := editor.transactions.undo_redo;
			undo_redo.add_do_method(view, &"set_object_view", object_type, obj, obj_view);
			undo_redo.add_do_method(view, &"notify_view_updated");
			undo_redo.add_do_method(view, &"select_object", object_type, obj);
			undo_redo.add_undo_method(view, &"remove_object_view", object_type, obj);
			undo_redo.add_undo_method(view, &"notify_view_updated");
			editor.transactions.end_transaction(false);
	
	func remove_object_view(object_type : String, obj : Object) -> void:
		if !view.has_object_view(object_type, obj):
			return;
		var obj_view := view.get_object_view(object_type, obj);
		
		editor.transactions.begin_transaction("Remove object view", UndoRedo.MERGE_ALL, null, false);
		var undo_redo := editor.transactions.undo_redo;
		undo_redo.add_do_method(view, &"remove_object_view", object_type, obj);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"set_object_view", object_type, obj, obj_view);
		undo_redo.add_undo_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"select_object", object_type, obj);
		editor.transactions.end_transaction();
	
	func add_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> void:
		if !view.add_object_view_member(object_type, obj, member_type, member_name):
			return;
		view.notify_view_updated();
		
		editor.transactions.begin_transaction("Add node view member", UndoRedo.MERGE_ALL, null, false);
		var undo_redo := editor.transactions.undo_redo;
		undo_redo.add_do_method(view, &"add_object_view_member", object_type, obj, member_type, member_name);
		undo_redo.add_undo_method(view, &"remove_object_view_member", object_type, obj, member_type, member_name);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"notify_view_updated");
		editor.transactions.end_transaction(false);