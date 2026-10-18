@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_projectile.svg")
class_name MDSProjectile
extends MDSHitbox
## A shot: spells and sub-weapons of the player (fired on [code]special[/code], costing mana), a
## turret's bolt. It flies at [member velocity] (falling with [member drop]), hits like an [MDSHitbox]
## of its team, and is gone after [member lifetime] seconds, after [member pierce] + 1 hits, or on
## touching terrain (unless [member passes_walls]). Without a shape of its own it is a
## [member radius] circle, drawn as a glowing ball.

@export var velocity := Vector2(600, 0)
## Pull down on it (px/s²; an arrow, a lobbed bomb).
@export var drop := 0.0
@export var lifetime := 2.0
## Targets it goes through before it is gone (0: the first one stops it).
@export var pierce := 0
@export var passes_walls := false
@export var radius := 10.0
@export var color := Color(0.65, 0.85, 1.0)

var _age := 0.0
var _hits := 0

func _ready() -> void:
	super()
	top_level = true
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = radius
		cs.shape = c
		add_child(cs)
	if not passes_walls:
		collision_mask |= MDSGameplaySetup.bit("world")
		body_entered.connect(func(_b: Node) -> void: queue_free())
	hit_landed.connect(func(_t: Node, _i: MDSDamageInfo) -> void:
		_hits += 1
		if _hits > pierce:
			queue_free())

## Fires a projectile of [param scene] (null: a plain one) from [param from] toward [param dir]
## for [param p_team], with [param p_attack], under [param parent].
static func fire(scene: PackedScene, parent: Node, from: Vector2, dir: Vector2, p_team: Team, p_attack: MDSAttackData, src: Node = null) -> MDSProjectile:
	var p: MDSProjectile = (scene.instantiate() as MDSProjectile) if scene else MDSProjectile.new()
	if not p:
		return null
	p.team = p_team
	p.attack = p_attack
	p.source = src
	var speed := p.velocity.length() if p.velocity != Vector2.ZERO else 600.0
	p.velocity = dir.normalized() * speed
	parent.add_child(p)
	p.global_position = from
	return p

func _physics_process(delta: float) -> void:
	velocity.y += drop * delta
	global_position += velocity * delta
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	super(delta)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * 1.8, Color(color, 0.25))
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 1, 1, 0.9))
