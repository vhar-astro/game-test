extends SceneTree
## Run the same staged review available in the Linux binary with -- --flight-review.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as InfinityGame
	root.add_child(game)
	game._run_flight_review()
