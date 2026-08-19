class_name SceneGraphView
extends RefCounted
## An abstract representation of the scene graph, representing what the user wants to see in the scene graph.

## Fired when the view is updated (via [method notify_view_updated])
signal view_updated()

## A reference to the [SceneGraphEditor].
var editor: SceneGraphEditor
## The [Transactions] inner class instance. Use this for creating transactions (undoable actions).
var transactions: Transactions
## The view rules. A dictionary where each key is a view rule type (e.g. "object_sources" and "member_sources"),
## and each value is an array of dictionaries containing:
## [br]
##   "id" (String): the view rule ID (from get_view_rule_id in hooks)
## [br]
##   "params" (Dictionary): the raw, serializable user configuration for this view rule. Keys are property names and values are values.
var view_rules: Dictionary = { }
## The hook options. A dictionary where each key is a hook ID (from get_hook_options_id),
## and each value is a dictionary with the raw, serializable user configuration for this view rule. Keys are property names and values are values.
var hook_options: Dictionary = { }
## Scene data for this view, such as scroll offset and zoom.
var scene_data: Dictionary = { }
## Scene object data for this view. Structured as follows:
## [codeblock]
## {
##     "<object_type 0>": {
##         <object_key 0>: { # This is an object view
##             "position_offset": Vector2(0, 0),
##             "members": {
##                 "<member_type 0>": [
##                     &"member_name 0"
##                     &"member_name 1"
##                     &"member_name 2"
##                     # ...
##                 ],
##                 "<member_type 1>": [ ... ]
##             }
##         },
##         <object_key 1>: { ... }
##         # another object view, and so on
##     },
##     "<object_type 1>": { ... }
##     # more object types
## }
## [/codeblock]
## Object types are Strings passed in through view-related methods.
## [br]
## Object keys are as given by view_object_to_object_key in "handle_view_object_types"-capable hooks.
## [br]
## Object views hold largely freeform data about the object.
## [br] 
## Member types are Strings passed in through view-related methods, and member names are StringNames provided the same way.
var scene_objects: Dictionary = { }
var _update_signal_queued := false


func _init(editor: SceneGraphEditor):
	self.editor = editor
	transactions = Transactions.new(editor, self)


## Notifies the view that its contents have changed, and fires the relevant signals.
## If the [param throttled] parameter is true, the execution of callbacks is deferred to the end of the frame,
## and it will avoid emitting repeated consecutive signals. If false, the callbacks and signals will execute immediately.
func notify_view_updated(throttled: bool = true) -> void:
	if throttled:
		if _update_signal_queued:
			return
		else:
			call_deferred(&"notify_view_updated", false)
			_update_signal_queued = true
			return
	_update_signal_queued = false
	view_updated.emit()


## Returns all object views grouped by object type. See [param scene_objects]
func get_all_scene_object_views() -> Dictionary:
	return scene_objects


## Returns a dictionary of all object views for a particular object type, by object key. See [param scene_objects]
func get_scene_object_views(object_type: String) -> Dictionary:
	return get_all_scene_object_views().get_or_add(object_type, { })


## Adds an object to the view, given a type and its Object representation.
## Returns true if the view was added, false if it was either unsuccessful or if the object view already existed.
func add_object_view(object_type: String, obj: Object) -> bool:
	if !obj:
		return false
	var object_key = view_object_to_object_key(object_type, obj)
	if object_key == null:
		return false
	var scene_object_views := get_scene_object_views(object_type)
	if scene_object_views.has(object_key):
		# already added
		return false
	var obj_view := {
		"members": { },
	}
	scene_object_views[object_key] = obj_view
	return true


## Overrides a object view's data, given a type, its Object representation, and the new object view data.
## Returns true if it was successful.
func set_object_view(object_type: String, obj: Object, obj_view: Dictionary) -> bool:
	if !obj:
		return false
	var object_key = view_object_to_object_key(object_type, obj)
	if object_key == null:
		return false
	var scene_object_views := get_scene_object_views(object_type)
	scene_object_views[object_key] = obj_view
	return true


## Retrieves the object view data for a particular object, given an object and its type.
## Returns an empty dictionary if unsuccessful or if the object is not present in the view.
func get_object_view(object_type: String, obj: Object) -> Dictionary:
	if !obj:
		return { }
	var object_key = view_object_to_object_key(object_type, obj)
	if object_key == null:
		return { }
	var scene_object_views := get_scene_object_views(object_type)
	if !scene_object_views.has(object_key):
		return { }
	return scene_object_views[object_key]


