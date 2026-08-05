@tool
extends EditorPlugin

const PLUGIN_ROOT := "res://addons/signal-graphs";

enum PluginMode {
	MainScreen,
	EditorDock
};

var graph_editor_template : PackedScene = preload(PLUGIN_ROOT + "/scenes/signal_graph_editor.tscn");
var _graph_editor : EditorDock;

var settings : Settings;

var _is_this_instance_main_screen : Variant;
var _pending_scene_state : Dictionary;

func _init() -> void:
	settings = Settings.new(self);
	scene_changed.connect(_on_scene_changed);
	scene_closed.connect(_on_scene_closed);
	scene_saved.connect(_on_scene_saved);

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	create_editor();

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	remove_editor();

func create_editor() -> void:
	_graph_editor = graph_editor_template.instantiate();
	_graph_editor.plugin = self;
	if _has_main_screen():
		EditorInterface.get_editor_main_screen().add_child(_graph_editor);
		_graph_editor.visible = false;
	else:
		add_dock(_graph_editor);
	
func remove_editor() -> void:
	if _graph_editor == null:
		return;
	if _has_main_screen():
		EditorInterface.get_editor_main_screen().remove_child(_graph_editor);
	else:
		remove_dock(_graph_editor);
	_graph_editor.queue_free();
	_graph_editor = null;

func _make_visible(visible: bool) -> void:
	if _has_main_screen():
		_graph_editor.visible = visible;
		
func _get_state() -> Dictionary:
	return _graph_editor.get_scene_state();

func _set_state(state: Dictionary) -> void:
	_pending_scene_state = state;

func _get_window_layout(configuration: ConfigFile) -> void:
	var editor_state = _graph_editor.get_editor_state();
	configuration.set_value("Signal Graphs", "editor_state", editor_state);

func _set_window_layout(configuration: ConfigFile) -> void:
	_graph_editor.set_editor_state(configuration.get_value("Signal Graphs", "editor_state", {}));

func _on_scene_changed(scene_root : Node) -> void:
	var scene_state := _pending_scene_state;
	_pending_scene_state = {};
	_graph_editor.load_scene(scene_root, scene_state);

func _on_scene_closed(filepath : String) -> void:
	pass;

func _on_scene_saved(filepath : String) -> void:
	pass;

func reload() -> void:
	EditorInterface.call_deferred(&"set_plugin_enabled", "signal-graphs", false);
	EditorInterface.call_deferred(&"set_plugin_enabled", "signal-graphs", true);

func _get_plugin_name() -> String:
	return "Signals";
	
func _has_main_screen() -> bool:
	var is_main_screen : bool = _is_this_instance_main_screen if _is_this_instance_main_screen != null else settings.plugin_mode == PluginMode.MainScreen;
	_is_this_instance_main_screen = is_main_screen;
	return is_main_screen;
	
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Signals", "EditorIcons");

class Settings extends RefCounted:
	const PROJECT_SETTING_PLUGIN_MODE := &"signal_graphs/editor/plugin_mode";
	const PROJECT_SETTING_HOOK_SCRIPTS := &"signal_graphs/hooks/hook_scripts";
	const ALL_PROJECT_SETTINGS := [PROJECT_SETTING_PLUGIN_MODE, PROJECT_SETTING_HOOK_SCRIPTS];
	
	signal plugin_mode_changed(mode : PluginMode);
	signal hook_scripts_changed(hook_scripts : Array[String]);
	
	var plugin : EditorPlugin;
	
	var plugin_mode : PluginMode:
		get:
			if !ProjectSettings.has_setting(PROJECT_SETTING_PLUGIN_MODE):
				return 0 as PluginMode;
			return ProjectSettings.get_setting(PROJECT_SETTING_PLUGIN_MODE);
	var hook_scripts : Array[String]:
		get:
			if !ProjectSettings.has_setting(PROJECT_SETTING_HOOK_SCRIPTS):
				return [] as Array[String];
			return ProjectSettings.get_setting(PROJECT_SETTING_HOOK_SCRIPTS);
	
	var _last_used_settings : Dictionary;
	
	func _init(plugin : EditorPlugin) -> void:
		self.plugin = plugin;
		plugin.project_settings_changed.connect(_on_project_settings_changed);
		_on_project_settings_changed();
		plugin.tree_entered.connect(add_project_settings);
	
	func add_project_settings() -> void:
		# Plugin Mode
		if !ProjectSettings.get_setting(PROJECT_SETTING_PLUGIN_MODE):
			ProjectSettings.set_setting(PROJECT_SETTING_PLUGIN_MODE, 0);
		ProjectSettings.add_property_info({
			"name": PROJECT_SETTING_PLUGIN_MODE,
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": "Main Screen,Editor Dock"
		});
		ProjectSettings.set_initial_value(PROJECT_SETTING_PLUGIN_MODE, 0);
		
		# Hooks
		if !ProjectSettings.get_setting(PROJECT_SETTING_HOOK_SCRIPTS):
			ProjectSettings.set_setting(PROJECT_SETTING_HOOK_SCRIPTS, [] as Array[String]);
		ProjectSettings.add_property_info({
			"name": PROJECT_SETTING_HOOK_SCRIPTS,
			"type": TYPE_ARRAY,
			"hint": PROPERTY_HINT_TYPE_STRING,
			"hint_string": "{0}/{1}:*.gd,*.cs".format([TYPE_STRING,PROPERTY_HINT_FILE])
		});
		ProjectSettings.set_initial_value(PROJECT_SETTING_HOOK_SCRIPTS, [] as Array[String]);
	
	func _on_project_settings_changed() -> void:
		for key in ALL_PROJECT_SETTINGS:
			var value = ProjectSettings.get_setting(key);
			if _last_used_settings.get(key) != value:
				if !_last_used_settings.has(key):
					# Just loaded plugin, only update the dictionary
					_last_used_settings[key] = value;
				else:
					print("Project setting changed: " + key + "; from " + str(_last_used_settings.get(key)) + " to " + str(value));
					_last_used_settings[key] = value;
					_on_relevant_project_setting_changed(key, value);
		pass;
	
	func _on_relevant_project_setting_changed(name : StringName, value) -> void:
		match name:
			PROJECT_SETTING_PLUGIN_MODE:
				plugin_mode_changed.emit(value);
				plugin.reload();
			PROJECT_SETTING_HOOK_SCRIPTS:
				hook_scripts_changed.emit(value);
				plugin.reload();