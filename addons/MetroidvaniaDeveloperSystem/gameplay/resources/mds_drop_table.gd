@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_drop_table.svg")
class_name MDSDropTable
extends Resource
## Loot: each entry {item: MDSItemData (or an item id), chance: 0 to 1, min, max} is rolled on
## its own when an enemy dies ([method roll]).

@export var entries: Array[Dictionary] = []

## What drops: [[item (MDSItemData or id), count], ...].
func roll(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e in entries:
		if rng.randf() > float(e.get("chance", 1.0)):
			continue
		var lo := int(e.get("min", 1))
		var n := rng.randi_range(lo, maxi(lo, int(e.get("max", lo))))
		if n > 0 and e.get("item") != null:
			out.append([e.get("item"), n])
	return out
