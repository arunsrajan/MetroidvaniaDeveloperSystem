extends "res://tests/test_case.gd"
## Gameplay Kit: the move system. Each action does what it says in a small walled room, the pattern
## moves run them in order, conditions and cooldowns gate them, a moves resource is safe to share
## between enemies, hits stagger a boss, a partner keeps the fight going, a boss can be inherited in
## code, and every attack of every recipe runs without leaving the room.

const ROOM := Rect2(0, 0, 1600, 720)
const FLOOR_Y := 720.0
## What each fight has to bring out in its last phase.
const EXPECT := {
	"swooper": [],
	"twin_swooper": [&"summon"],
	"showman": [&"zone", &"shot", &"hidden"],
	"duelist": [&"zone"],
	"possessed_duelist": [&"zone", &"shot", &"hidden"],
	"hanging_matriarch": [&"zone", &"summon"],
}

var stage: Node2D
var player: CharacterBody2D
var player_hurt: MDSHurtbox
var player_hits := 0

## A boss built in code, the way a game would inherit it.
class Hopper extends MDSMoveBoss:
	func _make_phases() -> Array[MDSBossPhase]:
		var hop := MDSMoveLeap.of(MDSMove.Anchor.PLAYER, 160.0, MDSMoveLeap.EndAt.LANDING, 0.0)
		return [MDSMovePhase.of(1.0, MDSMoveSequence.of([hop, MDSMoveWait.of(0.1)]))]

## Counts how often it runs, and takes as long as it is told.
class Counter extends MDSMove:
	var started := 0
	var stopped := 0
	var frames := 1
	func _start(ctx: MDSMoveContext) -> void:
		started += 1
		mem(ctx)[&"left"] = frames
	func _update(ctx: MDSMoveContext, _delta: float) -> Status:
		mem(ctx)[&"left"] = int(mem(ctx)[&"left"]) - 1
		return Status.DONE if int(mem(ctx)[&"left"]) <= 0 else Status.RUNNING
	func _stop(_ctx: MDSMoveContext) -> void:
		stopped += 1

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	await _patterns()
	await _conditions()
	await _dash()
	await _leap_and_fly()
	await _vanish()
	await _strike()
	await _zones()
	await _shots()
	await _summons()
	await _guard()
	await _cue_and_reaction()
	await _shared_moves()
	await _stagger_and_phases()
	await _partner()
	await _inherited()
	for recipe: String in MDSMoveRecipes.RECIPES:
		await _recipe(recipe)
	_clear_stage()
	await get_tree().process_frame

# --- The room -------------------------------------------------------------------------------------

func _clear_stage() -> void:
	if is_instance_valid(stage):
		stage.queue_free()
		stage = null

func _stage(player_at := Vector2(500, FLOOR_Y - 40.0)) -> void:
	_clear_stage()
	await get_tree().process_frame
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	_wall(Rect2(-100, FLOOR_Y, ROOM.size.x + 200.0, 100))
	_wall(Rect2(-100, -100, ROOM.size.x + 200.0, 100))
	_wall(Rect2(-100, -100, 100, FLOOR_Y + 200.0))
	_wall(Rect2(ROOM.size.x, -100, 100, FLOOR_Y + 200.0))
	player = CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group(&"player")
	player.collision_layer = 0
	var h := MDSHealth.new()
	h.name = "Health"
	h.stats = MDSCombatStats.make(100000)
	h.iframe_time = 0.0
	player.add_child(h)
	player_hurt = MDSHurtbox.make(MDSHurtbox.Team.PLAYER, Vector2(30, 60))
	player_hits = 0
	player.add_child(player_hurt)
	player_hurt.hurt.connect(func(_i: MDSDamageInfo) -> void: player_hits += 1)
	stage.add_child(player)
	player.global_position = player_at

func _wall(r: Rect2) -> void:
	var b := StaticBody2D.new()
	b.collision_layer = MDSGameplaySetup.bit("world")
	var cs := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = r.size
	cs.shape = s
	b.add_child(cs)
	stage.add_child(b)
	b.global_position = r.get_center()

func _enemy(moves: MDSMove, at := Vector2(1000, FLOOR_Y - 40.0), gravity_on := true) -> MDSMoveEnemy:
	var e := MDSMoveEnemy.new()
	e.name = "Enemy"
	e.moves = moves
	e.wait_to_see = false
	e.uses_gravity = gravity_on
	e.respawn = MDSEnemy.Respawn.ON_ROOM_LOAD
	stage.add_child(e)
	e.global_position = at
	e.home = at
	return e

func _boss(recipe := "", at := Vector2(1000, FLOOR_Y - 50.0)) -> MDSMoveBoss:
	var b := MDSMoveBoss.new()
	b.name = "Boss"
	b.recipe = recipe
	stage.add_child(b)
	b.global_position = at
	b.home = at
	b.fight._context().arena = ROOM
	return b

