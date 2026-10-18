@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_state.svg")
class_name MDSPlayerState
extends MDSState
## A state of [MDSPlayer]'s state machine. An ability state sets [member required_ability]: it can
## only be entered while the player has that ability ([method MDSPlayer.has_ability]: granted by
## [method MDSWorldGame.grant_ability], or lent by equipment). A game adds an ability with an
## [MDSAbilityData] .tres and a state script extending this one, added under the player's
## StateMachine; [method MDSPlayer.try_air_moves] and [method MDSPlayer.try_ground_moves] try
## every state whose [member trigger] says where it starts.
##
## The helpers ([method run], [method fall], [method land_or_fall]) are the shared movement: run
## and air control, gravity, and the moves the player can go into from the ground or the air.

## Where the player's shared transitions try this state: never (only by name), from the ground,
## from the air, or both. Ability states set it; the core states (Idle, Run...) don't need to.
enum Trigger { NONE, GROUND, AIR, ANY }

## The ability it needs (empty: none).
@export var required_ability := ""
@export var trigger: Trigger = Trigger.NONE
## The higher, the earlier the shared transitions try it.
@export var priority := 0
## Animation played on entering it (empty: the state's name in snake_case).
@export var animation: StringName = &""

## The player (the [member MDSState.body]).
var player: MDSPlayer:
	get:
		return body as MDSPlayer

func can_enter() -> bool:
	return required_ability.is_empty() or (player != null and player.has_ability(required_ability))

## The animation name of the state.
func get_animation() -> StringName:
	return animation if animation != &"" else StringName(String(name).to_snake_case())

## Run and steer: on the ground or in the air.
func run(delta: float) -> void:
	player.steer(delta)

## Gravity, with the lighter apex and heavier fall.
func fall(delta: float, multiplier := 1.0) -> void:
	player.apply_gravity(delta, multiplier)

## After moving in the air: landed (Idle or Run, or a buffered jump), else nothing.
func land_or_fall() -> bool:
	if player.is_on_floor():
		player.on_landed()
		if not player.try_ground_moves():
			go(&"Run" if absf(player.input_x()) > 0.01 else &"Idle")
		return true
	return false
