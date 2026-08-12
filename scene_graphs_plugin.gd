@tool
extends EditorPlugin

signal plugin_enabled();
signal plugin_disabled();
signal editor_layout_saving();
signal editor_layout_loading();

const PLUGIN_ROOT := "res://addons/scene-graphs";

enum PluginMode {
	MainScreen,
	EditorDock
};

var graph_editor_template : PackedScene = preload(PLUGIN_ROOT + "/scenes/scene_graph_editor.tscn");
var _dock : EditorDock;

var settings : Settings;
var persistence : Persistence;

var _is_this_instance_main_screen : Variant;

func _init() -> void:
	settings = Settings.new(self);
	persistence = Persistence.new(self);

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	create_editor();

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	remove_editor();

func create_editor() -> void:
	_dock = graph_editor_template.instantiate();
	_dock.plugin = self;
	if _has_main_screen():
		EditorInterface.get_editor_main_screen().add_child(_dock);
		_dock.visible = false;
	else:
		add_dock(_dock);
	
func remove_editor() -> void:
	if _dock == null:
		return;
	if _has_main_screen():
		EditorInterface.get_editor_main_screen().remove_child(_dock);
	else:
		remove_dock(_dock);
	_dock.queue_free();
	_dock = null;

func _make_visible(visible: bool) -> void:
	if _has_main_screen():
		_dock.visible = visible;
		
func _get_state() -> Dictionary:
	return persistence.get_scene_state();

func _set_state(state: Dictionary) -> void:
	persistence.set_scene_state(state);

func _get_window_layout(configuration: ConfigFile) -> void:
	editor_layout_saving.emit();

func _set_window_layout(configuration: ConfigFile) -> void:
	editor_layout_loading.emit();

func reload() -> void:
	EditorInterface.call_deferred(&"set_plugin_enabled", "scene-graphs", false);
	EditorInterface.call_deferred(&"set_plugin_enabled", "scene-graphs", true);
	
func _enable_plugin() -> void:
	plugin_enabled.emit();
	
func _disable_plugin() -> void:
	plugin_disabled.emit();

func _get_plugin_name() -> String:
	return "Signals";
	
func _has_main_screen() -> bool:
	var is_main_screen : bool = _is_this_instance_main_screen if _is_this_instance_main_screen != null else settings.plugin_mode == PluginMode.MainScreen;
	_is_this_instance_main_screen = is_main_screen;
	return is_main_screen;
	
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Signals", "EditorIcons");

class Settings extends RefCounted:
	const PROJECT_SETTING_PLUGIN_MODE := &"scene_graphs/editor/plugin_mode";
	const PROJECT_SETTING_HOOK_SCRIPTS := &"scene_graphs/editor/hook_scripts";
	const PROJECT_SETTING_DEV_MODE := &"scene_graphs/editor/dev_mode";
	const ALL_PROJECT_SETTINGS := [PROJECT_SETTING_PLUGIN_MODE, PROJECT_SETTING_HOOK_SCRIPTS, PROJECT_SETTING_DEV_MODE];
	
	signal plugin_mode_changed(mode : PluginMode);
	signal hook_scripts_changed(hook_scripts : Array[String]);
	signal dev_mode_changed(enabled : bool);
	
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
	var dev_mode : bool:
		get:
			if !ProjectSettings.has_setting(PROJECT_SETTING_DEV_MODE):
				return false;
			return ProjectSettings.get_setting(PROJECT_SETTING_DEV_MODE);
	
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
		
		# Dev Mode
		if !ProjectSettings.get_setting(PROJECT_SETTING_DEV_MODE):
			ProjectSettings.set_setting(PROJECT_SETTING_DEV_MODE, false);
		ProjectSettings.add_property_info({
			"name": PROJECT_SETTING_DEV_MODE,
			"type": TYPE_BOOL,
			"hint": PROPERTY_HINT_NONE,
			"hint_string": ""
		});
		ProjectSettings.set_initial_value(PROJECT_SETTING_DEV_MODE, false);
	
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
			PROJECT_SETTING_DEV_MODE:
				dev_mode_changed.emit(value);
				plugin.reload();

class Persistence extends RefCounted:
	const CONFIG_SECTION_NAME := "Scene Graph";
	const SCENE_STATE_DIR := "res://.godot/scene_graphs";
	const EDITOR_STATE_FILE := "res://.godot/scene_graphs/editor_state.cfg";

	var plugin : EditorPlugin;
	
	var editor_data_cache : Dictionary = {};
	var scene_data_cache : Dictionary = {};
	var scene_runtime_cache : Dictionary = {};
	
	var _pending_scene_state : Dictionary;
	var _active_scene_identifier : String;
	
	func _init(plugin : EditorPlugin) -> void:
		self.plugin = plugin;
		plugin.scene_changed.connect(_on_scene_changed);
		plugin.scene_closed.connect(_on_scene_closed);
		plugin.scene_saved.connect(_on_scene_saved);
		plugin.editor_layout_saving.connect(_on_editor_layout_saving);
		plugin.editor_layout_loading.connect(_on_editor_layout_loading);
		plugin.plugin_enabled.connect(_on_plugin_enabled);
	
	func _on_scene_changed(scene_root : Node) -> void:
#		print("Scene changed: " + str(scene_root));
		var scene_state := _pending_scene_state;
		_pending_scene_state = {};
		
		var saved_scene_identifier : String = scene_state.get("scene_identifier", "");
		_active_scene_identifier = generate_scene_identifier(scene_root, saved_scene_identifier);
#		print("Active scene identifier: " + _active_scene_identifier + " (was saved as " + saved_scene_identifier + ")");
		
		var scene_data := get_scene_data(_active_scene_identifier, saved_scene_identifier);
