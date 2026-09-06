class_name InfinityGame
extends Node3D
## Coordinates gameplay through typed components and persistent stable identities.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const ROBOT_SCENE := preload("res://scenes/actors/sentinel.tscn")
const DIMENSIONS := {
	"forest":preload("res://assets/data/forest.tres"),
	"ruins":preload("res://assets/data/ruins.tres"),
	"hub":preload("res://assets/data/hub.tres")}
const PUZZLE: PuzzleDefinition = preload("res://assets/data/prism_array.tres")
const RESONANCE: AbilityDefinition = preload("res://assets/data/resonance.tres")
const DEFAULT_SETTINGS := {"fov":65.0,"sensitivity":0.003,"invert_y":false,"interaction_hold":false,"layout":"wasd","locale":"en","master":0.8,"music":0.45,"effects":0.75,"fullscreen":false,"quality":"high"}
var session := GameSession.new()
var store := SaveStore.new()
var checkpoint: Dictionary = {}
var world: SliceWorld
var player: ExplorerPlayer
var robot: SentinelRobot
var ui: GameInterface
var audio: SliceAudio
var flight: FlightCoordinator
var _interact_needs_release := false
var _application_focused := true
var _render_review := false
var active_profile := 0
var mode := "menu"
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var resonance_cooldown := 0.0
var nearest_id := ""
var hold_elapsed := 0.0
var last_safe := Vector3.ZERO
var camera_puzzle: Camera3D
var selected_prism := 0
var transition_times: Array[float] = []
var _return_from_settings := "menu"
var _was_grounded := true
var _game_started := false
var _saved_camera_view := Vector2.ZERO
var _boundary_timer := 0.0
var _active_encounter := false
var _save_failed := false
var _decay_material: ShaderMaterial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_setup_input()
	_load_settings()
	ui = GameInterface.new()
	add_child(ui)
	ui.command.connect(_on_command)
	audio = SliceAudio.new()
	add_child(audio)
	flight = FlightCoordinator.new()
	flight.game = self
	add_child(flight)
	_create_decay_overlay()
	_apply_settings()
	_connect_session()
	_load_world("forest", false)
	_set_mode("menu")
	ui.show_main(_profiles())
	if OS.get_cmdline_user_args().has("--flight-review"):
		call_deferred("_run_flight_review")
	elif OS.get_cmdline_user_args().has("--benchmark"):
		call_deferred("_run_benchmark")
	elif OS.get_cmdline_user_args().has("--smoke-test"):
		call_deferred("_export_smoke")

func _connect_session() -> void:
	session.puzzle_completed.connect(func(_id): _reward("puzzle", "PUZZLE_COMPLETE"))
	session.enemy_defeated.connect(func(_id): _reward("defeat", "ROBOT_DEFEATED"))
	session.artifact_acquired.connect(func(_id): _reward("artifact", "ARTIFACT_FOUND"))
	session.crystal_acquired.connect(func(_id): _reward("crystal", "CRYSTAL_MEMORY"))

func _setup_input() -> void:
	var keys := {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"jump":KEY_SPACE,"ship_descend":KEY_CTRL,"sprint":KEY_SHIFT,"interact":KEY_E,"resonance":KEY_1,"pause":KEY_ESCAPE}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode=keys[action]
		InputMap.action_add_event(action,event)
	if not InputMap.has_action("attack"): InputMap.add_action("attack")
	InputMap.action_erase_events("attack")
	var click := InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack",click)

func _profiles() -> Array:
	var profiles: Array=[]
	for i in range(3): profiles.append(store.profile_summary(i))
	return profiles

func new_game(profile := -1) -> bool:
	if profile>=0: active_profile=profile
	var writable:=store.can_write_profile(active_profile)
	if not writable.ok:
		ui.toast(tr("SAVE_FUTURE") if writable.error==SaveStore.ERROR_UNSUPPORTED_VERSION else tr("SAVE_UNAVAILABLE"))
		return false
	session.new_game()
	session.prism_orientations.assign([1,2,3])
	session.player_position=Vector3(0,.12,15)
	checkpoint=session.to_dict()
	_game_started=true
	_active_encounter=false
	_load_world("forest",true)
	_set_mode("explore")
	ui.show_hud()
	_save()
	ui.toast(tr("ARRIVAL"))
	return true

