extends CharacterBody3D
class_name ExplorerPlayer

signal noise_emitted(position: Vector3, loudness: float)
signal attack_requested
signal resonance_requested
signal died
signal health_changed(value: float)

@export_group("Vitals")
@export var health: float = 100.0

@export_group("Movement")
@export var walk_speed: float = 4.0
@export var run_speed: float = 7.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 18.0
@export var acceleration: float = 26.0
@export var deceleration: float = 34.0

@export_group("Camera")
@export var input_enabled: bool = true
@export_range(0.001, 0.03, 0.001) var mouse_sensitivity: float = 0.008
@export var invert_y: bool = false
@export_range(60.0, 70.0, 0.5) var camera_fov: float = 65.0
@export_range(0.0, 0.2, 0.005) var camera_smoothing: float = 0.06
@export var camera_yaw: float = 0.0
@export var camera_pitch: float = deg_to_rad(-12.0)
@export_range(1.0, 4.0, 0.1) var camera_pitch_limit_degrees: float = 70.0

@export_group("Combat")
@export var attack_telegraph: float = 0.12
@export var attack_cooldown: float = 0.5
@export var interaction_animation_lock: float = 0.55

@export_group("Assets")
@export_file("*.glb") var model_path: String = "res://assets/models/explorer.glb"

@onready var camera: Camera3D = %Camera
@onready var _camera_rig: Node3D = %CameraRig
@onready var _camera_yaw_node: Node3D = %CameraYaw
@onready var _spring_arm: SpringArm3D = %SpringArm
@onready var _visual: Node3D = %Visual

var _attack_windup_remaining: float = -1.0
var _attack_cooldown_remaining: float = 0.0
var _footstep_noise_remaining: float = 0.0
var _camera_follow_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
var _interaction_animation_remaining: float = 0.0
var _animation_player: AnimationPlayer


func _ready() -> void:
	if camera:
		camera.fov = camera_fov
	if _camera_rig:
		_camera_follow_offset = _camera_rig.position
		_camera_rig.top_level = true
		_camera_rig.global_position = global_position + _camera_follow_offset
	if _spring_arm:
		_spring_arm.spring_length = maxf(_spring_arm.spring_length, 0.1)
	set_view(camera_yaw, camera_pitch)
	_capture_mouse()
	_try_attach_model()
	_play_animation(&"idle")


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed:
		_capture_mouse()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var vertical_sign := -1.0 if invert_y else 1.0
		set_view(
			camera_yaw - event.screen_relative.x * mouse_sensitivity,
			camera_pitch - event.screen_relative.y * mouse_sensitivity * vertical_sign
		)


func _physics_process(delta: float) -> void:
	_update_camera_follow(delta)
	_interaction_animation_remaining = maxf(0.0, _interaction_animation_remaining - delta)
	if health <= 0.0:
		return
	_advance_attack(delta)
	if not input_enabled:
		_apply_gravity(delta)
		move_and_slide()
		return
	if _action_just_pressed(&"resonance"):
		resonance_requested.emit()
	if _action_just_pressed(&"attack"):
		perform_attack()
	_update_movement(delta)


func set_view(yaw: float, pitch: float) -> void:
	camera_yaw = yaw
	var pitch_limit := deg_to_rad(camera_pitch_limit_degrees)
	camera_pitch = clampf(pitch, -pitch_limit, pitch_limit)
	if _camera_yaw_node:
		_camera_yaw_node.rotation.y = camera_yaw
	if _camera_rig:
		_camera_rig.rotation.x = camera_pitch


func set_camera_fov(value: float) -> void:
	camera_fov = clampf(value, 60.0, 70.0)
	if camera:
		camera.fov = camera_fov


func set_health(value: float) -> void:
	var previous_health := health
	health = clampf(value, 0.0, 100.0)
	if not is_equal_approx(previous_health, health):
		health_changed.emit(health)
	if previous_health > 0.0 and health <= 0.0:
		input_enabled = false
		_interaction_animation_remaining = 0.0
		_play_animation(&"death")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	set_health(health - amount)


