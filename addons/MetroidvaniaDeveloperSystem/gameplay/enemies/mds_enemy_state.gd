@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_enemy_state.svg")
class_name MDSEnemyState
extends MDSState
## A state of an [MDSEnemy]'s state machine (patrol, chase, swoop, fire...). [member enemy] is the
## enemy; its helpers ([method MDSEnemy.walk], [method MDSEnemy.fall], [method MDSEnemy.sees_player])
## are the shared moves. The templates ([MDSWalker], [MDSFlyer], [MDSTurret], [MDSCharger],
## [MDSAmbusher]) and [MDSBoss] define theirs; a game adds its own by extending this.

var enemy: MDSEnemy:
	get:
		return body as MDSEnemy

## Seconds in this state (the machine's).
func elapsed() -> float:
	return machine.time_in_state if machine else 0.0
