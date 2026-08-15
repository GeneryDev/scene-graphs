class_name SceneGraphView 
extends RefCounted

signal view_updated();

var editor : SceneGraphEditor;
var transactions : Transactions;

var view_rules : Dictionary = {};
var hook_options : Dictionary = {};
var scene_data : Dictionary = {};
var scene_objects : Dictionary = {};

func _init(editor : SceneGraphEditor):
	self.editor = editor;
	transactions = Transactions.new(editor, self);

var _update_signal_queued := false;

func notify_view_updated(throttled : bool = true) -> void:
	if throttled:
		if _update_signal_queued:
			return;
		else:
			call_deferred(&"notify_view_updated", false);
			_update_signal_queued = true;
			return;
	_update_signal_queued = false;
	view_updated.emit();

func get_all_scene_object_views() -> Dictionary:
	var all_scene_object_views : Dictionary = scene_objects;
	return all_scene_object_views;

func get_scene_object_views(object_type : String) -> Dictionary:
	return get_all_scene_object_views().get_or_add(object_type, {});
	
func add_object_view(object_type : String, obj : Object) -> bool:
	if !obj: return false;
	var object_key = view_object_to_object_key(object_type, obj);
	if object_key == null: return false;
	var scene_object_views := get_scene_object_views(object_type);
	if scene_object_views.has(object_key):
		# already added
		return false;
	var obj_view := {
		"members": {}
	};
	scene_object_views[object_key] = obj_view;
	return true;
	
func set_object_view(object_type : String, obj : Object, obj_view : Dictionary) -> bool:
	if !obj: return false;
	var object_key = view_object_to_object_key(object_type, obj);
	if object_key == null: return false;
	var scene_object_views := get_scene_object_views(object_type);
	scene_object_views[object_key] = obj_view;
	return true;
	
func get_object_view(object_type : String, obj : Object) -> Dictionary:
	if !obj: return {};
	var object_key = view_object_to_object_key(object_type, obj);
	if object_key == null: return {};
	var scene_object_views := get_scene_object_views(object_type);
	if !scene_object_views.has(object_key): return {};
	return scene_object_views[object_key];
	
func has_object_view(object_type : String, obj : Object) -> bool:
	if get_object_view(object_type, obj):
		return true;
	return false;
	
func remove_object_view(object_type : String, obj : Object) -> bool:
	if !obj: return false;
	var object_key = view_object_to_object_key(object_type, obj);
	if object_key == null: return false;
	var scene_object_views := get_scene_object_views(object_type);
	if !scene_object_views.has(object_key): return false;
	var removed = scene_object_views[object_key];
	scene_object_views.erase(object_key);
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

func override_object_view_members_by_type(object_type : String, obj : Object, member_type : String, member_names : Array) -> bool:
	var obj_view := get_object_view(object_type, obj);
	if !obj_view:
		printerr("Failed to add object view member; no object view for " + object_type + " " + str(obj));
		return false;
	var list : Array = obj_view.members[member_type] if obj_view.members.has(member_type) else [];
	obj_view.members[member_type] = list;
	if list == member_names: return false;
	list.clear();
	for member_name : StringName in member_names:
		list.append(member_name);
	return true;

func override_object_view_members(object_type : String, obj : Object, members_by_type : Dictionary) -> bool:
	var any := false;
	for member_type in members_by_type:
		if override_object_view_members_by_type(object_type, obj, member_type, members_by_type[member_type] as Array):
			any = true;
	return any;
	
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
	printerr("Graph view object type '" + object_type + "' is not supported by any of the active scene graph editor hooks. Some data may be lost.");

func view_object_to_object_key(object_type : String, obj : Object) -> Variant:
	if !obj: return null;
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.view_object_to_object_key(object_type, obj);
	
	_print_unsupported_object_type(object_type);
	return null;

func object_key_to_view_object(object_type : String, key : Variant) -> Object:
	if key == null: return null;
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.object_key_to_view_object(object_type, key);
	
	_print_unsupported_object_type(object_type);
	return null;

func object_key_serialize(object_type : String, key : Variant) -> Variant:
	if key == null: return null;
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.object_key_serialize(object_type, key);
	
	_print_unsupported_object_type(object_type);
	return null;

