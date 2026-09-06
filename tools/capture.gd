extends SceneTree
## Staged visual QA, not a claim of input-driven gameplay completion.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.store=SaveStore.new("user://visual_qa")
	game.settings.fullscreen=true
	game.new_game(0)
	root.size=Vector2i(1920,1080)
	for i in range(90): await process_frame
	DirAccess.make_dir_recursive_absolute("res://artifacts/screenshots")
	await snap("forest")
	game.player.position=Vector3(10.7,.12,5)
	game.player.set_view(-PI/2,-.18)
	for i in range(30): await process_frame
	await snap("boundary")
	game.player.position=Vector3(-5,0.1,6.5)
	game.player.set_view(0,-.18)
	game.open_puzzle(0)
	for i in range(60): await process_frame
	await snap("puzzle")
	game.close_puzzle()
	game._set_mode("pause")
	game.ui.show_pause()
	await snap("pause")
	game.settings.locale="ru"
	game._apply_settings()
	game.ui.show_settings(game.settings)
	await snap("settings-ru")
	game.settings.locale="en"
	game._apply_settings()
	game.session.mark_puzzle_solved()
	game.session.mark_robot_defeated()
	game.session.collect_artifact()
	game.session.open_resonant_lock()
	game.session.collect_crystal()
	game._set_mode("explore")
	await game.travel("ruins")
	for i in range(90): await process_frame
	game.player.set_view(0,-.15)
	for i in range(30): await process_frame
	await snap("ruins")
	await game.travel("hub")
	for i in range(90): await process_frame
	await snap("hub")
	game._set_mode("menu")
	game.ui.show_main(game._profiles())
	await snap("menu")
	print("VISUAL_CAPTURE_OK")
	game._shutdown()

func snap(label: String) -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	var result:=picture.save_png("res://artifacts/screenshots/"+label+".png")
	print("SCREENSHOT ",label," ",result)
