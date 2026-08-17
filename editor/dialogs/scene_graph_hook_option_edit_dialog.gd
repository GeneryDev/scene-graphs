@tool
extends ConfirmationDialog

signal finished(hook: Object, options: Variant)

var _hook: Object
var _editing_options: Variant


func _init() -> void:
	confirmed.connect(_on_confirmed)


func setup(hook: Object, options: Variant) -> void:
	theme = EditorInterface.get_editor_theme()

	_hook = hook
	_editing_options = options

	%"Hook Name Label".text = hook.get_hook_options_label(null)

	setup_inspector()


func setup_inspector() -> void:
	var property_container: Container = %"Property Editors"
	for child in property_container.get_children():
		property_container.remove_child(child)
		child.queue_free()

	if _hook.has_method(&"get_hook_description"):
		%"Description Label".text = _hook.get_hook_description()
		%"Description Label".visible = true
	else:
		%"Description Label".visible = false

	if _hook.has_method(&"create_hook_options"):
		for property in _editing_options.get_property_list():
			if property.name == &"script":
				continue
			var value = _editing_options.get(property.name)
			if value == null:
				continue

			var property_editor := EditorInspector.instantiate_property_editor(_editing_options, property.type, "", property.hint, property.hint_string, property.usage)
			property_editor.label = property.name.capitalize()
			property_editor.set_object_and_property(_editing_options, property.name)
			property_editor.selectable = false
			property_editor.update_property()
			property_container.add_child(property_editor)
			property_editor.property_changed.connect(_on_property_changed)
			if value is Array || value is Dictionary:
				property_editor.property_changed.connect(
					func(_property: StringName, _value: Variant, _field: StringName, _changing: bool) -> void:
						property_editor.update_property()
				)

			if _editing_options.has_method(&"get_property_description"):
				var description: String = _editing_options.get_property_description(property.name)
				if !description.is_empty():
					property_editor.tooltip_text = description
	else:
		var none_label := Label.new()
		none_label.text = "No parameters for this rule"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		none_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		property_container.add_child(none_label)


func _on_property_changed(property: StringName, value: Variant, field: StringName, changing: bool) -> void:
	_editing_options.set(property, value)


func _on_confirmed() -> void:
	finished.emit(_hook, _editing_options)