## Checks whether the given object is present in the view, given an object and its type.
func has_object_view(object_type: String, obj: Object) -> bool:
	if get_object_view(object_type, obj):
		return true
	return false


## Removes an object from the view, given an object and its type.
## Returns true if it was successful in removing the object,
## or false if unsuccessful or if the object was not present in the view in the first place.
func remove_object_view(object_type: String, obj: Object) -> bool:
	if !obj:
		return false
	var object_key = view_object_to_object_key(object_type, obj)
	if object_key == null:
		return false
	var scene_object_views := get_scene_object_views(object_type)
	if !scene_object_views.has(object_key):
		return false
	var removed = scene_object_views[object_key]
	scene_object_views.erase(object_key)
	return true


## Given an object and its type, and a member and its type, adds the member to the object view of the corresponding object, if it exists.
## Fails if there is no such object view for the given object.
## Returns true if successful and the member was added. Returns false if unsuccessful, or if the member was already present in the object's view.
func add_object_view_member(object_type: String, obj: Object, member_type: String, member_name: StringName) -> bool:
	var obj_view := get_object_view(object_type, obj)
	if !obj_view:
		printerr("Failed to add object view member; no object view for " + object_type + " " + str(obj))
		return false
	var list: Array = obj_view.members[member_type] if obj_view.members.has(member_type) else []
	obj_view.members[member_type] = list
	if list.has(member_name):
		return false
	list.append(member_name)
	return true


## Overrides an object view's members, given an object and its type, a member type, and an array of member names.
## Fails if there is no such object view for the given object.
## Returns true if successful and the members were changed. Returns false if unsuccessful, or if the members already present matched the input.
func override_object_view_members_by_type(object_type: String, obj: Object, member_type: String, member_names: Array) -> bool:
	var obj_view := get_object_view(object_type, obj)
	if !obj_view:
		printerr("Failed to add object view member; no object view for " + object_type + " " + str(obj))
		return false
	var list: Array = obj_view.members[member_type] if obj_view.members.has(member_type) else []
	obj_view.members[member_type] = list
	if list == member_names:
		return false
	list.clear()
	for member_name: StringName in member_names:
		list.append(member_name)
	return true


## Overrides an object view's members, given an object and its type, and a dictionary mapping member types to arrays of member names.
## Fails if there is no such object view for the given object.
## Returns true if successful and the members were changed. Returns false if unsuccessful, or if the members already present matched the input.
func override_object_view_members(object_type: String, obj: Object, members_by_type: Dictionary) -> bool:
	var any := false
	for member_type in members_by_type:
		if override_object_view_members_by_type(object_type, obj, member_type, members_by_type[member_type] as Array):
			any = true
	return any


## Checks if an object has a specific member, given an object and its type, and a member and its type.
func has_object_view_member(object_type: String, obj: Object, member_type: String, member_name: StringName) -> bool:
	var obj_view := get_object_view(object_type, obj)
	if !obj_view:
		return false
	return get_object_view_members(object_type, obj, member_type).has(member_name)


## Retrieves an array of member names corresponding to the given member type.
## Fails if there is no such object view for the given object.
func get_object_view_members(object_type: String, obj: Object, member_type: String) -> Array:
	var obj_view := get_object_view(object_type, obj)
	if !obj_view:
		printerr("Failed to get object view members; no object view for " + object_type + " " + str(obj))
		return []
	var list: Array = obj_view.members[member_type] if obj_view.members.has(member_type) else []
	obj_view.members[member_type] = list
	return list


## Given an object and its type, and a member and its type, removes the member from the object view of the corresponding object, if it exists.
## Fails if there is no such object view for the given object.
## Returns true if successful and the member was removed. Returns false if unsuccessful, or if the member wasn't present in the object's view in the first place.
func remove_object_view_member(object_type: String, obj: Object, member_type: String, member_name: StringName) -> bool:
	var obj_view := get_object_view(object_type, obj)
	if !obj_view:
		printerr("Failed to remove object view member; no object view for " + object_type + " " + str(obj))
		return false
	var list: Array = get_object_view_members(object_type, obj, member_type)
	if !list.has(member_name):
		return false
	list.remove_at(list.find(member_name))
	return true


## Clears all scene objects from this view
func clear_all_objects() -> void:
	scene_objects = { }


## Clears all scene objects of a specific type from this view
func clear_objects(object_type: String) -> void:
	scene_objects[object_type] = { }


