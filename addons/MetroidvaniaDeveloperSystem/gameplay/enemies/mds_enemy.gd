@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_enemy.svg")
class_name MDSEnemy
extends CharacterBody2D
## An enemy: a CharacterBody2D in the [code]enemy[/code] group (the scanner counts it, dark rooms
## light it, the camera director watches it) on the [code]enemy[/code] layer, running on the same
## state machine as the player. Its parts are made when it starts if missing: an [MDSHealth] (from
## [member data]'s stats), an [MDSHurtbox], a contact [MDSHitbox] (touching it hurts), an
## [MDSKnockback], an [MDSPlayerDetector] (sight with a line of sight through terrain) and an
## [MDSStateMachine] with the states of its kind ([method _make_states]).
##
## When it dies it drops its loot (currency and [member MDSEnemyData.drops], never persistent),
## counts for the bestiary and XP, and by [member respawn]: NEVER is recorded
## ([method MDSWorldGame.mark_defeated]: gone for good, like a boss), ON_REST comes back after the
## player rests on a bench, ON_ROOM_LOAD comes back whenever its room loads.
##
## The templates are [MDSWalker], [MDSFlyer], [MDSTurret], [MDSCharger] and [MDSAmbusher]; bosses
## are [MDSBoss].

signal died
signal hurt(info: MDSDamageInfo)

enum Respawn { ON_ROOM_LOAD, ON_REST, NEVER }
enum Look { CRAWLER, BAT, TURRET, BEETLE, WORM, KNIGHT }

@export var data: MDSEnemyData
@export var respawn: Respawn = Respawn.ON_REST
## 1 facing right, -1 left.
@export var facing := -1:
	set(v):
		facing = 1 if v >= 0 else -1
		queue_redraw()
@export var body_size := Vector2(40, 36):
	set(v):
		body_size = v
		queue_redraw()
@export var gravity := 1400.0
@export var uses_gravity := true
@export var max_fall_speed := 900.0
## Damage of touching it (-1: its stats' contact_damage).
@export var contact_damage := -1
## Seconds it lingers after dying.
@export var dead_time := 0.6
@export var look: Look = Look.CRAWLER:
	set(v):
		look = v
		queue_redraw()
@export var body_color := Color(0.72, 0.36, 0.3):
	set(v):
		body_color = v
		queue_redraw()
## The state it goes back to after being hurt (empty: the first state).
@export var resume_state: StringName = &""

var machine: MDSStateMachine
var health: MDSHealth
var hurtbox: MDSHurtbox
var contact: MDSHitbox
var knockback: MDSKnockback
var detector: MDSPlayerDetector
var game: MDSWorldGame
var gameplay: MDSGameplay
## Where it started (flyers come back to it).
var home := Vector2.ZERO
var stunned_left := 0.0
var dying := false
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	add_to_group(&"enemy")

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_build_missing()
	collision_layer = MDSGameplaySetup.bit("enemy")
	collision_mask = MDSGameplaySetup.bit("world")
	game = MDSWorldGame.instance if MDSWorldGame.instance and MDSWorldGame.instance.is_ancestor_of(self) else null
	gameplay = MDSGameplay.find(game) if game else null
	if game and gameplay and gameplay.rest_defeated.has(game.object_id(self)):
		queue_free()
		return
	home = global_position
	_rng.seed = hash(name) ^ int(global_position.x * 13.0)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

## Builds the parts it lacks (see the class description). With [param with_states] off, its state
## machine is left empty (the states are made when it starts).
func _build_missing(with_states := true) -> void:
	var shape := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if not shape:
		shape = CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var r := RectangleShape2D.new()
		r.size = body_size
		shape.shape = r
		add_child(shape)
	var stats := get_stats()
	health = get_node_or_null(^"Health") as MDSHealth
	if not health:
		health = MDSHealth.new()
		health.name = "Health"
		health.iframe_time = 0.12
		health.stats = stats
		add_child(health)
	elif not health.stats:
		health.stats = stats
	hurtbox = get_node_or_null(^"Hurtbox") as MDSHurtbox
	if not hurtbox:
		hurtbox = MDSHurtbox.make(MDSHurtbox.Team.ENEMY, body_size + Vector2(6, 6))
		hurtbox.name = "Hurtbox"
		add_child(hurtbox)
	contact = get_node_or_null(^"Contact") as MDSHitbox
	if not contact:
		var touch := MDSAttackData.make("touch", contact_damage if contact_damage >= 0 else stats.contact_damage, [])
		touch.knockback = Vector2(280, -260)
		touch.hitstop_ms = 40
		contact = MDSHitbox.make(MDSHitbox.Team.ENEMY, body_size * 0.85, touch)
		contact.name = "Contact"
		contact.one_hit_per_target = false
		add_child(contact)
	knockback = get_node_or_null(^"Knockback") as MDSKnockback
	if not knockback:
		knockback = MDSKnockback.new()
		knockback.name = "Knockback"
		knockback.hitstun_time = 0.25
		add_child(knockback)
	detector = get_node_or_null(^"PlayerDetector") as MDSPlayerDetector
	if not detector:
		detector = MDSPlayerDetector.new()
		detector.name = "PlayerDetector"
		add_child(detector)
	machine = get_node_or_null(^"StateMachine") as MDSStateMachine
	if not machine:
		machine = MDSStateMachine.new()
		machine.name = "StateMachine"
		add_child(machine)
	if with_states and machine.get_child_count() == 0:
		var states := _make_states()
		for n in ["Hurt", "Dead"]:
			if not states.any(func(s: Node) -> bool: return String(s.name) == n):
				var s: Node = Hurt.new() if n == "Hurt" else Dead.new()
				s.name = n
				states.append(s)
		for s in states:
			machine.add_child(s)
		if machine.initial_state == &"" and not states.is_empty():
			machine.initial_state = StringName(states[0].name)
		if resume_state == &"":
			resume_state = machine.initial_state
		# Added after the machine was ready: it learns them now.
		if machine.is_node_ready():
			for s in states:
				machine.register(s)
			if not machine.current:
				machine.force(machine.initial_state)