func object_key_deserialize(object_type : String, serialized : Variant) -> Variant:
	if serialized == null: return null;
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type): continue;
		return hook.object_key_deserialize(object_type, serialized);
	
	_print_unsupported_object_type(object_type);
	return null;

func instantiate_graph_node_for_object(object_type : String, obj : Object, graph_node_script : Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd")) -> GraphNode:
	if !obj: return null;
	var graph_node : GraphNode = graph_node_script.new(object_type, obj, editor);
	graph_node.name = _object_to_graph_node_name(object_type, obj);
	return graph_node;

func _object_to_graph_node_name(object_type : String, obj : Object) -> StringName:
	if !obj: return &"";
	var object_key = view_object_to_object_key(object_type, obj);
	if !object_key: return &"";
	var node_name := StringName(object_type + "_" + str(object_key));
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
	if !hook: return null;
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

func hook_options_from_dict(hook : Object, raw_options : Dictionary) -> Variant:
	if !hook: return null;
	if !hook.has_method(&"create_hook_options"): return null;
	var params : Object = hook.create_hook_options();
	
	for key in raw_options:
		var raw_value = raw_options[key];
		var default_value = params.get(key);
		if default_value == null: continue;
		if default_value is Array:
			default_value.assign(raw_value);
		elif default_value is Dictionary:
			default_value.assign(raw_value);
		else:
			params.set(key, raw_value);
	return params;

func hook_options_to_dict(hook : Object, params : Variant) -> Dictionary:
	if !params: return {};
	var raw_params : Dictionary = {};
	for property in params.get_property_list():
		if property.name == &"script": continue;
		var value = params.get(property.name);
		if value == null: continue;
		raw_params[property.name] = value;
	return raw_params;

func get_hook_options(hook : Object) -> Variant:
	var id : String = hook.get_hook_options_id();
	var raw_hook_options : Dictionary = self.hook_options.get(id,{});
	return hook_options_from_dict(hook, raw_hook_options);

func get_view_rules_of_type(rule_type : String) -> Array:
	return view_rules.get_or_add(rule_type, []);

func update_object_views_with_rules() -> void:
	var objects := generate_object_list_with_rules();
	for entry in objects:
		var object_type : String = entry.object_type;
		var object : Object = entry.object;
		add_object_view(object_type, object);

func generate_object_list_with_rules() -> Array:
	var generated_objects := [];
	for rule_entry in get_view_rules_of_type("object_source"):
		var id : String = rule_entry.id;
		var raw_params : Dictionary = rule_entry.get("params");
		var rule_hook := get_view_rule_hook(id, "object_source");
		if !rule_hook: continue;
		var objects : Array = rule_hook.generate_view_objects(rule_params_from_dict(rule_hook, raw_params));
		generated_objects.append_array(objects);
	return generated_objects;

func add_object_view_members(members : Array, fallback_object_type : String, fallback_object : Object) -> Dictionary:
	var output := {
		"success": false,
		"added_object_views": [],
		"added_member_views": []
	};
	for member in members:
		var member_type : String = member.member_type;
		var member_name : StringName = member.member_name;
		var entry_object_type : String = member.get("object_type", fallback_object_type);
		var entry_object : Object = member.get("object", fallback_object);
		if !has_object_view(entry_object_type, entry_object):
			output.added_object_views.append({"object_type": entry_object_type, "object": entry_object});
			add_object_view(entry_object_type, entry_object);
		if add_object_view_member(entry_object_type, entry_object, member_type, member_name):
			output.added_member_views.append({"object_type": entry_object_type, "object": entry_object, "member_type": member_type, "member_name": member_name});
			output.success = true;
	return output;

func remove_object_view_members(members : Array, fallback_object_type : String, fallback_object : Object) -> Dictionary:
	var output := {
		"success": false,
		"removed_member_views": []
	};
	for member in members:
		var member_type : String = member.member_type;
		var member_name : StringName = member.member_name;
		var entry_object_type : String = member.get("object_type", fallback_object_type);
		var entry_object : Object = member.get("object", fallback_object);
		if !has_object_view(entry_object_type, entry_object): continue;
		if remove_object_view_member(entry_object_type, entry_object, member_type, member_name):
			output.removed_member_views.append({"object_type": entry_object_type, "object": entry_object, "member_type": member_type, "member_name": member_name});
			output.success = true;
	return output;

func update_object_view_members_with_rules(object_type : String, obj : Object) -> Dictionary:
	var members := generate_object_member_list_with_rules(object_type, obj);
	return add_object_view_members(members, object_type, obj);

func generate_object_member_list_with_rules(object_type : String, obj : Object) -> Array:
	var generated_members := [];
	for rule_entry in get_view_rules_of_type("member_source"):
		generated_members.append_array(generate_object_member_list_with_rule(object_type, obj, rule_entry));
	return generated_members;

func generate_object_member_list_with_rule(object_type : String, obj : Object, rule_entry : Dictionary) -> Array:
	var id : String = rule_entry.id;
	var raw_params : Dictionary = rule_entry.get("params");
	var rule_hook := get_view_rule_hook(id, "member_source");
	if !rule_hook: return [];
	return rule_hook.generate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params));