func continue_game(profile := -1) -> bool:
	if profile>=0: active_profile=profile
	var loaded:=store.load_profile(active_profile)
	if not loaded.ok:
		ui.toast(tr("SAVE_FUTURE") if loaded.error==SaveStore.ERROR_UNSUPPORTED_VERSION else tr("SAVE_UNAVAILABLE"))
		return false
	if not session.restore(loaded.data.resume): return false
	checkpoint=loaded.data.checkpoint.duplicate(true)
	_game_started=true
	_load_world(session.scene_id,true)
	_resume_game()
	if loaded.recovered: ui.toast(tr("SAVE_RECOVERED"))
	return true

func _load_world(id: String, restore_position: bool) -> void:
	flight.unload()
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	if is_instance_valid(player):
		remove_child(player)
		player.queue_free()
	if is_instance_valid(robot):
		remove_child(robot)
		robot.queue_free()
	robot=null
	var definition: DimensionDefinition=DIMENSIONS[id]
	world=load(definition.scene_path).instantiate()
	world.set_meta("build_by_main",true)
	add_child(world)
	world.build(id,session)
	player=PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position=session.player_position if restore_position else world.spawn_position
	player.set_health(session.health)
	player.gravity=18.0*definition.gravity_scale
	player.set_view(session.player_rotation.y,session.player_rotation.x if restore_position else -0.18)
	player.attack_requested.connect(_blade_hit)
	player.resonance_requested.connect(use_resonance)
	player.died.connect(_on_death)
	player.health_changed.connect(func(value): session.health=value; audio.effect("hit",player.global_position))
	player.noise_emitted.connect(_on_noise)
	last_safe=player.global_position
	if id=="forest" and not session.robot_defeated:
		robot=ROBOT_SCENE.instantiate()
		robot.player=player
		robot.patrol_points.assign([Vector3(-4,0,-21),Vector3(0,0,-24),Vector3(6,0,-19)])
		add_child(robot)
		robot.position=world.robot_position
		robot.rotation.y=0.0
		robot.defeated.connect(_on_robot_defeated)
		robot.attack_hit.connect(func(amount):
			if mode=="explore": player.take_damage(amount)
		)
		robot.alert_changed.connect(func(alert):
			audio.set_context("alert" if alert else "explore")
		)
	_apply_settings()
	resonance_cooldown=0
	_active_encounter=false
	audio.set_context("explore")
	audio.clear_spatial()
	if id=="forest":
		audio.loop_spatial("puzzle",Vector3(-5,1,4))
		audio.loop_spatial("crystal",Vector3(0,1,-38))
	flight.load_ship()
	player.reset_camera_follow()
	_set_mode(mode)

func _set_mode(value: String) -> void:
	mode=value
	if mode!="explore" and _decay_material!=null:
		_decay_material.set_shader_parameter("intensity",0.0)
		_boundary_timer=0.0
	var active:=mode=="explore"
	if is_instance_valid(player): player.input_enabled=active and not _render_review
	if is_instance_valid(robot): robot.enabled=active and session.puzzle_solved
	if is_instance_valid(flight):
		flight.set_active(mode=="flight")
		if _render_review and is_instance_valid(flight.ship): flight.ship.input_enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if mode in ["explore","flight"] and not _render_review else Input.MOUSE_MODE_VISIBLE
	if mode not in ["explore","flight"]:
		_interact_needs_release=true
		hold_elapsed=0
	# Freeze actors through process mode while menus remain interactive.
	if is_instance_valid(player): player.set_physics_process(mode=="explore")
	if is_instance_valid(robot): robot.set_physics_process(mode=="explore")
	if is_instance_valid(world): world.set_process(mode in ["explore","flight","menu","puzzle"])

func _resume_game() -> void:
	if not _application_focused and not _render_review:
		_set_mode("pause")
		ui.show_pause()
		return
	_set_mode("flight" if flight.aboard() else "explore")
	# Menu clicks must not become an attack after the same-frame handoff.
	Input.action_release("attack")
	ui.show_hud()

