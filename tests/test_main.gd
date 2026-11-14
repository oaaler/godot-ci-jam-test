extends SceneTree
## Minimal headless test runner. Run with:
##   godot --headless -s res://tests/test_main.gd
## Exits with code 1 if any check fails, so CI goes red.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)

	# Player stays inside the screen.
	main.player_x = -500.0
	main._process(0.016)
	check(main.player_x >= main.PLAYER_SIZE.x / 2, "player is clamped to the left edge")

	# Blocks spawn over time.
	main.reset()
	main._process(0.016)
	check(main.blocks.size() > 0, "a block spawns on the first frame")

	# Score increases while alive.
	check(main.score > 0.0, "score increases while playing")

	# Hitting a block ends the game.
	main.reset()
	main.blocks.append(main.player_rect())
	main.speeds.append(0.0)
	main._process(0.016)
	check(main.game_over, "colliding with a block ends the game")

	# Reset restores a fresh game.
	main.reset()
	check(not main.game_over and main.score == 0.0 and main.blocks.is_empty(), "reset starts a fresh game")

	print("\n%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