func _count(kind: Script) -> int:
	var n := 0
	for c in stage.get_children():
		if is_instance_of(c, kind) and not c.is_queued_for_deletion():
			n += 1
	return n

## The state running its moves.
func _state(e: MDSEnemy) -> MDSMoveState:
	return e.machine.current as MDSMoveState

# --- Patterns ------------------------------------------------------------------------------------

func _run_alone(move: MDSMove, frames := 200) -> int:
	# A move run on a still enemy: frames until it finished.
	var holder := _enemy(MDSMoveWait.of(60.0))
	await physics_frames(1)
	var ctx := MDSMoveContext.new(holder)
	move.begin(ctx)
	var used := 0
	for i in frames:
		used += 1
		if ctx.step(move, 1.0 / 60.0) != MDSMove.Status.RUNNING:
			break
		await get_tree().physics_frame
	move.end(ctx)
	holder.queue_free()
	return used

func _patterns() -> void:
	await _stage()
	var a := Counter.new()
	var b := Counter.new()
	b.frames = 3
	var seq := MDSMoveSequence.of([a, b])
	var used := await _run_alone(seq)
	check(a.started == 1 and b.started == 1, "a sequence runs each move once")
	check(a.stopped == 1 and b.stopped == 1, "a sequence stops each move")
	check(used >= 4 and used < 10, "a sequence takes as long as its moves (%d frames)" % used)

	var r := Counter.new()
	await _run_alone(MDSMoveRepeat.of(r, 3))
	check(r.started == 3, "a repeat runs its move the set number of times")

	var fast := Counter.new()
	var slow := Counter.new()
	slow.frames = 500
	var p := MDSMoveParallel.of([fast, slow] as Array[MDSMove], true)
	await _run_alone(p, 30)
	check(fast.started == 1 and slow.started == 1, "a parallel starts all of its moves")
	check(slow.stopped == 1, "a parallel that ends with the first stops the rest")

	var one := Counter.new()
	var two := Counter.new()
	var turn := MDSMovePick.of([one, two] as Array[MDSMove], MDSMovePick.Mode.IN_TURN)
	var holder := _enemy(MDSMoveWait.of(60.0))
	await physics_frames(1)
	var ctx := MDSMoveContext.new(holder)
	for i in 4:
		turn.begin(ctx)
		while ctx.step(turn, 1.0 / 60.0) == MDSMove.Status.RUNNING:
			pass
		turn.end(ctx)
	check(one.started == 2 and two.started == 2, "a pick in turn takes each in turn")

	var never := Counter.new()
	never.when = [MDSMoveCondition.make(MDSMoveCondition.Kind.ALWAYS, 0.0, true)]
	var ready := Counter.new()
	var firsts := MDSMovePick.of([never, ready] as Array[MDSMove], MDSMovePick.Mode.FIRST_READY)
	firsts.begin(ctx)
	ctx.step(firsts, 1.0 / 60.0)
	firsts.end(ctx)
	check(never.started == 0 and ready.started == 1, "a pick skips a move whose condition fails")

	var cooled := Counter.new()
	cooled.cooldown = 100.0
	cooled.begin(ctx)
	ctx.step(cooled, 1.0 / 60.0)
	cooled.end(ctx)
	check(not cooled.can_start(ctx), "a move on cooldown can't start")

	var weighted := MDSMovePick.new()
	var heavy := Counter.new()
	heavy.weight = 1000.0
	var light := Counter.new()
	light.weight = 0.001
	weighted.moves = [heavy, light]
	weighted.no_repeat = false
	for i in 20:
		weighted.begin(ctx)
		ctx.step(weighted, 1.0 / 60.0)
		weighted.end(ctx)
	check(heavy.started >= 18, "a heavier move is picked more often (%d of 20)" % heavy.started)

func _conditions() -> void:
	await _stage(Vector2(500, 300))
	var e := _boss()
	await physics_frames(2)
	var ctx := e.fight._context()
	var K := MDSMoveCondition.Kind
	var test := func(kind: int, value := 0.0, invert := false, flag := &"") -> bool:
		return MDSMoveCondition.make(kind, value, invert, flag).holds(ctx)
	check(test.call(K.ALWAYS), "always holds")
	check(not test.call(K.ALWAYS, 0.0, true), "a condition can be turned around")
	check(test.call(K.PLAYER_FAR, 200.0) and not test.call(K.PLAYER_NEAR, 200.0), "player far, not near")
	check(test.call(K.PLAYER_ABOVE, 50.0) and not test.call(K.PLAYER_BELOW, 50.0), "player above, not below")
	check(test.call(K.PLAYER_IN_AIR), "a player off the ground is in the air")
	check(not test.call(K.PLAYER_OUTSIDE_ARENA), "the player is in the arena")
	check(test.call(K.HEALTH_BELOW, 1.0) and not test.call(K.HEALTH_BELOW, 0.5), "health share")
	check(test.call(K.PHASE_AT_LEAST, 0.0) and not test.call(K.PHASE_AT_LEAST, 1.0), "phase")
	check(not test.call(K.FLAG, 0.0, false, &"seen"), "a flag not set")
	ctx.flags[&"seen"] = true
	check(test.call(K.FLAG, 0.0, false, &"seen"), "a flag set")
	check(test.call(K.SUMMONS_BELOW, 1.0), "nothing summoned")
	check(not test.call(K.HIT_WITHIN, 1.0), "not hit yet")
	e.health.take_damage(1.0)
	check(test.call(K.HIT_WITHIN, 1.0), "just hit")
	check(test.call(K.CHANCE, 1.1) and not test.call(K.CHANCE, -1.0), "chance")
	e.facing = 1
	check(test.call(K.PLAYER_BEHIND), "the player is behind what faces away")
	var e2 := MDSMoveCondition.make(K.PLAYER_NEAR, 200.0)
	check(not e2.holds(ctx), "the player isn't near")