func update_all_object_view_members_with_rules() -> Dictionary:
	var output := {
		"success": false,
		"added_object_views": [],
		"added_member_views": []
	};
	for object_type in get_all_scene_object_views():
		var object_views : Dictionary = get_scene_object_views(object_type);
		
		for rule_entry in get_view_rules_of_type("member_source"):
			var id : String = rule_entry.id;
			var raw_params : Dictionary = rule_entry.get("params");
			var rule_hook := get_view_rule_hook(id, "member_source");
			if !rule_hook: continue;
			for object_key in object_views:
				var obj : Object = object_key_to_view_object(object_type, object_key);
				if !obj: continue;
				var members : Array = rule_hook.generate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params));
				var result := add_object_view_members(members, object_type, obj);
				output.added_object_views.append_array(result.added_object_views);
				output.added_member_views.append_array(result.added_member_views);
				output.success |= result.success;
	return output;

func get_scene_object_count() -> int:
	var total := 0;
	for object_type in scene_objects:
		total += scene_objects[object_type].size();
	return total;

func has_any_scene_data() -> bool:
	return !scene_data.is_empty() || !scene_objects.is_empty();

func serialize() -> Dictionary:
	var serialized := {
		"view_rules": view_rules.duplicate(true),
		"hook_options": hook_options.duplicate(true),
		"scene_data": scene_data.duplicate(true),
		"scene_objects": scene_objects.duplicate(true)
	};
	
	var serialized_objects : Dictionary = serialized["scene_objects"];
	for object_type in serialized_objects:
		var serialized_objects_of_type := {};
		var runtime_objects_of_type = serialized_objects[object_type];
		serialized_objects[object_type] = serialized_objects_of_type;
		for runtime_key in runtime_objects_of_type:
			var serialized_key = object_key_serialize(object_type, runtime_key);
			if serialized_key == null: continue;
			serialized_objects_of_type[serialized_key] = runtime_objects_of_type[runtime_key];
	
	for hook in editor.hooks.view_serialization:
		hook.edit_serialized_view(serialized);
	
	return serialized;

func deserialize(serialized_view : Dictionary) -> SceneGraphView:
	view_rules = serialized_view.get("view_rules",{}).duplicate(false);
	hook_options = serialized_view.get("hook_options",{}).duplicate(false);
	scene_data = serialized_view.get("scene_data",{}).duplicate(false);
	scene_objects = serialized_view.get("scene_objects",{}).duplicate(false);
	
	var serialized_objects := scene_objects;
	for object_type in serialized_objects:
		var runtime_objects_of_type := {};
		var serialized_objects_of_type = serialized_objects[object_type];
		serialized_objects[object_type] = runtime_objects_of_type;
		for serialized_key in serialized_objects_of_type:
			var runtime_key = object_key_deserialize(object_type, serialized_key);
			if runtime_key == null: continue;
			runtime_objects_of_type[runtime_key] = serialized_objects_of_type[serialized_key];
	
	for hook in editor.hooks.view_serialization:
		hook.edit_deserialized_view(self);
	
	return self;

func copy_non_scene_data_from(other : SceneGraphView, duplicate_deep : bool = false) -> void:
	if !other: return;
	if duplicate_deep:
		view_rules = other.view_rules.duplicate(true);
		hook_options = other.hook_options.duplicate(true);
	else:
		view_rules = other.view_rules;
		hook_options = other.hook_options;

