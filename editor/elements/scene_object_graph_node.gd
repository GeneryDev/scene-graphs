extends GraphNode

const PORT_COLOR_WILDCARD := Color(0xe0e0e0ff)

var object_type: String
var obj: Object
var editor: SceneGraphEditor
var user_size: Vector2
var _member_cache: Dictionary = { }
var _last_built_view: Dictionary = { }
var _building_from_view := false
var _custom_titlebar: Control
var _custom_titlebar_stylebox: StyleBox
var _custom_titlebar_selected_stylebox: StyleBox
var _custom_titlebar_wildcard_port_icon: Texture2D
var _custom_titlebar_wildcard_ports: Array[TextureRect]


func _init(object_type: String, obj: Object, editor: SceneGraphEditor):
	self.editor = editor
	self.object_type = object_type
	self.obj = obj
	resizable = true
	custom_minimum_size = Vector2(120, 0)
	theme = load("res://addons/scene-graphs/themes/scene_object_graph_node_theme.tres")
	get_titlebar_hbox().visible = false
	get_titlebar_hbox().get_child(0).visible = false
	get_titlebar_hbox().custom_minimum_size = Vector2.ZERO

	title = obj.name if obj is Node else (obj.resource_name if obj is Resource else str(obj))

	var icon := SceneGraphEditor.Utility.get_object_icon(obj)
	if icon:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	_build_custom_titlebar()

	for hook in editor.hooks.initialize_object_graph_node:
		hook.initialize_object_graph_node(self)

	node_selected.connect(_update_titlebar)
	node_deselected.connect(_update_titlebar)
	position_offset_changed.connect(_on_position_offset_changed)
	resize_end.connect(_on_resize_end)
	tree_entered.connect(_on_theme_changed)


func get_object() -> Object:
	return obj


func get_object_type() -> String:
	return object_type


func get_object_key() -> Variant:
	return editor.current_view.view_object_to_object_key(object_type, get_object())


func get_object_view() -> Dictionary:
	return editor.current_view.get_object_view(object_type, get_object())


func get_object_name() -> String:
	return obj.name if obj is Node else (obj.resource_name if obj is Resource else str(obj))


func update_from_view() -> void:
	_building_from_view = true
	var obj_view := get_object_view()

	if obj_view.has("position_offset"):
		position_offset = obj_view["position_offset"] as Vector2
	else:
		position_offset = Vector2.ZERO
		editor.queue_arrange(self)

	if obj_view.has("user_size"):
		user_size = obj_view["user_size"] as Vector2

	if !_last_built_view.recursive_equal(obj_view, 3):
		_last_built_view = obj_view.duplicate(true)
		rebuild_contents_from_view()

	reset_to_user_size()
	_building_from_view = false


func update_view() -> void:
	if _building_from_view:
		return
	var obj_view := get_object_view()
	if !obj_view:
		return

	obj_view["position_offset"] = position_offset
	obj_view["user_size"] = user_size


func reset_to_user_size() -> void:
	reset_size()
	var size = self.size
	var snapping_distance := editor.snapping_distance
	size = Vector2(ceil(size.x / snapping_distance) * snapping_distance, ceil(size.y / snapping_distance) * snapping_distance)
	self.size = size.max(user_size)


func rebuild_contents_from_view() -> void:
	clear_all_slots()
	_member_cache.clear()
	for child in get_children():
		if child == _custom_titlebar:
			continue
		remove_child(child)
		child.queue_free()

	create_and_add_contents()
	reset_to_user_size()


func claim_object_graph_node_member_slot(hook: Object, member_type: String, member_name: StringName) -> bool:
	var highest_bid: float = 0
	var matching_bid: float = 0
	for other_hook in editor.hooks.claim_object_graph_node_member_slots:
		var bid: float = other_hook.get_object_graph_node_member_slot_bid(object_type, get_object(), member_type, member_name)
		if bid > highest_bid:
			highest_bid = bid
		if other_hook == hook:
			matching_bid = bid
	return matching_bid == highest_bid


