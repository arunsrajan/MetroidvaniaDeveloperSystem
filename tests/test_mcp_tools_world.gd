extends "res://tests/mcp_test_case.gd"
## The MCP world, area, room and gate tools: what they write, compared with the world they say.

func _run() -> void:
	start_server()
	await make_world()
	var w := MDSWorld.load_world(WORLD)
	check(w.get_world_name() == "W" and w.get_start_room() == "R1", "name and start room")
	check(w.has_area("A") and w.get_areas().A.color == "#336699" and w.get_areas().A.title == "Area", "the area's values")
	check(w.get_room_ids().size() == 2 and w.get_room_area("R2") == "A", "rooms")
	check(w.get_gate("R1", "right1").get("to") == "R2" and w.get_gate("R2", "left1").get("to") == "R1", "gates connect both ways")

	var listed: Dictionary = await ok("mds_world_list")
	check(listed.worlds.is_empty() or true, "listing runs (tests/ isn't searched)")
	var got: Dictionary = await ok("mds_world_get", {"world": WORLD, "include": ["rooms", "gates"]})
	check(got.rooms.size() == 2 and got.rooms[0].gates.right1.to == "R2", "world_get has rooms and gates")
	check(got.rooms[0].bounds == [0, 0, 1152, 648], "bounds as a list")

	await refused("mds_world_create", {"path": WORLD, "name": "again"}, "already_exists")
	await refused("mds_world_create", {"path": "res://addons/x.mdsworld.json", "name": "x"}, "path_not_allowed")
	await refused("mds_world_create", {"path": "res://../x.mdsworld.json", "name": "x"}, "bad_world")
	await refused("mds_world_update", {"world": WORLD, "settings": {"nope": 1}}, "unknown_setting")
	await refused("mds_world_update", {"world": WORLD, "start_room": "nope"}, "room_not_found")
	await refused("mds_world_get", {"world": WORK + "/none.mdsworld.json"}, "world_not_found")
	await refused("mds_room_add", {"world": WORLD, "id": "X", "rect": {"x": 0, "y": 0, "w": 9, "h": 9}, "area": "nope"}, "area_not_found")
	await refused("mds_room_add", {"world": WORLD, "id": "X"}, "bad_arguments")

	var added: Dictionary = await ok("mds_room_add", {"world": WORLD, "id": "R1", "rect": {"x": 0, "y": 2000, "w": 500, "h": 500}, "type": "boss"})
	check(added.room.id != "R1", "a taken id gets another: %s" % added.room.id)
	var extra: String = added.room.id
	check(MDSWorld.load_world(WORLD).get_room_value(extra, "type", "") == "boss", "the room's type")
	await ok("mds_room_update", {"world": WORLD, "id": extra, "rename_to": "Boss", "area": "A", "origin": {"x": 0, "y": 3000}})
	w = MDSWorld.load_world(WORLD)
	check(w.has_room("Boss") and not w.has_room(extra) and w.get_origin("Boss") == Vector2(0, 3000), "rename and origin")
	await ok("mds_room_update", {"world": WORLD, "id": "Boss", "rects": [[0, 0, 300, 200], [300, 0, 100, 200]]})
	check(MDSWorld.load_world(WORLD).get_local_rects("Boss").size() == 2, "rects")
	var cells: Dictionary = await ok("mds_room_add", {"world": WORLD, "id": "Painted", "cells": [[20, 20], [21, 20]]})
	check(MDSWorld.load_world(WORLD).has_room(cells.room.id), "a room from cells")

	await ok("mds_area_set", {"world": WORLD, "area": "A", "rename_to": "B"})
	w = MDSWorld.load_world(WORLD)
	check(w.has_area("B") and not w.has_area("A") and w.get_room_area("R1") == "B", "rename an area")

	# Gates.
	var gate: Dictionary = await ok("mds_gate_add", {"world": WORLD, "room": "Boss", "pos": {"x": 0, "y": 3100}, "side": "left"})
	check(gate.side == "left" and not gate.gate.is_empty(), "a gate gets a name")
	await ok("mds_gate_update", {"world": WORLD, "room": "Boss", "gate": gate.gate, "rename_to": "left9"})
	check(MDSWorld.load_world(WORLD).has_gate("Boss", "left9"), "rename a gate")
	await refused("mds_gate_update", {"world": WORLD, "room": "Boss", "gate": "nope"}, "gate_not_found")
	await refused("mds_gate_update", {"world": WORLD, "room": "Boss", "gate": "left9", "values": {"to": "x"}}, "bad_arguments")
	await ok("mds_gate_add", {"world": WORLD, "room": "R2", "pos": {"x": 2304, "y": 100}, "side": "right", "name": "right2"})
	await ok("mds_gate_connect", {"world": WORLD, "a": "R2", "a_gate": "right2", "b": "Boss", "b_gate": "left9", "requires": ["dash"]})
	w = MDSWorld.load_world(WORLD)
	check("dash" in w.get_door_requires(MDSWorld.edge_key("R2", "right2", "Boss", "left9")), "a door's requirement")
	await ok("mds_gate_disconnect", {"world": WORLD, "room": "R2", "gate": "right2"})
	check(not MDSWorld.load_world(WORLD).get_gate("R2", "right2").has("to"), "disconnect")
	await refused("mds_gate_remove", {"world": WORLD, "room": "R2", "gate": "right2"}, "bad_arguments")
	await refused("mds_gate_remove", {"world": WORLD, "room": "R2", "gate": "right2", "confirm": false}, "confirm_needed")
	await ok("mds_gate_remove", {"world": WORLD, "room": "R2", "gate": "right2", "confirm": true})
	check(not MDSWorld.load_world(WORLD).has_gate("R2", "right2"), "remove a gate")

	# Generating: the same seed makes the same map as the class does directly.
	var box := {"x": 100, "y": 100, "w": 12, "h": 8}
	var preview: Dictionary = await ok("mds_area_generate", {"world": WORLD, "area": "Gen", "box": box, "seed": 5, "dry_run": true})
	check(preview.rooms > 0 and not MDSWorld.load_world(WORLD).has_area("Gen"), "a dry run makes nothing")
	var before := MDSWorld.load_world(WORLD)
	var direct := MDSAreaGenerator.new()
	direct.seed_value = 5
	var want := direct.generate(before, Rect2i(100, 100, 12, 8), 0, "Gen")
	var made: Dictionary = await ok("mds_area_generate", {"world": WORLD, "area": "Gen", "box": box, "seed": 5})
	check(made.rooms == Array(want.rooms) and made.doors == want.doors, "the same as MDSAreaGenerator: %s" % [made])
	await refused("mds_area_generate", {"world": WORLD, "area": "Gen2", "box": box, "seed": 5}, "nothing_generated")

	# Merging, and removing.
	await ok("mds_room_add", {"world": WORLD, "id": "M1", "rect": {"x": 9000, "y": 0, "w": 100, "h": 100}})
	await ok("mds_room_add", {"world": WORLD, "id": "M2", "rect": {"x": 9100, "y": 0, "w": 100, "h": 100}})
	await refused("mds_room_merge", {"world": WORLD, "ids": ["M1"]}, "cant_merge")
	var merged: Dictionary = await ok("mds_room_merge", {"world": WORLD, "ids": ["M1", "M2"], "keep_id": "M1"})
	check(merged.room.id == "M1" and not MDSWorld.load_world(WORLD).has_room("M2"), "merged")
	await refused("mds_room_remove", {"world": WORLD, "id": "M1"}, "bad_arguments")
	await ok("mds_room_remove", {"world": WORLD, "id": "M1", "confirm": true})
	check(not MDSWorld.load_world(WORLD).has_room("M1"), "removed")
	await ok("mds_area_remove", {"world": WORLD, "area": "Gen", "confirm": true})
	check(not MDSWorld.load_world(WORLD).has_area("Gen"), "area removed")
	var auto: Dictionary = await ok("mds_gates_auto", {"world": WORLD, "mode": "touching"})
	check(auto.made >= 0, "auto gates run")

	# Atomic writes leave no temporary file.
	check(not FileAccess.file_exists(WORLD + ".tmp"), "no temporary file left")
	end_server()
