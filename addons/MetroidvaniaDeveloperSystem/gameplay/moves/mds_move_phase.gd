@tool
class_name MDSMovePhase
extends MDSBossPhase
## A phase of an [MDSMoveBoss]: [member moves] runs over and over from when its health falls to
## [member MDSBossPhase.health_threshold], at [member MDSBossPhase.speed_multiplier].

## What it does in this phase, usually an [MDSMovePick] of its attacks.
@export var moves: MDSMove
## Played once as the phase starts: a laugh, a scream, its new attack straight away.
@export var opening: MDSMove
## Moves that cut in as soon as their [member MDSMove.when] holds, whatever it is doing (unless that
## isn't [member MDSMove.interruptible]): backing off a player too close, answering a hit.
@export var reactions: Array[MDSMove] = []

## A phase (for code).
static func of(threshold: float, p_moves: MDSMove, p_speed := 1.0, p_opening: MDSMove = null, p_reactions: Array[MDSMove] = []) -> MDSMovePhase:
	var p := MDSMovePhase.new()
	p.health_threshold = threshold
	p.moves = p_moves
	p.speed_multiplier = p_speed
	p.opening = p_opening
	p.reactions = p_reactions
	return p