## Converts an object and its type into an object key, by calling "handle_view_object_types"-capable hooks.
## Fails if no hook supports the given object type.
func view_object_to_object_key(object_type: String, obj: Object) -> Variant:
	if !obj:
		return null
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type):
			continue
		return hook.view_object_to_object_key(object_type, obj)

	_print_unsupported_object_type(object_type)
	return null


## Converts an object key and its type into an object instance, by calling "handle_view_object_types"-capable hooks.
## Fails if no hook supports the given object type.
func object_key_to_view_object(object_type: String, key: Variant) -> Object:
	if key == null:
		return null
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type):
			continue
		return hook.object_key_to_view_object(object_type, key)

	_print_unsupported_object_type(object_type)
	return null


## Converts an object key and its type into a serializable, persistent representation,
## by calling "handle_view_object_types"-capable hooks.
## Fails if no hook supports the given object type.
func object_key_serialize(object_type: String, key: Variant) -> Variant:
	if key == null:
		return null
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type):
			continue
		return hook.object_key_serialize(object_type, key)

	_print_unsupported_object_type(object_type)
	return null


## Converts a serialized object key and its type into an object key,
## by calling "handle_view_object_types"-capable hooks.
## Fails if no hook supports the given object type.
func object_key_deserialize(object_type: String, serialized: Variant) -> Variant:
	if serialized == null:
		return null
	for hook in editor.hooks.handle_view_object_types:
		if !hook.get_supported_view_object_types().has(object_type):
			continue
		return hook.object_key_deserialize(object_type, serialized)

	_print_unsupported_object_type(object_type)
	return null


## Given an object type, object and, optionally, a GraphNode-derived script,
## instantiates a GraphNode to represent the given object, and adds it as a child of the editor.
## If the script is not provided, the standard SceneObjectGraphNode is used.
## The script, if provided, must have a 3-parameter constructor,
## corresponding to the object type (String), object (Object) and editor (SceneGraphEditor)
func create_graph_node_for_object(object_type: String, obj: Object, graph_node_script: Script = preload("res://addons/scene-graphs/editor/elements/scene_object_graph_node.gd")) -> GraphNode:
	if !obj:
		return null
	var graph_node: GraphNode = graph_node_script.new(object_type, obj, editor)
	graph_node.name = _object_to_graph_node_name(object_type, obj)
	if graph_node:
		editor.add_child(graph_node)
	return graph_node


## Retrieves a [GraphNode] from the editor, corresponding to the given object and type. Returns null if no such [GraphNode] exists.
func get_graph_node_for_object(object_type: String, obj: Object) -> GraphNode:
	return editor.get_node_or_null(NodePath(_object_to_graph_node_name(object_type, obj))) as GraphNode


## Selects the [GraphNode] corresponding to the corresponding to the given object and type in the editor, if it exists.
func select_object(object_type: String, obj: Object) -> void:
	if editor.current_view != self:
		return
	var existing_graph_node: GraphNode = get_graph_node_for_object(object_type, obj)
	if existing_graph_node:
		existing_graph_node.set_selected(true)


## Retrieves all view rule hooks for the given view rule type (e.g. "object_sources" and "member_sources")
func get_view_rule_hooks(type: String) -> Array[Object]:
	return editor.hooks.get("view_rule." + type)


## Retrieves a view rule hooks by a given view rule type (e.g. "object_sources" and "member_sources")
## and ID (as returned by get_view_rule_id)
## Fails and returns null if no hook has the given ID.
func get_view_rule_hook(id: String, type: String) -> Object:
	for hook in get_view_rule_hooks(type):
		if hook.get_view_rule_id() == id:
			return hook

	printerr("Invalid view rule id '" + id + "'")
	return null


## Given a view rule hook and a dictionary corresponding to view rule parameters, creates an object that the hook can use
## in place of the params in view rule-related methods. It does so by copying each dictionary entry to properties of the same name.
## This returned value will be of the same type as returned by the hook's [code]create_view_rule_params[/code] method.
## Returns null if the hook does not define a parameters object.
func rule_params_from_dict(hook: Object, raw_params: Dictionary) -> Variant:
	if !hook:
		return null
	if !hook.has_method(&"create_view_rule_params"):
		return null
	var params: Object = hook.create_view_rule_params()

	for key in raw_params:
		var raw_value = raw_params[key]
		var default_value = params.get(key)
		if default_value == null:
			continue
		if default_value is Array:
			default_value.assign(raw_value)
		elif default_value is Dictionary:
			default_value.assign(raw_value)
		else:
			params.set(key, raw_value)
	return params


