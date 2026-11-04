class_name MDSMoveRecipes
extends RefCounted
## Whole fights built from moves, each a starting point to change or copy. They are patterns, with
## placeholder looks: your own art and tuning make them your own bosses.
##
## - [b]swooper[/b]: a flyer. Dives and skids; later rams the ceiling, bringing down rocks, then adds.
## - [b]twin_swooper[/b]: the same, and at half health it calls a second one, which must fall too.
## - [b]showman[/b]: a bouncing whirlwind, fireworks, bombs, flutters, travel under the floor; at half
##   health, columns of fire from below.
## - [b]duelist[/b]: a fencer. Lunges, cuts, a leaping spin, guard and riposte, a slash at the player's
##   spot. Three phases, with reactions to a player too close.
## - [b]possessed_duelist[/b]: dives through the floor between attacks, long lashes, arcing shots,
##   columns. Four phases, faster and faster.
## - [b]hanging_matriarch[/b]: hangs from the ceiling. Three swipes from above, thorn walls to cut
##   down, flying adds; at low health, a full row of walls.

const RECIPES: PackedStringArray = ["swooper", "twin_swooper", "showman", "duelist", "possessed_duelist", "hanging_matriarch"]

## Gives [param boss] the fight named [param recipe]: its phases and how it moves.
static func setup(boss: MDSMoveBoss, recipe: String) -> void:
	match recipe:
		"swooper":
			_swooper(boss, false)
		"twin_swooper":
			_swooper(boss, true)
		"showman":
			_showman(boss)
		"duelist":
			_duelist(boss)
		"possessed_duelist":
			_possessed_duelist(boss)
		"hanging_matriarch":
			_hanging_matriarch(boss)
		_:
			push_warning("MDS: no fight named %s" % recipe)

static func _near(pixels: float) -> MDSMoveCondition:
	return MDSMoveCondition.make(MDSMoveCondition.Kind.PLAYER_NEAR, pixels)

static func _health(share: float) -> MDSMoveCondition:
	return MDSMoveCondition.make(MDSMoveCondition.Kind.HEALTH_BELOW, share)

static func _weighted(move: MDSMove, p_weight: float, p_cooldown := 0.0) -> MDSMove:
	move.weight = p_weight
	move.cooldown = p_cooldown
	return move

## A hit from the wall of a dash with these numbers, and a beat to punish it.
static func _dive(speed: float, skid: float, damage: int) -> MDSMoveDash:
	var d := MDSMoveDash.of(MDSMoveDash.Aim.AT_PLAYER, speed, 0.7, 0.45, Vector2(70, 50), damage)
	d.keep_gravity = false
	d.skid = skid
	return d

static func _swooper(boss: MDSMoveBoss, twin: bool) -> void:
	boss.uses_gravity = false
	boss.look = MDSEnemy.Look.BAT
	boss.body_size = Vector2(90, 60)
	boss.stagger_hits = 11
	boss.stagger_time = 2.0
	var rise := MDSMoveFly.of(MDSMove.Anchor.ABOVE_PLAYER, 520.0, Vector2(0, -60))
	var swoop := MDSMoveSequence.of([rise, _dive(760.0, 0.55, 1), MDSMoveWait.of(0.7, 0.4)], "swoop")
	var ceiling := MDSMoveFly.of(MDSMove.Anchor.CEILING_ABOVE_SELF, 900.0)
	var rocks := MDSMoveShoot.of(MDSMoveShoot.From.CEILING_RANDOM, MDSMoveShoot.Aim.DOWN, 3, 620.0, 0.14)
	rocks.marker_time = 0.5
	rocks.windup = 0.0
	rocks.recovery = 0.6
	var grubs := MDSMoveSummon.of(MDSWalker, 2, MDSMove.Anchor.CEILING_ABOVE_PLAYER)
	grubs.max_alive = 2
	grubs.when = [_health(0.7)]
	var falls := MDSMovePick.of([_weighted(grubs, 1.0, 6.0), rocks], MDSMovePick.Mode.RANDOM)
	var ram := MDSMoveSequence.of([ceiling, MDSMoveCue.of(0.15, 12.0), falls, MDSMoveWait.of(0.5)], "ceiling_ram")
	ram.when = [_health(0.94)]
	ram.weight = 0.7
	var attacks: Array[MDSMove] = [swoop, ram]
	if twin:
		var second := MDSMoveSummon.of(MDSMoveBoss, 1, MDSMove.Anchor.CEILING_ABOVE_PLAYER)
		second.properties = {"recipe": "swooper", "boss_name": boss.boss_name, "respawn": MDSEnemy.Respawn.NEVER}
		second.partner = true
		second.title = "call_partner"
		var call_once := MDSMoveCondition.make(MDSMoveCondition.Kind.FLAG, 0.0, true, &"partner_called")
		var mark := MDSMoveCue.of(0.0, 0.0, &"partner_called")
		var calling := MDSMoveSequence.of([ceiling, MDSMoveCue.of(0.15, 12.0), mark, second, MDSMoveWait.of(0.5)], "call_partner")
		calling.when = [_health(0.5), call_once]
		calling.weight = 100.0
		attacks.append(calling)
		boss.on_death = second
	boss.phases = [MDSMovePhase.of(1.0, MDSMovePick.of(attacks), 1.0, MDSMoveCue.of(0.6, 6.0))]

