@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_attack_controller.svg")
class_name MDSAttackController
extends Node2D
## The player's attacks, a child of [MDSPlayer]: they run alongside its movement (it can attack
## while running and jumping), each by its [MDSAttackData] frame data at 60 fps (startup, active,
## recovery) with one [MDSHitbox] placed in front, above or below.
##
## - [code]attack[/code]: the ground combo ([member ground_combo], 3 hits; the next one follows
##   when pressed during the recovery and listed in [member MDSAttackData.cancel_into]), the air
##   combo (2 hits), up with [code]move_up[/code] held, down in the air with [code]move_down[/code]
##   held. A down hit on an enemy, a hazard or a breakable bounces the player up (pogo).
## - Hold [code]attack[/code] for [member charge_time] with the [code]charge_attack[/code] ability:
##   the charged attack on release.
## - [code]special[/code]: the [member spell] (an [MDSProjectile]), costing its mana.
## - With the [code]super_attack[/code] ability every attack also breaks [code]reinforced[/code]
##   breakables; with [code]parry[/code], an attack pressed within [member parry_window] of being
##   hit blocks the hit and stuns the attacker.
## Hits give mana ([member mana_per_hit]), freeze the game a moment (hit-stop) and shake the camera
## a little.

signal attack_started(attack: MDSAttackData)
signal attack_ended(attack: MDSAttackData)
## A hit landed on [param target].
signal hit(target: Node, info: MDSDamageInfo)
signal parried(info: MDSDamageInfo)

enum Phase { NONE, STARTUP, ACTIVE, RECOVERY }

@export var ground_combo: Array[MDSAttackData] = []
@export var air_combo: Array[MDSAttackData] = []
@export var up_attack: MDSAttackData
@export var down_attack: MDSAttackData
@export var charge_attack: MDSAttackData
@export var spell: MDSAttackData
## Upward speed of a pogo bounce.
@export var pogo_velocity := 520.0
@export var mana_per_hit := 3
@export var charge_time := 0.6
@export var parry_window := 0.12
## States the player can't attack in.
@export var blocked_states: PackedStringArray = ["Locked", "Rest", "Dead", "Hurt", "LedgeGrab", "LedgeClimb", "Climb", "Grapple", "Slide", "Dash", "AirDash", "GroundPound", "Swim"]

var current: MDSAttackData
var phase: Phase = Phase.NONE
var hitbox: MDSHitbox
var _time := 0.0
var _combo := 0
var _charge := 0.0
var _charged := false
var _last_attack_press := -10.0
var _clock := 0.0
var _bounced := false ## this swing already bounced the player (pogo)

func _ready() -> void:
	if ground_combo.is_empty():
		ground_combo = [_make("slash_1", 1, ["slash_2"]), _make("slash_2", 1, ["slash_3"]), _make("slash_3", 2, [])]
		ground_combo[2].knockback = Vector2(320, -180)
	if air_combo.is_empty():
		air_combo = [_make("air_1", 1, ["air_2"]), _make("air_2", 1, [])]
	if not up_attack:
		up_attack = _make("up", 1, [])
		up_attack.direction = MDSAttackData.Direction.UP
		up_attack.hitbox_size = Vector2(44, 60)
		up_attack.hitbox_offset = Vector2(0, -50)
	if not down_attack:
		down_attack = _make("down", 1, [])
		down_attack.direction = MDSAttackData.Direction.DOWN
		down_attack.hitbox_size = Vector2(44, 56)
		down_attack.hitbox_offset = Vector2(0, 50)
	if not charge_attack:
		charge_attack = _make("charge", 3, [])
		charge_attack.hitbox_size = Vector2(96, 48)
		charge_attack.hitbox_offset = Vector2(56, 0)
		charge_attack.knockback = Vector2(420, -220)
		charge_attack.hitstop_ms = 110
	hitbox = get_node_or_null(^"AttackHitbox") as MDSHitbox
	if not hitbox:
		hitbox = MDSHitbox.make(MDSHitbox.Team.PLAYER, Vector2(56, 40))
		hitbox.name = "AttackHitbox"
		add_child(hitbox)
	hitbox.active = false
	hitbox.monitoring = false
	hitbox.source = get_parent()
	# It also sees hazards' hitboxes (they have no hurtbox): a down hit on spikes is a pogo.
	hitbox.collision_mask |= MDSGameplaySetup.bit("enemy_hitbox")
	if not hitbox.hit_landed.is_connected(_on_hit):
		hitbox.hit_landed.connect(_on_hit)
	var p := _player()
	if p and p.hurtbox is MDSHurtbox:
		(p.hurtbox as MDSHurtbox).blocker = try_parry

