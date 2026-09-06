extends RefCounted

const MainScene = preload("res://scenes/main.tscn")
const SaveStoreScript = preload("res://scripts/data/save_store.gd")

var _failures: Array[String] = []
var _save_root := ""


func run(tree: SceneTree) -> Array[String]:
	_failures.clear()
	_save_root = "user://test_slice_%d" % Time.get_ticks_usec()
	var game := MainScene.instantiate() as InfinityGame
	if game == null:
		_failures.append("the main scene could not be instantiated")
		return _failures.duplicate()
	tree.root.add_child(game)
	await tree.process_frame
	game.store = SaveStoreScript.new(_save_root)

	_expect(game.new_game(0), "a new isolated profile should start")
	await _frames(tree, 3)
	_expect(game.player.play_interaction(0.2), "the player should expose an interaction animation entrypoint")
	await tree.physics_frame
	_expect(game.player._interaction_animation_remaining > 0.0, "interaction animation should hold before locomotion can replace it")
	await _complete_prism_puzzle(tree, game)
	await _continue_from_boundary(tree, game, "puzzle completion")
	await _verify_encounter_physics(tree, game)
	await _defeat_robot(tree, game)
	await _continue_from_boundary(tree, game, "sentinel defeat")
	await _collect_and_travel(tree, game)
	await _revisit_and_verify_rollback(tree, game)

	var expected_resume_flags: Dictionary = game.session.to_dict()["flags"].duplicate(true)
	var expected_resume_position := game.player.global_position
	_expect(game._save(), "the post-rollback state should be resumable by a fresh game instance")
	_release_movement()
	game.queue_free()
	await _frames(tree, 2)
	var reopened := MainScene.instantiate() as InfinityGame
	if reopened == null:
		_failures.append("a fresh main scene could not be instantiated for continue-game validation")
		_cleanup_saves()
		return _failures.duplicate()
	tree.root.add_child(reopened)
	await _frames(tree, 2)
	reopened.store = SaveStoreScript.new(_save_root)
	_expect(reopened.continue_game(0), "a true fresh game instance should continue the isolated profile")
	await _frames(tree, 2)
	_expect(reopened.session.scene_id == "forest", "fresh continue should restore the current forest scene")
	_expect(reopened.session.to_dict()["flags"] == expected_resume_flags, "fresh continue should restore collected rewards and defeated sentinel state")
	_expect(reopened.player.global_position.distance_to(expected_resume_position) < 0.2, "fresh continue should restore the player transform")
	game = reopened
	_verify_future_profile_guard(game)

	_release_movement()
	if is_instance_valid(game):
		game.queue_free()
		await tree.process_frame
	_cleanup_saves()
	return _failures.duplicate()


func _complete_prism_puzzle(tree: SceneTree, game: InfinityGame) -> void:
	await _walk_to(tree, game, Vector3(0.0, 0.12, 4.0), 0.8, 260, "the prism court")
	await _walk_to(tree, game, Vector3(-5.0, 0.12, 4.0), 0.9, 150, "the first prism")
	# A recent boundary return must not leave a frozen distortion in puzzle mode.
	game._decay_material.set_shader_parameter("intensity", 0.6)
	await _tap(tree, &"interact")
	await tree.process_frame
	_expect(game.mode == "puzzle", "E near the first prism should open the puzzle")
	_expect(is_zero_approx(float(game._decay_material.get_shader_parameter("intensity"))), "opening a mechanism should clear boundary distortion")
	if game.mode != "puzzle":
		return

	game._on_command("reset_puzzle")
	_expect(game.session.prism_orientations == [1, 2, 3], "puzzle reset should restore the authored orientation")
	game.session.hint_elapsed = 90.0
	game._on_command("hint")
	_expect(game.session.hint_level == 1, "the available puzzle hint should be accepted through its UI command")
	for _step in 3:
		game._on_command("rotate", 0)
	for _step in 3:
		game._on_command("rotate", 1)
	game._on_command("rotate", 2)
	await tree.process_frame
	_expect(game.session.puzzle_solved, "the authored prism sequence should open the encounter")
	_expect(game.mode == "explore", "solving the prism sequence should restore exploration controls")


