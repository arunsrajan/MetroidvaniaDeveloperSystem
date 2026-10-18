@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_detector.svg")
class_name MDSPlayerDetector
extends Area2D
## An enemy's eyes: a circle of [member sight_range] around it, and a line of sight through terrain
## (layer 1). [method sees_player] is true while the player is in it and nothing solid is between
## them (with [member needs_line_of_sight]).

signal player_seen(player: Node2D)
signal player_lost

@export var sight_range := 360.0:
	set(v):
		sight_range = v
		_fit()
@export var needs_line_of_sight := true
## Only in front of the enemy (its facing), with this half angle in degrees (180: all round).
@export_range(0.0, 180.0) var view_half_angle := 180.0

var _player: Node2D
var _seen := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = MDSGameplaySetup.player_detect_mask()
	monitorable = false
	_fit()
	body_entered.connect(func(b: Node) -> void:
		if b.is_in_group(&"player") and b is Node2D:
			_player = b)
	body_exited.connect(func(b: Node) -> void:
		if b == _player:
			_player = null)

func _fit() -> void:
	if not is_inside_tree():
		return
	var cs := get_node_or_null(^"Shape") as CollisionShape2D
	if not cs:
		cs = CollisionShape2D.new()
		cs.name = "Shape"
		add_child(cs)
	if not cs.shape is CircleShape2D:
		cs.shape = CircleShape2D.new()
	(cs.shape as CircleShape2D).radius = sight_range

## The player in range (seen or not), or null.
func get_player() -> Node2D:
	return _player if is_instance_valid(_player) else null

## Whether the player is in range, in view and in sight.
func sees_player() -> bool:
	var p := get_player()
	if not p:
		return _note(false)
	var to := p.global_position - global_position
	if view_half_angle < 180.0:
		var facing := 1.0
		var e := get_parent()
		if e and "facing" in e:
			facing = float(e.get("facing"))
		if absf(rad_to_deg(Vector2(facing, 0).angle_to(to))) > view_half_angle:
			return _note(false)
	if needs_line_of_sight:
		var q := PhysicsRayQueryParameters2D.create(global_position, p.global_position, MDSGameplaySetup.bit("world"))
		var ex: Array[RID] = []
		if get_parent() is CollisionObject2D:
			ex.append((get_parent() as CollisionObject2D).get_rid())
		if p is CollisionObject2D:
			ex.append((p as CollisionObject2D).get_rid())
		q.exclude = ex
		if not get_world_2d().direct_space_state.intersect_ray(q).is_empty():
			return _note(false)
	return _note(true)

func _note(seen: bool) -> bool:
	if seen != _seen:
		_seen = seen
		if seen:
			player_seen.emit(_player)
		else:
			player_lost.emit()
	return seen