func create_and_add_contents() -> void:
	if _custom_titlebar != null:
		_set_custom_titlebar_slot()

	var slots_to_add: Array[Dictionary] = []
	for hook in editor.hooks.create_object_graph_node_slots:
		var slots_from_hook: Array[Dictionary] = hook.create_object_graph_node_slots(self)
		for slot in slots_from_hook:
			var sort_key: int = slot.get("sort_key", 0)
			var insertion_index: int
			# insert into slots_to_add already sorted
			if slots_to_add.is_empty():
				insertion_index = 0
			elif slots_to_add[slots_to_add.size() - 1].get("sort_key", 0) <= sort_key:
				insertion_index = slots_to_add.size()
			elif slots_to_add[0].get("sort_key", 0) > sort_key:
				insertion_index = 0
			else:
				insertion_index = slots_to_add.rfind_custom(
					func(s: Dictionary) -> bool:
						return s.get("sort_key", 0) <= sort_key
				) + 1
			slots_to_add.insert(insertion_index, slot)

	var left_port_index := 0
	var right_port_index := 0
	if _custom_titlebar != null:
		left_port_index += 1
		right_port_index += 1

	for slot in slots_to_add:
		var slot_index := get_child_count()
		var control: Control = slot.control
		var left_port: Dictionary = slot.get("left_port", { })
		var right_port: Dictionary = slot.get("right_port", { })
		add_child(control)
		set_slot(
			slot_index,
			!left_port.is_empty(),
			left_port.get("port_type", -1),
			left_port.get("port_color", Color.WHITE),
			!right_port.is_empty(),
			right_port.get("port_type", -1),
			right_port.get("port_color", Color.WHITE),
		)
		if slot.has("member"):
			_add_member_to_cache(slot.member.member_type, slot.member.member_name, slot_index, -1, "none")
		if left_port:
			set_slot_metadata_left(slot_index, left_port)
			if left_port.has("member"):
				_add_member_to_cache(left_port.member.member_type, left_port.member.member_name, slot_index, left_port_index, "left")
			left_port_index += 1
		if right_port:
			set_slot_metadata_right(slot_index, right_port)
			if right_port.has("member"):
				_add_member_to_cache(right_port.member.member_type, right_port.member.member_name, slot_index, right_port_index, "right")
			right_port_index += 1


func manage_members() -> void:
	editor.member_selector.show_multi_select(
		object_type,
		get_object(),
		editor.member_selector.get_all_member_types(),
		get_object_view().get("members"),
		editor.current_view.transactions.override_object_view_members,
	)


func get_member_port_id(member_type: String, member_name: StringName) -> int:
	return _get_member_cache(member_type, member_name).get("port_id", -1)


func get_member_slot_id(member_type: String, member_name: StringName) -> int:
	return _get_member_cache(member_type, member_name).get("slot_id", -1)


func get_member_from_port_id_and_type(port_id: int, member_type: String) -> Dictionary:
	if !_member_cache.has(member_type):
		return { }
	for member_name in _member_cache[member_type]:
		var member: Dictionary = _member_cache[member_type][member_name]
		if member["port_id"] == port_id:
			return member
	return { }


func get_member_from_port_id_and_side(port_id: int, side: String) -> Dictionary:
	for entry_member_type in _member_cache:
		for member_name in _member_cache[entry_member_type]:
			var member: Dictionary = _member_cache[entry_member_type][member_name]
			if member["port_id"] == port_id && member["port_side"] == side:
				return member
	return { }


func get_member_from_slot_id(slot_id: int, member_type: String) -> Dictionary:
	if !_member_cache.has(member_type):
		return { }
	for member_name in _member_cache[member_type]:
		var member: Dictionary = _member_cache[member_type][member_name]
		if member["slot_id"] == slot_id:
			return member
	return { }


func get_members_from_slot_id(slot_id: int) -> Array:
	var output := []
	for member_type in _member_cache:
		for member_name in _member_cache[member_type]:
			var member: Dictionary = _member_cache[member_type][member_name]
			if member["slot_id"] == slot_id:
				output.append(member)
	return output


