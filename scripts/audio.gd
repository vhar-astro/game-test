class_name SliceAudio
extends Node
## Fully offline generated score, with continuously crossfaded contextual layers.

var layers: Dictionary = {}
var context := "explore"
var music_volume := 0.45
var effects_volume := 0.75
var loops: Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	for layer in ["explore","puzzle","alert","boss"]:
		var player:=AudioStreamPlayer.new()
		var stream: AudioStreamWAV=load("res://assets/audio/"+layer+".wav").duplicate()
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=stream.data.size()/2
		player.stream=stream
		player.volume_db=-55
		add_child(player)
		player.play()
		layers[layer]=player

func set_context(value: String) -> void:
	context=value

func apply_volumes(settings: Dictionary) -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(float(settings.master)))
	music_volume=float(settings.music)
	effects_volume=float(settings.effects)

func _process(delta: float) -> void:
	for loop in loops:
		loop.volume_db = -16 + linear_to_db(maxf(effects_volume, 0.0001))
	for id: String in layers:
		var player: AudioStreamPlayer=layers[id]
		var target:=music_volume*(0.55 if id=="explore" else 0.75) if id==context or id=="explore" else 0.0001
		player.volume_db=lerpf(player.volume_db,linear_to_db(maxf(target,0.0001)),minf(1,delta*1.7))

func effect(id: String, at := Vector3.ZERO) -> void:
	var path:="res://assets/audio/"+id+".wav"
	if not ResourceLoader.exists(path): return
	var sound:=AudioStreamPlayer3D.new()
	sound.stream=load(path)
	sound.position=at
	sound.volume_db=linear_to_db(maxf(effects_volume,0.0001))
	sound.unit_size=9
	sound.max_distance=30
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func loop_spatial(id: String, at: Vector3) -> AudioStreamPlayer3D:
	var sound:=AudioStreamPlayer3D.new()
	var stream: AudioStreamWAV=load("res://assets/audio/"+id+".wav").duplicate()
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_end=stream.data.size()/2
	sound.stream=stream
	sound.position=at
	sound.unit_size=2
	sound.max_distance=12
	sound.volume_db=-16
	add_child(sound)
	sound.play()
	loops.append(sound)
	return sound

func clear_spatial() -> void:
	for loop in loops:
		loop.stop()
		loop.stream=null
		loop.queue_free()
	loops.clear()

func stop_all() -> void:
	set_process(false)
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream=null
	layers.clear()
	loops.clear()

func _exit_tree() -> void:
	stop_all()