## Given a view rule hook and an object corresponding to view rule parameters, creates a serializable dictionary containing
## all the properties defined in the given parameter object. It does so by copying each property into a dictionary entry with the same name.
## Returns an empty dictionary if the hook does not define a parameters object.
func rule_params_to_dict(hook: Object, params: Variant) -> Dictionary:
	if !params:
		return { }
	var raw_params: Dictionary = { }
	for property in params.get_property_list():
		if property.name == &"script":
			continue
		var value = params.get(property.name)
		if value == null:
			continue
		raw_params[property.name] = value
	return raw_params


## Given a hook and a dictionary corresponding to its options, creates an object that the hook can use to retrieve user configuration.
## It does so by copying each dictionary entry to properties of the same name.
## This returned value will be of the same type as returned by the hook's [code]create_hook_options[/code] method.
## Returns null if the hook does not define a hook options object.
func hook_options_from_dict(hook: Object, raw_options: Dictionary) -> Variant:
	if !hook:
		return null
	if !hook.has_method(&"create_hook_options"):
		return null
	var params: Object = hook.create_hook_options()

	for key in raw_options:
		var raw_value = raw_options[key]
		var default_value = params.get(key)
		if default_value == null:
			continue
		if default_value is Array:
			default_value.assign(raw_value)
		elif default_value is Dictionary:
			default_value.assign(raw_value)
		else:
			params.set(key, raw_value)
	return params


## Given a hook and an object corresponding to its options, creates a serializable dictionary containing
## all the properties defined in the given options object. It does so by copying each property into a dictionary entry with the same name.
## Returns an empty dictionary if the hook does not define an options object.
func hook_options_to_dict(hook: Object, params: Variant) -> Dictionary:
	if !params:
		return { }
	var raw_params: Dictionary = { }
	for property in params.get_property_list():
		if property.name == &"script":
			continue
		var value = params.get(property.name)
		if value == null:
			continue
		raw_params[property.name] = value
	return raw_params


## Given a hook, retrieves the user configuration for that hook.
## This returned value will be of the same type as returned by the hook's [code]create_hook_options[/code] method.
## Returns null if the hook does not define a hook options object.
func get_hook_options(hook: Object) -> Variant:
	var id: String = hook.get_hook_options_id()
	var raw_hook_options: Dictionary = self.hook_options.get(id, { })
	return hook_options_from_dict(hook, raw_hook_options)


## Retrieves an array of raw view rule dictionaries for the given rule type (i.e. "object_source", "member_source").
## See [member view_rules]
func get_view_rules_of_type(rule_type: String) -> Array:
	return view_rules.get_or_add(rule_type, [])


## Uses this view's view rules to generate an array of objects that should be added to this view, and adds them. 
func update_object_views_with_rules() -> void:
	var objects := generate_object_list_with_rules()
	for entry in objects:
		var object_type: String = entry.object_type
		var object: Object = entry.object
		add_object_view(object_type, object)


## Uses this view's view rules to generate an array of objects that should be added to this view.
## The generated object dictionaries contain "object_type" and "object" entries that can be used in other view methods.
func generate_object_list_with_rules() -> Array:
	var generated_objects := []
	for rule_entry in get_view_rules_of_type("object_source"):
		var id: String = rule_entry.id
		var raw_params: Dictionary = rule_entry.get("params")
		var rule_hook := get_view_rule_hook(id, "object_source")
		if !rule_hook:
			continue
		var objects: Array = rule_hook.generate_view_objects(rule_params_from_dict(rule_hook, raw_params))
		generated_objects.append_array(objects)
	return generated_objects


## Given an array of members, an object and its type, adds them to the view.
## The members array expects dictionaries with "member_type" and "member_name" properties, and optional "object_type" and "object" properties
## (which if missing, will default to the ones passed into the method)
## The returned dictionary will contain the following values:
## * "success" (bool) Whether any change was made
## * "added_object_views" (Dictionary) Dictionaries containing "object_type" and "object" properties for object views
##   that were added during this operation, which didn't already exist when the method was called.
## * "added_member_views" (Dictionary) Dictionaries containing "object_type", "object", "member_type" and "member" properties
##   for object members that were added during this operation, which didn't already exist when the method was called.
func add_object_view_members(members: Array, fallback_object_type: String, fallback_object: Object) -> Dictionary:
	var output := {
		"success": false,
		"added_object_views": [],
		"added_member_views": [],
	}
	for member in members:
		var member_type: String = member.member_type
		var member_name: StringName = member.member_name
		var entry_object_type: String = member.get("object_type", fallback_object_type)
		var entry_object: Object = member.get("object", fallback_object)
		if !has_object_view(entry_object_type, entry_object):
			output.added_object_views.append({ "object_type": entry_object_type, "object": entry_object })
			add_object_view(entry_object_type, entry_object)
		if add_object_view_member(entry_object_type, entry_object, member_type, member_name):
			output.added_member_views.append({ "object_type": entry_object_type, "object": entry_object, "member_type": member_type, "member_name": member_name })
			output.success = true
	return output