static func _showman(boss: MDSMoveBoss) -> void:
	boss.look = MDSEnemy.Look.KNIGHT
	boss.body_size = Vector2(56, 90)
	boss.stagger_hits = 15
	boss.stagger_time = 2.2
	var whirl := MDSMoveDash.of(MDSMoveDash.Aim.TOWARD_PLAYER, 620.0, 1.5, 0.35, Vector2(90, 100), 2)
	whirl.bounces = 2
	whirl.stop_at_wall = false
	var offshoots := MDSMoveShoot.of(MDSMoveShoot.From.SELF, MDSMoveShoot.Aim.UP, 2, 420.0, 0.0)
	offshoots.aim = MDSMoveShoot.Aim.FAN_AT_PLAYER
	offshoots.spread = 90.0
	offshoots.drop = 500.0
	offshoots.windup = 0.05
	var whirlwind := MDSMoveSequence.of([whirl, offshoots, MDSMoveWait.of(0.5)], "whirlwind")
	var fireworks := MDSMoveZones.of(MDSMoveZones.Place.RANDOM_IN_ARENA, 5, Vector2(150, 150), 1.0, 0.25)
	fireworks.wait_until_gone = false
	fireworks.color = Color(1.0, 0.65, 0.9)
	var bombs := MDSMoveShoot.of(MDSMoveShoot.From.SELF, MDSMoveShoot.Aim.FAN_AT_PLAYER, 3, 460.0, 0.12)
	bombs.spread = 30.0
	bombs.drop = 400.0
	bombs.bounces = 2
	bombs.fuse = 0.8
	bombs.knockable = true
	bombs.lifetime = 4.0
	bombs.color = Color(0.9, 0.9, 0.4)
	var ground: Array[MDSMove] = [whirlwind, MDSMoveSequence.of([fireworks, MDSMoveWait.of(0.8)]), MDSMoveSequence.of([bombs, MDSMoveWait.of(0.6)])]
	var up := MDSMoveLeap.of(MDSMove.Anchor.SELF, 340.0, MDSMoveLeap.EndAt.APEX)
	var flutter := MDSMoveFly.of(MDSMove.Anchor.ARENA_FAR_SIDE, 460.0, Vector2(0, -160))
	var aerial := MDSMovePick.of([bombs, fireworks] as Array[MDSMove])
	var airborne := MDSMoveSequence.of([up, flutter, aerial], "flutter")
	var under := MDSMoveVanish.of(MDSMoveVanish.Mode.VANISH_AND_RETURN, 0.9, MDSMove.Anchor.ARENA_FAR_SIDE)
	under.marker_time = 0.5
	var shuffle := MDSMoveSequence.of([under, MDSMoveWait.of(0.3)], "floor_shuffle")
	var attacks: Array[MDSMove] = []
	attacks.append_array(ground)
	attacks.append(airborne)
	attacks.append(_weighted(shuffle, 0.6))
	var dodge := MDSMoveDash.of(MDSMoveDash.Aim.AWAY_FROM_PLAYER, 620.0, 0.22, 0.0)
	dodge.when = [_near(110.0)]
	dodge.cooldown = 3.0
	var phase_one := MDSMovePick.of(attacks)
	var hide := MDSMoveVanish.of(MDSMoveVanish.Mode.HIDE, 0.3)
	var pillars := MDSMoveZones.of(MDSMoveZones.Place.FLOOR_RANDOM, 5, Vector2(90, 420), 0.6, 0.35, MDSCombatZone.Shape.BOX, 2)
	pillars.interval = 0.35
	pillars.color = Color(1.0, 0.45, 0.2)
	var rise := MDSMoveVanish.of(MDSMoveVanish.Mode.SHOW, 0.2, MDSMove.Anchor.FLOOR_AT_PLAYER, Vector2(0, -120))
	var pyro := MDSMoveSequence.of([hide, pillars, rise, MDSMoveWait.of(0.5)], "pyrotechnics")
	var late: Array[MDSMove] = []
	late.append_array(attacks)
	late.append(pyro)
	boss.phases = [
		MDSMovePhase.of(1.0, phase_one, 1.0, MDSMoveCue.of(0.5, 4.0), [dodge]),
		MDSMovePhase.of(0.5, MDSMovePick.of(late), 1.15, pyro, [dodge]),
	]

