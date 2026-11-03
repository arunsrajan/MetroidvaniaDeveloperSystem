extends "res://tests/mcp_test_case.gd"
## The MCP checks on a world with known problems: a door nobody can open, a room nothing leads to.

func _run() -> void:
	start_server()
	await make_world()
	await ok("mds_room_add", {"world": WORLD, "id": "Island", "rect": {"x": 0, "y": 5000, "w": 1152, "h": 648}})
	await ok("mds_room_add", {"world": WORLD, "id": "Locked", "rect": {"x": 2304, "y": 0, "w": 1152, "h": 648}})
	await ok("mds_gate_add", {"world": WORLD, "room": "R2", "pos": {"x": 2304, "y": 500}, "side": "right", "name": "right1"})
	await ok("mds_gate_add", {"world": WORLD, "room": "Locked", "pos": {"x": 2304, "y": 500}, "side": "left", "name": "left1"})
	await ok("mds_gate_connect", {"world": WORLD, "a": "R2", "a_gate": "right1", "b": "Locked", "b_gate": "left1", "requires": ["dash"]})
	await ok("mds_room_generate", {"world": WORLD, "room": "R1", "seed": 4})

	var v: Dictionary = await ok("mds_validate", {"world": WORLD})
	check(v.total > 0 and not v.issues.is_empty(), "the validator finds problems: %s" % [v.get("counts")])
	check(v.issues.any(func(i: Dictionary) -> bool: return i.room == "Island"), "the island is reported")
	var w := MDSWorld.load_world(WORLD)
	var scanner := MDSSceneScanner.new(w.get_default_room_size())
	scanner.require_room_instance = false
	var paths: Array[String] = [w.get_scene_path("R1")]
	var direct_db: Dictionary = await scanner.scan_paths(paths)
	var direct := MDSAnalysis.new(MDSGraph.from_world(w, direct_db), w, direct_db).run()
	check(v.total == MDSWorldValidator.run(w, direct, direct_db).size(), "the same as running the validator")
	var worst: Dictionary = await ok("mds_validate", {"world": WORLD, "min_severity": "error"})
	check(worst.issues.size() <= v.issues.size(), "min_severity filters")

	var progression: Dictionary = await ok("mds_analysis", {"world": WORLD, "kind": "progression"})
	check("Locked" in progression.locked, "the door is locked: %s" % [progression.locked])
	check("Island" in progression.disconnected, "the island is cut off: %s" % [progression.disconnected])
	var path: Dictionary = await ok("mds_analysis", {"world": WORLD, "kind": "path", "from": "R1", "to": "R2"})
	check(path.path == ["R1", "R2"], "the route: %s" % [path.path])
	await refused("mds_analysis", {"world": WORLD, "kind": "path", "from": "R1"}, "bad_arguments")
	await refused("mds_analysis", {"world": WORLD, "kind": "path", "from": "R1", "to": "nope"}, "room_not_found")
	var uses: Dictionary = await ok("mds_analysis", {"world": WORLD, "kind": "ability_uses", "ability": "dash"})
	check(uses.uses.size() == 1 and uses.sources.is_empty(), "dash is needed once, found nowhere")
	var back: Dictionary = await ok("mds_analysis", {"world": WORLD, "kind": "backtracking"})
	check(back.has("dead_ends") and back.has("hubs"), "backtracking")
	await ok("mds_analysis", {"world": WORLD, "kind": "objectives"})

	var checked: Dictionary = await ok("mds_room_check", {"world": WORLD, "rooms": ["R1", "R2"]})
	check(checked.rooms.has("R1") and checked.no_scene == ["R2"], "rooms with scenes are played: %s" % [checked.keys()])
	await refused("mds_room_check", {"world": WORLD, "rooms": ["nope"]}, "room_not_found")

	var dot: Dictionary = await ok("mds_export", {"world": WORLD, "format": "dot"})
	check(dot.text.contains("digraph") or dot.text.contains("graph"), "dot")
	var md: Dictionary = await ok("mds_export", {"world": WORLD, "format": "markdown"})
	check(md.text.contains("Locked"), "markdown")
	var json: Dictionary = await ok("mds_export", {"world": WORLD, "format": "json", "path": WORK + "/out/e.json"})
	check(JSON.parse_string(FileAccess.get_file_as_string(json.written)) is Dictionary, "json written")
	check(WORK + "/out/e.json" in json.changed, "a file written can be undone")

	# The same through the resources.
	var encoded := WORLD.uri_encode()
	var issues: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 1, "method": "resources/read", "params": {"uri": "mds://world/%s/issues" % encoded}})
	check(JSON.parse_string(issues.result.contents[0].text).total == v.total, "issues as a resource")
	var room: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 2, "method": "resources/read", "params": {"uri": "mds://world/%s/room/R1" % encoded}})
	check(JSON.parse_string(room.result.contents[0].text).gates.has("right1"), "a room as a resource")
	var nope: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 3, "method": "resources/read", "params": {"uri": "mds://world/%s/room/nope" % encoded}})
	check(nope.has("error"), "a missing room")
	var audit: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 4, "method": "resources/read", "params": {"uri": "mds://audit"}})
	check(JSON.parse_string(audit.result.contents[0].text).calls.size() > 0, "the audit log")
	var cat: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 5, "method": "resources/read", "params": {"uri": "mds://catalog/damage_types"}})
	check(JSON.parse_string(cat.result.contents[0].text).items.size() > 5, "the catalog")
	end_server()
