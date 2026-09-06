extends CharacterBody3D
class_name SentinelRobot

signal defeated
signal attack_hit(amount: float)
signal alert_changed(active: bool)

enum State { PATROL, ALERT, CHASE, ATTACK, LOST, DEFEATED }

@export_group("Targeting")
@export var player: ExplorerPlayer
@export var enabled: bool = true
@export var patrol_points: Array[Vector3] = []
@export var sight_range: float = 15.0
@export_range(10.0, 180.0, 1.0) var sight_angle_degrees: float = 70.0
@export var hearing_multiplier: float = 1.8
@export var lose_target_after: float = 3.5

@export_group("Vitals and combat")
@export var health: float = 30.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 2.35
@export var attack_telegraph: float = 0.65
@export var attack_interval: float = 1.3

@export_group("Movement")
@export var patrol_speed: float = 2.4
@export var chase_speed: float = 4.0
@export var gravity: float = 18.0

@export_group("Assets")
@export_file("*.glb") var model_path: String = "res://assets/models/sentinel.glb"

@onready var navigation_agent: NavigationAgent3D = %NavigationAgent
@onready var _sight_ray: RayCast3D = %SightRay
@onready var _visual: Node3D = %Visual

var state: State = State.PATROL
var _alert_active: bool = false
var _alert_remaining: float = 0.0
var _lost_time: float = 0.0
var _last_known_position: Vector3
var _patrol_index: int = 0
var _spawn_position: Vector3
var _attack_windup_remaining: float = -1.0
var _attack_cooldown_remaining: float = 0.0
var _navigation_target: Vector3 = Vector3.INF
var _animation_player: AnimationPlayer


func _ready() -> void:
	_spawn_position = global_position
	_last_known_position = global_position
	if _sight_ray:
		_sight_ray.add_exception(self)
	if navigation_agent:
		navigation_agent.path_desired_distance = 0.45
		navigation_agent.target_desired_distance = 0.8
	_try_attach_model()
	_play_animation(&"idle")


func _physics_process(delta: float) -> void:
	if not enabled or state == State.DEFEATED:
		return
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	var can_see_player := _can_see_player()
	if can_see_player:
		_last_known_position = player.global_position
		_lost_time = 0.0
		if not _alert_active or state == State.LOST:
			_begin_alert()
	elif _alert_active:
		_lost_time += delta
		if _lost_time >= lose_target_after and state != State.LOST:
			_begin_lost()

	var destination := Vector3.INF
	var move_speed := 0.0
	match state:
		State.PATROL:
			destination = _current_patrol_position()
			move_speed = patrol_speed
			if _at_position(destination):
				_advance_patrol()
				destination = _current_patrol_position()
		State.ALERT:
			_alert_remaining -= delta
			_face_toward(_last_known_position, delta)
			if _alert_remaining <= 0.0:
				state = State.CHASE
		State.CHASE:
			if can_see_player and global_position.distance_to(player.global_position) <= attack_range:
				state = State.ATTACK
			else:
				destination = _last_known_position
				move_speed = chase_speed
		State.ATTACK:
			if not can_see_player or global_position.distance_to(player.global_position) > attack_range:
				_cancel_attack()
				state = State.CHASE
			else:
				_update_attack(delta)
		State.LOST:
			destination = _current_patrol_position()
			move_speed = patrol_speed
			if _at_position(destination):
				_set_alert(false)
				state = State.PATROL

	if destination != Vector3.INF:
		_move_to(destination, move_speed, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, chase_speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, chase_speed * 8.0 * delta)
		_apply_gravity(delta)
		move_and_slide()


func notify_noise(position: Vector3, loudness: float) -> void:
	if not enabled or loudness <= 0.0:
		return
	if global_position.distance_to(position) > loudness * hearing_multiplier:
		return
	_last_known_position = position
	_lost_time = 0.0
	if not _alert_active or state == State.LOST:
		_begin_alert()


func take_damage(amount: float) -> void:
	if not enabled or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_defeat()


func _begin_alert() -> void:
	_set_alert(true)
	state = State.ALERT
	_alert_remaining = 0.35
	_play_animation(&"idle")


func _begin_lost() -> void:
	_cancel_attack()
	state = State.LOST
	_last_known_position = _current_patrol_position()


func _update_attack(delta: float) -> void:
	_face_toward(player.global_position, delta)
	if _attack_windup_remaining >= 0.0:
		_attack_windup_remaining -= delta
		if _attack_windup_remaining > 0.0:
			return
		_attack_windup_remaining = -1.0
		if _can_see_player() and global_position.distance_to(player.global_position) <= attack_range:
			attack_hit.emit(attack_damage)
		_attack_cooldown_remaining = maxf(0.0, attack_interval - attack_telegraph)
		return
	if _attack_cooldown_remaining <= 0.0:
		_attack_windup_remaining = attack_telegraph
		_play_animation(&"attack")


func _cancel_attack() -> void:
	_attack_windup_remaining = -1.0


func _move_to(destination: Vector3, speed: float, delta: float) -> void:
	if navigation_agent and _navigation_target.distance_squared_to(destination) > 0.04:
		navigation_agent.target_position = destination
		_navigation_target = destination
	var movement_direction := Vector3.ZERO
	if navigation_agent and not navigation_agent.is_navigation_finished():
		var next_path_position := navigation_agent.get_next_path_position()
		movement_direction = global_position.direction_to(next_path_position)
		movement_direction.y = 0.0
		movement_direction = movement_direction.normalized()
	velocity.x = movement_direction.x * speed
	velocity.z = movement_direction.z * speed
	_apply_gravity(delta)
	move_and_slide()
	if movement_direction != Vector3.ZERO:
		_face_toward(global_position + movement_direction, delta)
		_play_animation(&"walk")
	else:
		_play_animation(&"idle")


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _can_see_player() -> bool:
	if not player or player.health <= 0.0 or not _sight_ray:
		return false
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	if distance > sight_range or distance <= 0.01:
		return false
	var planar_direction := to_player
	planar_direction.y = 0.0
	if planar_direction.length_squared() <= 0.001:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	var half_cone_cosine := cos(deg_to_rad(sight_angle_degrees * 0.5))
	if forward.normalized().dot(planar_direction.normalized()) < half_cone_cosine:
		return false
	_sight_ray.target_position = _sight_ray.to_local(player.global_position + Vector3.UP)
	_sight_ray.force_raycast_update()
	return _sight_ray.is_colliding() and _sight_ray.get_collider() == player


func _current_patrol_position() -> Vector3:
	if patrol_points.is_empty():
		return _spawn_position
	return patrol_points[_patrol_index % patrol_points.size()]


func _advance_patrol() -> void:
	if patrol_points.size() > 1:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()


func _at_position(position: Vector3) -> bool:
	var planar_offset := global_position - position
	planar_offset.y = 0.0
	return planar_offset.length_squared() <= 0.64


func _face_toward(target: Vector3, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, 10.0 * delta))


func _set_alert(value: bool) -> void:
	if _alert_active == value:
		return
	_alert_active = value
	alert_changed.emit(value)


func _defeat() -> void:
	enabled = false
	state = State.DEFEATED
	_cancel_attack()
	velocity = Vector3.ZERO
	if navigation_agent:
		navigation_agent.avoidance_enabled = false
	collision_layer = 0
	collision_mask = 0
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	_play_animation(&"death")
	_set_alert(false)
	defeated.emit()


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
