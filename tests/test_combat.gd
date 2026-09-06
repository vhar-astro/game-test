extends RefCounted

const ExplorerPlayer = preload("res://scripts/actors/player.gd")
const SentinelRobot = preload("res://scripts/actors/sentinel.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var player := ExplorerPlayer.new()
	player.take_damage(20.0)
	if not is_equal_approx(player.health, 80.0):
		failures.append("A sentinel hit must reduce player health by 20.")
	player.take_damage(80.0)
	if not is_equal_approx(player.health, 0.0):
		failures.append("Five sentinel hits must defeat a 100-health player.")

	var sentinel := SentinelRobot.new()
	sentinel.take_damage(10.0)
	sentinel.take_damage(10.0)
	if not is_equal_approx(sentinel.health, 10.0):
		failures.append("Two player strikes must leave the sentinel with 10 health.")
	sentinel.take_damage(10.0)
	if sentinel.enabled:
		failures.append("Three player strikes must disable the sentinel.")
	if sentinel.state != SentinelRobot.State.DEFEATED:
		failures.append("A defeated sentinel must enter its terminal state.")

	# These fixtures are instantiated directly rather than added to a scene tree;
	# free them explicitly so headless shutdown leak diagnostics stay actionable.
	player.free()
	sentinel.free()

	return failures
