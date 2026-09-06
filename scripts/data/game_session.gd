class_name GameSession
extends RefCounted

signal puzzle_completed(puzzle_id: String)
signal enemy_defeated(enemy_id: String)
signal artifact_acquired(artifact_id: String)
signal crystal_acquired(crystal_id: String)
signal scene_changed(scene_id: String)

const SCENE_FOREST := "forest"
const SCENE_RUINS := "ruins"
const SCENE_HUB := "hub"
const VALID_SCENES := [SCENE_FOREST, SCENE_RUINS, SCENE_HUB]

const PUZZLE_ID := "forest_prism_array"
const ROBOT_ID := "forest_sentinel"
const ARTIFACT_ID := "forest_phase_gauntlet"
const LOCK_ID := "forest_resonant_lock"
const CRYSTAL_ID := "forest_memory_crystal"
const MEMORY_SHARD_ID := "forest_memory_shard_01"
const FLIGHT_MEMORY_SHARD_ID := "forest_flight_memory_01"

const MOVEMENT_ON_FOOT := "on_foot"
const MOVEMENT_SHIP := "ship"
const VALID_MOVEMENT_MODES := [MOVEMENT_ON_FOOT, MOVEMENT_SHIP]

const DEFAULT_SHIP_SCENE_ID := SCENE_FOREST
const DEFAULT_SHIP_POSITION := Vector3(-5.6, 0.08, 14.0)
const DEFAULT_SHIP_YAW := PI - 0.35
const DEFAULT_SHIP_ROTATION := Vector3(0.0, DEFAULT_SHIP_YAW, 0.0)

const MAX_HEALTH := 100.0
const MAX_HINT_ELAPSED := 86400.0
const MAX_MEMORY_SHARDS := 256
const MAX_ID_LENGTH := 64
const MAX_TRANSFORM_COMPONENT := 1000000.0

var scene_id: String = SCENE_FOREST
var player_position := Vector3.ZERO
var player_rotation := Vector3.ZERO
var puzzle_solved := false
var robot_defeated := false
var artifact_collected := false
var lock_open := false
var crystal_collected := false
var prism_orientations: Array[int] = [0, 0, 0]
var hint_elapsed := 0.0
var hint_level := 0
var visited_scenes: Array[String] = [SCENE_FOREST]
var memory_shards: Array[String] = []
var health := MAX_HEALTH
var movement_mode := MOVEMENT_ON_FOOT
var ship_scene_id := DEFAULT_SHIP_SCENE_ID
var ship_position := DEFAULT_SHIP_POSITION
var ship_rotation := DEFAULT_SHIP_ROTATION
var ship_landed := true
var ship_last_landed_position := DEFAULT_SHIP_POSITION
var ship_last_landed_yaw := DEFAULT_SHIP_YAW


func _init() -> void:
	new_game()


func new_game() -> void:
	scene_id = SCENE_FOREST
	player_position = Vector3.ZERO
	player_rotation = Vector3.ZERO
	puzzle_solved = false
	robot_defeated = false
	artifact_collected = false
	lock_open = false
	crystal_collected = false
	prism_orientations.assign([0, 0, 0])
	hint_elapsed = 0.0
	hint_level = 0
	visited_scenes.assign([SCENE_FOREST])
	memory_shards.clear()
	health = MAX_HEALTH
	movement_mode = MOVEMENT_ON_FOOT
	ship_scene_id = DEFAULT_SHIP_SCENE_ID
	ship_position = DEFAULT_SHIP_POSITION
	ship_rotation = DEFAULT_SHIP_ROTATION
	ship_landed = true
	ship_last_landed_position = DEFAULT_SHIP_POSITION
	ship_last_landed_yaw = DEFAULT_SHIP_YAW