#		print("Loaded scene data: " + str(scene_data));
		plugin._dock.set_scene_state(scene_data);
	
	func _on_scene_closed(filepath : String) -> void:
#		print("Scene closed: " + filepath);
		if filepath:
			var scene_identifier := generate_scene_identifier_from_path(filepath);
			scene_data_cache.erase(scene_identifier);
			scene_runtime_cache.erase(scene_identifier);
		pass;
	
	func _on_scene_saved(filepath : String) -> void:
#		print("Scene saved: " + filepath);
		if filepath:
			var scene_identifier := generate_scene_identifier_from_path(filepath);
			if scene_data_cache.has(scene_identifier):
				# There is data to save
				_save_scene_data(scene_identifier, scene_data_cache[scene_identifier]);
	
	func set_scene_state(state : Dictionary) -> void:
#		print("Set scene state: " + str(state));
		if state.has("scene_identifier"):
			_active_scene_identifier = state["scene_identifier"];
		_pending_scene_state = state;
	
	func get_scene_state() -> Dictionary:
		var state := {
			"scene_identifier": _active_scene_identifier
		};
		var scene_data : Dictionary = plugin._dock.get_scene_state();
		set_scene_data(_active_scene_identifier, scene_data);
#		print("Saving state: " + str(state));
		return state;
	
	func generate_scene_identifier(node : Node, prev_saved : String) -> String:
		if node == null:
			# empty
			if prev_saved.begins_with("empty-"):
				return prev_saved; # avoid generating a different random number for every time an empty scene is switched to.
			return "empty-%x" % [randi()];
		elif node.scene_file_path:
			# saved to scene
			return generate_scene_identifier_from_path(node.scene_file_path);
		else:
			# unsaved
			return "unsaved-%x" % [node.get_instance_id()];
	
	func generate_scene_identifier_from_path(scene_file_path : String) -> String:
		return "%s-%x" % [scene_file_path.get_file(), scene_file_path.hash()];
	
	func should_save_to_disk(scene_identifier : String) -> bool:
		return !(scene_identifier.begins_with("empty-") || scene_identifier.begins_with("unsaved-"));
	
	func get_scene_data_save_path(scene_identifier : String) -> String:
		if !should_save_to_disk(scene_identifier): return "";
		return SCENE_STATE_DIR.path_join(scene_identifier + "-scene_state.cfg");
	
	func _save_scene_data(scene_identifier : String, scene_data : Dictionary) -> void:
		var path := get_scene_data_save_path(scene_identifier);
		if !path: return;
		DirAccess.make_dir_recursive_absolute(path.get_base_dir());
		var config_file := ConfigFile.new();
		config_file.set_value(CONFIG_SECTION_NAME, "scene_data", scene_data);
#		print("Saved scene data to " + path + ": " + str(scene_data));
		var err := config_file.save(path);
		if err != OK:
			printerr("Failed to save to " + path + ": " + error_string(err));
	
	func get_scene_data(scene_identifier : String, fallback_scene_identifier : String) -> Dictionary:
		if !scene_identifier: return {}
		if scene_data_cache.has(scene_identifier):
			return {
				"serialized": scene_data_cache[scene_identifier],
				"runtime": scene_runtime_cache[scene_identifier],
			};
		if fallback_scene_identifier && scene_data_cache.has(fallback_scene_identifier):
			return {
				"serialized": scene_data_cache[fallback_scene_identifier],
				"runtime": scene_runtime_cache[fallback_scene_identifier],
			};
		var loaded := _load_scene_data(fallback_scene_identifier if fallback_scene_identifier else scene_identifier);
		scene_data_cache[scene_identifier] = loaded;
		scene_runtime_cache[scene_identifier] = null;
		return {
			"serialized": loaded,
			"runtime": null
		};
		
	func _load_scene_data(scene_identifier : String) -> Dictionary:
		var path := get_scene_data_save_path(scene_identifier);
		if !path: return {};
		var config_file := ConfigFile.new();
		if config_file.load(path) == OK:
			return config_file.get_value(CONFIG_SECTION_NAME, "scene_data", {});
		else:
			return {};
	
	func set_scene_data(scene_identifier : String, scene_data : Dictionary) -> void:
		if !scene_identifier: return;
		scene_data_cache[scene_identifier] = scene_data["serialized"];
		scene_runtime_cache[scene_identifier] = scene_data["runtime"];
	
	func _save_editor_data(editor_data : Dictionary) -> void:
		var path := EDITOR_STATE_FILE;
		DirAccess.make_dir_recursive_absolute(path.get_base_dir());
		var config_file := ConfigFile.new();
		config_file.set_value(CONFIG_SECTION_NAME, "editor_data", editor_data);
#		print("Saved editor data to " + path + ": " + str(editor_data));
		var err := config_file.save(path);
		if err != OK:
			printerr("Failed to save to " + path + ": " + error_string(err));
		
	func _load_editor_data() -> Dictionary:
		var path := EDITOR_STATE_FILE;
		if !path: return {};
		var config_file := ConfigFile.new();
		if config_file.load(path) == OK:
			return config_file.get_value(CONFIG_SECTION_NAME, "editor_data", {});
		else:
			return {};
	
	func get_editor_data() -> Dictionary:
		if editor_data_cache: return editor_data_cache;
		var loaded := _load_editor_data();
		editor_data_cache = loaded;
		return loaded;
	
	func _on_editor_layout_saving() -> void:
		editor_data_cache = plugin._dock.get_editor_state();
		_save_editor_data(editor_data_cache);
	
	func _on_editor_layout_loading() -> void:
		plugin._dock.set_editor_state(get_editor_data());
	
	func _on_plugin_enabled() -> void:
		_on_scene_changed(EditorInterface.get_edited_scene_root());
		_on_editor_layout_loading();