@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_boss.svg")
class_name MDSBoss
extends MDSEnemy
## A boss: an [MDSEnemy] in the [code]boss[/code] group, recorded by [member boss_name] when
## defeated ([member respawn] is always NEVER, and [code]mds_boss_name[/code] metadata names it, so
## the scanner, [method MDSWorldGame.is_boss_defeated] and [code]boss:<name>[/code] objectives
## know it). Defeated, it is gone when its room loads again.
##
## It waits (Dormant) until its [MDSBossArena] starts the fight ([method start_fight]), then rests
## a moment between attacks, each picked from its current phase's
## [member MDSBossPhase.attack_states]: Swipe (walks up and strikes), Charge (rushes across), Slam
## (leaps at the player and crashes down with a shockwave), Volley (a fan of shots). At each
## phase's [member MDSBossPhase.health_threshold] it staggers (Stagger, its enter animation, a
## camera punch-in) and fights on with that phase's attacks at its speed. Without phases it has two:
## Swipe and Charge, then from half its health Slam, Volley and Charge, faster.
##
## With an [MDSDialogueBox] in the game it speaks: [member intro_dialogue] as the fight starts and
## [member defeat_dialogue] as it falls, named [member boss_name] (the game waits meanwhile).

signal fight_started
signal phase_changed(index: int)

@export var boss_name := "":
	set(v):
		boss_name = v
		_update_meta()
@export var phases: Array[MDSBossPhase] = []
## Its arena (which starts the fight). Empty: the fight starts when the player comes near.
@export var arena: Node
## Said when the fight starts (with an [MDSDialogueBox] in the game).
@export var intro_dialogue: MDSDialogueData
## Said when it falls, before it fades away.
@export var defeat_dialogue: MDSDialogueData
## Its fight's music. Empty: the area's boss_music.
@export var music: AudioStream
@export var walk_speed := 110.0
@export var charge_speed := 520.0
@export var leap_speed := 640.0
@export var volley_count := 5
@export var shot_speed := 360.0
@export var attack_damage := 2
## Seconds of rest between attacks (shorter in faster phases).
@export var rest_time := 0.9
## Starts the fight on its own when the player comes this close, with no arena (0: never).
@export var wake_range := 0.0

var phase_index := 0
var fighting := false
var attack_box: MDSHitbox

func _init() -> void:
	super()
	add_to_group(&"boss")
	respawn = Respawn.NEVER
	look = Look.KNIGHT
	body_size = Vector2(56, 96)
	body_color = Color(0.32, 0.34, 0.42)
	gravity = 1800.0

func _update_meta() -> void:
	if boss_name.strip_edges().is_empty():
		if has_meta(&"mds_boss_name"):
			remove_meta(&"mds_boss_name")
	else:
		set_meta(&"mds_boss_name", boss_name)

func _ready() -> void:
	_update_meta()
	if Engine.is_editor_hint():
		super()
		return
	respawn = Respawn.NEVER
	if not data:
		data = MDSEnemyData.new()
		data.id = MDSGameplay.normalize_id(boss_name) if not boss_name.is_empty() else "boss"
		data.display_name = boss_name
		data.stats = MDSCombatStats.make(30, 0, 2)
		data.currency_drop = Vector2i(40, 60)
	super()
	if is_queued_for_deletion():
		return
	if game and not boss_name.is_empty() and game.is_boss_defeated(boss_name):
		queue_free()
		return
	if phases.is_empty():
		phases = [MDSBossPhase.make(1.0, ["Swipe", "Charge"]), MDSBossPhase.make(0.5, ["Slam", "Volley", "Charge"], 1.3)]
	phases.sort_custom(func(a: MDSBossPhase, b: MDSBossPhase) -> bool: return a.health_threshold > b.health_threshold)
	knockback.resistance = 1.0
	health.iframe_time = 0.08
	health.health_changed.connect(_on_health_changed)
	var swipe := MDSAttackData.make("boss_swipe", attack_damage, [])
	swipe.knockback = Vector2(360, -280)
	attack_box = MDSHitbox.make(MDSHitbox.Team.ENEMY, Vector2(90, 70), swipe)
	attack_box.name = "AttackBox"
	attack_box.active = false
	attack_box.monitoring = false
	add_child(attack_box)

