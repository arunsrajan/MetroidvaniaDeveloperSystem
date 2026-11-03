extends "res://tests/mcp_test_case.gd"
## What the MCP server refuses: paths, tiers, confirmations, sizes, and the lock between processes.

func _run() -> void:
	var project_before := FileAccess.get_file_as_bytes("res://project.godot")

	# Paths.
	check(MDSMcpGuard.normalize("res://a/../../b").is_empty(), ".. is refused")
	check(MDSMcpGuard.normalize("user://a").is_empty() and MDSMcpGuard.normalize("C:/a").is_empty() and MDSMcpGuard.normalize("/etc/passwd").is_empty(), "only res://")
	check(MDSMcpGuard.normalize("res://a\\b//c.tscn") == "res://a/b/c.tscn", "normalized")
	var guard := MDSMcpGuard.new()
	for no in ["res://addons/x.gd", "res://.godot/x", "res://.git/config", "res://.github/x.yml", "res://project.godot", "res://ADDONS/../addons/x"]:
		check(not guard.write_problem(no).is_empty(), "%s can't be written" % no)
	check(guard.write_problem("res://levels/a.tscn").is_empty(), "elsewhere can")
	guard.allow_project_file = true
	check(guard.write_problem("res://project.godot").is_empty(), "project.godot, for the tool allowed to")
	check(not guard.write_problem("res://addons/x.gd").is_empty(), "that doesn't open addons")

	# Tiers.
	start_server(MDSMcpGuard.Tier.READ)
	await ok("mds_status")
	await refused("mds_world_create", {"path": WORLD, "name": "x"}, "tier_too_low")
	check(not FileAccess.file_exists(WORLD), "the read tier wrote nothing")
	await refused("mds_gameplay_setup", {}, "tier_too_low")
	start_server(MDSMcpGuard.Tier.AUTHOR)
	await make_world()
	await refused("mds_gameplay_setup", {}, "tier_too_low")
	check(FileAccess.get_file_as_bytes("res://project.godot") == project_before, "project.godot is untouched")

	# Writes where they don't belong, through each kind of tool.
	await refused("mds_world_create", {"path": "res://addons/a.mdsworld.json", "name": "x"}, "path_not_allowed")
	await refused("mds_tileset_create", {"path": "res://addons/a.tres"}, "path_not_allowed")
	await refused("mds_room_scene_create", {"world": WORLD, "room": "R1", "scene_path": "res://addons/a.tscn"}, "path_not_allowed")
	await refused("mds_game_scene_create", {"world": WORLD, "path": "res://addons/a.tscn"}, "path_not_allowed")
	await refused("mds_export", {"world": WORLD, "format": "dot", "path": "res://project.godot"}, "path_not_allowed")
	await refused("mds_world_get", {"world": "res://../secret.mdsworld.json"}, "bad_world")
	await refused("mds_world_update", {"world": WORLD, "settings": {"scene_folder": "C:/elsewhere"}}, "path_not_allowed")
	await refused("mds_room_scene_create", {"world": WORLD, "room": "R1", "scene_path": "res://rooms/a.gd"}, "bad_arguments")

	# Destructive tools.
	await refused("mds_room_remove", {"world": WORLD, "id": "R1"}, "bad_arguments")
	await refused("mds_room_remove", {"world": WORLD, "id": "R1", "confirm": false}, "confirm_needed")
	check(MDSWorld.load_world(WORLD).has_room("R1"), "the room is still there")

	# Sizes.
	var many := []
	many.resize(MDSMcpProtocol.MAX_BATCH_OPS + 1)
	many.fill({"tool": "mds_status"})
	await refused("mds_batch", {"ops": many}, "bad_arguments")
	await refused("mds_batch", {"ops": [{"tool": "mds_batch", "args": {"ops": []}}]}, "bad_batch")
	var huge := {"world": WORLD, "room": "R1", "layer": "Terrain", "op": "erase", "rect": {"x": 0, "y": 0, "w": 100000, "h": 100000}}
	await ok("mds_room_generate", {"world": WORLD, "room": "R1", "seed": 1})
	await refused("mds_room_paint", huge, "too_many_cells")

	# Editor tools, without an editor.
	await refused("mds_editor_open", {"world": WORLD}, "requires_editor")
	await refused("mds_editor_save_scenes", {}, "requires_editor")

	# A live process holds the lock: another one waits, then gives up. A dead holder doesn't count.
	var data := WORK + "/lockdata"
	var a := MDSMcpGuard.new(MDSMcpGuard.Tier.AUTHOR, data)
	check(await a.acquire_lock(), "the lock is free")
	check(FileAccess.get_file_as_string(data + "/lock").to_int() == OS.get_process_id(), "it says who holds it")
	check(await a.acquire_lock(), "this process may take its own again")
	a.release_lock()
	check(not FileAccess.file_exists(data + "/lock"), "released")
	var f := FileAccess.open(data + "/lock", FileAccess.WRITE)
	f.store_string("999999")
	f.close()
	a.lock_wait_msec = 200
	check(not await a.acquire_lock(), "another process's lock is waited for, then given up on")
	a.lock_stale_sec = -1
	check(await a.acquire_lock(), "a lock left long ago doesn't count")
	check(FileAccess.get_file_as_string(data + "/lock").to_int() == OS.get_process_id(), "it is taken over")
	a.release_lock()

	# The editor is open with MCP off: this process doesn't write behind it, but reads.
	var endpoint_file := server.ctx.guard.data_dir.path_join("endpoint.json")
	MDSMcpEndpoint.write(0, "", endpoint_file)
	var endpoint := FileAccess.open(endpoint_file, FileAccess.READ_WRITE)
	endpoint.store_string(JSON.stringify({"pid": 999999, "port": 0, "token": ""}))
	endpoint.close()
	check(MDSMcpEndpoint.read_live(endpoint_file).pid == 999999, "the endpoint can be read")
	await refused("mds_area_set", {"world": WORLD, "area": "Z"}, "editor_open_mcp_off")
	await ok("mds_world_get", {"world": WORLD})
	DirAccess.remove_absolute(endpoint_file)

	# The audit log.
	var audit := server.ctx.guard.recent_audit(500)
	check(audit.size() > 3 and audit[0].has("tool") and audit[0].has("time"), "calls are logged")
	check(audit.any(func(e: Dictionary) -> bool: return e.tool == "mds_world_create" and WORLD in e.changed), "with the files they changed")
	check(FileAccess.get_file_as_bytes("res://project.godot") == project_before, "project.godot is still untouched")

	# Only at the full tier, and it only adds.
	start_server(MDSMcpGuard.Tier.FULL)
	var setup: Dictionary = await ok("mds_gameplay_setup")
	check(setup.added.has("actions") and setup.added.has("layers") and setup.added.has("settings"), "gameplay setup says what it added")
	check(not server.ctx.guard.allow_project_file, "the permission ends with the tool")
	var restore := FileAccess.open("res://project.godot", FileAccess.WRITE)
	restore.store_buffer(project_before)
	restore.close()
	end_server()