# --- Actions -------------------------------------------------------------------------------------

func _dash() -> void:
	await _stage(Vector2(700, FLOOR_Y - 40.0))
	var d := MDSMoveDash.of(MDSMoveDash.Aim.TOWARD_PLAYER, 900.0, 0.5, 0.05, Vector2(90, 60), 2)
	var rest := MDSMoveWait.of(60.0)
	var e := _enemy(MDSMoveSequence.of([d, rest]))
	e.contact.active = false
	await physics_frames(50)
	check(e.global_position.x < 800.0, "a dash rushes at the player (at %.0f)" % e.global_position.x)
	check(player_hits > 0, "a dash hits on the way")

	await _stage(Vector2(800, 300))
	var whirl := MDSMoveDash.of(MDSMoveDash.Aim.FORWARD, 1500.0, 1.2, 0.0)
	whirl.bounces = 1
	whirl.stop_at_wall = false
	var w := _enemy(MDSMoveSequence.of([whirl, MDSMoveWait.of(60.0)]), Vector2(1300, FLOOR_Y - 40.0))
	w.facing = 1
	var turned := false
	for i in 70:
		await get_tree().physics_frame
		if w.velocity.x < 0.0:
			turned = true
	check(turned, "a dash comes back off a wall")

	await _stage(Vector2(600, FLOOR_Y - 40.0))
	var dive := MDSMoveDash.of(MDSMoveDash.Aim.AT_PLAYER, 900.0, 0.3, 0.0)
	dive.keep_gravity = false
	dive.skid = 0.3
	var f := _enemy(MDSMoveSequence.of([dive, MDSMoveWait.of(60.0)]), Vector2(1000, 300), false)
	var skidding := false
	for i in 90:
		await get_tree().physics_frame
		if f.is_on_floor() and absf(f.velocity.x) > 100.0 and absf(f.velocity.y) < 1.0:
			skidding = true
	check(skidding, "a dive reaches the ground and skids along it")
	check(not f.machine.current == null, "still fighting after a dive")

func _leap_and_fly() -> void:
	await _stage(Vector2(600, FLOOR_Y - 40.0))
	var leap := MDSMoveLeap.of(MDSMove.Anchor.PLAYER, 260.0, MDSMoveLeap.EndAt.LANDING, 0.0)
	leap.slam_size = Vector2(300, 40)
	var e := _enemy(MDSMoveSequence.of([leap, MDSMoveWait.of(60.0)]))
	e.contact.active = false
	await physics_frames(5)
	var highest := e.global_position.y
	for i in 110:
		await get_tree().physics_frame
		highest = minf(highest, e.global_position.y)
	check(highest < FLOOR_Y - 200.0, "a leap goes up (to %.0f)" % highest)
	check(absf(e.global_position.x - 600.0) < 120.0, "a leap lands on the player (at %.0f)" % e.global_position.x)
	check(e.is_on_floor(), "a leap lands")
	check(player_hits > 0, "a slam hits on landing")

	await _stage()
	var apex := MDSMoveLeap.of(MDSMove.Anchor.SELF, 200.0, MDSMoveLeap.EndAt.APEX, 0.0)
	var a := _enemy(MDSMoveSequence.of([apex, MDSMoveWait.of(60.0)]))
	await physics_frames(40)
	check(a.global_position.y < FLOOR_Y - 100.0, "a leap can end at its top (at %.0f)" % a.global_position.y)

	await _stage(Vector2(300, FLOOR_Y - 40.0))
	var fly := MDSMoveFly.of(MDSMove.Anchor.ABOVE_PLAYER, 900.0)
	var f := _enemy(MDSMoveSequence.of([fly, MDSMoveWait.of(60.0)]), Vector2(1000, 400), false)
	await physics_frames(70)
	var want := player.global_position + Vector2(0, -220)
	check(f.global_position.distance_to(want) < 40.0, "a flight reaches its place (%s)" % f.global_position)

	await _stage()
	var up := MDSMoveFly.of(MDSMove.Anchor.CEILING_ABOVE_SELF, 900.0)
	var u := _enemy(MDSMoveSequence.of([up, MDSMoveWait.of(60.0)]), Vector2(1000, 400), false)
	await physics_frames(50)
	check(u.global_position.y < u.body_size.y, "a flight reaches the ceiling (at %.0f)" % u.global_position.y)