func _build_custom_titlebar() -> void:
	var obj: Object = get_object()

	var slot := MarginContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(panel)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)
	var icon := SceneGraphEditor.Utility.get_object_icon(obj)
	if icon:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon_rect)
		hbox.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = get_object_name()
	label.theme_type_variation = &"GraphNodeTitleLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)

	var edit_button := Button.new()
	edit_button.theme_type_variation = &"FlatMenuButton"
	edit_button.icon = EditorInterface.get_editor_theme().get_icon(&"Edit", &"EditorIcons")
	edit_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit_button.pressed.connect(manage_members)
	edit_button.tooltip_text = "Manage Members"
	hbox.add_child(edit_button)

	var overlays := Control.new()
	overlays.mouse_filter = MOUSE_FILTER_IGNORE
	slot.add_child(overlays)
	var wildcard_port_left := _create_wildcard_port_control()
	wildcard_port_left.anchor_left = 0
	wildcard_port_left.anchor_right = 0
	wildcard_port_left.offset_left = -1
	wildcard_port_left.offset_right = -1
	var wildcard_port_right := _create_wildcard_port_control()
	wildcard_port_right.anchor_left = 1
	wildcard_port_right.anchor_right = 1
	wildcard_port_right.offset_left = 1
	wildcard_port_right.offset_right = 1
	overlays.add_child(wildcard_port_left)
	overlays.add_child(wildcard_port_right)

	_custom_titlebar = slot

	add_child(_custom_titlebar)


func _create_wildcard_port_control() -> TextureRect:
	var control := TextureRect.new()
	control.self_modulate = PORT_COLOR_WILDCARD
	control.mouse_filter = MOUSE_FILTER_IGNORE
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.grow_horizontal = GROW_DIRECTION_BOTH
	control.grow_vertical = GROW_DIRECTION_BOTH
	_custom_titlebar_wildcard_ports.append(control)
	return control


func _set_custom_titlebar_slot() -> void:
	set_slot(
		0,
		true,
		editor.port_type(&"wildcard_in"),
		PORT_COLOR_WILDCARD,
		true,
		editor.port_type(&"wildcard_out"),
		PORT_COLOR_WILDCARD,
		get_theme_icon("empty"),
		get_theme_icon("empty"),
		false,
	)


func _add_member_to_cache(member_type: String, member_name: StringName, slot_id: int, port_id: int, port_side: String) -> void:
	_member_cache.get_or_add(member_type, { })[member_name] = {
		"member_type": member_type,
		"member_name": member_name,
		"slot_id": slot_id,
		"port_id": port_id,
		"port_side": port_side,
	}


func _get_member_cache(member_type: String, member_name: StringName) -> Dictionary:
	return _member_cache.get(member_type, { }).get(member_name, { })


func _update_titlebar() -> void:
	(_custom_titlebar.get_child(0) as PanelContainer).add_theme_stylebox_override("panel", _custom_titlebar_selected_stylebox if selected else _custom_titlebar_stylebox)
	for port_texture_rect in _custom_titlebar_wildcard_ports:
		port_texture_rect.texture = _custom_titlebar_wildcard_port_icon


func _on_theme_changed() -> void:
	_custom_titlebar_stylebox = get_theme_stylebox("titlebar_custom")
	_custom_titlebar_selected_stylebox = get_theme_stylebox("titlebar_custom_selected")
	_custom_titlebar_wildcard_port_icon = get_theme_icon("wildcard_port")
	if _custom_titlebar_wildcard_port_icon is DPITexture:
		_custom_titlebar_wildcard_port_icon.set_size_override(Vector2i.ONE * get_theme_constant("wildcard_port_size"))
	_update_titlebar()


func _on_position_offset_changed() -> void:
	update_view()


func _on_resize_end(new_size: Vector2) -> void:
	user_size = new_size
	update_view()


func _draw_port(slot_index: int, position: Vector2i, left: bool, color: Color) -> void:
	var drawn := false
	for hook in editor.hooks.draw_object_graph_node_port:
		if hook.draw_object_graph_node_port(self, slot_index, position, left, color):
			drawn = true
			break

	if !drawn:
		# default drawing
		var port_icon := get_slot_custom_icon_left(slot_index) if left else get_slot_custom_icon_right(slot_index)
		if !port_icon:
			port_icon = get_theme_icon("port")

		if !port_icon:
			return

		var icon_offset: Vector2
		icon_offset = -port_icon.get_size() * 0.5
		draw_texture(port_icon, Vector2(position) + icon_offset, color)
