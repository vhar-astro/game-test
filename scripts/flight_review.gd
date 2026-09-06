extends Node
## Staged render review and an actual 1080p flight benchmark; isolated profiles.

var game: InfinityGame
var root: Window
var output_dir := "user://flight-review"
var report := {"staged_render_benchmark":true, "scenes":{}, "screenshots":[]}

func _ready() -> void:
	root = get_tree().root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--flight-output="):
			output_dir = argument.trim_prefix("--flight-output=")
	call_deferred("capture")

func capture() -> void:
	game.store=SaveStore.new("user://flight_visual_qa")
	game.settings.fullscreen=true
	game.settings.locale="en"
	game.new_game(0)
	DisplayServer.window_set_title("Infinity Reality Flight Review")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	root.size=Vector2i(1920,1080)
	DirAccess.make_dir_recursive_absolute(output_dir+"/screenshots")
	await get_tree().create_timer(1).timeout
	report.engine=Engine.get_version_info().string
	report.renderer=RenderingServer.get_current_rendering_driver_name()
	report.gpu=RenderingServer.get_video_adapter_name()
	report.executable=OS.get_executable_path()
	var actual:=root.get_texture().get_size()
	report.resolution=[int(actual.x),int(actual.y)]
	if actual!=Vector2(1920,1080):
		push_error("Flight capture requires a 1920x1080 framebuffer")
		get_tree().quit(1)
		return
	game.player.set_view(.4,-.18)
	await snap("ship-boarding")
	game.player.position=game.flight.ship.boarding_positions()[1]
	if not await game.flight.board():
		push_error("Flight capture could not board ship")
		get_tree().quit(1)
		return
	game.flight.ship.set_pose(Vector3(-18,14,17),Vector3(-.35,.4,0),false)
	await snap("flight-forest")
	await benchmark("forest_flight")
	game.flight.ship.set_pose(Vector3(-29,7,6),Vector3.ZERO,false)
	await snap("flight-landing")
	if not await game.flight.land():
		push_error("Flight capture could not land at observatory")
		get_tree().quit(1)
		return
	await snap("landing-exit")
	game.player.position = Vector3(-25,1.03,9)
	game.player.reset_camera_follow()
	game.player.set_view(-.75,-.22)
	await snap("observatory")
	game.player.position=game.flight.ship.boarding_positions()[1]
	await game.flight.board()
	game.settings.locale="ru"
	game._apply_settings()
	game.flight.ship.set_pose(Vector3(-18,14,17),Vector3(-.35,.4,0),false)
	await snap("flight-ru")
	game.settings.locale="en"
	game._apply_settings()
	game.session.mark_puzzle_solved()
	game.session.mark_robot_defeated()
	game.session.collect_artifact()
	game.session.open_resonant_lock()
	game.session.collect_crystal()
	await game.travel("ruins",true)
	game.flight.ship.set_view(0,-.25)
	await snap("flight-ruins")
	await benchmark("ruins_flight")
	await game.travel("hub",true)
	game.flight.ship.set_view(.25,-.2)
	await snap("flight-hub")
	await benchmark("hub_flight")
	report.transition_seconds=game.transition_times
	var status: Array = []
	OS.execute("/bin/cat",PackedStringArray(["/proc/%d/status" % OS.get_process_id()]),status)
	for line in str(status[0]).split("\n"):
		if line.begins_with("VmHWM:") or line.begins_with("VmRSS:"):
			report[line.get_slice(":",0)]=line.get_slice(":",1).strip_edges()
	var file:=FileAccess.open(output_dir+"/flight-benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("FLIGHT_CAPTURE_OK ",JSON.stringify(report))
	game._shutdown()

func snap(label: String) -> void:
	await get_tree().create_timer(2.1).timeout
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png(output_dir+"/screenshots/"+label+".png")
	assert(result==OK)
	report.screenshots.append(label)
	print("SCREENSHOT ",label," ",result)

func benchmark(label: String) -> void:
	await get_tree().create_timer(2).timeout
	var frames: Array[float]=[]
	var start:=Time.get_ticks_usec()
	var previous:=start
	var yaw:=game.flight.ship.flight_yaw
	while Time.get_ticks_usec()-start<12000000:
		await get_tree().process_frame
		var now:=Time.get_ticks_usec()
		frames.append(float(now-previous)/1000)
		previous=now
		game.flight.ship.set_view(yaw+sin(float(now-start)/1000000*.5)*.6,-.22)
	frames.sort()
	var total:=0.0
	for frame in frames: total+=frame
	report.scenes[label]={"frames":frames.size(),"mean_fps":1000/(total/frames.size()),"worst_frame_fps":1000/frames[-1],"p99_frame_ms":frames[int(frames.size()*.99)],"seconds":total/1000}
