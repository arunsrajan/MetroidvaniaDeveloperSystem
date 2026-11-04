@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_projectile.svg")
class_name MDSBossShot
extends MDSProjectile
## A shot with more to it than [MDSProjectile]: it comes back off the walls [member bounces] times,
## can stop and go off after [member fuse] seconds into zones ([member burst]), and the player can
## knock it away before then ([member knockable]). Fired by [MDSMoveShoot].

## How many times it comes back off the terrain. After that it stops ([member fuse] > 0) or is gone.
@export var bounces := 0
## Seconds after it stops until it goes off. 0: it is gone instead of stopping.
@export var fuse := 0.0
## It goes off into these: a [MDSCombatZone] for each direction, up and down or to the sides.
@export var burst_vertical := true
@export var burst_size := Vector2(60, 400)
@export var burst_color := Color(1.0, 0.8, 0.45)
@export var knockable := false
## It flies through terrain, whatever it hits.
@export var ignore_terrain := false
## Seconds the player can still knock it away after it stops.
@export var fuse_left := 0.0

var _stopped := false
var _left := 0
var _guard: MDSHurtbox

func _ready() -> void:
	passes_walls = true
	super()
	_left = bounces
	if knockable:
		_guard = MDSHurtbox.make(MDSHurtbox.Team.NEUTRAL, Vector2(radius, radius) * 3.0)
		_guard.name = "Guard"
		add_child(_guard)

func _physics_process(delta: float) -> void:
	if _stopped:
		fuse_left -= delta
		if fuse_left <= 0.0:
			_go_off()
			return
		super(delta)
		return
	if ignore_terrain:
		super(delta)
		return
	var from := global_position
	var to := from + (velocity + Vector2(0, drop * delta)) * delta
	var q := PhysicsRayQueryParameters2D.create(from, to, MDSGameplaySetup.bit("world"))
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		if _left > 0:
			_left -= 1
			velocity = velocity.bounce(hit.normal) * 0.9
			global_position = hit.position + hit.normal * 2.0
		elif fuse > 0.0:
			global_position = hit.position + hit.normal * (radius + 1.0)
			_stop_here()
			return
		else:
			queue_free()
			return
	super(delta)

func _stop_here() -> void:
	_stopped = true
	velocity = Vector2.ZERO
	drop = 0.0
	lifetime += fuse + 1.0
	fuse_left = fuse

## The player knocks it away, or sets it off once it has stopped.
func mds_take_hit(info: MDSDamageInfo) -> int:
	if not knockable:
		return 0
	if _stopped:
		_go_off()
		return 1
	var dir := signf(global_position.x - info.origin.x)
	velocity = Vector2((dir if dir != 0.0 else 1.0) * velocity.length(), -absf(velocity.length()) * 0.4)
	return 1

func _go_off() -> void:
	var z := MDSCombatZone.new()
	z.shape = MDSCombatZone.Shape.BOX
	z.size = burst_size if burst_vertical else Vector2(burst_size.y, burst_size.x)
	z.telegraph = 0.0
	z.active_time = 0.3
	z.color = burst_color
	z.attack = attack
	z.source = source
	if get_parent():
		get_parent().add_child(z)
		z.global_position = global_position
	queue_free()
