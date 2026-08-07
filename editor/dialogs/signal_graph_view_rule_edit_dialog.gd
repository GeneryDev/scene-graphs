@tool
extends ConfirmationDialog

signal rule_selected(hook : Object, params : Variant);

var _hooks : Array[Object];
var _editing_params : Variant;

func _init() -> void:
	confirmed.connect(_on_confirmed);

func setup(view_rule_type : String, hooks : Array[Object], selected_hook : Object, params : Variant) -> void:
	theme = EditorInterface.get_editor_theme();
	
	_hooks = hooks;
	
	%"Type Label".text = view_rule_type.capitalize();
	
	var dropdown : OptionButton = %"Rule Dropdown";
	dropdown.clear();
	
	for hook in hooks:
		var label : String = hook.get_view_rule_label(null);
		dropdown.add_item(label);
		if hook == selected_hook:
			dropdown.select(dropdown.item_count-1);
	
	dropdown.item_selected.connect(_on_item_selected);
	if params:
		_editing_params = params;
	else:
		_on_item_selected(dropdown.selected);
	
	setup_inspector();

func _on_item_selected(index : int) -> void:
	print("item selected " + str(index));
	var dropdown : OptionButton = %"Rule Dropdown";
	var hook := _hooks[dropdown.selected];
	if hook.has_method(&"create_view_rule_params"):
		_editing_params = hook.create_view_rule_params();
	else:
		_editing_params = null;
	setup_inspector();

func setup_inspector() -> void:
	var property_container : Container = %"Property Editors";
	for child in property_container.get_children():
		property_container.remove_child(child);
		child.queue_free();
		
	var dropdown : OptionButton = %"Rule Dropdown";
	var hook := _hooks[dropdown.selected];
	
	if hook.has_method(&"create_view_rule_params"):
		for property in _editing_params.get_property_list():
			if property.name == &"script": continue;
			var value = _editing_params.get(property.name);
			if value == null: continue;
			
			var property_editor := EditorInspector.instantiate_property_editor(_editing_params, property.type, "", property.hint, property.hint_string, property.usage);
			property_editor.label = property.name.capitalize();
			property_editor.set_object_and_property(_editing_params, property.name);
			property_editor.selectable = false;
			property_editor.update_property();
			property_container.add_child(property_editor);
			property_editor.property_changed.connect(_on_property_changed);
			if value is Array || value is Dictionary:
				property_editor.property_changed.connect(func (_property: StringName, _value: Variant, _field: StringName, _changing: bool) -> void:
					property_editor.update_property();
				);
			
			if _editing_params.has_method(&"get_property_description"):
				var description : String = _editing_params.get_property_description(property.name);
				if !description.is_empty():
					property_editor.tooltip_text = description;
	else:
		var none_label := Label.new();
		none_label.text = "No parameters for this rule";
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;
		none_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER;
		none_label.size_flags_vertical = Control.SIZE_EXPAND_FILL;
		property_container.add_child(none_label);

func _on_property_changed(property: StringName, value: Variant, field: StringName, changing: bool) -> void:
	_editing_params.set(property, value);

func _on_confirmed() -> void:
	var dropdown : OptionButton = %"Rule Dropdown";
	var hook := _hooks[dropdown.selected];
	rule_selected.emit(hook, _editing_params);