static func _make(id: String, damage: int, cancel: PackedStringArray) -> MDSAttackData:
	var a := MDSAttackData.make(id, damage)
	a.cancel_into = cancel
	return a

func _player() -> MDSPlayer:
	return get_parent() as MDSPlayer

## Whether the player can start an attack now.
func can_attack() -> bool:
	var p := _player()
	return p != null and p.can_take_input() and p.machine.current != null and not blocked_states.has(String(p.machine.get_state()))

func is_attacking() -> bool:
	return phase != Phase.NONE

func _physics_process(delta: float) -> void:
	_clock += delta
	var p := _player()
	if not p:
		return
	if p.held(&"attack"):
		_charge += delta
	if p.pressed("attack"):
		_last_attack_press = _clock
	_advance(delta)
	# Charged attack: released after holding long enough.
	if _charge >= charge_time and p.has_ability("charge_attack") and not p.held(&"attack") and can_attack() and not _charged:
		_charged = true
		_charge = 0.0
		if p.machine.has_state(&"Attack"):
			p.machine.force(&"Attack", {"attack": charge_attack})
		start(charge_attack)
		return
	if not p.held(&"attack"):
		_charge = 0.0
		_charged = false
	if p.pressed("special") and spell and can_attack():
		p.buffer.consume("special")
		cast(spell)
	if not p.pressed("attack") or not can_attack():
		return
	var next := _choose(p)
	if not next:
		return
	if phase == Phase.NONE or (phase == Phase.RECOVERY and current and current.cancel_into.has(next.id)):
		p.buffer.consume("attack")
		start(next)

## The attack the press makes: up, down (in the air), else the next hit of the combo.
func _choose(p: MDSPlayer) -> MDSAttackData:
	if p.input_y() < -0.5 and up_attack:
		return up_attack
	if p.input_y() > 0.5 and not p.is_on_floor() and down_attack:
		return down_attack
	var combo := ground_combo if p.is_on_floor() else air_combo
	if combo.is_empty():
		return null
	if phase == Phase.RECOVERY and current:
		for i in combo.size():
			if current.cancel_into.has(combo[i].id):
				_combo = i
				return combo[i]
	_combo = 0
	return combo[0]

## Starts [param a] now.
func start(a: MDSAttackData) -> void:
	current = a
	phase = Phase.STARTUP
	_time = 0.0
	hitbox.attack = a
	hitbox.reset_hits()
	_bounced = false
	_place_hitbox(a)
	var p := _player()
	if p:
		MDSAttackFX.on_swing(a, p, float(p.facing))
	attack_started.emit(a)

func _advance(delta: float) -> void:
	if phase == Phase.NONE or not current:
		return
	_time += delta
	var p := _player()
	_place_hitbox(current)
	var s := current.startup_time()
	var act := current.active_time()
	if _time < s:
		phase = Phase.STARTUP
	elif _time < s + act:
		if phase != Phase.ACTIVE:
			phase = Phase.ACTIVE
			hitbox.damage_bonus = p.get_damage_bonus() if p else 0
			hitbox.extra_breaks = PackedStringArray(["reinforced"]) if p and p.has_ability("super_attack") else PackedStringArray()
			hitbox.monitoring = true
			hitbox.active = true
		elif _hits_hazard():
			_pogo(p)
	elif _time < current.total_time():
		_hitbox_off()
		phase = Phase.RECOVERY
	else:
		_hitbox_off()
		var done := current
		phase = Phase.NONE
		current = null
		attack_ended.emit(done)