func _unhandled_input(event: InputEvent) -> void:
	if _render_review: return
	if event.is_echo(): return
	if event.is_action_released("interact"):
		_interact_needs_release=false
	if event.is_action_pressed("pause"):
		if mode=="puzzle": close_puzzle()
		elif mode in ["explore","flight"]:
			_set_mode("pause")
			ui.show_pause()
		elif mode=="pause": _resume_game()
		get_viewport().set_input_as_handled()
	elif mode in ["explore","flight"] and event.is_action_pressed("interact") and not settings.interaction_hold and not _interact_needs_release:
		if mode=="flight": flight.interact()
		else: interact(nearest_id)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if mode not in ["explore","flight","puzzle"]: return
	if not Input.is_action_pressed("interact"): _interact_needs_release=false
	if mode=="flight":
		flight.tick(delta)
		if settings.interaction_hold and Input.is_action_pressed("interact") and not _interact_needs_release:
			hold_elapsed+=delta
			if hold_elapsed>=.45:
				_interact_needs_release=true
				flight.interact()
		else: hold_elapsed=0
		return
	resonance_cooldown=maxf(0,resonance_cooldown-delta)
	if session.scene_id=="forest" and not session.puzzle_solved:
		var was_available:=session.hint_elapsed>=PUZZLE.hint_delay_seconds
		session.hint_elapsed+=delta
		if mode=="puzzle" and not was_available and session.hint_elapsed>=PUZZLE.hint_delay_seconds:
			ui.show_puzzle(session.prism_orientations,true,session.hint_level)
	if mode=="puzzle": return
	_boundary_timer=maxf(0,_boundary_timer-delta)
	var edge_distance:=world.surface_boundary_distance(player.global_position)
	var decay:=maxf(clampf((.85-edge_distance)/.85,0,1)*.65,_boundary_timer*.6)
	if player.position.y<-0.4: decay=maxf(decay,0.6)
	_decay_material.set_shader_parameter("intensity",decay)
	if player.is_on_floor() and edge_distance>0.4:
		last_safe=player.global_position
	if player.global_position.y < -4:
		player.global_position=last_safe+Vector3.UP*.15
		player.velocity=Vector3.ZERO
		ui.toast(tr("BOUNDARY_RETURN"))
		_boundary_timer=1.0
	if not _was_grounded and player.is_on_floor(): audio.effect("land",player.global_position)
	_was_grounded=player.is_on_floor()
	nearest_id=_find_interaction()
	if settings.interaction_hold and Input.is_action_pressed("interact") and not nearest_id.is_empty() and not _interact_needs_release:
		hold_elapsed+=delta
		if hold_elapsed>=0.45:
			interact(nearest_id)
			hold_elapsed=-100
	else: hold_elapsed=0
	if session.scene_id=="forest":
		_collect_nearby()
		if session.puzzle_solved and not session.robot_defeated and player.position.z<-15 and not _active_encounter:
			_active_encounter=true
			# The checkpoint is outside enemy reach and retains the solved prism court.
			var position_before:=player.position
			player.position=Vector3(0,.12,-15.2)
			_sync_session()
			checkpoint=session.to_dict()
			player.position=position_before
			_save()
	ui.update_hud(session,resonance_cooldown,_objective(),_prompt(nearest_id))

func _find_interaction() -> String:
	var best:=""
	var best_distance:=3.5
	var boarding_point:=flight.nearest_boarding_point()
	if boarding_point!=Vector3.INF:
		best="ship"
		best_distance=player.global_position.distance_to(boarding_point)
	for id: String in world.interactables:
		var obj: Node3D=world.interactables[id].node
		if not obj.visible: continue
		var pos:=world.interaction_position(id)
		var distance:=player.global_position.distance_to(pos)
		if distance<best_distance and _line_clear(player.global_position+Vector3.UP,pos):
			best_distance=distance
			best=id
	return best

func _prompt(id: String) -> String:
	if id.is_empty(): return ""
	if id=="ship": return tr("SHIP_BOARD")
	if id.begins_with("prism_"): return tr("INTERACT_PRISM")
	match id:
		"reset": return tr("INTERACT_RESET")
		"artifact": return tr("INTERACT_ARTIFACT")
		"crystal": return tr("INTERACT_CRYSTAL")
		"lock": return tr("INTERACT_RESONANCE") if session.artifact_collected else tr("LOCKED")
		"portal": return tr("INTERACT_PORTAL") if session.crystal_collected else tr("PORTAL_LOCKED")
		"shard": return tr("INTERACT_SHARD")
		"return_hub": return tr("INTERACT_HUB")
		"hub_forest": return tr("INTERACT_FOREST")
		"hub_ruins": return tr("INTERACT_RUINS") if session.crystal_collected else tr("PORTAL_LOCKED")
	return ""

