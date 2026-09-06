extends RefCounted
## Integration coverage for the player/ship handoff. Fixture teleports only
## stage distant landing pads and portals; each state change still goes through
## the public interaction or coordinator API used by gameplay.

const MainScene := preload("res://scenes/main.tscn")
const SaveStoreScript := preload("res://scripts/data/save_store.gd")

var _failures: Array[String] = []
var _save_root := ""


func run(tree: SceneTree) -> Array[String]:
	_failures.clear()
	_save_root = "user://test_flight_%d" % Time.get_ticks_usec()
	var game := await _new_game(tree)
	if game == null:
		_cleanup()
		return _failures.duplicate()
	_verify_forest_walkable_surfaces(game)

	await _board_at_current_ship(tree, game, "the parked forest ship should board through the ship interaction")
	if game.mode == "flight":
		await _verify_flight_controls(tree, game)
		await _verify_observatory_landing(tree, game)
		game = await _restart(tree, game, "a landed ship should survive restart")
	if game != null and game.mode == "explore":
		await _board_at_current_ship(tree, game, "the restarted landed ship should be boardable")
	if game != null and game.mode == "flight":
		game = await _verify_airborne_restart(tree, game)
	if game != null and game.mode == "flight":
		await _verify_no_foot_actions_aboard(tree, game)
		await _land_at_observatory(tree, game)
	if game != null and game.mode == "explore":
		await _verify_foot_portal_leaves_ship(tree, game)
	if game != null and game.mode == "explore":
		await _return_to_forest_on_foot(tree, game)
		await _board_at_current_ship(tree, game, "the personal forest ship should remain boardable after foot portals")
	if game != null and game.mode == "flight":
		await _verify_ship_portals_and_boundary(tree, game)
		await _verify_hub_dock_foot_portals(tree, game)

	_release_inputs()
	if is_instance_valid(game):
		game.queue_free()
		await _frames(tree, 3)
	_cleanup()
	return _failures.duplicate()


func _new_game(tree: SceneTree) -> InfinityGame:
	var game := MainScene.instantiate() as InfinityGame
	if game == null:
		_failures.append("main scene should instantiate for flight integration")
		return null
	tree.root.add_child(game)
	await _frames(tree, 2)
	game.store = SaveStoreScript.new(_save_root)
	_expect(game.new_game(0), "new game should create an isolated flight profile")
	await _frames(tree, 4)
	_expect(is_instance_valid(game.flight.ship) and game.flight.ship.landed, "new game should place one landed personal ship in forest")
	return game


func _verify_forest_walkable_surfaces(game: InfinityGame) -> void:
	_expect(game.world.surface_boundary_distance(SliceWorld.ship_dock("forest")) > 0.0, "forest dock should remain inside a positive walkable surface")
	_expect(game.world.surface_boundary_distance(Vector3(-29, 1, 6)) > 0.0, "observatory pad should remain inside a positive walkable surface")


func _restart(tree: SceneTree, game: InfinityGame, label: String) -> InfinityGame:
	_expect(game._save(), "%s should save" % label)
	game.queue_free()
	await _frames(tree, 4)
	var reopened := MainScene.instantiate() as InfinityGame
	if reopened == null:
		_failures.append("%s could not instantiate a fresh game" % label)
		return null
	tree.root.add_child(reopened)
	await _frames(tree, 2)
	reopened.store = SaveStoreScript.new(_save_root)
	_expect(reopened.continue_game(0), "%s should continue from its isolated save" % label)
	await _frames(tree, 5)
	return reopened


func _board_at_current_ship(tree: SceneTree, game: InfinityGame, message: String) -> void:
	if not is_instance_valid(game.flight.ship):
		_failures.append("%s: ship should exist in the active scene" % message)
		return
	var points := game.flight.ship.boarding_positions()
	game.player.global_position = points[1]
	game.player.velocity = Vector3.ZERO
	await tree.physics_frame
	_expect(game.flight.nearest_boarding_point() != Vector3.INF, "%s: a legal boarding point should be found" % message)
	game.interact("ship")
	var boarded := await _wait_mode(tree, game, "flight", 100)
	_expect(boarded and game.flight.aboard() and not game.flight.ship.landed, message)
	var before_mode := game.session.movement_mode
	game.interact("ship")
	await _frames(tree, 2)
	_expect(game.mode == "flight" and game.session.movement_mode == before_mode, "ship interaction should not duplicate while already aboard")


func _verify_flight_controls(tree: SceneTree, game: InfinityGame) -> void:
	var ship := game.flight.ship
	var before := ship.global_position
	Input.action_press(&"move_forward")
	await _frames(tree, 12)
	Input.action_release(&"move_forward")
	await _frames(tree, 2)
	_expect(ship.global_position.distance_to(before) > 0.4, "forward flight input should move the ship")
	_expect(ship.velocity.length() < 0.01, "releasing flight input should hover immediately without inertia")


