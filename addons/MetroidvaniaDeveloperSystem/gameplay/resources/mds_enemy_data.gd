@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_enemy_data.svg")
class_name MDSEnemyData
extends Resource
## An enemy's definition ([MDSEnemy]): its stats, what it drops, its currency and XP, and its
## bestiary entry (the pause menu's Bestiary lists the enemies defeated).

@export var id := ""
@export var display_name := ""
@export var stats: MDSCombatStats
@export var drops: MDSDropTable
## Currency dropped: between x and y.
@export var currency_drop := Vector2i(2, 5)
## Experience given, with the LEVELS progression.
@export var xp := 0
@export_multiline var bestiary_text := ""

func get_display_name() -> String:
	return display_name if not display_name.is_empty() else id.capitalize()
