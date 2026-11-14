extends RefCounted
## Upgrade definitions and the pick-3 roll. Pure data + logic, no nodes, so it is easy to unit test.
## To add an upgrade: add an entry here and handle its id in player_stats.gd apply().

const LIST := [
	{"id": "damage", "name": "Sharpened Steel", "desc": "+25% shuriken damage", "max": 5},
	{"id": "firerate", "name": "Swift Hands", "desc": "Throw shuriken 15% faster", "max": 5},
	{"id": "speed", "name": "Straw Sandals", "desc": "+10% movement speed", "max": 5},
	{"id": "maxhp", "name": "Iron Will", "desc": "+20 max HP and heal 20", "max": 5},
	{"id": "magnet", "name": "Spirit Lure", "desc": "+40% spirit orb pickup range", "max": 4},
	{"id": "multishot", "name": "Twin Shuriken", "desc": "+1 shuriken per throw", "max": 4},
	{"id": "pierce", "name": "Folded Steel", "desc": "Shuriken pierce +1 more demon", "max": 3},
	{"id": "heal", "name": "Green Tea", "desc": "Restore 50% of your HP", "max": 999},
]


static func get_by_id(id: String) -> Dictionary:
	for u in LIST:
		if u["id"] == id:
			return u
	return {}


## Returns up to `count` distinct upgrades that are not yet at max level.
static func roll(levels: Dictionary, rng: RandomNumberGenerator, count := 3) -> Array:
	var pool := []
	for u in LIST:
		if levels.get(u["id"], 0) < u["max"]:
			pool.append(u)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, count)
