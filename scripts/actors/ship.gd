class_name ExplorerShip
extends CharacterBody3D
## A collision-aware explorer craft.  World orchestration (boarding, UI and
## persistence) deliberately lives in InfinityGame rather than this actor.

const HULL_SIZE := Vector3(6.6, 3.2, 6.4)
const HULL_CENTER_Y := 1.6
const LANDING_HALF_WIDTH := 3.0
const LANDING_HALF_LENGTH := 2.9
const LANDING_MAX_DROP := 12.0
const LANDING_MAX_SLOPE_DOT := 0.9902681 # cos(8 degrees)
const LANDING_HEIGHT_TOLERANCE := 0.25
const EXIT_RADIUS := 0.35
const EXIT_HEIGHT := 1.8
const EXIT_CLEARANCE := 0.03
const SHIP_LAYER_MASK := 1 | 4

@export_group("Flight")
@export var input_enabled := false
@export var piloted := false
@export var landed := true
@export var flight_yaw := 0.0
@export_range(-60.0, 60.0, 0.5, "radians_as_degrees") var flight_pitch := 0.0
@export var speed := 16.0

@export_group("Camera")
@export_range(0.001, 0.03, 0.001) var mouse_sensitivity := 0.008
@export var invert_y := false
@export_range(60.0, 70.0, 0.5) var camera_fov := 65.0

@onready var camera: Camera3D = %Camera
@onready var _camera_pitch: Node3D = %CameraPitch
@onready var _spring_arm: SpringArm3D = %SpringArm
@onready var _visual: Node3D = %Visual

var _visual_bank := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 16
	collision_mask = SHIP_LAYER_MASK
	if camera:
		camera.fov = camera_fov
	if _spring_arm:
		_spring_arm.add_excluded_object(get_rid())
	set_view(flight_yaw, flight_pitch)
	_update_visual(0.0)
	if input_enabled and piloted:
		_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not piloted:
		return
	if event is InputEventMouseButton and event.pressed:
		_capture_mouse()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.screen_relative
		if motion.is_zero_approx(): motion = event.relative
		var vertical_sign := -1.0 if invert_y else 1.0
		set_view(
			flight_yaw - motion.x * mouse_sensitivity,
			flight_pitch - motion.y * mouse_sensitivity * vertical_sign
		)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not input_enabled or not piloted or landed:
		velocity = Vector3.ZERO
		_visual_bank = move_toward(_visual_bank, 0.0, delta * 2.8)
		_update_visual(delta)
		return
	var forward_input := _action_strength(&"move_forward") - _action_strength(&"move_back")
	var strafe_input := _action_strength(&"move_right") - _action_strength(&"move_left")
	var rise_input := _action_strength(&"jump") - _action_strength(&"ship_descend")
	var direction := _flight_forward() * forward_input
	direction += _yaw_basis() * Vector3.RIGHT * strafe_input
	direction += Vector3.UP * rise_input
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()
	_visual_bank = move_toward(_visual_bank, deg_to_rad(-10.0) * strafe_input, delta * 5.5)
	_update_visual(delta)


func set_view(yaw: float, pitch: float) -> void:
	flight_yaw = yaw
	flight_pitch = clampf(pitch, deg_to_rad(-60.0), deg_to_rad(60.0))
	rotation = Vector3(0.0, flight_yaw, 0.0)
	if _camera_pitch:
		_camera_pitch.rotation.x = -.18 + flight_pitch * 0.45
	_update_visual(0.0)


func set_pose(at_position: Vector3, at_rotation: Vector3, is_landed: bool) -> void:
	global_position = at_position
	landed = is_landed
	velocity = Vector3.ZERO
	set_view(at_rotation.y, 0.0 if is_landed else at_rotation.x)
	if is_landed:
		_visual_bank = 0.0
		_update_visual(0.0)


func set_piloted(value: bool) -> void:
	piloted = value
	input_enabled = value
	velocity = Vector3.ZERO
	if value:
		_capture_mouse()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func attempt_takeoff(exclude_rids: Array[RID] = []) -> Dictionary:
	if not landed:
		return _result(false, "takeoff_not_landed")
	var excludes := _query_excludes(exclude_rids)
	var source := Transform3D(_yaw_basis(), global_position + Vector3.UP * (HULL_CENTER_Y + 0.08))
	if not _motion_is_clear(source, Vector3.UP * 3.42, excludes):
		return _result(false, "takeoff_blocked")
	var next_position := global_position + Vector3.UP * 3.5
	if not _hull_is_clear(next_position, excludes):
		return _result(false, "takeoff_blocked")
	var result := _result(true, "")
	result.position = next_position
	result.rotation = Vector3(0.0, flight_yaw, 0.0)
	return result


