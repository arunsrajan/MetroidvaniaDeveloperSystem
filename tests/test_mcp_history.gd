extends "res://tests/mcp_test_case.gd"
## Undoing MCP changes: bytes come back, later edits aren't overwritten, batches go as one.

func _run() -> void:
	start_server()
	await make_world()

	# Undo puts the very bytes back.
	var before := FileAccess.get_file_as_bytes(WORLD)
	var changed: Dictionary = await ok("mds_area_set", {"world": WORLD, "area": "New"})
	check(WORLD in changed.changed and changed.undo_id > 0, "an edit says what changed and how to undo it")
	check(FileAccess.get_file_as_bytes(WORLD) != before, "the file changed")
	var undone: Dictionary = await ok("mds_undo")
	check(WORLD in undone.restored, "undo says what it restored")
	check(FileAccess.get_file_as_bytes(WORLD) == before, "the same bytes as before")
	check(not MDSWorld.load_world(WORLD).has_area("New"), "the area is gone")

	# Undo removes files the step made.
	var scene: Dictionary = await ok("mds_room_scene_create", {"world": WORLD, "room": "R1"})
	check(FileAccess.file_exists(scene.scene), "the scene is there")
	await ok("mds_undo")
	check(not FileAccess.file_exists(scene.scene), "undo removes the scene it made")
	check(MDSWorld.load_world(WORLD).get_scene_path("R1").is_empty(), "and the world forgets it")

	# A later edit isn't overwritten.
	await ok("mds_area_set", {"world": WORLD, "area": "Kept"})
	var edited := FileAccess.get_file_as_string(WORLD) + "\n"
	var f := FileAccess.open(WORLD, FileAccess.WRITE)
	f.store_string(edited)
	f.close()
	await refused("mds_undo", {}, "undo_refused")
	check(FileAccess.get_file_as_string(WORLD) == edited, "someone's edit stays")

	# Only the newest can be undone; steps are listed newest first.
	await ok("mds_area_set", {"world": WORLD, "area": "One"})
	var second: Dictionary = await ok("mds_area_set", {"world": WORLD, "area": "Two"})
	var history: Dictionary = await ok("mds_history", {"limit": 2})
	check(history.steps[0].id == second.undo_id and history.steps[0].tool == "mds_area_set" and history.steps.size() == 2, "newest first")
	await refused("mds_undo", {"undo_id": second.undo_id - 1}, "undo_refused")
	await ok("mds_undo", {"undo_id": second.undo_id})
	await ok("mds_undo")
	check(not MDSWorld.load_world(WORLD).has_area("One"), "two undos")

	# A batch is one step.
	before = FileAccess.get_file_as_bytes(WORLD)
	var batch: Dictionary = await ok("mds_batch", {"ops": [
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "B1"}},
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "B2"}},
		{"tool": "mds_status"},
	]})
	check(batch.results.size() == 3 and batch.undo_id > 0, "the batch ran: %s" % [batch.keys()])
	check(not batch.results[0].has("undo_id"), "its calls aren't steps of their own")
	await ok("mds_undo")
	check(FileAccess.get_file_as_bytes(WORLD) == before, "one undo takes the batch back")

	# An atomic batch that fails leaves nothing, and says which call failed.
	var failed: Dictionary = await call_mcp("mds_batch", {"ops": [
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "B1"}},
		{"tool": "mds_room_scene_create", "args": {"world": WORLD, "room": "R2"}},
		{"tool": "mds_room_remove", "args": {"world": WORLD, "id": "nope", "confirm": true}},
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "B3"}},
	]})
	check(failed.has("_error") and failed._error.code == "room_not_found" and failed._error.details.failed_op == 2, "says which: %s" % [failed])
	check(FileAccess.get_file_as_bytes(WORLD) == before, "the world is as it was")
	check(not FileAccess.file_exists(WORK + "/rooms/r2.tscn"), "a scene it made is gone")

	# Not atomic: what ran before the failure stays.
	var partial: Dictionary = await ok("mds_batch", {"atomic": false, "ops": [
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "P1"}},
		{"tool": "mds_area_remove", "args": {"world": WORLD, "area": "nope", "confirm": true}},
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "P2"}},
	]})
	check(partial.stopped_at == 1 and partial.results.size() == 1, "stops at the failure")
	var w := MDSWorld.load_world(WORLD)
	check(w.has_area("P1") and not w.has_area("P2"), "what ran stays")

	# Unknown tools in a batch are failures, and the lock isn't left behind.
	var nope: Dictionary = await call_mcp("mds_batch", {"ops": [{"tool": "nope"}]})
	check(nope.has("_error") and nope._error.code == "unknown_tool", "an unknown tool")
	check(not FileAccess.file_exists(server.ctx.guard.data_dir.path_join("lock")), "no lock left")

	# Old steps are dropped.
	var h := MDSMcpHistory.new(WORK + "/h")
	var file := WORK + "/h.txt"
	for i in MDSMcpHistory.MAX_STEPS + 3:
		h.begin("t")
		h.touch(file)
		var w2 := FileAccess.open(file, FileAccess.WRITE)
		w2.store_string(str(i))
		w2.close()
		h.commit()
	check(h.steps().size() == MDSMcpHistory.MAX_STEPS, "only so many steps are kept")
	end_server()