func _vanish() -> void:
	await _stage(Vector2(300, FLOOR_Y - 40.0))
	var v := MDSMoveVanish.of(MDSMoveVanish.Mode.VANISH_AND_RETURN, 0.5, MDSMove.Anchor.FLOOR_AT_PLAYER, Vector2(150, 0))
	v.marker_time = 0.3
	var e := _enemy(MDSMoveSequence.of([v, MDSMoveWait.of(60.0)]))
	await physics_frames(10)
	check(not e.hurtbox.enabled, "it can't be hit while gone")
	check(not e.contact.active, "it doesn't hit while gone")
	check(is_zero_approx(e.modulate.a), "it can't be seen while gone")
	await physics_frames(15)
	check(_count(MDSCombatZone) == 1, "a mark shows where it will come back")
	await physics_frames(20)
	check(e.hurtbox.enabled and e.modulate.a > 0.9, "it comes back")
	check(absf(e.global_position.x - 450.0) < 20.0, "it comes back beside the player (at %.0f)" % e.global_position.x)
	check(absf(e.global_position.y - (FLOOR_Y - e.body_size.y * 0.5)) < 8.0, "it comes back on the floor (at %.0f)" % e.global_position.y)

	await _stage()
	var hide := MDSMoveVanish.of(MDSMoveVanish.Mode.HIDE, 0.05)
	var shown := MDSMoveVanish.of(MDSMoveVanish.Mode.SHOW, 0.05, MDSMove.Anchor.ARENA_CENTER)
	var s := _enemy(MDSMoveSequence.of([hide, MDSMoveWait.of(0.3), shown, MDSMoveWait.of(60.0)]))
	await physics_frames(10)
	check(not s.hurtbox.enabled, "hidden stays hidden through the next move")
	await physics_frames(50)
	check(s.hurtbox.enabled, "and comes back when it is told to")

	# A stop in the middle brings it back whatever it was doing.
	await _stage()
	var b := _boss()
	b.phases = [MDSMovePhase.of(1.0, MDSMoveVanish.of(MDSMoveVanish.Mode.HIDE, 10.0))] as Array[MDSBossPhase]
	b.start_fight()
	await physics_frames(5)
	check(not b.hurtbox.enabled, "a boss can hide")
	b.machine.force(&"Stagger")
	check(b.hurtbox.enabled, "a stagger brings it back")

func _strike() -> void:
	await _stage(Vector2(900, FLOOR_Y - 40.0))
	var s := MDSMoveStrike.of(0.2, Vector2(140, 80), Vector2(70, 0), 3, 0.2)
	var e := _enemy(MDSMoveSequence.of([s, MDSMoveWait.of(60.0)]))
	e.contact.active = false
	await physics_frames(6)
	check(player_hits == 0, "a strike warns first")
	check(not is_equal_approx(e.modulate.g, 1.0), "it changes color as it winds up")
	await physics_frames(25)
	check(player_hits == 1, "then it hits, once (hit %d)" % player_hits)
	check(is_equal_approx(e.modulate.g, 1.0), "and looks itself again")
	await physics_frames(20)
	check(player_hits == 1, "and stops hitting")
	var box := e.get_node_or_null(^"MoveHitbox") as MDSHitbox
	check(box != null and not box.active, "its hit goes off")

