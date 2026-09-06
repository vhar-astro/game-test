class_name FlightCoordinator
extends Node
## Owns the handoff between the explorer and their one persistent ship.

const SHIP_SCENE := preload("res://scenes/actors/ship.tscn")
var game: InfinityGame
var ship: ExplorerShip
var portal_id := ""
var landing_status: Dictionary = {}
var _probe_elapsed := 0.0
var _engine_audio: AudioStreamPlayer3D

func unload() -> void:
	if is_instance_valid(ship):
		remove_child(ship)
		ship.queue_free()
	ship = null
	portal_id = ""
	landing_status = {}
	_probe_elapsed = 0.0

func load_ship() -> void:
	if game.session.ship_scene_id != game.world.scene_id: return
	ship = SHIP_SCENE.instantiate()
	add_child(ship)
	ship.set_pose(game.session.ship_position, game.session.ship_rotation, game.session.ship_landed)
	ship.set_piloted(aboard())
	_apply_player_visibility()
	if aboard(): ship.camera.make_current()
	else:
		game.player.camera.make_current()
		# Returning on foot must not spawn the explorer inside their parked hull.
		var local_player := ship.to_local(game.player.global_position)
		var hull := AABB(Vector3(-3.65,-.1,-3.55), Vector3(7.3,3.5,7.1))
		if hull.has_point(local_player):
			var exit_position := ship.clear_exit_position([game.player.get_rid()])
			if exit_position != Vector3.INF:
				game.player.global_position = exit_position
				game.last_safe = exit_position
	apply_settings()
	_engine_audio = game.audio.loop_spatial("ship", ship.global_position)

func aboard() -> bool:
	return game.session.movement_mode == GameSession.MOVEMENT_SHIP

func apply_settings() -> void:
	if not is_instance_valid(ship): return
	ship.mouse_sensitivity = float(game.settings.sensitivity)
	ship.invert_y = bool(game.settings.invert_y)
	ship.camera_fov = float(game.settings.fov)
	ship.camera.fov = ship.camera_fov

func set_active(active: bool) -> void:
	if not is_instance_valid(ship): return
	ship.input_enabled = active and aboard()
	ship.set_physics_process(active)

func nearest_boarding_point() -> Vector3:
	var best := Vector3.INF
	if not is_instance_valid(ship) or not ship.landed: return best
	var distance := 3.5
	for point in ship.boarding_positions():
		var next_distance := game.player.global_position.distance_to(point)
		if next_distance < distance and game._line_clear(game.player.global_position + Vector3.UP, point + Vector3.UP):
			distance = next_distance
			best = point
	return best

func board() -> bool:
	if game.mode != "explore" or nearest_boarding_point() == Vector3.INF: return false
	var takeoff := ship.attempt_takeoff([game.player.get_rid()])
	if not takeoff.ok:
		game.ui.toast(tr(str(takeoff.reason).to_upper()))
		return false
	game._save()
	game._set_mode("boarding")
	game.player.play_interaction()
	game.ui.toast(tr("SHIP_BOARDING"))
	await get_tree().create_timer(.4).timeout
	if game.mode != "boarding": return false
	game.player.visible = false
	ship.camera.make_current()
	var tween := create_tween()
	tween.tween_property(ship, "global_position", takeoff.position, .5).set_trans(Tween.TRANS_SINE)
	await tween.finished
	if game.mode != "boarding": return false
	ship.landed = false
	game.session.set_ship_state(game.world.scene_id, ship.global_position, Vector3(0,ship.flight_yaw,0), false,
		game.session.ship_last_landed_position, game.session.ship_last_landed_yaw)
	game.session.set_movement_mode(GameSession.MOVEMENT_SHIP)
	ship.set_piloted(true)
	_apply_player_visibility()
	game._resume_game()
	game._save()
	return true