func _continue_from_boundary(tree: SceneTree, game: InfinityGame, boundary: String) -> void:
	if game.mode != "explore":
		return
	var expected_flags: Dictionary = game.session.to_dict()["flags"].duplicate(true)
	var expected_position := game.player.global_position
	_expect(game._save(), "%s should create a resumable save" % boundary)
	game._set_mode("menu")
	_expect(game.continue_game(0), "continue should restore %s" % boundary)
	await _frames(tree, 3)
	_expect(game.session.to_dict()["flags"] == expected_flags, "continue should retain flags at %s" % boundary)
	_expect(game.player.global_position.distance_to(expected_position) < 0.2, "continue should restore player position at %s" % boundary)


func _verify_encounter_physics(tree: SceneTree, game: InfinityGame) -> void:
	if not is_instance_valid(game.robot):
		_failures.append("the encounter fixture needs a sentinel")
		return
	# These fixture teleports are only negative physics checks; progression movement stays input-driven.
	game.player.global_position = Vector3(2.7, 0.12, -19.5)
	game.robot.global_position = Vector3(2.7, 0.1, -22.0)
	game.robot.rotation.y = PI
	await _frames(tree, 2)
	_expect(not game.robot._can_see_player(), "the arena pillar should occlude sentinel vision")
	var health_before_wall_strike := game.robot.health
	game.player.set_view(0.0, game.player.camera_pitch)
	await _tap(tree, &"attack")
	await _frames(tree, 12)
	_expect(is_equal_approx(game.robot.health, health_before_wall_strike), "blade hit detection must not strike through the arena pillar")

	game.robot.global_position = Vector3(0.0, 0.1, -21.0)
	game.player.global_position = Vector3(6.0, 0.12, -21.0)
	game.robot.rotation.y = -PI * 0.5
	game.robot.state = SentinelRobot.State.PATROL
	game.robot.enabled = true
	game.robot.health = 30.0
	var navigation_start := game.robot.global_position
	game.robot.notify_noise(game.player.global_position, 10.0)
	await _frames(tree, 105)
	var navigation_offset := game.robot.global_position - navigation_start
	_expect(navigation_offset.length() > 0.5 and absf(navigation_offset.z) > 0.1, "the NavigationAgent path should move the sentinel around the pillar")

	game.robot.global_position = Vector3(0.0, 0.1, -21.0)
	game.player.global_position = Vector3(0.0, 0.12, -18.0)
	game.robot.rotation.y = PI
	game.robot.state = SentinelRobot.State.LOST
	game.robot._alert_active = true
	var sight_reacquired := await _wait_for_robot_state(tree, game.robot, SentinelRobot.State.ALERT, 10)
	_expect(sight_reacquired, "a visible player should reacquire a sentinel from LOST state")
	game.robot.state = SentinelRobot.State.LOST
	game.robot._alert_active = true
	game.robot.notify_noise(Vector3(0.0, 0.12, -18.0), 10.0)
	_expect(game.robot.state == SentinelRobot.State.ALERT, "heard noise should reacquire a sentinel from LOST state")

	game.player.set_health(100.0)
	game.player.global_position = Vector3(0.0, 0.12, -13.0)
	game.player.velocity = Vector3.ZERO
	game.robot.global_position = game.world.robot_position
	game.robot.velocity = Vector3.ZERO
	game.robot.rotation.y = 0.0
	game.robot.state = SentinelRobot.State.PATROL
	game.robot.enabled = true



func _defeat_robot(tree: SceneTree, game: InfinityGame) -> void:
	if not game.session.puzzle_solved:
		return
	await _walk_to(tree, game, Vector3(0.0, 0.12, -13.0), 0.9, 350, "the opened arena gate")
	await _walk_to(tree, game, Vector3(0.0, 0.12, -18.45), 0.75, 180, "the sentinel encounter")
	_expect(is_instance_valid(game.robot) and game.robot.enabled, "the sentinel should activate after the puzzle")
	if not is_instance_valid(game.robot):
		return
	for strike in 3:
		await _approach_robot(tree, game)
		if not is_instance_valid(game.robot) or not game.robot.enabled:
			break
		var direction := game.robot.global_position - game.player.global_position
		game.player.set_view(atan2(-direction.x, -direction.z), game.player.camera_pitch)
		await _tap(tree, &"attack")
		await _frames(tree, 42)
	var remaining_health := game.robot.health if is_instance_valid(game.robot) else 0.0
	_expect(game.session.robot_defeated, "three 10-damage LMB strikes should defeat the 30-health sentinel (remaining %.1f)" % remaining_health)
	_expect(not game.robot.enabled, "a defeated sentinel should disable itself for persistence")


