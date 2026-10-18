@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_ability_data.svg")
class_name MDSAbilityData
extends Resource
## One unlockable ability of the Gameplay Kit: [member id] is what
## [method MDSWorldGame.grant_ability] stores and what gates, barriers and objectives require
## ([code]dash[/code] or [code]ability:dash[/code]). The player's ability states check it with
## [method MDSPlayer.has_ability]; [MDSAbilityPickup] grants it, and [MDSAbilityPopup] shows
## [member display_name], [member description], [member icon] and the glyph of
## [member input_action] when it is gained.

enum Category { MOVEMENT, COMBAT, UTILITY }

## Lowercase id, as the world file and the save store it ("double_jump").
@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var category: Category = Category.MOVEMENT
## Other abilities it needs to work (informational: shown by the popup and the analysis).
@export var requires: PackedStringArray = []
## The input action that uses it (its key or button is shown by the popup), or empty.
@export var input_action: StringName = &""

## [member display_name], else the id made readable ("double_jump" -> "Double Jump").
func get_display_name() -> String:
	return display_name if not display_name.is_empty() else id.capitalize()