func interact(id: String) -> void:
	if mode!="explore" or id.is_empty(): return
	if id=="ship":
		flight.board()
		return
	if not world.interactables.has(id): return
	if player.position.distance_to(world.interaction_position(id))>3.5: return
	if id.begins_with("prism_"):
		if not session.puzzle_solved: open_puzzle(int(id.trim_prefix("prism_")))
		else: ui.toast(tr("PUZZLE_COMPLETE"))
		return
	match id:
		"reset":
			if not session.puzzle_solved: open_puzzle(0)
		"artifact", "crystal", "shard": _collect_nearby(3.5)
		"lock": ui.toast(tr("INTERACT_RESONANCE"))
		"portal":
			if session.crystal_collected: travel("ruins")
			else: ui.toast(tr("PORTAL_LOCKED"))
		"return_hub": travel("hub")
		"hub_forest": travel("forest")
		"hub_ruins":
			if session.crystal_collected: travel("ruins")
			else: ui.toast(tr("PORTAL_LOCKED"))

func open_puzzle(index: int) -> void:
	if mode!="explore" or session.puzzle_solved: return
	selected_prism=index
	player.play_interaction()
	_saved_camera_view=Vector2(player.camera_yaw,player.camera_pitch)
	_set_mode("puzzle")
	camera_puzzle=Camera3D.new()
	add_child(camera_puzzle)
	camera_puzzle.global_transform=player.camera.global_transform
	camera_puzzle.fov=65
	camera_puzzle.make_current()
	var destination:=Transform3D.IDENTITY
	destination.origin=Vector3(0,17,12)
	destination=destination.looking_at(Vector3(0,0,-2),Vector3.UP)
	create_tween().tween_property(camera_puzzle,"global_transform",destination,.45).set_trans(Tween.TRANS_CUBIC)
	ui.show_puzzle(session.prism_orientations,session.hint_elapsed>=90,session.hint_level)
	audio.set_context("puzzle")

func rotate_prism(index: int) -> void:
	if mode!="puzzle" or session.puzzle_solved or index<0 or index>2: return
	session.set_prism_orientation(index,(session.prism_orientations[index]+1)%4)
	audio.effect("rotate",world.PRISM_POINTS[index])
	world.apply_state(session)
	ui.show_puzzle(session.prism_orientations,session.hint_elapsed>=90,session.hint_level)
	if session.prism_orientations==PUZZLE.target_orientations:
		session.mark_puzzle_solved()
		close_puzzle()
		_sync_session()
		checkpoint=session.to_dict()
		_save()

func close_puzzle() -> void:
	if mode!="puzzle": return
	if is_instance_valid(camera_puzzle): camera_puzzle.queue_free()
	player.camera.make_current()
	player.set_view(_saved_camera_view.x,_saved_camera_view.y)
	_set_mode("explore")
	ui.show_hud()
	audio.set_context("explore")
	_save()

func reset_puzzle() -> void:
	if mode!="puzzle" or session.puzzle_solved: return
	session.prism_orientations.assign([1,2,3])
	world.apply_state(session)
	ui.show_puzzle(session.prism_orientations,session.hint_elapsed>=90,session.hint_level)

func _blade_hit() -> void:
	if mode!="explore": return
	audio.effect("blade",player.global_position)
	if not is_instance_valid(robot) or robot.health<=0: return
	var offset:=robot.global_position-player.global_position
	offset.y=0
	var forward:=-player.camera.global_basis.z
	forward.y=0
	if offset.length()<=2.6 and forward.normalized().dot(offset.normalized())>0.15 and _line_clear(player.position+Vector3.UP,robot.position+Vector3.UP):
		robot.take_damage(10)
		audio.effect("hit",robot.position)

