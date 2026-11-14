extends Node2D
## Block Dodge: dodge falling blocks for as long as you can.
## Controls: arrow keys / A-D, or drag with mouse / finger. Enter or click to restart.

const W := 480.0
const H := 720.0
const PLAYER_SIZE := Vector2(48, 16)
const PLAYER_SPEED := 420.0
const PLAYER_Y := H - 60.0

var player_x := W / 2
var blocks: Array[Rect2] = []
var speeds: Array[float] = []
var spawn_timer := 0.0
var score := 0.0
var best := 0.0
var game_over := false


func _ready() -> void:
	randomize()


func reset() -> void:
	blocks.clear()
	speeds.clear()
	player_x = W / 2
	spawn_timer = 0.0
	score = 0.0
	game_over = false


func player_rect() -> Rect2:
	return Rect2(Vector2(player_x - PLAYER_SIZE.x / 2, PLAYER_Y), PLAYER_SIZE)


func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if event.is_action_pressed("ui_accept") \
				or (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			reset()
		return
	if event is InputEventScreenDrag \
			or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		player_x = event.position.x


func _process(delta: float) -> void:
	if game_over:
		queue_redraw()
		return

	var dir := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir += 1.0
	player_x = clampf(player_x + dir * PLAYER_SPEED * delta, PLAYER_SIZE.x / 2, W - PLAYER_SIZE.x / 2)

	score += delta
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = maxf(0.15, 0.8 - score * 0.02)
		var size := randf_range(20.0, 60.0)
		blocks.append(Rect2(randf_range(0.0, W - size), -size, size, size))
		speeds.append(randf_range(150.0, 250.0) + score * 8.0)

	var p := player_rect()
	for i in range(blocks.size() - 1, -1, -1):
		var b := blocks[i]
		b.position.y += speeds[i] * delta
		blocks[i] = b
		if b.intersects(p):
			game_over = true
			best = maxf(best, score)
		elif b.position.y > H:
			blocks.remove_at(i)
			speeds.remove_at(i)

	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, W, H), Color("1d1f2b"))
	for b in blocks:
		draw_rect(b, Color("ff5d73"))
	draw_rect(player_rect(), Color("5df2c4"))
	draw_string(font, Vector2(16, 36), "Score: %.1f" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(font, Vector2(16, 64), "Best: %.1f" % best, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.6))
	if game_over:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, H / 2 - 20), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, W, 48)
		draw_string(font, Vector2(0, H / 2 + 30), "Press Enter or click to retry", HORIZONTAL_ALIGNMENT_CENTER, W, 20)