## The states of its kind, the first one the starting state (templates override it).
func _make_states() -> Array[Node]:
	var s := Idle.new()
	s.name = "Idle"
	return [s]

## Its stats: [member data]'s, else 3 health.
func get_stats() -> MDSCombatStats:
	if data and data.stats:
		return data.stats
	return MDSCombatStats.make(3)

func get_health_component() -> MDSHealth:
	return health

# --- Shared moves ----------------------------------------------------------------------------------

func fall(delta: float) -> void:
	if uses_gravity:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

## Walks toward its facing at [param speed].
func walk(speed: float, delta: float, accel := 1400.0) -> void:
	velocity.x = move_toward(velocity.x, facing * speed, accel * delta)

## Slows to a stop.
func halt(delta: float, decel := 1800.0) -> void:
	velocity.x = move_toward(velocity.x, 0.0, decel * delta)

func move() -> void:
	move_and_slide()

func turn() -> void:
	facing = -facing

## Whether a wall is just ahead.
func at_wall() -> bool:
	if is_on_wall() and signf(get_wall_normal().x) == -facing:
		return true
	return _ray(Vector2.ZERO, Vector2(facing * (body_size.x * 0.5 + 6.0), 0))

## Whether the floor ends just ahead (it would walk off a ledge).
func at_ledge() -> bool:
	if not is_on_floor():
		return false
	return not _ray(Vector2(facing * (body_size.x * 0.5 + 4.0), 0), Vector2(facing * (body_size.x * 0.5 + 4.0), body_size.y * 0.5 + 24.0))

func _ray(from: Vector2, to: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters2D.create(global_position + from, global_position + to, MDSGameplaySetup.bit("world"), [get_rid()])
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()

## The player (the game's), or null.
func get_player() -> Node2D:
	if game and is_instance_valid(game.player):
		return game.player
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null

func sees_player() -> bool:
	return detector != null and detector.sees_player()

## -1 or 1: which side the player is on.
func player_side() -> int:
	var p := get_player()
	if not p:
		return facing
	return 1 if p.global_position.x >= global_position.x else -1

func face_player() -> void:
	facing = player_side()

func distance_to_player() -> float:
	var p := get_player()
	return p.global_position.distance_to(global_position) if p else INF

## Stunned for [param seconds] (a parry, a charger hitting a wall): no attacks, no moves.
func stun(seconds: float) -> void:
	stunned_left = maxf(stunned_left, seconds)
	if machine and machine.has_state(&"Stunned"):
		machine.force(&"Stunned")
	elif machine and machine.has_state(&"Hurt"):
		machine.force(&"Hurt")

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	stunned_left = maxf(0.0, stunned_left - delta)

# --- Hits and death -------------------------------------------------------------------------------

func _on_damaged(info: MDSDamageInfo) -> void:
	hurt.emit(info)
	if dying or health.is_dead():
		return
	if machine.has_state(&"Hurt") and knockback.is_stunned():
		machine.force(&"Hurt")

func _on_died() -> void:
	if dying:
		return
	dying = true
	if machine.has_state(&"Dead"):
		machine.force(&"Dead")
	drop_loot()
	if gameplay:
		gameplay.record_defeat(self)
	if game:
		match respawn:
			Respawn.NEVER:
				game.mark_defeated(self)
			Respawn.ON_REST:
				if gameplay:
					gameplay.defeat_until_rest(game.object_id(self))
	died.emit()

## Drops its currency and loot where it is (never persistent).
func drop_loot() -> void:
	var parent := get_parent()
	if not parent:
		return
	if data:
		var coins := _rng.randi_range(mini(data.currency_drop.x, data.currency_drop.y), maxi(data.currency_drop.x, data.currency_drop.y))
		while coins > 0:
			var c := MDSCurrencyPickup.new()
			c.amount = mini(coins, 5)
			coins -= c.amount
			parent.add_child.call_deferred(c)
			c.position = position + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-24, -4))
		if data.drops:
			for d in data.drops.roll(_rng):
				var item: MDSItemData = d[0] if d[0] is MDSItemData else (gameplay.get_item_data(str(d[0])) if gameplay else null)
				if not item:
					continue
				var p := MDSPickup.new()
				p.item = item
				p.amount = int(d[1])
				p.persistent = false
				parent.add_child.call_deferred(p)
				p.position = position + Vector2(_rng.randf_range(-16, 16), -16)