func land() -> bool:
	if game.mode != "flight" or not is_instance_valid(ship): return false
	var candidate := ship.landing_candidate([game.player.get_rid()])
	if not candidate.ok:
		game.ui.toast(tr(str(candidate.reason).to_upper()))
		return false
	game._save()
	game._set_mode("landing")
	var tween := create_tween()
	tween.tween_property(ship, "global_position", candidate.position, .55).set_trans(Tween.TRANS_SINE)
	await tween.finished
	if game.mode != "landing": return false
	ship.land(candidate)
	ship.set_piloted(false)
	game.session.set_movement_mode(GameSession.MOVEMENT_ON_FOOT)
	game.session.set_ship_state(game.world.scene_id, ship.global_position, Vector3(0,ship.flight_yaw,0), true,
		ship.global_position, ship.flight_yaw)
	game.player.global_position = candidate.exit_position
	game.player.velocity = Vector3.ZERO
	var toward_ship := ship.global_position - game.player.global_position
	game.player.set_view(atan2(-toward_ship.x, -toward_ship.z), -.18)
	game.player.reset_camera_follow()
	game.player.camera.make_current()
	game.last_safe = game.player.global_position
	_apply_player_visibility()
	game._resume_game()
	game.audio.effect("land", ship.global_position)
	game._save()
	return true

func interact() -> void:
	if game.mode != "flight": return
	_update_portal()
	if not portal_id.is_empty():
		var destination := {"portal":"ruins", "return_hub":"hub", "hub_forest":"forest", "hub_ruins":"ruins"}[portal_id] as String
		if destination == "ruins" and not game.session.crystal_collected:
			game.ui.toast(tr("PORTAL_LOCKED"))
		else:
			game.travel(destination, true)
		return
	land()

func tick(delta: float) -> void:
	if not is_instance_valid(ship): return
	if is_instance_valid(_engine_audio):
		_engine_audio.global_position = ship.global_position
		_engine_audio.pitch_scale = 1.0 + ship.velocity.length() / ship.speed * .3
	game.player.global_position = ship.global_position + Vector3.UP
	if not game.world.flight_bounds.has_point(ship.global_position):
		ship.set_pose(game.session.ship_last_landed_position + Vector3.UP * 4,
			Vector3(0, game.session.ship_last_landed_yaw, 0), false)
		game.ui.toast(tr("FLIGHT_BOUNDARY_RETURN"))
		game._save()
	_probe_elapsed -= delta
	if _probe_elapsed <= 0:
		_probe_elapsed = .2
		_update_portal()
		landing_status = ship.landing_candidate([game.player.get_rid()])
	game.ui.update_hud(game.session, 0, tr("FLIGHT_OBJECTIVE") if game.world.scene_id == "forest" else game._objective(), prompt())

func prompt() -> String:
	if not portal_id.is_empty():
		return tr("FLIGHT_PORTAL") if portal_id not in ["portal", "hub_ruins"] or game.session.crystal_collected else tr("PORTAL_LOCKED")
	if landing_status.get("ok", false): return tr("SHIP_LAND")
	return tr(str(landing_status.get("reason", "landing_void")).to_upper())

func _update_portal() -> void:
	portal_id = ""
	var best := 8.0
	for id: String in game.world.interactables:
		if id not in ["portal", "return_hub", "hub_forest", "hub_ruins"]: continue
		var distance := ship.global_position.distance_to(game.world.interaction_position(id))
		if distance < best:
			best = distance
			portal_id = id

func sync_session() -> void:
	if not is_instance_valid(ship): return
	game.session.set_ship_state(game.world.scene_id, ship.global_position,
		Vector3(ship.flight_pitch, ship.flight_yaw, 0), ship.landed,
		game.session.ship_last_landed_position, game.session.ship_last_landed_yaw)
	if aboard():
		game.session.player_position = ship.global_position + Vector3.UP
		game.session.player_rotation = Vector3(ship.flight_pitch, ship.flight_yaw, 0)

func _apply_player_visibility() -> void:
	game.player.visible = not aboard()
	game.player.collision_layer = 0 if aboard() else 2
	game.player.collision_mask = 0 if aboard() else 21
