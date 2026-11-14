extends Node2D
## Night of a Hundred Demons: survive until dawn.
## Move with WASD / arrows, or hold mouse / touch to walk toward the pointer.
## Shuriken fire automatically at the nearest demon. Collect spirit orbs to level up and pick 1 of 3 upgrades.
## Run with `-- --bot` for an autoplaying bot (used by the CI smoke test).

const Upgrades := preload("res://scripts/upgrades.gd")
const PlayerStats := preload("res://scripts/player_stats.gd")

enum State { PLAYING, LEVEL_UP, GAME_OVER, VICTORY }

const VIEW := Vector2(960, 540)
const RUN_LENGTH := 600.0  # 10 minutes until dawn
const PLAYER_RADIUS := 14.0
const FIRE_RANGE := 420.0
const PROJECTILE_SPEED := 520.0
const GEM_RADIUS := 6.0
const CARD_SIZE := Vector2(240, 280)
const CARD_GAP := 30.0

const ENEMY_TYPES := {
	"bandit": {"radius": 11.0, "speed": 95.0, "hp": 12.0, "dps": 10.0, "xp": 1},
	"oni": {"radius": 22.0, "speed": 52.0, "hp": 55.0, "dps": 25.0, "xp": 4},
}


class Enemy:
	var kind: String
	var pos: Vector2
	var hp: float
	var radius: float
	var speed: float
	var dps: float
	var xp: int
	var flash := 0.0


class Projectile:
	var pos: Vector2
	var vel: Vector2
	var damage: float
	var pierce: int
	var life := 1.2
	var hits: Array = []


class Gem:
	var pos: Vector2
	var value: int


var rng := RandomNumberGenerator.new()
var stats: PlayerStats
var state := State.PLAYING
var player_pos := Vector2.ZERO
var enemies: Array[Enemy] = []
var projectiles: Array[Projectile] = []
var gems: Array[Gem] = []
var time := 0.0
var kills := 0
var fire_timer := 0.0
var spawn_timer := 0.0
var choices: Array = []
var pending_levels := 0
var input_delay := 0.0
var anim := 0.0
var bot := false
var runs := 0


func _ready() -> void:
	bot = "--bot" in OS.get_cmdline_user_args()
	rng.randomize()
	new_run()


func new_run() -> void:
	stats = PlayerStats.new()
	state = State.PLAYING
	player_pos = Vector2.ZERO
	enemies.clear()
	projectiles.clear()
	gems.clear()
	time = 0.0
	kills = 0
	fire_timer = 0.0
	spawn_timer = 0.0
	choices = []
	pending_levels = 0
	runs += 1


# ---------------------------------------------------------------- simulation

func _process(delta: float) -> void:
	input_delay -= delta
	if bot:
		_bot_think()
	step(delta)
	queue_redraw()


## Advances the game by `delta` seconds. Called every frame, and directly by tests.
func step(delta: float) -> void:
	anim += delta
	if state != State.PLAYING:
		return
	time += delta
	if time >= RUN_LENGTH:
		_end_run(State.VICTORY)
		return
	_move_player(delta)
	_spawn(delta)
	_fire(delta)
	_update_projectiles(delta)
	_update_enemies(delta)
	_update_gems(delta)
	if stats.hp <= 0.0:
		stats.hp = 0.0
		_end_run(State.GAME_OVER)
	elif pending_levels > 0:
		_open_level_up()


func _move_player(delta: float) -> void:
	var dir := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): dir.y += 1.0
	if bot:
		dir = Vector2(cos(time * 0.7), sin(time * 1.1))
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var to_pointer := get_local_mouse_position() - VIEW / 2
		if to_pointer.length() > 12.0:
			dir = to_pointer
	if dir.length() > 0.0:
		player_pos += dir.normalized() * stats.speed * delta


