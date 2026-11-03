extends "res://tests/test_case.gd"
## The MCP server with the editor open: a headless editor as a child, and the stdio command handing
## it each request. Off by default; edits go through the panel; scenes open with unsaved changes
## aren't written over; when the editor goes, the command works by itself again.
##
## Slow (it starts the editor twice). Everything it starts is killed, and the files the editor
## writes outside tests/tmp are put back.

const Child := preload("res://tests/mcp_child.gd")
const Case := preload("res://tests/mcp_test_case.gd")
const WORK := TMP + "/mcp_editor"
const WORLD := WORK + "/w.mdsworld.json"
const SCENE := WORK + "/rooms/r_1.tscn"
const METADATA := "res://.godot/editor/project_metadata.cfg"
const ENDPOINT := MDSMcpGuard.DATA_DIR + "/endpoint.json"
const SECTION := "metroidvania_developer_system"

var editor_pid := -1
var child: Child

func _exit_tree() -> void:
	_stop_editor()
	if child:
		child.kill()

func _stop_editor() -> void:
	if editor_pid > 0 and OS.is_process_running(editor_pid):
		OS.kill(editor_pid)
	editor_pid = -1

func _set_enabled(on: bool) -> void:
	DirAccess.make_dir_recursive_absolute(METADATA.get_base_dir())
	var cfg := ConfigFile.new()
	cfg.load(METADATA)
	cfg.set_value(SECTION, "mcp_enabled", on)
	cfg.save(METADATA)

## Starts the editor on [param scene] and waits for its endpoint file.
func _start_editor(scene: String, wanted_on: bool) -> bool:
	DirAccess.remove_absolute(ENDPOINT)
	var args := PackedStringArray(["--headless", "--editor", "--path", ProjectSettings.globalize_path("res://").trim_suffix("/")])
	if not scene.is_empty():
		args.append(scene)
	editor_pid = OS.create_process(OS.get_executable_path(), args)
	var until := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < until:
		var live := MDSMcpEndpoint.read_live()
		if int(live.get("pid", 0)) == editor_pid and (int(live.port) > 0) == wanted_on:
			# Let the editor finish starting: the first requests are served while it scans.
			await get_tree().create_timer(2.0).timeout
			return true
		await get_tree().create_timer(0.2).timeout
	return false