func _zones() -> void:
	await _stage()
	var z := MDSMoveZones.of(MDSMoveZones.Place.AT_PLAYER, 1, Vector2(200, 200), 0.3, 0.2)
	var e := _enemy(MDSMoveSequence.of([z, MDSMoveWait.of(60.0)]), Vector2(1400, FLOOR_Y - 40.0))
	await physics_frames(5)
	check(_count(MDSCombatZone) == 1, "a zone appears")
	check(player_hits == 0, "it warns first")
	await physics_frames(25)
	check(player_hits == 1, "then it hurts")
	await physics_frames(20)
	check(_count(MDSCombatZone) == 0, "then it is gone")

	await _stage(Vector2(100, FLOOR_Y - 40.0))
	var floor_row := MDSMoveZones.of(MDSMoveZones.Place.FLOOR_EVEN, 4, Vector2(60, 300), 0.5, 0.2, MDSCombatZone.Shape.BOX)
	floor_row.interval = 0.0
	var r := _boss()
	r.phases = [MDSMovePhase.of(1.0, MDSMoveSequence.of([floor_row, MDSMoveWait.of(60.0)]))] as Array[MDSBossPhase]
	r.start_fight()
	await physics_frames(5)
	var xs: Array[float] = []
	for c in stage.get_children():
		if c is MDSCombatZone:
			xs.append(c.global_position.x)
			check_near(c.global_position.y, FLOOR_Y, 2.0, "a column stands on the floor")
	xs.sort()
	check(xs.size() == 4, "all come at once")
	if xs.size() == 4:
		check_near(xs[1] - xs[0], ROOM.size.x / 4.0, 2.0, "evenly spaced")

	await _stage(Vector2(100, FLOOR_Y - 40.0))
	var wall := MDSMoveZones.of(MDSMoveZones.Place.CEILING_RANDOM, 1, Vector2(50, 400), 0.05, 30.0, MDSCombatZone.Shape.BOX)
	wall.hits_to_break = 3
	var b := _boss()
	b.phases = [MDSMovePhase.of(1.0, MDSMoveSequence.of([wall, MDSMoveWait.of(60.0)]))] as Array[MDSBossPhase]
	b.start_fight()
	await physics_frames(5)
	var wz: MDSCombatZone = null
	for c in stage.get_children():
		if c is MDSCombatZone:
			wz = c
	check(wz != null, "a wall grows")
	if wz:
		check_near(wz.global_position.y, 0.0, 2.0, "it hangs from the ceiling")
		var hit := MDSDamageInfo.make(1, "physical")
		var guard := wz.get_node(^"Guard") as MDSHurtbox
		guard.receive(hit)
		guard.receive(hit)
		check(not wz.is_queued_for_deletion(), "it stands two hits")
		guard.receive(hit)
		check(wz.is_queued_for_deletion(), "and breaks on the third")
	await physics_frames(2)
	var w2 := MDSMoveZones.of(MDSMoveZones.Place.CEILING_RANDOM, 2, Vector2(50, 400), 0.05, 30.0, MDSCombatZone.Shape.BOX)
	w2.hits_to_break = 3
	w2.interval = 0.0
	b.fight.pending(w2)
	b.fight._stop_current()
	await physics_frames(5)
	check(_count(MDSCombatZone) >= 2, "two more grow")
	b.stagger_time = 0.1
	b._on_staggered()
	await physics_frames(2)
	check(_count(MDSCombatZone) == 0, "a stagger clears them")

func _shots() -> void:
	await _stage(Vector2(600, FLOOR_Y - 40.0))
	var s := MDSMoveShoot.of(MDSMoveShoot.From.SELF, MDSMoveShoot.Aim.AT_PLAYER, 3, 900.0, 0.05)
	s.windup = 0.05
	var e := _enemy(MDSMoveSequence.of([s, MDSMoveWait.of(60.0)]))
	e.contact.active = false
	await physics_frames(16)
	check(_count(MDSBossShot) >= 2, "it fires, one after another (%d)" % _count(MDSBossShot))
	await physics_frames(40)
	check(player_hits == 3, "each reaches the player (hit %d)" % player_hits)

	await _stage(Vector2(100, 100))
	var rocks := MDSMoveShoot.of(MDSMoveShoot.From.CEILING_ABOVE_PLAYER, MDSMoveShoot.Aim.DOWN, 1, 300.0, 0.0)
	rocks.marker_time = 0.2
	rocks.windup = 0.0
	_enemy(MDSMoveSequence.of([rocks, MDSMoveWait.of(60.0)]))
	await physics_frames(4)
	check(_count(MDSCombatZone) == 1 and _count(MDSBossShot) == 0, "a rock warns before it falls")
	await physics_frames(20)
	check(_count(MDSBossShot) == 1, "then it falls")

	await _stage(Vector2(100, 100))
	var bomb := MDSMoveShoot.of(MDSMoveShoot.From.SELF, MDSMoveShoot.Aim.FORWARD, 1, 800.0, 0.0)
	bomb.windup = 0.0
	bomb.bounces = 1
	bomb.fuse = 0.2
	bomb.lifetime = 5.0
	var be := _enemy(MDSMoveSequence.of([bomb, MDSMoveWait.of(60.0)]), Vector2(1200, FLOOR_Y - 40.0))
	be.facing = 1
	await physics_frames(3)
	var shot: MDSBossShot = null
	for c in stage.get_children():
		if c is MDSBossShot:
			shot = c
	check(shot != null, "a bomb flies")
	var went_back := false
	for i in 80:
		await get_tree().physics_frame
		if is_instance_valid(shot) and shot.velocity.x < 0.0:
			went_back = true
			break
	check(went_back, "it comes back off the wall")
	var stopped := false
	var burst := false
	for i in 240:
		await get_tree().physics_frame
		if is_instance_valid(shot) and shot.velocity == Vector2.ZERO:
			stopped = true
		if _count(MDSCombatZone) > 0:
			burst = true
			break
	check(stopped, "then it stops")
	check(burst, "then it goes off")

	await _stage(Vector2(100, 100))
	var knock := MDSBossShot.new()
	knock.team = MDSHitbox.Team.ENEMY
	knock.velocity = Vector2(-300, 0)
	knock.knockable = true
	knock.lifetime = 5.0
	stage.add_child(knock)
	knock.global_position = Vector2(800, 400)
	await physics_frames(1)
	var info := MDSDamageInfo.make(1, "physical")
	info.origin = Vector2(900, 400)
	(knock.get_node(^"Guard") as MDSHurtbox).receive(info)
	check(knock.velocity.x < 0.0, "a knocked shot flies away from the hit")
	info.origin = Vector2(700, 400)
	(knock.get_node(^"Guard") as MDSHurtbox).receive(info)
	check(knock.velocity.x > 0.0, "the other way when hit from the other side")

