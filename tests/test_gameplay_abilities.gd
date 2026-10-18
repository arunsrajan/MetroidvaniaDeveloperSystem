extends "res://tests/test_case.gd"
## Gameplay Kit, phase 3: every movement ability is a state the player can't enter before
## MDSWorldGame.grant_ability() and can after (double jump, wall jump, dash, air dash, slide, ledge
## grab, climb, swim, glide, grapple, ground pound), and works: the dash goes at dash_speed, the
## wall jump pushes away from the wall, the glide falls slowly, the grapple pulls toward its point;
## super_attack makes attacks break reinforced walls; the ability popup shows the ability gained.

const Fixture := preload("res://tests/game_fixture.gd")

var game: MDSWorldGame
var player: MDSPlayer
var room: Node2D

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	Fixture.build()
	game = Fixture.make_game()
	game.remove_child(game.player)
	game.player.free()
	var kit := MDSGameplay.new()
	kit.name = "Gameplay"
	game.add_child(kit)
	player = load(MDSPlayer.SCENE).instantiate()
	game.add_child(player)
	game.player = player
	var popup := MDSAbilityPopup.new()
	popup.pause_game = false
	game.get_node("UI").add_child(popup)
	add_child(game)
	await game.room_loaded
	room = game.room_node
	_geometry()
	await physics_frames(10)
	await _double_jump()
	await _wall_jump()
	await _dash()
	await _air_dash()
	await _slide()
	await _ledge_grab()
	await _climb()
	await _swim()
	await _glide()
	await _grapple()
	await _ground_pound()
	await _super_attack()
	check(popup.is_showing() and popup._name.text != "", "the ability popup shows the last ability gained (%s)" % popup._name.text)
	_release_all()
	game.queue_free()
	await get_tree().process_frame

## A wall, a ledge block, vines, a pool hanging in the air and a grapple ring in Garden_01.
func _geometry() -> void:
	_block(Rect2(300, 0, 40, 576))
	_block(Rect2(700, 400, 100, 176))
	var vines := MDSClimbable.new()
	vines.size = Vector2(40, 400)
	vines.position = Vector2(1000, 300)
	room.add_child(vines)
	var pool := MDSSwimZone.new()
	pool.size = Vector2(300, 200)
	pool.position = Vector2(500, 150)
	room.add_child(pool)
	var ring := MDSGrapplePoint.new()
	ring.position = Vector2(600, 260)
	room.add_child(ring)

func _block(r: Rect2) -> void:
	var b := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	b.add_child(cs)
	room.add_child(b)

func _release_all() -> void:
	for a in MDSGameplaySetup.ACTIONS:
		Input.action_release(a)

## Puts the player at [param at] (room-local) in the air, falling at [param fall_speed], or standing.
func _put(at: Vector2, standing := false, fall_speed := 120.0) -> void:
	_release_all()
	player.buffer.clear()
	player.global_position = room.global_position + at
	player.velocity = Vector2(0, fall_speed)
	player.machine.force(&"Fall")
	if standing:
		await physics_frames(30)
	else:
		await physics_frames(1)
		player.velocity = Vector2(0, fall_speed)
	player.on_landed()
	player.coyote_left = 0.0

## Blocked before the ability is granted, entered after: [param setup] puts the player in the
## situation, [param state] is tried.
func _gate(ability: String, state: StringName, setup: Callable) -> bool:
	await setup.call()
	var before := player.machine.transition_to(state)
	check(not before, "%s: no %s before the ability is granted" % [ability, state])
	game.grant_ability(ability)
	await setup.call()
	var after := player.machine.transition_to(state)
	check(after, "%s: %s once it is granted (in %s)" % [ability, state, player.machine.get_state()])
	return after

func _forget(ability: String) -> void:
	game.abilities.erase(ability)
	_release_all()

func _double_jump() -> void:
	var setup := func() -> void:
		await _put(Vector2(150, 300))
		player.buffer.press("jump")
	if await _gate("double_jump", &"Jump", setup):
		await physics_frames(1)
		check(player.velocity.y < 0.0 and player.air_jumps_left == player.config.max_air_jumps - 1, "an air jump rises, using up an air jump")
	_forget("double_jump")

func _wall_jump() -> void:
	var setup := func() -> void:
		await _put(Vector2(340 + player.body_size.x * 0.5 + 2, 300))
		Input.action_press(&"move_left")
	if await _gate("wall_jump", &"WallSlide", setup):
		await physics_frames(10)
		check(player.machine.is_in(&"WallSlide") and player.velocity.y <= player.config.wall_slide_speed + 0.5, "sliding down the wall slowly (%.0f)" % player.velocity.y)
		player.buffer.press("jump")
		await physics_frames(2)
		check(player.velocity.x > 0.0 and player.velocity.y < 0.0, "a wall jump kicks up and away from the wall (%s)" % player.velocity)
	_forget("wall_jump")

func _dash() -> void:
	var setup := func() -> void:
		await _put(Vector2(500, 540), true)
		player.dash_cooldown_left = 0.0
		player.facing = 1
		player.buffer.press("dash")
	if await _gate("dash", &"Dash", setup):
		await physics_frames(2)
		check_near(player.velocity.x, player.config.dash_speed, 1.0, "the dash goes at dash_speed")
	await physics_frames(20)
	_forget("dash")