func _spawn(delta: float) -> void:
	spawn_timer -= delta
	while spawn_timer <= 0.0:
		spawn_timer += maxf(0.12, 1.1 - time * 0.004)
		var oni_chance := clampf(time / 300.0, 0.05, 0.4)
		var kind := "oni" if rng.randf() < oni_chance else "bandit"
		var angle := rng.randf() * TAU
		spawn_enemy(kind, player_pos + Vector2.from_angle(angle) * (VIEW.length() / 2 + 40.0))


func spawn_enemy(kind: String, pos: Vector2) -> Enemy:
	var t: Dictionary = ENEMY_TYPES[kind]
	var e := Enemy.new()
	e.kind = kind
	e.pos = pos
	e.hp = t["hp"] * (1.0 + time / 90.0)
	e.radius = t["radius"]
	e.speed = t["speed"]
	e.dps = t["dps"]
	e.xp = t["xp"]
	enemies.append(e)
	return e


func _nearest_enemy(max_range: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_range * max_range
	for e in enemies:
		var d := e.pos.distance_squared_to(player_pos)
		if e.hp > 0.0 and d < best_d:
			best_d = d
			best = e
	return best


func _fire(delta: float) -> void:
	fire_timer -= delta
	if fire_timer > 0.0:
		return
	var target := _nearest_enemy(FIRE_RANGE)
	if target == null:
		return
	fire_timer = stats.fire_cooldown
	var base := (target.pos - player_pos).angle()
	var n: int = stats.projectiles
	for i in n:
		var p := Projectile.new()
		p.pos = player_pos
		p.vel = Vector2.from_angle(base + (i - (n - 1) / 2.0) * 0.18) * PROJECTILE_SPEED
		p.damage = stats.damage
		p.pierce = stats.pierce
		projectiles.append(p)


func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p := projectiles[i]
		p.pos += p.vel * delta
		p.life -= delta
		var done := p.life <= 0.0
		if not done:
			for e in enemies:
				if e.hp <= 0.0 or p.hits.has(e):
					continue
				var r := e.radius + 5.0
				if p.pos.distance_squared_to(e.pos) < r * r:
					e.hp -= p.damage
					e.flash = 0.1
					p.hits.append(e)
					if p.hits.size() > p.pierce:
						done = true
						break
		if done:
			projectiles.remove_at(i)


func _update_enemies(delta: float) -> void:
	var contact_dps := 0.0
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if e.hp <= 0.0:
			var g := Gem.new()
			g.pos = e.pos
			g.value = e.xp
			gems.append(g)
			kills += 1
			enemies.remove_at(i)
			continue
		e.flash = maxf(0.0, e.flash - delta)
		var to_player := player_pos - e.pos
		var d := to_player.length()
		if d > e.radius + PLAYER_RADIUS - 4.0:
			e.pos += to_player / d * e.speed * delta
		if d < e.radius + PLAYER_RADIUS:
			contact_dps += e.dps
	stats.hp -= contact_dps * delta


func _update_gems(delta: float) -> void:
	for i in range(gems.size() - 1, -1, -1):
		var g := gems[i]
		var d := g.pos.distance_to(player_pos)
		if d < PLAYER_RADIUS + GEM_RADIUS:
			pending_levels += stats.add_xp(g.value)
			gems.remove_at(i)
		elif d < stats.pickup_range:
			g.pos = g.pos.move_toward(player_pos, 380.0 * delta)


func _open_level_up() -> void:
	choices = Upgrades.roll(stats.levels, rng)
	state = State.LEVEL_UP
	input_delay = 0.35


func pick(index: int) -> void:
	if state != State.LEVEL_UP or index < 0 or index >= choices.size():
		return
	var u: Dictionary = choices[index]
	stats.apply(u["id"])
	if bot:
		print("[bot] t=%.0fs level %d picked %s" % [time, stats.level, u["name"]])
	pending_levels -= 1
	if pending_levels > 0:
		_open_level_up()
	else:
		state = State.PLAYING


func _end_run(result: State) -> void:
	state = result
	input_delay = 0.8
	if bot:
		print("[bot] run %d ended: %s at %.0fs, level %d, %d kills" % [
			runs, "victory" if result == State.VICTORY else "death", time, stats.level, kills])


func _bot_think() -> void:
	if input_delay > 0.0:
		return
	if state == State.LEVEL_UP:
		pick(rng.randi_range(0, choices.size() - 1))
	elif state == State.GAME_OVER or state == State.VICTORY:
		new_run()


# ---------------------------------------------------------------- input

func _card_rect(i: int) -> Rect2:
	var total := CARD_SIZE.x * 3 + CARD_GAP * 2
	var x := (VIEW.x - total) / 2 + i * (CARD_SIZE.x + CARD_GAP)
	return Rect2(Vector2(x, 150), CARD_SIZE)


func _unhandled_input(event: InputEvent) -> void:
	if input_delay > 0.0:
		return
	if state == State.LEVEL_UP:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_1: pick(0)
				KEY_2: pick(1)
				KEY_3: pick(2)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in choices.size():
				if _card_rect(i).has_point(event.position):
					pick(i)
					break
	elif state == State.GAME_OVER or state == State.VICTORY:
		if event.is_action_pressed("ui_accept") \
				or (event is InputEventMouseButton and event.pressed):
			new_run()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var off := VIEW / 2 - player_pos
	_draw_ground(off)

	draw_set_transform(off)
	for g in gems:
		var pulse := 1.0 + sin(anim * 6.0 + g.pos.x) * 0.15
		draw_circle(g.pos, GEM_RADIUS * 1.6 * pulse, Color(0.35, 0.7, 1.0, 0.25))
		draw_circle(g.pos, GEM_RADIUS * pulse, Color("4fb3ff"))
		draw_circle(g.pos, GEM_RADIUS * 0.4, Color.WHITE)
	for e in enemies:
		_draw_enemy(e)
	for p in projectiles:
		_draw_shuriken(p.pos, anim * 18.0)
	_draw_samurai(player_pos)
	draw_set_transform(Vector2.ZERO)

	_draw_hud()
	match state:
		State.LEVEL_UP:
			_draw_level_up()
		State.GAME_OVER:
			_draw_end_screen("Your journey ends", Color("8e1b1b"))
		State.VICTORY:
			_draw_end_screen("You survived until dawn", Color("c9a227"))


func _draw_ground(off: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("e9dfc7"))
	var cell := 96.0
	var line := Color(0.35, 0.25, 0.15, 0.12)
	var sx := fposmod(off.x, cell)
	var sy := fposmod(off.y, cell)
	for i in range(-1, int(VIEW.x / cell) + 2):
		draw_line(Vector2(sx + i * cell, 0), Vector2(sx + i * cell, VIEW.y), line, 2.0)
	for i in range(-1, int(VIEW.y / cell) + 2):
		draw_line(Vector2(0, sy + i * cell), Vector2(VIEW.x, sy + i * cell), line, 2.0)


func _draw_samurai(p: Vector2) -> void:
	draw_circle(p + Vector2(0, 4), PLAYER_RADIUS, Color(0, 0, 0, 0.15))  # shadow
	draw_circle(p, PLAYER_RADIUS, Color("23395b"))  # robe
	draw_circle(p, 9.0, Color("c0392b"))  # armor
	draw_circle(p + Vector2(0, -3), 5.0, Color("1b1b1b"))  # helmet
	draw_line(p + Vector2(-7, -14), p + Vector2(0, -7), Color("d4af37"), 2.5)  # kabuto crest
	draw_line(p + Vector2(7, -14), p + Vector2(0, -7), Color("d4af37"), 2.5)
	draw_line(p + Vector2(9, 5), p + Vector2(26, -10), Color("dfe6e9"), 3.0)  # katana
	draw_line(p + Vector2(7, 7), p + Vector2(11, 3), Color("2d3436"), 4.0)  # hilt


func _draw_enemy(e: Enemy) -> void:
	var r := e.radius
	var p := e.pos
	var white := e.flash > 0.0
	draw_circle(p + Vector2(0, 3), r, Color(0, 0, 0, 0.15))
	if e.kind == "oni":
		draw_circle(p, r, Color.WHITE if white else Color("b83227"))
		var horn := Color("f3e9d2")
		draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.7, -r * 0.5), p + Vector2(-r * 0.3, -r * 0.8), p + Vector2(-r * 0.6, -r * 1.5)]), horn)
		draw_colored_polygon(PackedVector2Array([p + Vector2(r * 0.7, -r * 0.5), p + Vector2(r * 0.3, -r * 0.8), p + Vector2(r * 0.6, -r * 1.5)]), horn)
		draw_circle(p + Vector2(-r * 0.35, -r * 0.1), 3.0, Color("ffd32a"))
		draw_circle(p + Vector2(r * 0.35, -r * 0.1), 3.0, Color("ffd32a"))
	else:
		draw_circle(p, r, Color.WHITE if white else Color("4a4a4a"))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-r - 5, -r * 0.2), p + Vector2(r + 5, -r * 0.2), p + Vector2(0, -r - 8)]), Color("c8a96a"))  # straw hat


