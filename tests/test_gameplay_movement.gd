extends "res://tests/test_case.gd"
## Gameplay Kit, phase 2: MDSPlayer's movement with simulated input over physics frames. A full
## jump peaks within 2 px of the arc MDSMovementConfig computes, releasing early cuts it short,
## coyote time and the jump buffer have their windows, running reaches the configured speed, a
## ceiling corner is slid past, down + jump drops through a one-way platform, slopes are walked
## up, and while the game changes rooms the player is Locked (no gravity, velocity untouched).

var player: MDSPlayer
var level: Node2D

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	level = _level()
	add_child(level)
	player = load(MDSPlayer.SCENE).instantiate()
	level.add_child(player)
	player.global_position = Vector2(200, 400)
	await _settle()
	check(player.is_on_floor() and player.machine.is_in(&"Idle"), "the player lands and stands (%s)" % player.machine.get_state())
	check(player.machine.states.size() == MDSPlayer.STATE_NAMES.size(), "it has every state (%d)" % player.machine.states.size())
	await _run_speed()
	await _jump_apex()
	await _jump_cut()
	await _coyote()
	await _buffer()
	await _corner()
	await _drop_through()
	await _slope()
	await _locked()
	_release_all()
	level.queue_free()
	await get_tree().process_frame

func _level() -> Node2D:
	var l := Node2D.new()
	l.name = "Level"
	# A: a floor ending in a ledge at x 1500, a catch floor far below.
	_block(l, Rect2(-500, 500, 2000, 100))
	_block(l, Rect2(-500, 1600, 12000, 100))
	# B: a floor with a low ceiling block (its left edge at x 3500, 40 px over the player's head).
	_block(l, Rect2(2800, 500, 1400, 100))
	_block(l, Rect2(3500, 300, 400, 100))
	# C: a floor and a one-way platform over it.
	_block(l, Rect2(5500, 500, 1500, 100))
	var plat := _block(l, Rect2(6000, 400, 400, 16))
	(plat.get_child(0) as CollisionShape2D).one_way_collision = true
	# D: a slope rising 200 px over 400 px (about 27 degrees), then a high floor.
	_block(l, Rect2(8500, 500, 600, 100))
	var slope := StaticBody2D.new()
	var poly := CollisionPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(9100, 500), Vector2(9500, 300), Vector2(9500, 600), Vector2(9100, 600)])
	slope.add_child(poly)
	l.add_child(slope)
	_block(l, Rect2(9500, 300, 800, 300))
	return l

func _block(parent: Node, r: Rect2) -> StaticBody2D:
	var b := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	b.add_child(cs)
	parent.add_child(b)
	return b

func _settle(frames := 40) -> void:
	await physics_frames(frames)

func _press(action: StringName) -> void:
	Input.action_press(action)

func _release(action: StringName) -> void:
	Input.action_release(action)

func _release_all() -> void:
	for a in MDSGameplaySetup.ACTIONS:
		Input.action_release(a)

func _place(at: Vector2) -> void:
	_release_all()
	player.global_position = at
	player.velocity = Vector2.ZERO
	player.machine.force(&"Fall")
	await _settle()

func _run_speed() -> void:
	await _place(Vector2(0, 450))
	_press(&"move_right")
	await physics_frames(20)
	check_near(player.velocity.x, player.config.max_run_speed, 1.0, "running reaches max_run_speed")
	check(player.machine.is_in(&"Run") and player.facing == 1, "in Run, facing right")
	_release(&"move_right")
	await physics_frames(12)
	check(absf(player.velocity.x) < 1.0 and player.machine.is_in(&"Idle"), "and stops when let go")

func _apex_of(hold_frames: int) -> float:
	await _place(Vector2(200, 450))
	var start := player.global_position.y
	var top := start
	_press(&"jump")
	for i in 70:
		await get_tree().physics_frame
		if i == hold_frames:
			_release(&"jump")
		top = minf(top, player.global_position.y)
	_release(&"jump")
	await _settle(20)
	return start - top

func _jump_apex() -> void:
	var arc := player.config.jump_arc(1.0 / Engine.physics_ticks_per_second)
	var want := 0.0
	for p in arc:
		want = maxf(want, -p.y)
	var got := await _apex_of(999)
	check_near(got, want, 2.0, "a full jump peaks at the height MDSMovementConfig's arc gives")
	check_near(got, player.config.jump_height(), 6.0, "close to the analytic jump_height()")
	check(player.is_on_floor(), "and lands again")

func _jump_cut() -> void:
	var full := player.config.jump_height()
	var short := await _apex_of(3)
	check(short < full * 0.6, "releasing jump early cuts the jump short (%.1f of %.1f px)" % [short, full])

