class_name MDSMoveContext
extends RefCounted
## What one enemy knows while it runs its moves: each move's memory and cooldown, the fight's flags,
## its last hit, what it has summoned, its hitbox and whether it is hidden. Moves are shared, so all
## of that lives here. It also applies the frame's movement: moves say what they want and it moves
## the body once ([method claim]).

const HITBOX_NAME := "MoveHitbox"

var enemy: MDSEnemy
var rng := RandomNumberGenerator.new()
var flags: Dictionary = {}
## Running moves that a reaction may not cut short.
var locks := 0
var hidden := false
var hitbox: MDSHitbox
## How much faster it is (its phase's).
var speed_scale := 1.0
## Its fight, in world pixels. Empty: its [MDSBossArena]'s, else around where it started.
var arena := Rect2()
## Goes up each time what it left is cleared: a shot still to come is called off.
var clears := 0

var _memory: Dictionary = {}
var _keeps: Dictionary = {}
var _cool: Dictionary = {}
var _claimed := false
var _no_gravity := false
var _last_hit := -INF
var _clock := 0.0
var _spawned: Array = []
var _mask_before := 0

func _init(p_enemy: MDSEnemy) -> void:
	enemy = p_enemy
	rng.seed = hash(String(p_enemy.name)) ^ int(p_enemy.global_position.x * 13.0)
	p_enemy.hurt.connect(func(_i: MDSDamageInfo) -> void: _last_hit = _clock)

## What this enemy keeps about [param move] for this run of it.
func memory(move: MDSMove) -> Dictionary:
	if not _memory.has(move):
		_memory[move] = {}
	return _memory[move]

## What it keeps about [param move] between runs ([method MDSMove.begin] clears the other).
func keeps(move: MDSMove) -> Dictionary:
	if not _keeps.has(move):
		_keeps[move] = {}
	return _keeps[move]

func speed() -> float:
	return maxf(0.01, speed_scale)

func cooling(move: MDSMove) -> bool:
	return _cool.has(move) and _cool[move] > _clock

func cool(move: MDSMove, seconds: float) -> void:
	_cool[move] = _clock + seconds

func phase() -> int:
	return (enemy as MDSBoss).phase_index if enemy is MDSBoss else 0

## Seconds since it was last hit.
func since_hit() -> float:
	return _clock - _last_hit

# --- The frame ------------------------------------------------------------------------------------

## A move sets the body's velocity this frame (without one, it slows to a stop).
func claim(no_gravity := false) -> void:
	_claimed = true
	_no_gravity = _no_gravity or no_gravity

## Runs [param move] one frame and moves the body.
func step(move: MDSMove, delta: float) -> MDSMove.Status:
	_clock += delta
	_claimed = false
	_no_gravity = false
	var status := move.tick(self, delta)
	if not _claimed:
		enemy.halt(delta)
		if not enemy.uses_gravity:
			enemy.velocity.y = move_toward(enemy.velocity.y, 0.0, 1800.0 * delta)
	if hidden:
		enemy.velocity = Vector2.ZERO
	elif not _no_gravity:
		enemy.fall(delta)
	enemy.move()
	return status

## The fight was cut short (a stagger, death): everything it had on goes off.
func interrupted() -> void:
	locks = 0
	disarm()
	show_body()

# --- Where things are -----------------------------------------------------------------------------

func arena_rect() -> Rect2:
	if arena.has_area():
		return arena
	var boss := enemy as MDSBoss
	if boss and boss.arena is MDSBossArena:
		var a := boss.arena as MDSBossArena
		return Rect2(a.global_position - a.size * 0.5, a.size)
	return Rect2(enemy.home - Vector2(640, 400), Vector2(1280, 800))

func player_position() -> Vector2:
	var p := enemy.get_player()
	return p.global_position if p else enemy.global_position + Vector2(enemy.facing * 200.0, 0)

## The first solid ground under [param at] (else the arena's bottom).
func floor_at(at: Vector2) -> Vector2:
	var hit := _ray(at, Vector2(at.x, arena_rect().end.y + 400.0))
	return hit if hit != Vector2.INF else Vector2(at.x, arena_rect().end.y)

## The first solid ground over [param at] (else the arena's top).
func ceiling_at(at: Vector2) -> Vector2:
	var hit := _ray(at, Vector2(at.x, arena_rect().position.y - 400.0))
	return hit if hit != Vector2.INF else Vector2(at.x, arena_rect().position.y)

func _ray(from: Vector2, to: Vector2) -> Vector2:
	if not enemy.is_inside_tree():
		return Vector2.INF
	var q := PhysicsRayQueryParameters2D.create(from, to, MDSGameplaySetup.bit("world"), [enemy.get_rid()])
	var hit := enemy.get_world_2d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector2.INF