func _draw_shuriken(p: Vector2, rot: float) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		var radius := 7.0 if k % 2 == 0 else 2.5
		pts.append(p + Vector2.from_angle(rot + k * TAU / 8.0) * radius)
	draw_colored_polygon(pts, Color("2d3436"))


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	# XP bar along the top
	draw_rect(Rect2(0, 0, VIEW.x, 8), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(0, 0, VIEW.x * float(stats.xp) / stats.xp_to_next(), 8), Color("4fb3ff"))
	# HP bar
	draw_rect(Rect2(16, 20, 200, 16), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(16, 20, 200 * stats.hp / stats.max_hp, 16), Color("c0392b"))
	draw_string(font, Vector2(22, 33), "%d / %d" % [ceili(stats.hp), int(stats.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(16, 58), "Level %d    Kills %d" % [stats.level, kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("2d3436"))
	# Time until dawn
	var left := maxf(0.0, RUN_LENGTH - time)
	draw_string(font, Vector2(0, 40), "%d:%02d until dawn" % [int(left) / 60, int(left) % 60], HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 22, Color("2d3436"))


func _draw_level_up() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(0, 110), "Level %d - choose your path" % stats.level, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 32)
	for i in choices.size():
		var u: Dictionary = choices[i]
		var rect := _card_rect(i)
		var hover := rect.has_point(get_local_mouse_position())
		draw_rect(rect, Color("fff6e0") if hover else Color("f5ecd7"))
		draw_rect(rect, Color("8e1b1b"), false, 4.0 if hover else 3.0)
		var cur: int = stats.levels.get(u["id"], 0)
		draw_string(font, rect.position + Vector2(0, 50), u["name"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color("1b1b1b"))
		draw_multiline_string(font, rect.position + Vector2(20, 110), u["desc"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 40, 17, -1, Color("2d3436"))
		var lvl_text := "New" if cur == 0 else "Lv %d -> %d" % [cur, cur + 1]
		if u["id"] == "heal":
			lvl_text = "Consumable"
		draw_string(font, rect.position + Vector2(0, 210), lvl_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color("8e1b1b"))
		draw_string(font, rect.position + Vector2(0, 255), "[%d]" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Color(0.2, 0.2, 0.2, 0.6))


func _draw_end_screen(title: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(0, VIEW.y / 2 - 40), title, HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 44, color.lightened(0.3))
	draw_string(font, Vector2(0, VIEW.y / 2 + 10), "Survived %d:%02d    Level %d    %d demons slain" % [int(time) / 60, int(time) % 60, stats.level, kills], HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 20)
	draw_string(font, Vector2(0, VIEW.y / 2 + 60), "Press Enter or click to rise again", HORIZONTAL_ALIGNMENT_CENTER, VIEW.x, 18, Color(1, 1, 1, 0.7))
