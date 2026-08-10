extends GraphNode

var object_type : String;
var obj : Object;

var editor : SignalGraphEditor;
var _member_cache : Dictionary = {};
var user_size : Vector2;

var _last_built_view : Dictionary = {};
var _building_from_view := false;

func _init(object_type : String, obj : Object, editor : SignalGraphEditor):
	self.editor = editor;
	self.object_type = object_type;
	self.obj = obj;
	resizable = true;
	custom_minimum_size = Vector2(120, 0);
	
	title = obj.name if obj is Node else (obj.resource_name if obj is Resource else str(obj));
	
	var icon := SignalGraphEditor.Utility.get_object_icon(obj);
	if icon:
		var icon_rect := TextureRect.new();
		icon_rect.texture = icon;
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
		get_titlebar_hbox().add_child(icon_rect, INTERNAL_MODE_FRONT);
		get_titlebar_hbox().move_child(icon_rect, 0);
		get_titlebar_hbox().add_theme_constant_override("separation", 8);
	
	_member_cache.clear();
	
	for hook in editor.hooks.initialize_object_graph_node:
		hook.initialize_object_graph_node(self);
	
	position_offset_changed.connect(_on_position_offset_changed);
	resize_end.connect(_on_resize_end);

func get_object() -> Object:
	return obj;

func update_from_view() -> void:
	_building_from_view = true;
	var obj := get_object();
	var obj_view := editor.current_view.get_object_view(object_type, obj);
	
	if obj_view.has("position_offset"):
		position_offset = obj_view["position_offset"] as Vector2;
	
	if obj_view.has("user_size"):
		user_size = obj_view["user_size"] as Vector2;
	
	if !_last_built_view.recursive_equal(obj_view, 3):
		_last_built_view = obj_view.duplicate(true);
		rebuild_contents_from_view();
	
	reset_to_user_size();
	_building_from_view = false;
	
func update_view() -> void:
	if _building_from_view: return;
	var obj := get_object();
	var obj_view := editor.current_view.get_object_view(object_type, obj);
	if !obj_view: return;
	
	obj_view["position_offset"] = position_offset;
	obj_view["user_size"] = user_size;
	
func rebuild_contents_from_view() -> void:
	clear_all_slots();
	_member_cache.clear();
	for child in get_children():
		remove_child(child)
		child.queue_free();
	
	create_and_add_contents();
	reset_to_user_size();

func reset_to_user_size() -> void:
	reset_size();
	var size = self.size;
	var snapping_distance := editor.snapping_distance;
	size = Vector2(ceil(size.x / snapping_distance)*snapping_distance,ceil(size.y / snapping_distance)*snapping_distance);
	self.size = size.max(user_size);

func create_and_add_contents() -> void:
	var slots_to_add : Array[Dictionary]= [];
	for hook in editor.hooks.create_object_graph_node_slots:
		var slots_from_hook : Array[Dictionary] = hook.create_object_graph_node_slots(self);
		for slot in slots_from_hook:
			var sort_key : int = slot.get("sort_key", 0);
			var insertion_index : int;
			# insert into slots_to_add already sorted
			if slots_to_add.is_empty():
				insertion_index = 0;
			elif slots_to_add[slots_to_add.size()-1].get("sort_key", 0) <= sort_key:
				insertion_index = slots_to_add.size();
			elif slots_to_add[0].get("sort_key", 0) > sort_key:
				insertion_index = 0;
			else:
				insertion_index = slots_to_add.rfind_custom(func (s : Dictionary) -> bool:
					return s.get("sort_key", 0) <= sort_key;
				) + 1;
			slots_to_add.insert(insertion_index, slot);
	
	var left_port_index := 0;
	var right_port_index := 0;
	
	for slot in slots_to_add:
		var slot_index := get_child_count();
		var control : Control = slot.control;
		var left_port : Dictionary = slot.get("left_port",{});
		var right_port : Dictionary = slot.get("right_port",{});
		add_child(control);
		set_slot(slot_index,
			!left_port.is_empty(),
			left_port.get("port_type",-1),
			left_port.get("port_color",Color.WHITE),
			!right_port.is_empty(),
			right_port.get("port_type",-1),
			right_port.get("port_color",Color.WHITE)
			);
		if left_port:
			if left_port.has("member"):
				_add_member_to_cache(left_port.member.member_type, left_port.member.member_name, slot_index, left_port_index);
			left_port_index += 1;
		if right_port:
			if right_port.has("member"):
				_add_member_to_cache(right_port.member.member_type, right_port.member.member_name, slot_index, right_port_index);
			right_port_index += 1;

func _add_member_to_cache(member_type : String, member_name : StringName, slot_id : int, port_id : int) -> void:
	_member_cache.get_or_add(member_type, {})[member_name] = {
		"member_type": member_type,
		"member_name": member_name,
		"slot_id": slot_id,
		"port_id": port_id
	};

func get_member_cache(member_type : String, member_name : StringName) -> Dictionary:
	return _member_cache.get(member_type, {}).get(member_name, {});

func get_member_port_id(member_type : String, member_name : StringName) -> int:
	return get_member_cache(member_type, member_name).get("port_id", -1);

func get_member_slot_id(member_type : String, member_name : StringName) -> int:
	return get_member_cache(member_type, member_name).get("slot_id", -1);

func get_member_from_port_id(member_type : String, port_id : int) -> Dictionary:
	if !_member_cache.has(member_type): return {};
	for member_name in _member_cache[member_type]:
		var member : Dictionary = _member_cache[member_type][member_name];
		if member["port_id"] == port_id:
			return member;
	return {};

func get_member_from_slot_id(member_type : String, slot_id : int) -> Dictionary:
	if !_member_cache.has(member_type): return {};
	for member_name in _member_cache[member_type]:
		var member : Dictionary = _member_cache[member_type][member_name];
		if member["slot_id"] == slot_id:
			return member;
	return {};

func _on_position_offset_changed() -> void:
	update_view();

func _on_resize_end(new_size : Vector2) -> void:
	user_size = new_size;
	update_view();
	
func _draw_port(slot_index: int, position: Vector2i, left: bool, color: Color) -> void:
	var drawn := false;
	for hook in editor.hooks.draw_object_graph_node_port:
		if hook.draw_object_graph_node_port(self, slot_index, position, left, color):
			drawn = true;
			break;
	
	if !drawn:
		# default drawing
		var port_icon := get_slot_custom_icon_left(slot_index) if left else get_slot_custom_icon_right(slot_index);
		if !port_icon:
			port_icon = get_theme_icon("port");
			
		if !port_icon:
			return;
	
		var icon_offset : Vector2;
		icon_offset = -port_icon.get_size() * 0.5;
		draw_texture(port_icon, Vector2(position) + icon_offset, color);