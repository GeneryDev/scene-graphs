@tool
extends EditorDock

@export var editor : SignalGraphEditor;
@export var view_manager : Node;

var plugin : EditorPlugin;

func reload_plugin() -> void:
	plugin.reload();

func populate_from_scene() -> void:
	var scene_root := EditorInterface.get_edited_scene_root();
	editor.clear();
	editor.pre_load(scene_root);

func get_scene_state() -> Dictionary:
	return view_manager.serialize_scene_state();

func load_scene(scene_root : Node, scene_state : Dictionary) -> void:
	editor.clear();
	editor.pre_load(scene_root);
	view_manager.deserialize_scene_state(scene_state);

func get_editor_state() -> Dictionary:
	return view_manager.serialize_editor_state();

func set_editor_state(editor_state : Dictionary) -> void:
	view_manager.deserialize_editor_state(editor_state);

func _enter_tree() -> void:
	if is_part_of_edited_scene(): return;
	_add_hooks_from_project_settings();

func _add_hooks_from_project_settings() -> void:
	var scripts_list = plugin.settings.hook_scripts;
	if scripts_list:
		for script_path in scripts_list:
			if !script_path: continue;
			editor.hooks.add_hook(load(script_path));
