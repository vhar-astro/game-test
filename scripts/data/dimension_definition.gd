class_name DimensionDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
@export var gravity_scale := 1.0
@export var order := 0
@export var required_crystal_id := ""


func is_valid() -> bool:
	return (
		_is_stable_id(id)
		and not display_name.strip_edges().is_empty()
		and scene_path.begins_with("res://")
		and scene_path.ends_with(".tscn")
		and is_finite(gravity_scale)
		and gravity_scale > 0.0
		and gravity_scale <= 10.0
		and order >= 0
		and (required_crystal_id.is_empty() or _is_stable_id(required_crystal_id))
	)


static func _is_stable_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true
