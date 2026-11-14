extends SceneTree
## Headless test runner:  godot --headless -s res://tests/test_game.gd
## Exits with code 1 if any check fails, so CI goes red.

const Upgrades := preload("res://scripts/upgrades.gd")
const PlayerStats := preload("res://scripts/player_stats.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	test_upgrades()
	test_stats()
	test_game()
	print("\n%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func test_upgrades() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for n in 50:
		var picks := Upgrades.roll({}, rng)
		var ids := {}
		for u in picks:
			ids[u["id"]] = true
		if picks.size() != 3 or ids.size() != 3:
			check(false, "roll returns 3 distinct upgrades")
			return
	check(true, "roll returns 3 distinct upgrades (50 rolls)")

	var maxed := {}
	for u in Upgrades.LIST:
		if u["id"] != "heal" and u["id"] != "damage":
			maxed[u["id"]] = u["max"]
	var limited := Upgrades.roll(maxed, rng)
	var limited_ids := limited.map(func(u): return u["id"])
	check(limited.size() == 2 and "heal" in limited_ids and "damage" in limited_ids,
		"roll never offers maxed upgrades")

	var stats := PlayerStats.new()
	for u in Upgrades.LIST:
		stats.apply(u["id"])
	check(stats.levels.size() == Upgrades.LIST.size(), "every upgrade id is handled by PlayerStats.apply")


func test_stats() -> void:
	var s := PlayerStats.new()
	check(s.add_xp(4) == 0 and s.level == 1, "4 xp does not level up")
	check(s.add_xp(1) == 1 and s.level == 2 and s.xp == 0, "5 xp reaches level 2")
	check(s.add_xp(100) > 1, "a big xp gain can level up multiple times")

	s = PlayerStats.new()
	s.apply("multishot")
	check(s.projectiles == 2, "Twin Shuriken adds a projectile")
	s.hp = 10.0
	s.apply("heal")
	check(is_equal_approx(s.hp, 60.0), "Green Tea heals 50% of max HP")


func test_game() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.rng.seed = 1
	game.new_run()
	game.spawn_timer = 9999.0  # disable random spawns

	var bandit = game.spawn_enemy("bandit", Vector2(150, 0))
	for i in 180:  # 3 seconds
		game.step(1.0 / 60.0)
		if game.kills > 0:
			break
	check(game.kills == 1, "autofire kills a nearby bandit")
	check(game.gems.size() == 1, "a dead demon drops a spirit orb")

	game.gems.clear()
	var g = game.Gem.new()
	g.pos = game.player_pos
	g.value = 5
	game.gems.append(g)
	game.step(1.0 / 60.0)
	check(game.state == game.State.LEVEL_UP, "collecting enough XP opens the level-up screen")
	check(game.choices.size() == 3, "level-up offers 3 choices")

	game.pick(0)
	check(game.state == game.State.PLAYING, "picking a card resumes the game")
	check(game.stats.levels.size() == 1, "the picked upgrade is applied")

	game.spawn_enemy("oni", game.player_pos)
	game.stats.hp = 1.0
	game.step(0.1)
	check(game.state == game.State.GAME_OVER, "contact damage can kill the player")

	game.new_run()
	check(game.state == game.State.PLAYING and game.enemies.is_empty() and game.stats.level == 1,
		"new_run resets everything")
	game.free()