func _collect_and_travel(tree: SceneTree, game: InfinityGame) -> void:
	if not game.session.robot_defeated:
		return
	await _walk_to(tree, game, Vector3(0.0, 0.12, -29.0), 1.0, 280, "the artifact")
	await _tap(tree, &"interact")
	await tree.process_frame
	_expect(game.session.artifact_collected, "E should collect the unlocked artifact")
	var after_artifact := game.session.to_dict()
	await _tap(tree, &"interact")
	await tree.process_frame
	_expect(game.session.to_dict() == after_artifact, "duplicate artifact pickup must not change progress counters")
	await _continue_from_boundary(tree, game, "artifact collection")

	await _walk_to(tree, game, Vector3(0.0, 0.12, -41.0), 1.0, 360, "the still-locked portal")
	await _tap(tree, &"interact")
	await tree.process_frame
	_expect(game.session.scene_id == "forest" and not game.session.crystal_collected, "the portal must stay locked before crystal collection")

	await _walk_to(tree, game, Vector3(0.0, 0.12, -33.0), 0.9, 140, "the resonant lock")
	game.player.set_view(0.0, game.player.camera_pitch)
	await _tap(tree, &"resonance")
	await _frames(tree, 3)
	_expect(game.session.lock_open, "Key 1 should open the visible resonant lock after artifact collection")
	_expect(is_equal_approx(game.resonance_cooldown, 6.0) or game.resonance_cooldown > 5.8, "resonance should begin its six-second cooldown")
	var cooldown_after_first_press := game.resonance_cooldown
	await _tap(tree, &"resonance")
	await tree.physics_frame
	_expect(game.resonance_cooldown < cooldown_after_first_press, "a second Key 1 press during cooldown must not restart resonance")
	await _continue_from_boundary(tree, game, "resonant lock")

	await _walk_to(tree, game, Vector3(0.0, 0.12, -38.0), 1.0, 180, "the memory crystal")
	await _tap(tree, &"interact")
	await tree.process_frame
	_expect(game.session.crystal_collected, "E should collect the crystal after opening the lock")
	await _continue_from_boundary(tree, game, "crystal collection")

	await _walk_to(tree, game, Vector3(0.0, 0.12, -41.0), 1.0, 120, "the forest portal")
	await _tap(tree, &"interact")
	var reached_ruins := await _wait_for_mode(tree, game, "ruins", "explore", 100)
	_expect(reached_ruins, "the collected crystal should let the portal travel to the ruins")
	_expect(game.session.visited_scenes.has("ruins"), "portal travel should record the ruins as visited")
	game.player.set_view(0.0, -0.18)
	await _frames(tree, 8)
	_expect(game.player.camera.global_position.z < 11.9, "the camera must not clip behind the ruins arrival portal")