## Where [param anchor] is now, in world pixels.
func point(anchor: MDSMove.Anchor, offset := Vector2.ZERO) -> Vector2:
	var pos := enemy.global_position
	var player := player_position()
	var r := arena_rect()
	var side := float(enemy.player_side())
	var half := enemy.body_size * 0.5
	var at := pos
	match anchor:
		MDSMove.Anchor.PLAYER:
			at = player
		MDSMove.Anchor.ABOVE_PLAYER:
			at = player + Vector2(0, -220)
		MDSMove.Anchor.BEHIND_PLAYER:
			at = player + Vector2(side * 90.0, 0)
		MDSMove.Anchor.FRONT_OF_PLAYER:
			at = player - Vector2(side * 110.0, 0)
		MDSMove.Anchor.HOME:
			at = enemy.home
		MDSMove.Anchor.ARENA_CENTER:
			at = r.get_center()
		MDSMove.Anchor.ARENA_LEFT:
			at = Vector2(r.position.x + half.x + 24.0, r.get_center().y)
		MDSMove.Anchor.ARENA_RIGHT:
			at = Vector2(r.end.x - half.x - 24.0, r.get_center().y)
		MDSMove.Anchor.ARENA_FAR_SIDE:
			at = Vector2(r.position.x + half.x + 24.0 if player.x > r.get_center().x else r.end.x - half.x - 24.0, r.get_center().y)
		MDSMove.Anchor.ARENA_NEAR_SIDE:
			at = Vector2(r.position.x + half.x + 24.0 if player.x <= r.get_center().x else r.end.x - half.x - 24.0, r.get_center().y)
		MDSMove.Anchor.CEILING_ABOVE_PLAYER:
			at = ceiling_at(Vector2(player.x, minf(player.y, pos.y))) + Vector2(0, half.y + 4.0)
		MDSMove.Anchor.CEILING_ABOVE_SELF:
			at = ceiling_at(pos) + Vector2(0, half.y + 4.0)
		MDSMove.Anchor.FLOOR_AT_PLAYER:
			at = floor_at(player) - Vector2(0, half.y + 2.0)
		MDSMove.Anchor.FLOOR_AT_SELF:
			at = floor_at(pos) - Vector2(0, half.y + 2.0)
		MDSMove.Anchor.FLOOR_AT_CENTER:
			at = floor_at(r.get_center()) - Vector2(0, half.y + 2.0)
	return at + offset

# --- Its body -------------------------------------------------------------------------------------

func play(animation_name: StringName) -> void:
	if animation_name == &"":
		return
	var anim := enemy.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation(animation_name):
		anim.play(animation_name)

## Its hit is on: [param size] at [param offset] in front of it.
func arm(attack: MDSAttackData, size: Vector2, offset := Vector2.ZERO) -> void:
	if not is_instance_valid(hitbox):
		hitbox = enemy.get_node_or_null(HITBOX_NAME) as MDSHitbox
	if not hitbox:
		hitbox = MDSHitbox.make(MDSHitbox.Team.ENEMY, size, attack)
		hitbox.name = HITBOX_NAME
		enemy.add_child(hitbox)
	hitbox.attack = attack
	hitbox.get_rect_shape().size = size
	hitbox.position = Vector2(offset.x * enemy.facing, offset.y)
	hitbox.reset_hits()
	hitbox.active = true
	hitbox.set_deferred(&"monitoring", true)

func disarm() -> void:
	if is_instance_valid(hitbox):
		hitbox.active = false
		hitbox.set_deferred(&"monitoring", false)

## It is gone from the fight: under the floor, in the void. It can't be hit and doesn't hit.
func hide_body() -> void:
	if hidden:
		return
	hidden = true
	enemy.velocity = Vector2.ZERO
	enemy.modulate.a = 0.0
	enemy.hurtbox.enabled = false
	enemy.contact.active = false
	_mask_before = enemy.collision_mask
	enemy.collision_mask = 0

func show_body() -> void:
	if not hidden:
		return
	hidden = false
	enemy.modulate.a = 1.0
	enemy.hurtbox.enabled = true
	enemy.contact.active = true
	enemy.collision_mask = _mask_before

# --- What it leaves behind ------------------------------------------------------------------------

## Keeps track of [param node], which it left in the room (see [method clear_spawned]).
func track(node: Node) -> void:
	_spawned.append(node)

## What it leaves in the room goes under its parent.
func spawn_parent() -> Node:
	return enemy.get_parent()

## How many enemies it summoned are alive.
func summons_alive() -> int:
	var n := 0
	for s in _spawned:
		if is_instance_valid(s) and s is MDSEnemy and not (s as MDSEnemy).dying:
			n += 1
	return n

## Removes what it left that goes when it is staggered or dies. A partner stays.
func clear_spawned() -> void:
	clears += 1
	# What its bombs left when they went off.
	if enemy.get_parent():
		for c in enemy.get_parent().get_children():
			if c is MDSCombatZone and (c as MDSCombatZone).source == enemy and (c as MDSCombatZone).clear_on_stagger:
				c.queue_free()
	for s in _spawned:
		if not is_instance_valid(s):
			continue
		if s is MDSEnemy:
			var e := s as MDSEnemy
			if not e.get_meta(&"mds_stays", false) and not e.dying and e.health:
				e.health.take_damage(float(e.health.current) * 10.0)
		elif s is MDSCombatZone:
			if (s as MDSCombatZone).clear_on_stagger:
				s.queue_free()
		elif s is MDSBossShot:
			s.queue_free()
	_spawned = _spawned.filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Node).is_queued_for_deletion())