func _make_states() -> Array[Node]:
	return MDSWalker._named([Dormant.new(), BossIdle.new(), Swipe.new(), BossCharge.new(), Slam.new(), Volley.new(), Stagger.new(), BossDead.new()],
		["Dormant", "Idle", "Swipe", "Charge", "Slam", "Volley", "Stagger", "Dead"])

## The fight begins: it stops waiting and attacks.
func start_fight() -> void:
	if fighting or dying:
		return
	fighting = true
	fight_started.emit()
	say(intro_dialogue)
	machine.force(&"Idle")

## The name it speaks with in conversations ([member boss_name]).
func get_dialogue_name() -> String:
	return boss_name

## Starts [param d] in the game's dialogue box, said by it. Returns whether a box shows it.
func say(d: MDSDialogueData) -> bool:
	if not d or not is_inside_tree():
		return false
	for box in get_tree().get_nodes_in_group(&"mds_dialogue_box"):
		if box.has_method(&"start"):
			box.call(&"start", d, self)
			return true
	return false

func _on_died() -> void:
	var was_dying := dying
	super()
	if not was_dying:
		say(defeat_dialogue)

func get_phase() -> MDSBossPhase:
	return phases[clampi(phase_index, 0, phases.size() - 1)] if not phases.is_empty() else null

## How much faster it is in this phase.
func speed() -> float:
	var p := get_phase()
	return p.speed_multiplier if p else 1.0

## Its next attack: one of the phase's attack states (it has).
func next_attack() -> StringName:
	var p := get_phase()
	var options: Array[StringName] = []
	if p:
		for s in p.attack_states:
			if machine.has_state(StringName(s)):
				options.append(StringName(s))
	if options.is_empty():
		return &"Swipe"
	return options[_rng.randi() % options.size()]

func _physics_process(delta: float) -> void:
	super(delta)
	if not Engine.is_editor_hint() and not fighting and wake_range > 0.0 and not dying and distance_to_player() < wake_range:
		start_fight()

## Bosses don't flinch.
func _on_damaged(info: MDSDamageInfo) -> void:
	hurt.emit(info)

func _on_health_changed(current: int, maximum: int) -> void:
	if dying or current <= 0 or phases.is_empty():
		return
	var share := float(current) / float(maxi(1, maximum))
	var idx := 0
	for i in phases.size():
		if share <= phases[i].health_threshold + 0.0001:
			idx = i
	if idx > phase_index:
		phase_index = idx
		phase_changed.emit(idx)
		machine.force(&"Stagger")
		var d := _director()
		if d:
			d.punch_in(1.12, 0.5, self)

func _director() -> MDSCameraDirector:
	return game.room_camera.get_director() if game and game.room_camera else null

## The strike hitbox in front, on for [param seconds].
func strike(seconds: float, size := Vector2(90, 70)) -> void:
	attack_box.position = Vector2(facing * (body_size.x * 0.5 + size.x * 0.4), 0)
	attack_box.get_rect_shape().size = size
	attack_box.reset_hits()
	attack_box.active = true
	attack_box.monitoring = true
	await get_tree().create_timer(seconds, false, true).timeout
	if is_instance_valid(attack_box):
		attack_box.active = false
		attack_box.set_deferred(&"monitoring", false)

## Waiting for the fight.
class Dormant extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()

## Between attacks: facing the player, resting.
class BossIdle extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		var b := enemy as MDSBoss
		b.face_player()
		b.fall(delta)
		b.halt(delta)
		b.move()
		if b.fighting and elapsed() >= b.rest_time / b.speed():
			go(b.next_attack())

## Walks up to the player (2 s at most) and strikes in front.
class Swipe extends MDSEnemyState:
	var _struck_at := -1.0
	func enter(_previous: StringName, _data: Dictionary) -> void:
		_struck_at = -1.0
	func physics_update(delta: float) -> void:
		var b := enemy as MDSBoss
		b.fall(delta)
		if _struck_at < 0.0:
			if b.distance_to_player() > 110.0 and elapsed() < 2.0:
				b.face_player()
				b.walk(b.walk_speed * b.speed(), delta)
			else:
				b.halt(delta)
				_struck_at = elapsed()
				b.strike(0.2)
		else:
			b.halt(delta)
		b.move()
		if _struck_at >= 0.0 and elapsed() > _struck_at + 0.6 / b.speed():
			go(&"Idle")