func _run() -> void:
	var tree := get_tree()
	var project := FileAccess.get_file_as_bytes("res://project.godot")
	var metadata := FileAccess.get_file_as_bytes(METADATA) if FileAccess.file_exists(METADATA) else PackedByteArray()
	Case.clean_folder(WORK)
	# A scene for the editor to have open.
	child = Child.new()
	child.start()
	var tiles := WORK + "/t.tres"
	var built: Dictionary = await child.tool(tree, "mds_batch", {"ops": [
		{"tool": "mds_world_create", "args": {"path": WORLD, "name": "W", "settings": {"scene_folder": WORK + "/rooms", "room_tileset": tiles}}},
		{"tool": "mds_tileset_create", "args": {"path": tiles}},
		{"tool": "mds_room_add", "args": {"world": WORLD, "id": "R1", "rect": {"x": 0, "y": 0, "w": 1152, "h": 648}}},
		{"tool": "mds_room_add", "args": {"world": WORLD, "id": "R2", "rect": {"x": 1152, "y": 0, "w": 1152, "h": 648}}},
		{"tool": "mds_room_generate", "args": {"world": WORLD, "room": "R1", "seed": 1}},
		{"tool": "mds_room_generate", "args": {"world": WORLD, "room": "R2", "seed": 2}},
	]})
	check(not built.has("_error"), "the world is built headless: %s" % built.get("_error", ""))

	# Editor open, MCP off (the default): reads work here, writes wait.
	_set_enabled(false)
	check(await _start_editor("", false), "the editor says it is open, with no port")
	var off: Dictionary = await child.tool(tree, "mds_area_set", {"world": WORLD, "area": "Off"})
	check(off.has("_error") and off._error.code == "editor_open_mcp_off", "writes are refused: %s" % [off])
	var read: Dictionary = await child.tool(tree, "mds_world_get", {"world": WORLD})
	check(read.get("room_count") == 2, "reads still work")
	var status: Dictionary = await child.tool(tree, "mds_status")
	check(status.get("mode") == "headless", "served here, not by the editor")
	_stop_editor()
	await tree.create_timer(0.5).timeout
	DirAccess.remove_absolute(ENDPOINT)

	# Editor open, MCP on, with a scene open: requests go to the editor.
	_set_enabled(true)
	check(await _start_editor(SCENE, true), "the editor is serving")
	status = await child.tool(tree, "mds_status")
	check(status.get("mode") == "editor", "the same command now reaches the editor: %s" % [status])
	var opened: Dictionary = await child.tool(tree, "mds_editor_open", {"world": WORLD})
	check(not opened.has("_error"), "mds_editor_open: %s" % opened.get("_error", ""))
	status = await child.tool(tree, "mds_status")
	check(status.get("open_world") == WORLD, "the panel has the world open: %s" % status.get("open_world"))

	# The panel's world is edited, and saved right away.
	var live: Dictionary = await child.tool(tree, "mds_area_set", {"world": WORLD, "area": "Live", "title": "Live"})
	check(not live.has("_error") and live.get("undo_id", 0) > 0, "an edit in the panel's world: %s" % [live])
	check(MDSWorld.load_world(WORLD).has_area("Live"), "in the file at once")
	var undone: Dictionary = await child.tool(tree, "mds_undo")
	check(not undone.has("_error"), "undo: %s" % undone.get("_error", ""))
	var after: Dictionary = await child.tool(tree, "mds_world_get", {"world": WORLD})
	check(not after.get("areas", {"Live": 1}).has("Live"), "undo reaches the panel's world")
	await tree.create_timer(1.0).timeout
	check(not MDSWorld.load_world(WORLD).has_area("Live"), "and the panel doesn't save it back")

	# A room whose scene isn't open is written and reported.
	var other: Dictionary = await child.tool(tree, "mds_room_paint", {"world": WORLD, "room": "R2", "layer": "Decor", "op": "fill", "cells": [[1, 1]], "fill": {"type": "color", "color": "#ff0000"}})
	check(not other.has("_error"), "painting a closed scene: %s" % other.get("_error", ""))

	# The open scene: 4.7 knows it has nothing unsaved. 4.6 can't tell, so it is refused unless told.
	var args := {"world": WORLD, "room": "R1", "layer": "Decor", "op": "fill", "cells": [[2, 2]], "fill": {"type": "color", "color": "#00ff00"}}
	var before := FileAccess.get_file_as_bytes(SCENE)
	var open_edit: Dictionary = await child.tool(tree, "mds_room_paint", args)
	if Engine.get_version_info().minor >= 7:
		check(not open_edit.has("_error"), "4.7: a saved open scene can be written: %s" % open_edit.get("_error", ""))
	else:
		check(open_edit.has("_error") and open_edit._error.code == "scene_has_unsaved_changes", "4.6: an open scene is refused: %s" % [open_edit])
		check(FileAccess.get_file_as_bytes(SCENE) == before, "and left alone")
		var forced := args.duplicate()
		forced.on_unsaved = "save_first"
		open_edit = await child.tool(tree, "mds_room_paint", forced)
		check(not open_edit.has("_error"), "4.6: save_first: %s" % open_edit.get("_error", ""))
	check(FileAccess.get_file_as_bytes(SCENE) != before, "the scene was written")

	# A batch in the editor, with progress passed on.
	var batch: Dictionary = await child.tool(tree, "mds_batch", {"ops": [
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "B1"}},
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "B2"}},
	]})
	check(not batch.has("_error") and batch.results.size() == 2, "a batch: %s" % [batch.keys()])
	check(child.not_json.is_empty(), "stdout held only JSON: %s" % [child.not_json])

	# Direct HTTP with the token, as a client with a URL does.
	var ep := MDSMcpEndpoint.read_live()
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", ep.port)
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		peer.poll()
		await tree.process_frame
	var body := '{"jsonrpc":"2.0","id":5,"method":"ping"}'
	peer.put_data(("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Length: %d\r\n\r\n%s" % [ep.port, body.length(), body]).to_utf8_buffer())
	var got := ""
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and got.is_empty():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		if peer.get_available_bytes() > 0:
			got = peer.get_utf8_string(peer.get_available_bytes())
		await tree.process_frame
	check(got.contains("401"), "without the token: %s" % got.left(40))

	# The editor is killed mid-session: the command answers by itself at once, and writes again
	# when the endpoint file has gone stale.
	_stop_editor()
	await tree.create_timer(0.5).timeout
	status = await child.tool(tree, "mds_status")
	check(status.get("mode") == "headless", "back to headless: %s" % [status])
	var soon: Dictionary = await child.tool(tree, "mds_area_set", {"world": WORLD, "area": "Soon"})
	check(soon.has("_error") and soon._error.code == "editor_open_mcp_off", "not writing while it may still be there: %s" % [soon])
	await tree.create_timer(MDSMcpEndpoint.STALE_SEC + 1.5).timeout
	var alone: Dictionary = await child.tool(tree, "mds_area_set", {"world": WORLD, "area": "Alone"})
	check(not alone.has("_error"), "and then it can write: %s" % alone.get("_error", ""))
	check(await child.close_and_wait(tree), "the command exits")

	# Back as it was.
	var f := FileAccess.open(METADATA, FileAccess.WRITE)
	f.store_buffer(metadata)
	f.close()
	DirAccess.remove_absolute(ENDPOINT)
	var p := FileAccess.open("res://project.godot", FileAccess.WRITE)
	p.store_buffer(project)
	p.close()
	Case.clean_folder(WORK)