func _air_dash() -> void:
	var setup := func() -> void:
		await _put(Vector2(500, 250))
		player.dash_cooldown_left = 0.0
		player.buffer.press("dash")
	if await _gate("air_dash", &"AirDash", setup):
		await physics_frames(2)
		check(absf(player.velocity.x) > player.config.max_run_speed and player.velocity.y == 0.0 and player.air_dashes_left == player.config.air_dashes - 1, "straight across the air, one air dash used")
	await physics_frames(20)
	_forget("air_dash")

func _slide() -> void:
	var setup := func() -> void:
		await _put(Vector2(500, 540), true)
		Input.action_press(&"move_down")
		player.buffer.press("dash")
	if await _gate("slide", &"Slide", setup):
		await physics_frames(2)
		check(is_equal_approx(player.get_body_height(), 0.5) and absf(player.velocity.x) > player.config.max_run_speed, "the slide is half as tall and fast")
	_release_all()
	await physics_frames(40)
	check(is_equal_approx(player.get_body_height(), 1.0), "standing again after it")
	_forget("slide")

func _ledge_grab() -> void:
	var setup := func() -> void:
		await _put(Vector2(700 - player.body_size.x * 0.5 - 2, 420))
		Input.action_press(&"move_right")
	if await _gate("ledge_grab", &"LedgeGrab", setup):
		await physics_frames(5)
		check(player.machine.is_in(&"LedgeGrab") and player.velocity == Vector2.ZERO, "hanging on the ledge")
		Input.action_press(&"move_up")
		await physics_frames(30)
		check(player.global_position.y < room.global_position.y + 400.0 and player.global_position.x > room.global_position.x + 700.0, "and up onto it (%s)" % (player.global_position - room.global_position))
	_forget("ledge_grab")
	await physics_frames(20)

func _climb() -> void:
	var setup := func() -> void:
		await _put(Vector2(1000, 300))
		await physics_frames(2)
		Input.action_press(&"move_up")
	if await _gate("climb", &"Climb", setup):
		var y := player.global_position.y
		await physics_frames(10)
		check(player.global_position.y < y - 5.0 and player.machine.is_in(&"Climb"), "climbing up the vines")
	_forget("climb")
	await physics_frames(40)

func _swim() -> void:
	var setup := func() -> void:
		await _put(Vector2(500, 150), false, 0.0)
		await physics_frames(2)
	if await _gate("swim", &"Swim", setup):
		Input.action_press(&"move_up")
		var y := player.global_position.y
		await physics_frames(10)
		check(player.global_position.y < y and player.machine.is_in(&"Swim"), "swimming up in the water")
	_forget("swim")
	await physics_frames(40)

func _glide() -> void:
	var setup := func() -> void:
		await _put(Vector2(150, 100), false, 300.0)
		Input.action_press(&"jump")
		player.buffer.clear()
	if await _gate("glide", &"Glide", setup):
		await physics_frames(30)
		check(player.velocity.y <= player.config.glide_fall_speed + 0.5 and player.machine.is_in(&"Glide"), "gliding down slowly (%.0f)" % player.velocity.y)
	_forget("glide")
	await physics_frames(40)

func _grapple() -> void:
	var setup := func() -> void:
		await _put(Vector2(480, 440))
		player.buffer.press("grapple")
	if await _gate("grapple", &"Grapple", setup):
		var d := player.global_position.distance_to(room.global_position + Vector2(600, 260))
		await physics_frames(4)
		check(player.global_position.distance_to(room.global_position + Vector2(600, 260)) < d - 40.0, "pulled toward the grapple ring")
	_forget("grapple")
	await physics_frames(40)

func _ground_pound() -> void:
	var setup := func() -> void:
		await _put(Vector2(500, 200))
		Input.action_press(&"move_down")
		player.buffer.press("dash")
	if await _gate("ground_pound", &"GroundPound", setup):
		await physics_frames(1)
		check_near(player.velocity.y, player.config.ground_pound_speed, 1.0, "slamming down at ground_pound_speed")
	_forget("ground_pound")
	await physics_frames(40)

func _super_attack() -> void:
	player.global_position = room.global_position + Vector2(500, 540)
	player.facing = 1
	await physics_frames(20)
	var wall := MDSBreakable.new()
	wall.kind = "reinforced"
	wall.size = Vector2(40, 100)
	room.add_child(wall)
	wall.global_position = player.global_position + Vector2(50, -20)
	await physics_frames(2)
	var info := MDSDamageInfo.make(1)
	info.breaks = PackedStringArray(["wall"])
	check(not wall.can_break_with(info), "a plain attack doesn't break a reinforced wall")
	var attacks := player.attacks as MDSAttackController
	attacks.start(attacks.ground_combo[0])
	await physics_frames(attacks.ground_combo[0].startup_frames + 2)
	check(not attacks.hitbox.extra_breaks.has("reinforced"), "without super_attack the attack doesn't list reinforced")
	await physics_frames(30)
	check(is_instance_valid(wall) and not wall.is_queued_for_deletion(), "and the wall stands after the swing")
	game.grant_ability("super_attack")
	attacks.start(attacks.ground_combo[0])
	await physics_frames(attacks.ground_combo[0].startup_frames + 2)
	check(attacks.hitbox.extra_breaks.has("reinforced"), "with super_attack it does")
	await physics_frames(6)
	check(not is_instance_valid(wall) or wall.is_queued_for_deletion(), "and the swing breaks the reinforced wall")