class BossCharge extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		enemy.face_player()
	func physics_update(delta: float) -> void:
		var b := enemy as MDSBoss
		b.fall(delta)
		var windup := 0.45 / b.speed()
		if elapsed() < windup:
			b.halt(delta)
		else:
			b.velocity.x = b.facing * b.charge_speed * b.speed()
			if b.at_wall() or elapsed() > windup + 1.4:
				if b.at_wall() and b.game and b.game.room_camera and b.game.room_camera.has_method(&"shake"):
					b.game.room_camera.call(&"shake", 8.0, 0.3)
				b.velocity.x = -b.facing * 120.0
				go(&"Idle")
		b.move()

class Slam extends MDSEnemyState:
	var _left_ground := false
	func enter(_previous: StringName, _data: Dictionary) -> void:
		var b := enemy as MDSBoss
		b.face_player()
		var p := b.get_player()
		var dx := (p.global_position.x - b.global_position.x) if p else b.facing * 200.0
		var air := 2.0 * b.leap_speed / b.gravity
		b.velocity = Vector2(clampf(dx / air, -500.0, 500.0), -b.leap_speed)
		_left_ground = false
	func physics_update(delta: float) -> void:
		var b := enemy as MDSBoss
		b.fall(delta)
		b.move()
		if not b.is_on_floor():
			_left_ground = true
			return
		if _left_ground:
			_left_ground = false
			b.velocity.x = 0.0
			b.strike(0.15, Vector2(260, 40))
			b.attack_box.position = Vector2(0, b.body_size.y * 0.4)
			if b.game and b.game.room_camera and b.game.room_camera.has_method(&"shake"):
				b.game.room_camera.call(&"shake", 10.0, 0.35)
		if elapsed() > 0.3 and b.is_on_floor() and not _left_ground:
			go(&"Idle")

class Volley extends MDSEnemyState:
	var _fired := 0
	func enter(_previous: StringName, _data: Dictionary) -> void:
		_fired = 0
	func physics_update(delta: float) -> void:
		var b := enemy as MDSBoss
		b.fall(delta)
		b.halt(delta)
		b.move()
		var every := 0.18 / b.speed()
		while _fired < b.volley_count and elapsed() >= 0.3 + _fired * every:
			var p := b.get_player()
			var aim := (p.global_position - b.global_position).normalized() if p else Vector2(b.facing, 0)
			var spread := (float(_fired) - (b.volley_count - 1) * 0.5) * 0.18
			var a := MDSAttackData.make("boss_shot", 1, [])
			var shot := MDSProjectile.fire(null, b.get_parent(), b.global_position + Vector2(0, -b.body_size.y * 0.25), aim.rotated(spread), MDSHitbox.Team.ENEMY, a, b)
			if shot:
				shot.velocity = aim.rotated(spread) * b.shot_speed
				shot.color = Color(0.85, 0.5, 1.0)
			_fired += 1
		if _fired >= b.volley_count and elapsed() > 0.3 + b.volley_count * every + 0.4:
			go(&"Idle")

## A phase change: it reels, then fights on.
class Stagger extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		var b := enemy as MDSBoss
		var p := b.get_phase()
		var anim := b.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
		if p and anim and p.enter_animation != &"" and anim.has_animation(p.enter_animation):
			anim.play(p.enter_animation)
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		if elapsed() > 0.8:
			go(&"Idle")

## Defeated: the camera pushes in on it, it falls and fades.
class BossDead extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		var b := enemy as MDSBoss
		b.fighting = false
		b.contact.active = false
		b.contact.set_deferred(&"monitoring", false)
		b.attack_box.active = false
		b.hurtbox.enabled = false
		var d := b._director()
		if d:
			d.punch_in(1.25, 0.9, b)
		if b.gameplay:
			b.gameplay.hitstop(160)
		var tw := b.create_tween()
		tw.tween_interval(0.6)
		tw.tween_property(b, "modulate:a", 0.0, b.dead_time + 0.6)
		tw.tween_callback(b.queue_free)
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta, 400.0)
		enemy.move()