## Given an array of members, an object and its type, removes them from the view.
## The members array expects dictionaries with "member_type" and "member_name" properties, and optional "object_type" and "object" properties
## (which if missing, will default to the ones passed into the method)
## The returned dictionary will contain the following values:
## * "success" (bool) Whether any change was made
## * "removed_member_views" (Dictionary) Dictionaries containing "object_type", "object", "member_type" and "member" properties
##   for object members that were removed during this operation, which were present when the method was called.
func remove_object_view_members(members: Array, fallback_object_type: String, fallback_object: Object) -> Dictionary:
	var output := {
		"success": false,
		"removed_member_views": [],
	}
	for member in members:
		var member_type: String = member.member_type
		var member_name: StringName = member.member_name
		var entry_object_type: String = member.get("object_type", fallback_object_type)
		var entry_object: Object = member.get("object", fallback_object)
		if !has_object_view(entry_object_type, entry_object):
			continue
		if remove_object_view_member(entry_object_type, entry_object, member_type, member_name):
			output.removed_member_views.append({ "object_type": entry_object_type, "object": entry_object, "member_type": member_type, "member_name": member_name })
			output.success = true
	return output


## Uses this view's view rules to generate an array of object members for the given object, and adds them.
func update_object_view_members_with_rules(object_type: String, obj: Object) -> Dictionary:
	var members := generate_object_member_list_with_rules(object_type, obj)
	return add_object_view_members(members, object_type, obj)


## Uses this view's view rules to generate an array of object members for the given object.
## The generated member dictionaries contain "member_type" and "member_name" properties,
## and optional "object_type" and "object" properties (which if they're missing,
## are assumed to belong to the object passed into the method).
func generate_object_member_list_with_rules(object_type: String, obj: Object) -> Array:
	var generated_members := []
	for rule_entry in get_view_rules_of_type("member_source"):
		generated_members.append_array(generate_object_member_list_with_rule(object_type, obj, rule_entry))
	return generated_members


## Uses a specific view rule configuration (as stored in [member view_rules])
## to generate an array of object members for the given object.
## The generated member dictionaries contain "member_type" and "member_name" properties,
## and optional "object_type" and "object" properties (which if they're missing,
## are assumed to belong to the object passed into the method).
func generate_object_member_list_with_rule(object_type: String, obj: Object, rule_entry: Dictionary) -> Array:
	var id: String = rule_entry.id
	var raw_params: Dictionary = rule_entry.get("params")
	var rule_hook := get_view_rule_hook(id, "member_source")
	if !rule_hook:
		return []
	return rule_hook.generate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params))


## Uses this view's view rules to generate members for the all view objects, and adds them.
## The returned dictionary will contain the following values:
## * "success" (bool) Whether any change was made
## * "added_object_views" (Dictionary) Dictionaries containing "object_type" and "object" properties for object views
##   that were added during this operation, which didn't already exist when the method was called.
## * "added_member_views" (Dictionary) Dictionaries containing "object_type", "object", "member_type" and "member" properties
##   for object members that were added during this operation, which didn't already exist when the method was called.
func update_all_object_view_members_with_rules() -> Dictionary:
	var output := {
		"success": false,
		"added_object_views": [],
		"added_member_views": [],
	}
	for object_type in get_all_scene_object_views():
		var object_views: Dictionary = get_scene_object_views(object_type)

		for rule_entry in get_view_rules_of_type("member_source"):
			var id: String = rule_entry.id
			var raw_params: Dictionary = rule_entry.get("params")
			var rule_hook := get_view_rule_hook(id, "member_source")
			if !rule_hook:
				continue
			for object_key in object_views:
				var obj: Object = object_key_to_view_object(object_type, object_key)
				if !obj:
					continue
				var members: Array = rule_hook.generate_view_object_members(object_type, obj, rule_params_from_dict(rule_hook, raw_params))
				var result := add_object_view_members(members, object_type, obj)
				output.added_object_views.append_array(result.added_object_views)
				output.added_member_views.append_array(result.added_member_views)
				output.success = output.success || result.success
	return output