func _summons() -> void:
	await _stage()
	var s := MDSMoveSummon.of(MDSWalker, 2, MDSMove.Anchor.FLOOR_AT_PLAYER)
	s.marker_time = 0.05
	s.max_alive = 2
	var again := MDSMoveRepeat.of(s, 3)
	var b := _boss()
	b.phases = [MDSMovePhase.of(1.0, MDSMoveSequence.of([again, MDSMoveWait.of(60.0)]))] as Array[MDSBossPhase]
	b.start_fight()
	await physics_frames(30)
	check(_count(MDSWalker) == 2, "it calls only as many as may live (%d)" % _count(MDSWalker))
	b.stagger_time = 0.1
	b._on_staggered()
	await physics_frames(3)
	var alive := 0
	for c in stage.get_children():
		if c is MDSWalker and not (c as MDSEnemy).dying:
			alive += 1
	check(alive == 0, "a stagger ends what it called")

	await _stage()
	var w := MDSMoveSummon.of(MDSWalker, 1, MDSMove.Anchor.FLOOR_AT_PLAYER)
	w.marker_time = 0.0
	w.wait_for_them = true
	w.wait_seconds = 30.0
	var after := Counter.new()
	var e := _enemy(MDSMoveSequence.of([w, after, MDSMoveWait.of(60.0)]))
	await physics_frames(10)
	check(after.started == 0, "it waits while what it called lives")
	for c in stage.get_children():
		if c is MDSWalker:
			(c as MDSEnemy).health.take_damage(1000.0)
	await physics_frames(5)
	check(after.started == 1, "and goes on when it is dead")
	check(e != null, "the enemy lives on")

func _guard() -> void:
	await _stage(Vector2(900, FLOOR_Y - 40.0))
	var counter := Counter.new()
	counter.frames = 6
	var g := MDSMoveGuard.of(0.4, counter)
	var after := Counter.new()
	var e := _enemy(MDSMoveSequence.of([g, after, MDSMoveWait.of(60.0)]))
	await physics_frames(4)
	var hp := e.health.current
	var dealt := e.hurtbox.receive(MDSDamageInfo.make(1, "physical"))
	check(dealt == 0 and e.health.current == hp, "on guard, a hit doesn't land")
	await physics_frames(3)
	check(counter.started == 1, "it answers with its riposte")
	check(after.started == 0, "and finishes that first")
	await physics_frames(8)
	check(after.started == 1, "then goes on")
	check(e.hurtbox.receive(MDSDamageInfo.make(1, "physical")) > 0, "a hit lands again")

	await _stage()
	var quiet := Counter.new()
	var g2 := MDSMoveGuard.of(0.1, quiet)
	var next := Counter.new()
	_enemy(MDSMoveSequence.of([g2, next, MDSMoveWait.of(60.0)]))
	await physics_frames(12)
	check(quiet.started == 0 and next.started == 1, "unhit, it just lowers its guard")

func _cue_and_reaction() -> void:
	await _stage()
	var b := _boss()
	var cues: Array[StringName] = []
	b.move_cue.connect(func(c: StringName) -> void: cues.append(c))
	var cue := MDSMoveCue.of(0.0, 4.0, &"opened")
	cue.cue = &"roar"
	var reaction := Counter.new()
	reaction.when = [MDSMoveCondition.make(MDSMoveCondition.Kind.PLAYER_NEAR, 100.0)]
	reaction.cooldown = 100.0
	var long_wait := Counter.new()
	long_wait.frames = 100000
	b.phases = [MDSMovePhase.of(1.0, long_wait, 1.0, cue, [reaction])] as Array[MDSBossPhase]
	b.start_fight()
	await physics_frames(4)
	check(cues.size() == 1 and cues[0] == &"roar", "a cue sends its signal")
	check(b.fight.ctx.flags.get(&"opened", false), "a cue sets its flag")
	check(reaction.started == 0, "a reaction waits for its condition")
	check(long_wait.started == 1, "the moves run after the opening")
	player.global_position = b.global_position + Vector2(60, 0)
	await physics_frames(3)
	check(reaction.started == 1, "a reaction cuts in")
	check(long_wait.stopped == 1, "what it cut short is stopped")
	await physics_frames(3)
	check(reaction.started == 1, "its cooldown holds it back")
	check(long_wait.started == 2, "and the moves go on")