static func _duelist(boss: MDSMoveBoss) -> void:
	boss.look = MDSEnemy.Look.KNIGHT
	boss.body_size = Vector2(44, 84)
	boss.stagger_hits = 16
	boss.stagger_time = 2.0
	var lunge := MDSMoveDash.of(MDSMoveDash.Aim.TOWARD_PLAYER, 980.0, 0.32, 0.35, Vector2(110, 50), 2)
	var cut := MDSMoveStrike.of(0.22, Vector2(130, 110), Vector2(70, -10), 1, 0.12, 180.0)
	var last_cut := MDSMoveStrike.of(0.18, Vector2(150, 120), Vector2(70, -10), 2, 0.45, 220.0)
	last_cut.cancel_when = [MDSMoveCondition.make(MDSMoveCondition.Kind.PLAYER_BEHIND)]
	var triple := MDSMoveSequence.of([cut, cut, last_cut], "triple_cut")
	var leap := MDSMoveLeap.of(MDSMove.Anchor.PLAYER, 300.0, MDSMoveLeap.EndAt.APEX, 0.18)
	var spin := MDSMoveStrike.of(0.08, Vector2(170, 170), Vector2.ZERO, 1, 0.08)
	spin.face_player = true
	spin.windup_tint = Color(0, 0, 0, 0)
	var diagonal := MDSMoveDash.of(MDSMoveDash.Aim.AT_PLAYER, 1000.0, 0.5, 0.1, Vector2(90, 70), 2)
	diagonal.keep_gravity = false
	diagonal.skid = 0.15
	var balestra := MDSMoveSequence.of([leap, spin, diagonal, MDSMoveWait.of(0.35)], "balestra")
	var flurry := MDSMoveStrike.of(0.04, Vector2(150, 90), Vector2(60, 0), 2, 0.3, 500.0)
	flurry.windup_tint = Color(0, 0, 0, 0)
	var parry := MDSMoveGuard.of(0.65, flurry)
	var retreat := MDSMoveDash.of(MDSMoveDash.Aim.AWAY_FROM_PLAYER, 640.0, 0.24, 0.0)
	var advance := MDSMoveDash.of(MDSMoveDash.Aim.TOWARD_PLAYER, 360.0, 0.14, 0.03)
	var whirl_zone := MDSMoveZones.of(MDSMoveZones.Place.AT_PLAYER, 1, Vector2(190, 190), 0.75, 0.55, MDSCombatZone.Shape.CIRCLE, 2)
	whirl_zone.color = Color(1, 1, 1)
	var moulinet := MDSMoveSequence.of([whirl_zone, MDSMoveWait.of(0.9), MDSMoveLeap.of(MDSMove.Anchor.PLAYER, 200.0)], "moulinet")
	var phase_one: Array[MDSMove] = [lunge, triple, balestra, _weighted(MDSMoveSequence.of([advance, advance]), 0.6), _weighted(moulinet, 0.5, 8.0)]
	var rest := MDSMoveWait.of(0.28, 0.25)
	var close_guard := MDSMovePick.of([parry, retreat] as Array[MDSMove])
	close_guard.when = [_near(120.0)]
	close_guard.cooldown = 3.0
	var answer := MDSMoveSequence.of([leap, spin, diagonal], "answer")
	answer.when = [MDSMoveCondition.make(MDSMoveCondition.Kind.HIT_WITHIN, 0.05), MDSMoveCondition.make(MDSMoveCondition.Kind.CHANCE, 0.25)]
	answer.cooldown = 4.0
	var reacts: Array[MDSMove] = [close_guard, answer]
	var double_lunge := MDSMoveSequence.of([lunge, MDSMoveDash.of(MDSMoveDash.Aim.TOWARD_PLAYER, 1100.0, 0.2, 0.1, Vector2(110, 50), 2), balestra], "double_lunge")
	var trail := MDSMoveZones.of(MDSMoveZones.Place.AT_SELF, 3, Vector2(150, 150), 0.6, 0.2, MDSCombatZone.Shape.CIRCLE, 2)
	trail.color = Color(1, 1, 1)
	var marked := MDSMoveSequence.of([MDSMoveParallel.of([leap, trail] as Array[MDSMove]), spin, diagonal, MDSMoveWait.of(0.35)], "balestra_trail")
	var phase_two: Array[MDSMove] = [double_lunge, triple, marked, _weighted(moulinet, 0.5, 8.0)]
	var twice := MDSMoveRepeat.of(moulinet, 2)
	var phase_three: Array[MDSMove] = [double_lunge, triple, marked, _weighted(twice, 0.6, 7.0)]
	boss.phases = [
		MDSMovePhase.of(1.0, MDSMoveSequence.of([MDSMovePick.of(phase_one), rest]), 1.0, MDSMoveCue.of(0.4), reacts),
		MDSMovePhase.of(0.67, MDSMoveSequence.of([MDSMovePick.of(phase_two), rest]), 1.1, MDSMoveCue.of(0.6, 3.0), reacts),
		MDSMovePhase.of(0.35, MDSMoveSequence.of([MDSMovePick.of(phase_three), rest]), 1.2, twice, reacts),
	]

