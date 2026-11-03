extends "res://tests/test_case.gd"
## The MCP server's command as a client runs it, in a child process: stdout must hold nothing but
## MCP messages, whatever the tools do.

const Child := preload("res://tests/mcp_child.gd")
const WORK := TMP + "/mcp_stdio"
const WORLD := WORK + "/w.mdsworld.json"
const Case := preload("res://tests/mcp_test_case.gd")

var child: Child

func _exit_tree() -> void:
	if child:
		child.kill()

func _run() -> void:
	Case.clean_folder(WORK)
	var tree := get_tree()
	child = Child.new()
	check(child.start(), "the server starts")
	var meta := {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientInfo": {"name": "test", "version": "1"}}

	# The first thing on stdout is the first answer.
	var first: Dictionary = await child.request(tree, {"jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": {"_meta": meta}})
	check(first.get("id") == 1 and first.result.resultType == "complete", "server/discover: %s" % [first.keys()])
	var init: Dictionary = await child.request(tree, {"jsonrpc": "2.0", "id": 2, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}})
	check(init.result.protocolVersion == "2025-06-18", "initialize")
	child.send('{"jsonrpc":"2.0","method":"notifications/initialized"}')
	var pong: Dictionary = await child.request(tree, {"jsonrpc": "2.0", "id": 3, "method": "ping"})
	check(pong.get("id") == 3, "a notification gets no answer, and the next request does")

	# Two in one write, a blank line between, and one with a Windows line end.
	child.send('{"jsonrpc":"2.0","id":10,"method":"ping"}\n\n{"jsonrpc":"2.0","id":11,"method":"ping"}\r')
	var a: Dictionary = JSON.parse_string(await child.read_line(tree))
	var b: Dictionary = JSON.parse_string(await child.read_line(tree))
	check(int(a.id) == 10 and int(b.id) == 11, "answered in order")

	# Broken input doesn't stop it.
	child.send("{broken")
	var broken: Variant = JSON.parse_string(await child.read_line(tree))
	check(broken is Dictionary and int(broken.error.code) == -32700, "broken JSON")

	# Building something: everything on stdout stays JSON.
	var listed: Dictionary = await child.request(tree, {"jsonrpc": "2.0", "id": 4, "method": "tools/list"})
	check(listed.result.tools.size() >= 40, "tools/list")
	var tiles := WORK + "/t.tres"
	var made: Dictionary = await child.tool(tree, "mds_batch", {"ops": [
		{"tool": "mds_world_create", "args": {"path": WORLD, "name": "Wörld ✓", "settings": {"scene_folder": WORK + "/rooms", "room_tileset": tiles}}},
		{"tool": "mds_tileset_create", "args": {"path": tiles}},
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "Área", "title": "日本語"}},
		{"tool": "mds_room_add", "args": {"world": WORLD, "id": "R1", "rect": {"x": 0, "y": 0, "w": 1152, "h": 648}, "area": "Área"}},
		{"tool": "mds_room_generate", "args": {"world": WORLD, "room": "R1", "seed": 1}},
		{"tool": "mds_room_place", "args": {"world": WORLD, "room": "R1", "kind": "enemy", "template": "walker", "pos": {"x": 300, "y": 300}, "name": "W"}},
		{"tool": "mds_enemy_configure", "args": {"world": WORLD, "room": "R1", "node": "W", "damage_type": "ice"}},
	]})
	check(not made.has("_error"), "a batch through stdio: %s" % made.get("_error", ""))
	var got: Dictionary = await child.tool(tree, "mds_world_get", {"world": WORLD})
	check(got.get("name") == "Wörld ✓" and got.areas.has("Área") and got.areas["Área"].title == "日本語", "UTF-8 both ways: %s" % got.get("name"))
	for call_args: Array in [["mds_status", {}], ["mds_validate", {"world": WORLD}], ["mds_room_ascii", {"world": WORLD, "room": "R1"}], ["mds_room_preview", {"world": WORLD, "room": "R1"}], ["mds_room_check", {"world": WORLD, "rooms": ["R1"]}], ["mds_analysis", {"world": WORLD, "kind": "progression"}], ["mds_export", {"world": WORLD, "format": "markdown"}], ["mds_catalog", {"kind": "effects"}]]:
		var r: Dictionary = await child.tool(tree, call_args[0], call_args[1])
		check(not r.has("_error"), "%s: %s" % [call_args[0], r.get("_error", "")])
	var missing: Dictionary = await child.tool(tree, "mds_room_generate", {"world": WORLD, "room": "nope"})
	check(missing.has("_error") and missing._error.code == "room_not_found", "a failure is an answer")

	# A scene whose script prints, and a world file that makes the engine report an error: neither
	# reaches the pipes.
	var script := FileAccess.open(WORK + "/noisy.gd", FileAccess.WRITE)
	script.store_string("extends Node2D\nfunc _init() -> void:\n\tprint(\"stray line\")\n\tprinterr(\"stray error\")\n\tpush_error(\"stray push\")\n")
	script.close()
	var noisy := FileAccess.open(WORK + "/noisy.tscn", FileAccess.WRITE)
	noisy.store_string("[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=\"%s/noisy.gd\" id=\"1\"]\n\n[node name=\"Noisy\" type=\"Node2D\"]\nscript = ExtResource(\"1\")\n" % WORK)
	noisy.close()
	var placed: Dictionary = await child.tool(tree, "mds_room_place", {"world": WORLD, "room": "R1", "kind": "scene", "template": WORK + "/noisy.tscn", "pos": {"x": 10, "y": 10}})
	check(not placed.has("_error"), "a scene that prints: %s" % placed.get("_error", ""))
	var bad_world := FileAccess.open(WORK + "/bad.mdsworld.json", FileAccess.WRITE)
	bad_world.store_string("{not json")
	bad_world.close()
	await child.tool(tree, "mds_world_get", {"world": WORK + "/bad.mdsworld.json"})
	await child.tool(tree, "mds_room_items", {"world": WORLD, "room": "R1"})
	var after_noise: Dictionary = await child.request(tree, {"jsonrpc": "2.0", "id": 7, "method": "ping"})
	check(after_noise.get("id") == 7, "still answering")
	check(child.not_json.is_empty(), "no stray print on stdout: %s" % [child.not_json])
	check(child.stderr_text.is_empty(), "nothing on stderr: %s" % child.stderr_text.left(300))

	# Large messages.
	var pad := "é".repeat(150000)
	var large: Dictionary = await child.request(tree, {"jsonrpc": "2.0", "id": 5, "method": "ping", "params": {"pad": pad}})
	check(large.get("id") == 5, "300 KB in")
	var out: Dictionary = await child.tool(tree, "mds_export", {"world": WORLD, "format": "json"})
	check(out.get("text", "").length() > 100, "a long answer out")
	var last: Dictionary = await child.request(tree, {"jsonrpc": "2.0", "id": 6, "method": "ping"})
	check(last.get("id") == 6, "still answering")
	check(child.not_json.is_empty(), "stdout held only JSON: %s" % [child.not_json])

	# Closing stdin ends it, quickly.
	var started := Time.get_ticks_msec()
	check(await child.close_and_wait(tree), "exits when stdin closes")
	print("  exited %d ms after stdin closed" % (Time.get_ticks_msec() - started))
	check(not FileAccess.file_exists(MDSMcpGuard.DATA_DIR + "/lock"), "no lock left")

	# The tier comes from the command line.
	child = Child.new()
	child.start(["--tier=read"])
	var refused: Dictionary = await child.tool(tree, "mds_area_set", {"world": WORLD, "area": "X"})
	check(refused.has("_error") and refused._error.code == "tier_too_low", "--tier=read")
	var status: Dictionary = await child.tool(tree, "mds_status")
	check(status.get("tier") == "read" and status.get("mode") == "headless", "the status says so")
	await child.close_and_wait(tree)
	Case.clean_folder(WORK)