func _verify_observatory_landing(tree: SceneTree, game: InfinityGame) -> void:
	var ship := game.flight.ship
	ship.set_pose(Vector3(-29, 9, 0), Vector3(0, ship.flight_yaw, 0), false)
	await tree.physics_frame
	var blocked := ship.landing_candidate([game.player.get_rid()])
	_expect(not bool(blocked.ok) and not str(blocked.reason).is_empty(), "observatory armillary should reject an obstructed landing fixture")
	await _land_at_observatory(tree, game)


func _land_at_observatory(tree: SceneTree, game: InfinityGame) -> void:
	if game.mode != "flight":
		return
	var ship := game.flight.ship
	# The north half remains clear of the armillary and perimeter collision.
	ship.set_pose(Vector3(-29, 9, 6), Vector3(0, ship.flight_yaw, 0), false)
	await tree.physics_frame
	var candidate := ship.landing_candidate([game.player.get_rid()])
	_expect(bool(candidate.ok), "the observatory's clear north pad should accept the full hull and player exit")
	game.flight.land()
	var landed := await _wait_mode(tree, game, "explore", 100)
	_expect(landed and game.flight.ship.landed and game.session.movement_mode == "on_foot", "valid landing should return the pilot to on-foot exploration")


func _verify_airborne_restart(tree: SceneTree, game: InfinityGame) -> InfinityGame:
	var expected_position := game.flight.ship.global_position
	var reopened := await _restart(tree, game, "an airborne ship should survive restart")
	if reopened == null:
		return null
	_expect(reopened.mode == "flight" and reopened.flight.aboard(), "restart should restore an airborne pilot into flight mode")
	_expect(is_instance_valid(reopened.flight.ship) and not reopened.flight.ship.landed, "restart should restore the ship airborne")
	_expect(reopened.flight.ship.global_position.distance_to(expected_position) < 0.35, "restart should preserve the airborne ship transform")
	return reopened


func _verify_no_foot_actions_aboard(tree: SceneTree, game: InfinityGame) -> void:
	var attack_before := game.player._attack_windup_remaining
	var resonance_before := game.resonance_cooldown
	var prism_before := game.session.prism_orientations.duplicate()
	Input.action_press(&"attack")
	Input.action_press(&"resonance")
	await _frames(tree, 2)
	_release_inputs()
	game.open_puzzle(0)
	await tree.process_frame
	_expect(game.mode == "flight", "attack, resonance and puzzle routes should not replace flight mode")
	_expect(is_equal_approx(game.player._attack_windup_remaining, attack_before), "attack input should be disabled while aboard")
	_expect(is_equal_approx(game.resonance_cooldown, resonance_before), "resonance input should be disabled while aboard")
	_expect(game.session.prism_orientations == prism_before, "puzzle input should not alter prism progress while aboard")


func _verify_foot_portal_leaves_ship(tree: SceneTree, game: InfinityGame) -> void:
	_complete_portal_gate(game)
	var parked_position := game.flight.ship.global_position
	game.player.global_position = game.world.interaction_position("portal")
	game.player.velocity = Vector3.ZERO
	game.world.apply_state(game.session)
	game.interact("portal")
	var arrived := await _wait_scene(tree, game, "ruins", "explore", 100)
	_expect(arrived, "unlocked foot portal should reach ruins")
	_expect(game.session.ship_scene_id == "forest" and game.session.ship_landed, "foot portal should leave the personal ship parked in forest")
	_expect(game.session.ship_position.distance_to(parked_position) < 0.35, "foot portal should preserve the parked ship position")
	_expect(not is_instance_valid(game.flight.ship), "a forest ship should not instantiate in ruins after foot travel")


func _return_to_forest_on_foot(tree: SceneTree, game: InfinityGame) -> void:
	game.player.global_position = game.world.interaction_position("return_hub")
	game.interact("return_hub")
	_expect(await _wait_scene(tree, game, "hub", "explore", 100), "ruins return portal should reach hub on foot")
	game.player.global_position = game.world.interaction_position("hub_forest")
	game.interact("hub_forest")
	_expect(await _wait_scene(tree, game, "forest", "explore", 100), "hub forest portal should return to the personal ship scene")
	_expect(is_instance_valid(game.flight.ship) and game.flight.ship.landed, "returning to forest should reload the parked personal ship")


func _verify_ship_portals_and_boundary(tree: SceneTree, game: InfinityGame) -> void:
	game.flight.ship.set_pose(Vector3(0, 4, -42), Vector3.ZERO, false)
	await tree.physics_frame
	game.flight.interact()
	_expect(await _wait_scene(tree, game, "ruins", "flight", 100), "ship portal should move an airborne player into ruins")
	_expect(game.session.ship_scene_id == "ruins" and game.flight.aboard(), "ship portal should migrate the personal ship with its pilot")
	_expect(game.session.visited_scenes.has("ruins") and game.session.crystal_collected, "ship portal should retain progression gate and visited history")
	game.flight.ship.set_pose(Vector3(0, 4, 12), Vector3.ZERO, false)
	await tree.physics_frame
	game.flight.interact()
	_expect(await _wait_scene(tree, game, "hub", "flight", 100), "ruins ship return portal should reach hub")
	game._unhandled_input(_action_event(&"pause"))
	await tree.process_frame
	_expect(game.mode == "pause", "pause input should suspend flight mode")
	game._unhandled_input(_action_event(&"pause"))
	await tree.process_frame
	_expect(game.mode == "flight" and game.flight.aboard(), "pause resume should return to the active ship flight")
	var safe := game.session.ship_last_landed_position + Vector3.UP * 4
	game.flight.ship.set_pose(game.world.flight_bounds.position - Vector3(5, 0, 0), Vector3.ZERO, false)
	game.flight.tick(0.3)
	_expect(game.flight.ship.global_position.distance_to(safe) < 0.2, "crossing flight bounds should recover the ship at its saved safe launch pose")