static func _possessed_duelist(boss: MDSMoveBoss) -> void:
	boss.look = MDSEnemy.Look.KNIGHT
	boss.body_size = Vector2(44, 84)
	boss.body_color = Color(0.13, 0.11, 0.18)
	boss.stagger_hits = 19
	boss.stagger_time = 2.0
	boss.damage_type = "void"
	var dive := MDSMoveVanish.of(MDSMoveVanish.Mode.VANISH_AND_RETURN, 0.45, MDSMove.Anchor.FLOOR_AT_PLAYER, Vector2(150, 0))
	dive.marker_color = Color(0.5, 0.3, 0.9, 0.7)
	var lash := MDSMoveStrike.of(0.32, Vector2(520, 44), Vector2(280, 0), 2, 0.35)
	var leap := MDSMoveLeap.of(MDSMove.Anchor.SELF, 300.0, MDSMoveLeap.EndAt.APEX, 0.1)
	var aerial_lunge := MDSMoveDash.of(MDSMoveDash.Aim.AT_PLAYER, 1000.0, 0.5, 0.18, Vector2(90, 70), 2)
	aerial_lunge.keep_gravity = false
	aerial_lunge.skid = 0.15
	var shots := MDSMoveShoot.of(MDSMoveShoot.From.RING_AROUND_SELF, MDSMoveShoot.Aim.AT_WHERE_PLAYER_WAS, 3, 520.0, 0.28, 1)
	shots.drop = 180.0
	shots.windup = 0.4
	shots.color = Color(0.55, 0.3, 0.95)
	var blobs := MDSMoveShoot.of(MDSMoveShoot.From.SELF, MDSMoveShoot.Aim.ALL_AROUND, 8, 360.0, 0.0, 1)
	blobs.drop = 420.0
	blobs.windup = 0.45
	blobs.recovery = 0.8
	blobs.color = Color(0.4, 0.2, 0.75)
	var columns := MDSMoveZones.of(MDSMoveZones.Place.FLOOR_RANDOM, 5, Vector2(90, 460), 0.65, 0.35, MDSCombatZone.Shape.BOX, 2)
	columns.interval = 0.22
	columns.color = Color(0.55, 0.3, 0.95)
	var waves := MDSMoveZones.of(MDSMoveZones.Place.FLOOR_EVEN, 6, Vector2(110, 90), 0.55, 0.3, MDSCombatZone.Shape.BOX, 2)
	waves.interval = 0.1
	waves.color = Color(0.45, 0.25, 0.85)
	var parry := MDSMoveGuard.of(0.55, MDSMoveStrike.of(0.05, Vector2(160, 90), Vector2(60, 0), 2, 0.3, 500.0))
	parry.when = [_near(120.0)]
	parry.cooldown = 3.5
	var moulinet_zone := MDSMoveZones.of(MDSMoveZones.Place.AT_PLAYER, 3, Vector2(200, 200), 0.8, 0.5, MDSCombatZone.Shape.CIRCLE, 3)
	moulinet_zone.interval = 0.65
	moulinet_zone.color = Color(1, 1, 1)
	var slam := MDSMoveLeap.of(MDSMove.Anchor.PLAYER, 380.0)
	slam.slam_size = Vector2(320, 50)
	slam.slam_shake = 10.0
	var moulinet := MDSMoveSequence.of([moulinet_zone, MDSMoveWait.of(0.7), slam, MDSMoveWait.of(0.5)], "lost_moulinet")
	var attacks: Array[MDSMove] = [lash, MDSMoveSequence.of([leap, aerial_lunge]), shots, blobs]
	var more: Array[MDSMove] = []
	more.append_array(attacks)
	more.append(columns)
	more.append(waves)
	var most: Array[MDSMove] = []
	most.append_array(more)
	most.append(_weighted(moulinet, 0.5, 8.0))
	var between := MDSMoveSequence.of([dive], "dive")
	var run := func(list: Array[MDSMove]) -> MDSMove:
		return MDSMoveSequence.of([between, MDSMovePick.of(list), MDSMoveWait.of(0.25, 0.2)])
	boss.phases = [
		MDSMovePhase.of(1.0, run.call(attacks), 1.0, MDSMoveCue.of(0.6, 6.0), [parry]),
		MDSMovePhase.of(0.75, run.call(more), 1.1, null, [parry]),
		MDSMovePhase.of(0.5, run.call(most), 1.2, moulinet, [parry]),
		MDSMovePhase.of(0.25, run.call(most), 1.35, MDSMoveCue.of(0.5, 8.0), [parry]),
	]