## Returns the number of objects represented in the view.
func get_scene_object_count() -> int:
	var total := 0
	for object_type in scene_objects:
		total += scene_objects[object_type].size()
	return total


## Returns true if and only if there is any scene-specific data in this view.
func has_any_scene_data() -> bool:
	return !scene_data.is_empty() || !scene_objects.is_empty()


## Serializes this view into a persistent format that can be saved to disk.
func serialize() -> Dictionary:
	var serialized := {
		"view_rules": view_rules.duplicate(true),
		"hook_options": hook_options.duplicate(true),
		"scene_data": scene_data.duplicate(true),
		"scene_objects": scene_objects.duplicate(true),
	}

	var serialized_objects: Dictionary = serialized["scene_objects"]
	for object_type in serialized_objects:
		var serialized_objects_of_type := { }
		var runtime_objects_of_type = serialized_objects[object_type]
		serialized_objects[object_type] = serialized_objects_of_type
		for runtime_key in runtime_objects_of_type:
			var serialized_key = object_key_serialize(object_type, runtime_key)
			if serialized_key == null:
				continue
			serialized_objects_of_type[serialized_key] = runtime_objects_of_type[runtime_key]

	for hook in editor.hooks.view_serialization:
		hook.edit_serialized_view(serialized)

	return serialized


## Deserializes a given serialized view into this view.
func deserialize(serialized_view: Dictionary) -> SceneGraphView:
	view_rules = serialized_view.get("view_rules", { }).duplicate(false)
	hook_options = serialized_view.get("hook_options", { }).duplicate(false)
	scene_data = serialized_view.get("scene_data", { }).duplicate(false)
	scene_objects = serialized_view.get("scene_objects", { }).duplicate(false)

	var serialized_objects := scene_objects
	for object_type in serialized_objects:
		var runtime_objects_of_type := { }
		var serialized_objects_of_type = serialized_objects[object_type]
		serialized_objects[object_type] = runtime_objects_of_type
		for serialized_key in serialized_objects_of_type:
			var runtime_key = object_key_deserialize(object_type, serialized_key)
			if runtime_key == null:
				continue
			runtime_objects_of_type[runtime_key] = serialized_objects_of_type[serialized_key]

	for hook in editor.hooks.view_serialization:
		hook.edit_deserialized_view(self)

	return self


## Copies non-scene specific data from a given view into this one (that is, only view rules and hook options).
func copy_non_scene_data_from(other: SceneGraphView, duplicate_deep: bool = false) -> void:
	if !other:
		return
	if duplicate_deep:
		view_rules = other.view_rules.duplicate(true)
		hook_options = other.hook_options.duplicate(true)
	else:
		view_rules = other.view_rules
		hook_options = other.hook_options


## Clear scene specific data from this view.
func clear_scene_data() -> void:
	scene_data.clear()
	scene_objects.clear()


func _print_unsupported_object_type(object_type: String) -> void:
	printerr("Graph view object type '" + object_type + "' is not supported by any of the active scene graph editor hooks. Some data may be lost.")


func _object_to_graph_node_name(object_type: String, obj: Object) -> StringName:
	if !obj:
		return &""
	var object_key = view_object_to_object_key(object_type, obj)
	if !object_key:
		return &""
	var node_name := StringName(object_type + "_" + str(object_key))
	return node_name