func perform_attack() -> bool:
	if health <= 0.0 or _attack_windup_remaining >= 0.0 or _attack_cooldown_remaining > 0.0:
		return false
	_interaction_animation_remaining = 0.0
	_face_visual_toward_camera()
	_attack_windup_remaining = attack_telegraph
	_play_animation(&"attack")
	return true


func play_interaction(duration: float = 0.0) -> bool:
	if health <= 0.0 or _attack_windup_remaining >= 0.0:
		return false
	_interaction_animation_remaining = maxf(duration, interaction_animation_lock)
	_play_animation(&"interact")
	return true


func _update_movement(delta: float) -> void:
	var forward_input := _action_strength(&"move_forward") - _action_strength(&"move_back")
	var right_input := _action_strength(&"move_right") - _action_strength(&"move_left")
	var move_direction := Vector3.ZERO
	if camera:
		var camera_forward := -camera.global_transform.basis.z
		var camera_right := camera.global_transform.basis.x
		camera_forward.y = 0.0
		camera_right.y = 0.0
		move_direction = (camera_forward.normalized() * forward_input + camera_right.normalized() * right_input)
	else:
		move_direction = Vector3(right_input, 0.0, -forward_input)
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()
	var speed := run_speed if _action_pressed(&"sprint") else walk_speed
	var target_velocity := move_direction * speed
	var rate := acceleration if move_direction != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, rate * delta)
	if _action_just_pressed(&"jump") and is_on_floor():
		velocity.y = jump_velocity
		noise_emitted.emit(global_position, 6.0)
	_apply_gravity(delta)
	move_and_slide()
	if move_direction != Vector3.ZERO:
		_face_visual(move_direction, delta)
		_play_locomotion_animation(&"run" if speed == run_speed else &"walk")
		_emit_footstep_noise(speed, delta)
	else:
		_play_locomotion_animation(&"idle")


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _update_camera_follow(delta: float) -> void:
	if not _camera_rig:
		return
	var target_position := global_position + _camera_follow_offset
	if camera_smoothing <= 0.0:
		_camera_rig.global_position = target_position
		return
	var weight := 1.0 - exp(-delta / camera_smoothing)
	_camera_rig.global_position = _camera_rig.global_position.lerp(target_position, weight)


func _advance_attack(delta: float) -> void:
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	if _attack_windup_remaining < 0.0:
		return
	_attack_windup_remaining -= delta
	if _attack_windup_remaining > 0.0:
		return
	_attack_windup_remaining = -1.0
	_attack_cooldown_remaining = attack_cooldown
	noise_emitted.emit(global_position, 9.0)
	attack_requested.emit()


func _emit_footstep_noise(speed: float, delta: float) -> void:
	_footstep_noise_remaining -= delta
	if _footstep_noise_remaining > 0.0:
		return
	_footstep_noise_remaining = 0.38 if speed == run_speed else 0.58
	noise_emitted.emit(global_position, 4.0 if speed == run_speed else 2.0)


func _face_visual(direction: Vector3, delta: float) -> void:
	if not _visual:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, desired_yaw, minf(1.0, 12.0 * delta))


func _face_visual_toward_camera() -> void:
	if not _visual:
		return
	var aim := -camera.global_transform.basis.z if camera else -global_transform.basis.z
	aim.y = 0.0
	if aim.length_squared() <= 0.001:
		return
	_visual.rotation.y = atan2(-aim.x, -aim.z)


func _capture_mouse() -> void:
	if input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _action_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _action_just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _action_strength(action: StringName) -> float:
	return Input.get_action_strength(action) if InputMap.has_action(action) else 0.0


func _try_attach_model() -> void:
	if not _visual or not ResourceLoader.exists(model_path):
		return
	var packed_model := load(model_path) as PackedScene
	if not packed_model:
		return
	var model_instance := packed_model.instantiate()
	_visual.add_child(model_instance)
	var animation_players := model_instance.find_children("*", "AnimationPlayer", true, false)
	if not animation_players.is_empty():
		_animation_player = animation_players.front() as AnimationPlayer


func _play_animation(animation_name: StringName) -> void:
	if _animation_player and _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name)


func _play_locomotion_animation(animation_name: StringName) -> void:
	if _interaction_animation_remaining <= 0.0:
		_play_animation(animation_name)
