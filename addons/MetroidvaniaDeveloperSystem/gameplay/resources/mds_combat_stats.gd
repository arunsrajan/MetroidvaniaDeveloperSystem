@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_combat_stats.svg")
class_name MDSCombatStats
extends Resource
## Health, mana and toughness of the player, an enemy or a boss ([MDSHealth]).

@export var max_health := 5
@export var max_mana := 0
## Taken off every hit (a hit always does at least 1).
@export var defense := 0
## Damage done by touching it (enemies).
@export var contact_damage := 1
## Damage type -> multiplier ({"fire": 0.5, "ice": 2.0}); a type not listed takes 1.
@export var resistances: Dictionary = {}
## 0 to 1: how much less it is pushed back by hits.
@export_range(0.0, 1.0) var knockback_resistance := 0.0

## The multiplier for [param damage_type] (1 when not listed).
func resistance(damage_type: String) -> float:
	return float(resistances.get(damage_type, 1.0))

## Stats of [param max_hp] health (for code and tests).
static func make(max_hp: int, p_defense := 0, contact := 1) -> MDSCombatStats:
	var s := MDSCombatStats.new()
	s.max_health = max_hp
	s.defense = p_defense
	s.contact_damage = contact
	return s