func _revisit_and_verify_rollback(tree: SceneTree, game: InfinityGame) -> void:
	if game.session.scene_id != "ruins":
		return
	game._on_command("hub", null)
	var reached_hub := await _wait_for_mode(tree, game, "hub", "explore", 100)
	_expect(reached_hub, "the pause-style hub command should travel from ruins to the hub")
	if not reached_hub:
		return
	await _walk_to(tree, game, Vector3(-6.0, 0.12, -5.0), 1.0, 300, "the forest return portal")
	await _tap(tree, &"interact")
	var revisited_forest := await _wait_for_mode(tree, game, "forest", "explore", 100)
	_expect(revisited_forest, "the hub portal should revisit the forest through normal movement and E")
	_expect(game.session.robot_defeated and game.session.crystal_collected, "revisiting must retain defeated-enemy and crystal progress")
	_expect(not is_instance_valid(game.robot), "the persisted defeated sentinel must not respawn on revisit")

	game._save()
	var saved := SaveStoreScript.new(_save_root).load_profile(0)
	_expect(saved.ok and saved.data.resume.flags.robot_defeated and saved.data.resume.flags.crystal_collected, "isolated save should retain encounter and crystal flags")

	# Fixture damage exercises checkpoint recovery after the positive traversal.
	game.player.take_damage(100.0)
	await _frames(tree, 72)
	_expect(game.mode == "explore" and is_equal_approx(game.player.health, 100.0), "death should restore the checkpoint with full health")
	_expect(game.session.robot_defeated and game.session.crystal_collected, "death rollback must keep already committed progression")


func _verify_future_profile_guard(game: InfinityGame) -> void:
	var absolute_root := ProjectSettings.globalize_path(_save_root)
	DirAccess.make_dir_recursive_absolute(absolute_root)
	var future_path := "%s/profile_3.json" % absolute_root
	var future_file := FileAccess.open(future_path, FileAccess.WRITE)
	if future_file == null:
		_failures.append("future-schema fixture could not be created")
		return
	future_file.store_string(JSON.stringify({"version": 99, "resume": {}, "checkpoint": {}}))
	future_file.flush()
	var before_guard := game.session.to_dict()
	_expect(not game.new_game(2), "new_game must refuse an unsupported future save schema")
	_expect(game.session.to_dict() == before_guard, "rejected new_game must preserve the active session")
	game.active_profile = 0


func _walk_to(tree: SceneTree, game: InfinityGame, target: Vector3, tolerance: float, maximum_frames: int, label: String) -> void:
	_release_movement()
	for _frame in maximum_frames:
		if not is_instance_valid(game.player):
			break
		var offset := target - game.player.global_position
		offset.y = 0.0
		if offset.length() <= tolerance:
			break
		game.player.set_view(atan2(-offset.x, -offset.z), game.player.camera_pitch)
		Input.action_press(&"move_forward")
		await tree.physics_frame
	Input.action_release(&"move_forward")
	await tree.physics_frame
	if is_instance_valid(game.player):
		var remaining := game.player.global_position.distance_to(target)
		_expect(remaining <= tolerance + 0.55, "%s should be reachable with camera-relative movement (remaining %.2f m)" % [label, remaining])


func _approach_robot(tree: SceneTree, game: InfinityGame) -> void:
	_release_movement()
	for _frame in 180:
		if not is_instance_valid(game.robot) or not game.robot.enabled or not is_instance_valid(game.player):
			break
		var offset := game.robot.global_position - game.player.global_position
		offset.y = 0.0
		if offset.length() <= 2.25:
			break
		game.player.set_view(atan2(-offset.x, -offset.z), game.player.camera_pitch)
		Input.action_press(&"move_forward")
		await tree.physics_frame
	Input.action_release(&"move_forward")
	await tree.physics_frame


func _tap(tree: SceneTree, action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await tree.physics_frame
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
	await tree.process_frame


func _frames(tree: SceneTree, count: int) -> void:
	for _frame in count:
		await tree.physics_frame


func _wait_for_mode(tree: SceneTree, game: InfinityGame, scene_id: String, mode: String, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		if game.session.scene_id == scene_id and game.mode == mode:
			return true
		await tree.physics_frame
	return false


func _wait_for_robot_state(tree: SceneTree, robot: SentinelRobot, target_state: SentinelRobot.State, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		await tree.physics_frame
		await tree.process_frame
		if robot.state == target_state:
			return true
	return false


func _release_movement() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(action)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup_saves() -> void:
	var absolute_root := ProjectSettings.globalize_path(_save_root)
	for profile_number in range(1, 4):
		var stem := "%s/profile_%d.json" % [absolute_root, profile_number]
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(stem + suffix):
				DirAccess.remove_absolute(stem + suffix)
	if DirAccess.dir_exists_absolute(absolute_root):
		DirAccess.remove_absolute(absolute_root)
