@tool
extends EditorPlugin

const PLUGIN_ROOT := "res://addons/signal-graphs";
const PROJECT_SETTING_NAME_HOOKS := &"signal_graphs/hooks/hook_scripts";

var graph_editor_template : PackedScene = preload(PLUGIN_ROOT + "/scenes/signal_graph_editor.tscn");
var _graph_editor : EditorDock;

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	create_editor();
	SignalGraphEditor.add_project_settings();

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	remove_editor();


func create_editor() -> void:
	_graph_editor = graph_editor_template.instantiate();
	_graph_editor.plugin = self;
	add_dock(_graph_editor);
	
func remove_editor() -> void:
	if _graph_editor == null:
		return;
	remove_dock(_graph_editor);
	_graph_editor.queue_free();
	_graph_editor = null;

func reload() -> void:
	remove_editor();
	create_editor();
	SignalGraphEditor.add_project_settings();
