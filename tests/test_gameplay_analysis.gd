extends "res://tests/test_case.gd"
## Gameplay Kit: the Progress tab's spheres with item: and flag: requirements (a room behind
## item:red_key comes after the room granting it, item:health_fragment>=2 after two fragments,
## flag: after the switch granting it), the scanner counting grants, the Issues tab matching
## requirements to their grants, and (phase 8) the kit's own Issues checks.

func _run() -> void:
	_spheres()
	_scanner_counts()
	_gameplay_issues()

## A -> B (needs item:red_key) -> C (needs item:health_fragment>=2) -> D (needs flag:bridge).
## A grants the key, B and C a fragment each, C the flag.
func _world() -> MDSWorld:
	var w := MDSWorld.new()
	var ids: Array[String] = []
	for i in 5:
		ids.append(w.add_room("R%d" % i, Rect2(i * 1152, 0, 1152, 648), 0))
	for i in 4:
		w.get_gates(ids[i])["right1"] = {"pos": [1152, 500], "side": "right"}
		w.get_gates(ids[i + 1])["left1"] = {"pos": [0, 500], "side": "left"}
		w.connect_gates(ids[i], "right1", ids[i + 1], "left1")
	w.set_start_room(ids[0])
	return w

func _spheres() -> void:
	var w := _world()
	w.get_gate("R0", "right1").requires = ["item:red_key"]
	w.get_gate("R1", "left1").requires = ["item:red_key"]
	w.get_gate("R1", "right1").requires = ["item:health_fragment>=2"]
	w.get_gate("R2", "left1").requires = ["item:health_fragment>=2"]
	w.get_gate("R2", "right1").requires = ["flag:bridge"]
	w.get_gate("R3", "left1").requires = ["flag:bridge"]
	w.get_gate("R3", "right1").requires = ["ability:dash"]
	w.get_gate("R4", "left1").requires = ["ability:dash"]
	w.set_room_value("R0", "grants", ["item:red_key", "item:health_fragment"])
	w.set_room_value("R1", "grants", ["item:health_fragment"])
	w.set_room_value("R2", "grants", ["flag:bridge"])
	w.set_room_value("R3", "grants", ["dash"])
	var a := MDSAnalysis.new(MDSGraph.from_world(w, {}), w, {}).run()
	check(a.sphere_of.get("R0") == 0 and a.sphere_of.get("R1") == 1, "the room behind item:red_key is in the sphere after the key's room (%s)" % [a.sphere_of])
	check(a.sphere_of.get("R2") == 2, "item:health_fragment>=2 opens once two fragments were found")
	check(a.sphere_of.get("R3") == 3, "flag:bridge opens after the room granting it")
	check(a.sphere_of.get("R4") == 4, "ability:dash is met by a dash grant")
	check(a.locked.is_empty(), "nothing locked")
	var issues := MDSWorldValidator.run(w, a, {})
	var never := issues.filter(func(i: Dictionary) -> bool: return str(i.message).contains("no room grants it"))
	check(never.is_empty(), "no 'required but never granted' for item:x>=n and ability:x (%s)" % [never.map(func(i: Dictionary) -> String: return i.message)])
	# One fragment fewer: R2 and beyond stay locked.
	w.set_room_value("R1", "grants", [])
	var b := MDSAnalysis.new(MDSGraph.from_world(w, {}), w, {}).run()
	check(not b.sphere_of.has("R2") and b.locked.has("R2"), "with one fragment, the door needing two stays shut")

## The scanner counts the nodes that grant the same thing.
func _scanner_counts() -> void:
	var root := Node2D.new()
	root.name = "Room"
	for i in 3:
		var n := Area2D.new()
		n.name = "Fragment%d" % i
		n.set_meta(&"mds_grants", ["item:health_fragment"])
		root.add_child(n)
		n.owner = root
	var path := TMP + "/gameplay_counts.tscn"
	check(save_scene(root, path) == OK, "a room with three fragments")
	root.free()
	var meta := MDSSceneScanner.new().analyze_scene_any(path)
	check(meta.grants == PackedStringArray(["item:health_fragment"]) and int(meta.grant_counts.get("item:health_fragment", 0)) == 3, "is scanned as granting item:health_fragment three times (%s)" % [meta.get("grant_counts")])

func _gameplay_issues() -> void:
	var temp_node := Node2D.new()
	temp_node.name = "R0"
	var scene_path := TMP + "/gameplay_issues_r0.tscn"
	check(save_scene(temp_node, scene_path) == OK, "saved dummy scene for issues check")
	temp_node.free()

	var w := MDSWorld.new()
	var r0 := w.add_room("R0", Rect2(0, 0, 1152, 648), 0)
	w.set_room_value(r0, "scene", scene_path)
	w.set_room_value(r0, "boss", "Warden")
	w.set_start_room(r0)

	var scene_db := {
		scene_path: {
			"ability_pickups_without_data": [{"name": "MDSAbilityPickup", "position": Vector2(100, 100)}],
			"invalid_boss_arenas": [{"name": "MDSBossArena", "has_boss": false, "has_doors": false, "position": Vector2(200, 200)}],
			"boss_nodes": [{"name": "WrongBossName", "position": Vector2(300, 300)}],
		}
	}
	var a := MDSAnalysis.new(MDSGraph.from_world(w, scene_db), w, scene_db).run()
	var issues := MDSWorldValidator.run(w, a, scene_db)

	var pickup_err := issues.filter(func(i: Dictionary) -> bool: return str(i.message).contains("has no ability data assigned"))
	check(not pickup_err.is_empty(), "ability pickup without data reported as error")

	var arena_err := issues.filter(func(i: Dictionary) -> bool: return str(i.message).contains("boss arena") and str(i.message).contains("no boss and no doors"))
	check(not arena_err.is_empty(), "boss arena without boss or doors reported as error")

	var boss_warn := issues.filter(func(i: Dictionary) -> bool: return str(i.message).contains("differs from room's boss"))
	check(not boss_warn.is_empty(), "boss name mismatch reported as warning")

	w.get_areas()["Forest"] = {"objective": "Find the key", "objective_done_when": "item:gold_key"}
	w.set_room_value(r0, "area", "Forest")
	var a2 := MDSAnalysis.new(MDSGraph.from_world(w, scene_db), w, scene_db).run()
	var issues2 := MDSWorldValidator.run(w, a2, scene_db)
	var obj_err := issues2.filter(func(i: Dictionary) -> bool: return str(i.message).contains("no room grants item 'gold_key'"))
	check(not obj_err.is_empty(), "objective with missing item grant reported as error")

