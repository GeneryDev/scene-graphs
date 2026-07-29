class_name SignalOneShotGraphNode
extends GraphNode

func setup(saved_data : Dictionary, editor : SignalGraphEditor) -> bool:
	title = "One-Shot";
	add_child(Label.new());
	set_slot(
		0,
		true,
		editor.port_type(&"signal"),
		Color.WHITE,
		true,
		editor.port_type(&"signal"),
		Color.WHITE
		);
	
	if saved_data:
		position_offset = saved_data["position_offset"] as Vector2;
	else:
		position_offset = Vector2.ZERO;
	
	return true;

func get_save_data() -> Dictionary:
	var dict := {};
	dict["position_offset"] = position_offset;
	return dict;