class_name PuzzleDefinition
extends Resource

@export var id := ""
@export var dimension_id := ""
@export var target_orientations: Array[int] = [0, 0, 0]
@export var hint_delay_seconds := 45.0
@export var hint_steps: Array[String] = []


func is_valid() -> bool:
	if not _is_stable_id(id) or not _is_stable_id(dimension_id):
		return false
	if target_orientations.size() != 3:
		return false
	for orientation: int in target_orientations:
		if orientation < 0 or orientation > 3:
			return false
	if not is_finite(hint_delay_seconds) or hint_delay_seconds < 0.0 or hint_delay_seconds > 3600.0:
		return false
	if hint_steps.size() > 3:
		return false
	for step: String in hint_steps:
		if step.strip_edges().is_empty() or step.length() > 240:
			return false
	return true


static func _is_stable_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true
