extends "res://tests/test_case.gd"
## Base of the tests that call the MCP tools: a server of its own on a data folder of its own,
## and a world under tests/tmp.

const WORK := TMP + "/mcp"
const WORLD := WORK + "/w.mdsworld.json"

var server: MDSMcpProtocol

func start_server(tier := MDSMcpGuard.Tier.FULL, host: MDSMcpHost = null) -> void:
	clean_folder(WORK)
	DirAccess.make_dir_recursive_absolute(WORK)
	server = MDSMcpProtocol.new(host if host else MDSMcpHost.new(), tier, WORK + "/data")

static func clean_folder(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for d in DirAccess.get_directories_at(folder):
		clean_folder(folder.path_join(d))
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(f))
	DirAccess.remove_absolute(folder)

## Calls a tool; returns its result, or the error under _error.
func call_mcp(tool_name: String, args: Dictionary = {}) -> Dictionary:
	var answer: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": tool_name, "arguments": MDSMcpSchema.clean(args)}})
	if answer.has("error"):
		return {"_error": answer.error}
	if answer.result.isError:
		return {"_error": answer.result.structuredContent}
	return answer.result.structuredContent

## Calls a tool that should work; a check fails with its error otherwise.
func ok(tool_name: String, args: Dictionary = {}) -> Dictionary:
	var r: Dictionary = await call_mcp(tool_name, args)
	check(not r.has("_error"), "%s: %s" % [tool_name, r.get("_error", "")])
	return r

## Calls a tool that should fail with [param code].
func refused(tool_name: String, args: Dictionary, code: String) -> void:
	var r: Dictionary = await call_mcp(tool_name, args)
	check(r.has("_error") and r._error.get("code") == code, "%s should refuse with %s: %s" % [tool_name, code, r])

## A small world: an area, two rooms joined by a door.
func make_world() -> void:
	await ok("mds_world_create", {"path": WORLD, "name": "W", "settings": {"scene_folder": WORK + "/rooms", "room_tileset": WORK + "/tiles/t.tres"}})
	await ok("mds_tileset_create", {"path": WORK + "/tiles/t.tres"})
	await ok("mds_area_set", {"world": WORLD, "area": "A", "title": "Area", "color": "#336699"})
	await ok("mds_room_add", {"world": WORLD, "id": "R1", "rect": {"x": 0, "y": 0, "w": 1152, "h": 648}, "area": "A"})
	await ok("mds_room_add", {"world": WORLD, "id": "R2", "rect": {"x": 1152, "y": 0, "w": 1152, "h": 648}, "area": "A"})
	await ok("mds_gate_add", {"world": WORLD, "room": "R1", "pos": {"x": 1152, "y": 500}, "side": "right", "name": "right1"})
	await ok("mds_gate_add", {"world": WORLD, "room": "R2", "pos": {"x": 1152, "y": 500}, "side": "left", "name": "left1"})
	await ok("mds_gate_connect", {"world": WORLD, "a": "R1", "a_gate": "right1", "b": "R2", "b_gate": "left1"})
	await ok("mds_world_update", {"world": WORLD, "start_room": "R1"})

func end_server() -> void:
	server = null
	clean_folder(WORK)