func to_dict() -> Dictionary:
	return {
		"scene_id": scene_id,
		"player": {
			"position": [player_position.x, player_position.y, player_position.z],
			"rotation": [player_rotation.x, player_rotation.y, player_rotation.z],
		},
		"flags": {
			"puzzle_solved": puzzle_solved,
			"robot_defeated": robot_defeated,
			"artifact_collected": artifact_collected,
			"lock_open": lock_open,
			"crystal_collected": crystal_collected,
		},
		"prism_orientations": prism_orientations.duplicate(),
		"hint": {"elapsed": hint_elapsed, "level": hint_level},
		"visited_scenes": visited_scenes.duplicate(),
		"memory_shards": memory_shards.duplicate(),
		"health": health,
		"movement_mode": movement_mode,
		"ship": {
			"scene_id": ship_scene_id,
			"position": [ship_position.x, ship_position.y, ship_position.z],
			"rotation": [ship_rotation.x, ship_rotation.y, ship_rotation.z],
			"landed": ship_landed,
			"last_landed_position": [
				ship_last_landed_position.x,
				ship_last_landed_position.y,
				ship_last_landed_position.z,
			],
			"last_landed_yaw": ship_last_landed_yaw,
		},
	}


## Restores only fully valid snapshots. A rejected dictionary never partially mutates state.
func restore(data: Dictionary) -> bool:
	var normalized := _normalize_snapshot(data)
	if normalized.is_empty():
		return false

	scene_id = normalized.scene_id
	player_position = normalized.player_position
	player_rotation = normalized.player_rotation
	puzzle_solved = normalized.puzzle_solved
	robot_defeated = normalized.robot_defeated
	artifact_collected = normalized.artifact_collected
	lock_open = normalized.lock_open
	crystal_collected = normalized.crystal_collected
	prism_orientations.assign(normalized.prism_orientations)
	hint_elapsed = normalized.hint_elapsed
	hint_level = normalized.hint_level
	visited_scenes.assign(normalized.visited_scenes)
	memory_shards.assign(normalized.memory_shards)
	health = normalized.health
	movement_mode = normalized.movement_mode
	ship_scene_id = normalized.ship_scene_id
	ship_position = normalized.ship_position
	ship_rotation = normalized.ship_rotation
	ship_landed = normalized.ship_landed
	ship_last_landed_position = normalized.ship_last_landed_position
	ship_last_landed_yaw = normalized.ship_last_landed_yaw
	return true