func _shared_moves() -> void:
	await _stage()
	var wait := MDSMoveWait.of(0.2)
	var mark := Counter.new()
	var shared := MDSMoveSequence.of([wait, mark])
	_enemy(shared, Vector2(1000, FLOOR_Y - 40.0))
	await physics_frames(6)
	var other := _enemy(shared, Vector2(1200, FLOOR_Y - 40.0))
	check(other.machine != null, "a second enemy uses the same moves")
	await physics_frames(9)
	check(mark.started == 1, "the first keeps its own time (%d)" % mark.started)
	await physics_frames(7)
	check(mark.started >= 2, "and so does the second (%d)" % mark.started)

func _stagger_and_phases() -> void:
	await _stage()
	var b := _boss()
	b.stagger_hits = 3
	b.stagger_time = 0.3
	var count := [0]
	b.staggered.connect(func() -> void: count[0] += 1)
	var a := Counter.new()
	a.frames = 100000
	var b2 := Counter.new()
	b2.frames = 100000
	var opener := Counter.new()
	b.phases = [MDSMovePhase.of(1.0, a), MDSMovePhase.of(0.5, b2, 1.5, opener)] as Array[MDSBossPhase]
	b.start_fight()
	await physics_frames(3)
	check(a.started == 1, "the first phase runs")
	for i in 3:
		b.hurtbox.receive(MDSDamageInfo.make(1, "physical"))
		await physics_frames(7)
	check(count[0] == 1, "enough hits stagger it (%d)" % count[0])
	check(b.machine.is_in(&"Stagger"), "it reels")
	check(a.stopped == 1, "what it was doing stops")
	await physics_frames(25)
	check(b.machine.is_in(&"Idle"), "then fights on")
	check(a.started == 2, "going back to its moves")

	b.health.set_current(int(b.health.get_max() * 0.4))
	await physics_frames(2)
	check(b.phase_index == 1, "health moves it to the next phase")
	check_near(b.fight.ctx.speed_scale, 1.5, 0.01, "at that phase's speed")
	check(a.stopped == 2, "the old phase stops")
	await physics_frames(int(b.phase_pause * 60.0) + 10)
	check(opener.started == 1, "the phase opens with its opening")
	check(b2.started == 1, "then its moves")

func _partner() -> void:
	await _stage()
	var arena := MDSBossArena.new()
	arena.name = "Arena"
	arena.size = ROOM.size
	var a := MDSMoveBoss.new()
	a.name = "First"
	a.boss_name = "Twins"
	a.phases = [MDSMovePhase.of(1.0, MDSMoveWait.of(60.0))] as Array[MDSBossPhase]
	a.arena = arena
	stage.add_child(a)
	a.global_position = Vector2(1000, FLOOR_Y - 50.0)
	a.fight._context().arena = ROOM
	arena.boss = a
	stage.add_child(arena)
	arena.global_position = ROOM.get_center()
	await physics_frames(1)
	var won := [0]
	arena.fight_won.connect(func(_b: Variant) -> void: won[0] += 1)
	arena.start()
	await physics_frames(2)
	check(a.fighting, "the arena starts the fight")
	var call_partner := MDSMoveSummon.of(MDSMoveBoss, 1, MDSMove.Anchor.FLOOR_AT_PLAYER)
	call_partner.marker_time = 0.0
	call_partner.partner = true
	call_partner.properties = {"recipe": "swooper"}
	a.fight.pending(call_partner)
	a.fight._stop_current()
	await physics_frames(3)
	check(a.partners.size() == 1, "it calls a partner")
	if a.partners.is_empty():
		return
	var b := a.partners[0] as MDSMoveBoss
	check(b.fighting, "the partner joins the fight")
	check(b.boss_name == "Twins", "under the same name")
	a.fight._context().clear_spawned()
	check(is_instance_valid(b) and not b.dying, "clearing the room doesn't kill a partner")
	a.health.take_damage(10000.0)
	await physics_frames(2)
	check(a.dying and arena.fighting, "the fight goes on when the first falls")
	check(won[0] == 0, "not won yet")
	check(a.respawn == MDSEnemy.Respawn.ON_ROOM_LOAD, "the first isn't gone for good until both are")
	b.health.take_damage(10000.0)
	await physics_frames(2)
	check(won[0] == 1 and not arena.fighting, "the fight ends when both have fallen")
	check(b.respawn == MDSEnemy.Respawn.NEVER, "the last settles it for good")

	# Killed before it called its partner, the partner comes anyway.
	await _stage()
	var twin := _boss("twin_swooper")
	twin.boss_name = "Twins"
	twin.start_fight()
	await physics_frames(2)
	twin.health.take_damage(10000.0)
	await physics_frames(2)
	check(twin.partners.size() == 1, "a partner comes when the first falls before calling it")
	check(twin.respawn == MDSEnemy.Respawn.ON_ROOM_LOAD, "and the first isn't gone for good yet")