## Provides methods for interacting with a SceneGraphView in an undoable way.
class Transactions extends RefCounted:
	var editor: SceneGraphEditor
	var view: SceneGraphView


	func _init(editor: SceneGraphEditor, view: SceneGraphView):
		self.editor = editor
		self.view = view


	## Undoable version of [method SceneGraphView.add_object_view].
	## Accepts an optional position offset to place it at a particular location on the graph.
	func add_object_view(object_type: String, obj: Object, position_offset = null) -> void:
		if view.has_object_view(object_type, obj):
			view.select_object(object_type, obj)
		else:
			view.add_object_view(object_type, obj)
			var obj_view := view.get_object_view(object_type, obj)
			if position_offset != null:
				obj_view["position_offset"] = position_offset as Vector2
			var member_changes := view.update_object_view_members_with_rules(object_type, obj)
			view.notify_view_updated()
			view.select_object(object_type, obj)

			var undo_redo := EditorInterface.get_editor_undo_redo()
			undo_redo.create_action("Add object view", UndoRedo.MERGE_ALL, editor.scene_root, false)

			undo_redo.add_do_method(view, &"set_object_view", object_type, obj, obj_view)
			for object in member_changes.added_object_views:
				var added_obj_view := view.get_object_view(object.object_type, object.object)
				undo_redo.add_do_method(view, &"set_object_view", object.object_type, object.object, added_obj_view)
			undo_redo.add_do_method(view, &"notify_view_updated")
			undo_redo.add_do_method(view, &"select_object", object_type, obj)

			undo_redo.add_undo_method(view, &"remove_object_view", object_type, obj)
			for object in member_changes.added_object_views:
				undo_redo.add_undo_method(view, &"remove_object_view", object.object_type, object.object)
			undo_redo.add_undo_method(view, &"notify_view_updated")

			undo_redo.commit_action(false)


	## Undoable, bulk version of [method SceneGraphView.add_object_view].
	func add_object_views(objects: Array) -> void:
		var undo_redo := EditorInterface.get_editor_undo_redo()
		var transaction_name := "Add object views"

		# Add object views first (with no members)
		for object in objects:
			var object_type: String = object.object_type
			var obj: Object = object.object
			var position_offset = object.get("position_offset")
			if !view.has_object_view(object_type, obj):
				view.add_object_view(object_type, obj)
				var obj_view := view.get_object_view(object_type, obj)
				if position_offset != null:
					obj_view["position_offset"] = position_offset as Vector2

				undo_redo.create_action(transaction_name, UndoRedo.MERGE_ALL, editor.scene_root, true)
				undo_redo.add_do_method(view, &"set_object_view", object_type, obj, obj_view)
				undo_redo.add_do_method(view, &"notify_view_updated")
				undo_redo.add_do_method(view, &"select_object", object_type, obj)
				undo_redo.add_undo_method(view, &"notify_view_updated")
				undo_redo.add_undo_method(view, &"remove_object_view", object_type, obj)
				undo_redo.commit_action(false)

		# Then add members, update
		var extra_added_object_views := []
		for object in objects:
			var object_type: String = object.object_type
			var obj: Object = object.object
			var result := view.update_object_view_members_with_rules(object_type, obj)
			for extra in result.added_object_views:
				if extra_added_object_views.has(extra):
					continue
				undo_redo.create_action(transaction_name, UndoRedo.MERGE_ALL, editor.scene_root, true)
				var extra_obj_view := view.get_object_view(extra.object_type, extra.object)
				undo_redo.add_do_method(view, &"set_object_view", extra.object_type, extra.object, extra_obj_view)
				undo_redo.add_undo_method(view, &"remove_object_view", extra.object_type, extra.object)
				undo_redo.commit_action(false)

		view.notify_view_updated()

		# Then select
		for object in objects:
			var object_type: String = object.object_type
			var obj: Object = object.object
			view.select_object.call_deferred(object_type, obj)


	## Undoable, bulk version of [method SceneGraphView.remove_object_view].
	func remove_object_views(objects: Array) -> void:
		var undo_redo := EditorInterface.get_editor_undo_redo()
		var transaction_name := "Remove object views"

		for object in objects:
			var object_type: String = object.object_type
			var obj: Object = object.object
			if !view.has_object_view(object_type, obj):
				return
			var obj_view := view.get_object_view(object_type, obj)
			undo_redo.create_action(transaction_name, UndoRedo.MERGE_ALL, editor.scene_root, true)
			undo_redo.add_do_method(view, &"remove_object_view", object_type, obj)
			undo_redo.add_do_method(view, &"notify_view_updated")
			undo_redo.add_undo_method(view, &"select_object", object_type, obj)
			undo_redo.add_undo_method(view, &"notify_view_updated")
			undo_redo.add_undo_method(view, &"set_object_view", object_type, obj, obj_view)
			undo_redo.commit_action()


	## Undoable, bulk version of [method SceneGraphView.remove_object_view].
	## Accepts an optional position offset to place it at a particular location on the graph.
	func remove_object_view(object_type: String, obj: Object) -> void:
		if !view.has_object_view(object_type, obj):
			return
		var obj_view := view.get_object_view(object_type, obj)

		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Remove object view", UndoRedo.MERGE_ALL, editor.scene_root, false)
		undo_redo.add_do_method(view, &"remove_object_view", object_type, obj)
		undo_redo.add_do_method(view, &"notify_view_updated")
		undo_redo.add_undo_method(view, &"set_object_view", object_type, obj, obj_view)
		undo_redo.add_undo_method(view, &"notify_view_updated")
		undo_redo.add_undo_method(view, &"select_object", object_type, obj)
		undo_redo.commit_action()


	## Undoable version of [method SceneGraphView.add_object_view_member].
	func add_object_view_member(object_type: String, obj: Object, member_type: String, member_name: StringName) -> void:
		if !view.add_object_view_member(object_type, obj, member_type, member_name):
			return
		view.notify_view_updated()

		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Add object view member", UndoRedo.MERGE_ALL, editor.scene_root, false)
		undo_redo.add_do_method(view, &"add_object_view_member", object_type, obj, member_type, member_name)
		undo_redo.add_undo_method(view, &"remove_object_view_member", object_type, obj, member_type, member_name)
		undo_redo.add_do_method(view, &"notify_view_updated")
		undo_redo.add_undo_method(view, &"notify_view_updated")
		undo_redo.commit_action(false)


	## Undoable version of [method SceneGraphView.add_object_view_members].
	func add_object_view_members(members: Array, fallback_object_type: String = "", fallback_object: Object = null) -> void:
		var result := view.add_object_view_members(members, fallback_object_type, fallback_object)
		if !result.success:
			return
		view.notify_view_updated()

		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Add object view members", UndoRedo.MERGE_ALL, editor.scene_root, false)
		undo_redo.add_do_method(view, &"add_object_view_members", members, fallback_object_type, fallback_object)
		undo_redo.add_undo_method(view, &"remove_object_view_members", result.added_member_views, fallback_object_type, fallback_object)
		for object in result.added_object_views:
			undo_redo.add_undo_method(view, &"remove_object_view", object.object_type, object.object)
		undo_redo.add_do_method(view, &"notify_view_updated")
		undo_redo.add_undo_method(view, &"notify_view_updated")
		undo_redo.commit_action(false)


	## Undoable version of [method SceneGraphView.remove_object_view_members].
	func remove_object_view_members(members: Array, fallback_object_type: String = "", fallback_object: Object = null) -> void:
		var result := view.remove_object_view_members(members, fallback_object_type, fallback_object)
		if !result.success:
			return
		view.notify_view_updated()

		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Remove object view members", UndoRedo.MERGE_ALL, editor.scene_root, false)
		undo_redo.add_do_method(view, &"remove_object_view_members", result.removed_member_views, fallback_object_type, fallback_object)
		undo_redo.add_undo_method(view, &"add_object_view_members", result.removed_member_views, fallback_object_type, fallback_object)
		undo_redo.add_do_method(view, &"notify_view_updated")
		undo_redo.add_undo_method(view, &"notify_view_updated")
		undo_redo.commit_action(false)


	## Undoable version of [method SceneGraphView.remove_object_view_member].
	func remove_object_view_member(object_type: String, obj: Object, member_type: String, member_name: StringName) -> void:
		if !view.remove_object_view_member(object_type, obj, member_type, member_name):
			return
		view.notify_view_updated()

		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Remove object view member", UndoRedo.MERGE_ALL, editor.scene_root, false)
		undo_redo.add_do_method(view, &"remove_object_view_member", object_type, obj, member_type, member_name)
		undo_redo.add_undo_method(view, &"add_object_view_member", object_type, obj, member_type, member_name)
		undo_redo.add_do_method(view, &"notify_view_updated")
		undo_redo.add_undo_method(view, &"notify_view_updated")
		undo_redo.commit_action(false)


	## Undoable version of [method SceneGraphView.override_object_view_members].
	func override_object_view_members(object_type: String, obj: Object, members_by_type: Dictionary) -> void:
		var old_members_by_type := { }
		for member_type in members_by_type:
			old_members_by_type[member_type] = view.get_object_view_members(object_type, obj, member_type).duplicate()

		if !view.override_object_view_members(object_type, obj, members_by_type):
			return
		view.notify_view_updated()

		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Change object view members", UndoRedo.MERGE_ALL, editor.scene_root, false)
		undo_redo.add_do_method(view, &"override_object_view_members", object_type, obj, members_by_type)
		undo_redo.add_undo_method(view, &"override_object_view_members", object_type, obj, old_members_by_type)
		undo_redo.add_do_method(view, &"notify_view_updated")
		undo_redo.add_undo_method(view, &"notify_view_updated")
		undo_redo.commit_action(false)
