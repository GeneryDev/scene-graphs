@tool
extends EditorDock

@export var editor: SceneGraphEditor
@export var view_manager: Node

var plugin: EditorPlugin


func _enter_tree() -> void:
	if is_part_of_edited_scene():
		return
	_add_hooks_from_project_settings()
	%"Reload Button".icon = EditorInterface.get_editor_theme().get_icon(&"Reload", &"EditorIcons")
	%"Dev Tools Button".get_popup().id_pressed.connect(_on_dev_tool_item_selected)
	%"Dev Tools".visible = plugin.settings.dev_mode


func populate_from_scene() -> void:
	editor.clear()
	editor.load(view_manager.active_local_view)


func get_scene_state() -> Dictionary:
	return view_manager.store_scene_state()


func set_scene_state(scene_state: Dictionary) -> void:
	editor.clear()
	view_manager.restore_scene_state(scene_state)


func get_editor_state() -> Dictionary:
	return view_manager.serialize_editor_state()


func set_editor_state(editor_state: Dictionary) -> void:
	view_manager.deserialize_editor_state(editor_state)


func _add_hooks_from_project_settings() -> void:
	var scripts_list = plugin.settings.hook_scripts
	if scripts_list:
		for script_path in scripts_list:
			if !script_path:
				continue
			editor.hooks.add_hook(load(script_path))


func _on_dev_tool_item_selected(id: int) -> void:
	match id:
		0: # Reload Plugin
			plugin.reload()