static func is_valid_snapshot(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return not _normalize_snapshot(data).is_empty()


## Upgrades an exact schema-v1 snapshot without changing any of its existing fields.
## An empty result means that the legacy snapshot was malformed.
static func migrate_v1_snapshot(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or _normalize_v1_snapshot(data).is_empty():
		return {}
	var migrated: Dictionary = data.duplicate(true)
	migrated["movement_mode"] = MOVEMENT_ON_FOOT
	migrated["ship"] = {
		"scene_id": DEFAULT_SHIP_SCENE_ID,
		"position": [DEFAULT_SHIP_POSITION.x, DEFAULT_SHIP_POSITION.y, DEFAULT_SHIP_POSITION.z],
		"rotation": [DEFAULT_SHIP_ROTATION.x, DEFAULT_SHIP_ROTATION.y, DEFAULT_SHIP_ROTATION.z],
		"landed": true,
		"last_landed_position": [
			DEFAULT_SHIP_POSITION.x,
			DEFAULT_SHIP_POSITION.y,
			DEFAULT_SHIP_POSITION.z,
		],
		"last_landed_yaw": DEFAULT_SHIP_YAW,
	}
	return migrated if is_valid_snapshot(migrated) else {}


func set_movement_mode(next_mode: String) -> bool:
	if next_mode not in VALID_MOVEMENT_MODES:
		return false
	if next_mode == MOVEMENT_SHIP and (ship_scene_id != scene_id or ship_landed):
		return false
	movement_mode = next_mode
	return true


## Replaces all ship persistence fields together, rejecting an invalid partial state.
func set_ship_state(
	next_scene_id: String,
	next_position: Vector3,
	next_rotation: Vector3,
	next_landed: bool,
	next_last_landed_position: Vector3,
	next_last_landed_yaw: float
) -> bool:
	var candidate := to_dict()
	candidate.ship = {
		"scene_id": next_scene_id,
		"position": [next_position.x, next_position.y, next_position.z],
		"rotation": [next_rotation.x, next_rotation.y, next_rotation.z],
		"landed": next_landed,
		"last_landed_position": [
			next_last_landed_position.x,
			next_last_landed_position.y,
			next_last_landed_position.z,
		],
		"last_landed_yaw": next_last_landed_yaw,
	}
	var normalized := _normalize_snapshot(candidate)
	if normalized.is_empty():
		return false
	ship_scene_id = normalized.ship_scene_id
	ship_position = normalized.ship_position
	ship_rotation = normalized.ship_rotation
	ship_landed = normalized.ship_landed
	ship_last_landed_position = normalized.ship_last_landed_position
	ship_last_landed_yaw = normalized.ship_last_landed_yaw
	return true


func set_prism_orientation(index: int, orientation: int) -> bool:
	if index < 0 or index >= prism_orientations.size() or orientation < 0 or orientation > 3:
		return false
	prism_orientations[index] = orientation
	return true


func set_hint_progress(elapsed: float, level: int) -> bool:
	if not is_finite(elapsed) or elapsed < 0.0 or elapsed > MAX_HINT_ELAPSED:
		return false
	if level < 0 or level > 3:
		return false
	hint_elapsed = elapsed
	hint_level = level
	return true


func mark_puzzle_solved() -> bool:
	if puzzle_solved:
		return false
	puzzle_solved = true
	puzzle_completed.emit(PUZZLE_ID)
	return true


func mark_robot_defeated() -> bool:
	if robot_defeated or not puzzle_solved:
		return false
	robot_defeated = true
	enemy_defeated.emit(ROBOT_ID)
	return true


func collect_artifact() -> bool:
	if artifact_collected or not puzzle_solved or not robot_defeated:
		return false
	artifact_collected = true
	artifact_acquired.emit(ARTIFACT_ID)
	return true


func open_resonant_lock() -> bool:
	if lock_open or not artifact_collected:
		return false
	lock_open = true
	return true


func collect_crystal() -> bool:
	if crystal_collected or not lock_open:
		return false
	crystal_collected = true
	crystal_acquired.emit(CRYSTAL_ID)
	return true


func collect_memory_shard(shard_id: String = MEMORY_SHARD_ID) -> bool:
	if not _is_stable_id(shard_id) or shard_id in memory_shards:
		return false
	if memory_shards.size() >= MAX_MEMORY_SHARDS:
		return false
	memory_shards.append(shard_id)
	return true


func travel_to(next_scene_id: String) -> bool:
	if movement_mode == MOVEMENT_SHIP:
		return false
	if next_scene_id not in VALID_SCENES:
		return false
	if next_scene_id == SCENE_RUINS and not crystal_collected:
		return false
	if scene_id == next_scene_id:
		return true
	scene_id = next_scene_id
	if next_scene_id not in visited_scenes:
		visited_scenes.append(next_scene_id)
	scene_changed.emit(next_scene_id)
	return true


## Moves the player and their one ship through a portal as one valid transaction.
func travel_ship_to(next_scene_id: String, launch_position: Vector3, launch_rotation: Vector3) -> bool:
	if movement_mode != MOVEMENT_SHIP or ship_scene_id != scene_id or ship_landed:
		return false
	if next_scene_id not in VALID_SCENES:
		return false
	if next_scene_id == SCENE_RUINS and not crystal_collected:
		return false
	var candidate := to_dict()
	candidate.scene_id = next_scene_id
	if next_scene_id not in candidate.visited_scenes:
		candidate.visited_scenes.append(next_scene_id)
	candidate.ship.scene_id = next_scene_id
	candidate.ship.position = [launch_position.x, launch_position.y, launch_position.z]
	candidate.ship.rotation = [launch_rotation.x, launch_rotation.y, launch_rotation.z]
	# The launch pose is the first safe recovery point in the destination.  The
	# schema intentionally has one last-landing transform for the personal ship.
	candidate.ship.last_landed_position = [launch_position.x, launch_position.y, launch_position.z]
	candidate.ship.last_landed_yaw = launch_rotation.y
	var normalized := _normalize_snapshot(candidate)
	if normalized.is_empty():
		return false
	var changed_scene := scene_id != next_scene_id
	scene_id = normalized.scene_id
	visited_scenes.assign(normalized.visited_scenes)
	ship_scene_id = normalized.ship_scene_id
	ship_position = normalized.ship_position
	ship_rotation = normalized.ship_rotation
	ship_last_landed_position = normalized.ship_last_landed_position
	ship_last_landed_yaw = normalized.ship_last_landed_yaw
	if changed_scene:
		scene_changed.emit(next_scene_id)
	return true


static func _normalize_snapshot(data: Dictionary) -> Dictionary:
	if not _has_exact_keys(data, [
		"scene_id", "player", "flags", "prism_orientations", "hint",
		"visited_scenes", "memory_shards", "health", "movement_mode", "ship"
	]):
		return {}
	var normalized := _normalize_common_snapshot(data)
	if normalized.is_empty():
		return {}

	var saved_movement_mode: Variant = data.movement_mode
	if typeof(saved_movement_mode) != TYPE_STRING or saved_movement_mode not in VALID_MOVEMENT_MODES:
		return {}
	var ship: Variant = data.ship
	if typeof(ship) != TYPE_DICTIONARY or not _has_exact_keys(ship, [
		"scene_id", "position", "rotation", "landed", "last_landed_position", "last_landed_yaw"
	]):
		return {}
	var saved_ship_scene: Variant = ship.scene_id
	if (
		typeof(saved_ship_scene) != TYPE_STRING
		or saved_ship_scene not in VALID_SCENES
		or saved_ship_scene not in normalized.visited_scenes
	):
		return {}
	var saved_ship_position: Variant = _parse_vector3(ship.position)
	var saved_ship_rotation: Variant = _parse_ship_rotation(ship.rotation)
	var saved_last_landed_position: Variant = _parse_vector3(ship.last_landed_position)
	var saved_last_landed_yaw: Variant = _parse_number(
		ship.last_landed_yaw, -MAX_TRANSFORM_COMPONENT, MAX_TRANSFORM_COMPONENT
	)
	if (
		saved_ship_position == null
		or saved_ship_rotation == null
		or typeof(ship.landed) != TYPE_BOOL
		or saved_last_landed_position == null
		or saved_last_landed_yaw == null
	):
		return {}
	if saved_movement_mode == MOVEMENT_SHIP and (saved_ship_scene != normalized.scene_id or ship.landed):
		return {}

	normalized["movement_mode"] = saved_movement_mode
	normalized["ship_scene_id"] = saved_ship_scene
	normalized["ship_position"] = saved_ship_position
	normalized["ship_rotation"] = saved_ship_rotation
	normalized["ship_landed"] = ship.landed
	normalized["ship_last_landed_position"] = saved_last_landed_position
	normalized["ship_last_landed_yaw"] = saved_last_landed_yaw
	return normalized


static func _normalize_v1_snapshot(data: Dictionary) -> Dictionary:
	if not _has_exact_keys(data, [
		"scene_id", "player", "flags", "prism_orientations", "hint",
		"visited_scenes", "memory_shards", "health"
	]):
		return {}
	return _normalize_common_snapshot(data)


static func _normalize_common_snapshot(data: Dictionary) -> Dictionary:

	var saved_scene: Variant = data.scene_id
	if typeof(saved_scene) != TYPE_STRING or saved_scene not in VALID_SCENES:
		return {}

	var player: Variant = data.player
	if typeof(player) != TYPE_DICTIONARY or not _has_exact_keys(player, ["position", "rotation"]):
		return {}
	var saved_position: Variant = _parse_vector3(player.position)
	var saved_rotation: Variant = _parse_vector3(player.rotation)
	if saved_position == null or saved_rotation == null:
		return {}

	var flags: Variant = data.flags
	var flag_names := [
		"puzzle_solved", "robot_defeated", "artifact_collected", "lock_open", "crystal_collected"
	]
	if typeof(flags) != TYPE_DICTIONARY or not _has_exact_keys(flags, flag_names):
		return {}
	for flag_name: String in flag_names:
		if typeof(flags[flag_name]) != TYPE_BOOL:
			return {}
	if flags.robot_defeated and not flags.puzzle_solved:
		return {}
	if flags.artifact_collected and not flags.robot_defeated:
		return {}
	if flags.lock_open and not flags.artifact_collected:
		return {}
	if flags.crystal_collected and not flags.lock_open:
		return {}
	if saved_scene == SCENE_RUINS and not flags.crystal_collected:
		return {}

	var orientations: Variant = data.prism_orientations
	if typeof(orientations) != TYPE_ARRAY or orientations.size() != 3:
		return {}
	var saved_orientations: Array[int] = []
	for orientation: Variant in orientations:
		var parsed_orientation: Variant = _parse_integer(orientation, 0, 3)
		if parsed_orientation == null:
			return {}
		saved_orientations.append(parsed_orientation)

	var hint: Variant = data.hint
	if typeof(hint) != TYPE_DICTIONARY or not _has_exact_keys(hint, ["elapsed", "level"]):
		return {}
	var saved_elapsed: Variant = _parse_number(hint.elapsed, 0.0, MAX_HINT_ELAPSED)
	var saved_hint_level: Variant = _parse_integer(hint.level, 0, 3)
	if saved_elapsed == null or saved_hint_level == null:
		return {}

	var saved_visited: Variant = _parse_string_array(data.visited_scenes, VALID_SCENES.size(), true)
	if saved_visited == null or SCENE_FOREST not in saved_visited or saved_scene not in saved_visited:
		return {}
	var saved_shards: Variant = _parse_string_array(data.memory_shards, MAX_MEMORY_SHARDS, false)
	if saved_shards == null:
		return {}

	var saved_health: Variant = _parse_number(data.health, 0.0, MAX_HEALTH)
	if saved_health == null:
		return {}

	return {
		"scene_id": saved_scene,
		"player_position": saved_position,
		"player_rotation": saved_rotation,
		"puzzle_solved": flags.puzzle_solved,
		"robot_defeated": flags.robot_defeated,
		"artifact_collected": flags.artifact_collected,
		"lock_open": flags.lock_open,
		"crystal_collected": flags.crystal_collected,
		"prism_orientations": saved_orientations,
		"hint_elapsed": saved_elapsed,
		"hint_level": saved_hint_level,
		"visited_scenes": saved_visited,
		"memory_shards": saved_shards,
		"health": saved_health,
	}


static func _has_exact_keys(data: Dictionary, expected: Array) -> bool:
	if data.size() != expected.size():
		return false
	for key: String in expected:
		if not data.has(key):
			return false
	return true


static func _parse_vector3(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return null
	var components: Array[float] = []
	for component: Variant in value:
		var parsed: Variant = _parse_number(component, -MAX_TRANSFORM_COMPONENT, MAX_TRANSFORM_COMPONENT)
		if parsed == null:
			return null
		components.append(parsed)
	return Vector3(components[0], components[1], components[2])


static func _parse_ship_rotation(value: Variant) -> Variant:
	var parsed: Variant = _parse_vector3(value)
	if parsed == null or parsed.x < -PI / 2.0 or parsed.x > PI / 2.0 or not is_zero_approx(parsed.z):
		return null
	return parsed


static func _parse_number(value: Variant, minimum: float, maximum: float) -> Variant:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return null
	var parsed := float(value)
	if not is_finite(parsed) or parsed < minimum or parsed > maximum:
		return null
	return parsed


static func _parse_integer(value: Variant, minimum: int, maximum: int) -> Variant:
	var parsed: Variant = _parse_number(value, minimum, maximum)
	if parsed == null or parsed != floor(parsed):
		return null
	return int(parsed)


static func _parse_string_array(value: Variant, maximum_size: int, scene_ids_only: bool) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() > maximum_size:
		return null
	var parsed: Array[String] = []
	for item: Variant in value:
		if typeof(item) != TYPE_STRING:
			return null
		if scene_ids_only:
			if item not in VALID_SCENES:
				return null
		elif not _is_stable_id(item):
			return null
		if item in parsed:
			return null
		parsed.append(item)
	return parsed


static func _is_stable_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_LENGTH:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var is_lowercase := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_lowercase and not is_digit and code != 95:
			return false
	return true