func _hitbox_off() -> void:
	hitbox.active = false
	hitbox.set_deferred(&"monitoring", false)

## Ends any attack (the player was hurt, the room changes).
func cancel() -> void:
	_hitbox_off()
	phase = Phase.NONE
	current = null

func _place_hitbox(a: MDSAttackData) -> void:
	var p := _player()
	var f := p.facing if p else 1
	var r := hitbox.get_rect_shape()
	r.size = a.hitbox_size
	match a.direction:
		MDSAttackData.Direction.FORWARD:
			hitbox.position = Vector2(a.hitbox_offset.x * f, a.hitbox_offset.y)
		_:
			hitbox.position = a.hitbox_offset

## Casts [param a] (a spell): its mana, then its projectile forward.
func cast(a: MDSAttackData) -> bool:
	var p := _player()
	if not p:
		return false
	var kit := p.gameplay
	if a.mana_cost > 0 and kit and not kit.spend_mana(a.mana_cost):
		return false
	var parent: Node = p.get_parent() if p.get_parent() else p
	var dir := Vector2(p.facing, 0)
	MDSProjectile.fire(a.projectile, parent, p.global_position + Vector2(p.facing * 30, -6), dir, MDSHitbox.Team.PLAYER, a, p)
	return true

func _on_hit(target: Node, info: MDSDamageInfo) -> void:
	var p := _player()
	if not p:
		return
	if p.gameplay:
		p.gameplay.set_mana(p.gameplay.mana + mana_per_hit)
		p.gameplay.hitstop(info.hitstop_ms)
	if p.game and p.game.room_camera and p.game.room_camera.has_method(&"shake"):
		p.game.room_camera.call(&"shake", 3.0 if info.amount < 3 else 7.0, 0.15)
	_pogo(p)
	hit.emit(target, info)

## Pogo: a down attack in the air bounces the player up off what it hit (once a swing): air
## jumps and air dashes come back.
func _pogo(p: MDSPlayer) -> void:
	if _bounced or not current or current.direction != MDSAttackData.Direction.DOWN or not p or p.is_on_floor():
		return
	_bounced = true
	p.velocity.y = -pogo_velocity
	p.air_dashes_left = p.config.air_dashes
	p.air_jumps_left = p.config.max_air_jumps if p.has_ability("double_jump") else 0
	if p.machine.has_state(&"Jump"):
		p.machine.force(&"Jump", {"keep_velocity": true})

## Whether the active down attack touches a hazard ([MDSHazard]'s hitbox: spikes, thorns),
## which has nothing to hurt but still bounces the player.
func _hits_hazard() -> bool:
	if _bounced or not current or current.direction != MDSAttackData.Direction.DOWN or not hitbox.monitoring:
		return false
	for a in hitbox.get_overlapping_areas():
		if a is MDSHitbox and (a as MDSHitbox).team == MDSHitbox.Team.HAZARD:
			return true
	return false

## Blocks [param info] when the player has the parry ability and pressed attack within
## [member parry_window] of the hit; the attacker is stunned. Returns whether it blocked.
func try_parry(info: MDSDamageInfo) -> bool:
	var p := _player()
	if not p or not p.has_ability("parry") or _clock - _last_attack_press > parry_window:
		return false
	var attacker := info.source
	if attacker and attacker.has_method(&"stun"):
		attacker.call(&"stun", 1.0)
	parried.emit(info)
	if MDSAttackFX.enabled() and p.is_inside_tree():
		MDSAttackFX.play("parry_flash", p.get_parent(), p.global_position + Vector2(p.facing * 24, -8))
	if p.gameplay:
		p.gameplay.hitstop(90)
	return true
