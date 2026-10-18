@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_ground_pound_state.svg")
class_name MDSPlayerGroundPoundState
extends MDSPlayerState
## With [code]ground_pound[/code]: down + dash in the air slams straight down
## ([member MDSMovementConfig.ground_pound_speed]); it breaks [code]cracked_floor[/code] breakables
## ([MDSBreakable]) it lands on and hits what is under it.

func _init() -> void:
	required_ability = "ground_pound"
	trigger = Trigger.AIR
	priority = 70

## The slam's hit (damage and what it breaks).
@export var attack: MDSAttackData
var hitbox: MDSHitbox
var _landed_for := 0.0

func can_enter() -> bool:
	return super() and not player.is_on_floor() and player.input_y() > 0.5 and player.pressed("dash")

func _ready() -> void:
	if not attack:
		attack = MDSAttackData.make("ground_pound", 2, ["cracked_floor", "wall"])
		attack.knockback = Vector2(260, -260)
		attack.hitstop_ms = 80

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.buffer.consume("dash")
	player.velocity = Vector2(0, player.config.ground_pound_speed)
	_landed_for = 0.0
	if not is_instance_valid(hitbox):
		hitbox = MDSHitbox.make(MDSHitbox.Team.PLAYER, Vector2(player.body_size.x + 16, 28), attack)
		hitbox.name = "PoundHitbox"
		hitbox.source = player
		player.add_child(hitbox)
	hitbox.position = Vector2(0, player.body_size.y * 0.5 + 8)
	hitbox.reset_hits()
	hitbox.active = true
	hitbox.monitoring = true

func exit(_next: StringName) -> void:
	if is_instance_valid(hitbox):
		hitbox.active = false
		hitbox.set_deferred(&"monitoring", false)

func physics_update(delta: float) -> void:
	player.velocity = Vector2(0, player.config.ground_pound_speed)
	player.move()
	if not player.is_on_floor():
		_landed_for = 0.0
		return
	if _landed_for == 0.0 and player.game and player.game.room_camera and player.game.room_camera.has_method(&"shake"):
		player.game.room_camera.call(&"shake", 9.0, 0.3)
	# A few frames on the floor, so what it landed on (a cracked floor) is hit.
	_landed_for += delta
	if _landed_for >= 0.1:
		player.on_landed()
		go(&"Idle")
