@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_hazard.svg")
class_name MDSHazard
extends Area2D
## Spikes, thorns or a pit: an area of [member size] (centred on the node) with an [MDSHitbox] of
## the HAZARD team. DAMAGE hurts the player and knocks it back; RESPAWN hurts it, then puts it
## back on the last safe ground (or the [MDSCheckpoint] touched in the room), as Hollow Knight's
## spikes do. While the player touches it no ground counts as safe. Nothing is saved: benches stay
## the only save points.

enum Mode { DAMAGE, RESPAWN }
enum Look { SPIKES, THORNS, PIT, NONE }

@export var mode: Mode = Mode.RESPAWN
@export var damage := 1
@export var knockback := Vector2(240, -340)
@export var size := Vector2(128, 32):
	set(v):
		size = v.max(Vector2(8, 8))
		_fit()
		queue_redraw()
@export var look: Look = Look.SPIKES:
	set(v):
		look = v
		queue_redraw()
@export var color := Color(0.78, 0.78, 0.82)

var hitbox: MDSHitbox

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	collision_layer = 0
	collision_mask = MDSGameplaySetup.player_detect_mask()
	var a := MDSAttackData.make("hazard", damage, [])
	a.knockback = knockback
	a.hitstop_ms = 50
	hitbox = MDSHitbox.make(MDSHitbox.Team.HAZARD, size, a)
	hitbox.name = "Hitbox"
	hitbox.one_hit_per_target = false
	hitbox.respawn = mode == Mode.RESPAWN
	add_child(hitbox)
	_fit()
	body_entered.connect(func(b: Node) -> void:
		if b is MDSPlayer:
			(b as MDSPlayer).hazards_touching += 1)
	body_exited.connect(func(b: Node) -> void:
		if b is MDSPlayer:
			(b as MDSPlayer).hazards_touching = maxi(0, (b as MDSPlayer).hazards_touching - 1))

func _fit() -> void:
	if not is_inside_tree():
		return
	var cs := get_node_or_null(^"Shape") as CollisionShape2D
	if not cs:
		if Engine.is_editor_hint():
			return
		cs = CollisionShape2D.new()
		cs.name = "Shape"
		add_child(cs)
	if not cs.shape is RectangleShape2D:
		cs.shape = RectangleShape2D.new()
	(cs.shape as RectangleShape2D).size = size
	if hitbox:
		hitbox.get_rect_shape().size = size

func _draw() -> void:
	var r := Rect2(-size * 0.5, size)
	match look:
		Look.SPIKES, Look.THORNS:
			var n := maxi(1, int(size.x / 16.0))
			var w := size.x / n
			var c := color if look == Look.SPIKES else Color(0.35, 0.5, 0.25)
			for i in n:
				var x := r.position.x + i * w
				draw_colored_polygon(PackedVector2Array([Vector2(x, r.end.y), Vector2(x + w * 0.5, r.position.y), Vector2(x + w, r.end.y)]), c)
				draw_line(Vector2(x + w * 0.5, r.position.y), Vector2(x + w * 0.5, r.end.y), c.darkened(0.35), 1.0)
		Look.PIT:
			draw_rect(r, Color(0.02, 0.02, 0.03, 0.85))
		_:
			if Engine.is_editor_hint():
				draw_rect(r, Color(1, 0.3, 0.2, 0.25))
				draw_rect(r, Color(1, 0.3, 0.2), false, 1.0)
