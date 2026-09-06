extends SceneTree
## Render a deterministic ship frame for visual review.

const ShipScene := preload("res://scenes/actors/ship.tscn")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_title("Infinity Reality Ship Capture")
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var environment := WorldEnvironment.new()
	var scene_environment := Environment.new()
	scene_environment.background_mode = Environment.BG_COLOR
	scene_environment.background_color = Color("07131e")
	scene_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	scene_environment.ambient_light_color = Color("8bb5c6")
	scene_environment.ambient_light_energy = 0.75
	environment.environment = scene_environment
	root.add_child(environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_color = Color("d9f7ff")
	key_light.light_energy = 1.8
	key_light.shadow_enabled = true
	root.add_child(key_light)

	var floor := StaticBody3D.new()
	floor.name = "CaptureFloor"
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 0.2, 40.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.1
	floor.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("102a37")
	floor_material.metallic = 0.15
	floor_material.roughness = 0.68
	plane.material = floor_material
	floor_mesh.mesh = plane
	floor.add_child(floor_mesh)
	root.add_child(floor)

	var ship := ShipScene.instantiate() as ExplorerShip
	if ship == null:
		push_error("ship scene should instantiate for visual capture")
		quit(1)
		return
	ship.name = "CaptureShip"
	root.add_child(ship)
	await process_frame
	ship.set_pose(Vector3(0.0, 0.0, 0.0), Vector3(deg_to_rad(-8.0), deg_to_rad(-22.0), 0.0), false)
	for _frame in 45:
		await process_frame
	await RenderingServer.frame_post_draw

	var output_path := ProjectSettings.globalize_path("res://artifacts/screenshots/ship.png")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image := root.get_texture().get_image()
	var result := image.save_png(output_path)
	print("SHIP_CAPTURE ", output_path, " ", result)
	if result != OK:
		quit(1)
		return
	print("SHIP_CAPTURE_OK")
	quit(0)