func _inherited() -> void:
	await _stage(Vector2(700, FLOOR_Y - 40.0))
	var h := Hopper.new()
	h.name = "Hopper"
	stage.add_child(h)
	h.global_position = Vector2(1100, FLOOR_Y - 50.0)
	await physics_frames(2)
	check(h.phases.size() == 1 and h.phases[0] is MDSMovePhase, "an inherited boss builds its own phases")
	h.start_fight()
	await physics_frames(60)
	check(h.global_position.x < 1000.0, "and fights with them (at %.0f)" % h.global_position.x)

	await _stage()
	var plain := MDSBoss.new()
	plain.name = "Plain"
	stage.add_child(plain)
	plain.global_position = Vector2(1000, FLOOR_Y - 50.0)
	await physics_frames(2)
	check(plain.stagger_hits == 0, "an old boss doesn't stagger from hits")
	plain.health.take_damage(1.0)
	await physics_frames(1)
	check(not plain.machine.is_in(&"Stagger"), "so a hit doesn't make it reel")

# --- Recipes -------------------------------------------------------------------------------------

## The attacks of a phase: what its pick chooses from.
func _attacks(move: MDSMove) -> Array[MDSMove]:
	if move is MDSMovePick:
		return (move as MDSMovePick).moves
	for c in move.get_children_moves():
		var found := _attacks(c)
		if not found.is_empty():
			return found
	return []

func _recipe(recipe: String) -> void:
	await _stage(Vector2(500, FLOOR_Y - 40.0))
	var b := _boss(recipe, Vector2(1100, 300))
	b.boss_name = recipe
	check(b.phases.size() >= 1 and b.phases[0] is MDSMovePhase, "%s has phases" % recipe)
	b.health.invulnerable = false
	b.start_fight()
	var saw := {}
	var watch := func(frames: int) -> bool:
		for i in frames:
			await get_tree().physics_frame
			for c in stage.get_children():
				if c is MDSCombatZone:
					saw[&"zone"] = true
				elif c is MDSBossShot:
					saw[&"shot"] = true
				elif c is MDSEnemy and c != b:
					saw[&"summon"] = true
			if b.modulate.a <= 0.01:
				saw[&"hidden"] = true
			if not ROOM.grow(90.0).has_point(b.global_position):
				saw[&"left_room"] = b.global_position
			if not b.machine.is_in(&"Idle") and not b.machine.is_in(&"Stagger"):
				saw[&"lost"] = b.machine.current.name
		return true
	await watch.call(120)
	# Into the last phase: every attack, one at a time.
	var last := b.phases[b.phases.size() - 1] as MDSMovePhase
	b.health.set_current(ceili(b.health.get_max() * 0.2))
	check(b.phase_index == b.phases.size() - 1, "%s reaches its last phase" % recipe)
	await watch.call(int(b.phase_pause * 60.0) + 6)
	var all := _attacks(last.moves)
	check(not all.is_empty(), "%s has attacks" % recipe)
	var started := 0
	for attack in all:
		b.fight._stop_current()
		b.fight.pending(attack)
		await watch.call(2)
		if b.fight._current == attack:
			started += 1
		for i in 40:
			await watch.call(10)
			if b.fight._current != attack:
				break
		check(b.fight._current != attack, "%s: %s finishes" % [recipe, attack.title if attack.title else attack.get_class()])
	check(started >= all.size() - 1, "%s: its attacks run (%d of %d)" % [recipe, started, all.size()])
	check(not saw.has(&"left_room"), "%s stays in the room (%s)" % [recipe, saw.get(&"left_room", "")])
	check(not saw.has(&"lost"), "%s stays in the fight (%s)" % [recipe, saw.get(&"lost", "")])
	check(player_hits > 0, "%s hurts the player" % recipe)
	for want: StringName in EXPECT[recipe]:
		check(saw.has(want), "%s: uses a %s (saw %s)" % [recipe, want, saw.keys()])
	print("  %s: %d hits, saw %s" % [recipe, player_hits, saw.keys()])
	b.health.take_damage(100000.0)
	await physics_frames(2)
	check(b.dying, "%s dies" % recipe)
	await physics_frames(3)
	var left := 0
	for c in stage.get_children():
		if c is MDSCombatZone and (c as MDSCombatZone).source == b and not c.is_queued_for_deletion():
			left += 1
	check(left == 0, "%s clears what it left when it dies (%d)" % [recipe, left])