func _verify_hub_dock_foot_portals(tree: SceneTree, game: InfinityGame) -> void:
	# Park at the hub dock, then return to hub through foot portals. This is the
	# regression route that used to create the new player at the docked hull's
	# default spawn before the transition overlay ended.
	game.flight.ship.set_pose(SliceWorld.ship_dock("hub") + Vector3.UP * 8, Vector3.ZERO, false)
	await tree.physics_frame
	var candidate := game.flight.ship.landing_candidate([game.player.get_rid()])
	_expect(bool(candidate.ok), "hub dock should have a valid full-hull landing candidate")
	game.flight.land()
	_expect(await _wait_mode(tree, game, "explore", 100), "ship should land at the hub dock for foot-portal regression coverage")
	if game.mode != "explore":
		return
	await _travel_while_transition_is_frozen(tree, game, "hub_forest", "forest")
	await _travel_while_transition_is_frozen(tree, game, "portal", "ruins")
	await _travel_while_transition_is_frozen(tree, game, "return_hub", "hub")
	_expect(is_instance_valid(game.flight.ship) and game.flight.ship.landed, "returning on foot should restore the personal ship parked at the hub dock")
	_expect(_player_clear_of_ship(game), "foot portal arrival must not spawn the player inside the docked hub hull")


func _travel_while_transition_is_frozen(tree: SceneTree, game: InfinityGame, portal_id: String, destination: String) -> void:
	game.player.global_position = game.world.interaction_position(portal_id)
	game.player.velocity = Vector3.ZERO
	game.interact(portal_id)
	var loaded := await _wait_transition_loaded(tree, game, destination, 55)
	_expect(loaded, "%s portal should load %s while transition overlay remains active" % [portal_id, destination])
	if loaded:
		_expect(not game.player.input_enabled and not game.player.is_physics_processing(), "new player must remain frozen and input-disabled under the transition overlay")
		if is_instance_valid(game.robot):
			_expect(not game.robot.enabled and not game.robot.is_physics_processing(), "new robot must remain frozen under the transition overlay")
		if is_instance_valid(game.flight.ship):
			_expect(not game.flight.ship.input_enabled and not game.flight.ship.is_physics_processing(), "new ship must remain frozen under the transition overlay")
	_expect(await _wait_scene(tree, game, destination, "explore", 80), "%s portal should resume on-foot exploration after the overlay" % portal_id)


func _wait_transition_loaded(tree: SceneTree, game: InfinityGame, destination: String, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		if not is_instance_valid(game):
			return false
		if game.mode == "transition" and game.session.scene_id == destination and game.world.scene_id == destination:
			return true
		await tree.physics_frame
	return false


func _player_clear_of_ship(game: InfinityGame) -> bool:
	if not is_instance_valid(game.flight.ship):
		return true
	var collider := game.player.get_node("CollisionShape3D") as CollisionShape3D
	if collider == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = collider.global_transform
	query.collision_mask = 16
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 4).is_empty()


func _complete_portal_gate(game: InfinityGame) -> void:
	if not game.session.puzzle_solved:
		game.session.mark_puzzle_solved()
	if not game.session.robot_defeated:
		game.session.mark_robot_defeated()
	if not game.session.artifact_collected:
		game.session.collect_artifact()
	if not game.session.lock_open:
		game.session.open_resonant_lock()
	if not game.session.crystal_collected:
		game.session.collect_crystal()
	game.world.apply_state(game.session)


func _wait_mode(tree: SceneTree, game: InfinityGame, wanted: String, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		if not is_instance_valid(game):
			return false
		if game.mode == wanted:
			return true
		await tree.physics_frame
	return game.mode == wanted


func _wait_scene(tree: SceneTree, game: InfinityGame, scene_id: String, mode: String, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		if not is_instance_valid(game):
			return false
		if game.session.scene_id == scene_id and game.mode == mode:
			return true
		await tree.physics_frame
	return game.session.scene_id == scene_id and game.mode == mode


func _frames(tree: SceneTree, count: int) -> void:
	for _frame in count:
		await tree.physics_frame


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _release_inputs() -> void:
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"ship_descend", &"attack", &"resonance", &"interact"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(_save_root)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			DirAccess.remove_absolute(absolute.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)