func landing_candidate(exclude_rids: Array[RID] = []) -> Dictionary:
	var excludes := _query_excludes(exclude_rids)
	var state := get_world_3d().direct_space_state
	var supports: Array[Dictionary] = []
	var points := [
		Vector3.ZERO,
		Vector3(-LANDING_HALF_WIDTH, 0.0, -LANDING_HALF_LENGTH),
		Vector3(LANDING_HALF_WIDTH, 0.0, -LANDING_HALF_LENGTH),
		Vector3(-LANDING_HALF_WIDTH, 0.0, LANDING_HALF_LENGTH),
		Vector3(LANDING_HALF_WIDTH, 0.0, LANDING_HALF_LENGTH),
	]
	for local_point: Vector3 in points:
		var world_point := global_position + _yaw_basis() * local_point + Vector3.UP * 0.05
		var ray := PhysicsRayQueryParameters3D.create(
			world_point, world_point + Vector3.DOWN * LANDING_MAX_DROP, SHIP_LAYER_MASK, excludes)
		var hit := state.intersect_ray(ray)
		if hit.is_empty():
			return _result(false, "landing_void")
		if float((hit.normal as Vector3).dot(Vector3.UP)) < LANDING_MAX_SLOPE_DOT:
			return _result(false, "landing_slope")
		supports.append(hit)
	var center_height := float((supports[0].position as Vector3).y)
	for support: Dictionary in supports:
		if absf(float((support.position as Vector3).y) - center_height) > LANDING_HEIGHT_TOLERANCE:
			return _result(false, "landing_unlevel")
	var landing_position := Vector3(global_position.x, center_height, global_position.z)
	if not _hull_is_clear(landing_position + Vector3.UP * 0.08, excludes):
		return _result(false, "landing_blocked")
	var descent_start := Transform3D(_yaw_basis(), global_position + Vector3.UP * HULL_CENTER_Y)
	# Stop the swept box just above the supporting surface.  The final short
	# settle is controlled by the owner, while this cast still catches any
	# overhang or actor in the descent volume.
	var descent := landing_position + Vector3.UP * 0.08 - global_position
	if descent.length_squared() > 0.01 and not _motion_is_clear(descent_start, descent, excludes):
		return _result(false, "landing_descent_blocked")
	var exit_position := _find_exit_position(landing_position, excludes)
	if exit_position == Vector3.INF:
		return _result(false, "landing_exit_blocked")
	var result := _result(true, "")
	result.position = landing_position
	result.rotation = Vector3(0.0, flight_yaw, 0.0)
	result.exit_position = exit_position
	return result


func land(candidate: Dictionary) -> bool:
	if not bool(candidate.get("ok", false)):
		return false
	if not candidate.has("position"):
		return false
	var target_position: Vector3 = candidate.position
	set_pose(target_position, Vector3(0.0, flight_yaw, 0.0), true)
	return true


func boarding_positions() -> Array[Vector3]:
	var basis := _yaw_basis()
	return [
		global_position + basis * Vector3(-4.0, 0.0, 0.0),
		global_position + basis * Vector3(4.0, 0.0, 0.0),
		global_position + basis * Vector3(0.0, 0.0, 4.1),
		global_position + basis * Vector3(0.0, 0.0, -4.1),
	]


func clear_exit_position(exclude_rids: Array[RID] = []) -> Vector3:
	return _find_exit_position(global_position, _query_excludes(exclude_rids))


func _find_exit_position(landing_position: Vector3, excludes: Array[RID]) -> Vector3:
	var state := get_world_3d().direct_space_state
	for offset: Vector3 in [Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), Vector3(0.0, 0.0, 4.1), Vector3(0.0, 0.0, -4.1)]:
		var proposed := landing_position + _yaw_basis() * offset
		var ray_from := proposed + Vector3.UP * 2.0
		var ray := PhysicsRayQueryParameters3D.create(ray_from, proposed + Vector3.DOWN * 1.0, SHIP_LAYER_MASK, excludes)
		var hit := state.intersect_ray(ray)
		if hit.is_empty() or float((hit.normal as Vector3).dot(Vector3.UP)) < LANDING_MAX_SLOPE_DOT:
			continue
		var foot := hit.position as Vector3
		var capsule_transform := Transform3D(Basis.IDENTITY, foot + Vector3.UP * (EXIT_HEIGHT * 0.5 + EXIT_CLEARANCE))
		if _shape_hits(_exit_shape(), capsule_transform, excludes).is_empty():
			return foot + Vector3.UP * EXIT_CLEARANCE
	return Vector3.INF


func _hull_is_clear(foot_position: Vector3, excludes: Array[RID]) -> bool:
	var transform := Transform3D(_yaw_basis(), foot_position + Vector3.UP * HULL_CENTER_Y)
	return _shape_hits(_hull_shape(), transform, excludes).is_empty()


func _motion_is_clear(transform: Transform3D, motion: Vector3, excludes: Array[RID]) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _hull_shape()
	query.transform = transform
	query.motion = motion
	query.collision_mask = SHIP_LAYER_MASK
	query.exclude = excludes
	query.margin = 0.01
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() >= 1 and fractions[0] >= 0.999


func _shape_hits(shape: Shape3D, transform: Transform3D, excludes: Array[RID]) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = transform
	query.collision_mask = SHIP_LAYER_MASK
	query.exclude = excludes
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_shape(query, 16)


func _hull_shape() -> BoxShape3D:
	return $CollisionShape3D.shape as BoxShape3D


func _exit_shape() -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = EXIT_RADIUS
	shape.height = EXIT_HEIGHT
	return shape


func _query_excludes(extra: Array[RID]) -> Array[RID]:
	var excludes: Array[RID] = [get_rid()]
	for rid: RID in extra:
		if rid.is_valid() and not excludes.has(rid):
			excludes.append(rid)
	return excludes


func _yaw_basis() -> Basis:
	return Basis(Vector3.UP, flight_yaw)


func _flight_forward() -> Vector3:
	return (_yaw_basis() * Basis(Vector3.RIGHT, flight_pitch)) * Vector3.FORWARD


func _update_visual(_delta: float) -> void:
	if _visual:
		_visual.rotation = Vector3(-flight_pitch, PI, _visual_bank)


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _action_strength(action: StringName) -> float:
	return Input.get_action_strength(action) if InputMap.has_action(action) else 0.0


func _result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"position": global_position,
		"rotation": Vector3(0.0, flight_yaw, 0.0),
		"exit_position": Vector3.ZERO,
	}
