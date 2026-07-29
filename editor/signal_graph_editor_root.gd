@tool
extends Control

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