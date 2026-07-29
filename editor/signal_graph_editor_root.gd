@tool
extends Control

@export var editor : GraphEdit;

func reload_plugin() -> void:
	print("reload plugin TODO")

func populate_from_scene() -> void:
	var scene_root := EditorInterface.get_edited_scene_root();
	editor.clear();
	editor.populating.populate_from_scene(scene_root);
	
func save_to_scene() -> void:
	var scene_root := EditorInterface.get_edited_scene_root();
	editor.save(scene_root);