func clear_scene_data() -> void:
	scene_data.clear();
	scene_objects.clear();

class Transactions extends RefCounted:
	var editor : SceneGraphEditor;
	var view : SceneGraphView;
	
	func _init(editor : SceneGraphEditor, view : SceneGraphView):
		self.editor = editor;
		self.view = view;
		
	func add_object_view(object_type : String, obj : Object, position_offset = null) -> void:
		if view.has_object_view(object_type, obj):
			view.select_object(object_type, obj);
		else:
			view.add_object_view(object_type, obj);
			var obj_view := view.get_object_view(object_type, obj);
			if position_offset != null:
				obj_view["position_offset"] = position_offset as Vector2;
			view.update_object_view_members_with_rules(object_type, obj);
			view.notify_view_updated();
			view.select_object(object_type, obj);
			
			var undo_redo := EditorInterface.get_editor_undo_redo();
			undo_redo.create_action("Add object view", UndoRedo.MERGE_ALL, editor.scene_root, false);
			undo_redo.add_do_method(view, &"set_object_view", object_type, obj, obj_view);
			undo_redo.add_do_method(view, &"notify_view_updated");
			undo_redo.add_do_method(view, &"select_object", object_type, obj);
			undo_redo.add_undo_method(view, &"remove_object_view", object_type, obj);
			undo_redo.add_undo_method(view, &"notify_view_updated");
			undo_redo.commit_action(false);
		
	func add_object_views(objects : Array) -> void:
		var undo_redo := EditorInterface.get_editor_undo_redo();
		var transaction_name := "Add object views";
		
		# Add object views first (with no members)
		for object in objects:
			var object_type : String = object.object_type;
			var obj : Object = object.object;
			var position_offset = object.get("position_offset");
			if !view.has_object_view(object_type, obj):
				view.add_object_view(object_type, obj);
				var obj_view := view.get_object_view(object_type, obj);
				if position_offset != null:
					obj_view["position_offset"] = position_offset as Vector2;
				
				undo_redo.create_action(transaction_name, UndoRedo.MERGE_ALL, editor.scene_root, true);
				undo_redo.add_do_method(view, &"set_object_view", object_type, obj, obj_view);
				undo_redo.add_do_method(view, &"notify_view_updated");
				undo_redo.add_do_method(view, &"select_object", object_type, obj);
				undo_redo.add_undo_method(view, &"notify_view_updated");
				undo_redo.add_undo_method(view, &"remove_object_view", object_type, obj);
				undo_redo.commit_action(false);
		
		# Then add members, update
		var extra_added_object_views := [];
		for object in objects:
			var object_type : String = object.object_type;
			var obj : Object = object.object;
			var result := view.update_object_view_members_with_rules(object_type, obj);
			for extra in result.added_object_views:
				if extra_added_object_views.has(extra): continue;
				undo_redo.create_action(transaction_name, UndoRedo.MERGE_ALL, editor.scene_root, true);
				var extra_obj_view := view.get_object_view(extra.object_type, extra.object);
				undo_redo.add_do_method(view, &"set_object_view", extra.object_type, extra.object, extra_obj_view);
				undo_redo.add_undo_method(view, &"remove_object_view", extra.object_type, extra.object);
				undo_redo.commit_action(false);
		
		view.notify_view_updated();
		
		# Then select
		for object in objects:
			var object_type : String = object.object_type;
			var obj : Object = object.object;
			view.select_object.call_deferred(object_type, obj);
		
	func remove_object_views(objects : Array) -> void:
		var undo_redo := EditorInterface.get_editor_undo_redo();
		var transaction_name := "Remove object views";
		
		for object in objects:
			var object_type : String = object.object_type;
			var obj : Object = object.object;
			if !view.has_object_view(object_type, obj):
				return;
			var obj_view := view.get_object_view(object_type, obj);
			undo_redo.create_action(transaction_name, UndoRedo.MERGE_ALL, editor.scene_root, true);
			undo_redo.add_do_method(view, &"remove_object_view", object_type, obj);
			undo_redo.add_do_method(view, &"notify_view_updated");
			undo_redo.add_undo_method(view, &"select_object", object_type, obj);
			undo_redo.add_undo_method(view, &"notify_view_updated");
			undo_redo.add_undo_method(view, &"set_object_view", object_type, obj, obj_view);
			undo_redo.commit_action();
	
	func remove_object_view(object_type : String, obj : Object) -> void:
		if !view.has_object_view(object_type, obj):
			return;
		var obj_view := view.get_object_view(object_type, obj);
		
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Remove object view", UndoRedo.MERGE_ALL, editor.scene_root, false);
		undo_redo.add_do_method(view, &"remove_object_view", object_type, obj);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"set_object_view", object_type, obj, obj_view);
		undo_redo.add_undo_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"select_object", object_type, obj);
		undo_redo.commit_action();
	
	func add_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> void:
		if !view.add_object_view_member(object_type, obj, member_type, member_name):
			return;
		view.notify_view_updated();
		
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Add object view member", UndoRedo.MERGE_ALL, editor.scene_root, false);
		undo_redo.add_do_method(view, &"add_object_view_member", object_type, obj, member_type, member_name);
		undo_redo.add_undo_method(view, &"remove_object_view_member", object_type, obj, member_type, member_name);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"notify_view_updated");
		undo_redo.commit_action(false);
	
	func add_object_view_members(members : Array, fallback_object_type : String = "", fallback_object : Object = null) -> void:
		var result := view.add_object_view_members(members, fallback_object_type, fallback_object);
		if !result.success:
			return;
		view.notify_view_updated();
		
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Add object view members", UndoRedo.MERGE_ALL, editor.scene_root, false);
		undo_redo.add_do_method(view, &"add_object_view_members", members, fallback_object_type, fallback_object);
		undo_redo.add_undo_method(view, &"remove_object_view_members", result.added_member_views, fallback_object_type, fallback_object);
		for object in result.added_object_views:
			undo_redo.add_undo_method(view, &"remove_object_view", object.object_type, object.object);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"notify_view_updated");
		undo_redo.commit_action(false);
	
	func remove_object_view_members(members : Array, fallback_object_type : String = "", fallback_object : Object = null) -> void:
		var result := view.remove_object_view_members(members, fallback_object_type, fallback_object);
		if !result.success:
			return;
		view.notify_view_updated();
		
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Remove object view members", UndoRedo.MERGE_ALL, editor.scene_root, false);
		undo_redo.add_do_method(view, &"remove_object_view_members", result.removed_member_views, fallback_object_type, fallback_object);
		undo_redo.add_undo_method(view, &"add_object_view_members", result.removed_member_views, fallback_object_type, fallback_object);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"notify_view_updated");
		undo_redo.commit_action(false);
	
	func remove_object_view_member(object_type : String, obj : Object, member_type : String, member_name : StringName) -> void:
		if !view.remove_object_view_member(object_type, obj, member_type, member_name):
			return;
		view.notify_view_updated();
		
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Remove object view member", UndoRedo.MERGE_ALL, editor.scene_root, false);
		undo_redo.add_do_method(view, &"remove_object_view_member", object_type, obj, member_type, member_name);
		undo_redo.add_undo_method(view, &"add_object_view_member", object_type, obj, member_type, member_name);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"notify_view_updated");
		undo_redo.commit_action(false);
	
	func override_object_view_members(object_type : String, obj : Object, members_by_type : Dictionary) -> void:
		var old_members_by_type := {};
		for member_type in members_by_type:
			old_members_by_type[member_type] = view.get_object_view_members(object_type, obj, member_type).duplicate();
	
		if !view.override_object_view_members(object_type, obj, members_by_type):
			return;
		view.notify_view_updated();
		
		var undo_redo := EditorInterface.get_editor_undo_redo();
		undo_redo.create_action("Change object view members", UndoRedo.MERGE_ALL, editor.scene_root, false);
		undo_redo.add_do_method(view, &"override_object_view_members", object_type, obj, members_by_type);
		undo_redo.add_undo_method(view, &"override_object_view_members", object_type, obj, old_members_by_type);
		undo_redo.add_do_method(view, &"notify_view_updated");
		undo_redo.add_undo_method(view, &"notify_view_updated");
		undo_redo.commit_action(false);