## Walks off the ledge at x 1500, presses jump [param frames_after] physics frames after leaving
## the floor. Returns whether it jumped.
func _off_ledge_then_jump(frames_after: int) -> bool:
	await _place(Vector2(1300, 450))
	_press(&"move_right")
	var guard := 0
	while player.is_on_floor() and guard < 200:
		await get_tree().physics_frame
		guard += 1
	_release(&"move_right")
	for i in frames_after:
		await get_tree().physics_frame
	_press(&"jump")
	await physics_frames(3)
	var jumped := player.velocity.y < -100.0
	_release(&"jump")
	return jumped

func _coyote() -> void:
	var window := int(player.config.coyote_time * Engine.physics_ticks_per_second)
	check(await _off_ledge_then_jump(maxi(1, window - 3)), "a jump just after walking off a ledge works (coyote time)")
	check(not await _off_ledge_then_jump(window + 4), "a jump after the coyote time doesn't")

## Drops the player onto the floor and presses jump about [param frames_before] frames before it
## lands. Returns whether it jumped on landing.
func _press_before_landing(frames_before: int) -> bool:
	await _place(Vector2(200, 450))
	player.global_position = Vector2(200, 200)
	player.velocity = Vector2.ZERO
	player.machine.force(&"Fall")
	var dt := 1.0 / Engine.physics_ticks_per_second
	var guard := 0
	while guard < 300:
		await get_tree().physics_frame
		guard += 1
		var feet := player.global_position.y + player.body_size.y * 0.5
		var frames_left := (500.0 - feet) / maxf(player.velocity.y * dt, 0.001)
		if frames_left <= frames_before and player.velocity.y > 0.0:
			break
	_press(&"jump")
	await get_tree().physics_frame
	_release(&"jump")
	var jumped := false
	for i in frames_before + 8:
		await get_tree().physics_frame
		jumped = jumped or (player.machine.is_in(&"Jump") and player.velocity.y < 0.0)
	return jumped

func _buffer() -> void:
	var window := int(player.config.jump_buffer_time * Engine.physics_ticks_per_second)
	check(await _press_before_landing(maxi(1, window - 3)), "a jump pressed just before landing happens on landing (buffer)")
	check(not await _press_before_landing(window + 8), "one pressed long before landing doesn't")

func _corner() -> void:
	# The player's right edge 4 px under the ceiling block's left edge.
	await _place(Vector2(3500 - player.body_size.x * 0.5 + 4.0, 450))
	var x0 := player.global_position.x
	var start := player.global_position.y
	var top := start
	_press(&"jump")
	for i in 40:
		await get_tree().physics_frame
		top = minf(top, player.global_position.y)
	_release(&"jump")
	check(start - top > 60.0, "a jump into a ceiling corner slides past it (rose %.1f px)" % (start - top))
	check(player.global_position.x < x0 - 1.0 and player.global_position.x >= x0 - player.config.corner_correction_px - 0.5, "nudged aside by at most corner_correction_px")
	await _settle(30)

func _drop_through() -> void:
	await _place(Vector2(6200, 340))
	check(player.is_on_floor() and player.global_position.y < 400.0, "standing on the one-way platform")
	_press(&"move_down")
	await physics_frames(2)
	_press(&"jump")
	await physics_frames(2)
	_release(&"jump")
	_release(&"move_down")
	await _settle(40)
	check(player.is_on_floor() and player.global_position.y > 440.0, "down + jump drops through to the floor below (y %.0f)" % player.global_position.y)

func _slope() -> void:
	await _place(Vector2(8800, 450))
	_press(&"move_right")
	await physics_frames(260)
	_release(&"move_right")
	check(player.global_position.y < 290.0 and player.global_position.x > 9500.0, "walked up the slope onto the high floor (%s)" % player.global_position)

func _locked() -> void:
	await _place(Vector2(200, 450))
	var fake := MDSWorldGame.new()
	player.game = fake
	player.global_position = Vector2(200, 300)
	player.velocity = Vector2(140, -300)
	fake.changing_room = true
	await physics_frames(6)
	check(player.machine.is_in(&"Locked"), "while the game changes rooms the player is Locked")
	check(player.velocity == Vector2(140, -300) and player.global_position == Vector2(200, 300), "no gravity, no movement, the velocity untouched")
	_press(&"move_left")
	await physics_frames(3)
	check(player.velocity == Vector2(140, -300), "input does nothing")
	_release(&"move_left")
	fake.changing_room = false
	await physics_frames(2)
	check(not player.machine.is_in(&"Locked") and player.global_position.y < 300.0, "the room change done, it moves on with its velocity (%s)" % player.machine.get_state())
	player.game = null
	fake.free()
	await _settle(40)
