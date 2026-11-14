extends RefCounted
## Player stats, XP and levelling. Pure logic, unit tested.

var max_hp := 100.0
var hp := 100.0
var speed := 190.0
var damage := 10.0
var fire_cooldown := 0.75
var projectiles := 1
var pierce := 0
var pickup_range := 70.0

var level := 1
var xp := 0
var levels := {}  # upgrade id -> times taken


func xp_to_next() -> int:
	return 5 + (level - 1) * 4


## Adds XP and returns how many levels were gained.
func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
	return gained


func apply(id: String) -> void:
	levels[id] = levels.get(id, 0) + 1
	match id:
		"damage":
			damage *= 1.25
		"firerate":
			fire_cooldown *= 0.85
		"speed":
			speed *= 1.1
		"maxhp":
			max_hp += 20.0
			hp = minf(max_hp, hp + 20.0)
		"magnet":
			pickup_range *= 1.4
		"multishot":
			projectiles += 1
		"pierce":
			pierce += 1
		"heal":
			hp = minf(max_hp, hp + max_hp * 0.5)
		_:
			push_error("Unknown upgrade id: %s" % id)