# --- Look -----------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	var w := body_size.x
	var h := body_size.y
	var c := body_color
	var f := float(facing)
	var eye := Color(1.0, 0.95, 0.7)
	match look:
		Look.BAT:
			var flap := sin(Time.get_ticks_msec() * 0.02) * h * 0.3
			draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.9, -flap), Vector2(0, -h * 0.2), Vector2(w * 0.9, -flap), Vector2(0, h * 0.3)]), c.darkened(0.2))
			draw_circle(Vector2.ZERO, h * 0.35, c)
			draw_circle(Vector2(f * h * 0.15, -h * 0.05), 3.0, eye)
		Look.TURRET:
			draw_rect(Rect2(-w * 0.5, -h * 0.2, w, h * 0.7), c.darkened(0.3))
			draw_circle(Vector2(0, -h * 0.1), w * 0.38, c)
			draw_line(Vector2(0, -h * 0.1), Vector2(f * w * 0.6, -h * 0.1), c.darkened(0.5), 6.0)
			draw_circle(Vector2(0, -h * 0.1), w * 0.14, eye)
		Look.WORM:
			for i in 4:
				draw_circle(Vector2(-f * i * w * 0.18, h * 0.5 - i * h * 0.22), w * (0.32 - i * 0.04), c.darkened(i * 0.08))
			draw_circle(Vector2(f * w * 0.08, -h * 0.1), 3.0, eye)
		Look.KNIGHT:
			draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.45, h * 0.5), Vector2(w * 0.45, h * 0.5), Vector2(w * 0.35, -h * 0.2), Vector2(-w * 0.35, -h * 0.2)]), c)
			draw_circle(Vector2(0, -h * 0.32), w * 0.28, c.lightened(0.15))
			draw_line(Vector2(-w * 0.2, -h * 0.5), Vector2(-w * 0.32, -h * 0.75), c.lightened(0.3), 4.0)
			draw_line(Vector2(w * 0.2, -h * 0.5), Vector2(w * 0.32, -h * 0.75), c.lightened(0.3), 4.0)
			draw_circle(Vector2(f * w * 0.1, -h * 0.32), 4.0, eye)
			draw_line(Vector2(f * w * 0.4, 0), Vector2(f * w * 0.95, -h * 0.35), Color(0.8, 0.82, 0.86), 5.0)
		_:
			var shell := PackedVector2Array()
			for i in 13:
				var t := PI * i / 12.0
				shell.append(Vector2(cos(t) * w * 0.5, h * 0.5 - sin(t) * h * (0.95 if look == Look.BEETLE else 0.8)))
			draw_colored_polygon(shell, c)
			draw_line(Vector2(-w * 0.45, h * 0.5), Vector2(w * 0.45, h * 0.5), c.darkened(0.4), 3.0)
			if look == Look.BEETLE:
				draw_line(Vector2(f * w * 0.3, h * 0.1), Vector2(f * w * 0.75, -h * 0.25), c.lightened(0.25), 4.0)
			draw_circle(Vector2(f * w * 0.25, h * 0.1), 3.0, eye)
	if stunned_left > 0.0:
		draw_arc(Vector2(0, -h * 0.7), 10.0, 0, TAU, 12, Color(1, 1, 0.5, 0.7), 2.0)

# --- Shared states ------------------------------------------------------------------------------

## Standing (the plain enemy's only state): falls, stops.
class Idle extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()

## Knocked back by a hit: no control until the hit-stun ends, then back to its resume state.
class Hurt extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.move()
		if elapsed() > 0.08 and not enemy.knockback.is_stunned() and enemy.stunned_left <= 0.0:
			machine.force(enemy.resume_state)

## Dying: harmless, it falls, fades and is gone.
class Dead extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		enemy.contact.active = false
		enemy.contact.set_deferred(&"monitoring", false)
		enemy.hurtbox.enabled = false
		enemy.set_deferred(&"collision_layer", 0)
		var tw := enemy.create_tween()
		tw.tween_property(enemy, "modulate:a", 0.0, enemy.dead_time)
		tw.tween_callback(enemy.queue_free)

	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta, 600.0)
		enemy.move()
