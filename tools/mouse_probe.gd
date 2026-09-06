extends SceneTree
## Keep a small live state file while a host injects native X11 events.

const MainScene := preload("res://scenes/main.tscn")
const SaveStoreScript := preload("res://scripts/data/save_store.gd")

var _game: InfinityGame
var _artifact_path := ""
var _window_title := ""
var _attack_count := 0
var _sequence := 0
var _flight_probe := false


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	_window_title = OS.get_environment("MOUSE_PROBE_TITLE")
	if _window_title.is_empty():
		_window_title = "Infinity Reality Mouse Probe"
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_artifact_path = OS.get_environment("MOUSE_PROBE_ARTIFACT")
	if _artifact_path.is_empty():
		_artifact_path = ProjectSettings.globalize_path("res://artifacts/mouse_probe.json")

	_game = MainScene.instantiate() as InfinityGame
	if _game == null:
		_write_snapshot(false, "main_scene_failed")
		quit(1)
		return
	root.add_child(_game)
	await process_frame
	# The script entrypoint runs before Godot has finalized the native window;
	# set the title after one frame so the host can match the exact X11 window.
	DisplayServer.window_set_title(_window_title)
	_game.store = SaveStoreScript.new("user://mouse_validation_%d" % Time.get_ticks_usec())
	if not _game.new_game(0):
		_write_snapshot(false, "isolated_new_game_failed")
		quit(1)
		return
	if is_instance_valid(_game.player):
		_game.player.attack_requested.connect(_on_attack)
	_flight_probe = OS.get_environment("MOUSE_PROBE_FLIGHT") == "1"
	if _flight_probe:
		if not is_instance_valid(_game.flight) or not is_instance_valid(_game.flight.ship):
			_write_snapshot(false, "ship_not_loaded")
			quit(1)
			return
		_game.player.global_position = _game.flight.ship.boarding_positions()[1]
		await physics_frame
		var boarded: bool = await _game.flight.board()
		if not boarded:
			_write_snapshot(false, "boarding_failed")
			quit(1)
			return
	else:
		# Ensure the probe is specifically exercising the transparent gameplay HUD.
		_game._set_mode("explore")
		_game.ui.show_hud()
		if OS.get_environment("MOUSE_PROBE_SCREEN_FILTER") == "stop":
			# Reproduce the pre-fix full-screen Control regression for a causal
			# comparison; the normal probe leaves the HUD pointer-transparent.
			_game.ui.get_node("Screen").mouse_filter = Control.MOUSE_FILTER_STOP
	for _frame in 30:
		await process_frame
	_write_snapshot(true, "ready")

	while true:
		await process_frame
		_write_snapshot(true, "running")


func _on_attack() -> void:
	_attack_count += 1


func _write_snapshot(ready: bool, phase: String) -> void:
	_sequence += 1
	var payload: Dictionary = {
		"ready": ready,
		"phase": phase,
		"sequence": _sequence,
		"window_title": _window_title,
		"viewport_size": _vector2_to_dict(_game.get_viewport().get_visible_rect().size) if is_instance_valid(_game) else {},
		"mode": _game.mode if is_instance_valid(_game) else "",
		"mouse_mode": Input.mouse_mode,
		"input_enabled": _game.player.input_enabled if is_instance_valid(_game) and is_instance_valid(_game.player) else false,
		"camera_yaw": _game.player.camera_yaw if is_instance_valid(_game) and is_instance_valid(_game.player) else 0.0,
		"camera_pitch": _game.player.camera_pitch if is_instance_valid(_game) and is_instance_valid(_game.player) else 0.0,
		"controller": "ship" if _flight_probe else "player",
		"ship_yaw": _game.flight.ship.flight_yaw if _flight_probe and is_instance_valid(_game.flight) and is_instance_valid(_game.flight.ship) else 0.0,
		"ship_pitch": _game.flight.ship.flight_pitch if _flight_probe and is_instance_valid(_game.flight) and is_instance_valid(_game.flight.ship) else 0.0,
		"attack_count": _attack_count,
		"player_position": _vector_to_dict(_game.player.global_position) if is_instance_valid(_game) and is_instance_valid(_game.player) else {},
		"resume_rect": _resume_rect(),
	}
	var file := FileAccess.open(_artifact_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()


func _vector_to_dict(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _vector2_to_dict(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _resume_rect() -> Dictionary:
	if not is_instance_valid(_game) or not is_instance_valid(_game.ui) or _game.mode != "pause":
		return {}
	var button := _find_resume_button(_game.ui)
	if button == null:
		return {}
	return {
		"x": button.global_position.x,
		"y": button.global_position.y,
		"width": button.size.x,
		"height": button.size.y,
	}


func _find_resume_button(node: Node) -> Button:
	if node is Button and (node as Button).text == tr("PAUSE_RESUME"):
		return node as Button
	for child in node.get_children():
		var found := _find_resume_button(child)
		if found != null:
			return found
	return null
