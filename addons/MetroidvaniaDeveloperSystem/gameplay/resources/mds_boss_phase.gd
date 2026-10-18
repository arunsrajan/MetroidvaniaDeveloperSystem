@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_boss_phase.svg")
class_name MDSBossPhase
extends Resource
## A phase of a boss ([MDSBoss]): it starts when the boss's health falls to
## [member health_threshold] of its maximum (1: from the start), plays [member enter_animation],
## and attacks with [member attack_states] (state names of the boss's state machine) at
## [member speed_multiplier].

@export_range(0.0, 1.0) var health_threshold := 1.0
@export var attack_states: PackedStringArray = []
@export var speed_multiplier := 1.0
@export var enter_animation: StringName = &""

static func make(threshold: float, states: PackedStringArray, speed := 1.0) -> MDSBossPhase:
	var p := MDSBossPhase.new()
	p.health_threshold = threshold
	p.attack_states = states
	p.speed_multiplier = speed
	return p
