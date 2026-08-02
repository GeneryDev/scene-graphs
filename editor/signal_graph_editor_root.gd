@tool
extends EditorDock

@export var editor : GraphEdit;

var plugin : EditorPlugin;

func reload_plugin() -> void:
	plugin.reload();

func populate_from_scene() -> void:
	var scene_root := EditorInterface.get_edited_scene_root();
	editor.clear();
	editor.load(scene_root);
	
func save_to_scene() -> void:
	var scene_root := EditorInterface.get_edited_scene_root();
	editor.save(scene_root);

func _enter_tree() -> void:
	if is_part_of_edited_scene(): return;
	plugin.scene_changed.connect(_on_scene_changed);

func _exit_tree() -> void:
	if is_part_of_edited_scene(): return;
	plugin.scene_changed.disconnect(_on_scene_changed);

func _on_scene_changed(scene_root : Node) -> void:
	editor.clear();
	editor.load(scene_root);