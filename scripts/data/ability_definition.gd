class_name AbilityDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var source_artifact_id := ""
@export_range(0.0, 120.0, 0.1, "or_greater") var cooldown_seconds := 0.0
@export_range(1, 4, 1) var input_slot := 1


func is_valid() -> bool:
	return (
		_is_stable_id(id)
		and _is_stable_id(source_artifact_id)
		and not display_name.strip_edges().is_empty()
		and display_name.length() <= 80
		and description.length() <= 400
		and is_finite(cooldown_seconds)
		and cooldown_seconds >= 0.0
		and cooldown_seconds <= 120.0
		and input_slot >= 1
		and input_slot <= 4
	)


static func _is_stable_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true
