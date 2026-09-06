extends RefCounted

const ShipScene := preload("res://scenes/actors/ship.tscn")

var _failures: Array[String] = []


func run(tree: SceneTree) -> Array[String]:
	_failures.clear()
	var ship := ShipScene.instantiate() as ExplorerShip
	if ship == null:
		return ["ship scene should instantiate as ExplorerShip"]
	tree.root.add_child(ship)
	await tree.physics_frame
	_expect(ship.collision_layer == 16 and ship.collision_mask == 5, "ship should use layer 16 and collide with world and robots")
	_expect(ship.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING, "ship should use floating CharacterBody3D motion")
	_expect(is_equal_approx(ship.get_node("Visual").scale.x, 1.25), "ship visual should bind the supplied model at scale 1.25")
	_expect(is_equal_approx(ship.get_node("Visual").rotation.y, PI), "ship visual should turn local +Z model nose toward controller -Z forward")
	ship.set_view(1.1, deg_to_rad(90.0))
	_expect(is_equal_approx(ship.flight_yaw, 1.1) and is_equal_approx(ship.flight_pitch, deg_to_rad(60.0)), "set_view should retain yaw and clamp pitch to 60 degrees")
	ship.set_view(0.0, -0.3)
	var visual_nose := (ship.get_node("Visual") as Node3D).global_basis.z.normalized()
	var expected_flight_nose := Basis(Vector3.RIGHT, -0.3) * Vector3.FORWARD
	_expect(visual_nose.dot(expected_flight_nose) > 0.999, "visual model nose should match the controller flight direction after its +Z to -Z binding")
	ship.set_pose(Vector3(2.0, 3.0, 4.0), Vector3(0.2, 0.5, 0.3), true)
	_expect(ship.landed and ship.velocity == Vector3.ZERO and is_equal_approx(ship.flight_pitch, 0.0), "landed pose should level craft and clear velocity")
	var positions := ship.boarding_positions()
	_expect(positions.size() == 4 and positions[0].distance_to(ship.global_position) > 3.9, "boarding positions should provide side and fore/aft access")
	ship.queue_free()
	await tree.process_frame
	return _failures.duplicate()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
