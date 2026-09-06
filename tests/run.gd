extends SceneTree

## Small, dependency-free test harness for headless CI.
## Test suites expose run() -> Array[String], where each returned string is a
## human-readable failure. Scene smoke tests ensure authored scenes instantiate
## and survive a few physics frames without relying on a display server.

const SUITE_SCRIPTS: Array[Script] = [
	preload("res://tests/test_combat.gd"),
	preload("res://tests/test_persistence.gd"),
]
const SCENE_PATHS: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/forest.tscn",
	"res://scenes/ruins.tscn",
	"res://scenes/hub.tscn",
	"res://scenes/actors/player.tscn",
	"res://scenes/actors/sentinel.tscn",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for suite_script: Script in SUITE_SCRIPTS:
		var suite = suite_script.new()
		var suite_failures: Array[String] = suite.run()
		for failure: String in suite_failures:
			_failures.append("%s: %s" % [suite_script.resource_path, failure])

	# The integrated slice suite is optional while the authored world is being
	# assembled. Its async signature receives this SceneTree so it can load and
	# drive the playable scene without introducing another test framework.
	var integration_script: Script = null
	if _failures.is_empty() and ResourceLoader.exists("res://tests/test_slice.gd"):
		integration_script = load("res://tests/test_slice.gd") as Script
	if integration_script != null:
		var integration_suite = integration_script.new()
		var integration_failures: Array[String] = await integration_suite.run(self)
		for failure: String in integration_failures:
			_failures.append("%s: %s" % [integration_script.resource_path, failure])

	for scene_path: String in SCENE_PATHS:
		await _smoke_scene(scene_path)

	if _failures.is_empty():
		print("ALL_TESTS_OK")
		quit(0)
		return

	for failure: String in _failures:
		push_error(failure)
	print("TEST_FAILURES=%d" % _failures.size())
	quit(1)


func _smoke_scene(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("%s: scene could not be loaded" % scene_path)
		return

	var instance := packed.instantiate()
	if instance == null:
		_failures.append("%s: scene could not be instantiated" % scene_path)
		return

	root.add_child(instance)
	for _frame in 3:
		await physics_frame
	instance.queue_free()
	await process_frame
	# Give queued physics bodies one full tick to leave the broadphase before
	# the harness exits; this keeps shutdown diagnostics meaningful in CI.
	await physics_frame
