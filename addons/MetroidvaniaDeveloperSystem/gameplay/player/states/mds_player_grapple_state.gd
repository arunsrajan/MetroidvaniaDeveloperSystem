@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_grapple_state.svg")
class_name MDSPlayerGrappleState
extends MDSPlayerState
## With [code]grapple[/code]: pressing grapple hooks the nearest [MDSGrapplePoint] in reach
## ([member MDSMovementConfig.grapple_range]) and in sight, and pulls the player to it
## ([member MDSMovementConfig.grapple_pull_speed]); the speed carries on after.

func _init() -> void:
	required_ability = "grapple"
	trigger = Trigger.ANY
	priority = 65

## Longest pull (s) before it lets go.
@export var max_time := 1.2
var target: Node2D
var _rope: Line2D

func can_enter() -> bool:
	return super() and player.pressed("grapple") and find_point() != null

## The grapple point to hook: the nearest in reach and in sight.
func find_point() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	var space := player.get_world_2d().direct_space_state
	for n in player.get_tree().get_nodes_in_group(&"mds_grapple_point"):
		if not n is Node2D or ("enabled" in n and not n.get("enabled")):
			continue
		var p := (n as Node2D).global_position
		var d := p.distance_to(player.global_position)
		if d > player.config.grapple_range or d >= best_d:
			continue
		var q := PhysicsRayQueryParameters2D.create(player.global_position, p, MDSGameplaySetup.bit("world"), [player.get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector2).distance_to(p) > 12.0:
			continue
		best = n
		best_d = d
	return best

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.buffer.consume("grapple")
	target = find_point()
	_rope = Line2D.new()
	_rope.width = 2.0
	_rope.default_color = Color(0.9, 0.85, 0.7)
	_rope.top_level = true
	player.add_child(_rope)
	player.on_landed()

func exit(_next: StringName) -> void:
	if is_instance_valid(_rope):
		_rope.queue_free()
	_rope = null

func physics_update(_delta: float) -> void:
	if not is_instance_valid(target):
		go(&"Fall")
		return
	var to := target.global_position - player.global_position
	_rope.points = PackedVector2Array([player.global_position, target.global_position])
	if to.length() < 28.0 or machine.time_in_state > max_time:
		player.velocity *= 0.6
		player.velocity.y = minf(player.velocity.y, -200.0)
		machine.force(&"Jump", {"keep_velocity": true})
		return
	player.velocity = to.normalized() * player.config.grapple_pull_speed
	player.facing = 1 if to.x > 0.0 else -1
	player.move()