func _line_clear(from: Vector3, to: Vector3) -> bool:
	var query:=PhysicsRayQueryParameters3D.create(from,to,1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func use_resonance() -> bool:
	if mode!="explore" or not session.artifact_collected or resonance_cooldown>0: return false
	resonance_cooldown=RESONANCE.cooldown_seconds
	player.play_interaction()
	audio.effect("resonance",player.global_position)
	_pulse_effect()
	if session.scene_id!="forest" or session.lock_open: return true
	var target:=world.interaction_position("lock")
	var direction:=(target-(player.position+Vector3.UP)).normalized()
	var forward:=-player.camera.global_basis.z
	if player.position.distance_to(target)<=8 and forward.dot(direction)>0.3 and _line_clear(player.position+Vector3.UP,target):
		if session.open_resonant_lock():
			world.apply_state(session)
			ui.toast(tr("LOCK_OPEN"))
			_save()
	return true

func _pulse_effect() -> void:
	var effect:=MeshInstance3D.new()
	var ring:=TorusMesh.new()
	ring.inner_radius=.93
	ring.outer_radius=1
	ring.rings=32
	ring.ring_segments=6
	effect.mesh=ring
	effect.position=player.position+Vector3.UP*.8
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(.2,1,.75,.7)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	effect.material_override=material
	add_child(effect)
	var tween:=create_tween().set_parallel(true)
	tween.tween_property(effect,"scale",Vector3(8,.4,8),.5)
	tween.tween_property(material,"albedo_color:a",0,.5)
	tween.chain().tween_callback(effect.queue_free)

func _on_noise(position: Vector3, loudness: float) -> void:
	if is_instance_valid(robot): robot.notify_noise(position,loudness)
	if loudness<=4: audio.effect("step",position)
	elif loudness==6: audio.effect("jump",position)

func _on_robot_defeated() -> void:
	if session.mark_robot_defeated():
		world.apply_state(session)
		_save()
		audio.set_context("explore")

func _collect_nearby(distance := 1.7) -> void:
	for id in ["artifact","crystal","shard"]:
		var node: Node3D=world.interactables[id].node
		if not node.visible or player.position.distance_to(node.position)>distance: continue
		if not _line_clear(player.position+Vector3.UP,node.position): continue
		var collected:=false
		match id:
			"artifact": collected=session.collect_artifact()
			"crystal": collected=session.collect_crystal()
			"shard":
				if not session.memory_shards.has(GameSession.MEMORY_SHARD_ID):
					session.memory_shards.append(GameSession.MEMORY_SHARD_ID)
					ui.toast(tr("SHARD_MEMORY"))
					collected=true
		if collected:
			player.play_interaction()
			_pickup_effect(node.global_position)
			world.apply_state(session)
			_save()

func _pickup_effect(from: Vector3) -> void:
	for i in range(8):
		var spark:=world.model("crystal",from+Vector3(sin(i)*.3,.15,cos(i)*.3),Vector3.ONE*.06)
		var tween:=create_tween()
		tween.tween_property(spark,"position",player.position+Vector3.UP*1.2,.45+float(i)*.025)
		tween.tween_callback(spark.queue_free)

func _reward(sound: String, text_key: String) -> void:
	audio.effect(sound,player.position)
	world.apply_state(session)
	ui.toast(tr(text_key))

func travel(destination: String, with_ship := false) -> bool:
	if mode not in ["explore","flight"] or not DIMENSIONS.has(destination): return false
	if with_ship!=flight.aboard(): return false
	if destination=="ruins" and not session.crystal_collected: return false
	_save()
	_set_mode("transition")
	ui.show_transition(0)
	var start:=Time.get_ticks_msec()
	audio.effect("portal",player.position)
	await get_tree().create_timer(.5).timeout
	if mode!="transition": return false
	if with_ship:
		if not session.travel_ship_to(destination, SliceWorld.ship_dock(destination)+Vector3.UP*4, Vector3.ZERO): return false
		session.set_ship_state(destination,session.ship_position,session.ship_rotation,false,SliceWorld.ship_dock(destination),0)
	else:
		if not session.travel_to(destination): return false
	_load_world(destination,false)
	player.set_view(PI if destination=="ruins" else 0,-.18)
	_sync_session()
	checkpoint=session.to_dict()
	_save()
	await get_tree().create_timer(.35).timeout
	transition_times.append((Time.get_ticks_msec()-start)/1000.0)
	ui.hide_transition()
	_resume_game()
	if destination=="ruins": ui.toast(tr("RUINS_PREVIEW"))
	return true

func _on_death() -> void:
	_set_mode("respawn")
	ui.toast(tr("CHECKPOINT_RESTORE"))
	await get_tree().create_timer(1.0).timeout
	if not session.restore(checkpoint): return
	session.health=100
	_load_world(session.scene_id,true)
	_resume_game()
	# Do not replace the resume snapshot with a partially restored world.
	_save()

func _sync_session(include_scene := true) -> void:
	if not is_instance_valid(player): return
	if include_scene: session.scene_id=world.scene_id
	session.player_position=player.position
	session.player_rotation=Vector3(player.camera_pitch,player.camera_yaw,0)
	session.health=player.health
	flight.sync_session()

func _save() -> bool:
	if not _game_started: return false
	if mode not in ["transition","boarding","landing"]: _sync_session()
	if checkpoint.is_empty(): checkpoint=session.to_dict()
	var result:=store.save_profile(active_profile,session.to_dict(),checkpoint)
	if result!=OK:
		if not _save_failed: ui.toast(tr("SAVE_FAILED"))
		_save_failed=true
		push_warning("SAVE_FAILED code="+str(result))
		return false
	_save_failed=false
	return true

func _objective() -> String:
	if session.scene_id=="hub": return tr("OBJECTIVE_HUB")
	if session.scene_id=="ruins": return tr("OBJECTIVE_RUINS")
	if not session.puzzle_solved: return tr("OBJECTIVE_PUZZLE")
	if not session.robot_defeated: return tr("OBJECTIVE_ROBOT")
	if not session.artifact_collected: return tr("OBJECTIVE_ARTIFACT")
	if not session.lock_open: return tr("OBJECTIVE_LOCK")
	if not session.crystal_collected: return tr("OBJECTIVE_CRYSTAL")
	return tr("OBJECTIVE_PORTAL")

func _on_command(action: String, value: Variant = null) -> void:
	match action:
		"select_profile": active_profile=int(value)
		"new_game":
			var existing:=store.load_profile(active_profile)
			if store.profile_summary(active_profile).exists:
				var confirm:=ConfirmationDialog.new()
				confirm.dialog_text=tr("CONFIRM_NEW_GAME")
				confirm.title=tr("NEW_GAME")
				confirm.confirmed.connect(func(): new_game(); confirm.queue_free())
				confirm.canceled.connect(confirm.queue_free)
				add_child(confirm)
				confirm.popup_centered(Vector2i(540,180))
			else: new_game()
		"continue": continue_game()
		"resume": _resume_game()
		"collection": _set_mode("pause"); ui.show_collection(session)
		"collection_back": ui.show_pause()
		"settings":
			_return_from_settings="menu" if mode=="menu" else "pause"
			ui.show_settings(settings)
		"setting":
			if value is Dictionary and settings.has(value.key):
				settings[value.key]=value.value
				_apply_settings()
				_save_settings()
		"settings_back":
			if _return_from_settings=="menu": ui.show_main(_profiles())
			else: ui.show_pause()
		"hub":
			_resume_game()
			travel("hub",flight.aboard())
		"rotate": rotate_prism(int(value))
		"reset_puzzle": reset_puzzle()
		"hint":
			if mode=="puzzle" and session.hint_elapsed>=90:
				session.hint_level=mini(3,session.hint_level+1)
				ui.show_puzzle(session.prism_orientations,true,session.hint_level)
		"close_puzzle": close_puzzle()
		"quit_to_menu":
			_save()
			_set_mode("menu")
			ui.show_main(_profiles())
		"quit": _quit()

func _apply_settings() -> void:
	if TranslationServer.get_locale()!=str(settings.locale):
		TranslationServer.set_locale(str(settings.locale))
		if is_instance_valid(ui): ui.set_locale(str(settings.locale))
	if is_instance_valid(player):
		player.set_camera_fov(float(settings.fov))
		player.mouse_sensitivity=float(settings.sensitivity)
		player.invert_y=bool(settings.invert_y)
	if is_instance_valid(flight): flight.apply_settings()
	var arrows: bool=settings.layout=="arrows"
	var keys: Array=[KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT] if arrows else [KEY_W,KEY_S,KEY_A,KEY_D]
	var names: Array[String]=["move_forward","move_back","move_left","move_right"]
	for i in range(4):
		InputMap.action_erase_events(names[i])
		var event:=InputEventKey.new()
		event.physical_keycode=keys[i]
		InputMap.action_add_event(names[i],event)
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if is_instance_valid(audio): audio.apply_volumes(settings)
	if is_instance_valid(world):
		for label in world.find_children("*", "Label3D", true, false):
			if label.has_meta("locale_key"): label.text=tr(str(label.get_meta("locale_key")))
		for child in world.get_children():
			if child is DirectionalLight3D: child.shadow_enabled=settings.quality=="high"

func _load_settings() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")==OK:
		for key in DEFAULT_SETTINGS:
			var value: Variant=config.get_value("settings",key,DEFAULT_SETTINGS[key])
			if typeof(value)==typeof(DEFAULT_SETTINGS[key]): settings[key]=value
	else:
		settings.locale="ru" if OS.get_locale_language()=="ru" else "en"
	settings.fov=clampf(float(settings.fov),60,70)
	settings.sensitivity=clampf(float(settings.sensitivity),.001,.01)
	for key in ["master","music","effects"]: settings[key]=clampf(float(settings[key]),0,1)
	if settings.locale not in ["en","ru"]: settings.locale="en"
	if settings.layout not in ["wasd","arrows"]: settings.layout="wasd"

func _save_settings() -> void:
	var config:=ConfigFile.new()
	for key in settings: config.set_value("settings",key,settings[key])
	config.save("user://settings.cfg")

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST: _quit()
	elif what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_focused=false
		if mode in ["explore","flight"] and not _render_review:
			_set_mode("pause")
			ui.show_pause()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:
		_application_focused=true

func _quit() -> void:
	if _game_started and mode!="respawn": _save()
	_save_settings()
	_shutdown()

func _shutdown() -> void:
	_set_mode("shutdown")
	audio.stop_all()
	# Give the audio mixer time to release playback refs before engine teardown.
	get_tree().create_timer(.2).timeout.connect(get_tree().quit)

func _create_decay_overlay() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=-1
	add_child(layer)
	var overlay:=ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_decay_material=ShaderMaterial.new()
	_decay_material.shader=load("res://scripts/decay.gdshader")
	_decay_material.set_shader_parameter("intensity",0.0)
	overlay.material=_decay_material
	layer.add_child(overlay)

func _export_smoke() -> void:
	store=SaveStore.new("user://export_smoke")
	new_game(0)
	await get_tree().create_timer(1).timeout
	print("EXPORT_SMOKE_OK ",RenderingServer.get_current_rendering_driver_name())
	_shutdown()

func _run_benchmark() -> void:
	# Explicit developer flag; isolated profile, no normal player-save writes.
	store=SaveStore.new("user://benchmark")
	settings.fullscreen=true
	new_game(0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_set_size(Vector2i(1920,1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var report:={"engine":Engine.get_version_info().string,"executable":OS.get_executable_path(),"renderer":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":[1920,1080],"vsync":false,"staged_render_benchmark":true,"scenes":{}}
	await get_tree().create_timer(.3).timeout
	var actual_size:=get_viewport().get_texture().get_size()
	report.resolution=[int(actual_size.x),int(actual_size.y)]
	report.window_size=[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y]
	if actual_size!=Vector2(1920,1080):
		push_error("Benchmark requires an actual 1920x1080 framebuffer; got "+str(actual_size))
		_shutdown()
		return
	for id in ["forest","ruins","hub"]:
		if id!="forest":
			session.mark_puzzle_solved()
			session.mark_robot_defeated()
			session.collect_artifact()
			session.open_resonant_lock()
			session.collect_crystal()
			await travel(id)
		player.set_view(0,-.18)
		await get_tree().create_timer(3.0).timeout
		var frames: Array[float]=[]
		var start:=Time.get_ticks_usec()
		var previous:=start
		while (Time.get_ticks_usec()-start)<12000000:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec()
			frames.append(float(now-previous)/1000.0)
			previous=now
			var elapsed:=float(now-start)/1000000.0
			player.set_view(sin(elapsed*.45)*.7,-.18)
		frames.sort()
		var total:=0.0
		for value in frames: total+=value
		report.scenes[id]={"frames":frames.size(),"seconds":total/1000.0,"mean_fps":1000.0/(total/frames.size()),"worst_frame_fps":1000.0/frames[-1],"p99_frame_ms":frames[int(frames.size()*.99)],"p95_frame_ms":frames[int(frames.size()*.95)],"engine_memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}
	report.transition_seconds=transition_times
	var status:=FileAccess.get_file_as_string("/proc/self/status")
	for line in status.split("\n"):
		if line.begins_with("VmHWM:") or line.begins_with("VmRSS:"):
			report[line.get_slice(":",0)]=line.get_slice(":",1).strip_edges()
	var output:="user://benchmark.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--benchmark-output="): output=argument.trim_prefix("--benchmark-output=")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("BENCHMARK_OK ",JSON.stringify(report))
	_shutdown()

func _run_flight_review() -> void:
	_render_review=true
	var review = load("res://scripts/flight_review.gd").new()
	review.game = self
	add_child(review)