static func _hanging_matriarch(boss: MDSMoveBoss) -> void:
	boss.uses_gravity = false
	boss.look = MDSEnemy.Look.WORM
	boss.body_size = Vector2(70, 110)
	boss.stagger_hits = 13
	boss.stagger_time = 2.4
	boss.falls_when_staggered = true
	var over := MDSMoveFly.of(MDSMove.Anchor.CEILING_ABOVE_PLAYER, 620.0, Vector2(0, 60), 0.7)
	var swipe := MDSMoveStrike.of(0.26, Vector2(120, 340), Vector2(0, 200), 1, 0.14)
	swipe.reach_floor = true
	var triple: Array[MDSMove] = [over, swipe, over, swipe, over, swipe, MDSMoveWait.of(0.6)]
	var up := MDSMoveFly.of(MDSMove.Anchor.CEILING_ABOVE_SELF, 700.0)
	var walls := MDSMoveZones.of(MDSMoveZones.Place.CEILING_RANDOM, 2, Vector2(50, 520), 0.8, 8.0, MDSCombatZone.Shape.BOX, 1)
	walls.hits_to_break = 3
	walls.span_room = true
	walls.color = Color(0.45, 0.75, 0.35)
	var more_walls := MDSMoveZones.of(MDSMoveZones.Place.CEILING_RANDOM, 3, Vector2(50, 520), 0.8, 8.0, MDSCombatZone.Shape.BOX, 1)
	more_walls.hits_to_break = 3
	more_walls.span_room = true
	more_walls.color = walls.color
	var thicket := MDSMoveZones.of(MDSMoveZones.Place.CEILING_EVEN, 6, Vector2(50, 520), 1.0, 8.0, MDSCombatZone.Shape.BOX, 1)
	thicket.hits_to_break = 3
	thicket.span_room = true
	thicket.color = walls.color
	var thicket_once := MDSMoveSequence.of([up, thicket, MDSMoveCue.of(0.0, 0.0, &"thicket_done"), MDSMoveWait.of(1.2)], "thicket")
	thicket_once.when = [_health(0.25), MDSMoveCondition.make(MDSMoveCondition.Kind.FLAG, 0.0, true, &"thicket_done")]
	thicket_once.weight = 100.0
	var adds := MDSMoveSummon.of(MDSFlyer, 1, MDSMove.Anchor.CEILING_ABOVE_PLAYER)
	adds.max_alive = 2
	var summon := MDSMoveSequence.of([MDSMoveFly.of(MDSMove.Anchor.ARENA_NEAR_SIDE, 620.0, Vector2(0, -200)), adds, MDSMoveWait.of(0.9)], "summon")
	var phase_one: Array[MDSMove] = [MDSMoveSequence.of(triple, "triple_swipe"), MDSMoveSequence.of([up, walls, MDSMoveWait.of(0.8)], "walls")]
	var phase_two: Array[MDSMove] = [MDSMoveSequence.of(triple, "triple_swipe"), MDSMoveSequence.of([up, more_walls, MDSMoveWait.of(0.8)], "walls"), summon, thicket_once]
	var call_adds := MDSMoveSummon.of(MDSFlyer, 2, MDSMove.Anchor.CEILING_ABOVE_PLAYER)
	call_adds.wait_for_them = true
	call_adds.wait_seconds = 6.0
	var entrance := MDSMoveSequence.of([up, call_adds], "calls_out")
	boss.phases = [
		MDSMovePhase.of(1.0, MDSMovePick.of(phase_one), 1.0, MDSMoveCue.of(0.5, 4.0)),
		MDSMovePhase.of(0.5, MDSMovePick.of(phase_two), 1.1, entrance),
	]
