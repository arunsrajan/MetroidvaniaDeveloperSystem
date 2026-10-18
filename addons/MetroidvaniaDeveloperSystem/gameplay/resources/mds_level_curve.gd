@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_level_curve.svg")
class_name MDSLevelCurve
extends Resource
## Experience levels, with the LEVELS progression setting: reaching level n takes
## [code]base_xp * growth^(n - 2)[/code] more XP than level n - 1, and each level past the first
## gives [member health_per_level] health and [member damage_per_level] damage.

@export var base_xp := 20
@export var growth := 1.5
@export var max_level := 30
@export var health_per_level := 1
@export var damage_per_level := 0.0

## Total XP needed to reach [param level] (level 1 needs none).
func xp_for(level: int) -> int:
	var total := 0.0
	for n in range(1, clampi(level, 1, max_level)):
		total += base_xp * pow(growth, n - 1)
	return int(round(total))

## The level [param xp] reaches.
func level_for(xp: int) -> int:
	var lvl := 1
	while lvl < max_level and xp >= xp_for(lvl + 1):
		lvl += 1
	return lvl
